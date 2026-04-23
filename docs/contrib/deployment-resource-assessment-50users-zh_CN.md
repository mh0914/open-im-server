# OpenIM 50 人在线部署资源评估

## 1. 评估范围

本评估基于当前项目实际结构：

- `open-im-server`
  - 对外提供 `msg_gateway(10001)`、`api(10002)`
  - 依赖 `MongoDB / Redis / Etcd / Kafka / MinIO`
- `chat-main`
  - 对外提供 `chat-api(10008)`、`chat-admin(10009)`
  - 依赖 `open-im-server + MongoDB / Redis / Etcd`
- `openim-electron-demo`
  - 当前是 Electron 桌面端
  - 后续计划改造成 Web 形式部署

当前本地实际运行组件：

- `openim-server`
- `openim-chat`
- `mongo`
- `redis`
- `etcd`
- `kafka`
- `minio`

## 2. 关键结论

### 2.1 50 人同时在线不属于高并发场景

如果是“50 人同时在线聊天”，且消息模型以：

- 文本消息为主
- 图片 / 文件 / 语音 / 短视频为辅
- 不包含大规模直播推流 / 音视频 RTC 集群

那么当前这套系统在资源上是完全可承载的。

### 2.2 真正吃服务器资源的不是 Electron，而是后端和中间件

如果后面把 Electron 改造成 Web 服务：

- 前端本身只是 `Vite build` 出来的静态资源
- 浏览器运行逻辑在用户侧机器，不在服务器侧消耗大量 CPU / 内存
- 服务器新增的只是：
  - 静态文件托管
  - 反向代理
  - WebSocket 转发

所以 Web 化后，服务端资源重点仍然是：

- `open-im-server`
- `openim-chat`
- `MongoDB`
- `Redis`
- `Kafka`
- `MinIO`

### 2.3 资源建议

对于“50 人在线 + 正常图文文件聊天”的目标，建议按下面三档理解：

- 演示/测试最低可用：`4C8G`
- 正式可用且留有余量：`8C16G`
- 更稳妥的生产建议：`12C24G`

如果必须单机部署，建议直接从 `8C16G + SSD` 起步。

## 3. 当前架构拆解

### 3.1 open-im-server 侧

当前 `docker-compose.openim-server.yml` 显示：

- `openim-server`
- `mongodb`
- `redis`
- `etcd`
- `kafka`
- `minio`

其中：

- `openim-server` 负责 API、消息网关、消息写入和路由
- `mongodb` 负责会话、消息、用户与群数据持久化
- `redis` 负责缓存、在线态、部分热数据
- `etcd` 负责配置和服务协调
- `kafka` 负责消息异步链路
- `minio` 负责图片、视频、文件、语音等对象存储

### 3.2 chat-main 侧

当前 `docker-compose.openim-chat.yml` 显示：

- `openim-chat`

它依赖：

- `mongo`
- `redis`
- `etcd`
- `openim-server`

`openim-chat` 主要承接：

- 注册登录
- 业务账号侧接口
- 聊天业务层扩展

### 3.3 Electron 改 Web 后的形态

当前 `openim-electron-demo` 是 Electron 应用，但它本质上是：

- `Vite` 前端
- Electron 外壳
- Electron preload / main 进程能力

改造成 Web 后，服务端部署部分通常变成：

- `Nginx` 或同类 Web 服务器
- 部署 `dist/` 静态文件
- 反代：
  - `/api`
  - `/chat`
  - `/msg_gateway`
  - `/object`
  - `/minio`

## 4. 分服务资源评估

以下是按“50 人同时在线聊天”估算的建议值。

### 4.1 open-im-server

职责：

- HTTP API
- WebSocket 长连接
- 消息投递
- 群聊 / 单聊业务核心逻辑

建议资源：

- 最低：`2 vCPU / 2 GB RAM`
- 建议：`2 vCPU / 4 GB RAM`
- 稳妥：`4 vCPU / 4~8 GB RAM`

说明：

- 50 人在线时，CPU 压力一般不大
- WebSocket 长连接和消息 fan-out 更依赖内存稳定性
- 如果群消息、系统提示、文件消息较多，建议至少 `4 GB RAM`

### 4.2 openim-chat

职责：

- 登录注册
- 账号侧业务接口
- 群扩展业务接口

建议资源：

- 最低：`1 vCPU / 1 GB RAM`
- 建议：`2 vCPU / 2 GB RAM`
- 稳妥：`2 vCPU / 4 GB RAM`

说明：

- `chat` 相比 `server` 更偏业务接口
- 50 人在线下压力不会特别大
- 如果后续把聊天室的角色、黑名单、禁言、群资料扩展都堆在 `chat` 层，建议按 `2C2G` 起步

### 4.3 MongoDB

职责：

- 消息记录
- 会话
- 用户/群资料
- 群成员关系

建议资源：

- 最低：`2 vCPU / 4 GB RAM / 50 GB SSD`
- 建议：`2 vCPU / 6 GB RAM / 100 GB SSD`
- 稳妥：`4 vCPU / 8 GB RAM / 200 GB SSD`

说明：

- 这是当前最重要的持久化组件
- 即使只有 50 人在线，消息历史和索引也会稳定增长
- 如果要保存图片、文件、位置、禁言记录、历史筛选结果等，Mongo 盘空间必须留余量

### 4.4 Redis

职责：

- 在线态
- 热缓存
- 快速读写状态

建议资源：

- 最低：`1 vCPU / 512 MB RAM`
- 建议：`1 vCPU / 1 GB RAM`
- 稳妥：`1 vCPU / 2 GB RAM`

说明：

- 50 人在线下 Redis 压力很小
- 更重要的是稳定与持久化策略，而不是绝对资源

### 4.5 Kafka

职责：

- 异步消息链路
- 解耦消息生产和消费

建议资源：

- 最低：`1~2 vCPU / 2 GB RAM`
- 建议：`2 vCPU / 4 GB RAM`
- 稳妥：`4 vCPU / 4~8 GB RAM`

说明：

- 单节点 Kafka 在小规模场景可用
- 50 人在线下，吞吐不是瓶颈
- 但 Kafka 本身比较“吃内存体验”，建议不要压得太低

### 4.6 Etcd

职责：

- 配置与服务协调

建议资源：

- 最低：`1 vCPU / 512 MB RAM`
- 建议：`1 vCPU / 1 GB RAM`

说明：

- 在这套场景里压力较小
- 更重要的是数据稳定和磁盘延迟

### 4.7 MinIO

职责：

- 图片消息
- 文件消息
- 语音消息
- 视频消息

建议资源：

- 最低：`1 vCPU / 1 GB RAM / 100 GB SSD`
- 建议：`2 vCPU / 2 GB RAM / 200 GB SSD`
- 稳妥：`2 vCPU / 4 GB RAM / 500 GB SSD`

说明：

- 媒体类消息真正吃的是对象存储容量和公网带宽
- 如果 50 人只是文本聊天，MinIO 压力很轻
- 如果 50 人频繁发图片、语音、视频，瓶颈会更快落在：
  - 磁盘容量
  - 上传带宽
  - 下载带宽

## 5. Electron 改 Web 后所需资源

## 5.1 前端部署方式

Electron 改 Web 后，建议部署形态：

- `Nginx`
- 前端静态资源 `dist/`

服务端资源建议：

- 最低：`1 vCPU / 512 MB RAM / 5 GB SSD`
- 建议：`1 vCPU / 1 GB RAM / 10 GB SSD`
- 稳妥：`2 vCPU / 2 GB RAM / 20 GB SSD`

说明：

- 这部分只是托管静态文件和反向代理
- 50 个用户同时打开页面，对前端静态服务压力很小

## 5.2 Web 化改造注意事项

当前 `openim-electron-demo` 并不是“直接 build 就能上 Web”的纯浏览器项目，因为它依赖了 Electron 能力：

- `@openim/electron-client-sdk`
- `window.electronAPI`
- `preload`
- `saveFileToDisk`
- 窗口控制
- Electron 本地路径与日志目录能力

这意味着改造成 Web 版本时，至少要处理：

1. SDK 适配
- 从 Electron render SDK 逐步切换到 Web/WASM 可运行方案

2. 文件与媒体能力适配
- 去掉本地磁盘保存依赖
- 改成浏览器原生上传 / 下载 / Blob 处理

3. 窗口控制适配
- 最小化、最大化、关闭窗口逻辑需要移除或替换

4. 本地持久化适配
- Electron keystore / 本地路径调用改为浏览器存储方案

所以：

- **Electron 改 Web 对服务器资源影响不大**
- **对前端代码改造量影响比较大**

## 6. 50 人在线推荐部署方案

## 6.1 单机合并部署

适合：

- 招投标演示
- 初期试运行
- 小规模正式使用

建议配置：

- `8 vCPU`
- `16 GB RAM`
- `200 GB SSD`
- `10~20 Mbps` 公网带宽

部署内容：

- `Nginx`
- `openim-server`
- `openim-chat`
- `MongoDB`
- `Redis`
- `Kafka`
- `Etcd`
- `MinIO`
- Web 前端静态资源

优点：

- 架构简单
- 运维成本低
- 适合当前规模

风险：

- 单点故障
- Mongo/Kafka/MinIO 抢同一台机器资源

## 6.2 推荐拆分部署

适合：

- 后续要扩容
- 对稳定性要求更高

建议配置：

### 应用节点

- `4 vCPU / 8 GB RAM / 100 GB SSD`

部署：

- `Nginx`
- Web 前端
- `openim-server`
- `openim-chat`

### 数据节点

- `4~8 vCPU / 8~16 GB RAM / 200~500 GB SSD`

部署：

- `MongoDB`
- `Redis`
- `Kafka`
- `Etcd`
- `MinIO`

优点：

- 应用和数据拆开
- 扩容更容易
- 稳定性更好

## 7. 带宽与存储建议

### 7.1 带宽

如果以文字聊天为主：

- `5 Mbps` 也能跑

如果包含图片、语音、文件、短视频：

- 建议 `10~20 Mbps`

如果图片/视频较频繁：

- 建议 `20 Mbps+`

### 7.2 存储

建议初始规划：

- MongoDB：`50~100 GB`
- MinIO：`100~200 GB`
- 日志：`10~20 GB`

如果要长期保留聊天媒体：

- MinIO 建议直接从 `200 GB+` 起步

## 8. 最终建议

如果你后面要把 Electron 改成 Web，并支持 50 人同时在线聊天，我建议按下面执行：

### 方案 A：单机上线

- `8C16G`
- `200 GB SSD`
- `10~20 Mbps`

适合当前阶段，能比较稳地承接 50 人在线聊天和常规图文文件消息。

### 方案 B：应用/数据分离

- 应用节点：`4C8G`
- 数据节点：`4C8G` 起步，推荐 `8C16G`

适合后面继续做正式部署和扩容。

### 方案 C：仅用于演示

- `4C8G`
- `100 GB SSD`

可以跑，但更适合演示和试运行，不建议作为长期正式承载配置。

## 9. 一句话结论

对于“聊天室 + 单聊 + 图片/文件/语音/视频 + 50 人同时在线”这类规模：

- **后端建议至少 `8C16G` 单机**
- **Electron 改 Web 后，前端静态服务几乎不构成资源瓶颈**
- **真正要优先保证的是 Mongo、MinIO、Kafka 和 open-im-server 的稳定资源**

