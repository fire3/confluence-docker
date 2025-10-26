#!/bin/bash

# Confluence 离线部署 - 镜像导入脚本
# 用于在离线环境中导入 Docker 镜像

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

# 检查镜像目录
check_images_dir() {
    local images_dir="$1"
    
    if [ ! -d "$images_dir" ]; then
        log_error "镜像目录不存在: $images_dir"
        exit 1
    fi
    
    # 检查是否有 tar 文件
    local tar_count=$(find "$images_dir" -name "*.tar" | wc -l)
    if [ $tar_count -eq 0 ]; then
        log_error "在目录 $images_dir 中未找到任何 .tar 镜像文件"
        exit 1
    fi
    
    log_success "找到 $tar_count 个镜像文件"
}

# 导入单个镜像
import_image() {
    local tar_file="$1"
    local filename=$(basename "$tar_file")
    
    log_info "正在导入镜像: $filename"
    
    # 显示文件大小
    local size=$(du -h "$tar_file" | cut -f1)
    log_info "文件大小: $size"
    
    # 导入镜像
    if docker load -i "$tar_file"; then
        log_success "镜像导入成功: $filename"
        return 0
    else
        log_error "镜像导入失败: $filename"
        return 1
    fi
}

# 验证镜像导入
verify_images() {
    log_info "验证导入的镜像..."
    
    # 预期的镜像列表
    local expected_images=(
        "haxqer/confluence:9.2.1"
        "haxqer/confluence:8.5.23"
        "mysql:8.0"
    )
    
    local missing_images=()
    
    for image in "${expected_images[@]}"; do
        if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^$image$"; then
            log_success "镜像已存在: $image"
        else
            log_warning "镜像缺失: $image"
            missing_images+=("$image")
        fi
    done
    
    if [ ${#missing_images[@]} -eq 0 ]; then
        log_success "所有预期镜像都已成功导入"
        return 0
    else
        log_warning "以下镜像缺失:"
        for image in "${missing_images[@]}"; do
            echo "  - $image"
        done
        return 1
    fi
}

# 显示导入的镜像列表
show_imported_images() {
    log_info "当前系统中的相关镜像:"
    echo
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | head -1
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep -E "(confluence|mysql)" || true
    echo
}

# 清理悬空镜像
cleanup_dangling_images() {
    log_info "清理悬空镜像..."
    
    local dangling_images=$(docker images -f "dangling=true" -q)
    if [ -n "$dangling_images" ]; then
        docker rmi $dangling_images
        log_success "已清理悬空镜像"
    else
        log_info "没有悬空镜像需要清理"
    fi
}

# 主函数
main() {
    log_info "开始导入 Confluence 部署所需的 Docker 镜像"
    
    # 检查 Docker 环境
    check_docker
    
    # 设置镜像目录
    local images_dir="${1:-./docker-images}"
    
    # 检查镜像目录
    check_images_dir "$images_dir"
    
    # 读取镜像清单（如果存在）
    local manifest_file="$images_dir/images-manifest.txt"
    if [ -f "$manifest_file" ]; then
        log_info "找到镜像清单文件，显示内容:"
        cat "$manifest_file"
        echo
    fi
    
    # 获取所有 tar 文件
    local tar_files=($(find "$images_dir" -name "*.tar" | sort))
    
    log_info "准备导入以下镜像文件:"
    for tar_file in "${tar_files[@]}"; do
        echo "  - $(basename "$tar_file")"
    done
    echo
    
    # 导入镜像
    local success_count=0
    local total_count=${#tar_files[@]}
    
    for tar_file in "${tar_files[@]}"; do
        if import_image "$tar_file"; then
            ((success_count++))
        fi
        echo
    done
    
    # 显示导入结果
    log_info "导入完成统计:"
    log_info "成功: $success_count/$total_count"
    
    if [ $success_count -eq $total_count ]; then
        log_success "所有镜像导入完成！"
    else
        log_warning "部分镜像导入失败"
    fi
    
    # 验证镜像
    echo
    verify_images
    
    # 显示导入的镜像
    echo
    show_imported_images
    
    # 清理悬空镜像
    echo
    cleanup_dangling_images
    
    if [ $success_count -eq $total_count ]; then
        log_success "镜像导入流程完成，可以继续进行环境配置"
    else
        exit 1
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
Confluence 离线部署 - 镜像导入脚本

用法: $0 [镜像目录]

参数:
  镜像目录    可选，指定包含 .tar 镜像文件的目录，默认为 ./docker-images

示例:
  $0                    # 从默认目录 ./docker-images 导入
  $0 /tmp/images        # 从指定目录 /tmp/images 导入

说明:
  此脚本会导入指定目录中的所有 .tar 格式的 Docker 镜像文件。
  导入完成后会验证镜像是否正确加载，并清理悬空镜像。

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