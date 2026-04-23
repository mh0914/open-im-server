# OpenIM 三台 8C16G 服务器部署方案

## 1. 前提

你计划申请的资源规格为：

- 3 台服务器
- 每台 `8 vCPU / 16 GB RAM`
- 每台 `100 GB 系统盘`
- 每台 `500 GB 数据盘`

目标场景：

- 当前系统全部采用 Docker 部署
- 前端按 `electron-web` 的 Web 形态部署
- 支持约 `50 人同时在线聊天`
- 消息类型包含文本、图片、文件、语音、视频、位置等常规消息

## 2. 总体部署思路

建议采用下面的分工：

- `Server-01`：应用节点 A
- `Server-02`：应用节点 B
- `Server-03`：数据节点

这样做的好处是：

- 两台应用节点可以共同承接公网流量
- 一台应用节点异常时，另一台还能继续服务
- 数据服务集中在一台机器，架构简单，便于当前规模落地
- 你申请的 `8C16G` 资源对 50 人在线来说余量比较充足

## 3. 每台服务器部署内容

| 服务器 | 服务器角色 | 部署内容 | 资源规格 | 建议用途 |
|---|---|---|---|---|
| Server-01 | 应用节点 A | `Nginx`、`electron-web`、`openim-server`、`openim-chat` | `8C16G / 100G系统盘 / 500G数据盘` | 对外提供 Web 前端、`/api`、`/chat`、`/msg_gateway` 访问 |
| Server-02 | 应用节点 B | `Nginx`、`electron-web`、`openim-server`、`openim-chat` | `8C16G / 100G系统盘 / 500G数据盘` | 与 Server-01 一起做应用双机分流和冗余 |
| Server-03 | 数据节点 | `MongoDB`、`Redis`、`Kafka`、`Etcd`、`MinIO` | `8C16G / 100G系统盘 / 500G数据盘` | 提供消息存储、缓存、对象存储和中间件支撑 |

## 4. 推荐网络关系

### Server-01

对外承接：

- `Nginx`
- `electron-web`
- `openim-server`
- `openim-chat`

建议暴露：

- `80/443`

建议反向代理到：

- `/api` -> `openim-server`
- `/chat` -> `openim-chat`
- `/msg_gateway` -> `openim-server`
- `/object` -> `openim-server`
- `/minio` -> `MinIO`

### Server-02

与 `Server-01` 部署完全一致。

建议放在同一个：

- `SLB`
- `Nginx upstream`
- 或其他四层/七层负载均衡

之后共同承接：

- Web 页面访问
- API 访问
- WebSocket 长连接

### Server-03

内部提供：

- `MongoDB`
- `Redis`
- `Kafka`
- `Etcd`
- `MinIO`

这台服务器建议：

- 不直接开放数据库和中间件公网访问
- 只对应用节点开放内网访问

## 5. 每台机器的数据盘建议分配

因为每台都是 `500 GB 数据盘`，建议这样使用。

### Server-01 数据盘

建议分配：

- Docker 数据目录：`100 GB`
- 应用日志：`50 GB`
- 预留扩容空间：`350 GB`

说明：

- 应用节点本身不会长期存大量业务数据
- 给足 Docker 和日志空间就够了
- 剩余空间作为后续扩容和应急缓冲

### Server-02 数据盘

建议分配：

- Docker 数据目录：`100 GB`
- 应用日志：`50 GB`
- 预留扩容空间：`350 GB`

### Server-03 数据盘

建议分配：

- MongoDB：`120 GB`
- MinIO：`250 GB`
- Kafka：`50 GB`
- Redis / Etcd：`20 GB`
- 日志与预留：`60 GB`

说明：

- 数据节点的磁盘重点是 `MongoDB + MinIO`
- 对于 50 人在线，这个容量已经比较宽裕
- 如果后续图片、文件、语音、视频保留时间较长，优先扩容 `MinIO`

## 6. 负载均衡建议

推荐在 `Server-01` 和 `Server-02` 前面增加统一入口。

可选方式：

1. 云厂商 `SLB`
2. 独立反向代理入口
3. DNS 轮询

推荐优先级：

1. `SLB`
2. 反向代理入口
3. DNS 轮询

原因：

- WebSocket 长连接更适合稳定的负载均衡入口
- 后续如果 `electron-web` 用户增加，也更方便扩容

## 7. 为什么这套配置够用

对于 `50 人同时在线聊天` 的目标，这套 `3 x 8C16G` 的方案已经比较充裕，原因是：

- 两台应用节点共同分担长连接和接口流量
- 一台应用节点就足以支撑当前规模，双机后冗余更高
- 数据节点单机 `8C16G` 足以承载当前这套：
  - `MongoDB`
  - `Redis`
  - `Kafka`
  - `Etcd`
  - `MinIO`
- 每台机器 `500 GB` 数据盘，容量明显高于当前 50 人场景的最低要求

## 8. 最终推荐表

如果你要拿去直接汇报，建议使用这张最终表。

| 服务器 | 服务器角色 | 部署内容 | CPU | 内存 | 系统盘 | 数据盘 |
|---|---|---|---:|---:|---:|---:|
| Server-01 | 应用节点 A | `Nginx`、`electron-web`、`openim-server`、`openim-chat` | 8 vCPU | 16 GB | 100 GB | 500 GB |
| Server-02 | 应用节点 B | `Nginx`、`electron-web`、`openim-server`、`openim-chat` | 8 vCPU | 16 GB | 100 GB | 500 GB |
| Server-03 | 数据节点 | `MongoDB`、`Redis`、`Kafka`、`Etcd`、`MinIO` | 8 vCPU | 16 GB | 100 GB | 500 GB |

## 9. 一句话结论

基于你计划申请的 `3 台 8C16G / 100G系统盘 / 500G数据盘`：

- 两台做应用节点
- 一台做数据节点
- `electron-web` 直接部署在两台应用节点上
- 这套方案足以支撑当前 `50 人同时在线聊天` 的目标，并且有比较好的余量

