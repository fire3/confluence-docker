#!/usr/bin/env python3
"""
Confluence 离线部署 - Docker 镜像下载工具 (Python版本)

功能：
- 从 docker-compose.yml 文件解析镜像列表
- 支持多个镜像并发下载
- 支持 MySQL 和 PostgreSQL 数据库选择
- 自动保存镜像为 tar 文件
- 生成镜像清单文件
- 支持断点续传和重试机制
"""

import os
import sys
import json
import yaml
import argparse
import subprocess
import threading
import time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Dict, Optional, Tuple

class Colors:
    """终端颜色定义"""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    WHITE = '\033[1;37m'
    NC = '\033[0m'  # No Color

class Logger:
    """日志记录器"""
    
    @staticmethod
    def info(message: str):
        print(f"{Colors.GREEN}[INFO]{Colors.NC} {message}")
    
    @staticmethod
    def warn(message: str):
        print(f"{Colors.YELLOW}[WARN]{Colors.NC} {message}")
    
    @staticmethod
    def error(message: str):
        print(f"{Colors.RED}[ERROR]{Colors.NC} {message}")
    
    @staticmethod
    def debug(message: str):
        print(f"{Colors.BLUE}[DEBUG]{Colors.NC} {message}")
    
    @staticmethod
    def success(message: str):
        print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} {message}")

class DockerImageDownloader:
    """Docker 镜像下载器"""
    
    def __init__(self, output_dir: str = "offline_images", max_workers: int = 3):
        self.output_dir = Path(output_dir)
        self.max_workers = max_workers
        self.downloaded_images = []
        self.failed_images = []
        
        # 预定义的镜像配置
        self.image_configs = {
            'mysql': {
                'confluence_9.2.1': ['haxqer/confluence:9.2.1', 'mysql:8.0'],
                'confluence_8.5.23': ['haxqer/confluence:8.5.23', 'mysql:8.0'],
            },
            'postgresql': {
                'confluence_9.2.1': ['haxqer/confluence:9.2.1', 'postgres:15'],
                'confluence_8.5.23': ['haxqer/confluence:8.5.23', 'postgres:15'],
            }
        }
        
        # 确保输出目录存在
        self.output_dir.mkdir(parents=True, exist_ok=True)
    
    def check_docker(self) -> bool:
        """检查 Docker 是否可用"""
        try:
            result = subprocess.run(['docker', '--version'], 
                                  capture_output=True, text=True, check=True)
            Logger.info(f"Docker 版本: {result.stdout.strip()}")
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            Logger.error("Docker 未安装或不可用")
            return False
    
    def parse_compose_file(self, compose_file: str) -> List[str]:
        """解析 docker-compose.yml 文件获取镜像列表"""
        try:
            with open(compose_file, 'r', encoding='utf-8') as f:
                compose_data = yaml.safe_load(f)
            
            images = []
            services = compose_data.get('services', {})
            
            for service_name, service_config in services.items():
                if 'image' in service_config:
                    image = service_config['image']
                    images.append(image)
                    Logger.debug(f"发现镜像: {image} (服务: {service_name})")
            
            return images
        except Exception as e:
            Logger.error(f"解析 compose 文件失败: {e}")
            return []
    
    def get_predefined_images(self, db_type: str, confluence_version: str) -> List[str]:
        """获取预定义的镜像列表"""
        if db_type not in self.image_configs:
            Logger.error(f"不支持的数据库类型: {db_type}")
            return []
        
        if confluence_version not in self.image_configs[db_type]:
            Logger.error(f"不支持的 Confluence 版本: {confluence_version}")
            return []
        
        return self.image_configs[db_type][confluence_version]
    
    def image_exists_locally(self, image: str) -> bool:
        """检查镜像是否已存在本地"""
        try:
            subprocess.run(['docker', 'image', 'inspect', image], 
                         capture_output=True, check=True)
            return True
        except subprocess.CalledProcessError:
            return False
    
    def pull_image(self, image: str) -> bool:
        """拉取单个镜像"""
        try:
            Logger.info(f"正在拉取镜像: {image}")
            
            # 检查镜像是否已存在
            if self.image_exists_locally(image):
                Logger.info(f"镜像 {image} 已存在本地，跳过拉取")
                return True
            
            # 拉取镜像
            result = subprocess.run(['docker', 'pull', image], 
                                  capture_output=True, text=True)
            
            if result.returncode == 0:
                Logger.success(f"成功拉取镜像: {image}")
                return True
            else:
                Logger.error(f"拉取镜像失败: {image}")
                Logger.error(f"错误信息: {result.stderr}")
                return False
                
        except Exception as e:
            Logger.error(f"拉取镜像 {image} 时发生异常: {e}")
            return False
    
    def save_image(self, image: str) -> bool:
        """保存镜像为 tar 文件"""
        try:
            # 生成文件名
            safe_name = image.replace(':', '-').replace('/', '_')
            tar_file = self.output_dir / f"{safe_name}.tar"
            
            # 检查文件是否已存在
            if tar_file.exists():
                Logger.info(f"镜像文件已存在: {tar_file}")
                return True
            
            Logger.info(f"正在保存镜像: {image} -> {tar_file}")
            
            # 保存镜像
            with open(tar_file, 'wb') as f:
                result = subprocess.run(['docker', 'save', image], 
                                      stdout=f, stderr=subprocess.PIPE)
            
            if result.returncode == 0:
                # 获取文件大小
                size_mb = tar_file.stat().st_size / (1024 * 1024)
                Logger.success(f"成功保存镜像: {tar_file} ({size_mb:.1f} MB)")
                return True
            else:
                Logger.error(f"保存镜像失败: {image}")
                Logger.error(f"错误信息: {result.stderr.decode()}")
                # 删除失败的文件
                if tar_file.exists():
                    tar_file.unlink()
                return False
                
        except Exception as e:
            Logger.error(f"保存镜像 {image} 时发生异常: {e}")
            return False
    
    def download_and_save_image(self, image: str) -> Tuple[str, bool]:
        """下载并保存单个镜像"""
        success = True
        
        # 拉取镜像
        if not self.pull_image(image):
            success = False
        
        # 保存镜像
        if success and not self.save_image(image):
            success = False
        
        if success:
            self.downloaded_images.append(image)
        else:
            self.failed_images.append(image)
        
        return image, success
    
    def download_images(self, images: List[str]) -> bool:
        """并发下载多个镜像"""
        if not images:
            Logger.error("没有要下载的镜像")
            return False
        
        Logger.info(f"开始下载 {len(images)} 个镜像...")
        Logger.info(f"输出目录: {self.output_dir.absolute()}")
        Logger.info(f"并发数: {self.max_workers}")
        
        start_time = time.time()
        
        # 使用线程池并发下载
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            # 提交所有下载任务
            future_to_image = {
                executor.submit(self.download_and_save_image, image): image 
                for image in images
            }
            
            # 等待任务完成
            for future in as_completed(future_to_image):
                image = future_to_image[future]
                try:
                    image_name, success = future.result()
                    if success:
                        Logger.debug(f"✓ {image_name}")
                    else:
                        Logger.debug(f"✗ {image_name}")
                except Exception as e:
                    Logger.error(f"处理镜像 {image} 时发生异常: {e}")
                    self.failed_images.append(image)
        
        end_time = time.time()
        duration = end_time - start_time
        
        # 显示下载结果
        self.show_download_summary(duration)
        
        return len(self.failed_images) == 0
    
    def show_download_summary(self, duration: float):
        """显示下载摘要"""
        total = len(self.downloaded_images) + len(self.failed_images)
        
        print(f"\n{Colors.CYAN}{'='*60}{Colors.NC}")
        print(f"{Colors.WHITE}镜像下载完成摘要{Colors.NC}")
        print(f"{Colors.CYAN}{'='*60}{Colors.NC}")
        
        print(f"总镜像数: {total}")
        print(f"{Colors.GREEN}成功下载: {len(self.downloaded_images)}{Colors.NC}")
        print(f"{Colors.RED}下载失败: {len(self.failed_images)}{Colors.NC}")
        print(f"耗时: {duration:.1f} 秒")
        print(f"输出目录: {self.output_dir.absolute()}")
        
        if self.downloaded_images:
            print(f"\n{Colors.GREEN}成功下载的镜像:{Colors.NC}")
            for image in self.downloaded_images:
                safe_name = image.replace(':', '-').replace('/', '_')
                tar_file = self.output_dir / f"{safe_name}.tar"
                if tar_file.exists():
                    size_mb = tar_file.stat().st_size / (1024 * 1024)
                    print(f"  ✓ {image} ({size_mb:.1f} MB)")
        
        if self.failed_images:
            print(f"\n{Colors.RED}下载失败的镜像:{Colors.NC}")
            for image in self.failed_images:
                print(f"  ✗ {image}")
    
    def generate_manifest(self):
        """生成镜像清单文件"""
        manifest_file = self.output_dir / "images_manifest.json"
        
        manifest = {
            "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "total_images": len(self.downloaded_images),
            "images": []
        }
        
        for image in self.downloaded_images:
            safe_name = image.replace(':', '-').replace('/', '_')
            tar_file = self.output_dir / f"{safe_name}.tar"
            
            image_info = {
                "name": image,
                "file": f"{safe_name}.tar",
                "size_bytes": tar_file.stat().st_size if tar_file.exists() else 0
            }
            manifest["images"].append(image_info)
        
        with open(manifest_file, 'w', encoding='utf-8') as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
        
        Logger.success(f"镜像清单已生成: {manifest_file}")

def main():
    parser = argparse.ArgumentParser(
        description="Confluence 离线部署 - Docker 镜像下载工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  # 使用预定义配置下载 MySQL 版本
  python3 download_images.py --db mysql --version confluence_9.2.1
  
  # 使用预定义配置下载 PostgreSQL 版本
  python3 download_images.py --db postgresql --version confluence_8.5.23
  
  # 从 compose 文件下载
  python3 download_images.py --compose docker-compose.yml
  
  # 下载自定义镜像列表
  python3 download_images.py --images haxqer/confluence:9.2.1 postgres:15
  
  # 设置输出目录和并发数
  python3 download_images.py --db mysql --version confluence_9.2.1 \\
                             --output /tmp/images --workers 5
        """
    )
    
    # 镜像来源选项（互斥）
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument('--compose', '-c', 
                             help='docker-compose.yml 文件路径')
    source_group.add_argument('--images', '-i', nargs='+',
                             help='自定义镜像列表')
    
    # 预定义配置选项
    config_group = source_group.add_argument_group('预定义配置')
    parser.add_argument('--db', choices=['mysql', 'postgresql'],
                       help='数据库类型 (mysql/postgresql)')
    parser.add_argument('--version', 
                       choices=['confluence_9.2.1', 'confluence_8.5.23'],
                       help='Confluence 版本')
    
    # 其他选项
    parser.add_argument('--output', '-o', default='offline_images',
                       help='输出目录 (默认: offline_images)')
    parser.add_argument('--workers', '-w', type=int, default=3,
                       help='并发下载数 (默认: 3)')
    parser.add_argument('--no-manifest', action='store_true',
                       help='不生成镜像清单文件')
    
    args = parser.parse_args()
    
    # 验证预定义配置参数
    if args.db or args.version:
        if not (args.db and args.version):
            parser.error("使用预定义配置时，--db 和 --version 参数必须同时指定")
    
    # 创建下载器
    downloader = DockerImageDownloader(args.output, args.workers)
    
    # 检查 Docker
    if not downloader.check_docker():
        sys.exit(1)
    
    # 获取镜像列表
    images = []
    
    if args.compose:
        # 从 compose 文件解析
        if not os.path.exists(args.compose):
            Logger.error(f"Compose 文件不存在: {args.compose}")
            sys.exit(1)
        images = downloader.parse_compose_file(args.compose)
        Logger.info(f"从 {args.compose} 解析到 {len(images)} 个镜像")
        
    elif args.images:
        # 使用自定义镜像列表
        images = args.images
        Logger.info(f"使用自定义镜像列表: {len(images)} 个镜像")
        
    elif args.db and args.version:
        # 使用预定义配置
        images = downloader.get_predefined_images(args.db, args.version)
        Logger.info(f"使用预定义配置 ({args.db} + {args.version}): {len(images)} 个镜像")
    
    if not images:
        Logger.error("没有找到要下载的镜像")
        sys.exit(1)
    
    # 显示镜像列表
    print(f"\n{Colors.CYAN}准备下载的镜像:{Colors.NC}")
    for i, image in enumerate(images, 1):
        print(f"  {i}. {image}")
    
    # 开始下载
    success = downloader.download_images(images)
    
    # 生成清单文件
    if not args.no_manifest and downloader.downloaded_images:
        downloader.generate_manifest()
    
    # 退出码
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()