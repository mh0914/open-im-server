# OpenIM Server Docker 打包说明

本文档面向当前仓库 `open-im-server`，重点说明两类镜像的打包方式：

- 单体镜像：根目录 `Dockerfile`，产物为 `openim-server`
- 拆分服务镜像：`build/images/*/Dockerfile`，产物为 `openim-api`、`openim-rpc-user` 等独立服务镜像

## 1. 先说结论

当前仓库的 Docker 相关资产可以分成两条路线：

- 本仓库负责构建 OpenIM Server 镜像
- 官方整套 Compose 部署更偏向使用 `openim-docker` 仓库

这也是为什么本仓库根目录的 `docker-compose.yml` 主要是 MongoDB、Redis、Kafka、etcd、MinIO 等依赖组件，而没有直接把 `openim-server` 服务编排进去。

为了方便本地落地，我补充了以下文件：

- `scripts/docker/build-openim-images.ps1`：构建单体镜像或拆分服务镜像
- `scripts/docker/prepare-docker-config.ps1`：生成容器网络可用的配置文件
- `deployments/docker/.env.example`：统一变量入口
- `deployments/docker/docker-compose.openim-server.yml`：最小可运行部署编排

## 2. 环境要求

- Docker Desktop 或 Docker Engine
- Docker Compose 插件

本机如果还没有 Docker，可以先确认：

```powershell
docker --version
docker compose version
```

## 3. 打包单体镜像

单体镜像使用仓库根目录的 `Dockerfile`，构建后容器会通过 `mage start` 启动全部 OpenIM 服务进程。

示例：

```powershell
Set-Location d:\大连数产\数据流通基础设施\2026年项目\IM\open-im-server
.\scripts\docker\build-openim-images.ps1 -Mode monolith -Registry local -Tag v3.8.3-local
```

构建完成后，镜像名默认是：

```text
local/openim-server:v3.8.3-local
```

## 4. 打包拆分服务镜像

如果你想按服务拆分镜像，可以使用：

```powershell
.\scripts\docker\build-openim-images.ps1 -Mode services -Registry local -Tag v3.8.3-local
```

会构建这些镜像：

- `openim-api`
- `openim-crontask`
- `openim-msggateway`
- `openim-msgtransfer`
- `openim-push`
- `openim-rpc-auth`
- `openim-rpc-conversation`
- `openim-rpc-friend`
- `openim-rpc-group`
- `openim-rpc-msg`
- `openim-rpc-third`
- `openim-rpc-user`

如果只打部分服务：

```powershell
.\scripts\docker\build-openim-images.ps1 -Mode services -Registry local -Tag v3.8.3-local -ServiceNames openim-api,openim-msggateway
```

## 5. 导出离线 Docker 包

如果你要把镜像带到离线环境，可以在构建时直接导出 tar 包：

```powershell
.\scripts\docker\build-openim-images.ps1 -Mode monolith -Registry local -Tag v3.8.3-local -SaveTar
```

导出目录默认是：

```text
artifacts/docker
```

离线导入示例：

```powershell
docker load -i .\artifacts\docker\openim-server-v3.8.3-local.tar
```

## 6. 变量建议

镜像构建完成后，建议把 `deployments/docker/.env.example` 复制成 `.env`，并把 `OPENIM_SERVER_IMAGE` 改成你刚构建好的镜像，例如：

```text
OPENIM_SERVER_IMAGE=local/openim-server:v3.8.3-local
```

## 7. 一个关键差异

源码默认配置里的依赖地址是本机模式：

- MongoDB: `localhost:37017`
- Redis: `localhost:16379`
- etcd: `localhost:12379`
- Kafka: `localhost:19094`
- MinIO: `localhost:10005`

容器部署时这些地址不能直接沿用，所以部署前必须先执行配置生成脚本，把它们改成容器网络地址，例如：

- MongoDB: `mongo:27017`
- Redis: `redis:6379`
- etcd: `etcd:2379`
- Kafka: `kafka:9092`
- MinIO: `minio:9000`

## 8. 推荐配套流程

```powershell
Copy-Item .\deployments\docker\.env.example .\deployments\docker\.env
.\scripts\docker\prepare-docker-config.ps1
.\scripts\docker\build-openim-images.ps1 -Mode monolith -Registry local -Tag v3.8.3-local -SaveTar
```

随后按 `docs/contrib/docker-deployment-zh_CN.md` 继续部署即可。
