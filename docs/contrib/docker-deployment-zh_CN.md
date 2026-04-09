# OpenIM Server Docker 部署说明

本文档对应当前仓库补充的最小可运行部署方案，目标是启动：

- `openim-server`
- MongoDB
- Redis
- etcd
- Kafka
- MinIO

如果你要部署完整的 `openim-server + openim-chat + 前端` 套件，优先参考官方 `openim-docker` 仓库。

## 1. 本方案和官方方案的关系

当前仓库原生提供了：

- 根目录 `Dockerfile`，用于构建 `openim-server` 镜像
- 根目录 `docker-compose.yml`，用于启动依赖组件

但它没有把 `openim-server` 自己编进 Compose。为方便本地使用，我补充了一份部署编排文件：

```text
deployments/docker/docker-compose.openim-server.yml
```

## 2. 第一步：准备变量文件

在仓库根目录执行：

```powershell
Set-Location d:\大连数产\数据流通基础设施\2026年项目\IM\open-im-server
Copy-Item .\deployments\docker\.env.example .\deployments\docker\.env
```

然后按需修改 `deployments/docker/.env`，至少确认这几项：

```text
OPENIM_SERVER_IMAGE=local/openim-server:v3.8.3-local
MINIO_EXTERNAL_ADDRESS=http://你的主机IP:10005
OPENIM_API_PORT=10002
OPENIM_MSG_GATEWAY_PORT=10001
```

说明：

- `MINIO_EXTERNAL_ADDRESS` 要填客户端实际能访问到的地址
- `OPENIM_SERVER_IMAGE` 要和你实际构建出的镜像一致

## 3. 第二步：生成 Docker 专用配置

源码默认配置是给源码直跑准备的，依赖地址大多指向 `localhost`。容器里必须改成服务名地址。

执行：

```powershell
.\scripts\docker\prepare-docker-config.ps1
```

执行后会生成目录：

```text
deployments/docker/config
```

这套配置会把关键依赖改成：

- MongoDB: `mongo:27017`
- Redis: `redis:6379`
- etcd: `etcd:2379`
- Kafka: `kafka:9092`
- MinIO: `minio:9000`

同时会同步：

- `share.yml` 里的 `secret`
- `log.yml` 的 stdout 输出和日志级别
- MinIO、MongoDB、Redis、Kafka、etcd 的凭据

## 4. 第三步：启动服务

进入部署目录：

```powershell
Set-Location .\deployments\docker
docker compose --env-file .env -f .\docker-compose.openim-server.yml up -d
```

查看状态：

```powershell
docker compose --env-file .env -f .\docker-compose.openim-server.yml ps
```

查看日志：

```powershell
docker logs -f openim-server
docker logs -f mongo
docker logs -f kafka
```

停止服务：

```powershell
docker compose --env-file .env -f .\docker-compose.openim-server.yml down
```

## 5. 默认对外端口

默认会开放这些端口：

- `10001`：OpenIM WebSocket 网关
- `10002`：OpenIM API
- `10005`：MinIO 对外端口
- `10004`：MinIO Console
- `16379`：Redis 映射端口
- `37017`：MongoDB 映射端口
- `12379`：etcd 客户端端口
- `19094`：Kafka 对外端口

## 6. 一个重要实现细节

Kafka 在这份编排里分成两种访问地址：

- 容器内部访问：`kafka:9092`
- 主机外部访问：`localhost:19094`

因此我在 Docker 专用配置里把 OpenIM 的 Kafka 地址固定成了 `kafka:9092`。这一步不要改回 `localhost:19094`，否则容器里的 OpenIM 会把 Kafka 连到自己容器内部。

## 7. 故障排查建议

如果 `openim-server` 启动失败，优先检查：

1. `deployments/docker/config` 是否已经重新生成
2. `.env` 里的 `OPENIM_SERVER_IMAGE` 是否真的是本地存在的镜像
3. `MINIO_EXTERNAL_ADDRESS` 是否还是示例值
4. 端口是否被占用
5. Docker 日志里是否出现 MongoDB、Kafka、etcd 连接失败

可以快速检查镜像：

```powershell
docker images | Select-String openim
```

可以快速检查容器：

```powershell
docker ps -a
```

## 8. 推荐完整流程

```powershell
Set-Location d:\大连数产\数据流通基础设施\2026年项目\IM\open-im-server
Copy-Item .\deployments\docker\.env.example .\deployments\docker\.env
.\scripts\docker\prepare-docker-config.ps1
.\scripts\docker\build-openim-images.ps1 -Mode monolith -Registry local -Tag v3.8.3-local
Set-Location .\deployments\docker
docker compose --env-file .env -f .\docker-compose.openim-server.yml up -d
```

如果你后续还要把这套环境交付到离线服务器，建议在构建镜像时追加 `-SaveTar`，直接导出离线 Docker 包。
