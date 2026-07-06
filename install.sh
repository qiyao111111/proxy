#!/usr/bin/env bash

set -Ee
set -o pipefail

SCRIPT_PATH="/tmp/proxy.sh"

URLS=(
  "https://cdn.jsdelivr.net/gh/qiyao111111/proxy@main/proxy.sh"
  "https://raw.githubusercontent.com/qiyao111111/proxy/main/proxy.sh"
)

echo "正在下载 Proxy 四合一一键脚本..."

for url in "${URLS[@]}"; do
  echo "尝试下载：$url"
  if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 "$url" -o "$SCRIPT_PATH"; then
    chmod +x "$SCRIPT_PATH"
    echo "下载成功，正在启动脚本..."
    exec bash "$SCRIPT_PATH"
  fi

  echo "当前下载源不可用，准备尝试下一个。"
done

echo "所有下载源都失败，请稍后重试，或检查服务器网络。"
exit 1
