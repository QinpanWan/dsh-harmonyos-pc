/**
 * Theme：桌面端主题门面。
 *
 * 颜色令牌**全部**来自上游开源的 `packages/client/ui-theme/src/styles/design-platform.css`
 * （见 common/Tokens.ets，由 scripts/gen-harmony-ui-assets.mjs 生成）；
 * 尺寸/节奏常量逐条对应上游 `ui-theme/src/styles/base.css`、`apps/desktop/src/windows-layout.ts`
 * 与各组件的 module.css，命名保持同源，禁止在此发明新的视觉值。
 *
 * 深浅色与上游一致：跟随系统，或由「设置 → 外观」显式指定。
 */
import { DARK, LIGHT, Palette } from './Tokens';

export { Palette };

/** 外观偏好（与上游 ui-theme 的设置项一致）。 */
export class Appearance {
  static readonly SYSTEM: string = 'system';
  static readonly LIGHT: string = 'light';
  static readonly DARK: string = 'dark';
}

/** AppStorage 键：跨组件订阅深浅色，避免逐层传参。 */
export const KEY_DARK_THEME: string = 'dshDarkTheme';
/** AppStorage 键：会话正文档位（12–17，默认 14）。 */
export const KEY_CONTENT_FONT_SIZE: string = 'dshContentFontSize';

export class Theme {
  /** 当前是否深色（由 AppStorage 写入）。 */
  static isDark(): boolean {
    const value: boolean | undefined = AppStorage.get<boolean>(KEY_DARK_THEME);
    return value === undefined ? true : value;
  }

  /**
   * 当前生效的令牌表。
   * @param dark - 组件订阅到的 @StorageProp 值（务必传 `this.dark`）。
   *   ArkUI 只有在渲染过程中「读到」观察变量才会登记依赖，直接读 AppStorage
   *   不会建立依赖，外观/字号切换时组件不会重建。
   */
  static palette(dark?: boolean): Palette {
    const isDark: boolean = dark === undefined ? Theme.isDark() : dark;
    return isDark ? DARK : LIGHT;
  }

  /** 会话正文档位（上游 12–17，默认 14）。 */
  static contentFontSize(): number {
    const value: number | undefined = AppStorage.get<number>(KEY_CONTENT_FONT_SIZE);
    return value === undefined ? 14 : value;
  }

  /** --dsh-content-font-delta = 档位 − 14。 */
  static fontDelta(): number {
    return Theme.contentFontSize() - 14;
  }

  /** --dsh-content-font-size-secondary：≤14 时 −1，>14 时 −2。 */
  static secondaryFontSize(): number {
    const base: number = Theme.contentFontSize();
    return base - (base > 14 ? 2 : 1);
  }

  /** --dsh-content-font-delta-secondary。 */
  static secondaryDelta(): number {
    return Theme.secondaryFontSize() - 13;
  }

  // —— 圆角（base.css --dsw-radius-*）——
  static readonly RADIUS_XS: number = 4;
  static readonly RADIUS_SM: number = 8;
  static readonly RADIUS_MD: number = 12;
  static readonly RADIUS_LG: number = 16;
  static readonly RADIUS_XL: number = 20;
  static readonly RADIUS_PANEL: number = 28;
  /** 窗口内容区左上角圆角（AppFrame --dsh-windows-content-radius）。 */
  static readonly WINDOWS_CONTENT_RADIUS: number = 16;

  // —— 桌面窗口几何（apps/desktop/src/windows-layout.ts）——
  static readonly WINDOWS_TITLEBAR_HEIGHT: number = 40;
  /** 标题栏菜单起始 x（--dsh-windows-menu-start）。 */
  static readonly WINDOWS_MENU_START: number = 48;
  static readonly WINDOWS_MENU_START_COLLAPSED: number = 84;
  /** 标题栏菜单项（preload-menu.ts：28 高 / 内边距 10 / 圆角 6 / 14px）。 */
  static readonly CAPTION_MENU_HEIGHT: number = 28;
  static readonly CAPTION_MENU_PADDING: number = 10;
  static readonly CAPTION_MENU_RADIUS: number = 6;

  // —— 三栏骨架（ui-layout/src/client/columns.ts）——
  static readonly SIDEBAR_DEFAULT: number = 280;
  static readonly SIDEBAR_MIN: number = 264;
  static readonly SIDEBAR_MAX: number = 420;
  static readonly SIDEBAR_COLLAPSED: number = 56;
  static readonly SIDEBAR_AUTO_COLLAPSE: number = 1024;
  /** 侧栏内边距（SidebarRoot --dsh-sidebar-inline-padding）。 */
  static readonly SIDEBAR_INLINE_PADDING: number = 12;
  /** 栏内 36x36 控制盒。 */
  static readonly CONTROL_BOX: number = 36;

  // —— 侧栏各排（SidebarRoot.module.css）——
  static readonly BRAND_ROW_HEIGHT: number = 60;
  static readonly BRAND_ROW_COLLAPSED: number = 36;
  /**
   * 品牌鲸鱼宽度 / 字标高度。
   * 上游 SidebarRoot 的 `sidebar.brand.mark` 给的是 size 24、BrandWordmark 默认 24；
   * 鸿蒙端按主人反馈「左上角 logo 比较小」放大到 30（同一套官方字形，仅尺寸不同）。
   * 尺寸依据：品牌排高 40（= 标题栏高），30 高的字标留 10 的上下留白；
   * 宽度 30(鲸鱼) + 8(间距 SidebarRoot .brandIdentity gap) + 195(字标 30*156/24) = 233，
   * 加品牌身份左内边距 4 = 237，仍在侧栏可用宽 252 之内（再大到 32 就正好贴边，故上限 32）。
   */
  static readonly BRAND_MARK_SIZE: number = 30;
  static readonly BRAND_NAME_HEIGHT: number = 30;
  static readonly NEW_SESSION_HEIGHT: number = 38;
  static readonly PANEL_ROW_MIN_HEIGHT: number = 36;
  /** 设置入口（SettingsRoot .trigger：42 高）。 */
  static readonly SETTINGS_TRIGGER_HEIGHT: number = 42;

  // —— 会话头（ConversationRoot.module.css .header / .titleRow）——
  static readonly HEADER_MIN_HEIGHT: number = 76;
  static readonly HEADER_PADDING_TOP: number = 10;
  static readonly HEADER_PADDING_LEFT: number = 20;
  static readonly HEADER_PADDING_RIGHT: number = 28;
  static readonly HEADER_PADDING_BOTTOM: number = 10;
  static readonly TITLE_ROW_HEIGHT: number = 30;
  static readonly TITLE_GAP: number = 10;
  static readonly TITLE_FONT_SIZE: number = 14;

  // —— 会话正文与输入卡（ConversationRoot / ChatView / InputBar）——
  static readonly CHAT_CONTENT_MIN: number = 680;
  static readonly CHAT_CONTENT_MAX: number = 920;
  static readonly CHAT_CONTENT_RATIO: number = 0.64;
  static readonly CHAT_FLOW_GAP: number = 16;
  static readonly COMPOSER_SIDE_CLEARANCE: number = 16;
  static readonly COMPOSER_CARD_EXTRA: number = 32;
  static readonly COMPOSER_TEXT_MAX_HEIGHT: number = 336;
  static readonly COMPOSER_DOCK_INSET: number = 8;
  static readonly COMPOSER_PADDING_TOP: number = 8;
  static readonly COMPOSER_ROW_PADDING_TOP: number = 2;
  static readonly COMPOSER_ROW_PADDING_SIDE: number = 8;
  static readonly COMPOSER_ROW_PADDING_BOTTOM: number = 6;
  static readonly COMPOSER_INPUT_PADDING_LEFT: number = 14;
  static readonly COMPOSER_INPUT_PADDING_RIGHT: number = 8;
  static readonly COMPOSER_INPUT_PADDING_TOP: number = 4;
  /** 停靠态草稿最小高度（一行 24 + 上 4 + 下 8）；hero 态 52。 */
  static readonly COMPOSER_INPUT_MIN_HEIGHT: number = 36;
  static readonly COMPOSER_HERO_INPUT_MIN_HEIGHT: number = 52;
  /** 附加按钮（+）：28 圆；发送按钮：34 圆。 */
  static readonly COMPOSER_ADD_SIZE: number = 28;
  static readonly COMPOSER_SEND_SIZE: number = 34;
  /** 选择器胶囊（Plan / 模型 / 只读）：28 高、圆角 8。 */
  static readonly COMPOSER_SELECT_HEIGHT: number = 28;
  static readonly COMPOSER_SELECT_ARROW: number = 20;
  static readonly COMPOSER_SELECT_MAX_WIDTH: number = 220;

  // —— 会话流（ui-chat MessageItem / ChatView）——
  static readonly BUBBLE_PADDING_V: number = 10;
  static readonly BUBBLE_PADDING_H: number = 16;
  static readonly BUBBLE_MAX_RATIO: number = 0.702;
  static readonly CHAT_SCROLL_PADDING: number = 16;
  static readonly TO_BOTTOM_SIZE: number = 34;
  static readonly ACTIONS_HEIGHT: number = 28;

  // —— 会话行（ui-workspace/rows Rows.module.css）——
  static readonly SESSION_ROW_HEIGHT: number = 32;
  static readonly PROJECT_ROW_HEIGHT: number = 34;
  static readonly ROW_SIDE_PADDING: number = 8;
  static readonly ROW_GAP: number = 6;

  // —— 设置面板（ui-settings-general SettingsRoot.module.css）——
  static readonly SETTINGS_PANEL_SIZE: number = 800;
  static readonly SETTINGS_NAV_WIDTH: number = 188;
  static readonly SETTINGS_NAV_CELL_HEIGHT: number = 40;
  static readonly SETTINGS_HEADER_HEIGHT: number = 54;
  static readonly SETTINGS_CARD_RADIUS: number = 12;

  // —— 字号阶梯（gradient-shadow-text.css）——
  static readonly FONT_TITLE: number = 18;
  static readonly FONT_BODY: number = 14;
  static readonly FONT_ROW: number = 14;
  static readonly FONT_SECONDARY: number = 13;
  static readonly FONT_SMALL: number = 12;
  static readonly FONT_CAPTION: number = 11;
  /** hero 标题：26/32 wt500。 */
  static readonly FONT_HERO: number = 26;
  static readonly LINE_HERO: number = 32;
  static readonly LINE_BODY: number = 24;
  static readonly LINE_ROW: number = 22;
  static readonly LINE_SECONDARY: number = 18;
  /** 字体族：上游 --dsw-font-family / --ds-font-family-code。 */
  static readonly FONT_SANS: string = 'HarmonyOS Sans';
  static readonly FONT_MONO: string = 'monospace';

  // —— 动效（base.css --ds-ease-in-out / --ds-transition-duration-*）——
  static readonly DURATION_FAST: number = 100;
  static readonly DURATION: number = 200;
  static readonly DURATION_SLOW: number = 300;
  static readonly CURVE: Curve = Curve.Friction;
}
