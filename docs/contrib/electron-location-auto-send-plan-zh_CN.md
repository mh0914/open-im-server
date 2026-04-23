# Electron 自动发送位置方案

## 当前现状

当前客户端的位置消息是手工输入模式：

- 入口文件：`openim-electron-demo/src/pages/chat/queryChat/ChatFooter/SendActionBar/index.tsx`
- 消息构造：`openim-electron-demo/src/pages/chat/queryChat/ChatFooter/SendActionBar/useFileMessage.ts`
- 当前发送内容：`description`、`longitude`、`latitude`

这已经能把位置消息发出去，但体验更像“录入经纬度”，还不是微信那种“打开地图 -> 获取当前位置 -> 选点/确认 -> 发送”。

## 结论

可以做成接近微信的体验，但推荐分成两层：

1. 定位能力
   - 获取当前经纬度
2. 地图能力
   - 地图展示
   - 逆地理编码，把经纬度转成“北京市朝阳区某某路”
   - POI 搜索与选点

仅靠 Electron 原生 `navigator.geolocation` 不够稳，不建议作为最终方案。

## 为什么不建议只用 Electron 原生定位

Electron 官方文档明确提到：

- 应用如果要使用 Geolocation，需要配置 `GOOGLE_API_KEY`
- 权限要通过 `session.setPermissionRequestHandler` / `setPermissionCheckHandler` 放行

这有两个问题：

1. 依赖 Google Geolocation 服务
   - 在国内网络环境下不稳定
2. 只有坐标，没有完整地图和 POI 选择体验

所以它最多适合作为兜底或调试方案，不适合作为你这套项目的正式实现方案。

## 推荐方案

### 方案 A：高德地图 JSAPI

推荐指数：高

适合你当前这套 Electron + React 客户端，原因是：

- 国内可用性更好
- 前端集成成本低
- 同时覆盖定位、逆地理编码、地点搜索、地图选点
- 可以直接做成“像微信”的交互

建议能力组合：

- Geolocation：获取当前位置
- Geocoder：把经纬度转地址描述
- PlaceSearch / AutoComplete：搜索附近地点
- Map + Marker：允许用户拖动或点击修正位置

推荐交互：

1. 用户点击“位置”
2. 打开地图弹窗
3. 自动获取当前位置并居中地图
4. 自动解析当前位置描述
5. 用户可直接发送当前位置，或搜索/拖动选择其他点
6. 最终仍调用现有 `IMSDK.createLocationMessage({ description, longitude, latitude })`

### 方案 B：腾讯位置服务

推荐指数：中

如果你的业务未来更偏微信生态，可以选腾讯位置服务。优势是生态一致性更强，但从你当前客户端技术栈出发，首轮改造成本与高德接近，整体没有明显优势。

### 方案 C：Electron 原生定位 + 第三方逆地理编码

推荐指数：低

做法是：

- Electron 放行 geolocation 权限
- 前端调用 `navigator.geolocation.getCurrentPosition`
- 再调用地图服务做逆地理编码

这个方案问题是：

- 仍然依赖 Electron 的 geolocation 能力
- 国内环境下稳定性不如直接用国内地图 SDK
- 地图选点、POI 搜索仍要另外补

## 推荐落地决策

建议直接选：

- 地图供应商：高德地图
- 客户端实现：地图弹窗 + 自动定位 + 逆地理编码 + 搜索选点
- 消息协议：继续沿用现有 `LocationMessage`

也就是说：

- `open-im-server` 不需要再改协议
- `chat-main` 不需要新增位置消息业务接口
- 主要改造点集中在 `openim-electron-demo`

## 代码改造清单

### 1. Electron 主进程权限放行

修改文件：

- `openim-electron-demo/electron/main/index.ts`

需要新增：

- `session.defaultSession.setPermissionCheckHandler`
- `session.defaultSession.setPermissionRequestHandler`

目的：

- 放行 `geolocation` 权限
- 避免地图定位组件在 Electron 中直接被拦截

### 2. 新增地图配置

修改文件：

- `openim-electron-demo/.env`

建议新增：

- `VITE_MAP_PROVIDER=amap`
- `VITE_AMAP_KEY=你的高德Key`

如果后续需要切腾讯，也可以预留：

- `VITE_TENCENT_MAP_KEY=你的腾讯Key`

### 3. 将“位置消息弹窗”从手工输入改成地图弹窗

修改文件：

- `openim-electron-demo/src/pages/chat/queryChat/ChatFooter/SendActionBar/index.tsx`

当前弹窗内容是：

- 描述输入框
- 经度输入框
- 纬度输入框

建议改成：

- 地图容器
- “获取当前位置”按钮
- 当前选中地址展示
- 搜索框
- POI 列表
- “发送当前位置”按钮

### 4. 新增地图服务封装

建议新增文件：

- `openim-electron-demo/src/services/map/amap.ts`
- `openim-electron-demo/src/services/map/types.ts`

封装内容：

- 加载高德 JSAPI
- 获取当前位置
- 逆地理编码
- POI 搜索
- 坐标与地址结构统一

### 5. 新增位置选择组件

建议新增文件：

- `openim-electron-demo/src/components/LocationPicker/index.tsx`

职责：

- 打开地图
- 自动定位
- 拖点选点
- 搜索地点
- 输出统一结构：
  - `description`
  - `longitude`
  - `latitude`

### 6. 位置消息发送层保持不变

当前文件：

- `openim-electron-demo/src/pages/chat/queryChat/ChatFooter/SendActionBar/useFileMessage.ts`

当前方法：

- `getLocationMessage(location)`

这层可以继续保留，最多做轻量调整，不需要重构协议。

## 建议的交互细节

为了更接近微信，建议这样做：

1. 进入位置弹窗后立即尝试定位
2. 定位成功后：
   - 地图自动居中
   - 自动放置标记
   - 自动显示地址描述
3. 用户可以：
   - 直接发送当前位置
   - 搜索其他地点
   - 拖动地图后重新确认
4. 最终发送内容：
   - 描述使用地址或 POI 名称
   - 坐标使用地图 SDK 返回结果

## 风险与注意点

### 1. 需要地图 Key

无论高德还是腾讯，正式实现都需要 Key。

这也是当前不建议我直接硬上代码的原因：没有 Key 时只能做半成品，跑不稳。

### 2. 坐标系要统一

国内地图常见是 GCJ-02。

建议：

- 如果用高德地图定位，就直接沿用高德返回坐标
- 不要混用浏览器原生坐标和地图 SDK 坐标

### 3. Windows 系统定位服务

即便使用地图 SDK，Windows 本机的定位权限仍可能影响精度。

所以产品上要准备两种结果：

- 精确定位成功
- 回退到城市级或附近位置

## 我建议的下一步

如果你准备开始做这项改造，最顺的推进方式是：

1. 你提供一个高德地图 Key
2. 我先在 `dev` 分支把 Electron 的位置发送升级成“地图选点版”
3. 完成后自动重打本地安装包并重装测试

## 参考资料

- Electron 环境变量文档：
  - https://www.electronjs.org/docs/api/environment-variables/
- Electron `session` 权限处理文档：
  - https://www.electronjs.org/docs/latest/api/session
- 高德地图官方示例仓库（包含 Geolocation、Geocoder、PlaceSearch 的地图选点思路）：
  - https://github.com/amap-demo/web-route-base-on-geolocation-and-placesearch
