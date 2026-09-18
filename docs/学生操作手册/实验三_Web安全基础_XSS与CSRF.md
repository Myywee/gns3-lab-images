# 实验三：Web 安全基础——XSS 与 CSRF

## 1. 实验目标与安全边界

1. 复现反射型 XSS 和存储型 XSS；
2. 说明输出编码为什么能够阻止脚本执行；
3. 比较 `HttpOnly`、`Secure` 和 `SameSite` Cookie 属性；
4. 复现已登录用户的跨源改密 CSRF；
5. 验证 CSRF Token 缺失、错误和重放均被拒绝。

所有测试只能在课程提供的隔离 GNS3 环境中进行。不得向外部站点发送 Cookie、Token 或测试载荷。

## 2. 阶段与镜像

| 节点 | `lab3-start` | `lab3-complete` |
|---|---|---|
| Web-Server | `ghcr.io/myywee/web-server:lab3-vulnerable` | `ghcr.io/myywee/web-server:lab3-complete` |
| DNS-Server | `ghcr.io/myywee/dns-server:lab3-complete` | `ghcr.io/myywee/dns-server:lab3-complete` |
| Client1 | `ghcr.io/myywee/client:lab1-complete` | `ghcr.io/myywee/client:lab1-complete` |
| Client2 | `ghcr.io/myywee/client:lab1-no-cache` | `ghcr.io/myywee/client:lab1-no-cache` |
| Administrator | `ghcr.io/myywee/client:lab1-no-cache` | `ghcr.io/myywee/client:lab1-no-cache` |

两个阶段都需要受害者域名和攻击者域名，因此均使用 `dns-server:lab3-complete`。阶段差异在 Web 应用。

```bash
docker pull ghcr.io/myywee/web-server:lab3-vulnerable
docker pull ghcr.io/myywee/web-server:lab3-complete
docker pull ghcr.io/myywee/dns-server:lab3-complete
docker pull ghcr.io/myywee/client:lab1-complete
docker pull ghcr.io/myywee/client:lab1-no-cache
```

## 3. 拓扑、地址与域名

实验三沿用实验一、二的五节点应用层拓扑：

| 节点 | 地址 | 网关 |
|---|---|---|
| DNS-Server | `10.10.20.10/24` | `10.10.20.1` |
| Web-Server | `10.10.20.20/24` | `10.10.20.1` |
| Administrator | `10.10.10.10/24` | `10.10.10.1` |
| Client1 | `10.10.30.10/24` | `10.10.30.1` |
| Client2 | `10.10.30.20/24` | `10.10.30.1` |

| 角色 | 域名 | 地址 |
|---|---|---|
| 受害者站点 | `networking-experiments.nju-slab.cn` | `10.10.20.20` |
| 模拟攻击者站点 | `networking-experiments-2.nju-slab.cn` | `10.10.20.20` |

若使用全新工程，Router 配置为：

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

## 4. 节点初始化

DNS-Server：

```text
/bin/bash -lc '/gns3/bin/busybox ip link set eth0 up; /gns3/bin/busybox ip addr flush dev eth0; /gns3/bin/busybox ip addr add 10.10.20.10/24 dev eth0; /gns3/bin/busybox ip route replace default via 10.10.20.1 dev eth0; /usr/sbin/named -u bind -c /etc/bind/named.conf; exec /bin/bash'
```

Web-Server：

```text
/bin/bash -lc '/gns3/bin/busybox ip link set eth0 up; /gns3/bin/busybox ip addr flush dev eth0; /gns3/bin/busybox ip addr add 10.10.20.20/24 dev eth0; /gns3/bin/busybox ip route replace default via 10.10.20.1 dev eth0; /opt/exp3/start-exp3.sh; exec /bin/bash'
```

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

## 5. HTTPS 证书

把宿主机证书目录只读挂载到 Web-Server 的 `/etc/nginx/certs`。目录必须包含：

```text
networking-experiments.nju-slab.cn.fullchain.pem
networking-experiments.nju-slab.cn.key
```

私钥权限必须为 `0400` 或 `0600`；证书 SAN 必须同时覆盖：

```text
networking-experiments.nju-slab.cn
networking-experiments-2.nju-slab.cn
```

## 6. 环境基线

启动 `lab3-start` 后，在 Client1：

```bash
dig networking-experiments.nju-slab.cn A +short
dig networking-experiments-2.nju-slab.cn A +short
curl -s https://networking-experiments.nju-slab.cn/ | head
curl -s https://networking-experiments-2.nju-slab.cn/ | head
```

两个域名均应返回 `10.10.20.20`，两个 HTTPS 站点均可访问。实验账号：

```text
admin / admin123
```

应用数据保存在内存中；重启 Flask 会恢复初始密码并清空留言。

## 7. `lab3-start` 漏洞观察

### 7.1 反射型 XSS

若课程提供图形浏览器节点，访问：

```text
https://networking-experiments.nju-slab.cn/search?q=%3Cscript%3Ealert(%27Reflected-XSS%27)%3C%2Fscript%3E
```

只有终端时，用 curl 检查危险字符串未经转义进入响应。curl 不执行 JavaScript，因此不能把命令行结果写成“已经弹窗”。

```bash
curl -sG \
  --data-urlencode "q=<script>alert('Reflected-XSS')</script>" \
  https://networking-experiments.nju-slab.cn/search | grep '<script>'
```

### 7.2 存储型 XSS

浏览器访问 `/guestbook` 并提交：

```html
<script>alert('Stored-XSS')</script>
```

终端验证：

```bash
curl -i -X POST \
  --data-urlencode "message=<script>alert('Stored-XSS')</script>" \
  https://networking-experiments.nju-slab.cn/guestbook
curl -s https://networking-experiments.nju-slab.cn/ | grep 'Stored-XSS'
```

记录输入在后续响应中是否仍以脚本形式出现。

### 7.3 Cookie 属性

```bash
curl -sS -D - -o /dev/null \
  -d 'username=admin&password=admin123' \
  https://networking-experiments.nju-slab.cn/login \
  | grep -i '^Set-Cookie:'
```

记录 `Secure`、`HttpOnly` 和 `SameSite` 的取值，但不要记录或提交 session Cookie 具体值。

### 7.4 CSRF 跨源改密

检查攻击者页面：

```bash
curl -sS https://networking-experiments-2.nju-slab.cn/ \
  | sed -n '/<form /,/<\/form>/p'
```

登录并保存 Cookie：

```bash
rm -f /tmp/exp3-csrf-cookies.txt
curl -sS -c /tmp/exp3-csrf-cookies.txt -o /dev/null \
  -w 'login-http=%{http_code}\n' \
  -d 'username=admin&password=admin123' \
  https://networking-experiments.nju-slab.cn/login
```

模拟来自攻击者站点、携带已登录 Cookie、但没有 CSRF Token 的 POST：

```bash
curl -sS -b /tmp/exp3-csrf-cookies.txt \
  -H 'Origin: https://networking-experiments-2.nju-slab.cn' \
  -H 'Referer: https://networking-experiments-2.nju-slab.cn/' \
  --data 'new_password=hacked' \
  -o /tmp/exp3-csrf-response.txt \
  -w 'csrf-post-http=%{http_code}\n' \
  https://networking-experiments.nju-slab.cn/change-password
cat /tmp/exp3-csrf-response.txt
```

start 阶段预期登录返回 `302`，改密返回 `200`。验证密码：

```bash
curl -sS -o /dev/null -w 'old=%{http_code}\n' \
  -d 'username=admin&password=admin123' \
  https://networking-experiments.nju-slab.cn/login
curl -sS -o /dev/null -w 'new=%{http_code}\n' \
  -d 'username=admin&password=hacked' \
  https://networking-experiments.nju-slab.cn/login
```

预期旧密码为 `401`，新密码为 `302`。完成后重启 Web-Server 节点恢复初始内存状态，并删除 Cookie 临时文件。

## 8. `lab3-complete` 防护核验

### 8.1 XSS 和 Cookie

重新执行第 7.1、7.2 节测试。危险字符应作为普通文本显示，并被编码为 `&lt;`、`&gt;`，不能作为脚本执行。

再次检查 `Set-Cookie`，应同时出现：

```text
Secure; HttpOnly; SameSite=Lax
```

`SameSite` 描述站点边界，不等同于同源。本实验两个主机名同属 `nju-slab.cn`，不能把 `SameSite=Lax` 当作唯一 CSRF 防线；服务端 Token 才是这里的关键防护。curl 也不会自动实施浏览器 SameSite 策略。

### 8.2 获取 CSRF Token

```bash
rm -f /tmp/lab3-cookies.txt /tmp/lab3-profile.html
curl -sS -c /tmp/lab3-cookies.txt -o /dev/null \
  -w 'login-http=%{http_code}\n' \
  -d 'username=admin&password=admin123' \
  https://networking-experiments.nju-slab.cn/login

curl -sS -b /tmp/lab3-cookies.txt -o /tmp/lab3-profile.html \
  https://networking-experiments.nju-slab.cn/profile

csrf_token=$(sed -n \
  's/.*name="csrf_token" value="\([a-f0-9]*\)".*/\1/p' \
  /tmp/lab3-profile.html | head -n 1)
printf 'token-length=%s\n' "${#csrf_token}"
```

预期长度为 `64`。不要把 Token 值写入报告。

### 8.3 无 Token 和错误 Token

```bash
curl -sS -b /tmp/lab3-cookies.txt \
  -H 'Origin: https://networking-experiments-2.nju-slab.cn' \
  --data 'new_password=bad' \
  -o /tmp/lab3-without-token.txt \
  -w 'without-token=%{http_code}\n' \
  https://networking-experiments.nju-slab.cn/change-password

curl -sS -b /tmp/lab3-cookies.txt \
  --data-urlencode 'new_password=bad2' \
  --data-urlencode 'csrf_token=invalid-token' \
  -o /tmp/lab3-wrong-token.txt \
  -w 'wrong-token=%{http_code}\n' \
  https://networking-experiments.nju-slab.cn/change-password
```

两者均应返回 `403` 和 `CSRF token mismatch`。

### 8.4 正确 Token 与重放

```bash
curl -sS -b /tmp/lab3-cookies.txt -c /tmp/lab3-cookies.txt \
  -H 'Origin: https://networking-experiments.nju-slab.cn' \
  -H 'Referer: https://networking-experiments.nju-slab.cn/profile' \
  --data-urlencode 'new_password=good' \
  --data-urlencode "csrf_token=$csrf_token" \
  -o /tmp/lab3-with-token.txt \
  -w 'with-token=%{http_code}\n' \
  https://networking-experiments.nju-slab.cn/change-password
```

预期返回 `200`。立即用同一旧 Token 重放：

```bash
curl -sS -b /tmp/lab3-cookies.txt \
  --data-urlencode 'new_password=reused' \
  --data-urlencode "csrf_token=$csrf_token" \
  -o /tmp/lab3-replay-token.txt \
  -w 'replay-old-token=%{http_code}\n' \
  https://networking-experiments.nju-slab.cn/change-password
```

预期返回 `403`，证明成功改密后 Token 已轮换。

清理：

```bash
rm -f /tmp/lab3-cookies.txt /tmp/lab3-profile.html \
  /tmp/lab3-without-token.txt /tmp/lab3-wrong-token.txt \
  /tmp/lab3-with-token.txt /tmp/lab3-replay-token.txt
```

## 9. 提交要求

1. 两个域名的 DNS 和 TLS 主机名验证；
2. XSS 修复前“未经转义”和修复后“作为文本显示”的对照；
3. start/complete 两阶段 Cookie 属性对照；
4. start 阶段无 Token 改密成功的状态码；
5. complete 阶段无 Token、错误 Token、旧 Token 为 `403`，正确 Token 为 `200`；
6. 输出编码、HttpOnly、SameSite 和 CSRF Token 各自防护边界的说明。

报告不得包含私钥、session Cookie 或 CSRF Token 的具体值。

## 10. 故障排查

| 现象 | 检查项 |
|---|---|
| 两域名只有一个可访问 | DNS 区域和证书 SAN |
| HTTPS 启动失败 | 只读挂载、文件名、私钥权限、证书/私钥匹配 |
| Flask 正常但 nginx 502 | `/var/log/exp3-flask.log`、127.0.0.1:5000 |
| 密码不是初始值 | 重启 Flask 或整个 Web-Server 节点 |
| Token 提取长度为 0 | 是否已登录、Cookie 文件、`/profile` 响应 |
| curl 没有弹窗 | curl 不执行 JavaScript，检查响应转义情况 |
