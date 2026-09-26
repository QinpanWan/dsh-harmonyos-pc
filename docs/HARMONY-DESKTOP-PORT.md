# 鸿蒙桌面端适配：Electron 壳 → ArkTS 原生壳

> 上游事实见 [DESKTOP-SHELL-UPSTREAM.md](DESKTOP-SHELL-UPSTREAM.md)，源码快照在 `desktop-upstream/`。
> 结论：**换壳不换核** —— dsh 内核、协议、profile 全部沿用；把 Electron 提供的那层「窗口/菜单/托盘/更新/对话框」用 ArkTS 重写到鸿蒙原生。

## 为什么不能直接把 Electron 壳搬过来

| 硬约束 | 实据 | 结论 |
|---|---|---|
| 官方发布目标只有 mac/win | `apps/desktop/README.zh.md`：「Linux 不是受支持的 Desktop 发布目标」 | Linux 都没有，鸿蒙更没有 |
| Electron 需要 Chromium + 原生 .node 模块 | 本仓库《限制》章节：鸿蒙禁 dlopen 非受信 ELF，无 openharmony-arm64 预编译包 | Electron 本体、`electron-updater`、`koffi`、`node-pty` 全部不可用 |
| 应用内不能拉起独立可执行文件 | 本仓库既有结论（PCL-HM 打包记录）：`childProcessManager` 只能 fork 自身 ArkTS 运行时，不能跑 node | 壳**不能**像上游那样自己 `spawn` dsh Host；dsh 仍在终端/HNP 侧常驻（默认 3080） |
| `desktop` profile 被 Electron 独占 | dsh `lib/bin.js`：`profile "desktop" is managed exclusively by the Electron application` | 鸿蒙壳不复用该 profile；继续用本仓库既有 profile（web/自定义） |

## 能力映射（逐条对照上游）

| 上游（Electron） | 鸿蒙实现 | 落地位置 | 状态 |
|---|---|---|---|
| `new BrowserWindow({1280,820,min 520x600})` | `setWindowLimits(min/max)` + `resize()` + `moveWindowTo()`（**调用时把 vp 换算成 px**，见下节） + 几何记忆并夹回屏内 | `entryability/EntryAbility.ets`、`desktop/WindowGeometry.ets` | ✅ 已实现 |
| 窗口几何持久化（Electron 自管） | `DesktopPrefs` 存 `window_geometry`（**vp，带 `v` 格式版本**），尺寸变化 400 ms 合并落盘 | `entryability/EntryAbility.ets`、`desktop/DesktopPrefs.ets` | ✅ 已实现 |
| 应用菜单（`Menu.setApplicationMenu`） | 自绘菜单栏 + 下拉层，结构与顺序取自契约 JSON | `view/DesktopMenuBar.ets` | ✅ 已实现 |
| 关于面板（`role:'about'` / Windows 自绘） | 自绘「关于」面板：客户端版本、适配基线、上游提交、Host 协议版本、契约来源 | `view/DesktopDialogs.ets` | ✅ 已实现 |
| 关闭进托盘 + 首次确认（`background-notice`） | `windowStage.on('windowStageClose')` 拦截 → 页面确认 → `terminateSelf()`；无托盘则「最小化」 | `entryability/EntryAbility.ets`、`view/DesktopDialogs.ets` | ✅ 已实现 |
| 退出前任务巡检（`quit-inspection.ts`，2000 ms 超时） | 用流式状态判断「有任务在跑」，确认框文案区分「任务中断 / 定时任务不跑」（沿用上游原文） | `pages/Index.ets` | ⚠️ 等价但更粗（无 Host 巡检 RPC） |
| 原生目录对话框（`dialog.showOpenDialog`） | `DocumentViewPicker` + `DocumentSelectMode.FOLDER`，并发请求合并成一次 | `desktop/DesktopDirectoryPicker.ets` | ✅ 已实现 |
| 设备级快捷键偏好（`keybindings.json`，原子写 0600） | `preferences` 存 `shortcuts`（带 revision 的单写者快照） | `desktop/ShortcutRegistry.ets`、`desktop/DesktopPrefs.ets` | ✅ 已实现 |
| 应用级快捷键（`accelerator`） | `keyboardShortcut()`：Ctrl+W 关闭确认、Ctrl+R 重连、F11 全屏 | `pages/Index.ets` | ✅ 已实现（功能键须走 `FunctionKey` 枚举） |
| 编辑菜单注入按键（`sendEditingKey`） | **不做**：鸿蒙文本组件自管编辑历史，壳无法注入按键；菜单保留条目并提示走系统快捷键 | `pages/Index.ets` | ⚠️ 有意降级（已写进限制） |
| 自更新（`electron-updater` + 签名安装器） | 读同一份 feed 判断「上游是否已发布新版本」，安装引导到官网/应用市场 | `service/DesktopUpdateService.ets`、`desktop/UpdateFeed.ets`、`desktop/UpdateSchedule.ets` | ⚠️ 只做「发现」不做「安装」 |
| 更新轮询策略（10 min / 封顶 1 h / ±20% 抖动 / 手动合并） | 逐条照搬，同样 completion-based 调度 | `desktop/UpdateSchedule.ets` | ✅ 已实现 |
| 强制更新策略、飞书策略登录、崩溃报告、安装器 | **不移植**：依赖 Electron/AGC 侧能力，且本机无对应基础设施 | — | ❌ 明确不做 |
| 打包 Web 页面 + HTTP 转发认证（`dsh-app://` + cookie） | 不用 Web 壳：本仓库客户端走原生 RPC（`/api/<method>` + `events.mux`），无需转发层 | `service/DshApiClient.ets` | ✅ 既定路线（更省资源） |
| 托盘（回窗 / 退出） | 无托盘概念 → 最小化 + 关闭确认；通知栏提醒为后续可选项 | `pages/Index.ets` | ⚠️ 降级 |

## 「单一事实来源」的做法

上游把这些常量写死在 TS 里；鸿蒙侧改为一份可被外部校验的契约：

- `client/entry/src/main/resources/rawfile/desktop-shell.json`：上游仓库/提交/版本、窗口几何、更新调度与 feed 布局、菜单树、快捷键表。
- `client/entry/src/main/ets/desktop/DesktopShellContract.ets`：运行时读取该 JSON（读取失败回落内置默认值并记录原因，**不静默降级到 0 值**）。
- `scripts/desktop-shell-check.mjs`：用 Node 把三方对起来 —— ①契约 ②上游源码快照（正则抠常量）③ArkTS 实现（文案表字段、标签解析 case、菜单分发分支、**窗口几何单位：`resize/moveWindowTo` 必须过 `pxFromVp()`、落盘必须带 `v` 版本号、px/vp 换算只许出现在 `WindowGeometry` 内**、字形 `Path` 必须显式 `strokeWidth`、独立模式必须走 `requestInStream`），任何一处漂移即失败。当前 33 项全绿。
- `scripts/direct-mode-check.mjs`：独立模式（内置直连，开箱即用）的静态契约 + 真解析器功能回归 —— 把 `.ets` 里的
  `frameBoundary/frameText/streamText/completionText` 抠出来在 node 里跑（`--experimental-strip-types` 剥类型），
  喂官方 API 抓下来的真实 SSE 固件，按任意字节边界切块。当前 32 项全绿。
- `scripts/session-live-check.mjs`：侧栏实时化（`$events` 事件流 → 就地 upsert/remove/status/activity）与思维链
  （`blocksToReasoning` / reasoning-delta / `assistant/message` 的 reasoning 块 / 摘要取行规则）的静态契约 + 功能回归 ——
  同样抠 `.ets` **真函数**在 node 里跑，喂**真 dsh 服务抓包的固件**。当前 50 项全绿。

```sh
node scripts/desktop-shell-check.mjs
node scripts/direct-mode-check.mjs
node scripts/session-live-check.mjs
```

## UI 复刻：令牌与图标都是「生成物」，不是手写物

界面不许闭门造车，所以视觉真源同样只认上游开源代码，且**不手工誊抄**：

```sh
node scripts/gen-harmony-ui-assets.mjs            # 生成（覆盖写入下面 5 个文件）
node scripts/gen-harmony-ui-assets.mjs --check    # 校验磁盘与生成结果一致（回归/CI）
node scripts/gen-harmony-ui-assets.mjs --upstream ~/dsh-desktop-src/deepseek-harness-master
```

| 上游文件 | 生成物 | 说明 |
| --- | --- | --- |
| `packages/client/ui-theme/src/styles/design-platform.css` | `client/entry/src/main/ets/common/Tokens.ets` | 181 项 `--dsw-*` 令牌，浅色（`body`）与深色（`body[data-ds-dark-theme]`）各一套；生成时递归解析 `var()` 与 `color-mix(in srgb)`，运行时零解析 |
| `packages/client/ui-primitives/src/icons/{index,shared-artwork,PermissionIcon}.tsx` | `client/entry/src/main/ets/common/Icons.ets` | 94 个字形 → `Shape` + `Path.commands`（视口缩放 ⇒ 运行时上色、跟随深浅色），含 `ICON_NAMES`；权限三枚（`PermissionIcon{ReadOnly,WorkspaceWrite,FullAccess}`）从上游 `PermissionIcon.tsx` 的 `*Artwork` 抠出，16×16 视口；不再用只能静态着色的 `Image($r('app.media.*'))`。填色字形**一律带 `strokeWidth(0)`**（关掉 ArkUI 固定加在 `Path` 上的第二遍默认黑描边，见《字形绘制：ArkUI 会给每个 Path 描两遍边》），描边字形带 `strokeWidth($$.strokeWidth ?? 1)` |
| `packages/client/ui-primitives/src/BrandWordmark.tsx` | 同上（`IconBrandWordmark` + `IconBrandFull`） | 生成器 `parseBrandParts()` 一次解析出**两个** @Builder：`IconBrandWordmark` = **只取 `includeMark={false}` 那半张**（viewBox `26 0 156 24`，剥掉带 `dsh-wordmark-whale-clip` 的鲸鱼组，只留「DeepSeek HARNESS」+ HARNESS 反色徽章，`alt` 取 `--dsw-alias-label-primary-inverted`）；`IconBrandFull` = 整幅（viewBox `0 0 182 24`，鲸鱼 + 字标一体，上游预平移好的坐标直接可用）。**品牌排必须用单幅 `IconBrandFull`** —— 早先「取 182 宽字标 + 另画 `FishMark`」会把同一头鲸鱼画两遍（2026-09-26 主人报的「logo 重影」）；折叠轨道只画鲸鱼，用 `FishMark` 是对的（`Brand.ets` 里 `FishMark` 仍保留） |
| `apps/desktop/resources/icon-windows.svg` | `entry/.../media/{icon,startIcon}.svg` + `AppScope/.../media/app_icon.svg` | 应用/入口/启动图统一为官方图标；生成时①剥 `filter` ②`linearGradient` 折成取各 stop 中值的实色 ③`transform` 烘焙进坐标（ArkUI 的 SVG 解析对这三样都不保证） |

尺寸与节奏常量（不属于生成物，但同样逐条有出处）集中在 `client/entry/src/main/ets/common/Theme.ets`：
`ui-theme/src/styles/base.css` 的圆角/动效/字体栈、`apps/desktop/src/windows-layout.ts` 的标题栏 40、
`ui-layout/src/client/columns.ts` 的侧栏 280/56 与正文列宽，以及各组件的 `*.module.css`（会话头 76、输入卡圆角 28、
气泡 20、会话行 32、设置面板 800×800…）。注释里写明了每一组的出处，改动前先回去看上游。

**深浅色/字号的生效链路**（ArkUI 的坑）：`Theme.palette()` 直接读 `AppStorage` **不会**建立渲染依赖，
所以每个组件都声明 `@StorageProp('dshDarkTheme') dark` 并调用 `Theme.palette(this.dark)`（构造参数即订阅），
页面另用 `@State dark`；写侧只有 `Index.applyAppearance()`（`AppStorage.setOrCreate`），
系统深浅色变化由 `EntryAbility.onConfigurationUpdate` → eventHub 触发重算。

## 首页会话入口：工作区 / 工作区权限 / 对话模式（2026-09-26，同日第二轮改为输入行并排）

上游把这三个选择器都挂在 **hero（空会话）相位**，且**共用同一张输入卡**（`ConversationContent.tsx`：
`composerStack` = HeroShell + `heroWorkspaceRow` + 输入卡，输入卡由 `conversation.composer.bar` 槽位**常驻**渲染一次）。
鸿蒙端的等价物逐条对齐如下（真源：`ui-conversation/src/client/skeleton/{ConversationContent,InputBar,EmptyHero}.tsx`、
`ui-conversation/src/client/skeleton/ConversationRoot.module.css` 的 `.composerHero`/`.heroWorkspaceRow`）。
**注意**：第二轮主人要求「工作区选择与对话模式选择放在工作区权限旁边」，所以现在三枚胶囊**并排在输入卡工具排里**，
hero 相位的 `heroWorkspaceRow` 已删除（详见下面《输入行四枚胶囊》一节）：

| 上游座位 | 鸿蒙实现 | 落地位置 |
| --- | --- | --- |
| `heroWorkspaceRow` 的 `WorkspaceChip`（文件夹字形 + 目录名 + chevron，未选时闭文件夹 + 「选择工作区」） | 工作区胶囊：`bindMenu` 列出会话 `cwd`（✓ 标当前）+「选择文件夹…」→ `DocumentViewPicker`；标签 = 手选目录优先，否则当前会话 `cwd` 的末段 | `view/InputBar.ets` 的 `workspaceChip()` / `workspaceMenu()` / `basenameOf()`、`pages/Index.ets` 的 `pickWorkspace()` / `pickWorkspaceDirectory()` |
| `conversation.input.permission`（`ui-permission-presets` 的 `PermissionSelect`） | 输入卡工具排的权限胶囊：权限字形 + 显示名（+ `auto` 档的 `EXP` 上标）+ chevron；菜单取自 `permissionPresets/catalog`，写入走 `commands/execute` 的 `/permission <preset>`；`danger-full-access` / `auto` 先过风险确认（上游 `RiskConfirmation`） | `view/InputBar.ets` 的 `permissionChip()` / `permissionMenu()`、`view/DesktopDialogs.ets` 的 `DesktopPermissionRiskPanel`、`pages/Index.ets` 的 `pickPermission()` / `commitPermission()` |
| `conversation.hero.agentPreset`（`ui-agent-preset` 的 `AgentPresetSeat`，首个回合后锁定） | 对话模式胶囊：dsh 服务模式下列 `agentPresets/list`（剔除 `broken`），选中即暂存给下一个新建会话（`session/create` 的 `agentPreset` 入参）；**独立模式下列内置 `rawfile/presets.json` 的 8 套模式**（选中即成为请求的 system 提示）；会话已有消息时菜单只显示「对话已开始，模式不可更改」 | `view/InputBar.ets` 的 `presetChip()` / `presetMenu()` / `presetText()`、`pages/Index.ets` 的 `pickPreset()` / `loadPresets()` / `applyBundledPresets()` |

本轮修掉的三个问题（对应主人反馈「首页有两个对话输入口 / 没有工作区选择按钮 / 没有工作区权限与对话模式选择」）：

1. **两个输入卡**：原实现 hero 相位渲染了一张 `InputBar`，列尾又常驻一张 → 空会话时同屏两张。按上游语义改为**全列唯一实例**：hero 相位 = hero chrome + 卡（工作区/对话模式两枚已在第二轮搬进卡内工具排），有消息 = 正文 + 同一张卡。全客户端只剩一处 `TextArea`（`view/InputBar.ets`）。
2. **工作区按钮**：原来只有一枚调 `pickWorkspaceDirectory()` 的死按钮；现在是胶囊 + 菜单（会话 `cwd` 候选 + 手选目录），标签与上游 `workspaceLabel` 同规则（目录末段）。
3. **工作区权限 / 对话模式**：原来只是一段被动文本；现在都是真选择器。权限显示名走 `Constants.permissionLabel()`（上游 `displayPermissionPreset`）：`read-only`→仅可查看、`workspace-write`→工作区内修改、`danger-full-access`→完全权限、`auto`→`Auto review`+`EXP`；其余部署名按上游 `displayPresetName` 转 Title Case。**机器值仍用于菜单比对与写入**（显示名绝不回写协议）。

协议侧（0.1.6 typert gateway，本机实测）：

- 单次 RPC：`POST /api/<ns>/<method>`，body `{type:'client-request',rpcId,method,payload:{args:{…}}}`；参数名由描述符决定（`session/list` 要 `_request:{}`，`session/create|prompt|…` 要 `request:{…}`，`agentPresets/list`、`permissionPresets/catalog` 无参）。
- 认证：`GET /`（回环）→ 303 + `set-cookie: dsh-auth-*`（30 天），之后 RPC 与 WebSocket 握手都带 cookie，否则 401（客户端落盘这枚 cookie 并自动重登一次）。
  **坑（2026-09-26 修的就是它）**：`@ohos.net.http` 默认跟随重定向，跟随后那次响应里**没有** `set-cookie`，
  于是 cookie 永远拿不到、所有 RPC 401 —— 用户视角就是「连不上服务」。`DshApiClient.login()` 必须传 `maxRedirects: 0`
  （API 23+；本 SDK **没有** `followRedirects`，写了直接编译报错），并用大小写不敏感的 `headerValue()` 取
  `set-cookie`、`resp.cookies` 兜底。curl 复核：303+cookie → 带 cookie `POST /api/session/list` 200 → `ws://…/api/remote.mux` 握手 101。
- 模型目录 / 选择：`session/modelCatalog`（`{default,routableProviders,groups}`）给候选；`session/selectModel`
  （`{request:{sessionId,provider,model,reasoningEffort}}`）切模型；效果从 `session/list` 的 `modelSelection` 投影读回。
- 会话流：`ws://host/api/remote.mux`，发 `{type:'open',streamId,endpoint:'session/follow',payload:{args:{request:{address:{kind:'session',sessionId},maxMessages:200,assistantStream:true}}}}`；下行 `item` 帧分 `snapshot`（records + 投影 `title`/`permissions`）、`event`（durable，事件名与旧 SSE 一致）、`assistant-stream`（`frame.chunk.type` = `text-delta` / `reasoning-delta`）。旧版 `/api/events.mux`（SSE）与 `agentPreset.list`/`host.describe` 已下线，旧调用全部换掉。
- 权限写入：`commands/execute` 的 `{agentId: sessionId, line:'/permission <preset>', submittedAttachments:[]}`；随后 `session/list` 的 `projections.values.permissions.currentValue` 变为新值（`permissionPresets/catalog` 实测三档：read-only / workspace-write / danger-full-access）。
- 独立模式（客户端内置 DeepSeek API）没有工作区/权限概念：权限胶囊**置灰并给出原因**（不隐藏入口），工作区/对话模式菜单顶部加一行禁用说明，三个菜单里都放一条可点的「切换到 dsh 服务模式…」（= 设置里的连接模式切换，切完自动重连），别让主人停在死路上。

### 独立模式：开箱即用（内置对话模式 + 系统提示）

主人原话是「这个桌面端还是要连本地服务但是连不上，你要么就直接做一套把全部环境融合进去开箱即用的」。
本轮把「必须连本地服务」这条硬依赖砍掉：

- **对话模式随包分发**：`scripts/gen-client-presets.mjs`（零依赖，支持 `--check`）把仓库
  `presets/*/{preset.yml,agent.cordis.yml}` 生成成 `client/entry/src/main/resources/rawfile/presets.json`
  （id / 中文产品名 / 说明 / persona 系统提示，8 套）；`common/PresetCatalog.ets` 读取
  （`getRawFileContentSync` + `util.TextDecoder`），**读不到就回落 `Constants.BUILTIN_PRESETS` 的 id 列表** ——
  列表仍可切换，只是没有中文名与提示，绝不阻塞启动。
- **模式即系统提示**：独立模式下每次请求把所选模式的 persona 作为 `messages[0]`（`role:'system'`）发出
  （`DeepSeekClient.chat()` 末位 `systemPrompt` 参数），`{{model}}`/`{{cwd}}` 占位替换成当前模型与工作目录
  （`PresetCatalog.systemPrompt()`）。这就是「对话模式」在没有服务端 agent 时的真实语义。
- **端点可配**：`Constants.KEY_DIRECT_BASE_URL` / `DIRECT_BASE_URL='https://api.deepseek.com/v1'` 只是默认值；
  设置面板里能改（OpenAI 兼容端点，`DeepSeekClient.setEndpoint()`：空串 → 官方、只给主机名 → 自动补 `/v1`、给了路径 → 补 `/chat/completions`）。
  API Key / 模型 / 接口地址三者只存本机 preferences，不经服务端。
- **不调服务端的部分**：独立模式下 `agentPresets/list` 不调用；`loadPresets()` 变成「**先内置、后服务**」——
  内置永远可用，连上服务端后用 `agentPresets/list` 覆盖，并用服务端 name 补上中文名缺失的那些。
- 文案统一为「独立模式（内置，开箱即用）」/「dsh 服务模式」（设置面板的 Select 与说明行）。

### 独立模式必须用 `requestInStream`（别用 `request`，否则「200 但零回调」）

主人报「开箱即用的模式发消息不回复，配好密钥也这样」——不是密钥/模型/网络问题，是 `@ohos.net.http` 的**派发条件**：

- **只有流式请求才有流式事件**：`communication_netstack` 里 `HttpExec::OnWritingMemoryBody`（`http_exec.cpp`）
  与 `ProcessResponseBodyAndEmitEvents` 都以 `context->IsRequestInStream()` 为前提才 `SetTempData` + 投递
  `OnDataReceive`；`ON_DATA_END` 只在 `AsyncWorkRequestInStreamCallback` 里发出；`EnableRequestInStream()`
  只被 `http_module.cpp` 的 `requestInStream` 调用。⇒ 用 `request()` 发 SSE 会拿到 **HTTP 200 和完整
  `resp.result`，但 `on('dataReceive')` / `on('dataEnd')` 一次都不响**；旧代码只在非 200 时报错，于是
  既不显示内容也不报错，看起来就是「发出去没反应」。
- **现在的形状**（`service/DshApiClient.ets` → `DeepSeekClient.chat()`）：`requestInStream` 的 promise 只用来拿
  **响应码**，正文只走 `dataReceive`；收尾是唯一的 `settle(err, flush)`（`finished` 闸门保证只生效一次）；
  用户点「停止」/ 开新回合走 `cancelHook` 按**正常结束**收尾；非 2xx 用自己攒的 `raw` 报错（流式模式没有
  `resp.result`）；**HTTP 200 但零数据块 → 明确报「服务端没有返回任何内容」**；非 SSE 端点（忽略 `stream:true`）
  走 `completionText` 兜底；`readTimeout` 600s（netstack 映射成 curl `CURLOPT_TIMEOUT_MS` = 整条响应总时限）。
- **解析器是静态可测的**：`frameBoundary()`（最后一整帧的结束位置，注意 `lastIndexOf` 返回 -1 时 `-1+2=1` 这种坑）、
  `frameText()`（一帧里的 `delta.content`，`data:` 带不带空格都认，多行 `data:` 按 SSE 规范拼接，注释帧与 `[DONE]` 跳过）、
  `streamText()`（整段原文 → 增量文本，收尾残帧用）、`completionText()`（非 SSE 整段 JSON 兜底）。
- **回归检查**：`node scripts/direct-mode-check.mjs`（32 项：静态契约 + 把上面这些**真函数**抠出来在 node 里跑
  **官方 API 抓下来的真流固件**，按 1–999 字节任意切块、keep-alive、`[DONE]`、残帧、非 SSE 兜底）。
  它当场抓到过一个「`-1+2=1` 把首字符当帧切掉」的边界错。`desktop-shell-check.mjs` 里也有 1 项守门（33/33）。
- **真机排查**：日志标签 `DshDirect`（首块到达 / 完成字数与耗时 / 失败原因），`hdc shell hilog -T DshDirect`。

### 输入行四枚胶囊（工作区 / 工作区权限 / 对话模式并排）

上游把「工作区」「对话模式」放在 hero 相位输入卡**上方**的 `heroWorkspaceRow`，与卡内的「工作区权限」分处两行；
主人要求三枚并排，于是 `view/InputBar.ets` 的工具排改成 **Flex 换行**，一行四枚：

```
+ 圆 → 工作区权限 → 工作区 → 对话模式                  模型胶囊（右侧，真 bindMenu）
```

- 上游座位不变（`conversation.input.{permission,model}` 仍是工具排左右两端），只是把 `heroWorkspaceRow` 的两枚
  **搬进**工具排 —— 这是与上游的**有意差异**，改代码前先读 `view/InputBar.ets` 顶部注释（那里写了原因与来源）。
- **模型胶囊是真菜单**（`conversation.input.model` 座位，语义照上游 `ui-model-selection/src/client/ModelSelect.tsx`）：
  候选打 ✓ 标当前，选中即切；最后一行才是设置入口（独立模式「模型与 API Key…」/ dsh 服务模式「模型与连接设置…」）。
  之前它被误接到 `onOpenModelSettings` 上，**点一下直接开设置**（主人报的 bug），已修。
- 模型候选与切换：独立模式 = 内置模型 id；dsh 服务模式 = `session/modelCatalog` 的 `groups[].models[]` 拼 `provider/model`。
  切换走 `session/selectModel`（`{request:{sessionId,provider,model,reasoningEffort}}`），之后 `session/list` 的
  `projections.values.modelSelection.{lastUsed,next}` 回填当前模型 —— `modelLabel()` 不再拿预设名冒充模型。
- 胶囊不可用时（独立模式 / 未连接 / 还没有会话）统一「**置灰 + 菜单首行写原因 + 末行留切换入口**」，不隐藏、不留死路。

### 侧栏实时化（`$events` 事件流）与思维链 / 跟随滚动

主人报「没有实时显示和滚动思维链，左侧没实时刷新出最新会话」。侧栏和思维链各是一个真 bug。

**侧栏＝宿主 `$events` 逻辑流**（会话列表的真源，别再轮询 `session/list`）：

- 宿主 `dsh-api-session-controller/lib/index.js` 把 `ctx.on('session/created'|'session/disposed'|'agent/status'|'session/event')`
  映成 `ctx.emit('api-session/added', summary)` / `('api-session/removed', sessionId)` / `('api-session/status', agentId, running)` /
  `('api-session/activity', sessionId, event.time)`；`dsh-api-remotes/lib/index.js` 的 `API_REMOTE_FORWARDED_EVENTS`
  白名单把它们交给网关的内建逻辑流转发到客户端 —— 官方 web 端 `dsh-client-ui-session` 的 `apply()` 用的
  `ctx.remote.$on(...)` 就是这条路。
- 端点常量 `REMOTE_EVENT_STREAM_ENDPOINT = '$events'`，**payload 必须是空 `args: {}`**（网关侧校验）。
  下行帧两种：`{"type":"item","streamId":…,"value":{"type":"ready","clientId":…,"host":{"home":…}}}`（事件源就绪）与
  `{"type":"item","streamId":…,"value":{"type":"emit","event":"api-session/added","args":[summary]}}`（业务）。
- 客户端：`DshApiClient.openHostEvents(sink)`（`streamId = 'events-N'`）→ `Index.openHostEvents()` 在 `connect()` 的
  `openMux` 成功回调与 `.then()` 里都补开一次（重连后由 `reopenStreams()` 原样重开）→ `Index.onHostEvent()`
  分派 `upsertSession()` / `removeSession()` / `markSessionRunning()` / `touchSession()`。
- **事件载荷与 `session/list` 的行同源**，所以 `parseSessionSummary()` 两边共用，行内字段够用 —— 事件到达时就地改列表，
  不重拉全表（`session/list` 实测 286 行 / ~188KB / ~1s）。只有本地查不到那一行时才 `scheduleSessionRefresh(200|800)`
  去抖兜底一次全量，外面套 `sessionRefreshInFlight` 并发闸门（飞行中来的挂起，落地后 200ms 补一次）。
- 列表排序统一走 `sortSessions()`（`updatedAt` 降序，与 `session/list` 的返回顺序一致）：新会话、别处发的消息都自然置顶。

**思维链（CoT）两个来源都要认**：

- 实时：`assistant-stream` 帧 `start` → `chunk{block-start|reasoning-delta|text-delta|block-end|usage|finish}` → `end`（`outcome.kind:'committed'`，实测一次回答约 200 帧）。
- 快照：落库的 `assistant/message` → `data.message.content[]` 里的 `{"type":"reasoning","text":…}`（切会话/重连只有这一份）。
- 旧缺陷：`blocksToText()` 只认 `text` 块（切会话即丢思维链）、`MessageItem` 只在「有 reasoning 且无 text」时印一行「思考中」（从不渲染内容）。
  现在 `blocksToReasoning()` 负责收集，`assistant/message` 分支回填 `msg.reasoning`，`applyAssistantFrame` 支持多段
  `block-start`（第 2 段起 `\n\n` 接上；单条 `block-start` 不造空气泡）。

**披露行与滚动**：

- `view/MessageItem.ets` 的 `reasoningRow()` 对齐上游 `packages/client/ui-chat/src/client/chat/ReasoningRow`：
  图标 + 标题（生成中「思考中」/ 结束「思考」）+ 一行摘要 + 展开/收起 chevron；摘要生成中取**最后一行**（实时尾巴）、
  结束取**首行**，去 `**` 并限长 160。上游的折叠与悬浮钉住**有意未做**。
- `scrollToBottom(force)` 的跟随闸门 `followBottom`：读者上翻后不再抢滚动，发消息/切会话 `force=true` 重新跟随。
  `ChatView.onDidScroll` → `syncAtEnd()` 用 `Scroller.isAtEnd()` 回报（索引法会被流式正文高度增长误判），
  非底部时显示 34 圆「回到底部」浮标（上游 `.toBottom`，`accessibilityText('回到底部')` = 上游 `aria-label`）。
- **回归检查**：`node scripts/session-live-check.mjs`（50 项）= 静态契约 + 抠出 `.ets` 真函数在 node 里跑真服务抓包固件。

### 侧栏实时化的真机分水岭：`$events` 握手的 `supportOriginPort` 与「行键不重绘」

上面的 `$events` 逻辑流在**真机上一次都没生效**。本机就是那台鸿蒙 PC（`hdc list targets` = `127.0.0.1:32905`），
在设备上对着本机 dsh（`127.0.0.1:3080`）排查，两个真因：

**① 握手 `Origin` 少端口 → Host/Origin 栅栏 403**。ArkTS `@ohos.web.webSocket` 建连默认
`Origin = address`（只有 host）；dsh 网关要求 Origin 的 authority 与 Host **含端口**一致，
`Origin: http://127.0.0.1` vs `Host: 127.0.0.1:3080` 判不等 ⇒ 403，事件流根本没建立。
修法（`service/DshApiClient.ets` `openHostEvents()`）：

```ts
// API 26 起：打开后 Origin 才带 host:port，否则被 dsh 的 Host/Origin 栅栏 403
const options: webSocket.WebSocketRequestOptions = { header: header, supportOriginPort: true };
```

定位手法值得复用：先起一个**本地假网关**回显握手头（`ws-probe-server.mjs`），直接看出 `Origin` 里没有端口；
再用 `mux-origin-probe.mjs` 对真 dsh 复现 403；最后 `mux-events-probe.mjs` 验证修好后能收到 `ready` + `emit` 帧。

**② 侧栏行键不重绘（`ForEach` 只按 key 判等的第二个病例）**。`view/Sidebar.ets` 的行键原先只有 `sessionId`：
新会话插得进来，但「标题/时间/运行位/选中态」这四种**原地变化**不改键 ⇒ ArkUI 复用旧行，列表看起来「有条目但不更新」。
修法：`rowKey(item, currentSessionId)` 把 `sessionId | title | updatedAt | running | 是否选中` 全编进键
（一次事件只重建一行）。**规律**：凡是「同一行内容会原地变」的 `ForEach`，键必须包含会变的那部分 ——
正文气泡看文本长度（第五轮）、侧栏行看标题/时间/运行位（本轮）。

**真机验收（dsh 服务模式）**：命令行 `session/create` → 约 2 秒内侧栏顶部自动出现该行；`session/prompt` 跑起来后
标题/时间行内实时刷新、页签名同步、思考行跟着流式增长、正文自动跟随；`uitest uiInput fling` 上翻后右下出现 34 圆
「回到底部」浮标（px `[2451,1575][2516,1640]`），点它回到底部。装机走
`~/bin/hm-sign-install.sh`（xiaobai 调试证书本地签名）+ `hdc install -r` + `aa start -b com.dsh.harmonyos.client -a EntryAbility`。

### 真机首测抓到的两个 bug：`ForEach` 键 与 独立模式 `reasoning_content`

2026-09-26 第五轮把改动**装到设备上跑**（本机即那台鸿蒙 PC：`hdc list targets` = `127.0.0.1:32905`），当场上轮「逻辑上没问题」的两处就露了馅：

**① 流式正文一个增量都不重绘 —— `ForEach` 只按 key 判等**

```ts
// 坏（旧）：键里没有内容 → 键不变 → ArkUI 认为还是同一个 item，不重绘
}, (block: TextBlock, index: number) => this.message.id + '-' + index.toString())

// 好（新，view/MessageItem.ets 的 blockKey）：把 isCode 与文本长度编进键，每个增量换一次键
private blockKey(block: TextBlock, index: number): string {
  return this.message.id + '-' + index.toString()
    + (block.isCode ? '-c-' : '-t-') + block.text.length.toString();
}
```

助手气泡的生命周期是「先 push 一条空消息 → 增量往 `text` 里追加」，所以键不变 = 气泡永远空着（`reasoning` 非空时上面那行字还在，看起来像「卡住」而不是「没反应」）。
**规律**：ArkUI 的 `ForEach`（以及 `LazyForEach`）**不比较 item 内容**，只比 key；凡是「内容原地增长」的列表，key 必须包含会变的那部分（长度/序号/版本号）。

**② 独立模式（直连 `api.deepseek.com`）整条思维链丢掉 —— 字段名不同**

推理模型把思维链放在 `choices[0].delta.reasoning_content`（不是 `content`）。旧解析器只认 `delta.content`，
于是整个思考阶段界面只有一行「思考中」、一个字都不涨 = 主人说的「思维链滚动不出来」。
新增（`service/DshApiClient.ets`，纯静态函数、可直接喂固件）：

| 函数 | 取什么 | 用途 |
| --- | --- | --- |
| `frameField(frame, field)` | 一帧 SSE 的 `choices[0].delta.<field>` | 唯一的 JSON 解析点 |
| `frameText` / `frameReasoning` | `content` / `reasoning_content` | `dataReceive` 里逐帧取增量 |
| `streamText` / `streamReasoning` | 整段原文（含残帧） | `dataEnd`/`settle` 收尾兜底 |
| `completionText` / `completionReasoning` | `choices[0].{message,delta}.<field>` | 端点忽略 `stream:true` 时的整段 JSON 兜底 |

`Index.ets` 直连回合把 reasoning 增量写进助手消息的 `reasoning` → 披露行（`reasoningRow()`）在独立模式下也有实时的 CoT 可显示。

**③ 附带：应用日志改公共域**。`EntryAbility.ets` 的 `DOMAIN` 由 `0x0000` 改成 `0xD0042`——
`0x00000–0x0FFFF` 是系统私有域，普通 `hdc shell hilog` 读不到（本轮前半段抓了 12743 行日志，零条应用日志）。
改到公共域后，真机排障 `hdc shell hilog -T DshDirect` 就能看到直连模式的首块/完成字数/失败原因。

**真机实测结论**（02:43 截图）：探针包自动发一条，界面同时出现用户气泡 + 思维链行（实时摘要）+ 助手回答；
随后去探针重打干净包、`hap-sign-tool` 签名并 `hdc install`，应用正常启动。

### 独立模式「发消息不在左侧生成会话」：切模式带过来的悬挂会话 id（2026-09-26 第七轮）

主人报「发送消息之后不生成新会话在左侧 —— 这个问题是独立模式下的」。真机复现（本机即那台鸿蒙 PC）：
**先在 dsh 服务模式里点过「新会话」或选过一条空会话，再切回独立模式发消息** —— 正文 / 思维链 / 回答都正常流式出来，
只有左侧栏一直挂着「还没有会话」。

**根因（`Index.ets` 的 `sendDirect()`）**：判断「要不要就地建一条本机会话」用的是 `currentSessionId.length === 0`。
从 dsh 服务模式切回来时 `currentSessionId` 还停在服务端的会话 id 上（**非空**，但 `directConversations` 里根本没有这一行），
于是 `beginDirectConversation()` 被跳过，侧栏那份投影（`publishDirectSessions()`）自然一条行都没有。
判据要问「这条 id 在不在本机会话清单里」：

```ts
// 好（新）：与 dsh 模式的 hero 直接开聊同语义，且不会漏建
if (this.findDirectConversation(this.currentSessionId) === null) {
  this.beginDirectConversation(text);
}
```

**同一族的第二处**：`adoptDirectConversation()`（进独立模式时把当前正文收进本机会话清单）原先在
`this.messages.length === 0` 时直接 `return`，把那枚悬挂的 dsh id 原样留在原地 —— 一样会漏建。现在先清掉不属于本机会话的
id（正文也是空的时候连标题一起复位成「新会话」，标题栏与侧栏的口径才一致）。

**第三处：切模式时的双向污染**。切走的瞬间，上一模式的服务端流还开着、回来照样往状态里写：
`session/list` 的全量回包会把侧栏从「本机会话投影」换成服务端那几百条会话；当前会话的 `follow` 快照会把独立模式的正文整段
覆盖；宿主 `$events` 的 `api-session/added` 会往侧栏插服务端行。三处各加一句模式守卫（dsh 模式行为不变）：

| 位置 | 守卫 |
| --- | --- |
| `refreshSessions()` 的 then 回包 | `if (this.mode !== 'dsh') { this.releaseSessionRefresh(); return; }` |
| `onFollowValue()`（当前会话 follow 流） | `if (this.mode !== 'dsh') return;` |
| `onHostEvent()`（宿主 `$events`） | `if (this.mode !== 'dsh') return;` |

**真机验收（18:12–18:18，以 `uitest dumpLayout` 为准）**：

- **复现（修复前）**：dsh 服务模式点一条空会话（`currentSessionId` 非空、正文空）→ 切回独立模式 → 发「测试乙」→ 回答正常、侧栏仍「还没有会话」。
- **修复后同一路径**：切回独立模式时标题栏即刻复位为「新会话」；发「回归乙」→ 侧栏顶部当场出现「回归乙 18:16」，下面留着上一轮「回归甲 18:15」。
- **回归**：冷启动独立模式发「回归甲」→ 侧栏照常出行（旧行为没被破坏）。
- **模式隔离**：独立模式下用命令行 `POST /api/session/create` 造活动（另一路 `$events` 探针同期收到 `api-session/added`）→ 应用侧栏纹丝不动；
  切到 dsh 服务模式后再造一次 → 两行「新会话 18:17」照旧实时冒出来（实时链路没被守卫打断）。
- **回归检查**：`scripts/direct-mode-check.mjs` **41 → 47 项**（新增上面六条接线契约）；`direct-mode-check` 的静态契约从此覆盖
  「独立模式出行」这条路径，别再退回按 `length === 0` 判。

## 构建与验证

```sh
# 用本机 API 26 混合工具链编译（见 ~/bin/deveco-api26.sh 说明）
sh ~/bin/deveco-api26.sh ~/dsh-harmonyos-pc/client assembleHap
# 产物：client/entry/build/default/outputs/default/entry-default-unsigned.hap

# 出「未签名 release HAP」（可直接分发的那个）
cd ~/dsh-harmonyos-pc/client && rm -rf .hvigor entry/build
sh ~/bin/deveco-api26.sh . assembleHap --mode module \
  -p module=entry@default -p requiredDeviceType=2in1 -p product=default -p buildMode=release
# 产物：entry/build/default/outputs/default/entry-default-unsigned.hap
#       769,014 B / ets/modules.abc 713,988 B（第七轮：独立模式侧栏出行 + 模式隔离守卫）
#       （HAP 是 zip，包内文件带 mtime ⇒ 同一份源码两次构建 sha256 不同；体积与 `ets/modules.abc` 字节数才是可比对量）
# 副本：client/dist/dsh-harmonyos-client-1.0.0-release-unsigned.hap（与 ~/Download/ 各一份）
```

- 现状：**编译通过**，产出未签名 HAP（本机无签名配置 → 不能直接 `hdc install`，会报 `error: no signature file`）。真机安装＝用调试证书（profile 的 UDID 白名单要含本机）`hap-sign-tool sign-app` 签一次再 `hdc install`；本轮已按这条路装到本机鸿蒙 PC 上实测。
- 为什么天然未签名：`client/build-profile.json5` 的 `signingConfigs` 是空数组，hvigor 到 `SignHap` 阶段只打印 `WARN: No signingConfig found for product default` 就跳过 —— 包内没有 `META-INF/`、没有证书与 profile。要签名只需往 `signingConfigs` 填 DevEco 生成的证书 + profile。
- 体积：release **769,014 B**（`ets/modules.abc` **713,988 B** + 三份 4,047 B 的官方图标 + 契约 + 内置对话模式表 `rawfile/presets.json` + `pack.info`）。比 UI 复刻前的 284,192 B 大，全部来自新增的令牌表、94 个字形、官方 1024 图标的矢量数据与内置预设提示（release 仍开 `obfuscation`，包内无 sourcemap）。sha256 `af4a1f45b6c8f4bd35e39fbc9dad59bcfabb2d4fc511ca46c9610caef8fba3bd`（`client/dist/` 与 `~/Download/` 一致；HAP 是 zip 且包内文件带 mtime，同一份源码两次构建 sha 会不同，**体积与 `ets/modules.abc` 字节数才是可比对量**）。
- 包内容（release，11 项）：`module.json`、`resources.index`、`resources/base/media/{app_icon,icon,startIcon}.svg`、`resources/base/profile/main_pages.json`、`resources/rawfile/desktop-shell.json`、**`resources/rawfile/presets.json`**、`ets/modules.abc`、`pack.info`、`pkgSdkInfo.json`。
- 已验证：ArkTS 编译零错误（仅剩 1 条无害 WARN：`startMoving` 起于 API 14，已用 `deviceInfo.sdkApiVersion` 门控）；`direct-mode-check.mjs` **41/41**（含 6 条思维链用例：逐帧 CoT / CoT 不污染正文 / 整条流含残帧 / 非推理模型为空 / keep-alive / 非 SSE 整段 JSON 的 CoT）；`desktop-shell-check.mjs` **33/33**（含单位防回归：把 `resize()` 的实参改回裸 vp 值后脚本 exit 1 并能逐条指认，改回即恢复全绿；另含 3 项「每个 Path 必须显式 strokeWidth」的消重影防回归）；`session-live-check.mjs` **50/50**（`$events` 事件流 / 侧栏就地更新 / 思维链两个来源，喂真服务抓包固件）；`gen-harmony-ui-assets.mjs --check` 五份生成物与磁盘一致（令牌 181 · 字形 94）；`gen-client-presets.mjs --check` 通过（`rawfile/presets.json` 与 `presets/` 一致，8 套模式）；契约负向测试（改坏 `defaultWidth` → 脚本 exit 1 且精确指认）；应用图标用自写的 `scripts/svg-preview.py`（纯标准库光栅化，`python3 scripts/svg-preview.py <in.svg> <out.png> [尺寸] [--bg #RRGGBB] [--scale S] [--pen W]`）渲染核对过几何——鲸鱼路径 `x 150.138..910.32 / y 260.291..819.325` 与上游 bbox 经同一线性映射后的结果逐位相同；`IconBrandWordmark` 的字标墨迹实测 `x 26.96..181.35 / y 4.63..21.64`（= 上游 `includeMark=false` 的 `26 0 156 24` 视口）；包内 `ets/modules.abc` 抽查含 `IconBrandFull` 的鲸鱼路径（`M23.0584 4.95203`，1 次）、`PresetCatalog`、`session/selectModel`、`maxRedirects`，并用 `ark_disasm` 反汇编确认 `strokeWidth(0)` 调用点 **87 处**（85 个填充字形 + `FishMark` + 发送箭头）——ABC 里是 `ldobjbyname "strokeWidth"` + `ldai 0x0` + `callthis1`，不是字符串，别再用 `grep strokeWidth(0)` 查包。
- 链路实测（curl，本机）：`GET /` → 303 + `set-cookie: dsh-auth-*`；带该 cookie `POST /api/session/list` → 200；`ws://127.0.0.1:3080/api/remote.mux` 握手 → **101**。
- 已验证（2026-09-26 第五轮）：真机（本机鸿蒙 PC）装机 + 独立模式端到端对话 + 截图（思维链行与回答同时出现）。未验证：`dsh` 服务模式下的侧栏「别处新建会话秒出现」对照。所有窗口/选择器/更新调用都写了 try-catch 与失败提示，不会把异常抛到 UI 线程。

## 字形绘制：ArkUI 会给**每个** `Path` 描两遍边（左上角 logo「重影」的真因）

主人 2026-09-26 报的「左上角 deepseekharness logo 还是重影不清晰」，真因不在品牌几何（几何逐字节来自上游
`BrandWordmark.tsx`），而在 ArkUI 的绘制语义：

```cpp
// frameworks/core/components_ng/pattern/shape/drawing_painter.cpp
void DrawingPainter::DrawPath(RSCanvas& canvas, const std::string& commands, const ShapePaintProperty& p) {
    // do brush first then do pen
    SetBrush(brush, p); canvas.AttachBrush(brush); canvas.DrawPath(path); canvas.DetachBrush();
    if (SetPen(pen, p)) { canvas.AttachPen(pen); canvas.DrawPath(path); canvas.DetachPen(); }   // ← 第二遍
}
bool DrawingPainter::SetPen(RSPen& pen, const ShapePaintProperty& p) {
    if (p.HasStrokeWidth()) { if (NearZero(p.GetStrokeWidth()->Value())) return false; ... }
    else { pen.SetWidth(p.STROKE_WIDTH_DEFAULT.ConvertToPx()); }        // = 1.0_vp
    ...
    Color strokeColor = p.GetStrokeValue(Color::BLACK);                 // 缺省 = 不透明黑
    ...
    return true;
}
```

**结论**：只要一个 `Path` 没写 `strokeWidth`，ArkUI 就**先用 brush 填色、再用默认黑 pen 描一遍边** —— 同一个字形
被画两次、外面再套一圈 1vp 黑描边。字号越小越致命（品牌字标只有 30vp 高、"deepseek" 笔画约 2 个 viewBox 单位宽，
1vp 黑描边就吃掉近一半笔宽），观感就是**重影 + 发虚**。描边字形（上游 outline 图标）本来就显式 `strokeWidth`，
所以受损的只有填充字形：品牌字标（最显眼）、HARNESS 反色徽章里的字、发送箭头、少数实心图标。

**修法**（不是「把描边调细」，是**关掉第二遍绘制**）：

| 位置 | 改法 |
| --- | --- |
| `scripts/gen-harmony-ui-assets.mjs` | `emitIcons` 的填充分支 + `emitBrand`/`emitBrandFull` 的每个 `Path` 一律补 `.strokeWidth(0)`（`NearZero` ⇒ `SetPen()` 返回 false ⇒ 只画填色那一遍） |
| `common/Brand.ets`（手写） | `FishMark` 的 `Path` 补 `.strokeWidth(0)` |
| `view/InputBar.ets`（手写） | 发送箭头的 `Path` 补 `.strokeWidth(0)` |
| `scripts/desktop-shell-check.mjs` | 新增 3 项防回归：`Icons.ets` 里 `.commands(` 数必须等于 `.strokeWidth(` 数；`Brand.ets`/`InputBar.ets` 每个 `.fill(` 的表达式链里必须有 `.strokeWidth` |

**自查手段**：`scripts/svg-preview.py` 新增 `--scale S`（放大看细节）与 `--pen W --pen-color`（`W` 以 viewBox 单位计，
模拟 ArkUI 的默认黑 pen 第二遍绘制）。同一份官方几何，两种渲染：

![strokeWidth(0)：一遍填色](assets/brand-strokeWidth0.png)
![缺省 strokeWidth：填色 + 默认黑 pen 描边 = 重影](assets/brand-arkui-default-pen.png)

左（现在）：单遍填色，笔画干净；右（修前）：每个笔画被黑 pen 再描一圈，细看就是「重影」。
包内核对：把 `ets/modules.abc` 解出来 `ark_disasm` 成 `.pa` 后，`strokeWidth` 的调用点里**传 0 的有 87 处**
（85 个填充字形 + `FishMark` + 发送箭头），与源码一一对应。

## 窗口几何：px 还是 vp（踩过的坑，别再来一次）

官方把两套单位放在同一个命名空间里，写错**照样能编译、照样有返回值**，只是结果全错：

| 官方 API / 类型 | 单位 | 出处 |
| --- | --- | --- |
| `resize(width, height)` / `resizeAsync()` | **px** | `arkts-apis-window-Window.md#resize9`：`New width of the window, in px` |
| `moveWindowTo(x, y)` / `moveWindowToAsync()` | **px** | 同文件 `#movewindowto9` |
| `getWindowProperties().windowRect` / `getLastWindowRect()` / `Rect` | **px** | `arkts-apis-window-i.md#rect7` |
| `on('windowSizeChange')` 回调的 `Size` | **px** | `arkts-apis-window-i.md#size7` |
| `WindowLimits` 的 min/maxWidth/maxHeight | **px** | `arkts-apis-window-i.md#windowlimits11`；《应用适配自由窗口》亦写「默认单位为 px」 |
| `RectInVP` / `SizeInVP` / `getWindowLimitsVP()` / `PixelUnit.VP` | vp | **API 22/23 才新增**，本工程不用（走 px 那套） |
| `Display.densityPixels` | px/vp 系数 | 唯一的换算依据（`px = vp * density`） |

工程约定（与 `client/entry/src/main/ets/desktop/WindowGeometry.ets` 顶部注释保持一致，改代码前先读那一段）：

- 内部（内存字段、落盘、夹取、与显示器可视区比较）**一律 vp**，与上游 Electron 的 CSS px 等价；
- 每次 `mainWindow.resize()/moveWindowTo()` 都必须经 `WindowGeometry.pxFromVp(vp, density)`；
- 每次读 `windowRect` 落盘都必须经 `vpFromPx()`（`fromPixelRect()` 一次转四个字段）；
- 落盘 JSON 带 `"v":2`：单位混用期写下的脏数据（px 值当 vp 存）**整条丢弃**回默认几何，不靠夹取兜底。

**症状对照**（2026-09-26 修的就是这条）：值按 vp 存、又按 vp 传给 px API ⇒ 每次重启窗口都被 `density` 折半，
再被 `setWindowLimits()` 的最小尺寸夹住，两三次启动后**永久停在 520x600**；从用户视角看只是「窗口拖不小」，
位置还会一轮一轮往左上角漂（`moveWindowTo()` 同样被砍半）。

## 权限变更（必须知道）

`module.json5` 新增 `definePermissions` 声明 `ohos.permission.USE_AI`（`system_grant` / `system_basic`）。
原因：HarmonyOS 26(API 26) SDK 的预定义权限表里没有 `USE_AI`，构建器 `PreBuild` 直接报
`00303221 Configuration Error`；显式声明后构建通过，语义与官方定义一致。
**注意**：该权限仍需 `system_basic` APL 的签名模板才会真正授予（见 [LOCAL-AI-USE_AI.md](LOCAL-AI-USE_AI.md)），
未签名/普通 APL 构建下声明存在但不会生效。

## 已知限制（与上游行为不同之处，均为有意选择）

1. **应用内更新安装**：鸿蒙端不做。dsh 桌面更新包是 Electron 制品，装不上；本壳只提示「上游有新版本」。
2. **编辑菜单**：撤销/重做/剪切/复制/粘贴/全选由系统文本组件处理，壳的菜单项只保留入口与提示。
3. **托盘**：鸿蒙无托盘，'隐藏应用' 类动作落到「最小化窗口」。
4. **`restartAppHost`（重启应用与 Host）**：dsh 不在应用进程内，壳无权重启，改为提示到终端重启。
5. **强制更新/策略登录/崩溃报告**：不移植（依赖 Electron 与 AGC 侧设施）。
6. **UI 只看得到代码，没看到真机**：`hdc list targets` 为空、SDK 里只有 Windows 版 Previewer，所以这一轮 UI 复刻是「按上游 CSS/TSX 的数值逐条对齐 + 编译通过」，没有截图比对。视觉上仍可能有偏差的地方集中在 ArkUI 与浏览器语义不同的部分：`filter` 投影（已剥离）、SVG 渐变（已折实色）、`border: 0.5px` 发丝线、`backgroundBlurStyle` 毛玻璃、`Shape.viewPort` 缩放的描边粗细。真机在手时优先核这几处。
7. **上游部分视觉能力没有等价物**：Electron 的窗口 vibrancy（macOS 半透明侧栏）、原生 caption 菜单（我们用自绘三键）、`-webkit-app-region: drag`（我们用 `startMoving()`，起于 API 14，低版本回退系统标题栏）。另外折叠轨道里上游的「会话列表 / 搜索」面板本端尚未接入，轨道只保留「展开侧栏」与「设置」两个真实入口，不做点了没反应的假按钮。
8. **自绘标题栏必须连系统三键一起隐藏**：`setWindowDecorVisible(false)` 只藏标题栏本体，系统三键（右上角最大化/最小化/关闭）仍在，且**压在自绘标题栏上层** —— 点过去命中的是系统按钮。所以 `EntryAbility.applyDesktopWindow()` 里必须同时调 `setWindowTitleButtonVisible(false, false, false)`，三键由 `view/DesktopMenuBar.ets` 自绘（几何与 hover 色照上游 Windows 标题栏）；`setWindowDecorHeight(40)` 只是让系统知道标题栏高度（与自绘栏对齐，合法区间 [37,112] vp）。
