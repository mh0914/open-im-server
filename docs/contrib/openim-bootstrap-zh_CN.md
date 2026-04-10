# OpenIM 启动后首个管理员与测试用户示例

当前这套 Docker 环境启动后，可直接用仓库里的脚本完成这几步：

1. 获取管理员 token
2. 检查测试用户是否已存在
3. 自动创建缺失的测试用户
4. 为第一个测试用户获取登录 token

脚本位置：

```powershell
scripts/docker/bootstrap-openim-demo.ps1
```

运行示例：

```powershell
Set-Location d:\大连数产\数据流通基础设施\2026年项目\IM\open-im-server
powershell -ExecutionPolicy Bypass -File .\scripts\docker\bootstrap-openim-demo.ps1
```

默认值对应当前 Docker 部署：

- API: `http://127.0.0.1:10002`
- 管理员 userID: `imAdmin`
- 系统 secret: `openIM123`
- 默认测试用户: `demo_user_001`、`demo_user_002`
- 默认用户 platformID: `2`，即 Android

也可以自定义参数：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\docker\bootstrap-openim-demo.ps1 `
  -ApiBaseUrl http://127.0.0.1:10002 `
  -AdminUserID imAdmin `
  -Secret openIM123 `
  -PlatformID 2 `
  -UserIDs demo_user_101,demo_user_102
```

脚本成功后会输出：

- 管理员 token
- 本次新建的用户列表
- 第一个测试用户的 token
- 当前常用服务地址

常用平台 ID：

- `1`: iOS
- `2`: Android
- `3`: Windows
- `5`: Web
- `6`: MiniWeb
- `10`: Admin

说明：

- `get_admin_token` 只需要 `secret + userID`
- `get_user_token` 需要管理员 token，并且 `platformID` 不能填 `10`
- OpenIM Server 本身是后端服务，不自带管理后台网页；如果需要前端客户端，可配合 `openim-electron-demo`、`openim-flutter-demo`、`open-im-android-demo` 等仓库使用
