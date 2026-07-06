# Proxy 四合一一键脚本

适用于 Ubuntu / Debian VPS 的代理协议一键部署与管理脚本，支持 SOCKS5 / SK5、SS2022、VLESS Reality Vision TCP、Hysteria2 / HY2。

脚本会自动安装依赖、生成配置、放行端口、设置上海时间、开启 BBR、识别 IP 地区，并输出客户端分享链接和绿色二维码。

## 一键运行

推荐使用 jsDelivr CDN 入口，避免 `raw.githubusercontent.com` 被部分 VPS 出口 IP 临时限流。

```bash
bash <(curl -fsSL https://cdn.jsdelivr.net/gh/qiyao111111/proxy@main/install.sh)
```

备用入口：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qiyao111111/proxy/main/install.sh)
```

如果只想直接运行主脚本：

```bash
bash <(curl -fsSL https://cdn.jsdelivr.net/gh/qiyao111111/proxy@main/proxy.sh)
```

## 项目特点

- 一键部署四种常用代理协议
- 随机端口范围：`10000-65535`
- 支持自定义端口、账号、密码、密钥、SNI、节点名
- 自动安装基础依赖、Docker、Xray Core、Hysteria2
- 自动设置系统时区为 `Asia/Shanghai`
- 自动开启 BBR
- 自动通过 `ipinfo.io` 识别服务器出口 IP 地区
- 自动生成统一格式节点名称
- 自动生成分享链接和绿色二维码
- 支持查看状态、重启、卸载

## 支持协议

| 协议 | 说明 |
|---|---|
| SOCKS5 / SK5 | 基于 Dante Server，支持用户名和密码认证 |
| SS2022 | 基于 shadowsocks-rust，使用 Docker 部署 |
| VLESS Reality | 基于 Xray Core，Reality + Vision + TCP |
| Hysteria2 / HY2 | 基于 Hysteria2，支持 UDP 加速和 salamander 混淆 |

## 菜单说明

```text
1) 安装 / 重装 SOCKS5 / SK5
2) 安装 / 重装 SS2022
3) 安装 / 重装 VLESS + Reality + Vision
4) 安装 / 重装 Hysteria2 / HY2

5) 查看 SOCKS5 / SK5 状态
6) 查看 SS2022 状态
7) 查看 VLESS Reality 状态
8) 查看 Hysteria2 / HY2 状态

9) 重启 SOCKS5 / SK5
10) 重启 SS2022
11) 重启 VLESS Reality
12) 重启 Hysteria2 / HY2

13) 卸载 SOCKS5 / SK5
14) 卸载 SS2022
15) 卸载 VLESS Reality
16) 卸载 Hysteria2 / HY2
```

## 节点命名规则

脚本会通过 `https://ipinfo.io/json` 自动识别服务器出口 IP 的国家、地区、城市和 IP 地址，然后生成节点名称。

```text
国家-地区-城市-IP
```

示例：

```text
TW-Taiwan-Taipei-78.105.182.181
US-California-LosAngeles-69.63.203.61
JP-Tokyo-Tokyo-xxx.xxx.xxx.xxx
```

四个协议统一使用相同命名格式，不额外添加协议前缀。

## 防火墙和安全组

脚本会尝试自动放行系统防火墙端口。如果 VPS 服务商有云防火墙或安全组，还需要在云后台手动放行对应端口。

| 协议 | 需要放行 |
|---|---|
| VLESS Reality | TCP |
| SOCKS5 / SK5 | TCP + UDP |
| SS2022 | TCP + UDP |
| Hysteria2 / HY2 | TCP + UDP，尤其是 UDP |

Hysteria2 主要依赖 UDP。如果云后台没有放行 UDP，脚本即使安装成功，客户端也可能无法连接。

## 常用检查命令

下载脚本到本地检查：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/qiyao111111/proxy@main/proxy.sh -o /tmp/proxy.sh
bash -n /tmp/proxy.sh
```

查看服务状态：

```bash
systemctl status danted --no-pager
systemctl status xray --no-pager
systemctl status hysteria-server.service --no-pager
docker ps -a
```

查看日志：

```bash
journalctl -u danted -n 80 --no-pager
journalctl -u xray -n 80 --no-pager
journalctl -u hysteria-server.service -n 80 --no-pager
docker logs ss2022-server
```

查看监听端口、BBR 和时间：

```bash
ss -lntup
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
timedatectl
date
```

## Hysteria2 权限说明

Hysteria2 官方安装脚本会创建 `hysteria` 系统用户。本项目会自动修复以下文件权限：

```text
/etc/hysteria/config.yaml
/etc/hysteria/server.crt
/etc/hysteria/server.key
```

如果遇到 `permission denied`，可以手动执行：

```bash
chown -R hysteria:hysteria /etc/hysteria
chmod 755 /etc/hysteria
chmod 644 /etc/hysteria/config.yaml
chmod 644 /etc/hysteria/server.crt
chmod 600 /etc/hysteria/server.key
systemctl daemon-reload
systemctl restart hysteria-server.service
```

## 推荐系统

- Ubuntu 22.04
- Ubuntu 24.04
- Debian 11
- Debian 12

## 注意事项

1. 请使用 `root` 用户运行脚本。
2. 随机端口不会低于 `10000`。
3. 如果客户端连接失败，优先检查 VPS 云后台安全组。
4. Reality 对系统时间比较敏感，脚本会自动设置上海时间并开启 NTP。
5. Hysteria2 主要依赖 UDP，必须确认 UDP 端口已经放行。
6. Reality 服务端配置文件包含私钥，请不要公开：`/usr/local/etc/xray/config.json`
7. Hysteria2 配置文件包含密码和混淆密码，请不要公开：`/etc/hysteria/config.yaml`
8. 分享链接和二维码请妥善保存，不要公开泄露。

## 项目简介

Ubuntu/Debian VPS 一键部署 SOCKS5、SS2022、VLESS Reality Vision TCP、Hysteria2 四合一代理脚本，支持自动节点命名、绿色二维码、BBR、上海时间和状态管理。
