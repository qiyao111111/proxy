下面是更新后的 **README.md 一键复制版**，已经把项目从三合一改成 **四合一**，加入了 **Hysteria2 / HY2**，并补充了 HY2 的 UDP、安全组、自签证书、权限说明。

直接复制到 GitHub 的 `README.md`。

````markdown
# Proxy 四合一一键脚本

一个适用于 Ubuntu / Debian VPS 的代理协议一键部署与管理脚本，支持：

- SOCKS5 / SK5
- SS2022
- VLESS + Reality + Vision + TCP
- Hysteria2 / HY2

脚本支持自动安装、自动生成配置、自动放行端口、自动设置上海时间、自动开启 BBR、自动识别 IP 地区，并生成可直接导入客户端的分享链接和绿色二维码。

---

## 项目特点

- 一键部署四种常用代理协议
- 支持随机端口，端口范围：`10000-65535`
- 支持自定义端口、账号、密码、密钥、SNI、节点名
- 自动安装基础依赖
- 自动安装 Docker
- 自动安装 Xray Core
- 自动安装 Hysteria2
- 自动设置系统时区为 `Asia/Shanghai`
- 自动开启 BBR
- 自动通过 `ipinfo.io` 识别服务器 IP 地区
- 自动生成统一格式节点名称
- 自动生成分享链接
- 自动生成绿色二维码
- 支持查看状态、重启、卸载

---

## 支持协议

| 协议 | 说明 |
|---|---|
| SOCKS5 / SK5 | 基于 Dante Server，支持用户名和密码认证 |
| SS2022 | 基于 shadowsocks-rust，使用 Docker 部署 |
| VLESS Reality | 基于 Xray Core，Reality + Vision + TCP |
| Hysteria2 / HY2 | 基于 Hysteria2，支持 UDP 加速和 salamander 混淆 |

---

## 节点命名规则

脚本会通过：

```text
https://ipinfo.io/json
````

自动识别服务器出口 IP 的：

* 国家
* 地区
* 城市
* IP 地址

然后自动生成节点名称。

节点命名格式：

```text
国家-地区-城市-IP
```

示例：

```text
TW-Taiwan-Taipei-78.105.182.181
US-California-LosAngeles-69.63.203.61
JP-Tokyo-Tokyo-xxx.xxx.xxx.xxx
```

四个协议统一使用相同命名格式，不额外添加 `SOCKS5`、`SS2022`、`VLESS`、`HY2` 前缀。

---

## 一键运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qiyao111111/proxy/main/proxy.sh)
```

---

## 菜单说明

运行脚本后会出现以下菜单：

```text
请选择操作：
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

---

## 安装 SOCKS5 / SK5

运行脚本后选择：

```text
1
```

安装模式：

```text
1) 自定义端口 / 账号 / 密码 / 节点名称
2) 随机端口 / 随机账号 / 随机密码 / 自动节点名
```

安装完成后会输出：

```text
socks5://用户名:密码@服务器IP:端口#节点名称
```

示例：

```text
socks5://sk5_xxxxxx:password@78.105.182.181:20787#TW-Taiwan-Taipei-78.105.182.181
```

---

## 安装 SS2022

运行脚本后选择：

```text
2
```

安装模式：

```text
1) 自定义端口 / 自定义密钥 / 节点名称
2) 随机端口 / 随机密钥 / 自动节点名
```

安装完成后会输出：

```text
ss://加密信息@服务器IP:端口#节点名称
```

示例：

```text
ss://xxxx@78.105.182.181:45990#TW-Taiwan-Taipei-78.105.182.181
```

---

## 安装 VLESS Reality

运行脚本后选择：

```text
3
```

安装模式：

```text
1) 自定义端口 / SNI / 指纹 / 节点名称
2) 随机端口 / 默认 SNI / 自动节点名
```

默认参数：

```text
SNI：www.paypal.com
Fingerprint：chrome
Flow：xtls-rprx-vision
传输协议：TCP
安全协议：Reality
```

安装完成后会输出：

```text
vless://UUID@服务器IP:端口?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=www.paypal.com&pbk=PublicKey&sid=ShortID&fp=chrome#节点名称
```

示例：

```text
vless://xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx@78.105.182.181:55661?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=www.paypal.com&pbk=PublicKey&sid=ShortID&fp=chrome#TW-Taiwan-Taipei-78.105.182.181
```

---

## 安装 Hysteria2 / HY2

运行脚本后选择：

```text
4
```

安装模式：

```text
1) 自定义端口 / 密码 / SNI / 节点名称
2) 随机端口 / 随机密码 / 默认 SNI / 自动节点名
```

默认参数：

```text
SNI：bing.com
TLS：自签证书
认证方式：password
混淆：salamander
传输特点：主要依赖 UDP
```

安装完成后会输出：

```text
hysteria2://密码@服务器IP:端口?sni=bing.com&insecure=1&obfs=salamander&obfs-password=混淆密码#节点名称
```

示例：

```text
hysteria2://password@78.105.182.181:41847?sni=bing.com&insecure=1&obfs=salamander&obfs-password=obfspassword#TW-Taiwan-Taipei-78.105.182.181
```

---

## 二维码

安装完成后，脚本会自动生成绿色二维码。

如果二维码显示不完整：

* 放大终端窗口
* 或者直接复制分享链接导入客户端

---

## 防火墙和安全组

脚本会尝试自动放行系统防火墙端口。

如果 VPS 服务商有云防火墙 / 安全组，需要手动放行对应端口。

### VLESS Reality

只需要放行：

```text
TCP 端口
```

### SOCKS5 / SS2022

建议放行：

```text
TCP + UDP 端口
```

### Hysteria2 / HY2

必须放行：

```text
TCP + UDP 端口
```

其中最重要的是：

```text
UDP 端口
```

Hysteria2 主要依赖 UDP，如果云后台安全组没有放行 UDP，脚本即使安装成功，客户端也可能无法连接。

---

## 常用检查命令

下载脚本到本地检查：

```bash
curl -fsSL https://raw.githubusercontent.com/qiyao111111/proxy/main/proxy.sh -o /tmp/proxy.sh
bash -n /tmp/proxy.sh
```

运行脚本：

```bash
bash /tmp/proxy.sh
```

查看 Xray 状态：

```bash
systemctl status xray
journalctl -u xray -n 80 --no-pager
```

查看 Dante 状态：

```bash
systemctl status danted
journalctl -u danted -n 80 --no-pager
```

查看 SS2022 容器：

```bash
docker ps -a
docker logs ss2022-server
```

查看 Hysteria2 状态：

```bash
systemctl status hysteria-server.service
journalctl -u hysteria-server.service -n 80 --no-pager
```

查看监听端口：

```bash
ss -lntup
```

查看 BBR 状态：

```bash
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
```

查看系统时间：

```bash
timedatectl
date
```

---

## Hysteria2 权限说明

Hysteria2 官方安装脚本会创建 `hysteria` 系统用户。

本项目会自动修复以下文件权限：

```text
/etc/hysteria/config.yaml
/etc/hysteria/server.crt
/etc/hysteria/server.key
```

如果遇到类似错误：

```text
tls.key: open /etc/hysteria/server.key: permission denied
```

可以手动执行：

```bash
chown -R hysteria:hysteria /etc/hysteria
chmod 755 /etc/hysteria
chmod 644 /etc/hysteria/config.yaml
chmod 644 /etc/hysteria/server.crt
chmod 644 /etc/hysteria/server.key

systemctl daemon-reload
systemctl restart hysteria-server.service
systemctl status hysteria-server.service --no-pager
```

---

## 依赖组件

脚本会自动安装以下组件：

* curl
* wget
* unzip
* socat
* cron
* ufw
* net-tools
* iproute2
* procps
* openssl
* ca-certificates
* qrencode
* jq
* dante-server
* docker
* xray-core
* hysteria2

---

## 推荐系统

推荐使用：

```text
Ubuntu 22.04
Ubuntu 24.04
Debian 11
Debian 12
```

---

## 注意事项

1. 请使用 `root` 用户运行脚本。
2. 随机端口不会低于 `10000`。
3. 如果客户端连接失败，优先检查 VPS 云后台安全组。
4. Reality 对系统时间比较敏感，脚本会自动设置上海时间并开启 NTP。
5. Hysteria2 主要依赖 UDP，必须确认 UDP 端口已经放行。
6. BBR 是网络优化，不是换线路；如果 VPS 线路本身很差，BBR 不能完全解决延迟问题。
7. Reality 服务端配置文件包含私钥，请不要公开：

```text
/usr/local/etc/xray/config.json
```

8. Hysteria2 配置文件包含密码和混淆密码，请不要公开：

```text
/etc/hysteria/config.yaml
```

9. 分享链接和二维码请妥善保存，不要公开泄露。

---

## 卸载说明

运行脚本后选择对应卸载菜单：

```text
13) 卸载 SOCKS5 / SK5
14) 卸载 SS2022
15) 卸载 VLESS Reality
16) 卸载 Hysteria2 / HY2
```

SS2022 卸载时只删除容器，不会卸载 Docker 本身。

---

## 项目定位

本脚本适合个人 VPS 快速部署代理节点，用于测试、学习、网络环境管理和自用节点维护。

请遵守当地法律法规和服务商使用条款。

````

GitHub 仓库简介可以更新成：

```text
Ubuntu/Debian VPS 一键部署 SOCKS5、SS2022、VLESS Reality Vision TCP、Hysteria2 四合一代理脚本，支持自动节点命名、绿色二维码、BBR、上海时间和状态管理。
````
