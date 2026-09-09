/**
 * 主题设计令牌（DeepSeek 品牌深色主题 · 沉浸光感版）
 * 参照华为开发者文档《主题应用》：集中管理颜色、字号，避免散落魔法值
 *
 * 沉浸光感：半透明玻璃面层 + 细边框 + 品牌蓝渐变。
 * 注意：backgroundBlurStyle 只用于容器/大卡片，不用于按钮/气泡（会发灰），
 * 玻璃感用「半透明 rgba + 1px 细边框」在 5.0.0(12) 下稳定实现。
 */
export class Theme {
  // —— 背景色 ——
  static readonly COLOR_BG: string = '#101318';
  static readonly COLOR_SIDEBAR: string = '#151A22';
  static readonly COLOR_SURFACE: string = '#1C212B';
  static readonly COLOR_SURFACE_HOVER: string = '#232936';
  // —— 玻璃面层（半透明，叠加在 COLOR_BG 上产生通透感）——
  static readonly GLASS_SIDEBAR: string = 'rgba(24,31,44,0.62)';
  static readonly GLASS_HEADER: string = 'rgba(22,28,39,0.55)';
  static readonly GLASS_INPUT: string = 'rgba(28,34,46,0.72)';
  // —— 玻璃边框（顶部受光的浅色细边）——
  static readonly GLASS_BORDER: string = 'rgba(120,140,180,0.16)';
  static readonly GLASS_BORDER_LIGHT: string = 'rgba(150,170,210,0.24)';
  // —— 边框 ——
  static readonly COLOR_BORDER: string = '#2A3140';
  // —— 文字 ——
  static readonly COLOR_TEXT: string = '#E6E8EB';
  static readonly COLOR_SUBTEXT: string = '#8A919E';
  // —— 品牌主色（DeepSeek 蓝） ——
  static readonly COLOR_PRIMARY: string = '#4D6BFE';
  static readonly COLOR_PRIMARY_DARK: string = '#3A55E0';
  // —— 品牌渐变（侧栏活动项 / 主按钮 / 助手气泡左缘）——
  static readonly BRAND_GRAD_START: string = '#5B78FF';
  static readonly BRAND_GRAD_END: string = '#3A55E0';
  // —— 气泡 ——
  static readonly COLOR_USER_BUBBLE: string = '#4D6BFE';
  static readonly COLOR_ASSISTANT_BUBBLE: string = '#1C212B';
  static readonly COLOR_CODE_BG: string = '#0D0F14';
  // —— 状态色 ——
  static readonly COLOR_SUCCESS: string = '#3DD68C';
  static readonly COLOR_ERROR: string = '#F76560';
  static readonly COLOR_WARNING: string = '#F7A84B';
  // —— 字号 ——
  static readonly FONT_TITLE: number = 18;
  static readonly FONT_BODY: number = 15;
  static readonly FONT_SMALL: number = 12;
  static readonly FONT_MONO: string = 'monospace';
}
