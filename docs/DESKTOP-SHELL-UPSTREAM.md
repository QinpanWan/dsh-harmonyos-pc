# 上游 dsh 桌面端（Electron 壳）架构剖析

> 对象：`desktop-upstream/apps/desktop` + `apps/desktop-host`
> 版本：`@deepseek-ai/dsh-desktop@0.1.7-rc.2`，commit `477b4f42`
> 目的：为鸿蒙端移植提供「逐项可核对」的能力清单。本文只描述上游事实，映射结论见 [HARMONY-DESKTOP-PORT.md](HARMONY-DESKTOP-PORT.md)。

## 一句话定位

桌面端 = **一层薄壳**：Electron 负责「窗口 / 菜单 / 托盘 / 原生对话框 / 自更新 / 打包与签名」，
页面与业务全部来自官方 Web 客户端 —— 壳只是把它**装进原生窗口并替它开门**（认证、转发、注入）。
`apps/desktop/README.zh.md` 原文：「桌面应用是完整 dsh Web 应用外的一层 Electron 壳」。

## 1. 进程模型

| 角色 | 进程 | 关键点 |
|---|---|---|
| 壳（主进程） | Electron main `src/main.ts` | 单实例锁、窗口、菜单、托盘、原生对话框、自更新、崩溃上报 |
| 页面（渲染进程） | Electron renderer | `sandbox: true` + `contextIsolation: true` + `nodeIntegration: false`，只通过 `preload-*.ts` 暴露的白名单 API 触达原生 |
| dsh Host | Electron **Node 模式**子进程 | `ELECTRON_RUN_AS_NODE=1`（`node-environment.ts`）跑共享 profile runner；`host-process.ts` 管生命周期 |
| 内置浏览器/产品页 | `WebContentsView`（`platform-view.ts`） | 独立 session 分区、cookie 合并、客户端元数据头 |
| 更新覆盖层 / 欢迎页 / 崩溃恢复 | 独立小窗口（`update-overlay.ts`、`welcome-window.ts`、`mandatory-update-window.ts`） | 与主窗口同壳不同文档 |

启动链：壳 `spawn` Host → Host 回 `{type:'ready', url, injections}` → 壳 `fetch` 该 URL 完成认证
（要求 `303` + `set-cookie`，见 `web-document.ts: authenticateWebHost`）→ 壳把 cookie 装进转发的每个请求。

## 2. 资源与归属

| 项 | 值 | 出处 |
|---|---|---|
| 协议 scheme | `dsh-app://app/` | `ipc.ts: SCHEME` |
| 默认端口 | **19387**（Web 端是 3080，互不影响） | `README.zh.md` |
| profile 独占 | `$DSH_HOME/profiles/desktop` + 其锁 `.../desktop/lock` | `paths.ts` |
| Host 生命周期协议版本 | `4` | `host-protocol.ts` |
| 安装体积归属 | `app.asar/dsh` 带完整生产依赖树；profile 只装外部插件 | `README.zh.md` 安装归属 |
| CLI 互斥 | CLI 拒绝 boot/dump/plugin `desktop` profile（`profile "desktop" is managed exclusively by the Electron application`） | 本仓库 MEMORY 记录 + dsh `lib/bin.js` |

## 3. 窗口与外观

- 主窗口 `1280x820`，最小 `520x600`（`main.ts: createWindow`）。
- Windows：自绘标题栏（`titleBarStyle: 'hidden'` + `titleBarOverlay`，标题栏高度常量 `WINDOWS_TITLEBAR_HEIGHT = 40`，`windows-layout.ts`），
  渲染进程通过 `dsh-desktop:windows-appearance` 回传实测配色，壳改 `setTitleBarOverlay`。
- macOS：`hiddenInset` + 红绿灯内嵌 + `vibrancy: 'sidebar'`；最小化/隐藏时把 vibrancy 置空并铺不透明底色，
  恢复时切回（规避 electron#25368 的材质回挂延迟）。
- 关闭 ＝ **进托盘**（Windows）：首次关闭弹一次确认（`background-notice.ts`，标记文件 `background-close-confirmed`），
  之后静默隐藏；托盘（`tray.ts`）点击回窗、右键菜单「打开 / 退出」。
- 全屏状态与外观（语言/配色）都会推给页面：`windowFullscreen`、`windows-appearance`、`locale-bootstrap` / `locale-changed`。

## 4. 菜单体系

- 应用菜单（`main.ts: refreshApplicationMenu`）：
  - 顶层：macOS 用应用名，其它平台用「应用 / 编辑」。
  - 应用子菜单：**关于 DeepSeek Harness** → **检查更新…** → （开发态：刷新页面 / 重启应用与 Host）→ 隐藏系（macOS）→ 退出/退出应用。
  - macOS 额外补 `fileMenu`（含「关闭页面或窗口」）、`editMenu`、`windowMenu`；Windows 只补 `editMenu`。
- 关于面板：macOS 走原生 `role: 'about'`；Windows 自绘暗色对话框（期望值见 `tests/expected/about-panel.json`）。
- 右键菜单：可编辑区给 撤销/重做/剪切/复制/粘贴/全选，只读选区给 复制，且**显式清空 accelerator** 以免暴露 Electron 默认快捷键标签。
- Windows 另有一条 `dsh-desktop:windows-menu` IPC：页面请求在指定坐标弹「应用菜单 / 编辑菜单」，
  编辑项不是原生 undo 栈，而是 `sendEditingKey()` 把 `Ctrl+Z` 等**当作按键注入编辑器**（编辑器自管历史）。

## 5. 本地化

`locale.ts` 一份 `en` / `zh` 文案表（341 行），覆盖菜单、关于、退出确认、托盘、欢迎页登录（含飞书/登出）、
自更新全状态文案（检查/下载/校验/安装/失败分类/技术详情）、强制更新、崩溃与恢复。
语言来源：`resolveDesktopStartupLocale()` 读系统 + 偏好，`localeChanged` 推给页面 —— **菜单文案跟随壳语言，页面文案跟随 Web 语言**。

## 6. 输入与快捷键

- 设备级偏好 `keybindings.json` 存 Electron `userData`，**原子写 + `0600`（目录 0700）**（`keybindings.ts`）。
- 真实配置读写与「绑定 → 展示」由 `@deepseek-ai/dsh-client-shortcuts/protocol` 的 `ShortcutPersistence` 统一（单写者事务）。
- `keyboard.ts` 负责：物理按键分发（录制态）、原生菜单快捷键与页面快捷键互不打架、
  内置浏览器 guest 的按键租约（lease）拦截。
- IPC 面（`ipc.ts: DESKTOP_IPC`，25 条）：`shortcuts-input`、`shortcuts-close-window`、`shortcuts-get/edit/changed/recording`、
  `boot`、`enter-workspace`、`onboarding-active`、`onboarding-api-key`、`boot-failed`、`browser-acquire/release/open-requested`、
  `directory-pick`、`locale-bootstrap/changed`、`updates-status/open/presentation`、`native-theme-set`、`window-fullscreen`、
  `windows-appearance`、`windows-menu`。
- 安全约束：`assertDesktopSender(event, ['app'])` —— 只有 `dsh-app://app` 主页面的主 frame 能调这些 IPC。

## 7. 原生目录选择

`directory-picker.ts`：`dialog.showOpenDialog(window, { properties: ['openDirectory', 'createDirectory'] })`，
同一窗口的并发请求**去重**（`WeakMap` 复用同一个 Promise），并先 `restore/show/focus` 目标窗口；
非主 frame 的调用直接拒绝。

## 8. 自更新

- 引擎：`electron-updater`，通道是 **nightly**（无 `latest.yml`），
  feed 形如 `https://download.deepseek.com/dsh-desk/feeds/<target>/nightly.yml`，产物 `dsh-desk/bin/<target>/deepseek-harness-<ver>-<target>.{exe|zip}`。
- 状态机（`ipc.ts: DesktopUpdateState`）：`idle → checking → available → downloading → verifying → installing → ready | error`，
  带 `percent`、`failedOperation`（check/download/install）、`preparationFailure`（stop-failed / tasks-changed / tasks-unavailable）。
- 调度（`update-schedule.ts`）：默认 **10 分钟**轮询、失败指数退避封顶 **1 小时**、**±20% 抖动**，
  可用 `DSH_DESKTOP_UPDATE_CHECK_INTERVAL_MS` / `..._MAX_BACKOFF_MS` / `..._JITTER` 覆盖（带范围校验）；
  手动检查立即执行并与自动检查**合并同一次飞行请求**。
- 安装前必须「安全停任务」：`apps/desktop-host/src/update-tasks.ts` 停任务、`quit-inspection.ts` 巡检
  （`activeTasks` / `scheduledTasks`，壳侧 2000 ms 超时视为「有任务」）。
- 强制更新策略：`mandatory-update-policy.ts` + `mandatory-update-window.ts` + `policy-login-loading.html`
  （测试环境需先飞书登录才查询策略），可含「前往官网下载 / 复制下载链接」兜底。
- 更新日记与恢复：`update-journal.ts`（崩溃后断点判断）、`fatal-recovery.ts`（「禁用第三方插件、备份 profile patch 并重启」一键恢复）。

## 9. 崩溃与失败面（对移植的启示）

| 场景 | 上游表现 |
|---|---|
| 端口/Host 被占 | `startup-error.ts`：「有其他正在运行的 DSH（如其他 dsh web、桌面端）…请退出其他正在运行的 DSH 后重启」 |
| 启动即崩 / 意外退出 | `fatal-recovery.ts`：只读诊断摘要 + 诊断报告落地 + 一键恢复（禁插件/备份 patch/重启） |
| 渲染进程异常 | `crash-report.ts`：保留控制台尾部输出，写报告，裁剪超长内容 |
| 退出确认 | `quit-confirmation.ts`：区分「正在运行的任务会中断」与「定时任务不会运行」，两者都给精确文案 |

## 10. 可移植性总览（结论先行）

| 上游能力 | 依赖 Electron | 鸿蒙可移植性 |
|---|---|---|
| 窗口/尺寸/标题栏/全屏 | `BrowserWindow` | ✅ ArkUI `window` API 等价 |
| 应用菜单 + 快捷键 | `Menu` / `accelerator` | ⚠️ 无系统级应用菜单 → 自绘菜单栏 + ArkUI 快捷键 |
| 托盘（回窗 + 退出） | `Tray` | ⚠️ 无托盘 → 后台任务/通知/桌面图标右键 |
| 原生目录对话框 | `dialog.showOpenDialog` | ✅ `@ohos.file.picker` 文件夹选择 |
| 关于面板 | `role: 'about'` / 自绘 | ✅ 自绘（上游 Windows 路径可直接照搬） |
| 自更新 | `electron-updater` + 安装器 | ❌ 不可移植 → 应用市场更新 + feed 版本提示（见映射文档） |
| 设备级快捷键偏好文件 | `userData/keybindings.json` | ✅ `preferences` 等价（键位语义照搬） |
| dsh Host 子进程 | Electron Node 模式 | ⚠️ 鸿蒙用 HNP node 起同一 profile runner（本仓库既有方案） |
| 打包 Web 页面 + HTTP 转发认证 | `protocol.handle` + `net` | ⚠️ 改用 ArkUI `Web` 组件或原生 RPC 客户端（本仓库选原生 RPC） |
