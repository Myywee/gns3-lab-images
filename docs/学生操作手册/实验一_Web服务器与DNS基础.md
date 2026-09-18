# 实验一：Web 服务器与 DNS 基础

## 1. 实验目标

完成实验后，应能够：

1. 配置三个内网网段之间的基本连通性和出站 PAT；
2. 使用 `curl` 观察 HTTP 请求、响应和状态码；
3. 发现并修复 `/secure/` 与 `/.git/` 的未授权访问；
4. 区分权威 DNS、递归解析、BIND 缓存和客户端缓存；
5. 使用 `dig`、日志和 Wireshark 观察 DNS 查询路径。

## 2. 阶段与镜像

| 节点 | `lab1-start` | `lab1-complete` |
|---|---|---|
| Web-Server | `ghcr.io/myywee/web-server:lab1-vulnerable` | `ghcr.io/myywee/web-server:lab1-complete` |
| DNS-Server | `ghcr.io/myywee/dns-server:lab1-no-recursion` | `ghcr.io/myywee/dns-server:lab1-complete` |
| Client1 | `ghcr.io/myywee/client:lab1-no-cache` | `ghcr.io/myywee/client:lab1-complete` |
| Client2 | `ghcr.io/myywee/client:lab1-no-cache` | `ghcr.io/myywee/client:lab1-no-cache` |
| Administrator | `ghcr.io/myywee/client:lab1-no-cache` | `ghcr.io/myywee/client:lab1-no-cache` |

在 GNS3 Docker 宿主机拉取：

```bash
docker pull ghcr.io/myywee/web-server:lab1-vulnerable
docker pull ghcr.io/myywee/web-server:lab1-complete
docker pull ghcr.io/myywee/dns-server:lab1-no-recursion
docker pull ghcr.io/myywee/dns-server:lab1-complete
docker pull ghcr.io/myywee/client:lab1-no-cache
docker pull ghcr.io/myywee/client:lab1-complete
```

## 3. 拓扑与地址

```text
GNS3 NAT
└── Core-Router G0/3（DHCP，NAT outside）
    ├── G0/0  10.10.20.1/24 ── SW-SERVER
    │                            ├── DNS-Server 10.10.20.10/24
    │                            └── Web-Server 10.10.20.20/24
    ├── G0/1  10.10.10.1/24 ── SW-MGMT
    │                            └── Administrator 10.10.10.10/24
    └── G0/2  10.10.30.1/24 ── SW-CLIENT
                                 ├── Client1 10.10.30.10/24
                                 └── Client2 10.10.30.20/24
```

| 名称 | 值 |
|---|---|
| 实验区域 | `experiment.test` |
| Web 域名 | `www.experiment.test` |
| DNS 域名 | `ns1.experiment.test` |
| DNS-Server | `10.10.20.10` |
| Web-Server | `10.10.20.20` |

## 4. 环境初始化

### 4.1 Router

如果接口编号不同，以 `show ip interface brief` 和 GNS3 接线为准替换接口名。

```text
enable
configure terminal
hostname Core-Router
no ip domain-lookup

interface GigabitEthernet0/0
 description SERVER-NETWORK
 ip address 10.10.20.1 255.255.255.0
 ip nat inside
 no shutdown
 exit

interface GigabitEthernet0/1
 description MANAGEMENT-NETWORK
 ip address 10.10.10.1 255.255.255.0
 ip nat inside
 no shutdown
 exit

interface GigabitEthernet0/2
 description CLIENT-NETWORK
 ip address 10.10.30.1 255.255.255.0
 ip nat inside
 no shutdown
 exit

interface GigabitEthernet0/3
 description GNS3-NAT-WAN
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

验证：

```text
show ip interface brief
show ip route
show dhcp lease
show ip nat statistics
```

### 4.2 Docker Start command

Client 镜像自带入口脚本：`lab1-complete` 把 DNS 指向本地缓存 `127.0.0.1`；`lab1-no-cache` 直接使用 `10.10.20.10`。因此不要在 Start command 中覆盖 `/etc/resolv.conf`。

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

## 5. 实验步骤

### 5.1 启动 `lab1-start` 并验证连通性

在 Client1：

```bash
ip -br address
ip route
ping -c 2 10.10.30.1
ping -c 2 10.10.20.10
ping -c 2 10.10.20.20
ping -c 2 10.10.10.10
ping -c 2 1.1.1.1
```

在 Router 立即查看 PAT：

```text
show ip nat translations
show ip nat statistics
```

检查服务：

```bash
# DNS-Server
ss -lnutp | grep ':53'
dig @10.10.20.10 www.experiment.test A +short

# Web-Server
ss -lntp | grep ':80'
nginx -t
```

内部域名应返回 `10.10.20.20`。

### 5.2 发现并修复 Web 访问控制问题

在 Client1：

```bash
curl -s -o /dev/null -w '/ = %{http_code}\n' http://10.10.20.20/
curl -s -o /dev/null -w '/secure/ = %{http_code}\n' http://10.10.20.20/secure/
curl -s -o /dev/null -w '/.git/HEAD = %{http_code}\n' http://10.10.20.20/.git/HEAD
curl -s -o /dev/null -w '/.git/config = %{http_code}\n' http://10.10.20.20/.git/config
```

start 阶段四个请求均可能返回 `200`。在 Web-Server 的 `/etc/nginx/sites-available/default` 中加入：

```nginx
location ^~ /secure/ {
    deny all;
}

location ~ /\. {
    deny all;
    access_log off;
    log_not_found off;
}
```

检查并重新加载：

```bash
nginx -t
nginx -s reload
```

重新测试，预期 `/` 为 `200`，其他三个敏感路径为 `403`。

### 5.3 从关闭递归切换到受限递归

初始对照：

```bash
dig @10.10.20.10 www.experiment.test A +noall +comments +answer
dig @10.10.20.10 www.example.com A +noall +comments +answer
```

第一个查询应成功；第二个不应得到公网 A 记录，响应不应包含 `ra`。

在 DNS-Server 备份并编辑 `/etc/bind/named.conf.options`，使关键项为：

```text
allow-query { lab_networks; };
allow-recursion { lab_networks; };
allow-query-cache { lab_networks; };
recursion yes;
```

保留 `lab_networks` 访问控制，不得改为 `any`；不要添加公共 DNS `forwarders`。

```bash
named-checkconf
rndc stop 2>/dev/null || pkill -TERM named
while pgrep -x named >/dev/null; do sleep 1; done
/usr/sbin/named -u bind -c /etc/bind/named.conf
dig @10.10.20.10 www.example.com A +noall +comments +answer
```

修改后应得到 `NOERROR`、`rd ra` 和公网地址。

### 5.4 验证 BIND 迭代和缓存

开始捕获 DNS-Server—SW-SERVER 链路。在 DNS-Server：

```bash
rndc flush
dig @10.10.20.10 www.example.com A +noall +answer +stats
rndc dumpdb -cache
grep -n -A2 -B2 'example.com' /var/cache/bind/named_dump.db | head -n 30
```

Wireshark 过滤器：

```text
dns.flags.response == 0 && ip.src == 10.10.20.10
```

第一次应看到 BIND 向根、TLD 和权威服务器发出查询。停止并重新开始捕获，再查询一次；第二次应由缓存回答，不再出现同样的公网查询。

### 5.5 核验 `lab1-complete` 客户端缓存

在 Client1：

```bash
cat /etc/resolv.conf
ss -lnup | grep '127.0.0.1:53'
: > /var/log/dnsmasq-lab.log
kill -HUP "$(cat /run/dnsmasq-lab.pid)"
dig www.example.com A +noall +answer +stats
dig www.example.com A +noall +answer +stats
grep -E 'forwarded|cached|reply' /var/log/dnsmasq-lab.log
```

解析器应为 `127.0.0.1`；第一次日志出现 `forwarded ... to 10.10.20.10`，第二次出现 `cached`。

在 Client2：

```bash
cat /etc/resolv.conf
dig www.example.com A +noall +answer +stats
```

Client2 应直接使用 `10.10.20.10`，作为无客户端缓存的对照。

## 6. 抓包与提交要求

建议捕获以下链路：

- Client1—SW-CLIENT；
- DNS-Server—SW-SERVER；
- Router—NAT；
- Web-Server—SW-SERVER。

常用过滤器：

```text
dns
dns.flags.response == 0 && ip.src == 10.10.20.10
http || tcp.port == 80
```

提交：

1. Router 接口、默认路由和 NAT 转换证据；
2. Web 修复前后的四个 HTTP 状态码；
3. 关闭/启用递归后的 `dig` 对比；
4. BIND 首次迭代与第二次缓存命中的抓包；
5. Client1 本地缓存与 Client2 直连 BIND 的对照。

## 7. 故障排查

| 现象 | 检查项 |
|---|---|
| 节点没有地址 | Start command 和接口名 `eth0` |
| 跨网段不通 | Router 接口、掩码和默认网关 |
| 公网 IP 不通 | 默认路由、NAT inside/outside、ACL、GNS3 NAT |
| DNS 端口未监听 | `pgrep -a named`、`named-checkconf -z` |
| Web 未监听 | `/tmp/start-web-server.log`、`nginx -t` |
| Client1 本地解析失败 | dnsmasq、`127.0.0.1:53`、上游 `10.10.20.10` |

