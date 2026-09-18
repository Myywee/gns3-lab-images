# 实验六：TCP 与 UDP Socket Echo

## 1. 实验目标

1. 说明 `socket()`、`bind()`、`listen()`、`accept()` 和 `connect()` 的作用；
2. 通过抓包和 `ss` 区分 TCP 监听 Socket 与已连接 Socket；
3. 使用四元组识别 TCP 连接；
4. 证明 TCP 与 UDP 可以同时使用相同端口号；
5. 对比 TCP 可靠字节流与 UDP 数据报服务；
6. 观察随机丢包期间的 TCP 重传和 UDP 应用层超时；
7. 使用已绑定的 UDP Socket 在两个固定端点之间双向通信。

## 2. 镜像

实验六只有 complete 版本：

| 节点 | 镜像 |
|---|---|
| Client | `ghcr.io/myywee/client:lab6-complete` |
| Server | `ghcr.io/myywee/server:lab6-complete` |

```bash
docker pull ghcr.io/myywee/client:lab6-complete
docker pull ghcr.io/myywee/server:lab6-complete
```

程序已经安装在 `/opt/socket-lab`，实验中不修改程序文件，也不需要联网安装软件。

## 3. 拓扑和地址

```text
Client 10.10.10.10/24
默认网关 10.10.10.1
        |
R1-IOSv
G0/0 10.10.10.1/24
G0/1 10.20.20.1/24
        |
        | 20 Mbit/s，单向延迟 25 ms，抖动 2 ms
        |
Server 10.20.20.20/24
默认网关 10.20.20.1
```

正常阶段 Packet loss 为 `0%`；丢包实验阶段为 `5%`。

## 4. 初始化

### 4.1 Docker Start command

Client：

```text
/bin/bash -lc '/gns3/bin/busybox ip link set eth0 up; /gns3/bin/busybox ip addr flush dev eth0; /gns3/bin/busybox ip addr add 10.10.10.10/24 dev eth0; /gns3/bin/busybox ip route replace default via 10.10.10.1 dev eth0; exec /bin/bash'
```

Server：

```text
/bin/bash -lc '/gns3/bin/busybox ip link set eth0 up; /gns3/bin/busybox ip addr flush dev eth0; /gns3/bin/busybox ip addr add 10.20.20.20/24 dev eth0; /gns3/bin/busybox ip route replace default via 10.20.20.1 dev eth0; exec /bin/bash'
```

### 4.2 R1-IOSv

```text
enable
configure terminal
hostname R1-IOSv
no ip domain-lookup

interface GigabitEthernet0/0
 description TO-CLIENT
 ip address 10.10.10.1 255.255.255.0
 no shutdown
 exit

interface GigabitEthernet0/1
 description TO-SERVER
 ip address 10.20.20.1 255.255.255.0
 no shutdown
 exit

end
write memory
```

两个网段均为直连网段，不需要 OSPF 或静态路由。

### 4.3 链路条件和连通性

在 R1—Server 链路配置：

- 带宽 `20 Mbit/s`；
- 单向延迟 `25 ms`；
- 抖动 `2 ms`；
- 初始 Packet loss `0%`。

```bash
# Client
ip -br address
ip route
ping -c 3 10.10.10.1
ping -c 3 10.20.20.20
```

## 5. 启动 Echo Server

在 Server：

```bash
cd /opt/socket-lab

python3 -u tcp_echo_server.py --host 0.0.0.0 --port 18080 \
  > /tmp/tcp_echo_server.log 2>&1 &
TCP_ECHO_PID=$!
printf '%s\n' "$TCP_ECHO_PID" > /tmp/tcp_echo_server.pid

python3 -u udp_echo_server.py --host 0.0.0.0 --port 18080 \
  > /tmp/udp_echo_server.log 2>&1 &
UDP_ECHO_PID=$!
printf '%s\n' "$UDP_ECHO_PID" > /tmp/udp_echo_server.pid

sleep 1
kill -0 "$TCP_ECHO_PID" && echo "TCP Server 正在运行，PID=$TCP_ECHO_PID"
kill -0 "$UDP_ECHO_PID" && echo "UDP Server 正在运行，PID=$UDP_ECHO_PID"
ss -ltnup | grep 18080
```

预期同时出现 TCP `LISTEN` 和 UDP `UNCONN`。两者端口空间独立，因此能同时绑定 18080。

启动失败时查看：

```bash
tail -n 20 /tmp/tcp_echo_server.log
tail -n 20 /tmp/udp_echo_server.log
```

## 6. 实验步骤

### 6.1 无丢包基线

在 R1—Server 链路开始抓包。Client：

```bash
cd /opt/socket-lab
python3 tcp_echo_client.py --server 10.20.20.20 --port 18080 --msg 'hello tcp'
python3 udp_echo_client.py --server 10.20.20.20 --port 18080 --count 10 --size 64
```

过滤器：

```text
tcp.port == 18080 || udp.port == 18080
```

记录：

- TCP 三次握手、Echo 和连接关闭；
- UDP 第一个应用数据报之前没有传输层握手；
- TCP 与 UDP 使用的临时源端口；
- 两个客户端是否收到相同内容的 Echo。

保存为 `exp6_baseline.pcapng`。

### 6.2 监听 Socket、连接 Socket 与四元组

Client：

```bash
timeout 45s python3 tcp_echo_client.py \
  --server 10.20.20.20 --port 18080 \
  --size 8388608 --timeout 20
```

传输期间在 Server：

```bash
ss -ltnp 'sport = :18080'
ss -tnp 'sport = :18080'
```

记录监听 Socket 的本地端点，以及至少一个 `ESTAB` Socket 的本地 IP、端口、远端 IP、端口。说明为什么监听 Socket 仍能继续接受新连接。

### 6.3 显式绑定源端口

Client：

```bash
python3 tcp_echo_client.py \
  --server 10.20.20.20 --port 18080 \
  --source-ip 10.10.10.10 --source-port 20001 \
  --msg 'tcp fixed source port'

python3 udp_echo_client.py \
  --server 10.20.20.20 --port 18080 \
  --source-ip 10.10.10.10 --source-port 20002 \
  --count 5 --size 64
```

在抓包中确认源端口分别为 20001、20002。立即重复使用 TCP/20001 可能因端口占用或 `TIME_WAIT` 失败。

### 6.4 多客户端并发

在 Client 的一个控制台启动三个后台连接：

```bash
python3 tcp_echo_client.py --server 10.20.20.20 \
  --source-port 20011 --size 8388608 > /tmp/client_20011.log 2>&1 &
C1_PID=$!

python3 tcp_echo_client.py --server 10.20.20.20 \
  --source-port 20012 --size 8388608 > /tmp/client_20012.log 2>&1 &
C2_PID=$!

python3 tcp_echo_client.py --server 10.20.20.20 \
  --source-port 20013 --size 8388608 > /tmp/client_20013.log 2>&1 &
C3_PID=$!
```

立即在 Server：

```bash
ss -tnp 'sport = :18080'
```

应看到一个监听端口对应多个不同四元组。回到 Client：

```bash
wait "$C1_PID"; C1_STATUS=$?
wait "$C2_PID"; C2_STATUS=$?
wait "$C3_PID"; C3_STATUS=$?
echo "exit status: $C1_STATUS $C2_STATUS $C3_STATUS"
```

### 6.5 随机丢包

把 R1—Server 链路 Packet loss 改为 `5%`。

TCP：

```bash
timeout 120s python3 tcp_echo_client.py \
  --server 10.20.20.20 --port 18080 \
  --size 1048576 --timeout 30
```

UDP：

```bash
python3 udp_echo_client.py \
  --server 10.20.20.20 --port 18080 \
  --count 50 --size 1200 --interval 0.05 --timeout 0.5
```

预期：

- TCP 出现重传、重复 ACK 或选择确认，最终仍收到完整 Echo；
- UDP 出现序号超时，不自动补发；
- 应用层 UDP 超时率不要求严格等于 5%，因为请求和响应两个方向均可能丢包。

每种协议至少重复 5 轮，保存 `exp6_loss_tcp.pcapng`、`exp6_loss_udp.pcapng`。完成后立即把 Packet loss 恢复为 `0%`。

TCP 重传过滤器：

```text
tcp.port == 18080 && (tcp.analysis.retransmission || tcp.analysis.fast_retransmission || tcp.analysis.duplicate_ack)
```

### 6.6 固定端口 UDP 对等通信

Client：

```bash
cd /opt/socket-lab
python3 udp_peer.py \
  --local-ip 10.10.10.10 --local-port 19001 \
  --peer-ip 10.20.20.20 --peer-port 19002
```

Server：

```bash
cd /opt/socket-lab
python3 udp_peer.py \
  --local-ip 10.20.20.20 --local-port 19002 \
  --peer-ip 10.10.10.10 --peer-port 19001
```

两端分别输入多行文本。过滤器：

```text
udp.port == 19001 || udp.port == 19002
```

确认 A→B 始终为 19001→19002，B→A 始终为 19002→19001。保存为 `exp6_peer_udp.pcapng`。

## 7. 结束实验

先在两个 `udp_peer.py` 前台进程按 `Ctrl+C`，再在 Server：

```bash
TCP_ECHO_PID="$(cat /tmp/tcp_echo_server.pid)"
UDP_ECHO_PID="$(cat /tmp/udp_echo_server.pid)"
kill "$TCP_ECHO_PID" "$UDP_ECHO_PID" 2>/dev/null || true
wait "$TCP_ECHO_PID" "$UDP_ECHO_PID" 2>/dev/null || true
ss -ltnup | grep 18080 || echo 'TCP/UDP 18080 已停止监听'
```

## 8. 记录表

| 协议 | Client 源端点 | Server 本地端点 | Server 看到的对端 | 是否握手 | 是否完整 Echo |
|---|---|---|---|---|---|
| TCP |  |  |  |  |  |
| UDP |  |  |  |  |  |

| 协议 | 轮次 | 链路丢包率 | 发送量/个数 | 完成时间 | 应用层丢失 | TCP 重传 |
|---|---:|---:|---:|---:|---:|---:|
| TCP | 1–5 | 5% | 1 MiB |  | 不适用 |  |
| UDP | 1–5 | 5% | 50 |  |  | 不适用 |

## 9. 思考题与提交要求

提交四个 pcapng、客户端输出、Server 的 `ss` 状态和随机丢包记录表，并回答：

1. `bind()`、`listen()`、`accept()`、`connect()` 分别做什么？
2. `accept()` 为什么返回新 Socket？本地端口是否仍为 18080？
3. 多个 TCP 连接怎样通过四元组区分？
4. UDP Socket 的本地端点和远端端点分别由什么调用确定？
5. 为什么同一主机能同时使用 TCP/18080 和 UDP/18080？
6. 为什么普通客户端通常不显式绑定源端口？
7. TCP 一次 `sendall()` 是否保证服务端一次 `recv()` 得到全部数据？
8. UDP Client 超时为什么不能证明报文一定在去程丢失？

## 10. 故障排查

| 现象 | 检查项 |
|---|---|
| Client 无法 ping Server | 地址、网关、R1 两接口是否 `up/up` |
| TCP `Connection refused` | TCP Server 进程、TCP/18080 监听 |
| UDP 全部超时 | UDP Server、UDP/18080 抓包、返回路由 |
| TCP 与 UDP 不能同时启动 | 是否错误地使用了相同协议，检查 `ss -ltnup` |
| 固定源端口被占用 | 进程占用或旧 TCP 四元组处于 `TIME_WAIT` |
| 大传输太快无法观察 | 检查 20 Mbit/s 链路限制 |
| UDP 丢失率与 5% 不同 | 样本量、双向丢包和超时阈值 |

