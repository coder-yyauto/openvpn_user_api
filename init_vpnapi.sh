uui/bin/bash

# 检查是否以root运行
if [ "$EUID" -ne 0 ]; then 
    echo "请以root用户运行此脚本"
    exit 1
fi

# 检查系统类型和包管理器
if [ -f /etc/debian_version ]; then
    PKG_MANAGER="apt"
    PKG_UPDATE="apt update"
    PYTHON_PKG="python3"
    PIP_PKG="python3-pip"
    PACKAGES="nginx openvpn"
elif [ -f /etc/redhat-release ]; then
    PKG_MANAGER="yum"
    PKG_UPDATE=""
    PYTHON_PKG="python3"
    PIP_PKG="python3-pip"
    PACKAGES="nginx openvpn"
else
    echo "不支持的系统类型。本脚本支持 Debian/Ubuntu 和 RHEL/CentOS/Rocky。"
    exit 1
fi

# 检查Python3和pip
echo "检查Python环境..."
if ! command -v python3 >/dev/null 2>&1; then
    echo "安装 Python3..."
    $PKG_UPDATE
    $PKG_MANAGER install -y $PYTHON_PKG
fi

if ! command -v pip3 >/dev/null 2>&1; then
    echo "安装 pip3..."
    $PKG_UPDATE
    $PKG_MANAGER install -y $PIP_PKG
fi

# 安装必要的系统包
echo "安装系统依赖..."
$PKG_MANAGER install -y $PACKAGES

# 安装系统Python依赖
echo "安装系统Python依赖..."

# 创建pyuser用户（不设置密码，后续通过root用户转移公钥认证）
if ! id "pyuser" &>/dev/null; then
    useradd -m -s /bin/bash pyuser
    echo "已创建pyuser用户（无密码，需配置SSH公钥认证）"
fi

# 创建并设置API socket目录
echo "配置API socket目录..."
mkdir -p /dev/shm/vpnapi
chmod 755 /dev/shm/vpnapi
chown pyuser:pyuser /dev/shm/vpnapi

# 创建并设置认证socket目录
echo "配置认证socket目录..."
mkdir -p /dev/shm/openvpn
chmod 777 /dev/shm/openvpn

# 创建并设置via-file目录
echo "配置OpenVPN认证目录..."
mkdir -p /dev/shm/via-file
chmod 777 /dev/shm/via-file
chown nobody:nobody /dev/shm/via-file

# 切换到pyuser用户安装micromamba
echo "安装micromamba和Python环境..."
su - pyuser -c '
    set -e
    cd $HOME
    # 标准非特权用户部署路径 (官方推荐)
    # 二进制: ~/micromamba/bin/micromamba
    # 环境和包: ~/micromamba/pkgs
    echo "创建标准micromamba目录结构..."
    MAMBA_DIR="$HOME/micromamba"
    mkdir -p "$MAMBA_DIR/bin" || { echo "目录创建失败"; exit 1; }
    chmod 755 "$MAMBA_DIR" || { echo "目录权限设置失败"; exit 1; }
    
    echo "下载并安装micromamba..."
    curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | \
        tar -xvj -C "$MAMBA_DIR/bin" --strip-components=1 bin/micromamba || { echo "下载安装失败"; exit 1; }
    
    echo "设置执行权限..."
    chmod +x "$MAMBA_DIR/bin/micromamba" || { echo "权限设置失败"; exit 1; }
    export PATH="$MAMBA_DIR/bin:$PATH"
    
    echo "初始化micromamba环境..."
    micromamba shell init -s bash --root-prefix="$MAMBA_DIR" || { echo "初始化失败"; exit 1; }
    eval "$(micromamba shell hook -s bash)"
    
    echo "创建Python环境..."
    "$MAMBA_PATH" create -y -n pyuser python=3.12 || { echo "创建环境失败"; exit 1; }
    "$MAMBA_PATH" activate pyuser
    
    echo "创建vpnapi目录..."
    mkdir -p /home/pyuser/vpnapi || { echo "创建目录失败"; exit 1; }
    cd /home/pyuser/vpnapi
    
    echo "安装Python依赖..."
    "$MAMBA_PATH" run -n pyuser pip install -r requirements.txt || { echo "依赖安装失败"; exit 1; }
'

# 配置自动激活环境
echo 'micromamba activate pyuser' >> /home/pyuser/.bashrc

# 复制认证程序
echo "配置OpenVPN认证..."
cp /home/pyuser/vpnapi/init/openvpn_auth_api.py.template /usr/local/sbin/openvpn_auth_api.py
chmod 755 /usr/local/sbin/openvpn_auth_api.py
chown root:root /usr/local/sbin/openvpn_auth_api.py

# 配置OpenVPN
mkdir -p /etc/openvpn/server
cp /home/pyuser/vpnapi/init/server.conf /etc/openvpn/server/
chmod 750 /etc/openvpn/server
if ! getent group openvpn >/dev/null; then
    groupadd openvpn
fi
chown root:openvpn /etc/openvpn/server

# 配置OpenVPN服务override
echo "配置OpenVPN服务..."
mkdir -p /etc/systemd/system/openvpn-server@server.service.d
cp /home/pyuser/vpnapi/init/openvpn-server@.service /etc/systemd/system/openvpn-server@.service

# 配置Nginx
echo "配置Nginx..."
cp /home/pyuser/vpnapi/init/nginx_vpn_api.conf /etc/nginx/conf.d/
systemctl enable nginx
systemctl restart nginx

# 配置VPN API服务
echo "配置VPN API服务..."
cp /home/pyuser/vpnapi/init/vpn_user_api.service /etc/systemd/system/
cp /home/pyuser/vpnapi/init/vpn_user_api.conf /home/pyuser/.vpnapi_env
chown pyuser:pyuser /home/pyuser/.vpnapi_env
chmod 600 /home/pyuser/.vpnapi_env

# 初始化数据目录
mkdir -p /home/pyuser/vpnapi/data
cp /home/pyuser/vpnapi/init/psw_empty.db /home/pyuser/vpnapi/data/psw.db
chown -R pyuser:pyuser /home/pyuser/vpnapi

# 启动服务
echo "启动服务..."
systemctl daemon-reload
systemctl enable vpn_user_api
systemctl start vpn_user_api
systemctl enable openvpn-server@server
systemctl start openvpn-server@server

echo "
VPN API服务部署完成！

后续步骤：
1. 生成OpenVPN证书（如果还没有）
2. 添加VPN用户：
   su - pyuser
   cd vpnapi
   python add_user.py <用户名> <密码>

3. 检查服务状态：
   systemctl status vpn_user_api
   systemctl status openvpn-server@server

4. 查看日志：
   journalctl -u vpn_user_api
   tail -f /var/log/openvpn/auth.log
" 