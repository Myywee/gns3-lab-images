# 实验二：复杂 Web 部署与 HTTPS

## 1. 实验目标

1. 验证静态资源的缓存策略和跨源资源共享；
2. 观察本地 DNS 覆盖前后，同一域名解析结果的变化；
3. 检查证书链、有效期、SAN 和私钥匹配关系；
4. 配置并验证 HTTPS 和 HTTP 301 跳转；
5. 用抓包区分明文 HTTP、TLS 握手和加密应用数据。

## 2. 阶段与镜像

| 节点 | `lab2-start` | `lab2-complete` |
|---|---|---|
| Web-Server | `ghcr.io/myywee/web-server:lab2-no-https` | `ghcr.io/myywee/web-server:lab2-complete` |
| DNS-Server | `ghcr.io/myywee/dns-server:lab1-complete` | `ghcr.io/myywee/dns-server:lab2-complete` |
| Client1 | `ghcr.io/myywee/client:lab1-complete` | `ghcr.io/myywee/client:lab1-complete` |
| Client2 | `ghcr.io/myywee/client:lab1-no-cache` | `ghcr.io/myywee/client:lab1-no-cache` |
| Administrator | `ghcr.io/myywee/client:lab1-no-cache` | `ghcr.io/myywee/client:lab1-no-cache` |

`lab2-start` 已包含个人主页、HTTP、缓存策略和 CORS，但尚未加入实验二 DNS 区和 HTTPS。`lab2-complete` 是最终检查点。

```bash
docker pull ghcr.io/myywee/web-server:lab2-no-https
docker pull ghcr.io/myywee/web-server:lab2-complete
docker pull ghcr.io/myywee/dns-server:lab1-complete
docker pull ghcr.io/myywee/dns-server:lab2-complete
docker pull ghcr.io/myywee/client:lab1-complete
docker pull ghcr.io/myywee/client:lab1-no-cache
```

## 3. 拓扑、地址与域名

实验二沿用实验一拓扑：

| 节点 | 地址 | 网关 |
|---|---|---|
| DNS-Server | `10.10.20.10/24` | `10.10.20.1` |
| Web-Server | `10.10.20.20/24` | `10.10.20.1` |
| Administrator | `10.10.10.10/24` | `10.10.10.1` |
| Client1 | `10.10.30.10/24` | `10.10.30.1` |
| Client2 | `10.10.30.20/24` | `10.10.30.1` |

Router 的 G0/0、G0/1、G0/2 分别为 `10.10.20.1/24`、`10.10.10.1/24`、`10.10.30.1/24`；G0/3 通过 DHCP 连接 GNS3 NAT，并对三个内网执行 PAT。

若本实验使用全新工程，Router 配置为：

```text
enable
configure terminal
hostname Core-Router
no ip domain-lookup
interface GigabitEthernet0/0
 ip address 10.10.20.1 255.255.255.0
 ip nat inside
 no shutdown
 exit
interface GigabitEthernet0/1
 ip address 10.10.10.1 255.255.255.0
 ip nat inside
 no shutdown
 exit
interface GigabitEthernet0/2
 ip address 10.10.30.1 255.255.255.0
 ip nat inside
 no shutdown
 exit
interface GigabitEthernet0/3
 ip address dhcp
 ip nat outside
 no shutdown
 exit
ip access-list standard NAT_INSIDE
 permit 10.10.10.0 0.0.0.255
 permit 10.10.20.0 0.0.0.255
 permit 10.10.30.0 0.0.0.255
 exit
ip nat inside source list NAT_INSIDE interface GigabitEthernet0/3 overload
ip route 0.0.0.0 0.0.0.0 dhcp
end
write memory
```

实验域名：

```text
networking-experiments.nju-slab.cn
```

## 4. Docker 节点初始化

Client1：

```text
/bin/bash -lc '/gns3/bin/busybox ip link set eth0 up; /gns3/bin/busybox ip addr flush dev eth0; /gns3/bin/busybox ip addr add 10.10.30.10/24 dev eth0; /gns3/bin/busybox ip route replace default via 10.10.30.1 dev eth0; exec /bin/bash'
```

Client2：

```text
/bin/bash -lc '/gns3/bin/busybox ip link set eth0 up; /gns3/bin/busybox ip addr flush dev eth0; /gns3/bin/busybox ip addr add 10.10.30.20/24 dev eth0; /gns3/bin/busybox ip route replace default via 10.10.30.1 dev eth0; exec /bin/bash'
```

Administrator：

```text
/bin/bash -lc '/gns3/bin/busybox ip link set eth0 up; /gns3/bin/busybox ip addr flush dev eth0; /gns3/bin/busybox ip addr add 10.10.10.10/24 dev eth0; /gns3/bin/busybox ip route replace default via 10.10.10.1 dev eth0; exec /bin/bash'
```

DNS-Server：

```text
/bin/bash -lc '/gns3/bin/busybox ip link set eth0 up; /gns3/bin/busybox ip addr flush dev eth0; /gns3/bin/busybox ip addr add 10.10.20.10/24 dev eth0; /gns3/bin/busybox ip route replace default via 10.10.20.1 dev eth0; /usr/sbin/named -u bind -c /etc/bind/named.conf; exec /bin/bash'
```

Web-Server：

```text
/bin/bash -lc '/gns3/bin/busybox ip link set eth0 up; /gns3/bin/busybox ip addr flush dev eth0; /gns3/bin/busybox ip addr add 10.10.20.20/24 dev eth0; /gns3/bin/busybox ip route replace default via 10.10.20.1 dev eth0; /usr/local/lib/gns3/start-web-server.sh >/tmp/start-web-server.log 2>&1 & exec /bin/bash'
```

Client 镜像入口脚本负责 DNS：Client1 使用 `127.0.0.1` 本地缓存，Client2 和 Administrator 直接使用 `10.10.20.10`。不要在 Start command 中覆盖它。

## 5. HTTPS 证书准备

教师应在 GNS3 Docker 宿主机准备只读目录，例如 `/opt/gns3-lab-secrets/lab2-web`：

```text
networking-experiments.nju-slab.cn.fullchain.pem
networking-experiments.nju-slab.cn.key
```

要求：

- 私钥权限为 `0400` 或 `0600`；
- 证书 SAN 包含 `networking-experiments.nju-slab.cn`；
- 宿主目录只读挂载到 Web-Server 的 `/etc/nginx/certs`；
- 不得复制、显示或提交私钥内容。

为了在 start 环境中完成 HTTPS 配置，`lab2-start` 模板也要配置此挂载。

## 6. 实验步骤

### 6.1 启动 `lab2-start`

```bash
# DNS-Server
ss -lnutp | grep ':53'
dig @10.10.20.10 networking-experiments.nju-slab.cn A +short

# Web-Server
ss -lntp | grep ':80'
nginx -t

# Client1：直接指定本地 Web 地址
curl --resolve networking-experiments.nju-slab.cn:80:10.10.20.20 \
  -I http://networking-experiments.nju-slab.cn/
```

此时 DNS-Server 尚未托管实验二区域，对该域名的普通查询会走公网递归；指定地址的 HTTP 请求应访问 `10.10.20.20` 上的实验主页。

### 6.2 检查缓存策略与 CORS

先从首页找到一个 CSS/JS、图片或字体及 HTML 路径，再检查响应头：

```bash
curl --resolve networking-experiments.nju-slab.cn:80:10.10.20.20 \
  -I http://networking-experiments.nju-slab.cn/

curl --resolve networking-experiments.nju-slab.cn:80:10.10.20.20 \
  -I http://networking-experiments.nju-slab.cn/实际静态资源路径
```

| 资源类型 | 预期 `Cache-Control` | 其他预期头部 |
|---|---|---|
| HTML | `no-store, no-cache, must-revalidate` | — |
| CSS/JS | `public, max-age=7200` | — |
| 图片/字体 | `public, max-age=2592000` | `Access-Control-Allow-Origin: *` |
| PDF | `public, max-age=86400` | — |

隐藏文件路径应返回 `403`。

### 6.3 创建本地 DNS 覆盖

在 DNS-Server 的 `/etc/bind/named.conf.local` 末尾加入：

```text
zone "networking-experiments.nju-slab.cn" {
    type master;
    file "/etc/bind/db.networking-experiments.nju-slab.cn";
};
```

创建 `/etc/bind/db.networking-experiments.nju-slab.cn`：

```text
$TTL 300
@       IN      SOA     ns.networking-experiments.nju-slab.cn. admin.networking-experiments.nju-slab.cn. (
                        2026090901
                        3600
                        900
                        604800
                        300 )
@       IN      NS      ns.networking-experiments.nju-slab.cn.
@       IN      A       10.10.20.20
ns      IN      A       10.10.20.10
```

```bash
chown root:bind /etc/bind/db.networking-experiments.nju-slab.cn
chmod 640 /etc/bind/db.networking-experiments.nju-slab.cn
named-checkconf
named-checkzone networking-experiments.nju-slab.cn \
  /etc/bind/db.networking-experiments.nju-slab.cn
rndc reload
```

在 Client1 清空本地缓存并验证：

```bash
kill -HUP "$(cat /run/dnsmasq-lab.pid)"
dig networking-experiments.nju-slab.cn A +short
curl -I http://networking-experiments.nju-slab.cn/
```

域名应由公网结果切换为 `10.10.20.20`，且 BIND 不再为该名称向公网查询。

### 6.4 核验证书

在 Web-Server：

```bash
openssl x509 -in /etc/nginx/certs/networking-experiments.nju-slab.cn.fullchain.pem \
  -noout -subject -issuer -dates -ext subjectAltName

openssl x509 -in /etc/nginx/certs/networking-experiments.nju-slab.cn.fullchain.pem \
  -pubkey -noout | openssl pkey -pubin -outform der | sha256sum

openssl pkey -in /etc/nginx/certs/networking-experiments.nju-slab.cn.key \
  -pubout -outform der | sha256sum
```

两个 SHA-256 值必须一致；有效期覆盖实验日期；SAN 包含实验域名。

### 6.5 配置 HTTPS 和 301 跳转

把 `/etc/nginx/conf.d/portal.conf` 改为：

```nginx
server {
    listen 80 default_server;
    server_name networking-experiments.nju-slab.cn;
    server_tokens off;
    return 301 https://networking-experiments.nju-slab.cn$request_uri;
}

server {
    listen 443 ssl http2 default_server;
    server_name networking-experiments.nju-slab.cn;
    server_tokens off;

    ssl_certificate /etc/nginx/certs/networking-experiments.nju-slab.cn.fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/networking-experiments.nju-slab.cn.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    access_log /var/log/nginx/lab2_portal_access.log;
    error_log /var/log/nginx/lab2_portal_error.log;
    include /etc/nginx/conf.d/site-locations.inc;
}
```

```bash
nginx -t
nginx -s reload
ss -lntp | grep -E ':(80|443) '
```

### 6.6 验证 start 实验结果和 complete 检查点

在完成配置的 start 工程和独立的 `lab2-complete` 工程中分别执行：

```bash
dig networking-experiments.nju-slab.cn A +short
curl -I http://networking-experiments.nju-slab.cn/
curl -I https://networking-experiments.nju-slab.cn/
```

预期：

- DNS 返回 `10.10.20.20`；
- HTTP 返回 `301`，`Location` 指向同一路径的 HTTPS URL；
- HTTPS 返回 `200`；
- 证书验证通过，页面及静态资源正常。

最终验收不得使用 `curl -k` 绕过证书验证。

## 7. 抓包与提交要求

Wireshark 过滤器：

```text
dns || tcp.port == 80 || tcp.port == 443 || tls
```

提交：

1. DNS 覆盖前后的地址对比；
2. 四类资源的缓存/CORS 响应头；
3. 证书 subject、issuer、有效期、SAN 和公钥匹配证据；
4. HTTP 301 与 HTTPS 200 证据；
5. TLS 握手和加密 Application Data 抓包，不提交私钥。

## 8. 故障排查

| 现象 | 检查项 |
|---|---|
| 域名仍返回公网地址 | BIND 区域、Client1 dnsmasq 缓存、SOA Serial |
| HTTP 正常但 HTTPS 失败 | 443 监听、证书挂载、私钥权限、SAN |
| `nginx -t` 报证书/私钥不匹配 | 比较两个公钥 SHA-256 |
| complete 节点立即退出 | `/etc/nginx/certs` 是否为专用只读挂载 |
| 静态资源 404 | `/var/www/portal` 持久卷及资源实际路径 |
