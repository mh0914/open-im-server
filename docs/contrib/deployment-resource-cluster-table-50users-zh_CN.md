# OpenIM 50人在线 Docker 集群部署资源表

## 1. 适用前提

本表按下面前提给出：

- 当前系统全部采用 Docker 部署
- 后续前端改造成 `electron-web` 的 Web 部署形态
- 目标规模为 `50 人同时在线聊天`
- 业务包含文本、图片、文件、语音、短视频、位置等常规消息
- 不包含独立 RTC 音视频会议集群

本表不再按单个组件拆资源，而是按“每台服务器部署什么服务”来规划。

## 2. 推荐主方案

推荐采用 `2 台应用节点 + 1 台数据节点` 的方式。

- 应用节点负责承接公网流量和 WebSocket 长连接
- 数据节点负责数据库、中间件和对象存储
- `electron-web` 以前端静态站点的形式部署在应用节点上
- 两台应用节点可挂在同一个 SLB / Nginx / 反向代理入口后面做流量分担

## 3. 推荐主表

| 服务器 | 服务器角色 | 部署服务 | CPU | 内存 | 系统盘 | 数据盘 |
|---|---|---|---:|---:|---:|---:|
| Server-01 | 应用节点 A | `Nginx`、`electron-web`、`openim-server`、`openim-chat` | 4 vCPU | 8 GB | 100 GB | 50 GB |
| Server-02 | 应用节点 B | `Nginx`、`electron-web`、`openim-server`、`openim-chat` | 4 vCPU | 8 GB | 100 GB | 50 GB |
| Server-03 | 数据节点 | `MongoDB`、`Redis`、`Kafka`、`Etcd`、`MinIO` | 8 vCPU | 16 GB | 100 GB | 300 GB |

## 4. `electron-web` 资源说明

这里单独把 `electron-web` 拆出来说明，避免它只被包含在“应用节点”描述里不够直观。

`electron-web` 在服务器上的形态通常是：

- `Vite build` 后生成的前端静态资源
- 通过 `Nginx` 或同类 Web 服务器托管
- 由浏览器访问
- 再反向代理到：
  - `/api`
  - `/chat`
  - `/msg_gateway`
  - `/object`
  - `/minio`

所以 `electron-web` 本身在服务端的资源需求并不高，主要消耗是：

- 静态文件存储
- Nginx 反向代理
- WebSocket 连接转发

如果你希望把 `electron-web` 的资源在表格里明确表达，可以按下面理解：

| 服务 | 推荐承载位置 | CPU占用 | 内存占用 | 磁盘占用 |
|---|---|---:|---:|---:|
| `electron-web` | 应用节点 | 0.5 ~ 1 vCPU | 512 MB ~ 1 GB | 5 ~ 10 GB |

也就是说，在推荐主表里：

- `Server-01` 和 `Server-02` 的 `4C8G`
- 已经把 `electron-web` 运行所需资源包含进去了

## 5. 如果你希望前端单独成节点

如果投标或汇报时，需要把前端也单独列成服务器，而不是和应用节点合并，可以使用下面这张表。

### 5.1 前后端分离部署表

| 服务器 | 服务器角色 | 部署服务 | CPU | 内存 | 系统盘 | 数据盘 |
|---|---|---|---:|---:|---:|---:|
| Server-01 | 前端节点 A | `Nginx`、`electron-web` | 2 vCPU | 2 GB | 50 GB | 20 GB |
| Server-02 | 前端节点 B | `Nginx`、`electron-web` | 2 vCPU | 2 GB | 50 GB | 20 GB |
| Server-03 | 应用节点 A | `openim-server`、`openim-chat` | 4 vCPU | 8 GB | 100 GB | 50 GB |
| Server-04 | 应用节点 B | `openim-server`、`openim-chat` | 4 vCPU | 8 GB | 100 GB | 50 GB |
| Server-05 | 数据节点 | `MongoDB`、`Redis`、`Kafka`、`Etcd`、`MinIO` | 8 vCPU | 16 GB | 100 GB | 300 GB |

这张表的好处是：

- 前端资源被单独体现
- 更适合做“前后端分层”的汇报展示
- 如果后续前端访问量增长，前端节点可独立扩容

## 6. 最低可用方案

如果当前只是测试、演示、投标验证，也可以采用 `2 台服务器` 的最低方案。

| 服务器 | 服务器角色 | 部署服务 | CPU | 内存 | 系统盘 | 数据盘 |
|---|---|---|---:|---:|---:|---:|
| Server-01 | 应用节点 | `Nginx`、`electron-web`、`openim-server`、`openim-chat` | 4 vCPU | 8 GB | 100 GB | 50 GB |
| Server-02 | 数据节点 | `MongoDB`、`Redis`、`Kafka`、`Etcd`、`MinIO` | 8 vCPU | 16 GB | 100 GB | 300 GB |

这个方案能跑，但没有应用层双机分流能力，更适合：

- 初期试运行
- 招投标演示
- 小规模内部使用

## 7. 更稳妥的生产方案

如果后面希望留更多冗余，建议按下面方案执行。

| 服务器 | 服务器角色 | 部署服务 | CPU | 内存 | 系统盘 | 数据盘 |
|---|---|---|---:|---:|---:|---:|
| Server-01 | 前端节点 A | `Nginx`、`electron-web` | 2 vCPU | 2 GB | 50 GB | 20 GB |
| Server-02 | 前端节点 B | `Nginx`、`electron-web` | 2 vCPU | 2 GB | 50 GB | 20 GB |
| Server-03 | 应用节点 A | `openim-server`、`openim-chat` | 4 vCPU | 8 GB | 100 GB | 50 GB |
| Server-04 | 应用节点 B | `openim-server`、`openim-chat` | 4 vCPU | 8 GB | 100 GB | 50 GB |
| Server-05 | 数据节点 | `MongoDB`、`Redis`、`Kafka`、`Etcd` | 8 vCPU | 16 GB | 100 GB | 150 GB |
| Server-06 | 对象存储节点 | `MinIO` | 4 vCPU | 8 GB | 100 GB | 300 GB |

这种方式的好处是：

- `electron-web` 前端单独部署
- 应用和数据拆开
- MinIO 再单独拆开
- 图片、文件、语音、视频增长后更容易扩容

## 8. 最终建议

如果你现在要做一个适合正式汇报和后续落地的资源方案，我建议：

### 方案 A：汇报主表

直接采用下面这张主表：

| 服务器 | 服务器角色 | 部署服务 | CPU | 内存 | 系统盘 | 数据盘 |
|---|---|---|---:|---:|---:|---:|
| Server-01 | 应用节点 A | `Nginx`、`electron-web`、`openim-server`、`openim-chat` | 4 vCPU | 8 GB | 100 GB | 50 GB |
| Server-02 | 应用节点 B | `Nginx`、`electron-web`、`openim-server`、`openim-chat` | 4 vCPU | 8 GB | 100 GB | 50 GB |
| Server-03 | 数据节点 | `MongoDB`、`Redis`、`Kafka`、`Etcd`、`MinIO` | 8 vCPU | 16 GB | 100 GB | 300 GB |

这张表最适合当前目标：

- 体现了 `electron-web`
- 体现了应用双机分流
- 体现了数据集中部署
- 复杂度适中

### 方案 B：如果甲方明确要求前端单列

就采用“前后端分离部署表”那张 5 节点方案。

## 9. 一句话结论

对于“Electron 改 Web + 50 人同时在线聊天”这类规模：

- `electron-web` 需要被明确算入应用节点资源
- 如果不单列前端节点，推荐表里的 `4C8G` 应用节点已经包含它
- 如果要单独体现前端资源，可以拆成 `2C2G` 的前端节点

