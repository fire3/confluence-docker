#!/bin/bash

# Confluence 离线部署 - 测试停止脚本
# 用于停止 Confluence 测试服务

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

# 检查服务状态
check_services() {
    local db_type="${1:-mysql}"
    log_info "检查服务状态 (数据库: $db_type)..."
    
    local containers=("confluence-srv")
    if [ "$db_type" = "mysql" ]; then
        containers+=("mysql-confluence")
    else
        containers+=("postgres-confluence")
    fi
    
    local running_containers=()
    
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^$container$"; then
            log_info "容器运行中: $container"
            running_containers+=("$container")
        else
            log_info "容器未运行: $container"
        fi
    done
    
    if [ ${#running_containers[@]} -eq 0 ]; then
        log_warning "没有找到运行中的 Confluence 相关容器"
        return 1
    fi
    
    return 0
}

# 显示当前状态
show_current_status() {
    log_info "当前服务状态:"
    echo
    docker ps --filter "name=confluence" --filter "name=mysql-confluence" --filter "name=postgres-confluence" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
    echo
}

# 停止服务
stop_services() {
    local db_type="${1:-mysql}"
    local remove_flag="${2:-}"
    log_info "停止 Confluence 服务 (数据库: $db_type)..."
    
    cd "$PROJECT_DIR"
    
    # 选择 compose 文件
    local compose_file
    if [ "$db_type" = "postgresql" ]; then
        compose_file="docker-compose-postgresql.yml"
    else
        compose_file="docker-compose.yml"
    fi
    
    # 停止并移除容器
    if [ "$remove_flag" = "--remove" ]; then
        log_info "停止并移除容器和网络..."
        $COMPOSE_CMD -f "$compose_file" down
    else
        log_info "停止容器..."
        $COMPOSE_CMD -f "$compose_file" stop
    fi
    
    if [ $? -eq 0 ]; then
        log_success "服务停止成功"
    else
        log_error "服务停止失败"
        exit 1
    fi
}

# 验证停止状态
verify_stopped() {
    local db_type="${1:-mysql}"
    log_info "验证停止状态 (数据库: $db_type)..."
    
    local containers=("confluence-srv")
    if [ "$db_type" = "mysql" ]; then
        containers+=("mysql-confluence")
    else
        containers+=("postgres-confluence")
    fi
    
    local still_running=()
    
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^$container$"; then
            still_running+=("$container")
        fi
    done
    
    if [ ${#still_running[@]} -eq 0 ]; then
        log_success "所有服务已停止"
    else
        log_warning "以下容器仍在运行:"
        for container in "${still_running[@]}"; do
            echo "  - $container"
        done
    fi
}

# 清理资源（可选）
cleanup_resources() {
    if [ "${1:-}" = "--cleanup" ]; then
        log_info "清理未使用的资源..."
        
        # 清理悬空镜像
        local dangling_images=$(docker images -f "dangling=true" -q)
        if [ -n "$dangling_images" ]; then
            docker rmi $dangling_images
            log_success "已清理悬空镜像"
        fi
        
        # 清理未使用的网络
        docker network prune -f
        log_success "已清理未使用的网络"
        
        # 清理未使用的卷（谨慎使用）
        if [ "${2:-}" = "--volumes" ]; then
            log_warning "清理未使用的卷（这将删除数据）..."
            read -p "确定要删除未使用的卷吗？(y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                docker volume prune -f
                log_success "已清理未使用的卷"
            else
                log_info "跳过卷清理"
            fi
        fi
    fi
}

# 显示停止后信息
show_stop_info() {
    local db_type="${1:-mysql}"
    log_success "Confluence 测试服务已停止 (数据库: $db_type)"
    echo
    echo "重新启动服务:"
    if [ "$db_type" = "mysql" ]; then
        echo "  $SCRIPT_DIR/start-test.sh"
    else
        echo "  $SCRIPT_DIR/start-test.sh postgresql"
    fi
    echo
    echo "完全移除容器和网络:"
    if [ "$db_type" = "mysql" ]; then
        echo "  $0 --remove"
    else
        echo "  $0 postgresql --remove"
    fi
    echo
    echo "清理系统资源:"
    if [ "$db_type" = "mysql" ]; then
        echo "  $0 --cleanup"
        echo "  $0 --cleanup --volumes  # 危险：会删除数据卷"
    else
        echo "  $0 postgresql --cleanup"
        echo "  $0 postgresql --cleanup --volumes  # 危险：会删除数据卷"
    fi
    echo
    echo "查看容器状态:"
    echo "  docker ps -a"
    echo
}

# 主函数
main() {
    local db_type=""
    local remove_flag=""
    local cleanup_flag=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            mysql|postgresql)
                db_type="$1"
                shift
                ;;
            --remove)
                remove_flag="$1"
                shift
                ;;
            --cleanup)
                cleanup_flag="$1"
                shift
                ;;
            --volumes)
                if [[ "$cleanup_flag" == "--cleanup" ]]; then
                    cleanup_flag="$cleanup_flag $1"
                fi
                shift
                ;;
            *)
                # 兼容旧的参数格式
                if [[ -z "$remove_flag" ]]; then
                    remove_flag="$1"
                elif [[ -z "$cleanup_flag" ]]; then
                    cleanup_flag="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 默认数据库类型
    if [[ -z "$db_type" ]]; then
        db_type="mysql"
    fi
    
    log_info "开始停止 Confluence 测试服务 (数据库: $db_type)"
    
    # 设置 compose 文件
    if [ "$db_type" = "postgresql" ]; then
        export COMPOSE_FILE="docker-compose-postgresql.yml"
    else
        export COMPOSE_FILE="docker-compose.yml"
    fi
    
    # 环境检查
    check_docker
    check_compose
    
    # 显示当前状态
    show_current_status
    
    # 检查服务状态
    if ! check_services "$db_type"; then
        log_info "没有运行中的服务需要停止"
        exit 0
    fi
    
    # 停止服务
    stop_services "$db_type" "$remove_flag"
    
    # 验证停止状态
    verify_stopped "$db_type"
    
    # 清理资源（如果指定）
    cleanup_resources "$remove_flag" "$cleanup_flag"
    
    # 显示停止后信息
    show_stop_info "$db_type"
}

# 显示帮助信息
show_help() {
    cat << EOF
Confluence 离线部署 - 测试停止脚本

用法: $0 [数据库类型] [选项]

参数:
  数据库类型    可选，支持 mysql 或 postgresql，默认为 mysql

选项:
  无参数        停止容器但保留容器和网络
  --remove      停止并移除容器和网络
  --cleanup     额外清理未使用的镜像和网络
  --volumes     与 --cleanup 一起使用，清理未使用的卷（危险）

示例:
  $0                          # 停止 MySQL 版本服务
  $0 mysql                    # 停止 MySQL 版本服务
  $0 postgresql               # 停止 PostgreSQL 版本服务
  $0 mysql --remove           # 停止并移除 MySQL 版本容器
  $0 postgresql --cleanup     # 停止 PostgreSQL 版本并清理资源
  $0 --cleanup --volumes      # 停止并清理所有资源（包括数据卷）

注意:
  使用 --volumes 选项会删除数据，请谨慎使用

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