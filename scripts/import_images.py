#!/usr/bin/env python3
"""
Confluence 离线部署 - Docker 镜像导入工具 (Python版本)

功能：
- 从指定目录导入所有 tar 格式的 Docker 镜像
- 支持多个镜像并发导入
- 支持镜像清单文件验证
- 自动清理悬空镜像
- 显示详细的导入进度和结果
"""

import os
import sys
import json
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

class DockerImageImporter:
    """Docker 镜像导入器"""
    
    def __init__(self, images_dir: str = "offline_images", max_workers: int = 2):
        self.images_dir = Path(images_dir)
        self.max_workers = max_workers
        self.imported_images = []
        self.failed_imports = []
        self.skipped_images = []
        
        # 线程锁用于同步输出
        self.print_lock = threading.Lock()
    
    def check_docker(self) -> bool:
        """检查 Docker 是否可用"""
        try:
            result = subprocess.run(['docker', '--version'], 
                                  capture_output=True, text=True, check=True)
            Logger.info(f"Docker 版本: {result.stdout.strip()}")
            
            # 检查 Docker 守护进程是否运行
            result = subprocess.run(['docker', 'info'], 
                                  capture_output=True, text=True, check=True)
            Logger.info("Docker 守护进程运行正常")
            return True
        except subprocess.CalledProcessError as e:
            if "Cannot connect to the Docker daemon" in e.stderr:
                Logger.error("Docker 守护进程未运行，请启动 Docker 服务")
            else:
                Logger.error(f"Docker 检查失败: {e.stderr}")
            return False
        except FileNotFoundError:
            Logger.error("Docker 未安装")
            return False
    
    def find_image_files(self) -> List[Path]:
        """查找所有镜像文件"""
        if not self.images_dir.exists():
            Logger.error(f"镜像目录不存在: {self.images_dir}")
            return []
        
        # 查找所有 .tar 文件
        tar_files = list(self.images_dir.glob("*.tar"))
        
        if not tar_files:
            Logger.warn(f"在目录 {self.images_dir} 中未找到 .tar 镜像文件")
            return []
        
        Logger.info(f"找到 {len(tar_files)} 个镜像文件")
        return tar_files
    
    def load_manifest(self) -> Optional[Dict]:
        """加载镜像清单文件"""
        manifest_file = self.images_dir / "images_manifest.json"
        
        if not manifest_file.exists():
            Logger.warn("未找到镜像清单文件，将导入所有找到的 tar 文件")
            return None
        
        try:
            with open(manifest_file, 'r', encoding='utf-8') as f:
                manifest = json.load(f)
            
            Logger.info(f"加载镜像清单: {len(manifest.get('images', []))} 个镜像")
            return manifest
        except Exception as e:
            Logger.error(f"读取镜像清单失败: {e}")
            return None
    
    def get_image_name_from_tar(self, tar_file: Path) -> Optional[str]:
        """从 tar 文件获取镜像名称"""
        try:
            # 尝试从文件名推断镜像名
            filename = tar_file.stem  # 去掉 .tar 扩展名
            
            # 将文件名转换回镜像名格式
            # 例如: haxqer_confluence-9.2.1.tar -> haxqer/confluence:9.2.1
            if '_' in filename and '-' in filename:
                parts = filename.split('_', 1)
                if len(parts) == 2:
                    namespace = parts[0]
                    repo_tag = parts[1].replace('-', ':', 1)
                    return f"{namespace}/{repo_tag}"
            
            # 如果无法从文件名推断，尝试检查 tar 文件内容
            result = subprocess.run(
                ['docker', 'load', '--input', str(tar_file), '--quiet'],
                capture_output=True, text=True
            )
            
            if result.returncode == 0 and result.stderr:
                # Docker load 输出格式: "Loaded image: image_name:tag"
                for line in result.stderr.split('\n'):
                    if line.startswith('Loaded image:'):
                        return line.split(':', 1)[1].strip()
            
            return None
        except Exception as e:
            Logger.debug(f"获取镜像名失败 {tar_file}: {e}")
            return None
    
    def image_exists_locally(self, image_name: str) -> bool:
        """检查镜像是否已存在本地"""
        try:
            subprocess.run(['docker', 'image', 'inspect', image_name], 
                         capture_output=True, check=True)
            return True
        except subprocess.CalledProcessError:
            return False
    
    def import_single_image(self, tar_file: Path, force: bool = False) -> Tuple[str, bool, str]:
        """导入单个镜像文件"""
        try:
            with self.print_lock:
                Logger.info(f"正在导入: {tar_file.name}")
            
            # 检查文件是否存在
            if not tar_file.exists():
                error_msg = f"文件不存在: {tar_file}"
                with self.print_lock:
                    Logger.error(error_msg)
                return str(tar_file), False, error_msg
            
            # 检查文件大小
            file_size = tar_file.stat().st_size
            if file_size == 0:
                error_msg = f"文件为空: {tar_file}"
                with self.print_lock:
                    Logger.error(error_msg)
                return str(tar_file), False, error_msg
            
            # 导入镜像
            start_time = time.time()
            result = subprocess.run(
                ['docker', 'load', '--input', str(tar_file)],
                capture_output=True, text=True
            )
            end_time = time.time()
            
            if result.returncode == 0:
                # 解析导入的镜像名
                imported_image = "unknown"
                if result.stderr:
                    for line in result.stderr.split('\n'):
                        if line.startswith('Loaded image:'):
                            imported_image = line.split(':', 1)[1].strip()
                            break
                
                duration = end_time - start_time
                size_mb = file_size / (1024 * 1024)
                
                with self.print_lock:
                    Logger.success(f"✓ {imported_image} ({size_mb:.1f} MB, {duration:.1f}s)")
                
                return imported_image, True, ""
            else:
                error_msg = f"导入失败: {result.stderr}"
                with self.print_lock:
                    Logger.error(f"✗ {tar_file.name}: {error_msg}")
                return str(tar_file), False, error_msg
                
        except Exception as e:
            error_msg = f"导入异常: {e}"
            with self.print_lock:
                Logger.error(f"✗ {tar_file.name}: {error_msg}")
            return str(tar_file), False, error_msg
    
    def import_images(self, tar_files: List[Path], force: bool = False) -> bool:
        """并发导入多个镜像"""
        if not tar_files:
            Logger.error("没有要导入的镜像文件")
            return False
        
        Logger.info(f"开始导入 {len(tar_files)} 个镜像文件...")
        Logger.info(f"镜像目录: {self.images_dir.absolute()}")
        Logger.info(f"并发数: {self.max_workers}")
        
        start_time = time.time()
        
        # 使用线程池并发导入
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            # 提交所有导入任务
            future_to_file = {
                executor.submit(self.import_single_image, tar_file, force): tar_file 
                for tar_file in tar_files
            }
            
            # 等待任务完成
            for future in as_completed(future_to_file):
                tar_file = future_to_file[future]
                try:
                    image_name, success, error_msg = future.result()
                    if success:
                        self.imported_images.append(image_name)
                    else:
                        self.failed_imports.append({
                            'file': str(tar_file),
                            'error': error_msg
                        })
                except Exception as e:
                    Logger.error(f"处理文件 {tar_file} 时发生异常: {e}")
                    self.failed_imports.append({
                        'file': str(tar_file),
                        'error': str(e)
                    })
        
        end_time = time.time()
        duration = end_time - start_time
        
        # 显示导入结果
        self.show_import_summary(duration)
        
        return len(self.failed_imports) == 0
    
    def show_import_summary(self, duration: float):
        """显示导入摘要"""
        total = len(self.imported_images) + len(self.failed_imports) + len(self.skipped_images)
        
        print(f"\n{Colors.CYAN}{'='*60}{Colors.NC}")
        print(f"{Colors.WHITE}镜像导入完成摘要{Colors.NC}")
        print(f"{Colors.CYAN}{'='*60}{Colors.NC}")
        
        print(f"总文件数: {total}")
        print(f"{Colors.GREEN}成功导入: {len(self.imported_images)}{Colors.NC}")
        print(f"{Colors.YELLOW}跳过导入: {len(self.skipped_images)}{Colors.NC}")
        print(f"{Colors.RED}导入失败: {len(self.failed_imports)}{Colors.NC}")
        print(f"耗时: {duration:.1f} 秒")
        
        if self.imported_images:
            print(f"\n{Colors.GREEN}成功导入的镜像:{Colors.NC}")
            for image in self.imported_images:
                print(f"  ✓ {image}")
        
        if self.skipped_images:
            print(f"\n{Colors.YELLOW}跳过的镜像:{Colors.NC}")
            for image in self.skipped_images:
                print(f"  - {image}")
        
        if self.failed_imports:
            print(f"\n{Colors.RED}导入失败的文件:{Colors.NC}")
            for failed in self.failed_imports:
                print(f"  ✗ {failed['file']}: {failed['error']}")
    
    def list_imported_images(self):
        """列出已导入的镜像"""
        try:
            result = subprocess.run(['docker', 'images', '--format', 'table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}'],
                                  capture_output=True, text=True, check=True)
            
            print(f"\n{Colors.CYAN}本地 Docker 镜像列表:{Colors.NC}")
            print(result.stdout)
            
        except subprocess.CalledProcessError as e:
            Logger.error(f"获取镜像列表失败: {e}")
    
    def cleanup_dangling_images(self):
        """清理悬空镜像"""
        try:
            Logger.info("正在清理悬空镜像...")
            
            # 查找悬空镜像
            result = subprocess.run(['docker', 'images', '-f', 'dangling=true', '-q'],
                                  capture_output=True, text=True, check=True)
            
            dangling_images = result.stdout.strip().split('\n')
            dangling_images = [img for img in dangling_images if img]
            
            if not dangling_images:
                Logger.info("没有发现悬空镜像")
                return
            
            Logger.info(f"发现 {len(dangling_images)} 个悬空镜像，正在清理...")
            
            # 删除悬空镜像
            result = subprocess.run(['docker', 'rmi'] + dangling_images,
                                  capture_output=True, text=True)
            
            if result.returncode == 0:
                Logger.success(f"成功清理 {len(dangling_images)} 个悬空镜像")
            else:
                Logger.warn(f"清理悬空镜像时出现警告: {result.stderr}")
                
        except subprocess.CalledProcessError as e:
            Logger.error(f"清理悬空镜像失败: {e}")
        except Exception as e:
            Logger.error(f"清理悬空镜像时发生异常: {e}")

def main():
    parser = argparse.ArgumentParser(
        description="Confluence 离线部署 - Docker 镜像导入工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  # 导入默认目录中的所有镜像
  python3 import_images.py
  
  # 指定镜像目录
  python3 import_images.py --dir /path/to/images
  
  # 强制重新导入已存在的镜像
  python3 import_images.py --force
  
  # 设置并发数
  python3 import_images.py --workers 4
  
  # 导入后清理悬空镜像
  python3 import_images.py --cleanup
  
  # 导入特定的镜像文件
  python3 import_images.py --files image1.tar image2.tar
        """
    )
    
    parser.add_argument('--dir', '-d', default='offline_images',
                       help='镜像文件目录 (默认: offline_images)')
    parser.add_argument('--files', '-f', nargs='+',
                       help='指定要导入的镜像文件')
    parser.add_argument('--workers', '-w', type=int, default=2,
                       help='并发导入数 (默认: 2)')
    parser.add_argument('--force', action='store_true',
                       help='强制重新导入已存在的镜像')
    parser.add_argument('--cleanup', action='store_true',
                       help='导入后清理悬空镜像')
    parser.add_argument('--list', '-l', action='store_true',
                       help='导入后列出所有本地镜像')
    parser.add_argument('--no-verify', action='store_true',
                       help='跳过镜像清单验证')
    
    args = parser.parse_args()
    
    # 创建导入器
    importer = DockerImageImporter(args.dir, args.workers)
    
    # 检查 Docker
    if not importer.check_docker():
        sys.exit(1)
    
    # 获取要导入的文件列表
    tar_files = []
    
    if args.files:
        # 使用指定的文件
        for file_path in args.files:
            tar_file = Path(file_path)
            if not tar_file.is_absolute():
                tar_file = importer.images_dir / tar_file
            
            if tar_file.exists():
                tar_files.append(tar_file)
            else:
                Logger.error(f"文件不存在: {tar_file}")
        
        Logger.info(f"指定导入 {len(tar_files)} 个文件")
    else:
        # 查找目录中的所有文件
        tar_files = importer.find_image_files()
    
    if not tar_files:
        Logger.error("没有找到要导入的镜像文件")
        sys.exit(1)
    
    # 加载并验证清单文件
    if not args.no_verify:
        manifest = importer.load_manifest()
        if manifest:
            manifest_files = {img['file'] for img in manifest.get('images', [])}
            found_files = {f.name for f in tar_files}
            
            missing_files = manifest_files - found_files
            extra_files = found_files - manifest_files
            
            if missing_files:
                Logger.warn(f"清单中的文件未找到: {', '.join(missing_files)}")
            
            if extra_files:
                Logger.warn(f"发现额外的文件: {', '.join(extra_files)}")
    
    # 显示要导入的文件
    print(f"\n{Colors.CYAN}准备导入的镜像文件:{Colors.NC}")
    for i, tar_file in enumerate(tar_files, 1):
        size_mb = tar_file.stat().st_size / (1024 * 1024)
        print(f"  {i}. {tar_file.name} ({size_mb:.1f} MB)")
    
    # 开始导入
    success = importer.import_images(tar_files, args.force)
    
    # 清理悬空镜像
    if args.cleanup:
        importer.cleanup_dangling_images()
    
    # 列出镜像
    if args.list:
        importer.list_imported_images()
    
    # 退出码
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()