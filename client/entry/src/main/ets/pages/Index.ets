/**
 * Index：主页面（桌面三栏式布局的编排中心）。
 *
 * 职责：
 * - 加载/保存服务器地址（@ohos.data.preferences）
 * - 建立 dsh 连接（cookie 登录 + `/api/remote.mux` WebSocket 事件流）
 * - 会话列表、历史加载、消息发送/停止、实时事件折叠（foldEvent）
 *
 * 参照华为开发者文档《声明式UI语法》：
 * @Entry 页面入口、@Component 自定义组件、@State 组件内状态、
 * $$ 双向绑定（bindSheet）、@Builder 复用 UI 片段。
 */
import { Constants, PermissionRisk } from '../common/Constants';
import { PresetCatalog, PresetInfo } from '../common/PresetCatalog';
import { Appearance, KEY_CONTENT_FONT_SIZE, KEY_DARK_THEME, Theme } from '../common/Theme';
import { DshApiClient, DeepSeekClient } from '../service/DshApiClient';
import { ChatMessage, DirectConversation, DshSession } from '../model/Types';
import { Sidebar } from '../view/Sidebar';
import { ChatView } from '../view/ChatView';
import { SettingsPanel } from '../view/SettingsPanel';
import { DesktopMenuBar, DesktopMenuDropdown, DESKTOP_MENUBAR_HEIGHT } from '../view/DesktopMenuBar';
import {
  DesktopAboutPanel, DesktopPermissionRiskPanel, DesktopQuitConfirmPanel, DesktopUpdatePanel,
} from '../view/DesktopDialogs';
import { DesktopShellContract, MenuSpec } from '../desktop/DesktopShellContract';
import { DESKTOP_ZH, DesktopCopy, DesktopMessages } from '../desktop/DesktopCopy';
import { DesktopPrefs, DesktopPrefKeys } from '../desktop/DesktopPrefs';
import { DesktopUpdatePhase, DesktopUpdateService } from '../service/DesktopUpdateService';
import { DesktopDirectoryPicker } from '../desktop/DesktopDirectoryPicker';
import {
  DESKTOP_CHROME_CHANGED, DESKTOP_CONFIG_CHANGED, DESKTOP_PAGE_READY, DESKTOP_QUIT_DECISION,
  DESKTOP_QUIT_REQUEST,
} from '../entryability/EntryAbility';
import { preferences } from '@kit.ArkData';
import { BusinessError, deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Entry
@Component
struct Index {
  @State serverUrl: string = Constants.DEFAULT_SERVER;
  @State connected: boolean = false;
  @State connecting: boolean = false;
  @State sessions: DshSession[] = [];
  @State currentSessionId: string = '';
  @State currentTitle: string = '';
  @State messages: ChatMessage[] = [];
  @State streaming: boolean = false;
  @State showSettings: boolean = false;
  @State statusText: string = '未连接';
  /** 部署可用的对话模式预设 id 与产品名（平行数组，来源见 loadPresets） */
  @State presetIds: string[] = [];
  @State presetNames: string[] = [];
  @State currentPreset: string = '';
  /** 随 HAP 分发内置的对话模式目录（rawfile/presets.json）：显示名 + 独立模式的系统提示 */
  @State presets: PresetInfo[] = [];
  /** 首页「工作区」选择器候选（会话 cwd 去重 + 手选目录；上游工作区菜单的鸿蒙等价物） */
  @State workspaceOptions: string[] = [];
  /** 首页「工作区权限」选择器：目录 + 当前会话的值（上游 conversation.input.permission 座位） */
  @State permissionOptions: string[] = [];
  @State currentPermission: string = '';
  /** 权限风险确认弹层（上游 RiskConfirmation：完全权限 / Auto review 两档） */
  @State permissionRiskVisible: boolean = false;
  @State permissionRiskAck: boolean = false;
  @State permissionRiskValue: string = '';
  @State permissionRiskTitle: string = '';
  @State permissionRiskBody: string = '';
  @State permissionRiskConfirm: string = '';
  /** 当前会话绑定的对话模式（首个回合后锁定，与上游「hero 上的 preset 座位」同语义） */
  @State sessionPreset: string = '';
  /** 连接模式：'direct' 内置直连（打开即用）/ 'dsh' dsh 服务 */
  @State mode: string = 'direct';
  @State directApiKey: string = '';
  @State directModel: string = 'deepseek-v4-flash';
  @State directModels: string[] = Constants.DIRECT_MODELS;
  /** 独立模式接口地址（默认官方 DeepSeek，可换任意 OpenAI 兼容端点） */
  @State directBaseUrl: string = Constants.DIRECT_BASE_URL;
  /** 模型胶囊：候选键（独立=模型 id / dsh=provider/model）与当前键 */
  @State modelKeys: string[] = Constants.DIRECT_MODELS;
  @State currentModelKey: string = 'deepseek-v4-flash';
  /** dsh 服务端模型目录的默认项（`session/modelCatalog`.default） */
  @State catalogDefaultModel: string = '';
  /** 系统标题栏是否仍然可见（隐藏失败时页面不再自绘品牌标，避免同一枚 logo 出现两次） */
  @State systemDecorVisible: boolean = false;
  private client: DshApiClient | null = null;
  private deepseek: DeepSeekClient = new DeepSeekClient();
  /**
   * 独立模式的本机会话清单（左侧栏那几行）。dsh 服务模式用服务端 `session/list`，
   * 独立模式没有服务端，就用这一份：发第一条消息时按需建会话（与 dsh 模式 hero 发消息同语义），
   * 「新会话」把当前这轮收进清单再开一轮新的。
   */
  private directConversations: DirectConversation[] = [];
  /** 当前会话的事件流（切换会话/断开时取消订阅） */
  private followStreamId: string = '';
  /** 宿主全局事件流（`$events`）：侧栏会话列表的实时来源（api-session/added|removed|status|activity） */
  private hostEventsStreamId: string = '';
  /** 会话列表全量刷新的去抖计时器（-1 = 空闲） */
  private sessionRefreshTimer: number = -1;
  /** 全量刷新是否在飞（避免并发堆叠） */
  private sessionRefreshInFlight: boolean = false;
  /** 去抖期间又来了新事件：本轮结束后补一次全量 */
  private sessionRefreshPending: boolean = false;
  /**
   * 正文是否「跟随到底部」。由 ChatView 的 onDidScroll 回报（读者往上翻就不再抢滚动），
   * 发出消息 / 切换会话时重置为 true —— 上游 web 端同一套 atBottom 语义。
   */
  private followBottom: boolean = true;
  /** 登录会话 cookie（`dsh-auth-*`，本机回环签发，落盘复用） */
  private authCookie: string = '';
  private scroller: Scroller = new Scroller();
  // —— 桌面壳层（菜单栏 / 关于 / 退出确认 / 更新检查 / 目录选择）——
  @State shell: DesktopShellContract = new DesktopShellContract();
  @State desktopCopy: DesktopMessages = DESKTOP_ZH;
  @State openMenuId: string = '';
  @State aboutVisible: boolean = false;
  @State quitVisible: boolean = false;
  @State updateVisible: boolean = false;
  @State updatePhase: string = DesktopUpdatePhase.IDLE;
  @State updateTitle: string = '';
  @State updateMessage: string = '';
  @State updateDetail: string = '';
  @State showUpdateTechnical: boolean = false;
  @State appVersion: string = '';
  /** 窗口是否处于最大化/全屏（标题栏「最大化/还原」键据此换字形，也决定点击语义）。 */
  @State windowMaximized: boolean = false;
  @State workspaceDirectory: string = '';
  /** 窗口宽度（用于上游 SIDEBAR_AUTO_COLLAPSE=1024 的自动收起判定） */
  @State windowWidth: number = 1280;
  /** 侧栏折叠手动覆盖：-1 自动 / 0 展开 / 1 收起 */
  @State sidebarOverride: number = -1;
  /** 外观偏好（system / light / dark，上游 ui-theme 的 ui-theme 设置命名空间） */
  @State appearance: string = Appearance.SYSTEM;
  /** 当前生效的深浅色（applyAppearance 写入并同步 AppStorage，供 build 建立依赖） */
  @State dark: boolean = true;
  /** 会话正文档位（12–17，默认 14） */
  @State contentFontSize: number = 14;
  /** 会话主列实际宽度（用于 --dsh-chat-content-width 求解） */
  @State columnWidth: number = 1200;
  private prefs: DesktopPrefs | null = null;
  private updates: DesktopUpdateService | null = null;
  /** 菜单标题的窗口坐标（用于下拉层定位，键 = 菜单 id） */
  private menuAnchors: Map<string, number> = new Map();
  private menuAnchorX: number = 8;

  aboutToAppear(): void {
    // 内置对话模式目录（rawfile/presets.json）：独立模式的「环境」就在这里，
    // 不依赖 dsh 服务在线；读不到时 PresetCatalog 会回落到裸 id 列表。
    this.presets = PresetCatalog.load(this.getUIContext().getHostContext());
    this.loadSettings();
    this.setupDesktopShell();
  }

  aboutToDisappear(): void {
    if (this.client !== null) {
      this.client.closeMux();
    }
    this.syncDirectCurrent();
    this.deepseek.stop();
    const service: DesktopUpdateService | null = this.updates;
    if (service !== null) {
      service.dispose();
    }
  }

  // —— 设置持久化 ——

  private loadSettings(): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) {
      this.connect();
      return;
    }
    try {
      const store = preferences.getPreferencesSync(host, { name: Constants.SETTINGS_STORE });
      const saved: string = store.getSync(Constants.KEY_SERVER_URL, Constants.DEFAULT_SERVER) as string;
      this.serverUrl = saved;
      const preset: string = store.getSync(Constants.KEY_AGENT_PRESET, '') as string;
      this.currentPreset = preset;
      const mode: string = store.getSync(Constants.KEY_MODE, 'direct') as string;
      this.mode = mode;
      const dk: string = store.getSync(Constants.KEY_DIRECT_API_KEY, '') as string;
      this.directApiKey = dk;
      const dm: string = store.getSync(Constants.KEY_DIRECT_MODEL, 'deepseek-v4-flash') as string;
      this.directModel = dm;
      const base: string = store.getSync(Constants.KEY_DIRECT_BASE_URL, Constants.DIRECT_BASE_URL) as string;
      this.directBaseUrl = base.length > 0 ? base : Constants.DIRECT_BASE_URL;
      const ap: string = store.getSync(Constants.KEY_APPEARANCE, Appearance.SYSTEM) as string;
      this.appearance = ap;
      const fs: number = store.getSync(Constants.KEY_CONTENT_FONT_SIZE, 14) as number;
      this.contentFontSize = fs;
      const cookie: string = store.getSync(Constants.KEY_AUTH_COOKIE, '') as string;
      this.authCookie = cookie;
    } catch (e) {
      this.serverUrl = Constants.DEFAULT_SERVER;
    }
    this.deepseek.setEndpoint(this.directBaseUrl);
    this.syncDirectModelKeys();
    this.applyAppearance();
    this.applyMode();
  }

  /** 独立模式的模型胶囊：候选 = 内置模型表，当前 = 选中的那一个。 */
  private syncDirectModelKeys(): void {
    this.modelKeys = this.directModels.slice();
    this.currentModelKey = this.directModel;
  }

  /** 按模式初始化：direct=内置直连（打开即用）；dsh=连接服务 */
  private applyMode(): void {
    if (this.mode === 'dsh') {
      // 侧栏此时由服务端 `session/list` 接管：先清空本机会话那几行，连接成功后 refreshSessions 填回来
      this.sessions = [];
      this.currentSessionId = '';
      this.connect();
    } else {
      this.deepseek.stop();
      this.connected = true;
      this.statusText = '独立模式（内置，打开即用）';
      this.connecting = false;
      this.syncDirectModelKeys();
      // 切回独立模式时把当前正文收进本机会话清单（否则这段内容在侧栏里没有对应行）
      this.adoptDirectConversation();
      this.publishDirectSessions();
      this.syncWorkspaceOptions(this.sessions);
    }
    // 预设列表始终可用：服务端拉不到（未连接）时用内置六套
    this.loadPresets();
  }

  // —— 独立模式的本机会话（左侧栏那几行） ——

  /** 侧栏渲染的是 `sessions`：独立模式下它就是本机会话清单的投影。 */
  private publishDirectSessions(): void {
    if (this.mode !== 'direct') {
      return;
    }
    const rows: DshSession[] = [];
    for (let i = 0; i < this.directConversations.length; i++) {
      const conv: DirectConversation = this.directConversations[i];
      const row: DshSession = new DshSession(conv.sessionId);
      row.title = conv.title;
      row.updatedAt = conv.updatedAt;
      row.cwd = conv.cwd;
      rows.push(row);
    }
    this.sessions = this.sortSessions(rows);
  }

  private findDirectConversation(sessionId: string): DirectConversation | null {
    for (let i = 0; i < this.directConversations.length; i++) {
      if (this.directConversations[i].sessionId === sessionId) {
        return this.directConversations[i];
      }
    }
    return null;
  }

  /** 把当前正文与标题存回它所属的本机会话（切走 / 收尾时调用）。 */
  private syncDirectCurrent(): void {
    const conv: DirectConversation | null = this.findDirectConversation(this.currentSessionId);
    if (conv === null) {
      return;
    }
    conv.messages = this.messages;
    if (conv.title.length === 0 && this.currentTitle.length > 0 && this.currentTitle !== '本机会话') {
      conv.title = this.currentTitle;
    }
  }

  /** 本机会话有活动（一轮结束 / 报错）：刷新时间并把它抬到最前。 */
  private bumpDirectConversation(sessionId: string): void {
    const conv: DirectConversation | null = this.findDirectConversation(sessionId);
    if (conv === null) {
      return;
    }
    conv.updatedAt = Date.now();
    this.publishDirectSessions();
  }

  /**
   * 建一条本机会话（独立模式的「hero 直接开聊」：发第一条消息就地建会话）。
   * 与 dsh 模式的 `sendDsh` 同语义：本地先出现一行，再开始产出。
   */
  private beginDirectConversation(firstText: string): void {
    const conv: DirectConversation = new DirectConversation('local-' + Date.now().toString());
    conv.cwd = this.workspaceDirectory;
    conv.title = firstText.length > Constants.TITLE_MAX_CHARS
      ? firstText.slice(0, Constants.TITLE_MAX_CHARS) : firstText;
    this.directConversations.unshift(conv);
    this.currentSessionId = conv.sessionId;
    this.currentTitle = conv.title;
    this.publishDirectSessions();
  }

  /**
   * 把当前正文收进一条本机会话（切回独立模式时用；已经在某条会话里就只同步）。
   *
   * ⚠️ 进来时 `currentSessionId` 可能还停在 **dsh 服务模式的会话 id** 上（从 dsh 服务模式切回来、
   * 或在那里点了「新会话」），它不是本机会话：必须先把这枚悬挂 id 清掉。否则后面发消息时
   * 「已经有 id」会跳过就地建会话（见 sendDirect），侧栏就一条行也不出 —— 主人报的
   * 「发送消息之后不生成新会话在左侧」正是这条路径。
   */
  private adoptDirectConversation(): void {
    const carriedTitle: string = this.currentTitle;
    if (this.findDirectConversation(this.currentSessionId) === null) {
      // 悬挂 id：正文也还没内容时连标题一起复位（标题栏/侧栏都以「新会话」起）
      this.currentSessionId = '';
      if (this.messages.length === 0) {
        this.currentTitle = '';
      }
    }
    if (this.messages.length === 0) {
      return;
    }
    if (this.findDirectConversation(this.currentSessionId) !== null) {
      this.syncDirectCurrent();
      return;
    }
    const conv: DirectConversation = new DirectConversation('local-' + Date.now().toString());
    conv.cwd = this.workspaceDirectory;
    conv.title = carriedTitle.length > 0 && carriedTitle !== '本机会话'
      ? carriedTitle : '本机会话';
    conv.messages = this.messages;
    this.directConversations.unshift(conv);
    this.currentSessionId = conv.sessionId;
    this.currentTitle = conv.title;
    this.publishDirectSessions();
  }

  /** 独立模式下选中一条本机会话：存回当前、取出目标（消息一起带过去）。 */
  private selectDirectSession(sessionId: string): void {
    if (sessionId === this.currentSessionId && this.messages.length > 0) {
      return;
    }
    this.deepseek.stop();
    this.syncDirectCurrent();
    const conv: DirectConversation | null = this.findDirectConversation(sessionId);
    this.currentSessionId = conv === null ? '' : conv.sessionId;
    this.currentTitle = conv === null || conv.title.length === 0 ? '本机会话' : conv.title;
    this.messages = conv === null ? [] : conv.messages.slice();
    this.streaming = false;
    this.followBottom = true;
  }

  /** 保存登录 cookie（30 天有效，重启后直接复用） */
  private saveAuthCookie(cookie: string): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(host, { name: Constants.SETTINGS_STORE });
      store.putSync(Constants.KEY_AUTH_COOKIE, cookie);
      store.flush();
    } catch (e) {
      // 保存失败不阻塞（下次启动重新取一枚）
    }
  }

  private saveServerUrl(): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(host, { name: Constants.SETTINGS_STORE });
      store.putSync(Constants.KEY_SERVER_URL, this.serverUrl);
      store.flush();
    } catch (e) {
      // 保存失败不阻塞
    }
  }

  private saveAgentPreset(preset: string): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(host, { name: Constants.SETTINGS_STORE });
      store.putSync(Constants.KEY_AGENT_PRESET, preset);
      store.flush();
    } catch (e) {
      // 保存失败不阻塞
    }
  }

  /** 保存连接模式偏好 */
  private saveMode(mode: string): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(host, { name: Constants.SETTINGS_STORE });
      store.putSync(Constants.KEY_MODE, mode);
      store.flush();
    } catch (e) {
      // 保存失败不阻塞
    }
  }

  /**
   * 解析并应用外观：跟随系统时读 Configuration.colorMode，否则用显式偏好。
   * 两处 AppStorage 写入即触发所有订阅组件重绘（令牌切换无逐层传参）。
   */
  private applyAppearance(): void {
    let dark: boolean = true;
    if (this.appearance === Appearance.LIGHT) {
      dark = false;
    } else if (this.appearance === Appearance.DARK) {
      dark = true;
    } else {
      dark = this.systemDark();
    }
    // 页面自身走 @State（build 读到即重建）；子组件走 AppStorage（@StorageProp 订阅）。
    this.dark = dark;
    AppStorage.setOrCreate(KEY_DARK_THEME, dark);
    AppStorage.setOrCreate(KEY_CONTENT_FONT_SIZE, this.contentFontSize);
  }

  /** 系统是否深色（Configuration.colorMode；读不到时沿用上一次）。 */
  private systemDark(): boolean {
    const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (host === undefined || host === null) {
      return Theme.isDark();
    }
    const mode: ConfigurationConstant.ColorMode | undefined = host.config.colorMode;
    if (mode === undefined) {
      return Theme.isDark();
    }
    return mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /** 保存外观偏好并立即生效（对应上游 ui-theme 的外观选择）。 */
  private saveAppearance(appearance: string): void {
    this.appearance = appearance;
    this.applyAppearance();
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(host, { name: Constants.SETTINGS_STORE });
      store.putSync(Constants.KEY_APPEARANCE, appearance);
      store.flush();
    } catch (e) {
      // 写失败不影响本次会话内的观感
    }
  }

  /** 保存正文档位并立即生效（上游 12–17，默认 14）。 */
  private saveContentFontSize(size: number): void {
    const clamped: number = Math.min(17, Math.max(12, Math.round(size)));
    this.contentFontSize = clamped;
    this.applyAppearance();
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(host, { name: Constants.SETTINGS_STORE });
      store.putSync(Constants.KEY_CONTENT_FONT_SIZE, clamped);
      store.flush();
    } catch (e) {
      // 同上
    }
  }

  /** 保存直连模式配置（API Key + 模型，存应用本地，不经过服务端） */
  private saveDirectConfig(): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(host, { name: Constants.SETTINGS_STORE });
      store.putSync(Constants.KEY_DIRECT_API_KEY, this.directApiKey);
      store.putSync(Constants.KEY_DIRECT_MODEL, this.directModel);
      store.putSync(Constants.KEY_DIRECT_BASE_URL, this.directBaseUrl);
      store.flush();
    } catch (e) {
      // 保存失败不阻塞
    }
  }

  /**
   * 加载对话模式：**先内置、后服务**。
   * 内置目录（rawfile/presets.json）永远可用 → 独立模式开箱即用；dsh 服务在线时再用
   * `agentPresets/list` 覆盖（服务端那份是部署真值，可能多出本仓库没有的预设）。
   * 服务端只给 id/name/description，产品名与系统提示仍以内置目录为准（提示是客户端要用的）。
   */
  private loadPresets(): void {
    this.applyBundledPresets();
    const client = this.client;
    if (client === null) {
      return;
    }
    client.agentPresetList().then((items: Array<Record<string, Object>>) => {
      const ids: string[] = [];
      const names: string[] = [];
      for (let i = 0; i < items.length; i++) {
        if (items[i]['broken'] !== undefined && items[i]['broken'] !== null) {
          continue; // broken 预设不可选
        }
        const id: string = String(items[i]['id']);
        ids.push(id);
        const served: string = items[i]['name'] === undefined || items[i]['name'] === null
          ? '' : String(items[i]['name']);
        // 内置目录有中文产品名（且与仓库同源）时优先它，服务端只补它没有的
        const bundled: string = PresetCatalog.displayName(this.presets, id);
        names.push(bundled !== id ? bundled : (served.length > 0 ? served : id));
      }
      if (ids.length === 0) {
        return;
      }
      this.presetIds = ids;
      this.presetNames = names;
      if (this.currentPreset.length > 0 && ids.indexOf(this.currentPreset) === -1) {
        this.currentPreset = '';
      }
    }).catch((e: BusinessError) => {
      // 服务端不可用：内置目录已在上面生效，什么都不用做
    });
  }

  /** 内置目录 → 胶囊列表；默认对话模式设为 ProMax（与仓库 presets 的 order 一致）。 */
  private applyBundledPresets(): void {
    const list: PresetInfo[] = this.presets.length > 0 ? this.presets : PresetCatalog.fallback();
    const ids: string[] = [];
    const names: string[] = [];
    for (let i = 0; i < list.length; i++) {
      ids.push(list[i].id);
      names.push(list[i].name.length > 0 ? list[i].name : list[i].id);
    }
    this.presetIds = ids;
    this.presetNames = names;
    if (this.currentPreset.length === 0) {
      this.currentPreset = 'harmony-chat-promax';
    }
  }

  /** 对话模式胶囊文案：会话绑定的优先，其次暂存值 → 产品名。 */
  private presetLabel(): string {
    const id: string = this.sessionPreset.length > 0 ? this.sessionPreset : this.currentPreset;
    if (id.length === 0) {
      return '';
    }
    return PresetCatalog.displayName(this.presets, id);
  }

  /** 当前模式的说明（菜单首行）。 */
  private presetDescription(): string {
    const id: string = this.sessionPreset.length > 0 ? this.sessionPreset : this.currentPreset;
    return PresetCatalog.describe(this.presets, id);
  }

  /** 模式是否锁定：已经开聊（两侧同语义，上游「首个回合后锁定」）。 */
  private presetLocked(): boolean {
    return this.messages.length > 0;
  }

  // —— 连接 ——

  private connect(): void {
    if (this.connecting) {
      return;
    }
    this.connecting = true;
    this.statusText = '连接中…';
    const client: DshApiClient = new DshApiClient(this.serverUrl);
    this.client = client;
    // 0.1.6 起 /api/* 与事件流都要求会话 cookie：本机回环由 Host 直接签发（30 天），
    // 先复用落盘的那枚；过期/缺失时 DshApiClient 内部还会在 401 后再取一次。
    client.setCookie(this.authCookie);
    client.login().then((cookie: string) => {
      if (cookie.length > 0 && cookie !== this.authCookie) {
        this.authCookie = cookie;
        this.saveAuthCookie(cookie);
      }
      client.openMux(
        () => {
          // 事件流建立（含断线自动重连成功）：恢复连接态、刷新会话列表并重订当前会话
          this.connected = true;
          this.statusText = '已连接';
          this.refreshSessions();
          this.refollowSession();
          // 宿主事件流（$events）：会话列表的实时刷新来源，连上就订，重连后由 reopenStreams 原样重开
          this.openHostEvents();
        },
        (msg: string) => {
          this.connected = false;
          this.statusText = msg;
        }
      );
      return client.describe();
    }).then(() => {
      this.connected = true;
      this.statusText = '已连接';
      this.connecting = false;
      this.refreshSessions();
      this.loadPermissionCatalog();
      this.loadModelCatalog();
      this.openHostEvents();
    }).catch((e: BusinessError) => {
      this.connecting = false;
      this.connected = false;
      this.statusText = '未连接：服务未启动？先在鸿蒙终端运行 sh ~/bin/dsh-web.sh（自动探测中…）';
    });
  }

  /** 读取工作区权限目录（沙箱模式 + 审批策略；`permissionPresets/catalog`） */
  private loadPermissionCatalog(): void {
    const client = this.client;
    if (client === null) {
      return;
    }
    client.permissionCatalog().then((options: Array<Record<string, Object>>) => {
      const names: string[] = [];
      for (let i = 0; i < options.length; i++) {
        const value = options[i]['value'];
        if (value !== undefined && value !== null) {
          names.push(String(value));
        }
      }
      this.permissionOptions = names;
    }).catch((e: BusinessError) => {
      // 目录拉不到就退回内置三档（与部署默认表一致）
      this.permissionOptions = ['read-only', 'workspace-write', 'danger-full-access'];
    });
  }

  /**
   * 读取 dsh 服务端模型目录（`session/modelCatalog`）：groups[].models[] 摊平成
   * `provider/model` 键进模型胶囊，default 作为当前值兜底（会话投影优先）。
   */
  private loadModelCatalog(): void {
    const client = this.client;
    if (client === null) {
      return;
    }
    client.modelCatalog().then((value: Record<string, Object>) => {
      const keys: string[] = [];
      const groups: Array<Record<string, Object>> = value['groups'] as Array<Record<string, Object>>;
      if (groups !== undefined && groups !== null) {
        for (let i = 0; i < groups.length; i++) {
          const provider: string = String(groups[i]['id']);
          const models: Array<Record<string, Object>> = groups[i]['models'] as Array<Record<string, Object>>;
          if (models === undefined || models === null) {
            continue;
          }
          for (let j = 0; j < models.length; j++) {
            keys.push(provider + '/' + String(models[j]['id']));
          }
        }
      }
      const fallback: Record<string, Object> = value['default'] as Record<string, Object>;
      let defaultKey: string = '';
      if (fallback !== undefined && fallback !== null && fallback['provider'] !== undefined) {
        defaultKey = String(fallback['provider']) + '/' + String(fallback['model']);
      }
      this.modelKeys = keys;
      this.catalogDefaultModel = defaultKey;
      this.syncCurrentSessionState();
    }).catch((e: BusinessError) => {
      // 目录拉不到就空着：菜单会提示「目录未就绪」，不影响发消息
    });
  }

  /**
   * 一条 session 摘要（`session/list` 的行 / `api-session/added` 的载荷，同一份权威结构）
   * → 侧栏投影。两处共用，避免「实时新增的行」与「全量刷新的行」字段对不上。
   */
  private parseSessionSummary(raw: Record<string, Object>): DshSession {
    const session: DshSession = new DshSession(String(raw['sessionId']));
    session.updatedAt = Number(raw['updatedAt']);
    session.running = raw['running'] === true;
    session.blank = raw['blank'] === true;
    const cwd = raw['cwd'];
    if (cwd !== undefined && cwd !== null) {
      session.cwd = String(cwd);
    }
    const proj: Record<string, Object> = raw['projections'] as Record<string, Object>;
    if (proj !== undefined && proj !== null) {
      const values: Record<string, Object> = proj['values'] as Record<string, Object>;
      if (values !== undefined && values !== null) {
        const title = values['title'];
        if (title !== undefined && title !== null) {
          session.title = String(title);
        }
        const permission: Record<string, Object> = values['permissions'] as Record<string, Object>;
        if (permission !== undefined && permission !== null && permission['currentValue'] !== undefined) {
          session.permission = String(permission['currentValue']);
        }
        const preset = values['agentPreset'];
        if (preset !== undefined && preset !== null) {
          session.agentPreset = String(preset);
        }
        // modelSelection 投影：lastUsed（已经用过的）/ next（下一次将用的）
        const selection: Record<string, Object> = values['modelSelection'] as Record<string, Object>;
        if (selection !== undefined && selection !== null) {
          let used: Record<string, Object> = selection['lastUsed'] as Record<string, Object>;
          if (used === undefined || used === null) {
            used = selection['next'] as Record<string, Object>;
          }
          if (used !== undefined && used !== null && used['model'] !== undefined) {
            session.model = String(used['model']);
            session.modelProvider = used['provider'] === undefined ? '' : String(used['provider']);
          }
        }
      }
    }
    return session;
  }

  /** 会话行按 updatedAt 降序（与 session/list 的返回顺序一致；新会话/新活动在最上面）。 */
  private sortSessions(list: DshSession[]): DshSession[] {
    const sorted: DshSession[] = list.slice();
    sorted.sort((a: DshSession, b: DshSession): number => b.updatedAt - a.updatedAt);
    return sorted;
  }

  /** 全量刷新去抖：短时间内多条事件只打一次 session/list（一份 ~190KB / ~1s）。 */
  private scheduleSessionRefresh(delay: number): void {
    if (this.sessionRefreshTimer !== -1) {
      clearTimeout(this.sessionRefreshTimer);
    }
    this.sessionRefreshTimer = setTimeout(() => {
      this.sessionRefreshTimer = -1;
      if (this.sessionRefreshInFlight) {
        this.sessionRefreshPending = true;
        return;
      }
      this.refreshSessions();
    }, delay);
  }

  private refreshSessions(): void {
    const client = this.client;
    if (client === null || this.sessionRefreshInFlight) {
      return;
    }
    this.sessionRefreshInFlight = true;
    client.listSessions().then((items: Array<Record<string, Object>>) => {
      if (this.mode !== 'dsh') {
        // 已经切回独立模式：这份服务端列表会盖掉 `directConversations` 的投影（侧栏瞬间变成 286 条服务端会话）
        this.releaseSessionRefresh();
        return;
      }
      const list: DshSession[] = [];
      for (let i = 0; i < items.length; i++) {
        list.push(this.parseSessionSummary(items[i]));
      }
      // 合并旧标题（避免刷新时丢失本地自动标题）
      if (this.sessions.length > 0) {
        for (let i = 0; i < list.length; i++) {
          if (list[i].title.length === 0) {
            for (let j = 0; j < this.sessions.length; j++) {
              if (this.sessions[j].sessionId === list[i].sessionId && this.sessions[j].title.length > 0) {
                list[i].title = this.sessions[j].title;
                break;
              }
            }
          }
        }
      }
      this.sessions = list;
      this.syncWorkspaceOptions(list);
      this.syncCurrentSessionState();
      this.releaseSessionRefresh();
      // 自动选中第一个非空会话
      if (this.currentSessionId.length === 0 && list.length > 0) {
        for (let i = 0; i < list.length; i++) {
          if (!list[i].blank) {
            this.selectSession(list[i].sessionId);
            return;
          }
        }
        this.selectSession(list[0].sessionId);
      }
    }).catch((e: BusinessError) => {
      this.statusText = String(e);
      this.releaseSessionRefresh();
    });
  }

  /** 全量刷新收尾：解锁并兑现去抖期间挂起的那一次。 */
  private releaseSessionRefresh(): void {
    this.sessionRefreshInFlight = false;
    if (this.sessionRefreshPending) {
      this.sessionRefreshPending = false;
      this.scheduleSessionRefresh(200);
    }
  }

  // —— 首页选择器（工作区 / 工作区权限 / 对话模式） ——

  /** 工作区候选：会话 cwd 去重（保序）+ 手选目录 + 当前会话工作区 */
  private syncWorkspaceOptions(list: DshSession[]): void {
    const options: string[] = [];
    const push = (value: string): void => {
      if (value.length === 0) {
        return;
      }
      for (let i = 0; i < options.length; i++) {
        if (options[i] === value) {
          return;
        }
      }
      options.push(value);
    };
    push(this.workspaceDirectory);
    for (let i = 0; i < list.length; i++) {
      push(list[i].cwd);
    }
    this.workspaceOptions = options;
  }

  /** 当前会话的三个选择器取值（标题 / 工作区权限 / 对话模式） */
  private syncCurrentSessionState(): void {
    for (let i = 0; i < this.sessions.length; i++) {
      const session: DshSession = this.sessions[i];
      if (session.sessionId !== this.currentSessionId) {
        continue;
      }
      this.currentPermission = session.permission;
      this.sessionPreset = session.agentPreset;
      if (session.model.length > 0 && session.modelProvider.length > 0) {
        this.currentModelKey = session.modelProvider + '/' + session.model;
      } else if (this.catalogDefaultModel.length > 0) {
        this.currentModelKey = this.catalogDefaultModel;
      }
      return;
    }
  }

  /** 当前选中会话（没有则 null）。 */
  private currentSession(): DshSession | null {
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].sessionId === this.currentSessionId) {
        return this.sessions[i];
      }
    }
    return null;
  }

  /**
   * 订阅当前会话的事件流（历史快照 + 实时事件 + 实时增量）。
   * 与上游一致：切会话先取消上一条订阅，再按新会话重开。
   */
  private followCurrentSession(): void {
    const client = this.client;
    if (client === null || this.currentSessionId.length === 0) {
      return;
    }
    if (this.followStreamId.length > 0) {
      client.closeStream(this.followStreamId);
      this.followStreamId = '';
    }
    this.followStreamId = client.followSession(this.currentSessionId, {
      onFrame: (value: Record<string, Object>) => { this.onFollowValue(value); },
      onEnd: (reason: string) => {
        if (reason.length > 0) {
          this.statusText = reason;
        }
      }
    });
  }

  /** 连接（含重连）后重订当前会话 */
  private refollowSession(): void {
    if (this.mode !== 'dsh' || this.currentSessionId.length === 0) {
      return;
    }
    this.followCurrentSession();
  }

  /**
   * 订阅宿主全局事件流（`$events`）。这是侧栏「实时刷新出最新会话」的唯一来源：
   * 宿主把 `api-session/added`（新会话）/ `removed` / `status`（运行位）/ `activity`（活动时间）
   * 按原样转发给客户端，官方 web 端也是靠这一路 `ctx.remote.$on` 维持列表的。
   */
  private openHostEvents(): void {
    const client = this.client;
    if (client === null || this.hostEventsStreamId.length > 0) {
      return;
    }
    this.hostEventsStreamId = client.openHostEvents({
      onFrame: (value: Record<string, Object>) => { this.onHostEvent(value); },
      onEnd: (reason: string) => {
        this.hostEventsStreamId = '';
        if (reason.length > 0) {
          this.statusText = reason;
        }
      }
    });
  }

  /**
   * 宿主事件 → 侧栏就地更新（不重拉 session/list：286 条要 ~190KB / ~1s）。
   * 事件载荷与 `session/list` 的行同源，字段够用；只有本地还没有这一行时才兜底全量刷新。
   */
  private onHostEvent(value: Record<string, Object>): void {
    if (this.mode !== 'dsh') {
      // 宿主事件流是切模式之前开的：独立模式下侧栏渲染的是本机会话，不能被服务端行混进来
      return;
    }
    const kind: string = String(value['type']);
    if (kind !== 'emit') {
      return; // ready = 事件源就绪，没有业务负载
    }
    const name: string = String(value['event']);
    const args: Array<Object> = value['args'] as Array<Object>;
    if (args === undefined || args === null || args.length === 0) {
      return;
    }
    // 真机排障：`hdc shell "hilog | grep DshMux"` 能看到宿主事件是否真的在往下走
    hilog.info(0xD004, 'DshMux', '宿主事件 %{public}s %{public}s', name, String(args[0]));
    if (name === 'api-session/added') {
      const raw: Record<string, Object> = args[0] as Record<string, Object>;
      if (raw !== undefined && raw !== null) {
        this.upsertSession(this.parseSessionSummary(raw));
      }
      return;
    }
    const sessionId: string = String(args[0]);
    if (name === 'api-session/removed') {
      this.removeSession(sessionId);
      return;
    }
    if (name === 'api-session/status') {
      this.markSessionRunning(sessionId, args.length > 1 && args[1] === true);
      return;
    }
    if (name === 'api-session/activity') {
      const at: number = args.length > 1 ? Number(args[1]) : Date.now();
      this.touchSession(sessionId, at);
      return;
    }
    if (name === 'api-session/error') {
      // 只管一行报错时本地可能还没有这条会话：交给一次去抖全量刷新兜底
      this.scheduleSessionRefresh(800);
    }
  }

  /** 新会话（含别处创建的）：本地插入并按 activity 时间排到最前。 */
  private upsertSession(session: DshSession): void {
    const list: DshSession[] = this.sessions.slice();
    let replaced: boolean = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i].sessionId === session.sessionId) {
        if (session.title.length === 0) {
          session.title = list[i].title;
        }
        list[i] = session;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      if (session.updatedAt <= 0) {
        session.updatedAt = Date.now();
      }
      list.push(session);
    }
    this.sessions = this.sortSessions(list);
    this.syncWorkspaceOptions(this.sessions);
  }

  /** 会话被移除（归档 / 关闭）：从侧栏摘掉；如果正是当前会话就连正文一起清。 */
  private removeSession(sessionId: string): void {
    const list: DshSession[] = [];
    let removed: boolean = false;
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].sessionId === sessionId) {
        removed = true;
        continue;
      }
      list.push(this.sessions[i]);
    }
    if (!removed) {
      return;
    }
    this.sessions = list;
    if (this.currentSessionId === sessionId) {
      this.currentSessionId = '';
      this.currentTitle = '';
      this.sessionPreset = '';
      this.currentPermission = '';
      this.messages = [];
      this.streaming = false;
    }
  }

  /** 运行位翻转（运行中 = 侧栏那一行的小圆点） */
  private markSessionRunning(sessionId: string, running: boolean): void {
    const list: DshSession[] = this.sessions.slice();
    for (let i = 0; i < list.length; i++) {
      if (list[i].sessionId !== sessionId) {
        continue;
      }
      if (list[i].running === running) {
        return;
      }
      list[i].running = running;
      this.sessions = list;
      return;
    }
    this.scheduleSessionRefresh(800);
  }

  /** 活动时间前移（别处发了消息 / 定时任务跑了一轮）：把这一行提到最前。 */
  private touchSession(sessionId: string, updatedAt: number): void {
    const list: DshSession[] = this.sessions.slice();
    for (let i = 0; i < list.length; i++) {
      if (list[i].sessionId !== sessionId) {
        continue;
      }
      const at: number = updatedAt > 0 ? updatedAt : Date.now();
      if (list[i].updatedAt === at && i === 0) {
        return; // 已经在最前且时间没变：不制造无谓重建
      }
      list[i].updatedAt = at;
      this.sessions = this.sortSessions(list);
      // 这一行还没有标题（刚在别处建出来、`session/title` 只走会话自己的 follow 流）：
      // 借一次去抖全量把标题补上，免得侧栏一直挂着「新会话」
      if (list[i].title.length === 0) {
        this.scheduleSessionRefresh(800);
      }
      return;
    }
    // 本地没有这一行（别处新建的会话）：交给一次去抖全量刷新
    this.scheduleSessionRefresh(200);
  }

  /** 事件流下行帧：snapshot（历史+投影）/ event（durable）/ assistant-stream（实时增量） */
  private onFollowValue(value: Record<string, Object>): void {
    if (this.mode !== 'dsh') {
      // 流是切模式之前开的、服务端仍在下发：别拿服务端快照/增量改写独立模式的正文
      return;
    }
    const kind: string = String(value['type']);
    if (kind === 'snapshot') {
      this.applySnapshot(value);
      return;
    }
    if (kind === 'event') {
      const ev: Record<string, Object> = value['event'] as Record<string, Object>;
      if (ev === undefined || ev === null) {
        return;
      }
      this.applyLiveEvent(ev);
      return;
    }
    if (kind === 'assistant-stream') {
      const frame: Record<string, Object> = value['frame'] as Record<string, Object>;
      if (frame === undefined || frame === null) {
        return;
      }
      this.applyAssistantFrame(frame);
    }
  }

  /** 历史快照：折叠 records 建消息列，并从投影基线刷新权限/模式 */
  private applySnapshot(value: Record<string, Object>): void {
    const projections: Record<string, Object> = value['projections'] as Record<string, Object>;
    if (projections !== undefined && projections !== null) {
      const values: Record<string, Object> = projections['values'] as Record<string, Object>;
      if (values !== undefined && values !== null) {
        const title = values['title'];
        if (title !== undefined && title !== null && String(title).length > 0) {
          this.currentTitle = String(title);
          this.updateSessionTitleLocal(this.currentSessionId, String(title));
        }
        const permission: Record<string, Object> = values['permissions'] as Record<string, Object>;
        if (permission !== undefined && permission !== null && permission['currentValue'] !== undefined) {
          this.currentPermission = String(permission['currentValue']);
        }
      }
    }
    const records: Array<Record<string, Object>> = value['records'] as Array<Record<string, Object>>;
    const list: ChatMessage[] = [];
    let current: ChatMessage | null = null;
    if (records !== undefined && records !== null) {
      for (let i = 0; i < records.length; i++) {
        const entry: Record<string, Object> = records[i];
        const ev: Record<string, Object> = entry['event'] as Record<string, Object>;
        if (ev === undefined || ev === null) {
          continue;
        }
        current = this.foldEvent(ev, list, current);
      }
    }
    this.messages = list;
    this.streaming = false;
    if (this.currentTitle.length === 0) {
      for (let i = 0; i < list.length; i++) {
        if (list[i].role === 'user' && list[i].text.length > 0) {
          const t: string = list[i].text.length > Constants.TITLE_MAX_CHARS ?
            list[i].text.slice(0, Constants.TITLE_MAX_CHARS) : list[i].text;
          this.currentTitle = t;
          this.updateSessionTitleLocal(this.currentSessionId, t);
          break;
        }
      }
    }
    this.scrollToBottom();
  }

  /** 一条 durable 事件（当前会话折叠进消息列，别的会话只更新运行态） */
  private applyLiveEvent(ev: Record<string, Object>): void {
    const list: ChatMessage[] = this.messages.slice();
    let current: ChatMessage | null = null;
    for (let i = list.length - 1; i >= 0; i--) {
      if (list[i].role === 'assistant' && list[i].status === 'streaming') {
        current = list[i];
        break;
      }
    }
    this.foldEvent(ev, list, current);
    this.messages = list;
    const type: string = String(ev['type']);
    if (type === 'turn/end' || type === 'session/title') {
      this.refreshSessions();
    }
    this.scrollToBottom();
  }

  /**
   * 实时增量帧（assistant-stream）：文本 / 思考逐字追加。
   *
   * 帧来自宿主 `assistantStream: true` 的 follow 流（官方 web 端的同一路）：
   * `start` → `chunk`（text-delta / reasoning-delta / block-start 等）→ `end`。
   * 这里只在第一个 text/reasoning 增量上建气泡，避免 `block-start` 先造出一个空气泡。
   */
  private applyAssistantFrame(frame: Record<string, Object>): void {
    const kind: string = String(frame['type']);
    if (kind === 'start') {
      this.streaming = true;
      return;
    }
    if (kind === 'end') {
      this.streaming = false;
      return;
    }
    if (kind !== 'chunk') {
      return;
    }
    const chunk: Record<string, Object> = frame['chunk'] as Record<string, Object>;
    if (chunk === undefined || chunk === null) {
      return;
    }
    const chunkType: string = String(chunk['type']);
    if (chunkType !== 'text-delta' && chunkType !== 'reasoning-delta' && chunkType !== 'block-start') {
      return;
    }
    const list: ChatMessage[] = this.messages.slice();
    let current: ChatMessage | null = null;
    for (let i = list.length - 1; i >= 0; i--) {
      if (list[i].role === 'assistant' && list[i].status === 'streaming') {
        current = list[i];
        break;
      }
    }
    if (current === null) {
      if (chunkType !== 'text-delta' && chunkType !== 'reasoning-delta') {
        return; // 还没有气泡时 block-start 单独到达：等第一个增量再说
      }
      current = new ChatMessage('stream-' + Date.now().toString(36), 'assistant', Date.now());
      current.status = 'streaming';
      list.push(current);
    }
    if (chunkType === 'block-start') {
      // 同一次尝试里的第 2..n 个思考块：换行接上，别把两段粘成一行
      if (String(chunk['blockType']) === 'reasoning' && current.reasoning.length > 0) {
        current.reasoning += '\n\n';
        this.messages = list;
      }
      return;
    }
    const text: string = chunk['text'] === undefined ? '' : String(chunk['text']);
    if (chunkType === 'text-delta') {
      current.text += text;
    } else {
      current.reasoning += text;
    }
    this.messages = list;
    this.scrollToBottom();
  }

  /** 工作区胶囊：选中一个工作区（用于之后新建的会话） */
  private pickWorkspace(path: string): void {
    this.workspaceDirectory = path;
    const prefs: DesktopPrefs | null = this.prefs;
    if (prefs !== null) {
      prefs.putString(DesktopPrefKeys.WORKSPACE_DIRECTORY, path);
    }
    const options: string[] = this.workspaceOptions.slice();
    let found: boolean = false;
    for (let i = 0; i < options.length; i++) {
      if (options[i] === path) {
        found = true;
        break;
      }
    }
    if (!found && path.length > 0) {
      options.unshift(path);
      this.workspaceOptions = options;
    }
    this.toast('工作区已设为：' + path);
  }

  /**
   * 工作区权限胶囊：走 `/permission <preset>` 命令（与网页端同一写入路径）。
   * 完全权限 / Auto review 两档先过风险确认（上游 RiskConfirmation），其余直接生效。
   */
  private pickPermission(preset: string): void {
    const client = this.client;
    if (client === null || this.currentSessionId.length === 0) {
      this.toast('请先连接 dsh 服务并选择会话');
      return;
    }
    if (Constants.permissionNeedsRisk(preset)) {
      const risk: PermissionRisk = Constants.permissionRisk(preset);
      this.permissionRiskValue = preset;
      this.permissionRiskTitle = risk.title;
      this.permissionRiskBody = risk.description;
      this.permissionRiskConfirm = risk.confirmLabel;
      this.permissionRiskAck = false;
      this.permissionRiskVisible = true;
      return;
    }
    this.commitPermission(preset);
  }

  /** 提交一次权限切换（风险档位由确认弹层调用） */
  private commitPermission(preset: string): void {
    const client = this.client;
    if (client === null) {
      return;
    }
    this.currentPermission = preset;
    client.executeCommand(this.currentSessionId, '/permission ' + preset).then(() => {
      this.toast('工作区权限已设为：' + Constants.permissionLabel(preset));
    }).catch((e: BusinessError) => {
      this.currentPermission = '';
      this.toast('切换失败：' + String(e));
      this.syncCurrentSessionState();
    });
  }

  /** 权限胶囊是否可点：dsh 服务 + 已连接 + 当前会话存在（上游无会话则不渲染该座位） */
  private permissionEnabled(): boolean {
    return this.mode !== 'direct' && this.connected && this.currentSessionId.length > 0;
  }

  /** 权限胶囊不可用时的原因文案 */
  private permissionReason(): string {
    if (this.mode === 'direct') {
      return '独立模式没有 dsh 工作区权限（这里是内置直连，不经过 dsh 沙箱）';
    }
    if (!this.connected) {
      return '未连接 dsh 服务：先在设置里确认服务地址';
    }
    return '还没有会话：发一条消息就会建会话，之后可切换工作区权限';
  }

  /** 从胶囊菜单一键切到 dsh 服务模式（独立模式下工作区/权限都属于 dsh 服务） */
  private switchToDshMode(): void {
    if (this.mode === 'dsh') {
      return;
    }
    this.syncDirectCurrent();
    this.mode = 'dsh';
    this.saveMode('dsh');
    this.deepseek.stop();
    this.messages = [];
    this.currentTitle = '';
    this.applyMode();
    this.toast('已切换到 dsh 服务模式');
  }

  /**
   * 对话模式胶囊：独立模式下它就是「系统提示」（立即生效，下一轮开始生效）；
   * dsh 服务模式下是新建会话的 agentPreset。已有对话内容的会话不可更换（与上游一致）。
   */
  private pickPreset(preset: string): void {
    if (this.messages.length > 0) {
      this.toast('当前会话已开始，对话模式不可更改；新建会话后生效');
      return;
    }
    this.currentPreset = preset;
    this.saveAgentPreset(preset);
    this.toast('对话模式已设为：' + PresetCatalog.displayName(this.presets, preset));
  }

  // —— 会话 ——

  private newSession(): void {
    if (this.mode === 'direct') {
      // 内置直连：新建会话 = 把当前这轮收进本机会话清单，再开一轮空的
      // （清单留在侧栏可切回；新会话行等第一条消息发出去时才落，不制造空行）
      this.deepseek.stop();
      this.syncDirectCurrent();
      this.messages = [];
      this.currentTitle = '本机会话';
      this.streaming = false;
      this.currentSessionId = '';
      this.followBottom = true;
      this.publishDirectSessions();
      return;
    }
    const client = this.client;
    if (client === null) {
      return;
    }
    client.createSession(this.workspaceDirectory, this.currentPreset).then((sessionId: string) => {
      const session: DshSession = new DshSession(sessionId);
      const list: DshSession[] = [];
      list.push(session);
      for (let i = 0; i < this.sessions.length; i++) {
        list.push(this.sessions[i]);
      }
      this.sessions = list;
      this.selectSession(sessionId);
    }).catch((e: BusinessError) => {
      this.statusText = String(e);
    });
  }

  private selectSession(sessionId: string): void {
    if (this.mode === 'direct') {
      this.selectDirectSession(sessionId);
      return;
    }
    const client = this.client;
    if (client === null) {
      return;
    }
    if (sessionId === this.currentSessionId && this.messages.length > 0) {
      return;
    }
    this.currentSessionId = sessionId;
    this.currentTitle = '';
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].sessionId === sessionId) {
        this.currentTitle = this.sessions[i].title;
        break;
      }
    }
    this.messages = [];
    this.streaming = false;
    // 换了一条会话就是要看它的最新内容：重新打开跟随（读者上一条会话里的上翻状态不带过来）
    this.followBottom = true;
    this.currentPermission = '';
    this.sessionPreset = '';
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].sessionId === sessionId) {
        this.currentPermission = this.sessions[i].permission;
        this.sessionPreset = this.sessions[i].agentPreset;
        break;
      }
    }
    // 历史与实时事件同源：一条 session/follow 流既给快照也给增量（上游同一套语义）
    this.followCurrentSession();
  }

  private updateSessionTitleLocal(sessionId: string, title: string): void {
    if (this.mode === 'direct') {
      // 独立模式的行是 directConversations 的投影，改投影没用：改本体再重投影
      const conv: DirectConversation | null = this.findDirectConversation(sessionId);
      if (conv !== null) {
        conv.title = title;
        this.publishDirectSessions();
      }
      return;
    }
    const list: DshSession[] = this.sessions.slice();
    for (let i = 0; i < list.length; i++) {
      if (list[i].sessionId === sessionId) {
        list[i].title = title;
        break;
      }
    }
    this.sessions = list;
  }

  private sendMessage(text: string): void {
    if (this.mode === 'direct') {
      this.sendDirect(text);
      return;
    }
    this.sendDsh(text);
  }

  /** 内置直连模式：直接调 DeepSeek 官方 API 流式对话（WorkBuddy 式打开即用） */
  private sendDirect(text: string): void {
    if (this.directApiKey.length === 0) {
      // 未配置 Key：Toast 提示并直接打开设置
      try {
        this.getUIContext().getPromptAction().showToast({ message: '请先在「设置」→「模型与连接」填写 API Key' });
      } catch (e) {
      }
      this.showSettings = true;
      return;
    }
    // 本机会话：当前 id 不是本机会话就地建一条（与 dsh 模式 hero 直接开聊同语义），
    // 这样侧栏「发消息即出现最新会话」在独立模式下同样成立。
    // ⚠️ 判据是「这条 id 在不在本机会话清单里」，不是「id 空不空」：从 dsh 服务模式切回来时
    // currentSessionId 会带着服务端会话 id（非空但本地没这一行），按空判就会漏建 ⇒ 侧栏不出行。
    if (this.findDirectConversation(this.currentSessionId) === null) {
      this.beginDirectConversation(text);
    }
    // 乐观插入用户消息
    const userMsg: ChatMessage = new ChatMessage('local-' + Date.now().toString(), 'user', Date.now());
    userMsg.text = text;
    userMsg.status = 'done';
    const list: ChatMessage[] = this.messages.slice();
    list.push(userMsg);
    this.messages = list;
    // 组装历史（user/assistant 文本）
    const history: Array<Record<string, Object>> = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].role === 'user' || list[i].role === 'assistant') {
        const item: Record<string, Object> = { 'role': list[i].role, 'content': list[i].text };
        history.push(item);
      }
    }
    // 流式占位
    const assistant: ChatMessage = new ChatMessage('direct-' + Date.now().toString(), 'assistant', Date.now());
    assistant.status = 'streaming';
    const list2: ChatMessage[] = this.messages.slice();
    list2.push(assistant);
    this.messages = list2;
    this.streaming = true;
    this.scrollToBottom(true);
    // 独立模式的「对话模式」= 该预设的 persona 系统提示（rawfile/presets.json），
    // {{model}} / {{cwd}} 就地替换成本机值；没选模式/提示缺失时退化为无 system 提示。
    const modeId: string = this.currentPreset.length > 0 ? this.currentPreset : 'harmony-chat';
    const systemPrompt: string = PresetCatalog.systemPrompt(
      this.presets, modeId, this.directModel,
      this.workspaceDirectory.length > 0 ? this.workspaceDirectory : '');
    this.deepseek.setEndpoint(this.directBaseUrl);
    this.deepseek.chat(this.directApiKey, this.directModel, history,
      (delta: string) => {
        const msgs: ChatMessage[] = this.messages.slice();
        for (let i = msgs.length - 1; i >= 0; i--) {
          if (msgs[i].role === 'assistant' && msgs[i].status === 'streaming') {
            msgs[i].text += delta;
            break;
          }
        }
        this.messages = msgs;
        this.scrollToBottom();
      },
      () => {
        const msgs: ChatMessage[] = this.messages.slice();
        for (let i = msgs.length - 1; i >= 0; i--) {
          if (msgs[i].role === 'assistant' && msgs[i].status === 'streaming') {
            msgs[i].status = 'done';
            break;
          }
        }
        this.messages = msgs;
        this.streaming = false;
        if (this.currentTitle.length === 0 || this.currentTitle === '本机会话') {
          const t: string = text.length > Constants.TITLE_MAX_CHARS ?
            text.slice(0, Constants.TITLE_MAX_CHARS) : text;
          this.currentTitle = t;
          this.updateSessionTitleLocal(this.currentSessionId, t);
        }
        this.syncDirectCurrent();
        this.bumpDirectConversation(this.currentSessionId);
      },
      (err: string) => {
        const msgs: ChatMessage[] = this.messages.slice();
        for (let i = msgs.length - 1; i >= 0; i--) {
          if (msgs[i].role === 'assistant' && msgs[i].status === 'streaming') {
            msgs[i].status = 'error';
            msgs[i].text = '⚠️ 回复失败：' + err;
            break;
          }
        }
        this.messages = msgs;
        this.streaming = false;
        this.statusText = err;
        this.syncDirectCurrent();
        this.bumpDirectConversation(this.currentSessionId);
      },
      systemPrompt,
      (reasoning: string) => {
        // 推理模型（deepseek-v4-flash / reasoner 系）先吐思维链：写进助手的 reasoning，
        // MessageItem 的「思考中」披露行实时跟着长（含跟随滚动）。
        const msgs: ChatMessage[] = this.messages.slice();
        for (let i = msgs.length - 1; i >= 0; i--) {
          if (msgs[i].role === 'assistant' && msgs[i].status === 'streaming') {
            msgs[i].reasoning += reasoning;
            break;
          }
        }
        this.messages = msgs;
        this.scrollToBottom();
      });
  }

  /** dsh 服务模式：走 dsh 的 session/prompt + `/api/remote.mux` WebSocket 事件流 */
  private sendDsh(text: string): void {
    const client = this.client;
    if (client === null) {
      return;
    }
    // 乐观插入用户消息（持久事件回放时会就地接管这条回显，见 foldEvent 的 user/message）
    const userMsg: ChatMessage = new ChatMessage('local-' + Date.now().toString(), 'user', Date.now());
    userMsg.text = text;
    userMsg.status = 'done';
    const list: ChatMessage[] = this.messages.slice();
    list.push(userMsg);
    this.messages = list;
    this.streaming = true;
    this.scrollToBottom(true);
    if (this.currentSessionId.length === 0) {
      // 首页直接开聊（上游同样按需建会话）：先建会话（带工作区 + 对话模式）再发这条
      client.createSession(this.workspaceDirectory, this.currentPreset).then((sessionId: string) => {
        const session: DshSession = new DshSession(sessionId);
        session.cwd = this.workspaceDirectory;
        session.agentPreset = this.currentPreset;
        const created: DshSession[] = [session];
        for (let i = 0; i < this.sessions.length; i++) {
          created.push(this.sessions[i]);
        }
        this.sessions = created;
        this.currentSessionId = sessionId;
        this.sessionPreset = this.currentPreset;
        this.followCurrentSession();
        return client.prompt(sessionId, text);
      }).then(() => {
        this.afterPrompt(text);
      }).catch((e: BusinessError) => {
        this.streaming = false;
        this.statusText = String(e);
      });
      return;
    }
    const sessionId: string = this.currentSessionId;
    client.prompt(sessionId, text).then(() => {
      this.afterPrompt(text);
    }).catch((e: BusinessError) => {
      this.streaming = false;
      this.statusText = String(e);
    });
  }

  /** 发送成功后的本地标题兜底（服务端 session/title 事件到达前先给个名字） */
  private afterPrompt(text: string): void {
    if (this.currentTitle.length === 0 || this.currentTitle === '新会话') {
      const t: string = text.length > Constants.TITLE_MAX_CHARS ?
        text.slice(0, Constants.TITLE_MAX_CHARS) : text;
      this.currentTitle = t;
      this.updateSessionTitleLocal(this.currentSessionId, t);
    }
  }

  private stopGeneration(): void {
    if (this.mode === 'direct') {
      this.deepseek.stop();
      this.streaming = false;
      const msgs: ChatMessage[] = this.messages.slice();
      for (let i = msgs.length - 1; i >= 0; i--) {
        if (msgs[i].role === 'assistant' && msgs[i].status === 'streaming') {
          msgs[i].status = 'done';
          break;
        }
      }
      this.messages = msgs;
      this.syncDirectCurrent();
      this.bumpDirectConversation(this.currentSessionId);
      return;
    }
    const client = this.client;
    if (client === null || this.currentSessionId.length === 0) {
      return;
    }
    client.cancel(this.currentSessionId).then(() => {
      this.streaming = false;
    }).catch((e: BusinessError) => {
      this.statusText = String(e);
    });
  }

  // —— 事件折叠：SessionEvent -> ChatMessage 列表 ——

  private foldEvent(ev: Record<string, Object>,
                    list: ChatMessage[],
                    current: ChatMessage | null): ChatMessage | null {
    const type: string = String(ev['type']);
    const time: number = Number(ev['time']);
    const data: Record<string, Object> = ev['data'] as Record<string, Object>;
    if (data === undefined || data === null) {
      return current;
    }
    if (type === 'user/message') {
      const content: Array<Record<string, Object>> = data['content'] as Array<Record<string, Object>>;
      const text: string = this.blocksToText(content);
      // 本地乐观回显（id 前缀 local-）与刚到的持久事件是同一条消息：就地接管，不再追加一条
      for (let i = list.length - 1; i >= 0; i--) {
        if (list[i].role !== 'user') {
          continue;
        }
        if (list[i].id.indexOf('local-') === 0 && list[i].text === text) {
          list[i].id = String(data['id']);
          return current;
        }
        break;
      }
      const msg: ChatMessage = new ChatMessage(String(data['id']), 'user', time);
      msg.text = text;
      msg.status = 'done';
      list.push(msg);
      return current;
    }
    if (type === 'assistant/chunk') {
      const chunk: Record<string, Object> = data['chunk'] as Record<string, Object>;
      if (chunk === undefined || chunk === null) {
        return current;
      }
      const chunkType: string = String(chunk['type']);
      if (current === null) {
        current = new ChatMessage('stream-' + String(data['turn']), 'assistant', time);
        current.status = 'streaming';
        list.push(current);
      }
      if (chunkType === 'text-delta') {
        current.text += String(chunk['text']);
      } else if (chunkType === 'reasoning-delta') {
        current.reasoning += String(chunk['text']);
      }
      return current;
    }
    if (type === 'assistant/message') {
      const message: Record<string, Object> = data['message'] as Record<string, Object>;
      const id: string = String(message['id']);
      const blocks: Array<Record<string, Object>> = message['content'] as Array<Record<string, Object>>;
      const text: string = this.blocksToText(blocks);
      // 落库的 assistant/message 自带 `reasoning` 块（会话历史/重连快照只有这一份）：
      // 不抽出来的话，切会话或刷一次就看不见思维链了。
      const reasoning: string = this.blocksToReasoning(blocks);
      if (current !== null && current.status === 'streaming') {
        current.id = id;
        current.text = text;
        if (reasoning.length > 0) {
          current.reasoning = reasoning;
        }
        current.status = 'done';
        current.time = time;
        return null;
      }
      const msg: ChatMessage = new ChatMessage(id, 'assistant', time);
      msg.text = text;
      msg.reasoning = reasoning;
      msg.status = 'done';
      list.push(msg);
      return current;
    }
    if (type === 'tool/call') {
      const msg: ChatMessage = new ChatMessage('tool-' + String(data['callId']), 'tool', time);
      msg.toolName = String(data['name']);
      msg.toolArgs = String(data['arguments']);
      msg.status = 'running';
      list.push(msg);
      return current;
    }
    if (type === 'tool/result') {
      const message: Record<string, Object> = data['message'] as Record<string, Object>;
      let callId: string = '';
      if (message !== undefined && message !== null) {
        const toolCallId = message['toolCallId'];
        if (toolCallId !== undefined && toolCallId !== null) {
          callId = String(toolCallId);
        }
      }
      if (callId.length > 0) {
        const targetId: string = 'tool-' + callId;
        for (let i = 0; i < list.length; i++) {
          if (list[i].id === targetId) {
            const err = data['error'];
            list[i].status = err !== undefined && err !== null ? 'error' : 'done';
            break;
          }
        }
      }
      return current;
    }
    if (type === 'turn/start') {
      this.streaming = true;
      return current;
    }
    if (type === 'turn/end') {
      this.streaming = false;
      return current;
    }
    if (type === 'session/title') {
      const title = data['title'];
      if (title !== undefined && title !== null) {
        this.currentTitle = String(title);
      }
      return current;
    }
    return current;
  }

  /** 内容块里的 `reasoning` 块拼成思维链正文（与 blocksToText 同一约定：只认文本块）。 */
  private blocksToReasoning(blocks: Array<Record<string, Object>>): string {
    if (blocks === undefined || blocks === null) {
      return '';
    }
    let text: string = '';
    for (let i = 0; i < blocks.length; i++) {
      const block: Record<string, Object> = blocks[i];
      if (block === undefined || block === null) {
        continue;
      }
      if (String(block['type']) === 'reasoning') {
        const t = block['text'];
        if (t !== undefined && t !== null) {
          text += String(t);
        }
      }
    }
    return text;
  }

  private blocksToText(blocks: Array<Record<string, Object>>): string {
    if (blocks === undefined || blocks === null) {
      return '';
    }
    let text: string = '';
    for (let i = 0; i < blocks.length; i++) {
      const block: Record<string, Object> = blocks[i];
      if (block === undefined || block === null) {
        continue;
      }
      if (String(block['type']) === 'text') {
        const t = block['text'];
        if (t !== undefined && t !== null) {
          text += String(t);
        }
      }
    }
    return text;
  }

  /**
   * 正文滚到底。**只在「跟随中」才抢滚动**：读者主动往上翻过之后（ChatView 的
   * onDidScroll 会把 atEnd=false 报上来）就不再把人拽回底部，改由右下角「回到底部」按钮接手。
   * @param force - 忽略跟随开关（发消息 / 切会话这种「本来就要看最新」的时刻）
   */
  private scrollToBottom(force: boolean = false): void {
    if (force) {
      this.followBottom = true;
    }
    if (!this.followBottom) {
      return;
    }
    setTimeout(() => {
      if (!this.followBottom) {
        return;
      }
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (e) {
        // 列表尚未挂载（hero 相位 / 切会话瞬间）：无需滚动
      }
    }, 50);
  }

  // —— 桌面壳层 ——

  /** 载入壳契约、语言、设备偏好与更新调度（与上游壳启动时的职责一致）。 */
  private setupDesktopShell(): void {
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) {
      return;
    }
    this.shell = DesktopShellContract.load(host.resourceManager);
    this.desktopCopy = DesktopCopy.forLanguage(i18n.System.getSystemLanguage());
    this.prefs = new DesktopPrefs(host);
    this.workspaceDirectory = this.prefs.getString(DesktopPrefKeys.WORKSPACE_DIRECTORY, '');
    this.appVersion = this.bundleVersion();
    this.updates = new DesktopUpdateService(this.shell, this.prefs, () => {
      this.syncUpdateState();
    });
    // 上游壳启动即开始轮询；这里同样在过期时开始（最后一次成功检查超过一个间隔才算过期）。
    this.updates.startIfDue();
    host.eventHub.on(DESKTOP_QUIT_REQUEST, () => {
      this.quitVisible = true;
    });
    // 外观跟随系统时，系统深浅色一变就重算令牌
    host.eventHub.on(DESKTOP_CONFIG_CHANGED, () => {
      this.applyAppearance();
    });
    // 窗口装饰状态：系统标题栏没能藏掉时，隐藏自绘品牌标（避免同一枚 logo 出现两次）
    host.eventHub.on(DESKTOP_CHROME_CHANGED, (decorVisible: boolean) => {
      this.systemDecorVisible = decorVisible === true;
    });
    // 通知 Ability：页面已就绪，关闭窗口时可以先弹确认
    host.eventHub.emit(DESKTOP_PAGE_READY);
    // 标题栏三键（自绘）需要知道窗口是否已最大化
    this.bindWindowStatus(host);
  }

  /** 应用版本（对应上游关于面板的 applicationVersion，取自包信息）。 */
  private bundleVersion(): string {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (e) {
      return '1.0.0';
    }
  }

  /** 当前展开的菜单（无则返回空菜单，UI 不会空指针）。 */
  private activeMenu(): MenuSpec {
    const found: MenuSpec | null = this.shell.menu(this.openMenuId);
    return found === null ? new MenuSpec('', '') : found;
  }

  /** 契约里的键名（用于真实的快捷键注册；空则回落到 W，保证注册一定成立）。 */
  private shortcutKey(id: string): string {
    const spec = this.shell.shortcut(id);
    if (spec === null || spec.key.length === 0) {
      return 'W';
    }
    return spec.key;
  }

  /** 菜单分发：与上游 applicationItems/fileMenu 的动作一一对应。 */
  private handleMenuAction(itemId: string): void {
    this.openMenuId = '';
    if (itemId === 'about') {
      this.aboutVisible = true;
      return;
    }
    if (itemId === 'checkUpdates') {
      this.checkUpdates();
      return;
    }
    if (itemId === 'quit') {
      this.quitVisible = true;
      return;
    }
    if (itemId === 'reloadPage') {
      this.reloadView();
      return;
    }
    if (itemId === 'toggleFullscreen') {
      this.toggleFullscreen();
      return;
    }
    if (itemId === 'openDownloadPage') {
      this.openDownloadPage();
      return;
    }
    if (itemId === 'pickDirectory') {
      this.pickWorkspaceDirectory();
      return;
    }
    if (itemId === 'restartAppHost') {
      // 鸿蒙端 dsh 服务由终端/HNP 侧启动，壳无权重启 → 明说，不假装成功。
      this.toast('请在终端重启 dsh 服务后重新连接（dsh 不在应用进程内）');
      return;
    }
    if (itemId === 'hideApplication') {
      this.minimizeWindow();
      return;
    }
    if (itemId === 'hideOtherApplications' || itemId === 'showAllApplications') {
      this.minimizeWindow();
      return;
    }
    // 编辑类条目：鸿蒙文本组件自管编辑历史，壳无法注入按键（上游是 sendEditingKey）。
    this.toast('请在输入框内使用系统快捷键完成「' + itemId + '」');
  }

  /** 检查更新：立刻显示「检查中」，完成后按状态机刷新文案。 */
  private checkUpdates(): void {
    this.updateVisible = true;
    const service: DesktopUpdateService | null = this.updates;
    if (service === null) {
      this.updatePhase = DesktopUpdatePhase.ERROR;
      this.updateTitle = this.desktopCopy.updateCheckFailedTitle;
      this.updateMessage = this.desktopCopy.updateCheckFailed;
      return;
    }
    this.updateTitle = this.desktopCopy.updateCheckTitle;
    this.updateMessage = this.desktopCopy.updateChecking;
    service.checkNow().then(() => {
      this.syncUpdateState();
    }).catch(() => {
      this.syncUpdateState();
    });
    this.syncUpdateState();
  }

  /** 把服务状态投影成面板文案（与上游 update-presentation 的职责一致）。 */
  private syncUpdateState(): void {
    const service: DesktopUpdateService | null = this.updates;
    if (service === null) {
      return;
    }
    const phase: string = service.phase();
    this.updatePhase = phase;
    const baseline: string = service.baselineVersion();
    if (phase === DesktopUpdatePhase.AVAILABLE) {
      this.updateTitle = this.desktopCopy.updateAvailable;
      this.updateMessage = '上游已发布 V' + service.latestVersion() + '（本适配基线 V' + baseline + '）';
      this.updateDetail = '鸿蒙端暂不支持应用内安装（Electron 更新包不可用），请前往官网下载或等待本仓库适配更新。';
    } else if (phase === DesktopUpdatePhase.CURRENT) {
      this.updateTitle = this.desktopCopy.updateCheckTitle;
      this.updateMessage = DesktopCopy.placeholder(this.desktopCopy.updateCurrent, 'version', baseline);
      this.updateDetail = '';
    } else if (phase === DesktopUpdatePhase.ERROR) {
      this.updateTitle = this.desktopCopy.updateCheckFailedTitle;
      this.updateMessage = service.lastFailureKind() === 'check-network'
        ? this.desktopCopy.updateCheckNetworkFailed : this.desktopCopy.updateCheckFailed;
      this.updateDetail = '';
    } else if (phase === DesktopUpdatePhase.CHECKING) {
      this.updateTitle = this.desktopCopy.updateCheckTitle;
      this.updateMessage = this.desktopCopy.updateChecking;
      this.updateDetail = '';
    } else {
      this.updateTitle = this.desktopCopy.updateCheckTitle;
      this.updateMessage = DesktopCopy.placeholder(this.desktopCopy.updateCurrent, 'version', baseline);
      this.updateDetail = '';
    }
  }

  /** 技术详情：只放可核对的事实，不放凭据（对齐上游「主进程诊断」的克制）。 */
  private updateTechnical(): string {
    const service: DesktopUpdateService | null = this.updates;
    if (service === null) {
      return '';
    }
    const lines: string[] = [];
    lines.push('清单：' + service.manifestUrl());
    lines.push('适配基线：V' + service.baselineVersion());
    const latest: string = service.latestVersion();
    if (latest.length > 0) {
      lines.push('上游最新：V' + latest);
    }
    const last: number = service.lastCheckTime();
    if (last > 0) {
      lines.push('上次成功检查：' + new Date(last).toISOString());
    }
    const failure: string = service.lastFailureMessage();
    if (failure.length > 0) {
      lines.push('失败原因：' + failure);
    }
    return lines.join('\n');
  }

  /** 关闭决定：交给 Ability 决定是否真的退出（对应上游 quit-confirmation 的确认路径）。 */
  private decideQuit(allow: boolean): void {
    this.quitVisible = false;
    if (!allow) {
      return;
    }
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) {
      return;
    }
    host.eventHub.emit(DESKTOP_QUIT_DECISION, true);
  }

  /** 退出确认正文：有任务在跑就说会中断（与上游 inspectQuit 的两种文案对应）。 */
  private quitBody(): string {
    return this.streaming ? this.desktopCopy.quitActiveTasks : this.desktopCopy.quitScheduledTasks;
  }

  /** 刷新页面：重新建立连接并重载会话（上游 role: 'reload' 的鸿蒙等价物）。 */
  private reloadView(): void {
    if (this.mode === 'dsh') {
      this.connect();
      this.toast('已重新连接 dsh 服务');
    } else {
      this.toast('直连模式无需刷新');
    }
  }

  /**
   * 最大化 / 还原切换（上游 Windows 标题栏该键由系统绘制，鸿蒙端自绘）。
   * 官方《自由窗口下如何自定义窗口标题栏》给的写法就是 `maximize()` / `recover()`，
   * 而不是 `setWindowLayoutFullScreen()`（后者只改内容布局，不改变窗口状态，
   * 点了会让人以为「回不到小窗口」）。
   */
  private toggleFullscreen(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined || context === null) {
      return;
    }
    window.getLastWindow(context).then((mainWindow: window.Window) => {
      if (this.windowMaximized) {
        mainWindow.recover().catch((error: BusinessError) => {
          this.toast('还原窗口失败：' + error.message);
        });
        return;
      }
      // 最大化时禁止系统标题栏随光标 hover 弹出来盖住自绘标题栏（API 20 起）
      if (deviceInfo.sdkApiVersion >= 20) {
        mainWindow.setTitleAndDockHoverShown(false, true).catch(() => {
        });
      }
      mainWindow.maximize().catch((error: BusinessError) => {
        this.toast('最大化失败：' + error.message);
      });
    }).catch((error: BusinessError) => {
      this.toast('无法获取窗口：' + error.message);
    });
  }

  /** 订阅窗口状态：最大化/还原后标题栏键位与字形要跟着变（也用于几何落盘时跳过铺满状态）。 */
  private bindWindowStatus(host: common.Context): void {
    window.getLastWindow(host).then((mainWindow: window.Window) => {
      const sync = (status: window.WindowStatusType): void => {
        this.windowMaximized = status === window.WindowStatusType.MAXIMIZE
          || status === window.WindowStatusType.FULL_SCREEN;
      };
      try {
        sync(mainWindow.getWindowStatus());
      } catch (e) {
        hilog.warn(0x0000, 'DshIndex', 'getWindowStatus failed: %{public}s', String(e));
      }
      mainWindow.on('windowStatusChange', sync);
    }).catch(() => {
    });
  }

  /** 最小化窗口（上游「隐藏应用」的鸿蒙等价物：没有托盘，最小化就是「退到后台」）。 */
  private minimizeWindow(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined || context === null) {
      return;
    }
    window.getLastWindow(context).then((mainWindow: window.Window) => {
      mainWindow.minimize().catch((error: BusinessError) => {
        this.toast('最小化失败：' + error.message);
      });
    }).catch((error: BusinessError) => {
      this.toast('无法获取窗口：' + error.message);
    });
  }

  /** 打开下载页（上游「前往官网下载」的鸿蒙等价物：交给系统浏览器）。 */
  private openDownloadPage(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined || context === null) {
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: this.shell.update.downloadPage
    };
    context.startAbility(want).catch((error: BusinessError) => {
      this.toast('无法打开浏览器：' + error.message);
    });
  }

  /** 选择工作目录（上游 directory-picker 的鸿蒙等价物）。 */
  private pickWorkspaceDirectory(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context === undefined || context === null) {
      return;
    }
    DesktopDirectoryPicker.pick(context).then((result) => {
      if (result.error.length > 0) {
        this.toast(this.desktopCopy.pickDirectoryFailed + ' ' + result.error);
        return;
      }
      if (result.canceled) {
        return;
      }
      this.workspaceDirectory = result.path;
      const prefs: DesktopPrefs | null = this.prefs;
      if (prefs !== null) {
        prefs.putString(DesktopPrefKeys.WORKSPACE_DIRECTORY, result.path);
      }
      this.toast('工作目录已设为：' + result.path);
    });
  }

  private toast(message: string): void {
    // showToast 会抛异常（窗口未就绪等），提示失败不该影响交互
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
    } catch (e) {
      hilog.warn(0x0000, 'DshIndex', 'toast failed: %{public}s', String(e));
    }
  }

  // —— UI ——

  /** 侧栏是否折叠：手动覆盖优先，否则按上游 1024 断点自动收起。 */
  private sidebarCollapsed(): boolean {
    if (this.sidebarOverride >= 0) {
      return this.sidebarOverride === 1;
    }
    return this.windowWidth < Theme.SIDEBAR_AUTO_COLLAPSE;
  }

  /** --dsh-chat-content-width 的求解输入：会话主列实际宽度。 */
  private chatColumnWidth(): number {
    return Math.max(320, this.windowWidth - (this.sidebarCollapsed() ? Theme.SIDEBAR_COLLAPSED : Theme.SIDEBAR_DEFAULT));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // 桌面壳：Windows 形态标题栏（40px / 左侧菜单 / 右侧窗口按钮），与上游 preload-menu 同一套几何
        DesktopMenuBar({
          menus: this.shell.menus,
          shortcuts: this.shell.shortcuts,
          messages: this.desktopCopy,
          openMenuId: this.openMenuId,
          menuStart: this.sidebarCollapsed() ? Theme.WINDOWS_MENU_START_COLLAPSED : Theme.WINDOWS_MENU_START,
          collapsed: this.sidebarCollapsed(),
          maximized: this.windowMaximized,
          onToggleSidebar: () => {
            this.sidebarOverride = this.sidebarCollapsed() ? 0 : 1;
          },
          onNewSession: () => {
            this.newSession();
          },
          onMenuMeasure: (menuId: string, x: number) => {
            this.menuAnchors.set(menuId, x);
          },
          onMinimize: () => {
            this.minimizeWindow();
          },
          onToggleMaximize: () => {
            this.toggleFullscreen();
          },
          onClose: () => {
            this.quitVisible = true;
          },
          onToggle: (menuId: string) => {
            if (this.openMenuId === menuId) {
              this.openMenuId = '';
              return;
            }
            const measured: number | undefined = this.menuAnchors.get(menuId);
            this.menuAnchorX = measured === undefined ? 8 : measured;
            this.openMenuId = menuId;
          }
        })

        // 三栏骨架（AppFrame）：侧栏 + 会话主列；Windows 形态下主列带 16px 左上圆角并自带底色
        Row() {
          Sidebar({
            sessions: $sessions,
            currentSessionId: this.currentSessionId,
            connected: this.connected,
            collapsed: this.sidebarCollapsed(),
            // 系统标题栏仍可见（隐藏失败）时不再自绘品牌标：同一枚 logo 只出现一次
            hideBrand: this.systemDecorVisible,
            workspaceName: this.workspaceName(),
            onSelect: (id: string) => { this.selectSession(id); },
            onNew: () => { this.newSession(); },
            onSettings: () => {
              this.showSettings = true;
              this.loadPresets();
            },
            onToggle: () => {
              this.sidebarOverride = this.sidebarCollapsed() ? 0 : 1;
            }
          })

          Column() {
            ChatView({
              title: this.currentTitle,
              messages: $messages,
              streaming: this.streaming,
              connected: this.connected,
              directMode: this.mode === 'direct',
              modelLabel: this.modelLabel(),
              presetLabel: this.presetLabel(),
              workspaceName: this.workspaceLabel(),
              workspacePath: this.currentWorkspacePath(),
              statusText: this.statusText,
              columnWidth: this.chatColumnWidth(),
              scroller: this.scroller,
              onFollowState: (atEnd: boolean) => { this.followBottom = atEnd; },
              workspaceOptions: this.workspaceOptions,
              workspaceAvailable: this.workspaceAvailable(),
              workspaceReason: this.workspaceReason(),
              presetIds: this.presetIds,
              presetNames: this.presetNames,
              presetDescription: this.presetDescription(),
              presetLocked: this.presetLocked(),
              modelKeys: this.modelKeys,
              modelKey: this.currentModelKey,
              hint: this.heroHint(),
              permissionOptions: this.permissionOptions,
              permissionLabel: this.currentPermission,
              permissionReason: this.permissionReason(),
              permissionEnabled: this.permissionEnabled(),
              onSend: (text: string) => { this.sendMessage(text); },
              onStop: () => { this.stopGeneration(); },
              onPickModel: (key: string) => { this.pickModel(key); },
              onOpenModelSettings: () => {
                this.showSettings = true;
                this.loadPresets();
              },
              onCopy: (text: string) => { this.copyToClipboard(text); },
              onOpenWorkspace: () => { this.pickWorkspaceDirectory(); },
              onPickWorkspace: (path: string) => { this.pickWorkspace(path); },
              onPickPreset: (preset: string) => { this.pickPreset(preset); },
              onPickPermission: (preset: string) => { this.pickPermission(preset); },
              onSwitchToDsh: () => { this.switchToDshMode(); }
            })
          }
          .layoutWeight(1)
          .height('100%')
          .backgroundColor(Theme.palette(this.dark).dswAliasBgBase)
          .borderRadius({ topLeft: Theme.WINDOWS_CONTENT_RADIUS })
          .clip(true)
        }
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.openMenuId = '';
        })
      }
      .width('100%')
      .height('100%')
      // Windows 形态：标题栏与侧栏同底（--dsw-specific-sidebar-fill）
      .backgroundColor(Theme.palette(this.dark).dswSpecificSidebarFill)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        const raw: Length | undefined = newArea.width;
        if (raw === undefined) {
          return;
        }
        const width: number = Number(raw.toString());
        if (Number.isFinite(width) && width > 0) {
          this.windowWidth = width;
        }
      })

      // 菜单下拉层：点击空白处关闭
      if (this.openMenuId !== '') {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.01)')
          .position({ x: 0, y: DESKTOP_MENUBAR_HEIGHT })
          .onClick(() => {
            this.openMenuId = '';
          })
        Column() {
          DesktopMenuDropdown({
            menu: this.activeMenu(),
            shortcuts: this.shell.shortcuts,
            messages: this.desktopCopy,
            onAction: (itemId: string) => {
              this.handleMenuAction(itemId);
            }
          })
        }
        .alignItems(HorizontalAlign.Start)
        .position({ x: this.menuAnchorX, y: DESKTOP_MENUBAR_HEIGHT })
      }

      // 设置：上游为 800x800 居中面板 + bg-mask-1 遮罩（不再用系统半模态弹窗）
      if (this.showSettings) {
        Column() {
          SettingsPanel({
            serverUrl: this.serverUrl,
            connected: this.connected,
            statusText: this.statusText,
            presetIds: this.presetIds,
            currentPreset: this.currentPreset,
            client: this.client,
            mode: this.mode,
            directApiKey: this.directApiKey,
            directModel: this.directModel,
            directModels: this.directModels,
            directBaseUrl: this.directBaseUrl,
            appearance: this.appearance,
            contentFontSize: this.contentFontSize,
            appVersion: this.appVersion,
            baselineVersion: this.shell.upstream.appVersion,
            onModeChange: (m: string) => {
              if (this.mode === 'direct' && m !== 'direct') {
                this.syncDirectCurrent();
              }
              this.mode = m;
              this.saveMode(m);
              if (m === 'dsh') {
                this.deepseek.stop();
                this.messages = [];
                this.currentTitle = '';
              }
              this.applyMode();
            },
            onSaveDirect: (key: string, model: string, baseUrl: string) => {
              this.directApiKey = key;
              this.directModel = model;
              this.directBaseUrl = baseUrl;
              this.deepseek.setEndpoint(baseUrl);
              this.syncDirectModelKeys();
              this.saveDirectConfig();
            },
            onSave: (url: string) => {
              this.serverUrl = url;
              this.saveServerUrl();
              this.connect();
            },
            onPresetSelect: (preset: string) => {
              this.currentPreset = preset;
              this.saveAgentPreset(preset);
            },
            onAppearanceChange: (value: string) => {
              this.saveAppearance(value);
            },
            onFontSizeChange: (size: number) => {
              this.saveContentFontSize(size);
            },
            onClose: () => {
              this.showSettings = false;
            }
          })
          .height('100%')
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(24)
        .backgroundColor(Theme.palette(this.dark).dswAliasBgMask1)
        .onClick(() => {
          this.showSettings = false;
        })
      }

      // 关于面板（上游 about-panel 的鸿蒙自绘版）
      if (this.aboutVisible) {
        Column() {
          DesktopAboutPanel({
            productName: this.desktopCopy.aboutProduct,
            versionLabel: DesktopCopy.placeholder(this.desktopCopy.aboutVersion, 'version', this.appVersion),
            appVersion: this.appVersion,
            baselineVersion: this.shell.upstream.appVersion,
            upstreamCommit: this.shell.upstream.commit,
            hostProtocolVersion: this.shell.upstream.hostProtocolVersion,
            contractSource: this.shell.loadError.length > 0
              ? ('内置默认值（契约读取失败：' + this.shell.loadError + '）')
              : ('rawfile/' + DesktopShellContract.RAWFILE + ' @ ' + this.shell.upstream.branch),
            messages: this.desktopCopy,
            onClose: () => {
              this.aboutVisible = false;
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Theme.palette(this.dark).dswAliasBgMask3)
      }

      // 退出确认（上游 quit-confirmation：区分「任务中断」与「定时任务不跑」）
      if (this.quitVisible) {
        Column() {
          DesktopQuitConfirmPanel({
            title: this.desktopCopy.quitTitle,
            body: this.quitBody(),
            confirmLabel: this.desktopCopy.quit,
            cancelLabel: this.desktopCopy.cancel,
            onCancel: () => {
              this.quitVisible = false;
            },
            onConfirm: () => {
              this.decideQuit(true);
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Theme.palette(this.dark).dswAliasBgMask3)
      }

      // 权限风险确认（上游 RiskConfirmation：完全权限 / Auto review 先勾选再启用）
      if (this.permissionRiskVisible) {
        Column() {
          DesktopPermissionRiskPanel({
            title: this.permissionRiskTitle,
            body: this.permissionRiskBody,
            acknowledgeLabel: Constants.PERMISSION_ACK,
            confirmLabel: this.permissionRiskConfirm,
            cancelLabel: Constants.PERMISSION_CANCEL,
            acknowledged: this.permissionRiskAck,
            onAcknowledge: (value: boolean) => {
              this.permissionRiskAck = value;
            },
            onCancel: () => {
              this.permissionRiskVisible = false;
              this.permissionRiskAck = false;
            },
            onConfirm: () => {
              const preset: string = this.permissionRiskValue;
              this.permissionRiskVisible = false;
              this.permissionRiskAck = false;
              this.commitPermission(preset);
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Theme.palette(this.dark).dswAliasBgMask3)
      }

      // 更新面板（上游 update-dialog：同一套状态机文案）
      if (this.updateVisible) {
        Column() {
          DesktopUpdatePanel({
            title: this.updateTitle,
            message: this.updateMessage,
            detail: this.updateDetail,
            technical: this.updateTechnical(),
            showTechnical: this.showUpdateTechnical,
            busy: this.updatePhase === DesktopUpdatePhase.CHECKING,
            canDownload: this.updatePhase === DesktopUpdatePhase.AVAILABLE,
            downloadLabel: this.updatePhase === DesktopUpdatePhase.AVAILABLE
              ? this.desktopCopy.updateDownload : this.desktopCopy.updateCheckTitle,
            closeLabel: this.desktopCopy.updateLater,
            onCheck: () => {
              this.checkUpdates();
            },
            onDownload: () => {
              this.openDownloadPage();
            },
            onToggleTechnical: () => {
              this.showUpdateTechnical = !this.showUpdateTechnical;
            },
            onClose: () => {
              this.updateVisible = false;
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Theme.palette(this.dark).dswAliasBgMask3)
      }
    }
    .width('100%')
    .height('100%')
    // 壳层快捷键：定义来自 desktop-shell.json（菜单提示与真实注册共用一份）
    .keyboardShortcut(this.shortcutKey('closePage'), [ModifierKey.CTRL], () => {
      this.quitVisible = true;
    })
    .keyboardShortcut(this.shortcutKey('reloadPage'), [ModifierKey.CTRL], () => {
      this.reloadView();
    })
    // 功能键必须走 FunctionKey 枚举（ArkUI 限制）；契约里的 'F11' 用于菜单提示
    .keyboardShortcut(FunctionKey.F11, [], () => {
      this.toggleFullscreen();
    })
  }

  /**
   * 模型标签（输入行右侧胶囊）：独立模式 = 本机模型；dsh 模式 = 当前会话的模型
   * （modelSelection 投影）→ 服务端目录默认项 → 占位。**不再拿对话模式冒充模型**：
   * 模式有自己的胶囊（在工具排里），这里只讲模型。
   */
  private modelLabel(): string {
    if (this.mode === 'direct') {
      return this.directModel;
    }
    const session: DshSession | null = this.currentSession();
    if (session !== null && session.model.length > 0) {
      return session.model;
    }
    if (this.catalogDefaultModel.length > 0) {
      const parts: string[] = this.catalogDefaultModel.split('/');
      return parts.length > 1 ? parts[1] : this.catalogDefaultModel;
    }
    return '选择模型';
  }

  /** 模型胶囊：选中一个模型（独立模式改本地配置；dsh 模式走 session/selectModel）。 */
  private pickModel(key: string): void {
    if (this.mode === 'direct') {
      this.directModel = key;
      this.currentModelKey = key;
      this.saveDirectConfig();
      this.toast('模型已设为：' + key);
      return;
    }
    const parts: string[] = key.split('/');
    if (parts.length < 2) {
      return;
    }
    const client = this.client;
    if (client === null || this.currentSessionId.length === 0) {
      this.toast('请先选中一个会话再切换模型');
      return;
    }
    const previous: string = this.currentModelKey;
    this.currentModelKey = key;
    client.selectModel(this.currentSessionId, parts[0], parts[1], '').then(() => {
      this.toast('模型已切换：' + parts[0] + ' / ' + parts[1]);
      this.refreshSessions();
    }).catch((e: BusinessError) => {
      this.currentModelKey = previous;
      this.toast('切换模型失败：' + String(e));
    });
  }

  /** 工作区胶囊是否可点：只有 dsh 服务模式才有会话工作区。 */
  private workspaceAvailable(): boolean {
    return this.mode !== 'direct' && this.connected;
  }

  /** 工作区胶囊不可用的原因。 */
  private workspaceReason(): string {
    if (this.mode === 'direct') {
      return '独立模式不绑定 dsh 工作区（想给 AI 指定目录请切到 dsh 服务模式）';
    }
    return '未连接 dsh 服务：先在设置里确认服务地址';
  }

  /**
   * 卡下提示（hero 相位）：把「为什么发不出去」说清楚。
   * 独立模式缺 API Key / dsh 模式没连上，各给一句能照做的指引。
   */
  private heroHint(): string {
    if (this.mode === 'direct') {
      if (this.directApiKey.length === 0) {
        return '独立模式：设置 →「模型与连接」填 API Key 即可开聊；对话模式已随包内置，不需要部署服务。';
      }
      return '';
    }
    if (!this.connected) {
      return 'dsh 服务模式未连接：设置 →「模型与连接」确认服务地址（默认 http://127.0.0.1:3080），'
        + '或在鸿蒙终端运行 sh ~/bin/dsh-web.sh。';
    }
    return '';
  }

  /** 工作区标签：选过目录显示目录名，否则显示应用名（上游工作区胶囊）。 */
  private workspaceName(): string {
    const dir: string = this.workspaceDirectory;
    if (dir.length === 0) {
      return Constants.APP_NAME;
    }
    return Index.basename(dir);
  }

  /**
   * 首页工作区胶囊的标签（上游 EmptyHero 的 workspaceLabel）：
   * 手选目录优先，其次当前会话的 cwd；都没有 → 空串，由 Chip 显示「选择工作区」占位。
   */
  private workspaceLabel(): string {
    if (this.workspaceDirectory.length > 0) {
      return Index.basename(this.workspaceDirectory);
    }
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].sessionId === this.currentSessionId && this.sessions[i].cwd.length > 0) {
        return Index.basename(this.sessions[i].cwd);
      }
    }
    return '';
  }

  /** 当前生效的工作区路径（手选目录优先，其次当前会话 cwd） */
  private currentWorkspacePath(): string {
    if (this.workspaceDirectory.length > 0) {
      return this.workspaceDirectory;
    }
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].sessionId === this.currentSessionId) {
        return this.sessions[i].cwd;
      }
    }
    return '';
  }

  /** 路径末段（工作区胶囊显示的目录名） */
  private static basename(dir: string): string {
    const parts: string[] = dir.split('/');
    for (let i = parts.length - 1; i >= 0; i--) {
      if (parts[i].length > 0) {
        return parts[i];
      }
    }
    return dir;
  }

  /** 复制到剪贴板（消息动作排，对应上游 MessageIconActions 的复制）。 */
  private copyToClipboard(text: string): void {
    if (text.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.toast('已复制');
      }).catch(() => {
      });
    } catch (e) {
      // 剪贴板不可用时静默失败（不打断会话）
    }
  }
}
