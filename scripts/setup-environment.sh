#!/bin/bash

# Confluence 离线部署 - 环境配置脚本
# 用于配置 Confluence 运行环境

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

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "此脚本需要 root 权限运行，请使用 sudo"
        exit 1
    fi
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! systemctl is-active --quiet docker; then
        log_info "启动 Docker 服务..."
        systemctl start docker
        systemctl enable docker
    fi
    
    log_success "Docker 服务运行正常"
}

# 检查 Docker Compose 是否安装
check_docker_compose() {
    if docker compose version &> /dev/null; then
        log_success "Docker Compose (v2) 可用"
        echo "docker compose" > /tmp/compose_cmd
    elif command -v docker-compose &> /dev/null; then
        log_success "Docker Compose (v1) 可用"
        echo "docker-compose" > /tmp/compose_cmd
    else
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
}

# 创建系统目录
create_system_directories() {
    log_info "创建系统目录..."
    
    # 创建 Confluence 安装目录
    local install_dir="/opt/confluence"
    if [ ! -d "$install_dir" ]; then
        mkdir -p "$install_dir"
        log_success "创建目录: $install_dir"
    else
        log_info "目录已存在: $install_dir"
    fi
    
    # 创建数据目录
    local data_dirs=(
        "/var/confluence"
        "/var/lib/mysql"
        "/var/lib/postgresql/data"
        "/var/log/confluence"
        "/var/log/postgresql"
    )
    
    for dir in "${data_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_success "创建目录: $dir"
        else
            log_info "目录已存在: $dir"
        fi
    done
    
    # 设置目录权限
    chmod 755 "$install_dir"
    chmod 777 "/var/confluence"  # Confluence 容器需要写权限
    chmod 777 "/var/lib/mysql"   # MySQL 容器需要写权限
    chmod 777 "/var/lib/postgresql"  # PostgreSQL 容器需要写权限
    chmod 755 "/var/log/confluence"
    chmod 755 "/var/log/postgresql"  # PostgreSQL 日志目录
    
    log_success "系统目录创建完成"
}

# 复制项目文件到系统目录
copy_project_files() {
    log_info "复制项目文件到系统目录..."
    
    local source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local target_dir="/opt/confluence"
    
    # 复制 docker-compose 文件
    cp "$source_dir/docker-compose.yml" "$target_dir/"
    log_success "复制: docker-compose.yml"
    
    # 复制 LTS 版本配置（如果存在）
    if [ -d "$source_dir/confluence_lts" ]; then
        cp -r "$source_dir/confluence_lts" "$target_dir/"
        log_success "复制: confluence_lts/"
    fi
    
    # 复制 PostgreSQL 版本配置（如果存在）
    if [ -d "$source_dir/confluence_postgresql" ]; then
        cp -r "$source_dir/confluence_postgresql" "$target_dir/"
        log_success "复制: confluence_postgresql/"
    fi
    
    # 复制 PostgreSQL 主配置文件（如果存在）
    if [ -f "$source_dir/docker-compose-postgresql.yml" ]; then
        cp "$source_dir/docker-compose-postgresql.yml" "$target_dir/"
        log_success "复制: docker-compose-postgresql.yml"
    fi
    
    # 复制脚本目录
    if [ -d "$source_dir/scripts" ]; then
        cp -r "$source_dir/scripts" "$target_dir/"
        chmod +x "$target_dir/scripts"/*.sh
        log_success "复制: scripts/"
    fi
    
    # 复制其他配置文件
    for file in README.md README_zh.md .gitignore; do
        if [ -f "$source_dir/$file" ]; then
            cp "$source_dir/$file" "$target_dir/"
        fi
    done
    
    log_success "项目文件复制完成"
}

# 创建环境配置文件
create_env_file() {
    log_info "创建环境配置文件..."
    
    local env_file="/opt/confluence/.env"
    local db_type="${1:-mysql}"  # 默认使用 MySQL
    
    cat > "$env_file" << EOF
# Confluence 环境配置
TZ=Asia/Shanghai

# JVM 内存配置（可根据服务器配置调整）
JVM_MINIMUM_MEMORY=4g
JVM_MAXIMUM_MEMORY=16g
JVM_CODE_CACHE_ARGS=-XX:InitialCodeCacheSize=2g -XX:ReservedCodeCacheSize=4g

# 网络配置
CONFLUENCE_PORT=8090

# 数据库类型选择: mysql 或 postgresql
DATABASE_TYPE=$db_type

# MySQL 配置
MYSQL_ROOT_PASSWORD=123456
MYSQL_DATABASE=confluence
MYSQL_USER=confluence
MYSQL_PASSWORD=123123

# PostgreSQL 配置
POSTGRES_DB=confluence
POSTGRES_USER=confluence
POSTGRES_PASSWORD=confluence123
POSTGRES_PORT=5432
EOF
    
    log_success "环境配置文件创建: $env_file (数据库类型: $db_type)"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    # 检查防火墙状态
    if command -v ufw &> /dev/null; then
        # Ubuntu/Debian UFW
        if ufw status | grep -q "Status: active"; then
            ufw allow 8090/tcp
            log_success "UFW: 已开放端口 8090"
        else
            log_info "UFW 未启用，跳过防火墙配置"
        fi
    elif command -v firewall-cmd &> /dev/null; then
        # CentOS/RHEL firewalld
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --add-port=8090/tcp
            firewall-cmd --reload
            log_success "firewalld: 已开放端口 8090"
        else
            log_info "firewalld 未启用，跳过防火墙配置"
        fi
    else
        log_warning "未检测到支持的防火墙，请手动开放端口 8090"
    fi
}

# 配置系统参数
configure_system_params() {
    log_info "配置系统参数..."
    
    # 配置内核参数
    local sysctl_conf="/etc/sysctl.d/99-confluence.conf"
    cat > "$sysctl_conf" << EOF
# Confluence 系统参数优化
vm.max_map_count=262144
fs.file-max=65536
net.core.somaxconn=65535
EOF
    
    # 应用内核参数
    sysctl -p "$sysctl_conf"
    log_success "系统参数配置完成"
    
    # 配置文件描述符限制
    local limits_conf="/etc/security/limits.d/99-confluence.conf"
    cat > "$limits_conf" << EOF
# Confluence 文件描述符限制
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
    
    log_success "文件描述符限制配置完成"
}

# 验证环境配置
verify_environment() {
    log_info "验证环境配置..."
    
    # 检查目录
    local required_dirs=(
        "/opt/confluence"
        "/var/confluence"
        "/var/lib/mysql"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_success "目录检查通过: $dir"
        else
            log_error "目录缺失: $dir"
            return 1
        fi
    done
    
    # 检查文件
    local required_files=(
        "/opt/confluence/docker-compose.yml"
        "/opt/confluence/.env"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            log_success "文件检查通过: $file"
        else
            log_error "文件缺失: $file"
            return 1
        fi
    done
    
    # 检查 Docker 镜像
    log_info "检查 Docker 镜像..."
    local required_images=(
        "haxqer/confluence:9.2.1"
        "mysql:8.0"
    )
    
    for image in "${required_images[@]}"; do
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$image$"; then
            log_success "镜像检查通过: $image"
        else
            log_warning "镜像缺失: $image (请先运行镜像导入脚本)"
        fi
    done
    
    log_success "环境验证完成"
}

# 显示配置信息
show_configuration() {
    local db_type="${1:-mysql}"
    
    log_info "环境配置信息:"
    echo
    echo "安装目录: /opt/confluence"
    echo "数据目录: /var/confluence"
    
    if [ "$db_type" = "mysql" ]; then
        echo "MySQL 数据: /var/lib/mysql"
    else
        echo "PostgreSQL 数据: /var/lib/postgresql/data"
        echo "PostgreSQL 日志: /var/log/postgresql"
    fi
    
    echo "日志目录: /var/log/confluence"
    echo "配置文件: /opt/confluence/.env"
    echo "访问地址: http://localhost:8090"
    echo "数据库类型: $db_type"
    echo
    echo "下一步操作:"
    if [ "$db_type" = "mysql" ]; then
        echo "1. 运行测试启动: cd /opt/confluence && ./scripts/start-test.sh"
    else
        echo "1. 运行测试启动: cd /opt/confluence && ./scripts/start-test.sh postgresql"
    fi
    echo "2. 安装系统服务: ./scripts/install-system.sh"
    echo
}

# 主函数
main() {
    local db_type="${1:-mysql}"
    
    # 验证数据库类型
    if [[ "$db_type" != "mysql" && "$db_type" != "postgresql" ]]; then
        log_error "不支持的数据库类型: $db_type"
        log_error "支持的类型: mysql, postgresql"
        exit 1
    fi
    
    log_info "开始配置 Confluence 运行环境 (数据库: $db_type)"
    
    # 检查权限
    check_root
    
    # 检查依赖
    check_docker
    check_docker_compose
    
    # 配置环境
    create_system_directories
    copy_project_files
    create_env_file "$db_type"
    configure_firewall
    configure_system_params
    
    # 验证配置
    verify_environment
    
    # 显示配置信息
    show_configuration "$db_type"
    
    log_success "环境配置完成！"
}

# 显示帮助信息
show_help() {
    cat << EOF
Confluence 离线部署 - 环境配置脚本

用法: sudo $0 [数据库类型]

参数:
  数据库类型    可选，支持 mysql 或 postgresql，默认为 mysql

示例:
  sudo $0              # 使用 MySQL 数据库
  sudo $0 mysql        # 使用 MySQL 数据库
  sudo $0 postgresql   # 使用 PostgreSQL 数据库

功能:
  - 创建系统目录结构
  - 复制项目文件到 /opt/confluence
  - 创建环境配置文件
  - 配置防火墙规则
  - 优化系统参数
  - 验证环境配置

注意:
  此脚本需要 root 权限运行，请使用 sudo 执行。

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