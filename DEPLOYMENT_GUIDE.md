# Confluence 离线部署指南

本指南提供了一套完整的脚本来支持 Confluence 在离线环境中的部署和管理。

## 📋 功能概述

本部署工具包提供以下功能：

1. **镜像下载** - 在有网络环境中下载所需的 Docker 镜像
2. **镜像导入** - 在离线环境中导入 Docker 镜像
3. **环境配置** - 配置系统目录、权限和参数
4. **测试启动/停止** - 用于测试的服务启动和停止
5. **系统服务安装** - 安装为 systemd 系统服务
6. **服务管理** - 统一的服务管理界面

## 🚀 快速开始

### 方式一：使用主控制脚本（推荐）

```bash
# 进入项目目录
cd /path/to/confluence

# 运行主控制脚本
chmod +x scripts/confluence-deploy.sh
./scripts/confluence-deploy.sh
```

主控制脚本提供交互式菜单，可以引导您完成整个部署过程。

### 方式二：手动执行各个步骤

#### 在线环境（有网络）

```bash
# 1. 下载镜像
chmod +x scripts/download-images.sh
./scripts/download-images.sh
```

#### 离线环境

```bash
# 2. 导入镜像
chmod +x scripts/import-images.sh
./scripts/import-images.sh

# 3. 配置环境（需要 root 权限）
chmod +x scripts/setup-environment.sh
sudo ./scripts/setup-environment.sh

# 4. 测试启动（可选）
chmod +x scripts/start-test.sh
./scripts/start-test.sh

# 5. 安装系统服务（需要 root 权限）
chmod +x scripts/install-system.sh
sudo ./scripts/install-system.sh
```

## 📁 脚本说明

### 核心脚本

| 脚本文件 | 功能描述 | 权限要求 |
|---------|---------|---------|
| `confluence-deploy.sh` | 主控制脚本，提供交互式菜单 | 普通用户 |
| `download-images.sh` | 下载 Docker 镜像到本地文件 | 普通用户 |
| `import-images.sh` | 从本地文件导入 Docker 镜像 | 普通用户 |
| `setup-environment.sh` | 配置系统环境和目录结构 | root |
| `start-test.sh` | 启动测试服务 | 普通用户 |
| `stop-test.sh` | 停止测试服务 | 普通用户 |
| `install-system.sh` | 安装为系统服务 | root |

### 辅助脚本

| 脚本文件 | 功能描述 |
|---------|---------|
| `common.sh` | 公共函数库 |
| `download_images.sh` | 简化版镜像下载脚本 |
| `import_images.sh` | 简化版镜像导入脚本 |
| `configure_env.sh` | 简化版环境配置脚本 |
| `start.sh` | 简化版启动脚本 |
| `stop.sh` | 简化版停止脚本 |
| `install_systemd.sh` | 简化版 systemd 安装脚本 |

## 🔧 详细配置

### 系统要求

- **操作系统**: Linux (支持 systemd)
- **Docker**: 20.10+ 
- **Docker Compose**: v2.0+ 或 v1.29+
- **内存**: 建议 8GB+
- **磁盘**: 建议 20GB+ 可用空间

### 目录结构

安装完成后的目录结构：

```
/opt/confluence/                 # 主安装目录
├── docker-compose.yml          # Docker Compose 配置
├── confluence_lts/              # LTS 版本配置
├── scripts/                     # 部署脚本
├── .env                        # 环境变量配置
└── README.md                   # 说明文档

/var/confluence/                # Confluence 数据目录
/var/lib/mysql/                 # MySQL 数据目录
/var/log/confluence/            # 日志目录
```

### 环境变量配置

编辑 `/opt/confluence/.env` 文件来自定义配置：

```bash
# 时区设置
TZ=Asia/Shanghai

# JVM 内存配置
JVM_MINIMUM_MEMORY=4g
JVM_MAXIMUM_MEMORY=16g
JVM_CODE_CACHE_ARGS=-XX:InitialCodeCacheSize=2g -XX:ReservedCodeCacheSize=4g

# MySQL 配置
MYSQL_ROOT_PASSWORD=123456
MYSQL_DATABASE=confluence
MYSQL_USER=confluence
MYSQL_PASSWORD=123123

# 端口配置
CONFLUENCE_PORT=8090
```

## 🎯 使用场景

### 场景一：完全离线部署

1. **在线环境准备**：
   ```bash
   ./scripts/download-images.sh
   ```

2. **传输到离线环境**：
   ```bash
   # 打包整个项目目录
   tar -czf confluence-offline.tar.gz /path/to/confluence
   
   # 在离线环境解压
   tar -xzf confluence-offline.tar.gz
   ```

3. **离线环境部署**：
   ```bash
   cd confluence
   ./scripts/confluence-deploy.sh
   # 选择 "完整部署向导"
   ```

### 场景二：测试部署

```bash
# 导入镜像
./scripts/import-images.sh

# 测试启动
./scripts/start-test.sh

# 访问 http://localhost:8090 进行测试

# 测试完成后停止
./scripts/stop-test.sh
```

### 场景三：生产部署

```bash
# 完整环境配置
sudo ./scripts/setup-environment.sh

# 安装系统服务
sudo ./scripts/install-system.sh

# 启动服务
sudo systemctl start confluence

# 启用开机自启
sudo systemctl enable confluence
```

## 🛠️ 服务管理

### systemd 服务管理

```bash
# 启动服务
sudo systemctl start confluence

# 停止服务
sudo systemctl stop confluence

# 重启服务
sudo systemctl restart confluence

# 查看状态
systemctl status confluence

# 查看日志
journalctl -u confluence -f

# 启用开机自启
sudo systemctl enable confluence

# 禁用开机自启
sudo systemctl disable confluence
```

### 便捷管理命令

安装完成后，可以使用便捷命令：

```bash
# 启动服务
confluence-service start

# 停止服务
confluence-service stop

# 重启服务
confluence-service restart

# 查看状态
confluence-service status

# 查看日志
confluence-service logs
```

## 🔍 故障排除

### 常见问题

1. **Docker 服务未启动**
   ```bash
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

2. **端口被占用**
   ```bash
   # 查看端口占用
   netstat -tulnp | grep 8090
   
   # 修改端口配置
   vim /opt/confluence/.env
   ```

3. **权限问题**
   ```bash
   # 修复数据目录权限
   sudo chmod 777 /var/confluence
   sudo chmod 777 /var/lib/mysql
   ```

4. **内存不足**
   ```bash
   # 调整 JVM 内存配置
   vim /opt/confluence/.env
   # 修改 JVM_MAXIMUM_MEMORY 值
   ```

### 日志查看

```bash
# 系统服务日志
journalctl -u confluence -f

# Docker 容器日志
docker logs confluence-srv -f
docker logs mysql-confluence -f

# 应用日志
tail -f /var/confluence/logs/atlassian-confluence.log
```

### 数据备份

```bash
# 备份 Confluence 数据
sudo tar -czf confluence-data-$(date +%Y%m%d).tar.gz /var/confluence

# 备份 MySQL 数据
sudo tar -czf mysql-data-$(date +%Y%m%d).tar.gz /var/lib/mysql

# 或使用 mysqldump
docker exec mysql-confluence mysqldump -u root -p123456 confluence > confluence-db-$(date +%Y%m%d).sql
```

## 📚 版本说明

### 支持的 Confluence 版本

- **默认版本**: Confluence 9.2.1 (最新版)
- **LTS 版本**: Confluence 8.5.23 (长期支持版)

### 切换版本

```bash
# 使用 LTS 版本
./scripts/start.sh lts

# 或修改 docker-compose.yml 中的镜像标签
```

## 🔐 安全建议

1. **修改默认密码**：
   - 修改 MySQL root 密码
   - 修改 MySQL confluence 用户密码

2. **网络安全**：
   - 配置防火墙规则
   - 使用 HTTPS（需要反向代理）

3. **数据安全**：
   - 定期备份数据
   - 设置合适的文件权限

4. **系统安全**：
   - 定期更新系统和 Docker
   - 监控系统资源使用

## 📞 技术支持

如果在部署过程中遇到问题，请：

1. 查看相关日志文件
2. 检查系统资源（内存、磁盘空间）
3. 确认网络连接和端口配置
4. 参考官方文档：https://confluence.atlassian.com/

## 📄 许可证

本部署工具遵循 MIT 许可证。Confluence 软件本身需要有效的 Atlassian 许可证。

---

**注意**: 本工具仅用于简化 Confluence 的部署过程，不包含 Confluence 软件许可证。请确保您拥有有效的 Atlassian Confluence 许可证。