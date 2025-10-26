#!/bin/bash

# Confluence 离线部署 - 测试启动脚本
# 用于测试启动 Confluence 服务

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

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 检查 Docker 环境
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker 服务未运行"
        exit 1
    fi
    
    log_success "Docker 环境检查通过"
}

# 检查 Docker Compose
check_compose() {
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        log_success "使用 Docker Compose v2"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        log_success "使用 Docker Compose v1"
    else
        log_error "Docker Compose 未安装"
        exit 1
    fi
}

# 检查镜像
check_images() {
    log_info "检查所需镜像..."
    
    local required_images=(
        "haxqer/confluence:9.2.1"
        "mysql:8.0"
    )
    
    local missing_images=()
    
    for image in "${required_images[@]}"; do
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$image$"; then
            log_success "镜像存在: $image"
        else
            log_warning "镜像缺失: $image"
            missing_images+=("$image")
        fi
    done
    
    if [ ${#missing_images[@]} -gt 0 ]; then
        log_error "缺少必要镜像，请先运行镜像导入脚本"
        for image in "${missing_images[@]}"; do
            echo "  - $image"
        done
        exit 1
    fi
}

# 检查配置文件
check_config() {
    log_info "检查配置文件..."
    
    local compose_file="$PROJECT_DIR/docker-compose.yml"
    if [ ! -f "$compose_file" ]; then
        log_error "docker-compose.yml 文件不存在: $compose_file"
        exit 1
    fi
    log_success "配置文件存在: $compose_file"
    
    # 检查 .env 文件（可选）
    local env_file="$PROJECT_DIR/.env"
    if [ -f "$env_file" ]; then
        log_info "找到环境配置文件: $env_file"
    else
        log_info "未找到 .env 文件，将使用默认配置"
    fi
}

# 检查端口占用
check_ports() {
    log_info "检查端口占用..."
    
    local ports=(8090)
    
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_warning "端口 $port 已被占用"
            log_info "占用端口的进程:"
            netstat -tulnp 2>/dev/null | grep ":$port " || true
            
            read -p "是否继续启动？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "用户取消启动"
                exit 0
            fi
        else
            log_success "端口 $port 可用"
        fi
    done
}

# 启动服务
start_services() {
    log_info "启动 Confluence 服务..."
    
    cd "$PROJECT_DIR"
    
    # 启动服务
    $COMPOSE_CMD up -d
    
    if [ $? -eq 0 ]; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败"
        exit 1
    fi
}

# 等待服务就绪
wait_for_services() {
    log_info "等待服务启动..."
    
    # 等待 MySQL 启动
    log_info "等待 MySQL 服务..."
    local mysql_ready=false
    for i in {1..30}; do
        if docker exec mysql-confluence mysqladmin ping -h localhost --silent 2>/dev/null; then
            mysql_ready=true
            break
        fi
        echo -n "."
        sleep 2
    done
    echo
    
    if [ "$mysql_ready" = true ]; then
        log_success "MySQL 服务已就绪"
    else
        log_warning "MySQL 服务启动超时，但可能仍在初始化中"
    fi
    
    # 等待 Confluence 启动
    log_info "等待 Confluence 服务..."
    log_info "这可能需要几分钟时间，请耐心等待..."
    
    local confluence_ready=false
    for i in {1..60}; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:8090 | grep -q "200\|302\|403"; then
            confluence_ready=true
            break
        fi
        echo -n "."
        sleep 5
    done
    echo
    
    if [ "$confluence_ready" = true ]; then
        log_success "Confluence 服务已就绪"
    else
        log_warning "Confluence 服务启动超时，请检查日志"
    fi
}

# 显示服务状态
show_status() {
    log_info "服务状态:"
    echo
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo
    
    log_info "服务日志 (最近 10 行):"
    echo
    echo "=== MySQL 日志 ==="
    docker logs --tail 10 mysql-confluence 2>/dev/null || log_warning "无法获取 MySQL 日志"
    echo
    echo "=== Confluence 日志 ==="
    docker logs --tail 10 confluence-srv 2>/dev/null || log_warning "无法获取 Confluence 日志"
    echo
}

# 显示访问信息
show_access_info() {
    log_success "Confluence 测试启动完成！"
    echo
    echo "访问信息:"
    echo "  URL: http://localhost:8090"
    echo "  或:  http://$(hostname -I | awk '{print $1}'):8090"
    echo
    echo "管理命令:"
    echo "  查看状态: docker ps"
    echo "  查看日志: docker logs confluence-srv"
    echo "  停止服务: $SCRIPT_DIR/stop-test.sh"
    echo
    echo "注意:"
    echo "  首次启动需要进行 Confluence 初始化配置"
    echo "  数据库连接信息请参考 docker-compose.yml 文件"
    echo
}

# 主函数
main() {
    log_info "开始测试启动 Confluence 服务"
    
    # 环境检查
    check_docker
    check_compose
    check_images
    check_config
    check_ports
    
    # 启动服务
    start_services
    
    # 等待服务就绪
    wait_for_services
    
    # 显示状态
    show_status
    
    # 显示访问信息
    show_access_info
}

# 显示帮助信息
show_help() {
    cat << EOF
Confluence 离线部署 - 测试启动脚本

用法: $0

功能:
  - 检查 Docker 环境和镜像
  - 检查配置文件和端口
  - 启动 Confluence 和 MySQL 服务
  - 等待服务就绪
  - 显示访问信息

注意:
  - 首次启动可能需要几分钟时间
  - 请确保已导入所需的 Docker 镜像
  - 服务将在后台运行，使用 stop-test.sh 停止

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