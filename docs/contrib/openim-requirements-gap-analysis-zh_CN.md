# OpenIM 需求清单符合性分析报告

## 1. 分析范围

本报告基于以下三套代码与运行环境进行分析：

- `open-im-server`
- `chat-main`
- `openim-electron-demo`

分析时间：`2026-04-12`

分析目标：

1. 将需求清单逐项映射到当前项目能力。
2. 判断每项需求是“符合 / 部分符合 / 不符合”。
3. 对可验证能力给出本地与互联网环境的测试结果。
4. 对缺失或不完全符合的部分给出功能设计与修改方案。

## 2. 测试环境与测试说明

### 2.1 本地环境

- Chat：`http://127.0.0.1:10008`
- OpenIM API：`http://127.0.0.1:10002`
- MsgGateway：`ws://127.0.0.1:10001`

本地测试账号：

- `demo_user_001`
- `demo_user_002`
- 本地 Chat 新注册账号 1：手机号 `13800153101`，`userID=9886503374`
- 本地 Chat 新注册账号 2：手机号 `13800153102`，`userID=3938505499`

本地测试群：

- `groupID=729776393`

### 2.2 互联网环境

- Chat：`http://59.46.214.114:18080/chat`
- OpenIM API：`http://59.46.214.114:18080/api`
- MsgGateway：`ws://59.46.214.114:18080/msg_gateway`

公网测试账号：

- 公网 Chat 新注册账号 1：手机号 `13800154101`，`userID=4073480511`
- 公网 Chat 新注册账号 2：手机号 `13800154102`，`userID=7563498067`

公网测试群：

- `groupID=2533779616`

### 2.3 重要说明

当前 `open-im-server` 的 HTTP 消息发送接口 `POST /msg/send_msg` 是管理侧接口，只允许管理员 token 调用，不是普通终端用户直接发送消息的公开接口。代码位置：

- `open-im-server/internal/api/msg.go`

普通 Electron 客户端实际发送消息走的是 IM SDK / WebSocket 链路，代码位置：

- `openim-electron-demo/src/pages/chat/queryChat/ChatFooter/useSendMessage.ts`

因此本报告中的“消息接口测试”分为两层：

1. 管理侧 API 是否支持对应消息类型。
2. Electron 终端是否已经提供发送入口和渲染能力。

## 3. 总体结论

### 3.1 当前已经较好支持的能力

- 文本消息
- 图片消息
- 群组创建、查询、更新
- 群组角色设置
- 群组成员禁言、临时禁言、全员禁言
- 群组踢人
- 群成员修改自己的群名片/扩展字段
- 群系统通知、业务通知

### 3.2 当前主要差异

- 当前核心模型是“单聊 + 群组”，不是独立“聊天室”模型。
- Electron 终端当前只明显落地了“文本 + 图片 + RTC 自定义消息”，没有完整落地语音、视频、文件、位置消息的发送与渲染。
- SDK 支持位置消息，但当前 `open-im-server` 的 HTTP `send_msg` 没有把位置消息映射进去。
- “聊天室在线人数、游客/匿名游客、聊天室黑名单、聊天室开关状态、聊天室 10 天历史策略”等能力当前没有独立实现。

## 4. 逐项需求分析

### 4.1 消息能力

| 序号 | 需求项 | 结论 | 当前项目分析 | 测试结果 | 差异与修改方案 |
| --- | --- | --- | --- | --- | --- |
| 1 | 文本消息 | 符合 | Electron 已提供文本输入与发送；SDK 支持 `createTextMessage`；服务端支持文本消息。代码见 `openim-electron-demo/src/pages/chat/queryChat/ChatFooter/index.tsx`、`openim-electron-demo/src/pages/chat/queryChat/ChatFooter/useSendMessage.ts`、`open-im-server/internal/api/msg.go`。 | 本地：`/msg/send_msg` 返回 `errCode=0`，`serverMsgID=b42d70828e7997db2061bac6e2bc51d3`。公网：返回 `errCode=0`，`serverMsgID=8e59947b7a9ea988e7b0c6949533d4f2`。 | 无需结构性改造。建议补自动化接口测试。 |
| 2 | 图片消息 | 符合 | Electron 已提供图片上传入口和图片消息渲染，SDK/服务端链路完整。代码见 `openim-electron-demo/src/pages/chat/queryChat/ChatFooter/SendActionBar/index.tsx`、`openim-electron-demo/src/pages/chat/queryChat/ChatFooter/SendActionBar/useFileMessage.ts`、`openim-electron-demo/src/pages/chat/queryChat/MessageItem/index.tsx`。 | 本地：`errCode=0`，`serverMsgID=139cea0060794eda02ecd64239ebe2ce`。公网：`errCode=0`，`serverMsgID=05e63bc9b467eebffaaf972302a20fd9`。 | 建议补图片尺寸校验、失败重传与缩略图策略。 |
| 3 | 语音消息 | 部分符合 | SDK 和服务端支持语音消息；Electron 当前没有现成发送入口，也没有明确的语音消息渲染组件。SDK 证据见 `openim-electron-demo/node_modules/@openim/wasm-client-sdk/lib/sdk/index.d.ts`，客户端 UI 仅暴露文本/图片见 `openim-electron-demo/src/pages/chat/queryChat/ChatFooter/SendActionBar/index.tsx`。 | 本地：管理 API 发送成功，`serverMsgID=e505153f12864601ebd1c76db8c0e121`。公网：发送成功，`serverMsgID=e608b7a05d29675a37a832415282dc35`。 | 在 Electron 增加录音/上传入口，接入 `createSoundMessageFromFullPath` 或 `createSoundMessageByURL`；新增 `VoiceMessageRender` 组件和播放控件。 |
| 4 | 视频消息 | 部分符合 | SDK 和服务端支持视频消息；Electron 当前未提供视频发送入口，也未渲染视频消息。 | 本地：管理 API 发送成功，`serverMsgID=1f249cc23087e4d9d94f01d0e443b869`。公网：发送成功，`serverMsgID=7a3bbed86896e740301bf1a448190bef`。 | 在 Electron 增加视频文件选择、快照上传与 `VideoMessageRender`；支持点击播放、下载与失败重发。 |
| 5 | 文件消息 | 部分符合 | SDK 和服务端支持文件消息；Electron 当前未提供通用文件发送入口，也未渲染文件卡片。 | 本地：管理 API 发送成功，`serverMsgID=6066f7ebb6731484c307327ee8fcc042`。公网：发送成功，`serverMsgID=c3da4bf99ec8a07d7f3e1d5debcbde02`。 | 在 Electron 增加文件选择入口，接入 `createFileMessageFromFullPath` / `createFileMessageByURL`；新增文件卡片、下载、打开本地文件能力。 |
| 6 | 地理位置消息 | 不符合 | SDK 支持位置消息，但当前服务端 HTTP `send_msg` 未处理 `Location` 类型；Electron 也没有位置发送入口和位置渲染。代码证据：SDK 支持 `createLocationMessage`，但 `open-im-server/internal/api/msg.go` 的 `getSendMsgReq` 没有 `constant.Location` 分支。 | 本地：`contentType=109` 返回 `errCode=1001`。公网：同样返回 `errCode=1001`。 | 先在 `open-im-server/internal/api/msg.go` 增加 `constant.Location -> apistruct.LocationElem` 映射；再在 Electron 增加位置选择器、地图预览和 `LocationMessageRender`。 |
| 7 | 通知消息 | 部分符合 | 当前已支持群系统通知和业务通知。群通知包括建群、进群、踢人、禁言、全员禁言等；业务通知支持管理侧下发。代码见 `openim-electron-demo/src/constants/im.ts`、`openim-electron-demo/src/utils/imCommon.ts`、`open-im-server/internal/api/msg.go`。但“聊天室事件通知”当前没有独立模型。 | 本地：`/msg/send_business_notification` 成功，`serverMsgID=fa189dd4a3637a6d6a1aafe1b0996a89`。公网：成功，`serverMsgID=7b376ffc33bac2c08cce435513f0c231`。 | 若要符合需求，应新增聊天室事件通知类型，例如“聊天室开始/结束/关闭/公告变更”，并在客户端区分“系统通知”“业务通知”“聊天室通知”。 |
| 8 | 提示消息 | 部分符合 | 当前存在撤回、输入中、群通知等轻量提示型消息，但没有单独设计为一套“提示消息产品能力”。Electron 对部分提示/通知已有处理，见 `useGlobalEvents.tsx`、`constants/im.ts`。 | 代码级证据明确，未单独做 HTTP 用例。 | 建议定义统一的 TipMessage 类型和展示规范，区分是否入库、是否推送、是否计未读。 |
| 9 | 自定义消息 | 部分符合 | SDK 和服务端支持自定义消息；Electron 目前主要在 RTC 场景使用，缺少通用“自定义消息发送入口”。代码见 `openim-electron-demo/src/pages/common/RtcCallModal/index.tsx`。 | 本地：管理 API 发送成功，`serverMsgID=99da58f0b7a3d52a9a2c6e6a299dd4c9`。公网：发送成功，`serverMsgID=5d7773678b22fc58bdd30c8ba10f2a10`。 | 若要满足业务自定义扩展，应增加自定义消息注册机制、消息 schema 校验和通用渲染插件机制。 |
| 10 | 系统通知消息 | 部分符合 | 当前已具备内置系统通知消息能力，包括好友、群组、禁言、踢人等；同时具备开发者业务通知下发能力。但没有“聊天室系统通知消息”的独立体系。 | 群通知代码已落地；业务通知本地/公网已实测成功。 | 建议新增系统通知分类表和统一通知中心，支持“平台系统通知 / 群系统通知 / 聊天室系统通知 / 自定义系统通知”。 |

### 4.2 聊天室能力

说明：当前代码库未发现独立 `chatroom` 域模型，当前最接近的能力是“群组”。因此以下条目主要按“群组可替代程度”进行判断。

| 序号 | 需求项 | 结论 | 当前项目分析 | 测试结果 | 差异与修改方案 |
| --- | --- | --- | --- | --- | --- |
| 11 | 新建聊天室 | 部分符合 | 当前可以创建群组，但不是独立聊天室。代码见 `open-im-server/internal/api/router.go` 的 `/group/create_group`，客户端入口见 `openim-electron-demo/src/pages/common/ChooseModal/index.tsx`。 | 本地：创建群 `729776393` 成功。公网：创建群 `2533779616` 成功。 | 低成本方案：继续以群组映射聊天室。标准方案：新增 `chatroom` 模块、数据表和 API，区分群组与聊天室。 |
| 12 | 查询聊天室信息 | 部分符合 | 当前可查询群组信息，能拿到名称、公告、简介、创建者、成员数、扩展字段等；但没有聊天室在线人数、直播地址、是否发送更新通知、通知事件扩展字段。 | 本地：`/group/get_groups_info` 成功返回群信息。公网：同能力已验证。 | 若严格按需求，需要在 `chatroom` 模型中增加 `onlineCount`、`liveURL`、`sendUpdateNotification`、`noticeEventEx` 等字段。 |
| 13 | 更新聊天室信息 | 部分符合 | 当前可更新群名称、公告、简介、头像、扩展字段，代码对应 `/group/set_group_info`。但缺聊天室直播地址、在线人数、更新通知开关等字段。 | 本地：更新群 `729776393` 成功。公网：更新群 `2533779616` 成功。 | 可先扩展群 `ex` 字段承载业务信息；正式方案是在 `chatroom` 表中增加结构化字段并补对应 API。 |
| 14 | 修改聊天室开/关状态 | 不符合 | 当前没有独立的聊天室开/关状态 API。系统有群组状态字段，但对外显式能力是“全员禁言/取消全员禁言”，不是聊天室生命周期开关。 | 未找到独立接口；仅存在 `/group/mute_group` 与 `/group/cancel_mute_group`。 | 新增 `set_chatroom_status(open/close)` 服务端 API，并在状态切换时广播聊天室状态通知。 |
| 15 | 聊天室消息类型 | 部分符合 | 如果把聊天室映射为群组，则文本、图片、自定义、群系统通知已较清晰；服务端还支持语音、视频、文件；但 Electron 未完整支持语音/视频/文件/位置消息，且聊天室模型本身不存在。 | 本地/公网：文本、图片、语音、视频、文件、自定义已通过管理 API 验证；位置消息失败。 | 先补齐 Electron 发送与渲染，再决定是否以群聊模式承载聊天室消息类型，或新增 `chatroom` 会话类型。 |
| 16 | 聊天室消息历史 | 部分符合 | Electron SDK 已支持拉取历史消息，代码见 `openim-electron-demo/src/pages/chat/queryChat/useHistoryMessageList.tsx`；但当前没有“聊天室 10 天历史消息”的专用策略，也没有按消息设置“是否上云历史”的对外能力。 | 代码层证据明确，未做聊天室历史接口实测。 | 若按需求实现，需要：1. 新增聊天室历史 retention 策略；2. 在发送消息接口暴露 `isHistory` / `isPersistent`；3. 对聊天室历史单独查询。 |
| 17 | 聊天室角色 | 不符合 | 当前群角色只有 `Owner/Admin/Normal`，代码见 `openim-electron-demo/node_modules/@openim/wasm-client-sdk/lib/types/enum.d.ts`。需求中的“普通游客/匿名游客/非固定成员”当前不存在。 | 本地/公网：已验证群角色能把成员设为管理员，但没有游客/匿名游客。 | 新增聊天室成员类型：固定成员、游客、匿名游客，并建立权限矩阵。 |
| 18 | 聊天室黑名单 | 不符合 | 当前系统只有用户黑名单，没有聊天室黑名单。代码搜索未发现房间黑名单接口；现有黑名单接口在 `/friend/add_black`、`/friend/remove_black`。 | 无聊天室黑名单测试项。 | 新增 `chatroom_blacklists` 表和 API：拉黑、取消拉黑、进房校验。 |
| 19 | 聊天室禁言 | 部分符合 | 当前群组支持对成员禁言。 | 本地：`/group/mute_group_member` 成功。公网：同能力成功。 | 如果继续用群组映射聊天室，可直接复用。若做独立聊天室模块，可把同一能力下沉到 `chatroom_member`。 |
| 20 | 聊天室临时禁言 | 部分符合 | 当前群禁言接口支持 `mutedSeconds`，本质就是临时禁言。 | 本地：设置 `mutedSeconds=120` 成功，成员 `muteEndTime` 更新。公网：同能力成功。 | 若改造成聊天室，可复用现有禁言时长模型。 |
| 21 | 聊天室全员禁言 | 部分符合 | 当前群组支持全员禁言和取消全员禁言。 | 本地：`/group/mute_group`、`/group/cancel_mute_group` 成功。公网：同能力成功。 | 若需求中的“聊天室关闭”实际只是全员禁言，则该能力可直接复用；若是房间生命周期关闭，则需新增状态机。 |
| 22 | 踢出聊天室 | 部分符合 | 当前群组支持踢成员，权限控制由群主/管理员负责。 | 本地：`/group/kick_group` 成功。公网：同能力成功。 | 如果采用聊天室模型，可直接继承相同权限规则，并增加游客踢出逻辑。 |
| 23 | 修改自己的聊天室成员信息 | 部分符合 | 当前群成员支持修改自己的昵称、头像、扩展字段，接口为 `/group/set_group_member_info`。权限逻辑已在服务端校验。 | 本地：`demo_user_002` 自改群成员信息成功。公网：`7563498067` 自改群成员信息成功。 | 若实现聊天室，应将该能力平移为 `set_chatroom_member_info`，并保留昵称/头像/ex 字段。 |

## 5. 关键代码证据

### 5.1 Electron 已落地的发送与渲染能力

- 文本发送：`openim-electron-demo/src/pages/chat/queryChat/ChatFooter/index.tsx`
- 实际发送走 SDK：`openim-electron-demo/src/pages/chat/queryChat/ChatFooter/useSendMessage.ts`
- 图片发送入口：`openim-electron-demo/src/pages/chat/queryChat/ChatFooter/SendActionBar/index.tsx`
- 图片消息构造：`openim-electron-demo/src/pages/chat/queryChat/ChatFooter/SendActionBar/useFileMessage.ts`
- 当前消息渲染仅明确映射文本、图片：`openim-electron-demo/src/pages/chat/queryChat/MessageItem/index.tsx`
- 历史消息拉取：`openim-electron-demo/src/pages/chat/queryChat/useHistoryMessageList.tsx`

### 5.2 SDK 已具备但 Electron UI 未完整暴露的能力

- 语音消息：`createSoundMessageByURL` / `createSoundMessageByFile`
- 视频消息：`createVideoMessageByURL` / `createVideoMessageByFile`
- 文件消息：`createFileMessageByURL` / `createFileMessageByFile`
- 位置消息：`createLocationMessage`

代码位置：

- `openim-electron-demo/node_modules/@openim/wasm-client-sdk/lib/sdk/index.d.ts`
- `openim-electron-demo/node_modules/@openim/electron-client-sdk/lib/core/modules/message.d.ts`

### 5.3 服务端群组接口

- 建群：`/group/create_group`
- 查询群信息：`/group/get_groups_info`
- 更新群信息：`/group/set_group_info`
- 成员信息更新：`/group/set_group_member_info`
- 成员禁言：`/group/mute_group_member`
- 全员禁言：`/group/mute_group`
- 踢人：`/group/kick_group`

代码位置：

- `open-im-server/internal/api/router.go`
- `open-im-server/internal/api/group.go`

### 5.4 服务端消息类型映射差异

`open-im-server/internal/api/msg.go` 中，`getSendMsgReq` 当前支持：

- 文本
- 图片
- 语音
- 视频
- 文件
- At 文本
- 自定义
- Markdown
- Quote
- OA 通知

但没有把 `Location` 映射进去，因此位置消息目前无法通过 HTTP `send_msg` 发送。

## 6. 设计与修改建议

### 6.1 低成本改造方案：继续以“群组”映射“聊天室”

适用场景：

- 业务可接受“聊天室”本质上是一个大群。
- 不要求游客、匿名游客、在线人数、聊天室黑名单、聊天室开关状态。

建议修改：

1. Electron 补齐语音、视频、文件、位置消息的发送与渲染。
2. 服务端补 `Location` 消息 HTTP 映射。
3. 通过群 `ex` 字段承载直播地址、业务公告扩展字段。
4. 通过群禁言/全员禁言/踢人/角色能力近似满足聊天室管理能力。

优点：

- 改造成本低。
- 复用现有 OpenIM 数据模型和同步机制。

缺点：

- 无法满足游客、匿名用户、聊天室在线人数、聊天室黑名单、聊天室生命周期开关等核心聊天室语义。

### 6.2 标准改造方案：新增独立 ChatRoom 域模型

适用场景：

- 需求清单必须严格实现。
- 后续有直播间、观众、游客、匿名、房间状态控制等演进需求。

建议新增模型：

1. `chatrooms`
   - `chatroomID`
   - `name`
   - `ownerUserID`
   - `announcement`
   - `liveURL`
   - `status`
   - `sendUpdateNotification`
   - `noticeEventEx`
   - `ex`
2. `chatroom_members`
   - `chatroomID`
   - `userID`
   - `memberType`
   - `roleLevel`
   - `nickname`
   - `faceURL`
   - `muteEndTime`
   - `ex`
3. `chatroom_blacklists`
4. `chatroom_online`
   - 在线人数和会话状态缓存

建议新增 API：

1. `POST /chatroom/create`
2. `POST /chatroom/get`
3. `POST /chatroom/update`
4. `POST /chatroom/set_status`
5. `POST /chatroom/get_members`
6. `POST /chatroom/set_member_info`
7. `POST /chatroom/mute_member`
8. `POST /chatroom/cancel_mute_member`
9. `POST /chatroom/mute_all`
10. `POST /chatroom/kick_member`
11. `POST /chatroom/add_blacklist`
12. `POST /chatroom/remove_blacklist`
13. `POST /chatroom/get_history`

Electron 建议新增页面能力：

1. 聊天室创建与信息管理页
2. 聊天室成员与角色管理页
3. 语音/视频/文件/位置消息发送入口
4. 对应消息渲染组件
5. 聊天室系统通知流

## 7. 建议排期顺序

### 第一阶段

- 补齐 Electron 的语音、视频、文件、位置消息发送与渲染
- 修复服务端 `Location` 消息 HTTP 映射
- 保持“群组映射聊天室”的临时方案

### 第二阶段

- 补齐群组映射下的业务字段：直播地址、公告扩展字段、通知事件扩展字段
- 增加业务通知与提示消息规范

### 第三阶段

- 若业务坚持“聊天室”语义，新增独立 `chatroom` 域模型
- 引入游客/匿名游客/在线人数/黑名单/生命周期状态/10 天历史策略

## 8. 最终判断

如果按“即时通讯基础能力”评估，当前项目已经具备较强基础，尤其是文本、图片、群管理、禁言、踢人、系统通知这类能力。

如果按你提供的清单“严格作为聊天室产品能力”评估，当前项目的主要问题不是单点接口缺失，而是：

1. 当前核心模型是群组，不是聊天室。
2. Electron 客户端没有把多媒体消息和位置消息完整产品化。
3. 聊天室特有的游客、匿名、在线人数、黑名单、开关状态、10 天历史策略尚未实现。

因此，当前项目可以判断为：

- “即时通讯基础层”大体可用
- “聊天室产品层”存在明显差异，需要继续设计和改造
