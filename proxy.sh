#!/bin/bash

set -e

RANDOM_PORT_MIN=10000
RANDOM_PORT_MAX=65535

SOCKS_CONFIG="/etc/danted.conf"
SOCKS_SERVICE="danted"

SS_CONTAINER="ss2022-server"
SS_IMAGE="ghcr.io/shadowsocks/ssserver-rust:latest"
SS_METHOD="2022-blake3-aes-128-gcm"

XRAY_SERVICE="xray"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
DEFAULT_SNI="www.paypal.com"
DEFAULT_FP="chrome"
DEFAULT_NODE_NAME="VLESS-Reality"

HY2_SERVICE="hysteria-server.service"
HY2_BIN="/usr/local/bin/hysteria"
HY2_CONFIG="/etc/hysteria/config.yaml"
HY2_CERT="/etc/hysteria/server.crt"
HY2_KEY="/etc/hysteria/server.key"
DEFAULT_HY2_SNI="bing.com"

clear
echo "======================================"
echo " 四合一代理一键管理脚本"
echo " 1. SOCKS5 / SK5"
echo " 2. SS2022"
echo " 3. VLESS + Reality + Vision + TCP"
echo " 4. Hysteria2 / HY2"
echo " 随机端口范围：${RANDOM_PORT_MIN}-${RANDOM_PORT_MAX}"
echo " 节点命名：国家-地区-城市-IP"
echo " 支持：绿色二维码 + BBR + 上海时间"
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
    echo "错误：无法识别系统"
    exit 1
  fi

  case "$OS_NAME" in
    ubuntu|debian)
      echo "系统检测通过：$PRETTY_NAME"
      ;;
    *)
      echo "提醒：当前系统可能不是 Ubuntu / Debian，脚本仍会尝试继续安装"
      ;;
  esac
}

install_base_packages() {
  echo ""
  echo "正在安装基础依赖..."

  apt update -y
  apt install -y curl wget unzip socat cron ufw net-tools iproute2 procps openssl ca-certificates qrencode jq
}

set_shanghai_time() {
  echo ""
  echo "正在设置系统时区为 Asia/Shanghai..."

  timedatectl set-timezone Asia/Shanghai 2>/dev/null || true
  timedatectl set-ntp true 2>/dev/null || true

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable systemd-timesyncd >/dev/null 2>&1 || true
    systemctl restart systemd-timesyncd 2>/dev/null || true
  fi

  echo "当前时间：$(date "+%Y-%m-%d %H:%M:%S")"
  timedatectl 2>/dev/null | grep "Time zone" || true
}

enable_bbr() {
  echo ""
  echo "正在开启 BBR..."

  modprobe tcp_bbr 2>/dev/null || true

  cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

  sysctl --system >/dev/null 2>&1 || true

  CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
  CURRENT_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)

  echo "当前拥塞控制算法：$CURRENT_CC"
  echo "当前队列算法：$CURRENT_QDISC"
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

install_hysteria_core() {
  echo ""
  echo "正在安装 / 更新 Hysteria2..."

  bash <(curl -fsSL https://get.hy2.sh/)

  if [ ! -f "$HY2_BIN" ]; then
    echo "错误：Hysteria2 安装失败，未找到 $HY2_BIN"
    exit 1
  fi

  echo "Hysteria2 安装完成：$($HY2_BIN version 2>/dev/null | head -n 1 || echo installed)"
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

sanitize_name() {
  echo "$1" | tr ' ' '-' | tr -cd 'A-Za-z0-9._-'
}

get_ipinfo() {
  IPINFO_JSON=$(curl -4 -s --max-time 10 https://ipinfo.io/json || true)

  PUBLIC_IP=""
  IP_COUNTRY=""
  IP_REGION=""
  IP_CITY=""

  if command -v jq >/dev/null 2>&1 && [ -n "$IPINFO_JSON" ]; then
    PUBLIC_IP=$(echo "$IPINFO_JSON" | jq -r '.ip // empty')
    IP_COUNTRY=$(echo "$IPINFO_JSON" | jq -r '.country // empty')
    IP_REGION=$(echo "$IPINFO_JSON" | jq -r '.region // empty')
    IP_CITY=$(echo "$IPINFO_JSON" | jq -r '.city // empty')
  fi

  if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -4 -s --max-time 8 https://api.ipify.org || true)
  fi

  if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -4 -s --max-time 8 https://ipv4.icanhazip.com || true)
  fi

  if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -4 -s --max-time 8 https://ifconfig.me || true)
  fi

  if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(hostname -I | awk '{print $1}')
  fi

  IP_COUNTRY=${IP_COUNTRY:-UnknownCountry}
  IP_REGION=${IP_REGION:-UnknownRegion}
  IP_CITY=${IP_CITY:-UnknownCity}
}

generate_node_name_by_ipinfo() {
  get_ipinfo

  CLEAN_COUNTRY=$(sanitize_name "$IP_COUNTRY")
  CLEAN_REGION=$(sanitize_name "$IP_REGION")
  CLEAN_CITY=$(sanitize_name "$IP_CITY")
  CLEAN_IP=$(sanitize_name "$PUBLIC_IP")

  if [ -n "$CLEAN_COUNTRY" ] && [ -n "$CLEAN_REGION" ] && [ -n "$CLEAN_CITY" ] && [ -n "$CLEAN_IP" ]; then
    AUTO_NODE_NAME="${CLEAN_COUNTRY}-${CLEAN_REGION}-${CLEAN_CITY}-${CLEAN_IP}"
  elif [ -n "$CLEAN_COUNTRY" ] && [ -n "$CLEAN_CITY" ] && [ -n "$CLEAN_IP" ]; then
    AUTO_NODE_NAME="${CLEAN_COUNTRY}-${CLEAN_CITY}-${CLEAN_IP}"
  elif [ -n "$CLEAN_COUNTRY" ] && [ -n "$CLEAN_IP" ]; then
    AUTO_NODE_NAME="${CLEAN_COUNTRY}-${CLEAN_IP}"
  else
    AUTO_NODE_NAME="$DEFAULT_NODE_NAME"
  fi
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

  echo "提醒：云后台安全组也要放行 TCP $PORT_TO_OPEN"
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

  echo "提醒：云后台安全组也要放行 TCP/UDP $PORT_TO_OPEN"
}

get_default_interface() {
  INTERFACE=$(ip route | awk '/default/ {print $5; exit}')

  if [ -z "$INTERFACE" ]; then
    echo "错误：无法识别默认网卡"
    exit 1
  fi

  echo "$INTERFACE"
}

url_encode_node_name() {
  NODE_NAME_ENCODED=$(printf '%s' "$NODE_NAME" | sed 's/ /%20/g')
}

show_qrcode() {
  QR_CONTENT="$1"

  if command -v qrencode >/dev/null 2>&1; then
    echo ""
    echo "请用手机代理软件扫码导入："
    echo ""
    echo -e "\033[32m"
    echo "$QR_CONTENT" | qrencode -t ANSIUTF8 -m 2
    echo -e "\033[0m"
    echo ""
    echo "如果二维码不完整，请放大终端窗口，或复制链接导入。"
  else
    echo "未安装 qrencode，无法显示二维码"
  fi
}

show_common_status() {
  get_ipinfo

  echo ""
  echo "IP 信息："
  echo "服务器 IP：$PUBLIC_IP"
  echo "识别国家：$IP_COUNTRY"
  echo "识别地区：$IP_REGION"
  echo "识别城市：$IP_CITY"

  echo ""
  echo "BBR 状态："
  sysctl net.ipv4.tcp_congestion_control 2>/dev/null || true
  sysctl net.core.default_qdisc 2>/dev/null || true

  echo ""
  echo "系统时间："
  date "+%Y-%m-%d %H:%M:%S"
  timedatectl 2>/dev/null | grep "Time zone" || true
  timedatectl 2>/dev/null | grep "System clock synchronized" || true
  timedatectl 2>/dev/null | grep "NTP service" || true
}

prepare_env() {
  check_system
  install_base_packages
  set_shanghai_time
  enable_bbr
}

install_socks5() {
  prepare_env

  echo ""
  echo "正在安装 Dante SOCKS5..."
  apt install -y dante-server

  generate_node_name_by_ipinfo
  DEFAULT_SOCKS_NAME="$AUTO_NODE_NAME"

  echo ""
  echo "请选择 SOCKS5 安装模式："
  echo "1) 自定义端口 / 账号 / 密码 / 节点名称"
  echo "2) 随机端口 / 随机账号 / 随机密码 / 自动节点名"
  echo ""

  read -r -p "请输入选项 [1/2]，默认 2: " MODE
  MODE=$(echo "$MODE" | tr -d '\r' | xargs)
  MODE=${MODE:-2}

  if [ "$MODE" = "1" ]; then
    read -r -p "请输入 SOCKS5 端口，必须 >=10000: " SOCKS_PORT
    read -r -p "请输入 SOCKS5 用户名: " SOCKS_USER
    read -s -p "请输入 SOCKS5 密码: " SOCKS_PASS
    echo ""
    read -r -p "请输入节点名称，默认 $DEFAULT_SOCKS_NAME: " NODE_NAME

    NODE_NAME=${NODE_NAME:-$DEFAULT_SOCKS_NAME}
  else
    SOCKS_PORT=$(random_port)
    SOCKS_USER=$(random_user)
    SOCKS_PASS=$(random_pass)
    NODE_NAME="$DEFAULT_SOCKS_NAME"
  fi

  if [ -z "$SOCKS_PORT" ] || [ -z "$SOCKS_USER" ] || [ -z "$SOCKS_PASS" ]; then
    echo "错误：端口、用户名、密码不能为空"
    exit 1
  fi

  validate_port "$SOCKS_PORT"

  if id "$SOCKS_USER" >/dev/null 2>&1; then
    echo "用户已存在，正在更新密码"
  else
    useradd -r -s /usr/sbin/nologin "$SOCKS_USER"
  fi

  echo "$SOCKS_USER:$SOCKS_PASS" | chpasswd

  INTERFACE=$(get_default_interface)

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

  systemctl restart "$SOCKS_SERVICE"
  systemctl enable "$SOCKS_SERVICE" >/dev/null 2>&1 || true

  sleep 1

  if ! systemctl is-active --quiet "$SOCKS_SERVICE"; then
    echo "错误：Dante 启动失败"
    journalctl -u "$SOCKS_SERVICE" -n 80 --no-pager
    exit 1
  fi

  get_ipinfo
  IP="$PUBLIC_IP"
  url_encode_node_name

  SOCKS_URL="socks5://$SOCKS_USER:$SOCKS_PASS@$IP:$SOCKS_PORT#$NODE_NAME_ENCODED"

  echo ""
  echo "======================================"
  echo " SOCKS5 / SK5 安装完成"
  echo "======================================"
  echo "服务器 IP：$IP"
  echo "识别国家：$IP_COUNTRY"
  echo "识别地区：$IP_REGION"
  echo "识别城市：$IP_CITY"
  echo "端口：$SOCKS_PORT"
  echo "用户名：$SOCKS_USER"
  echo "密码：$SOCKS_PASS"
  echo "节点名称：$NODE_NAME"
  echo ""
  echo "SOCKS5 分享链接："
  echo "$SOCKS_URL"
  echo ""
  echo "SOCKS5 绿色二维码："
  show_qrcode "$SOCKS_URL"
  echo ""
  echo "测试命令："
  echo "curl -x socks5://$SOCKS_USER:$SOCKS_PASS@$IP:$SOCKS_PORT https://ipinfo.io"
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

  echo ""
  echo "配置文件："
  if [ -f "$SOCKS_CONFIG" ]; then
    cat "$SOCKS_CONFIG"
  else
    echo "未找到 $SOCKS_CONFIG"
  fi

  show_common_status
}

restart_socks5() {
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
  read -r -p "确认卸载吗？输入 y 确认: " CONFIRM

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

install_ss2022() {
  prepare_env
  install_docker

  generate_node_name_by_ipinfo
  DEFAULT_SS_NAME="$AUTO_NODE_NAME"

  echo ""
  echo "请选择 SS2022 安装模式："
  echo "1) 自定义端口 / 自定义密钥 / 节点名称"
  echo "2) 随机端口 / 随机密钥 / 自动节点名"
  echo ""

  read -r -p "请输入选项 [1/2]，默认 2: " MODE
  MODE=$(echo "$MODE" | tr -d '\r' | xargs)
  MODE=${MODE:-2}

  if [ "$MODE" = "1" ]; then
    read -r -p "请输入 SS2022 端口，必须 >=10000: " SS_PORT
    read -r -p "请输入自定义密钥，留空则自动生成: " SS_KEY
    read -r -p "请输入节点名称，默认 $DEFAULT_SS_NAME: " NODE_NAME

    SS_KEY=${SS_KEY:-$(random_key)}
    NODE_NAME=${NODE_NAME:-$DEFAULT_SS_NAME}
  else
    SS_PORT=$(random_port)
    SS_KEY=$(random_key)
    NODE_NAME="$DEFAULT_SS_NAME"
  fi

  validate_port "$SS_PORT"
  open_firewall_tcp_udp "$SS_PORT"

  docker pull "$SS_IMAGE"

  if docker ps -a --format '{{.Names}}' | grep -q "^${SS_CONTAINER}$"; then
    docker stop "$SS_CONTAINER" >/dev/null 2>&1 || true
    docker rm "$SS_CONTAINER" >/dev/null 2>&1 || true
  fi

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

  get_ipinfo
  IP="$PUBLIC_IP"
  url_encode_node_name

  SS_USERINFO=$(printf "%s:%s" "$SS_METHOD" "$SS_KEY" | base64 -w 0 2>/dev/null || printf "%s:%s" "$SS_METHOD" "$SS_KEY" | base64 | tr -d '\n')
  SS_URL="ss://$SS_USERINFO@$IP:$SS_PORT#$NODE_NAME_ENCODED"

  echo ""
  echo "======================================"
  echo " SS2022 安装完成"
  echo "======================================"
  echo "服务器 IP：$IP"
  echo "识别国家：$IP_COUNTRY"
  echo "识别地区：$IP_REGION"
  echo "识别城市：$IP_CITY"
  echo "端口：$SS_PORT"
  echo "加密方式：$SS_METHOD"
  echo "密码 / 密钥：$SS_KEY"
  echo "节点名称：$NODE_NAME"
  echo ""
  echo "SS URI："
  echo "$SS_URL"
  echo ""
  echo "SS2022 绿色二维码："
  show_qrcode "$SS_URL"
  echo ""
  echo "Mihomo / Clash Meta 配置："
  echo "- name: $NODE_NAME"
  echo "  type: ss"
  echo "  server: $IP"
  echo "  port: $SS_PORT"
  echo "  cipher: $SS_METHOD"
  echo "  password: $SS_KEY"
  echo "  udp: true"
  echo "======================================"
}

status_ss2022() {
  echo "======================================"
  echo " SS2022 状态"
  echo "======================================"

  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker 未安装"
    return
  fi

  if docker ps -a --format '{{.Names}}' | grep -q "^${SS_CONTAINER}$"; then
    docker ps -a | grep "$SS_CONTAINER" || true
    echo ""
    docker logs --tail 50 "$SS_CONTAINER" || true
  else
    echo "未找到 SS2022 容器"
  fi

  show_common_status
}

restart_ss2022() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker 未安装"
    return
  fi

  docker restart "$SS_CONTAINER"
  echo "SS2022 重启完成"
}

uninstall_ss2022() {
  echo "警告：即将卸载 SS2022"
  read -r -p "确认卸载吗？输入 y 确认: " CONFIRM

  if [ "$CONFIRM" != "y" ]; then
    echo "已取消卸载"
    exit 0
  fi

  if command -v docker >/dev/null 2>&1; then
    docker stop "$SS_CONTAINER" >/dev/null 2>&1 || true
    docker rm "$SS_CONTAINER" >/dev/null 2>&1 || true
  fi

  echo "SS2022 容器已卸载，Docker 本身未卸载。"
}

generate_uuid() {
  UUID=$($XRAY_BIN uuid 2>&1 | tr -d '[:space:]')

  if [ -z "$UUID" ]; then
    echo "错误：UUID 生成失败"
    exit 1
  fi
}

generate_reality_keys() {
  echo ""
  echo "正在生成 Reality 密钥..."

  KEY_OUTPUT=$($XRAY_BIN x25519 2>&1 || true)

  PRIVATE_KEY=$(echo "$KEY_OUTPUT" | awk -F': ' '/PrivateKey/ {print $2; exit}')
  PUBLIC_KEY=$(echo "$KEY_OUTPUT" | awk -F': ' '/PublicKey/ {print $2; exit}')

  PRIVATE_KEY=$(echo "$PRIVATE_KEY" | tr -d '[:space:]')
  PUBLIC_KEY=$(echo "$PUBLIC_KEY" | tr -d '[:space:]')

  if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "错误：Reality 密钥生成失败"
    echo "$KEY_OUTPUT"
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
  if "$XRAY_BIN" run -test -config "$XRAY_CONFIG"; then
    echo "Xray 配置检测通过"
  else
    echo "错误：Xray 配置检测失败"
    exit 1
  fi
}

start_xray() {
  systemctl restart "$XRAY_SERVICE"
  systemctl enable "$XRAY_SERVICE" >/dev/null 2>&1 || true

  sleep 2

  if systemctl is-active --quiet "$XRAY_SERVICE"; then
    echo "Xray 启动成功"
  else
    echo "错误：Xray 启动失败"
    journalctl -u "$XRAY_SERVICE" -n 80 --no-pager
    exit 1
  fi
}

install_reality() {
  prepare_env
  install_xray
  generate_node_name_by_ipinfo

  echo ""
  echo "请选择 Reality 安装模式："
  echo "1) 自定义端口 / SNI / 指纹 / 节点名称"
  echo "2) 随机端口 / 默认 SNI / 自动节点名"
  echo ""

  read -r -p "请输入选项 [1/2]，默认 2: " MODE
  MODE=$(echo "$MODE" | tr -d '\r' | xargs)
  MODE=${MODE:-2}

  if [ "$MODE" = "1" ]; then
    read -r -p "请输入 VLESS 端口，必须 >=10000: " VLESS_PORT
    read -r -p "请输入 SNI 域名，默认 $DEFAULT_SNI: " SNI_DOMAIN
    read -r -p "请输入浏览器指纹，默认 $DEFAULT_FP: " FINGERPRINT
    read -r -p "请输入节点名称，默认 $AUTO_NODE_NAME: " NODE_NAME

    SNI_DOMAIN=${SNI_DOMAIN:-$DEFAULT_SNI}
    FINGERPRINT=${FINGERPRINT:-$DEFAULT_FP}
    NODE_NAME=${NODE_NAME:-$AUTO_NODE_NAME}
  else
    VLESS_PORT=$(random_port)
    SNI_DOMAIN="$DEFAULT_SNI"
    FINGERPRINT="$DEFAULT_FP"
    NODE_NAME="$AUTO_NODE_NAME"
  fi

  validate_port "$VLESS_PORT"

  generate_uuid
  generate_reality_keys
  SHORT_ID=$(random_short_id)

  write_xray_config
  test_xray_config
  open_firewall_tcp "$VLESS_PORT"
  start_xray

  get_ipinfo
  IP="$PUBLIC_IP"
  url_encode_node_name

  VLESS_URL="vless://$UUID@$IP:$VLESS_PORT?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=$SNI_DOMAIN&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=$FINGERPRINT#$NODE_NAME_ENCODED"

  echo ""
  echo "======================================"
  echo " VLESS + Reality + Vision 安装完成"
  echo "======================================"
  echo "服务器 IP：$IP"
  echo "识别国家：$IP_COUNTRY"
  echo "识别地区：$IP_REGION"
  echo "识别城市：$IP_CITY"
  echo "端口：$VLESS_PORT"
  echo "UUID：$UUID"
  echo "SNI：$SNI_DOMAIN"
  echo "Public Key：$PUBLIC_KEY"
  echo "Short ID：$SHORT_ID"
  echo "节点名称：$NODE_NAME"
  echo ""
  echo "VLESS 分享链接："
  echo "$VLESS_URL"
  echo ""
  echo "VLESS 绿色二维码："
  show_qrcode "$VLESS_URL"
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

  echo ""
  echo "配置文件路径：$XRAY_CONFIG"

  show_common_status
}

restart_reality() {
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
  read -r -p "确认卸载吗？输入 y 确认: " CONFIRM

  if [ "$CONFIRM" != "y" ]; then
    echo "已取消卸载"
    exit 0
  fi

  systemctl stop "$XRAY_SERVICE" 2>/dev/null || true
  systemctl disable "$XRAY_SERVICE" 2>/dev/null || true
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge || true

  echo "Xray Reality 已卸载"
}

fix_hy2_permissions() {
  mkdir -p /etc/hysteria

  if id hysteria >/dev/null 2>&1; then
    chown -R hysteria:hysteria /etc/hysteria
  fi

  chmod 755 /etc/hysteria 2>/dev/null || true
  chmod 644 "$HY2_CONFIG" 2>/dev/null || true
  chmod 644 "$HY2_CERT" 2>/dev/null || true
  chmod 600 "$HY2_KEY" 2>/dev/null || true
}

generate_hy2_cert() {
  echo ""
  echo "正在生成 Hysteria2 自签证书..."

  mkdir -p /etc/hysteria

  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$HY2_KEY" \
    -out "$HY2_CERT" \
    -subj "/CN=$HY2_SNI" \
    -days 36500 >/dev/null 2>&1

  if [ ! -f "$HY2_CERT" ] || [ ! -f "$HY2_KEY" ]; then
    echo "错误：Hysteria2 证书生成失败"
    exit 1
  fi

  fix_hy2_permissions

  echo "Hysteria2 证书生成完成，权限已修复"
}

write_hy2_config() {
  echo ""
  echo "正在写入 Hysteria2 配置..."

  mkdir -p /etc/hysteria

  cat > "$HY2_CONFIG" <<EOF
listen: :$HY2_PORT

tls:
  cert: $HY2_CERT
  key: $HY2_KEY

auth:
  type: password
  password: $HY2_PASS

obfs:
  type: salamander
  salamander:
    password: $HY2_OBFS_PASS

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

  fix_hy2_permissions

  echo "Hysteria2 配置写入完成，权限已修复"
}

start_hy2() {
  echo ""
  echo "正在启动 Hysteria2..."

  fix_hy2_permissions

  systemctl daemon-reload
  systemctl restart "$HY2_SERVICE"
  systemctl enable "$HY2_SERVICE" >/dev/null 2>&1 || true

  sleep 2

  if systemctl is-active --quiet "$HY2_SERVICE"; then
    echo "Hysteria2 启动成功"
  else
    echo "错误：Hysteria2 启动失败，请查看日志："
    journalctl -u "$HY2_SERVICE" -n 100 --no-pager
    exit 1
  fi
}

install_hy2() {
  prepare_env
  install_hysteria_core
  generate_node_name_by_ipinfo

  echo ""
  echo "请选择 Hysteria2 安装模式："
  echo "1) 自定义端口 / 密码 / SNI / 节点名称"
  echo "2) 随机端口 / 随机密码 / 默认 SNI / 自动节点名"
  echo ""

  read -r -p "请输入选项 [1/2]，默认 2: " MODE
  MODE=$(echo "$MODE" | tr -d '\r' | xargs)
  MODE=${MODE:-2}

  if [ "$MODE" = "1" ]; then
    read -r -p "请输入 Hysteria2 端口，必须 >=10000: " HY2_PORT
    read -r -p "请输入 Hysteria2 密码，留空自动生成: " HY2_PASS
    read -r -p "请输入 Hysteria2 混淆密码，留空自动生成: " HY2_OBFS_PASS
    read -r -p "请输入 SNI，默认 $DEFAULT_HY2_SNI: " HY2_SNI
    read -r -p "请输入节点名称，默认 $AUTO_NODE_NAME: " NODE_NAME

    HY2_PASS=${HY2_PASS:-$(random_pass)}
    HY2_OBFS_PASS=${HY2_OBFS_PASS:-$(random_pass)}
    HY2_SNI=${HY2_SNI:-$DEFAULT_HY2_SNI}
    NODE_NAME=${NODE_NAME:-$AUTO_NODE_NAME}
  else
    HY2_PORT=$(random_port)
    HY2_PASS=$(random_pass)
    HY2_OBFS_PASS=$(random_pass)
    HY2_SNI="$DEFAULT_HY2_SNI"
    NODE_NAME="$AUTO_NODE_NAME"
  fi

  validate_port "$HY2_PORT"

  generate_hy2_cert
  write_hy2_config
  fix_hy2_permissions
  open_firewall_tcp_udp "$HY2_PORT"
  start_hy2

  get_ipinfo
  IP="$PUBLIC_IP"
  url_encode_node_name

  HY2_URL="hysteria2://$HY2_PASS@$IP:$HY2_PORT?sni=$HY2_SNI&insecure=1&obfs=salamander&obfs-password=$HY2_OBFS_PASS#$NODE_NAME_ENCODED"

  echo ""
  echo "======================================"
  echo " Hysteria2 / HY2 安装完成"
  echo "======================================"
  echo "服务器 IP：$IP"
  echo "识别国家：$IP_COUNTRY"
  echo "识别地区：$IP_REGION"
  echo "识别城市：$IP_CITY"
  echo "端口：$HY2_PORT"
  echo "密码：$HY2_PASS"
  echo "SNI：$HY2_SNI"
  echo "混淆：salamander"
  echo "混淆密码：$HY2_OBFS_PASS"
  echo "节点名称：$NODE_NAME"
  echo ""
  echo "Hysteria2 分享链接："
  echo "$HY2_URL"
  echo ""
  echo "Hysteria2 绿色二维码："
  show_qrcode "$HY2_URL"
  echo ""
  echo "Mihomo / Clash Meta 配置："
  echo "- name: $NODE_NAME"
  echo "  type: hysteria2"
  echo "  server: $IP"
  echo "  port: $HY2_PORT"
  echo "  password: $HY2_PASS"
  echo "  sni: $HY2_SNI"
  echo "  skip-cert-verify: true"
  echo "  obfs: salamander"
  echo "  obfs-password: $HY2_OBFS_PASS"
  echo "  udp: true"
  echo ""
  echo "重要提醒：Hysteria2 主要依赖 UDP，云后台安全组必须放行 UDP $HY2_PORT"
  echo "======================================"
}

status_hy2() {
  echo "======================================"
  echo " Hysteria2 / HY2 状态"
  echo "======================================"

  systemctl status "$HY2_SERVICE" --no-pager || true

  echo ""
  echo "监听端口："
  ss -lntup | grep hysteria || true

  echo ""
  echo "最近日志："
  journalctl -u "$HY2_SERVICE" -n 50 --no-pager || true

  echo ""
  echo "配置文件路径：$HY2_CONFIG"

  if [ -f "$HY2_CONFIG" ]; then
    echo ""
    cat "$HY2_CONFIG"
  fi

  show_common_status
}

restart_hy2() {
  fix_hy2_permissions
  systemctl daemon-reload
  systemctl restart "$HY2_SERVICE"

  if systemctl is-active --quiet "$HY2_SERVICE"; then
    echo "Hysteria2 重启成功"
  else
    echo "Hysteria2 重启失败"
    journalctl -u "$HY2_SERVICE" -n 100 --no-pager
  fi
}

uninstall_hy2() {
  echo "警告：即将卸载 Hysteria2 / HY2"
  read -r -p "确认卸载吗？输入 y 确认: " CONFIRM

  if [ "$CONFIRM" != "y" ]; then
    echo "已取消卸载"
    exit 0
  fi

  systemctl stop "$HY2_SERVICE" 2>/dev/null || true
  systemctl disable "$HY2_SERVICE" 2>/dev/null || true

  bash <(curl -fsSL https://get.hy2.sh/) --remove || true

  rm -rf /etc/hysteria

  echo "Hysteria2 / HY2 已卸载"
}

main_menu() {
  echo "请选择操作："
  echo "1) 安装 / 重装 SOCKS5 / SK5"
  echo "2) 安装 / 重装 SS2022"
  echo "3) 安装 / 重装 VLESS + Reality + Vision"
  echo "4) 安装 / 重装 Hysteria2 / HY2"
  echo ""
  echo "5) 查看 SOCKS5 / SK5 状态"
  echo "6) 查看 SS2022 状态"
  echo "7) 查看 VLESS Reality 状态"
  echo "8) 查看 Hysteria2 / HY2 状态"
  echo ""
  echo "9) 重启 SOCKS5 / SK5"
  echo "10) 重启 SS2022"
  echo "11) 重启 VLESS Reality"
  echo "12) 重启 Hysteria2 / HY2"
  echo ""
  echo "13) 卸载 SOCKS5 / SK5"
  echo "14) 卸载 SS2022"
  echo "15) 卸载 VLESS Reality"
  echo "16) 卸载 Hysteria2 / HY2"
  echo ""

  read -r -p "请输入选项 [1-16]，默认 1: " ACTION
  ACTION=$(echo "$ACTION" | tr -d '\r' | xargs)
  ACTION=${ACTION:-1}

  case "$ACTION" in
    1) install_socks5 ;;
    2) install_ss2022 ;;
    3) install_reality ;;
    4) install_hy2 ;;
    5) status_socks5 ;;
    6) status_ss2022 ;;
    7) status_reality ;;
    8) status_hy2 ;;
    9) restart_socks5 ;;
    10) restart_ss2022 ;;
    11) restart_reality ;;
    12) restart_hy2 ;;
    13) uninstall_socks5 ;;
    14) uninstall_ss2022 ;;
    15) uninstall_reality ;;
    16) uninstall_hy2 ;;
    *)
      echo "无效选项"
      exit 1
      ;;
  esac
}

main_menu
