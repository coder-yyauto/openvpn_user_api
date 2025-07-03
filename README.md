# OpenVPN User API

这是一个基于Unix Socket的OpenVPN用户认证API系统。它提供了以下功能：

- 基于SQLite的用户管理
- 通过Unix Socket进行认证，提高安全性
- 支持Tunnelblick等多种VPN客户端
- 详细的认证日志记录
- 完整的部署脚本

## 快速开始

1. 克隆仓库并进入目录：
   ```bash
   git clone git@github.com:your-username/openvpn_user_api.git
   cd openvpn_user_api
   ```

2. 运行安装脚本：
   ```bash
   sudo ./init_vpnapi.sh
   ```

3. 添加VPN用户：
   ```bash
   su - pyuser
   cd vpnapi
   python add_user.py <用户名> <密码>
   ```

## 系统要求

- Linux系统（支持以下发行版）：
  - Debian 10+
  - Ubuntu 20.04+
  - RHEL/CentOS/Rocky 8+
- 系统Python 3.6+（仅用于初始化，如果系统中没有会自动安装）
- 运行环境：Python 3.12（通过micromamba自动安装）
- 1GB以上可用内存
- 1GB以上可用磁盘空间

## 配置文件

主要配置文件位置：

- OpenVPN配置：`/etc/openvpn/server/server.conf`
- Nginx配置：`/etc/nginx/conf.d/nginx_vpn_api.conf`
- API服务配置：`/home/pyuser/.vpnapi_env`
- 认证程序：`/usr/local/sbin/openvpn_auth_api.py`

## 日志文件

- API服务日志：`journalctl -u vpn_user_api`
- 认证日志：`/var/log/openvpn/auth.log`
- OpenVPN日志：`journalctl -u openvpn-server@server`

## 安全说明

- 所有密码使用scrypt算法加密存储
- 使用Unix Socket通信，避免网络暴露
- 最小权限原则配置
- OpenVPN目录权限严格控制

## 故障排除

1. 检查服务状态：
   ```bash
   systemctl status vpn_user_api
   systemctl status openvpn-server@server
   ```

2. 检查认证日志：
   ```bash
   tail -f /var/log/openvpn/auth.log
   ```

3. 检查API服务日志：
   ```bash
   journalctl -u vpn_user_api -f
   ```

## 贡献

欢迎提交Issue和Pull Request！

## 许可证

MIT License 
