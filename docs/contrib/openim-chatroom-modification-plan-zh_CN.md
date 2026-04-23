# OpenIM 聊天室改造详细方案

## 1. 基线版本说明

当前三个仓库已经打上统一基线标签：

- Tag 名称：`im-native-version`
- Tag 说明：`IM原生版本`

对应提交如下：

- `open-im-server`：`229138f49a82ab2d884fbe35c60dfd22c5ed04c3`
- `chat-main`：`df6ce24c3ae2e1666a08cc81f53e6d7c103ac987`
- `openim-electron-demo`：`5bcf42772279ec00ee2373a0e3331b34276edbef`

说明：

1. 该标签记录的是当前本地开发基线，也就是目前 `dev` 分支所处的原生 OpenIM 版本。
2. 后续聊天室改造建议从这个基线开始分阶段推进。

## 2. 改造原则

本次改造建议采用“原生 OpenIM 群组能力作为底座，新增聊天室业务适配层”的方式，而不是直接深改 OpenIM 内核。

推荐原则如下：

1. `open-im-server` 内部核心 RPC、proto、存储模型中的 `group` 概念尽量保留。
2. 对外业务 API、前端 UI、文案、字段命名统一改造成 `chatroom / 聊天室`。
3. `chat-main` 作为业务层，承担“群组 -> 聊天室”的映射、补充字段和补充规则。
4. `openim-electron-demo` 作为终端展示层，完成命名替换、页面替换和缺失功能落地。

这样做的原因：

1. 改动风险更可控。
2. 可以最大化复用 OpenIM 原生群组、消息、通知、禁言、角色能力。
3. 后续即使再引入独立聊天室模型，也能平滑升级。

## 3. 不建议直接做的改动

以下内容不建议在第一阶段直接深改：

1. 不建议把 `open-im-server` 内部所有 `group` RPC / proto / 表名全部重命名为 `chatroom`。
2. 不建议第一阶段就改 OpenIM SDK 原生对象名，例如把 `GroupItem` 改成 `ChatroomItem`。
3. 不建议第一阶段修改消息网关、会话同步、群组通知的底层核心流程。

原因：

1. 这些属于 OpenIM 核心引擎层。
2. 深改后会显著增加升级成本。
3. 后续很难再与上游 OpenIM 同步。

## 4. 推荐的总体技术路线

### 4.1 架构定位

- `open-im-server`
  - 保留原生 IM 能力和群组能力
  - 只补必要的底层能力缺口
- `chat-main`
  - 新增聊天室业务模型
  - 提供 `/chatroom/*` 业务 API
  - 内部调用 `open-im-server` 的 `/group/*` 和 `/msg/*`
- `openim-electron-demo`
  - 完成“群组产品”向“聊天室产品”的命名和页面改造
  - 增加多媒体消息发送与渲染

### 4.2 改造层级

第一层：命名适配

- 对外名称从“群组/群聊”改为“聊天室”
- 对外字段从 `groupID` 映射为 `chatroomID`
- 对外角色从 `owner/admin/normal` 映射为 `房主/管理员/固定成员`

第二层：能力补齐

- 补齐语音、视频、文件、位置消息
- 补齐聊天室状态、黑名单、公告扩展字段、直播地址等

第三层：规则增强

- 游客/匿名游客
- 聊天室在线人数
- 聊天室 10 天历史策略
- 聊天室生命周期控制

## 5. 命名改造映射表

| 原生 OpenIM 概念 | 改造后业务概念 | 说明 |
| --- | --- | --- |
| Group / 群组 | ChatRoom / 聊天室 | 对外统一改名，底层仍复用 Group |
| groupID | chatroomID | 对外 API 和 UI 字段改名 |
| groupName | chatroomName | UI 与业务模型改名 |
| ownerUserID | roomOwnerUserID / 房主 | 对外角色语义调整 |
| admin | moderator / 管理员 | 保留管理语义 |
| normal member | fixedMember / 固定成员 | 对应需求中的固定成员 |
| notification | announcement / 公告 | 群公告改为聊天室公告 |
| introduction | description / 简介 | 房间简介 |
| faceURL | avatar / 封面 | 房间头像/封面 |
| set_group_info | update_chatroom_info | 对外接口改名 |
| get_groups_info | get_chatroom_info | 对外接口改名 |
| get_group_members_info | get_chatroom_members | 对外接口改名 |
| kick_group | kick_chatroom_member | 对外接口改名 |
| mute_group_member | mute_chatroom_member | 对外接口改名 |
| mute_group | mute_chatroom_all | 对外接口改名 |
| set_group_member_info | set_chatroom_member_info | 对外接口改名 |

## 6. 仓库级修改计划

## 6.1 open-im-server 修改计划

`open-im-server` 作为底层 IM 引擎，建议只做必要增强，不做大面积领域重命名。

### A. 消息能力增强

1. 补齐位置消息 HTTP 映射
   - 文件：`internal/api/msg.go`
   - 当前问题：`send_msg` 未处理 `Location` 类型
   - 修改目标：增加 `constant.Location -> apistruct.LocationElem` 映射

2. 明确消息发送接口分层
   - 保留管理侧 `POST /msg/send_msg`
   - 增加更清晰的业务层说明，普通终端继续走 SDK / WebSocket
   - 如果后续需要统一业务接口，可在 `chat-main` 增加聊天室消息业务封装，不建议直接改 `open-im-server`

3. 增加消息能力配置开关
   - 文本 / 图片 / 语音 / 视频 / 文件 / 位置 / 自定义
   - 作用：为聊天室消息类型控制提供底层支持

### B. 群组能力复用增强

1. 保持以下群组能力不变，并作为聊天室底座：
   - 建群
   - 查群
   - 更新群
   - 群角色
   - 成员禁言
   - 全员禁言
   - 踢成员
   - 修改成员信息

2. 对群组扩展字段 `ex` 的使用规范化
   - 约定聊天室映射信息写入 `group.ex`
   - 例如：
     - `roomType`
     - `liveURL`
     - `sendUpdateNotification`
     - `noticeEventEx`

3. 增加聊天室业务通知所需的系统消息模板
   - 聊天室开启
   - 聊天室关闭
   - 聊天室公告变更
   - 聊天室直播地址变更
   - 聊天室全员禁言开启/关闭

### C. 不在第一阶段改造的内容

1. 不改 proto 包名
2. 不改 `group` RPC 服务名
3. 不改底层 Mongo 表名
4. 不改原生 SDK 会话类型

## 6.2 chat-main 修改计划

`chat-main` 是本次聊天室改造的主战场。

### A. 新增聊天室业务域

建议新增以下业务对象：

1. `ChatroomInfo`
   - `chatroomID`
   - `groupID`
   - `chatroomName`
   - `announcement`
   - `description`
   - `avatar`
   - `liveURL`
   - `status`
   - `sendUpdateNotification`
   - `noticeEventEx`
   - `roomType`
   - `ex`

2. `ChatroomMember`
   - `chatroomID`
   - `userID`
   - `memberType`
   - `roleLevel`
   - `nickname`
   - `faceURL`
   - `muteEndTime`
   - `joinTime`
   - `ex`

3. `ChatroomBlacklist`
   - `chatroomID`
   - `userID`
   - `operatorUserID`
   - `reason`
   - `createTime`

4. `ChatroomOnlineStat`
   - `chatroomID`
   - `onlineCount`
   - `guestCount`
   - `anonymousCount`

### B. 新增聊天室对外 API

建议新增一组新的业务 API，由 `chat-main` 对外暴露：

1. `POST /chatroom/create`
2. `POST /chatroom/get`
3. `POST /chatroom/update`
4. `POST /chatroom/set_status`
5. `POST /chatroom/get_members`
6. `POST /chatroom/update_member`
7. `POST /chatroom/kick_member`
8. `POST /chatroom/mute_member`
9. `POST /chatroom/cancel_mute_member`
10. `POST /chatroom/mute_all`
11. `POST /chatroom/cancel_mute_all`
12. `POST /chatroom/add_blacklist`
13. `POST /chatroom/remove_blacklist`
14. `POST /chatroom/get_blacklist`
15. `POST /chatroom/get_history`
16. `POST /chatroom/send_message`
17. `POST /chatroom/get_message_types`
18. `POST /chatroom/set_message_types`

### C. API 内部实现映射

这些新 API 的内部建议映射：

1. `chatroom/create`
   - 调用 `open-im-server /group/create_group`
   - 额外写入 `chatroom_info`

2. `chatroom/get`
   - 调用 `open-im-server /group/get_groups_info`
   - 再合并 `chatroom_info`

3. `chatroom/update`
   - 调用 `open-im-server /group/set_group_info`
   - 再更新 `chatroom_info`

4. `chatroom/get_members`
   - 调用 `open-im-server /group/get_group_members_info`
   - 再合并业务成员类型信息

5. `chatroom/update_member`
   - 调用 `open-im-server /group/set_group_member_info`
   - 再更新业务扩展字段

6. `chatroom/kick_member`
   - 调用 `open-im-server /group/kick_group`

7. `chatroom/mute_member`
   - 调用 `open-im-server /group/mute_group_member`

8. `chatroom/mute_all`
   - 调用 `open-im-server /group/mute_group`

9. `chatroom/send_message`
   - 管理侧可走 `/msg/send_msg`
   - 终端侧保持走 IM SDK
   - `chat-main` 只负责做业务校验和策略控制

### D. 新增业务规则

1. 聊天室开关状态
   - `open`
   - `closed`
   - `readonly`

2. 聊天室消息类型开关
   - 是否允许文本
   - 是否允许图片
   - 是否允许语音
   - 是否允许视频
   - 是否允许文件
   - 是否允许位置
   - 是否允许自定义消息

3. 聊天室历史策略
   - 默认保留 10 天
   - 是否开启云端历史
   - 是否允许按消息类型存储历史

4. 聊天室在线统计
   - 通过 Redis 维护在线人数
   - 区分固定成员/游客/匿名游客

### E. 新增成员体系

当前原生群组成员角色只有：

- Owner
- Admin
- Normal

需求里的聊天室建议扩展为：

1. 房主
2. 管理员
3. 固定成员
4. 普通游客
5. 匿名游客

实现建议：

1. OpenIM 原生群角色仍然只保留：
   - Owner
   - Admin
   - Normal
2. 业务层额外增加 `memberType`
   - `fixed`
   - `visitor`
   - `anonymous`

### F. 黑名单能力新增

当前系统只有“用户黑名单”，没有“聊天室黑名单”。

需要新增：

1. 房间级黑名单表
2. 进房前校验
3. 发言前校验
4. 黑名单变更通知

## 6.3 openim-electron-demo 修改计划

Electron 侧的改造重点是“命名改造 + 页面改造 + 多媒体消息补齐”。

### A. 全局命名替换

需要统一替换以下对外显示名称：

1. 群聊 -> 聊天室
2. 群组 -> 聊天室
3. 群成员 -> 聊天室成员
4. 群主 -> 房主
5. 管理员 -> 聊天室管理员
6. 退出群组 -> 退出聊天室
7. 解散群组 -> 关闭聊天室 / 解散聊天室

涉及范围：

1. `i18n` 文案
2. 路由名
3. 菜单名
4. 弹窗标题
5. 设置页字段名

### B. 页面与组件改造

1. 创建群弹窗 -> 创建聊天室弹窗
2. 群设置页 -> 聊天室设置页
3. 群成员列表 -> 聊天室成员列表
4. 群角色管理 -> 聊天室角色管理
5. 群公告 -> 聊天室公告
6. 增加聊天室状态页
7. 增加聊天室黑名单页
8. 增加聊天室消息类型控制页

### C. 消息发送入口补齐

当前明显已有：

1. 文本发送
2. 图片发送
3. RTC 自定义消息

需要新增：

1. 语音消息发送入口
2. 视频消息发送入口
3. 文件消息发送入口
4. 位置消息发送入口

### D. 消息渲染补齐

当前明确渲染：

1. 文本消息
2. 图片消息

需要新增：

1. 语音消息渲染组件
2. 视频消息渲染组件
3. 文件消息渲染组件
4. 位置消息渲染组件
5. 自定义消息通用渲染组件
6. 聊天室业务通知渲染组件
7. 提示消息渲染组件

### E. 聊天室成员类型展示

需要在成员列表和头像区分显示：

1. 房主
2. 管理员
3. 固定成员
4. 普通游客
5. 匿名游客

### F. 权限与操作入口控制

根据成员类型和角色显示不同操作：

1. 房主
   - 修改聊天室信息
   - 设置管理员
   - 黑名单管理
   - 全员禁言
   - 关闭聊天室

2. 管理员
   - 禁言成员
   - 踢出成员
   - 管理公告

3. 固定成员
   - 修改自己的成员资料

4. 游客
   - 只读或按配置发言

5. 匿名游客
   - 不显示真实身份

## 7. 按需求清单拆解的详细修改点

下面这部分可直接拿去和需求清单逐条比对。

### 7.1 文本消息

修改点：

1. 对外名称改为“聊天室文本消息”
2. 聊天室会话中继续复用原生文本消息发送
3. 支持聊天室消息类型开关控制文本是否可发

### 7.2 图片消息

修改点：

1. 对外名称改为“聊天室图片消息”
2. 继续复用原生图片消息结构
3. 增加聊天室发送权限控制

### 7.3 语音消息

修改点：

1. Electron 增加录音入口
2. Electron 增加语音播放组件
3. 聊天室消息策略中增加“是否允许语音”

### 7.4 视频消息

修改点：

1. Electron 增加视频上传入口
2. Electron 增加视频卡片与播放
3. 聊天室消息策略中增加“是否允许视频”

### 7.5 文件消息

修改点：

1. Electron 增加文件发送入口
2. Electron 增加文件卡片
3. 聊天室消息策略中增加“是否允许文件”

### 7.6 地理位置消息

修改点：

1. `open-im-server` 补位置消息 HTTP 映射
2. Electron 增加地图位置选择入口
3. Electron 增加位置卡片和地图跳转
4. 聊天室消息策略中增加“是否允许位置”

### 7.7 通知消息

修改点：

1. 新增聊天室事件通知类型
2. 聊天室开启/关闭/公告更新/直播地址更新时自动下发通知
3. 区分“系统通知”“业务通知”“聊天室通知”

### 7.8 提示消息

修改点：

1. 增加聊天室提示消息类型
2. 输入中、权限不足、禁言剩余时间、房间已关闭等统一走 Tip 流

### 7.9 自定义消息

修改点：

1. 保留 RTC 自定义消息
2. 增加聊天室业务自定义消息 schema
3. 增加客户端通用渲染注册机制

### 7.10 系统通知消息

修改点：

1. 现有好友/群系统通知保留
2. 增加聊天室系统通知分类
3. 增加自定义系统通知扩展字段

### 7.11 新建聊天室

修改点：

1. 新增 `/chatroom/create`
2. 内部映射 `/group/create_group`
3. 同步写 `chatroom_info`

### 7.12 查询聊天室信息

修改点：

1. 新增 `/chatroom/get`
2. 返回聊天室扩展字段
3. 增加直播地址、在线人数、通知策略

### 7.13 更新聊天室信息

修改点：

1. 新增 `/chatroom/update`
2. 同步更新群基本信息与聊天室业务信息

### 7.14 修改聊天室开/关状态

修改点：

1. 新增 `status`
2. 新增 `/chatroom/set_status`
3. 关闭后限制发言与进房

### 7.15 聊天室消息类型

修改点：

1. 新增聊天室消息类型策略
2. 支持管理员配置允许的消息类型

### 7.16 聊天室消息历史

修改点：

1. 新增聊天室历史查询 API
2. 增加 10 天保留策略
3. 增加是否入云历史开关

### 7.17 聊天室角色

修改点：

1. 业务层新增游客/匿名游客
2. 保持底层 owner/admin/normal 不变
3. 前端展示改造成聊天室角色

### 7.18 聊天室黑名单

修改点：

1. 新增聊天室黑名单表
2. 新增聊天室黑名单 API
3. 进入聊天室与发言前做校验

### 7.19 聊天室禁言

修改点：

1. 直接复用群成员禁言能力
2. 对外统一命名为聊天室禁言

### 7.20 聊天室临时禁言

修改点：

1. 直接复用 `mutedSeconds`
2. 前端补剩余时长展示

### 7.21 聊天室全员禁言

修改点：

1. 直接复用群全员禁言
2. 对外统一命名为聊天室全员禁言

### 7.22 踢出聊天室

修改点：

1. 直接复用踢群成员能力
2. 对外统一命名为踢出聊天室

### 7.23 修改自己的聊天室成员信息

修改点：

1. 复用 `set_group_member_info`
2. 对外改名为 `update_chatroom_member_profile`
3. 增加聊天室成员昵称、头像、扩展字段

## 8. 分阶段实施建议

### 第一阶段：命名适配 + 低风险补齐

目标：

1. 不动 OpenIM 内核
2. 完成聊天室命名替换
3. 补齐多媒体消息与位置消息

交付：

1. Electron 文案全部改成聊天室
2. 新增 `/chatroom/*` 业务 API 外壳
3. 补位置消息
4. 补语音/视频/文件/位置消息 UI

### 第二阶段：业务规则补齐

目标：

1. 补聊天室状态
2. 补消息类型策略
3. 补黑名单
4. 补在线人数

### 第三阶段：高级聊天室能力

目标：

1. 游客 / 匿名游客
2. 聊天室生命周期
3. 10 天历史策略
4. 聊天室专属通知体系

## 9. 本方案的决策建议

建议你在和需求清单对照时，优先做三个决策：

1. 是否接受“第一阶段聊天室 = 群组业务化改名”
2. 是否必须支持“游客 / 匿名游客”
3. 是否必须支持“聊天室 10 天历史消息策略”

这三个点会直接决定项目复杂度：

1. 如果接受“群组业务化改名”，第一阶段推进会很快。
2. 如果必须支持游客和匿名游客，就需要新增业务成员体系。
3. 如果必须支持独立历史策略，就要引入聊天室专属消息策略，不再只是简单复用群组。

## 10. 推荐实施顺序

推荐顺序如下：

1. 先做命名改造和对外 API 改造
2. 再做多媒体消息补齐
3. 再做聊天室规则补齐
4. 最后做游客 / 匿名游客 / 历史策略

这样可以保证：

1. 最快形成“看起来已经是聊天室”的可演示版本
2. 最小化对 OpenIM 原生能力的破坏
3. 为后续继续扩展留出空间
