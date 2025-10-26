#!/bin/bash

# Confluence 离线部署 - 系统安装脚本
# 用于安装 Confluence 为系统服务

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

# 检查系统类型
check_system() {
    if ! command -v systemctl &> /dev/null; then
        log_error "此系统不支持 systemd，无法安装系统服务"
        exit 1
    fi
    
    log_success "系统支持 systemd"
}

# 检查 Docker 环境
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    # 检查 Docker Compose
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        log_success "检测到 Docker Compose v2"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        log_success "检测到 Docker Compose v1"
    else
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
}

# 检查安装目录
check_install_dir() {
    local install_dir="/opt/confluence"
    
    if [ ! -d "$install_dir" ]; then
        log_error "安装目录不存在: $install_dir"
        log_error "请先运行环境配置脚本: setup-environment.sh"
        exit 1
    fi
    
    if [ ! -f "$install_dir/docker-compose.yml" ]; then
        log_error "配置文件不存在: $install_dir/docker-compose.yml"
        exit 1
    fi
    
    log_success "安装目录检查通过: $install_dir"
}

# 创建 systemd 服务文件
create_systemd_service() {
    log_info "创建 systemd 服务文件..."
    
    local service_name="confluence"
    local service_file="/etc/systemd/system/${service_name}.service"
    local install_dir="/opt/confluence"
    
    # 获取 Docker Compose 完整路径
    local compose_path
    if [ "$COMPOSE_CMD" = "docker compose" ]; then
        compose_path="$(which docker)"
    else
        compose_path="$(which docker-compose)"
    fi
    
    cat > "$service_file" << EOF
[Unit]
Description=Confluence Wiki Server
Documentation=https://www.atlassian.com/software/confluence
Requires=docker.service
After=docker.service
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$install_dir
Environment=COMPOSE_PROJECT_NAME=confluence

# 启动命令
ExecStart=$compose_path $COMPOSE_CMD -f docker-compose.yml up -d

# 停止命令
ExecStop=$compose_path $COMPOSE_CMD -f docker-compose.yml down

# 重载命令
ExecReload=$compose_path $COMPOSE_CMD -f docker-compose.yml restart

# 超时设置
TimeoutStartSec=300
TimeoutStopSec=120

# 重启策略
Restart=no

# 用户和组
User=root
Group=root

# 标准输出和错误输出
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    log_success "systemd 服务文件创建完成: $service_file"
}

# 创建服务管理脚本
create_service_scripts() {
    log_info "创建服务管理脚本..."
    
    local script_dir="/opt/confluence/scripts"
    
    # 创建服务控制脚本
    cat > "$script_dir/confluence-service.sh" << 'EOF'
#!/bin/bash

# Confluence 服务管理脚本

SERVICE_NAME="confluence"

case "${1:-}" in
    start)
        echo "启动 Confluence 服务..."
        systemctl start $SERVICE_NAME
        ;;
    stop)
        echo "停止 Confluence 服务..."
        systemctl stop $SERVICE_NAME
        ;;
    restart)
        echo "重启 Confluence 服务..."
        systemctl restart $SERVICE_NAME
        ;;
    status)
        systemctl status $SERVICE_NAME
        ;;
    enable)
        echo "启用 Confluence 服务（开机自启）..."
        systemctl enable $SERVICE_NAME
        ;;
    disable)
        echo "禁用 Confluence 服务（取消开机自启）..."
        systemctl disable $SERVICE_NAME
        ;;
    logs)
        echo "查看 Confluence 服务日志..."
        journalctl -u $SERVICE_NAME -f
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|enable|disable|logs}"
        echo
        echo "命令说明:"
        echo "  start   - 启动服务"
        echo "  stop    - 停止服务"
        echo "  restart - 重启服务"
        echo "  status  - 查看服务状态"
        echo "  enable  - 启用开机自启"
        echo "  disable - 禁用开机自启"
        echo "  logs    - 查看服务日志"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$script_dir/confluence-service.sh"
    log_success "服务管理脚本创建完成: $script_dir/confluence-service.sh"
    
    # 创建符号链接到系统路径
    ln -sf "$script_dir/confluence-service.sh" "/usr/local/bin/confluence-service"
    log_success "创建系统命令链接: confluence-service"
}

# 配置日志轮转
configure_log_rotation() {
    log_info "配置日志轮转..."
    
    local logrotate_conf="/etc/logrotate.d/confluence"
    
    cat > "$logrotate_conf" << EOF
/var/log/confluence/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        systemctl reload confluence 2>/dev/null || true
    endscript
}
EOF
    
    log_success "日志轮转配置完成: $logrotate_conf"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙规则..."
    
    # 检查并配置 UFW (Ubuntu/Debian)
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            ufw allow 8090/tcp
            log_success "UFW: 已开放端口 8090"
        else
            log_info "UFW 未启用，跳过配置"
        fi
    fi
    
    # 检查并配置 firewalld (CentOS/RHEL)
    if command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --add-port=8090/tcp
            firewall-cmd --reload
            log_success "firewalld: 已开放端口 8090"
        else
            log_info "firewalld 未启用，跳过配置"
        fi
    fi
}

# 安装和启用服务
install_service() {
    log_info "安装和配置 systemd 服务..."
    
    # 重新加载 systemd 配置
    systemctl daemon-reload
    log_success "systemd 配置已重新加载"
    
    # 启用服务（开机自启）
    systemctl enable confluence
    log_success "Confluence 服务已启用（开机自启）"
    
    # 检查服务状态
    if systemctl is-enabled confluence &> /dev/null; then
        log_success "服务启用状态: $(systemctl is-enabled confluence)"
    fi
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    # 检查服务文件
    if [ -f "/etc/systemd/system/confluence.service" ]; then
        log_success "systemd 服务文件存在"
    else
        log_error "systemd 服务文件缺失"
        return 1
    fi
    
    # 检查服务状态
    if systemctl list-unit-files | grep -q "confluence.service"; then
        log_success "服务已注册到 systemd"
    else
        log_error "服务未正确注册"
        return 1
    fi
    
    # 检查管理脚本
    if [ -x "/usr/local/bin/confluence-service" ]; then
        log_success "服务管理命令可用"
    else
        log_warning "服务管理命令不可用"
    fi
    
    log_success "安装验证完成"
}

# 显示安装后信息
show_post_install_info() {
    log_success "Confluence 系统服务安装完成！"
    echo
    echo "服务管理命令:"
    echo "  启动服务: sudo systemctl start confluence"
    echo "  停止服务: sudo systemctl stop confluence"
    echo "  重启服务: sudo systemctl restart confluence"
    echo "  查看状态: systemctl status confluence"
    echo "  查看日志: journalctl -u confluence -f"
    echo
    echo "便捷管理命令:"
    echo "  confluence-service start    # 启动服务"
    echo "  confluence-service stop     # 停止服务"
    echo "  confluence-service restart  # 重启服务"
    echo "  confluence-service status   # 查看状态"
    echo "  confluence-service logs     # 查看日志"
    echo
    echo "服务配置:"
    echo "  服务文件: /etc/systemd/system/confluence.service"
    echo "  工作目录: /opt/confluence"
    echo "  开机自启: 已启用"
    echo "  访问地址: http://localhost:8090"
    echo
    echo "下一步操作:"
    echo "  1. 启动服务: sudo systemctl start confluence"
    echo "  2. 检查状态: systemctl status confluence"
    echo "  3. 访问 Web 界面进行初始化配置"
    echo
}

# 主函数
main() {
    log_info "开始安装 Confluence 系统服务"
    
    # 环境检查
    check_root
    check_system
    check_docker
    check_install_dir
    
    # 创建服务配置
    create_systemd_service
    create_service_scripts
    configure_log_rotation
    configure_firewall
    
    # 安装服务
    install_service
    
    # 验证安装
    verify_installation
    
    # 显示安装后信息
    show_post_install_info
}

# 显示帮助信息
show_help() {
    cat << EOF
Confluence 离线部署 - 系统安装脚本

用法: sudo $0

功能:
  - 创建 systemd 服务文件
  - 配置服务管理脚本
  - 设置日志轮转
  - 配置防火墙规则
  - 启用开机自启动

前置条件:
  - 需要 root 权限
  - 已运行环境配置脚本
  - Docker 和 Docker Compose 已安装
  - 镜像已导入

注意:
  安装完成后，Confluence 将作为系统服务运行，
  支持开机自启动和标准的 systemctl 管理命令。

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