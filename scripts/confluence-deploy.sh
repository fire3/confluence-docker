#!/bin/bash

# Confluence 离线部署 - 主控制脚本
# 统一管理 Confluence 离线部署的各个阶段

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 显示横幅
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║              Confluence 离线部署管理工具                      ║
║                                                              ║
║              Confluence Offline Deployment Tool             ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 显示主菜单
show_main_menu() {
    echo
    echo "请选择操作:"
    echo
    echo "  1) 下载镜像 (在线环境)"
    echo "  2) 导入镜像 (离线环境)"
    echo "  3) 配置环境"
    echo "  4) 测试启动"
    echo "  5) 测试停止"
    echo "  6) 安装系统服务"
    echo "  7) 服务管理"
    echo "  8) 查看状态"
    echo "  9) 完整部署向导"
    echo "  0) 退出"
    echo
}

# 显示服务管理菜单
show_service_menu() {
    echo
    echo "服务管理选项:"
    echo
    echo "  1) 启动服务"
    echo "  2) 停止服务"
    echo "  3) 重启服务"
    echo "  4) 查看状态"
    echo "  5) 查看日志"
    echo "  6) 启用开机自启"
    echo "  7) 禁用开机自启"
    echo "  0) 返回主菜单"
    echo
}

# 检查脚本文件
check_scripts() {
    local scripts=(
        "download-images.sh"
        "import-images.sh"
        "setup-environment.sh"
        "start-test.sh"
        "stop-test.sh"
        "install-system.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            log_error "脚本文件不存在: $script"
            return 1
        fi
        
        if [ ! -x "$SCRIPT_DIR/$script" ]; then
            chmod +x "$SCRIPT_DIR/$script"
        fi
    done
    
    return 0
}

# 执行脚本
run_script() {
    local script="$1"
    local description="$2"
    shift 2
    
    log_step "$description"
    echo
    
    if [ -f "$SCRIPT_DIR/$script" ]; then
        "$SCRIPT_DIR/$script" "$@"
    else
        log_error "脚本不存在: $script"
        return 1
    fi
}

# 下载镜像
download_images() {
    run_script "download-images.sh" "下载 Docker 镜像"
}

# 导入镜像
import_images() {
    run_script "import-images.sh" "导入 Docker 镜像"
}

# 配置环境
setup_environment() {
    if [ "$EUID" -ne 0 ]; then
        log_warning "环境配置需要 root 权限，将使用 sudo 执行"
        sudo "$SCRIPT_DIR/setup-environment.sh"
    else
        run_script "setup-environment.sh" "配置运行环境"
    fi
}

# 测试启动
start_test() {
    run_script "start-test.sh" "启动测试服务"
}

# 测试停止
stop_test() {
    echo "选择停止方式:"
    echo "  1) 仅停止容器"
    echo "  2) 停止并移除容器"
    echo "  3) 停止并清理资源"
    echo
    read -p "请选择 (1-3): " choice
    
    case $choice in
        1)
            run_script "stop-test.sh" "停止测试服务"
            ;;
        2)
            run_script "stop-test.sh" "停止并移除容器" "--remove"
            ;;
        3)
            run_script "stop-test.sh" "停止并清理资源" "--cleanup"
            ;;
        *)
            log_error "无效选择"
            return 1
            ;;
    esac
}

# 安装系统服务
install_system() {
    if [ "$EUID" -ne 0 ]; then
        log_warning "系统安装需要 root 权限，将使用 sudo 执行"
        sudo "$SCRIPT_DIR/install-system.sh"
    else
        run_script "install-system.sh" "安装系统服务"
    fi
}

# 服务管理
manage_service() {
    while true; do
        show_service_menu
        read -p "请选择操作 (0-7): " choice
        
        case $choice in
            1)
                log_step "启动 Confluence 服务"
                sudo systemctl start confluence
                ;;
            2)
                log_step "停止 Confluence 服务"
                sudo systemctl stop confluence
                ;;
            3)
                log_step "重启 Confluence 服务"
                sudo systemctl restart confluence
                ;;
            4)
                log_step "查看服务状态"
                systemctl status confluence
                ;;
            5)
                log_step "查看服务日志"
                echo "按 Ctrl+C 退出日志查看"
                sleep 2
                journalctl -u confluence -f
                ;;
            6)
                log_step "启用开机自启"
                sudo systemctl enable confluence
                ;;
            7)
                log_step "禁用开机自启"
                sudo systemctl disable confluence
                ;;
            0)
                return 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                ;;
        esac
        
        echo
        read -p "按回车键继续..."
    done
}

# 查看状态
show_status() {
    log_step "系统状态检查"
    echo
    
    # Docker 状态
    echo "=== Docker 状态 ==="
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            log_success "Docker 服务运行正常"
            echo "Docker 版本: $(docker --version)"
        else
            log_error "Docker 服务未运行"
        fi
    else
        log_error "Docker 未安装"
    fi
    echo
    
    # Docker Compose 状态
    echo "=== Docker Compose 状态 ==="
    if docker compose version &> /dev/null; then
        log_success "Docker Compose v2 可用"
        echo "版本: $(docker compose version)"
    elif command -v docker-compose &> /dev/null; then
        log_success "Docker Compose v1 可用"
        echo "版本: $(docker-compose --version)"
    else
        log_error "Docker Compose 未安装"
    fi
    echo
    
    # 容器状态
    echo "=== 容器状态 ==="
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(confluence|mysql)" &> /dev/null; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -1
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(confluence|mysql)"
    else
        log_info "没有运行中的 Confluence 相关容器"
    fi
    echo
    
    # 系统服务状态
    echo "=== 系统服务状态 ==="
    if systemctl list-unit-files | grep -q "confluence.service"; then
        systemctl status confluence --no-pager || true
    else
        log_info "Confluence 系统服务未安装"
    fi
    echo
    
    # 镜像状态
    echo "=== 镜像状态 ==="
    if docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "(confluence|mysql)" &> /dev/null; then
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | head -1
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "(confluence|mysql)"
    else
        log_warning "没有找到 Confluence 相关镜像"
    fi
    echo
}

# 完整部署向导
deployment_wizard() {
    log_step "启动完整部署向导"
    echo
    
    echo "此向导将引导您完成 Confluence 的完整离线部署过程。"
    echo
    read -p "是否继续？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "用户取消部署"
        return 0
    fi
    
    # 步骤 1: 检查环境
    log_step "步骤 1/5: 检查基础环境"
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        return 1
    fi
    log_success "Docker 环境检查通过"
    echo
    
    # 步骤 2: 导入镜像
    log_step "步骤 2/5: 导入 Docker 镜像"
    read -p "是否需要导入镜像？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        import_images
    fi
    echo
    
    # 步骤 3: 配置环境
    log_step "步骤 3/5: 配置运行环境"
    read -p "是否需要配置环境？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        setup_environment
    fi
    echo
    
    # 步骤 4: 测试启动
    log_step "步骤 4/5: 测试启动服务"
    read -p "是否需要测试启动？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        start_test
        echo
        read -p "测试完成后按回车键继续..."
        stop_test
    fi
    echo
    
    # 步骤 5: 安装系统服务
    log_step "步骤 5/5: 安装系统服务"
    read -p "是否需要安装为系统服务？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        install_system
    fi
    echo
    
    log_success "部署向导完成！"
    echo
    echo "后续操作:"
    echo "  - 启动服务: sudo systemctl start confluence"
    echo "  - 访问地址: http://localhost:8090"
    echo "  - 服务管理: 选择主菜单中的 '服务管理' 选项"
    echo
}

# 主循环
main_loop() {
    while true; do
        show_main_menu
        read -p "请选择操作 (0-9): " choice
        
        case $choice in
            1)
                download_images
                ;;
            2)
                import_images
                ;;
            3)
                setup_environment
                ;;
            4)
                start_test
                ;;
            5)
                stop_test
                ;;
            6)
                install_system
                ;;
            7)
                manage_service
                ;;
            8)
                show_status
                ;;
            9)
                deployment_wizard
                ;;
            0)
                log_info "退出部署工具"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                ;;
        esac
        
        echo
        read -p "按回车键继续..."
    done
}

# 主函数
main() {
    # 显示横幅
    show_banner
    
    # 检查脚本文件
    if ! check_scripts; then
        log_error "脚本文件检查失败"
        exit 1
    fi
    
    # 进入主循环
    main_loop
}

# 显示帮助信息
show_help() {
    cat << EOF
Confluence 离线部署 - 主控制脚本

用法: $0 [选项]

选项:
  -h, --help    显示此帮助信息

功能:
  提供交互式菜单来管理 Confluence 离线部署的各个阶段：
  - 镜像下载和导入
  - 环境配置
  - 测试启动和停止
  - 系统服务安装
  - 服务管理
  - 状态查看
  - 完整部署向导

使用说明:
  1. 在有网络的环境中运行 "下载镜像" 功能
  2. 将项目目录复制到离线环境
  3. 在离线环境中依次执行：导入镜像 -> 配置环境 -> 安装系统服务
  4. 使用服务管理功能来控制 Confluence 服务

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