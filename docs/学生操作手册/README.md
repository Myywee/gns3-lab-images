# GNS3 网络实验学生操作手册（分册）

本目录按实验拆分学生操作手册。实验五不在本课程手册范围内。

| 实验 | 手册 | 阶段 |
|---|---|---|
| 实验一：Web 服务器与 DNS 基础 | [实验一_Web服务器与DNS基础.md](实验一_Web服务器与DNS基础.md) | `lab1-start`、`lab1-complete` |
| 实验二：复杂 Web 部署与 HTTPS | [实验二_复杂Web部署与HTTPS.md](实验二_复杂Web部署与HTTPS.md) | `lab2-start`、`lab2-complete` |
| 实验三：Web 安全基础——XSS 与 CSRF | [实验三_Web安全基础_XSS与CSRF.md](实验三_Web安全基础_XSS与CSRF.md) | `lab3-start`、`lab3-complete` |
| 实验四：CUBIC 与 BBR 拥塞控制对比 | [实验四_CUBIC与BBR拥塞控制对比.md](实验四_CUBIC与BBR拥塞控制对比.md) | `complete` |
| 实验六：TCP 与 UDP Socket Echo | [实验六_TCP与UDP_Socket_Echo.md](实验六_TCP与UDP_Socket_Echo.md) | `complete` |

## 阶段使用规则

- `start` 是学生实验基线，应在该环境中完成配置、测试和抓包。
- `complete` 是完成态检查点，用于结果核验、故障恢复或教师演示。
- 实验四和实验六只有 `complete` 镜像；镜像提供工具和程序，实验数据仍由学生采集和分析。
- 建议为每个实验、每个阶段建立独立 GNS3 工程副本，不要修改公用模板来切换阶段。
- Docker 节点被删除或重建后，其可写层中的实验结果可能消失，应及时导出 pcapng、JSON 和日志。

## 安全要求

实验三的 XSS、CSRF、Cookie 和口令操作只能用于课程提供的隔离 GNS3 环境。不得将测试载荷用于未授权系统。不得提交 TLS 私钥、session Cookie 或 CSRF Token 的具体值。

