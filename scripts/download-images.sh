#!/bin/bash

# Confluence 离线部署 - 镜像下载脚本
# 用于在有网络环境中下载所需的 Docker 镜像

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker 服务未运行，请启动 Docker 服务"
        exit 1
    fi
    
    log_success "Docker 环境检查通过"
}

# 创建输出目录
create_output_dir() {
    local output_dir="$1"
    if [ ! -d "$output_dir" ]; then
        mkdir -p "$output_dir"
        log_info "创建输出目录: $output_dir"
    fi
}

# 下载并保存镜像
download_and_save_image() {
    local image="$1"
    local output_dir="$2"
    local filename="$3"
    
    log_info "正在下载镜像: $image"
    
    # 拉取镜像
    if docker pull "$image"; then
        log_success "镜像下载成功: $image"
        
        # 保存镜像为 tar 文件
        log_info "正在保存镜像到文件: $filename"
        if docker save "$image" -o "$output_dir/$filename"; then
            log_success "镜像保存成功: $output_dir/$filename"
            
            # 显示文件大小
            local size=$(du -h "$output_dir/$filename" | cut -f1)
            log_info "文件大小: $size"
        else
            log_error "镜像保存失败: $filename"
            return 1
        fi
    else
        log_error "镜像下载失败: $image"
        return 1
    fi
}

# 主函数
main() {
    log_info "开始下载 Confluence 部署所需的 Docker 镜像"
    
    # 检查 Docker 环境
    check_docker
    
    # 设置输出目录
    local output_dir="${1:-./docker-images}"
    create_output_dir "$output_dir"
    
    # 定义需要下载的镜像列表
    declare -A images=(
        ["haxqer/confluence:9.2.1"]="confluence-9.2.1.tar"
        ["haxqer/confluence:8.5.23"]="confluence-8.5.23-lts.tar"
        ["mysql:8.0"]="mysql-8.0.tar"
    )
    
    log_info "将下载以下镜像:"
    for image in "${!images[@]}"; do
        echo "  - $image -> ${images[$image]}"
    done
    echo
    
    # 下载镜像
    local success_count=0
    local total_count=${#images[@]}
    
    for image in "${!images[@]}"; do
        if download_and_save_image "$image" "$output_dir" "${images[$image]}"; then
            ((success_count++))
        fi
        echo
    done
    
    # 显示下载结果
    log_info "下载完成统计:"
    log_info "成功: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        log_success "所有镜像下载完成！"
        log_info "镜像文件保存在: $output_dir"
        log_info "请将整个 $output_dir 目录复制到离线环境中"
    else
        log_warning "部分镜像下载失败，请检查网络连接后重试"
        exit 1
    fi
    
    # 生成镜像清单文件
    log_info "生成镜像清单文件..."
    cat > "$output_dir/images-manifest.txt" << EOF
# Confluence 离线部署镜像清单
# 生成时间: $(date)

EOF
    
    for image in "${!images[@]}"; do
        echo "$image -> ${images[$image]}" >> "$output_dir/images-manifest.txt"
    done
    
    log_success "镜像清单文件已生成: $output_dir/images-manifest.txt"
}

# 显示帮助信息
show_help() {
    cat << EOF
Confluence 离线部署 - 镜像下载脚本

用法: $0 [输出目录]

参数:
  输出目录    可选，指定镜像保存目录，默认为 ./docker-images

示例:
  $0                    # 下载到默认目录 ./docker-images
  $0 /tmp/images        # 下载到指定目录 /tmp/images

说明:
  此脚本会下载 Confluence 部署所需的所有 Docker 镜像，并保存为 tar 文件。
  下载完成后，请将整个输出目录复制到离线环境中使用。

EOF
}

# 处理命令行参数
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac