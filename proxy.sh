#!/bin/bash

set -e

# ==============================
# 三合一代理管理脚本
# SOCKS5 / SS2022 / VLESS Reality
# 随机端口范围：10000-65535
# ==============================

RANDOM_PORT_MIN=10000
RANDOM_PORT_MAX=65535

# SOCKS5
SOCKS_CONFIG="/etc/danted.conf"
SOCKS_SERVICE="danted"

# SS2022
SS_CONTAINER="ss2022-server"
SS_IMAGE="ghcr.io/shadowsocks/ssserver-rust:latest"
SS_METHOD="2022-blake3-aes-128-gcm"

# Reality
XRAY_SERVICE="xray"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
DEFAULT_SNI="www.paypal.com"
DEFAULT_FP="chrome"
DEFAULT_NODE_NAME="VLESS-Reality"

clear
echo "======================================"
echo " 三合一代理一键管理脚本"
echo " 1. SOCKS5 / SK5"
echo " 2. SS2022"
echo " 3. VLESS + Reality + Vision + TCP"
echo " 随机端口范围：${RANDOM_PORT_MIN}-${RANDOM_PORT_MAX}"
echo " 适用于 Ubuntu / Debian"
echo "======================================"
echo ""

if [ "$(id -u)" != "0" ]; then
  echo "错误：请使用 root 用户执行"
  echo "示例：sudo bash proxy.sh"
  exit 1
fi

check_system() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$ID"
  else
    echo "无法识别系统"
    exit 1
  fi

  case "$OS_NAME" in
    ubuntu|debian)
      echo "系统检测通过：$PRETTY_NAME"
      ;;
    *)
      echo "当前系统可能不是 Ubuntu / Debian，脚本仍会尝试继续安装"
      ;;
  esac
}

install_base_packages() {
  echo ""
  echo "正在安装基础依赖..."
  apt update -y
  apt install -y curl wget unzip socat cron ufw net-tools iproute2 procps openssl ca-certificates
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo "Docker 已安装"
  else
    echo "正在安装 Docker..."
    curl -fsSL https://get.docker.com | bash
  fi

  systemctl enable docker >/dev/null 2>&1 || true
  systemctl restart docker
}

install_xray() {
  echo ""
  echo "正在安装 / 更新 Xray Core..."

  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

  if [ ! -f "$XRAY_BIN" ]; then
    echo "错误：Xray 安装失败，未找到 $XRAY_BIN"
    exit 1
  fi

  echo "Xray 安装完成：$($XRAY_BIN version | head -n 1)"
}

random_port() {
  while true; do
    PORT=$(shuf -i ${RANDOM_PORT_MIN}-${RANDOM_PORT_MAX} -n 1)
    if ! ss -lntup | grep -q ":$PORT "; then
      echo "$PORT"
      return
    fi
  done
}

random_user() {
  echo "sk5_$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
}

random_pass() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 18
}

random_key() {
  openssl rand -base64 16
}

random_short_id() {
  openssl rand -hex 8
}

get_public_ip() {
  IP=$(curl -4 -s --max-time 8 https://api.ipify.org || true)

  if [ -z "$IP" ]; then
    IP=$(curl -4 -s --max-time 8 https://ipv4.icanhazip.com || true)
  fi

  if [ -z "$IP" ]; then
    IP=$(curl -4 -s --max-time 8 https://ifconfig.me || true)
  fi

  if [ -z "$IP" ]; then
    IP=$(hostname -I | awk '{print $1}')
  fi

  echo "$IP"
}

validate_port() {
  PORT_TO_CHECK="$1"

  if ! [[ "$PORT_TO_CHECK" =~ ^[0-9]+$ ]]; then
    echo "错误：端口必须是数字"
    exit 1
  fi

  if [ "$PORT_TO_CHECK" -lt 1 ] || [ "$PORT_TO_CHECK" -gt 65535 ]; then
    echo "错误：端口范围必须是 1-65535"
    exit 1
  fi

  if [ "$PORT_TO_CHECK" -lt 10000 ]; then
    echo "错误：端口不能低于 10000"
    exit 1
  fi

  if ss -lntup | grep -q ":$PORT_TO_CHECK "; then
    echo "错误：端口 $PORT_TO_CHECK 已被占用，请换一个端口"
    exit 1
  fi
}

open_firewall_tcp_udp() {
  PORT_TO_OPEN="$1"

  echo ""
  echo "正在放行端口：$PORT_TO_OPEN/tcp + $PORT_TO_OPEN/udp"

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$PORT_TO_OPEN"/tcp >/dev/null 2>&1 || true
    ufw allow "$PORT_TO_OPEN"/udp >/dev/null 2>&1 || true
  fi

  if command -v iptables >/dev/null 2>&1; then
    iptables -I INPUT -p tcp --dport "$PORT_TO_OPEN" -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p udp --dport "$PORT_TO_OPEN" -j ACCEPT 2>/dev/null || true
  fi
}

open_firewall_tcp() {
  PORT_TO_OPEN="$1"

  echo ""
  echo "正在放行端口：$PORT_TO_OPEN/tcp"

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$PORT_TO_OPEN"/tcp >/dev/null 2>&1 || true
  fi

  if command -v iptables >/dev/null 2>&1; then
    iptables -I INPUT -p tcp --dport "$PORT_TO_OPEN" -j ACCEPT 2>/dev/null || true
  fi
}

get_default_interface() {
  INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

  if [ -z "$INTERFACE" ]; then
    echo "无法识别默认网卡"
    exit 1
  fi

  echo "$INTERFACE"
}

# ==============================
# SOCKS5 / SK5
# ==============================

install_socks5() {
  check_system
  install_base_packages

  echo ""
  echo "正在安装 Dante SOCKS5..."
  apt install -y dante-server

  echo ""
  echo "请选择 SOCKS5 安装模式："
  echo "1) 自定义端口 / 账号 / 密码"
  echo "2) 随机生成端口 / 账号 / 密码"
  echo ""

  read -p "请输入选项 [1/2]，默认 2: " MODE
  MODE=${MODE:-2}

  if [ "$MODE" = "1" ]; then
    read -p "请输入 SOCKS5 端口，必须 >=10000: " SOCKS_PORT
    read -p "请输入 SOCKS5 用户名: " SOCKS_USER
    read -s -p "请输入 SOCKS5 密码: " SOCKS_PASS
    echo ""
  else
    SOCKS_PORT=$(random_port)
    SOCKS_USER=$(random_user)
    SOCKS_PASS=$(random_pass)
  fi

  if [ -z "$SOCKS_PORT" ] || [ -z "$SOCKS_USER" ] || [ -z "$SOCKS_PASS" ]; then
    echo "错误：端口、用户名、密码不能为空"
    exit 1
  fi

  validate_port "$SOCKS_PORT"

  echo ""
  echo "正在创建 SOCKS5 用户..."

  if id "$SOCKS_USER" >/dev/null 2>&1; then
    echo "用户已存在，正在更新密码"
  else
    useradd -r -s /usr/sbin/nologin "$SOCKS_USER"
  fi

  echo "$SOCKS_USER:$SOCKS_PASS" | chpasswd

  INTERFACE=$(get_default_interface)

  echo "检测到默认网卡：$INTERFACE"
  echo "正在写入 Dante 配置..."

  cat > "$SOCKS_CONFIG" <<CONFIG
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

internal: 0.0.0.0 port = $SOCKS_PORT
external: $INTERFACE

socksmethod: username
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    log: connect disconnect error
}
CONFIG

  open_firewall_tcp_udp "$SOCKS_PORT"

  echo ""
  echo "正在启动 Dante..."
  systemctl restart "$SOCKS_SERVICE"
  systemctl enable "$SOCKS_SERVICE" >/dev/null 2>&1 || true

  sleep 1

  if ! systemctl is-active --quiet "$SOCKS_SERVICE"; then
    echo "错误：Dante 启动失败"
    journalctl -u "$SOCKS_SERVICE" -n 80 --no-pager
    exit 1
  fi

  IP=$(get_public_ip)

  echo ""
  echo "======================================"
  echo " SOCKS5 / SK5 安装完成"
  echo "======================================"
  echo "服务器 IP：$IP"
  echo "端口：$SOCKS_PORT"
  echo "用户名：$SOCKS_USER"
  echo "密码：$SOCKS_PASS"
  echo ""
  echo "连接格式："
  echo "socks5://$SOCKS_USER:$SOCKS_PASS@$IP:$SOCKS_PORT"
  echo ""
  echo "Shadowrocket / Clash 手动填写："
  echo "类型：SOCKS5"
  echo "服务器：$IP"
  echo "端口：$SOCKS_PORT"
  echo "用户名：$SOCKS_USER"
  echo "密码：$SOCKS_PASS"
  echo ""
  echo "开机自启：已开启"
  echo "======================================"
}

status_socks5() {
  echo "======================================"
  echo " SOCKS5 / SK5 状态"
  echo "======================================"
  systemctl status "$SOCKS_SERVICE" --no-pager || true
  echo ""
  echo "监听端口："
  ss -lntup | grep danted || true
}

restart_socks5() {
  echo "正在重启 SOCKS5..."
  systemctl restart "$SOCKS_SERVICE"

  if systemctl is-active --quiet "$SOCKS_SERVICE"; then
    echo "SOCKS5 重启成功"
  else
    echo "SOCKS5 重启失败"
    journalctl -u "$SOCKS_SERVICE" -n 80 --no-pager
  fi
}

uninstall_socks5() {
  echo "警告：即将卸载 SOCKS5 / SK5"
  read -p "确认卸载吗？输入 y 确认: " CONFIRM

  if [ "$CONFIRM" != "y" ]; then
    echo "已取消卸载"
    exit 0
  fi

  systemctl stop "$SOCKS_SERVICE" 2>/dev/null || true
  systemctl disable "$SOCKS_SERVICE" 2>/dev/null || true
  apt remove -y dante-server || true
  rm -f "$SOCKS_CONFIG"

  echo "SOCKS5 / SK5 已卸载"
}

# ==============================
# SS2022
# ==============================

install_ss2022() {
  check_system
  install_base_packages
  install_docker

  echo ""
  echo "请选择 SS2022 安装模式："
  echo "1) 自定义端口 / 自定义密钥"
  echo "2) 随机生成端口 / 随机密钥"
  echo ""

  read -p "请输入选项 [1/2]，默认 2: " MODE
  MODE=${MODE:-2}

  if [ "$MODE" = "1" ]; then
    read -p "请输入 SS2022 端口，必须 >=10000: " SS_PORT
    echo ""
    echo "如果你不懂密钥，直接回车，让脚本自动生成。"
    read -p "请输入自定义密钥，留空则自动生成: " SS_KEY

    if [ -z "$SS_KEY" ]; then
      SS_KEY=$(random_key)
    fi
  else
    SS_PORT=$(random_port)
    SS_KEY=$(random_key)
  fi

  if [ -z "$SS_PORT" ] || [ -z "$SS_KEY" ]; then
    echo "错误：端口和密钥不能为空"
    exit 1
  fi

  validate_port "$SS_PORT"
  open_firewall_tcp_udp "$SS_PORT"

  echo ""
  echo "正在拉取 Shadowsocks-Rust 镜像..."
  docker pull "$SS_IMAGE"

  if docker ps -a --format '{{.Names}}' | grep -q "^${SS_CONTAINER}$"; then
    echo "检测到旧 SS2022 容器，正在删除..."
    docker stop "$SS_CONTAINER" >/dev/null 2>&1 || true
    docker rm "$SS_CONTAINER" >/dev/null 2>&1 || true
  fi

  echo ""
  echo "正在启动 SS2022..."

  docker run -d \
    --name "$SS_CONTAINER" \
    --restart always \
    -p "$SS_PORT:$SS_PORT/tcp" \
    -p "$SS_PORT:$SS_PORT/udp" \
    "$SS_IMAGE" \
    ssserver \
    -s "0.0.0.0:$SS_PORT" \
    -m "$SS_METHOD" \
    -k "$SS_KEY" \
    --tcp-fast-open \
    -U

  sleep 2

  if ! docker ps --format '{{.Names}}' | grep -q "^${SS_CONTAINER}$"; then
    echo "错误：SS2022 启动失败"
    docker logs "$SS_CONTAINER" || true
    exit 1
  fi

  IP=$(get_public_ip)
  SS_USERINFO=$(printf "%s:%s" "$SS_METHOD" "$SS_KEY" | base64 -w 0 2>/dev/null || printf "%s:%s" "$SS_METHOD" "$SS_KEY" | base64 | tr -d '\n')

  echo ""
  echo "======================================"
  echo " SS2022 安装完成"
  echo "======================================"
  echo "服务器 IP：$IP"
  echo "端口：$SS_PORT"
  echo "加密方式：$SS_METHOD"
  echo "密码 / 密钥：$SS_KEY"
  echo ""
  echo "SS URI："
  echo "ss://$SS_USERINFO@$IP:$SS_PORT#SS2022-$IP"
  echo ""
  echo "Shadowrocket 手动填写："
  echo "类型：Shadowsocks"
  echo "服务器：$IP"
  echo "端口：$SS_PORT"
  echo "加密方式：$SS_METHOD"
  echo "密码：$SS_KEY"
  echo ""
  echo "Mihomo / Clash Meta 配置："
  echo "- name: SS2022-$IP"
  echo "  type: ss"
  echo "  server: $IP"
  echo "  port: $SS_PORT"
  echo "  cipher: $SS_METHOD"
  echo "  password: $SS_KEY"
  echo "  udp: true"
  echo ""
  echo "开机自启：已开启"
  echo "======================================"
}

status_ss2022() {
  echo "======================================"
  echo " SS2022 状态"
  echo "======================================"

  if docker ps -a --format '{{.Names}}' | grep -q "^${SS_CONTAINER}$"; then
    docker ps -a | grep "$SS_CONTAINER" || true
    echo ""
    echo "最近日志："
    docker logs --tail 50 "$SS_CONTAINER" || true
  else
    echo "未找到 SS2022 容器"
  fi
}

restart_ss2022() {
  echo "正在重启 SS2022..."
  docker restart "$SS_CONTAINER"
  echo "SS2022 重启完成"
}

uninstall_ss2022() {
  echo "警告：即将卸载 SS2022"
  read -p "确认卸载吗？输入 y 确认: " CONFIRM

  if [ "$CONFIRM" != "y" ]; then
    echo "已取消卸载"
    exit 0
  fi

  docker stop "$SS_CONTAINER" >/dev/null 2>&1 || true
  docker rm "$SS_CONTAINER" >/dev/null 2>&1 || true

  echo "SS2022 容器已卸载，Docker 本身未卸载。"
}

# ==============================
# VLESS Reality Vision TCP
# ==============================

generate_reality_keys() {
  echo ""
  echo "正在生成 Reality 密钥..."

  KEY_OUTPUT=$($XRAY_BIN x25519)

  PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep "Private key" | awk '{print $3}')
  PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep "Public key" | awk '{print $3}')

  if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "错误：Reality 密钥生成失败"
    exit 1
  fi
}

generate_uuid() {
  echo ""
  echo "正在生成 UUID..."

  UUID=$($XRAY_BIN uuid)

  if [ -z "$UUID" ]; then
    echo "错误：UUID 生成失败"
    exit 1
  fi
}

backup_old_xray_config() {
  if [ -f "$XRAY_CONFIG" ]; then
    BACKUP_FILE="${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$XRAY_CONFIG" "$BACKUP_FILE"
    echo "已备份旧配置：$BACKUP_FILE"
  fi
}

write_xray_config() {
  mkdir -p /usr/local/etc/xray

  backup_old_xray_config

  echo ""
  echo "正在写入 Xray Reality 配置..."

  cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality-vision",
      "listen": "0.0.0.0",
      "port": $VLESS_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision",
            "email": "reality-user"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SNI_DOMAIN:443",
          "xver": 0,
          "serverNames": [
            "$SNI_DOMAIN"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
}

test_xray_config() {
  echo ""
  echo "正在检测 Xray 配置..."

  if "$XRAY_BIN" run -test -config "$XRAY_CONFIG"; then
    echo "配置检测通过"
  else
    echo "错误：Xray 配置检测失败"
    exit 1
  fi
}

install_reality() {
  check_system
  install_base_packages
  install_xray

  echo ""
  echo "请选择 Reality 安装模式："
  echo "1) 自定义端口 / SNI / 指纹 / 节点名称"
  echo "2) 随机端口 / 默认 SNI"
  echo ""

  read -p "请输入选项 [1/2]，默认 2: " MODE
  MODE=${MODE:-2}

  if [ "$MODE" = "1" ]; then
    read -p "请输入 VLESS 端口，必须 >=10000: " VLESS_PORT
    read -p "请输入 SNI 域名，默认 $DEFAULT_SNI: " SNI_DOMAIN
    read -p "请输入浏览器指纹，默认 $DEFAULT_FP: " FINGERPRINT
    read -p "请输入节点名称，默认 $DEFAULT_NODE_NAME: " NODE_NAME

    SNI_DOMAIN=${SNI_DOMAIN:-$DEFAULT_SNI}
    FINGERPRINT=${FINGERPRINT:-$DEFAULT_FP}
    NODE_NAME=${NODE_NAME:-$DEFAULT_NODE_NAME}
  else
    VLESS_PORT=$(random_port)
    SNI_DOMAIN="$DEFAULT_SNI"
    FINGERPRINT="$DEFAULT_FP"
    NODE_NAME="$DEFAULT_NODE_NAME"
  fi

  validate_port "$VLESS_PORT"

  generate_uuid
  generate_reality_keys
  SHORT_ID=$(random_short_id)

  write_xray_config
  test_xray_config
  open_firewall_tcp "$VLESS_PORT"

  echo ""
  echo "正在启动 Xray..."
  systemctl restart "$XRAY_SERVICE"
  systemctl enable "$XRAY_SERVICE" >/dev/null 2>&1 || true

  sleep 2

  if ! systemctl is-active --quiet "$XRAY_SERVICE"; then
    echo "错误：Xray 启动失败"
    journalctl -u "$XRAY_SERVICE" -n 80 --no-pager
    exit 1
  fi

  IP=$(get_public_ip)
  NODE_NAME_ENCODED=$(printf '%s' "$NODE_NAME" | sed 's/ /%20/g')
  VLESS_URL="vless://$UUID@$IP:$VLESS_PORT?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=$SNI_DOMAIN&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=$FINGERPRINT#$NODE_NAME_ENCODED"

  echo ""
  echo "======================================"
  echo " VLESS + Reality + Vision 安装完成"
  echo "======================================"
  echo "服务器 IP：$IP"
  echo "端口：$VLESS_PORT"
  echo "UUID：$UUID"
  echo "协议：VLESS"
  echo "传输：TCP"
  echo "安全：Reality"
  echo "Flow：xtls-rprx-vision"
  echo "SNI：$SNI_DOMAIN"
  echo "Fingerprint：$FINGERPRINT"
  echo "Public Key：$PUBLIC_KEY"
  echo "Short ID：$SHORT_ID"
  echo "节点名称：$NODE_NAME"
  echo ""
  echo "VLESS 分享链接："
  echo "$VLESS_URL"
  echo ""
  echo "Shadowrocket 手动填写："
  echo "类型：VLESS"
  echo "服务器：$IP"
  echo "端口：$VLESS_PORT"
  echo "UUID：$UUID"
  echo "加密：none"
  echo "传输协议：TCP"
  echo "TLS / 安全：Reality"
  echo "Flow：xtls-rprx-vision"
  echo "SNI：$SNI_DOMAIN"
  echo "Public Key：$PUBLIC_KEY"
  echo "Short ID：$SHORT_ID"
  echo "Fingerprint：$FINGERPRINT"
  echo ""
  echo "Mihomo / Clash Meta 配置："
  echo "- name: $NODE_NAME"
  echo "  type: vless"
  echo "  server: $IP"
  echo "  port: $VLESS_PORT"
  echo "  uuid: $UUID"
  echo "  network: tcp"
  echo "  tls: true"
  echo "  udp: true"
  echo "  flow: xtls-rprx-vision"
  echo "  servername: $SNI_DOMAIN"
  echo "  client-fingerprint: $FINGERPRINT"
  echo "  reality-opts:"
  echo "    public-key: $PUBLIC_KEY"
  echo "    short-id: $SHORT_ID"
  echo ""
  echo "开机自启：已开启"
  echo "======================================"
}

status_reality() {
  echo "======================================"
  echo " VLESS Reality 状态"
  echo "======================================"
  systemctl status "$XRAY_SERVICE" --no-pager || true

  echo ""
  echo "监听端口："
  ss -lntup | grep xray || true

  echo ""
  echo "最近日志："
  journalctl -u "$XRAY_SERVICE" -n 50 --no-pager || true
}

restart_reality() {
  echo "正在重启 Xray Reality..."
  systemctl restart "$XRAY_SERVICE"

  if systemctl is-active --quiet "$XRAY_SERVICE"; then
    echo "Reality 重启成功"
  else
    echo "Reality 重启失败"
    journalctl -u "$XRAY_SERVICE" -n 80 --no-pager
  fi
}

uninstall_reality() {
  echo "警告：即将卸载 Xray Reality"
  echo "这会删除 Xray 程序和配置文件"
  read -p "确认卸载吗？输入 y 确认: " CONFIRM

  if [ "$CONFIRM" != "y" ]; then
    echo "已取消卸载"
    exit 0
  fi

  systemctl stop "$XRAY_SERVICE" 2>/dev/null || true
  systemctl disable "$XRAY_SERVICE" 2>/dev/null || true

  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge || true

  echo "Xray Reality 已卸载"
}

# ==============================
# 主菜单
# ==============================

main_menu() {
  echo "请选择操作："
  echo "1) 安装 / 重装 SOCKS5 / SK5"
  echo "2) 安装 / 重装 SS2022"
  echo "3) 安装 / 重装 VLESS + Reality + Vision"
  echo ""
  echo "4) 查看 SOCKS5 / SK5 状态"
  echo "5) 查看 SS2022 状态"
  echo "6) 查看 VLESS Reality 状态"
  echo ""
  echo "7) 重启 SOCKS5 / SK5"
  echo "8) 重启 SS2022"
  echo "9) 重启 VLESS Reality"
  echo ""
  echo "10) 卸载 SOCKS5 / SK5"
  echo "11) 卸载 SS2022"
  echo "12) 卸载 VLESS Reality"
  echo ""

  read -p "请输入选项 [1-12]，默认 1: " ACTION
  ACTION=${ACTION:-1}

  case "$ACTION" in
    1)
      install_socks5
      ;;
    2)
      install_ss2022
      ;;
    3)
      install_reality
      ;;
    4)
      status_socks5
      ;;
    5)
      status_ss2022
      ;;
    6)
      status_reality
      ;;
    7)
      restart_socks5
      ;;
    8)
      restart_ss2022
      ;;
    9)
      restart_reality
      ;;
    10)
      uninstall_socks5
      ;;
    11)
      uninstall_ss2022
      ;;
    12)
      uninstall_reality
      ;;
    *)
      echo "无效选项"
      exit 1
      ;;
  esac
}

main_menu
