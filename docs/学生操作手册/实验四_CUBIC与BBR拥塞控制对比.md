# 实验四：CUBIC 与 BBR 拥塞控制对比

## 1. 实验目标

1. 识别 TCP 三次握手、数据传输、重传和连接关闭；
2. 区分接收窗口与发送端拥塞窗口 `cwnd`；
3. 使用 `iperf3 -C` 为单次连接选择 CUBIC 或 BBR；
4. 使用 `ss -ti` 观察 `cwnd`、RTT、重传数和 pacing rate；
5. 在相同链路条件下比较两种算法的吞吐、重传和恢复轨迹。

## 2. 镜像

实验四只有 complete 版本：

| 节点 | 镜像 |
|---|---|
| Client | `ghcr.io/myywee/client:lab4-complete` |
| Server | `ghcr.io/myywee/server:lab4-complete` |

```bash
docker pull ghcr.io/myywee/client:lab4-complete
docker pull ghcr.io/myywee/server:lab4-complete
```

镜像已经提供 `iperf3`、`iproute2`、`tcpdump` 和 `/opt/cc-lab/run_cc_client.sh`，实验中不需要联网安装软件。

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

正常阶段 Packet loss 为 `0%`；故障阶段为 `2%`。过滤器双向生效，实测 RTT 应约为 50 ms 加处理时间。

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

如果实际接口编号不同，以 `show ip interface brief` 和 GNS3 接线为准替换接口名。两个网段均为直连网段，不需要静态路由或 OSPF。

### 4.3 GNS3 链路条件

右击 R1-IOSv—Server 链路并打开 **Packet filters**：

- Delay Latency：`25 ms`；
- Jitter：`2 ms`；
- 正常 Packet loss：`0%`；
- 故障 Packet loss：`2%`。

修改丢包率时只改 Packet loss Chance 并点击 Apply。不要使用全局 Reset，否则会清除固定 Delay/Jitter。

## 5. 实验前检查

```bash
# Client
ip -br address
ip route
ping -c 3 10.20.20.20
cat /proc/sys/net/ipv4/tcp_available_congestion_control
cat /proc/sys/net/ipv4/tcp_congestion_control
tc qdisc show dev eth0
```

可用算法必须同时包含 `cubic` 和 `bbr`。Docker 节点共享 GNS3 Docker 宿主内核。如果没有 BBR，由实验环境维护者在宿主侧启用；学生不要在容器内执行 `modprobe`。

若模板已授予 `NET_ADMIN`，可配置公平队列：

```bash
tc qdisc replace dev eth0 root fq
tc qdisc show dev eth0
```

若返回 `Operation not permitted`，联系实验环境维护者，不要绕过权限。

## 6. 执行实验

### 6.1 启动 Server

在 Server 前台运行并保持控制台打开：

```bash
iperf3 -s -p 5201
```

应显示 `Server listening on 5201`。

### 6.2 开始抓包

在 R1-IOSv—Server 链路开始捕获，并使用：

```text
tcp.port == 5201
```

必须在流量开始前抓包，才能保留三次握手。

### 6.3 运行 CUBIC

确认 Packet loss 为 `0%`，在 Client：

```bash
cd /opt/cc-lab
./run_cc_client.sh cubic run01
```

脚本总时长 90 秒，会自动：

- 每 0.2 秒运行一次 `ss -ti`；
- 保存 iperf3 JSON；
- 记录 start/loss/recovery/end 时间戳；
- 在 30 秒提示把 Packet loss 改为 `2%`；
- 在 50 秒提示把 Packet loss 恢复为 `0%`；
- 结束时停止后台采样任务。

看到提示后立即在 GNS3 操作，人工点击延迟应在报告中注明。测试结束后停止捕获并保存为：

```text
cubic_run01.pcapng
```

检查输出：

```bash
ls -lh cubic_run01_iperf.json cubic_run01_ss.log cubic_run01_events.log
grep -q '"sum_sent"' cubic_run01_iperf.json && echo 'iperf3 JSON 完整'
```

### 6.4 运行 BBR

重新确认 Packet loss 为 `0%`，重新开始抓包：

```bash
cd /opt/cc-lab
./run_cc_client.sh bbr run01
```

保存为 `bbr_run01.pcapng`。两种算法各重复至少 5 轮，轮次编号依次增加；建议交替运行 CUBIC 与 BBR，减少宿主负载随时间变化造成的偏差。

## 7. 数据与分析

每轮应得到：

```text
<算法>_<轮次>.pcapng
<算法>_<轮次>_iperf.json
<算法>_<轮次>_ss.log
<算法>_<轮次>_events.log
```

重传过滤器：

```text
tcp.port == 5201 && (tcp.analysis.retransmission || tcp.analysis.fast_retransmission || tcp.analysis.duplicate_ack)
```

按事件日志把每轮分为：

| 阶段 | 时间 | 链路状态 |
|---|---:|---|
| 基线 | 0–30 s | 0% 丢包 |
| 故障 | 30–50 s | 2% 丢包 |
| 恢复 | 50–90 s | 0% 丢包 |

每种算法计算或整理：

1. 三阶段平均吞吐；
2. 故障阶段重传数量；
3. `cwnd`、RTT、pacing rate 的变化；
4. 恢复到故障前吞吐 90% 所需时间；
5. 五轮结果的中位数和离散程度。

Wireshark 的 TCP Window 是接收窗口，不是发送端 `cwnd`；`cwnd` 必须引用 Client 的 `ss -ti` 日志。

## 8. 提交要求

1. 两种算法各至少 5 轮的四类原始文件；
2. 完整三次握手与故障期重传的抓包截图；
3. 三阶段吞吐、重传、恢复时间汇总表；
4. `cwnd`、RTT、pacing rate 随时间的图或表；
5. 结合控制依据解释现象，不得仅凭单轮结果断言某算法始终更快。

## 9. 故障排查

| 现象 | 检查项 |
|---|---|
| Client 无法连接 Server | 地址、网关、R1 接口、`iperf3 -s` |
| `bbr` 不可用 | 宿主内核的 `tcp_available_congestion_control` |
| qdisc 配置无权限 | Docker 模板是否授予 `NET_ADMIN` |
| 没有抓到握手 | 是否在运行脚本前开始捕获 |
| 日志文件已存在 | 使用新的轮次名，不要覆盖已有证据 |
| 固定时延消失 | 是否误用了 Packet filters 全局 Reset |

