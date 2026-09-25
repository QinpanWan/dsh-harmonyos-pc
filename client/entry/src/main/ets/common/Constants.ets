/**
 * 全局常量定义
 */
export class Constants {
  /** 默认连接的 dsh 服务地址（本机 web 服务） */
  static readonly DEFAULT_SERVER: string = 'http://127.0.0.1:3080';
  /** 应用名 */
  static readonly APP_NAME: string = 'DeepSeek Harness';
  /** 本地设置存储名称（@ohos.data.preferences） */
  static readonly SETTINGS_STORE: string = 'dsh_client_settings';
  /** 服务器地址存储键 */
  static readonly KEY_SERVER_URL: string = 'server_url';
  /** 登录会话 cookie（`dsh-auth-*`）：本机回环由 Host 签发 30 天，落盘复用 */
  static readonly KEY_AUTH_COOKIE: string = 'auth_cookie';
  /** 默认对话模式（鸿蒙 agent preset）存储键 */
  static readonly KEY_AGENT_PRESET: string = 'agent_preset';
  /** 连接模式存储键：'direct'（独立模式，内置直连、打开即用）/ 'dsh'（dsh 服务模式） */
  static readonly KEY_MODE: string = 'mode';
  /** 直连模式 API Key 存储键（存应用本地 preferences，不经过服务端） */
  static readonly KEY_DIRECT_API_KEY: string = 'direct_api_key';
  /** 直连模式默认模型存储键 */
  static readonly KEY_DIRECT_MODEL: string = 'direct_model';
  /** 外观偏好存储键（system / light / dark，对应上游 ui-theme） */
  static readonly KEY_APPEARANCE: string = 'appearance';
  /** 会话正文档位存储键（12–17，默认 14） */
  static readonly KEY_CONTENT_FONT_SIZE: string = 'content_font_size';
  /**
   * 直连模式可选模型（DeepSeek v4 系优先：主人鸿蒙环境主循环 v4-flash、
   * 复杂任务 v4-pro；兼容官方 deepseek-chat / deepseek-reasoner）。
   */
  static readonly DIRECT_MODELS: string[] = [
    'deepseek-v4-flash',
    'deepseek-v4-pro',
    'deepseek-chat',
    'deepseek-reasoner'
  ];
  /**
   * 内置对话模式的**回落** id 列表：真身是 `rawfile/presets.json`
   * （由 `scripts/gen-client-presets.mjs` 从仓库 `presets/` 生成，含中文名 + persona 系统提示），
   * 由 `PresetCatalog` 读取。只有 rawfile 读不到时才用这份裸 id 列表 ——
   * 保证「独立模式」不依赖 dsh 服务端 agentPresets/list 也能列出对话模式。
   */
  static readonly BUILTIN_PRESETS: string[] = [
    'harmony-chat',
    'harmony-chat-pro',
    'harmony-chat-promax',
    'harmony-chat-ops',
    'harmony-chat-rampagemax',
    'harmony-kb',
    'harmony-deveco',
    'harmony-chat-monash'
  ];

  /** 独立模式的接口地址存储键（默认官方 DeepSeek；任何 OpenAI 兼容端点都能填） */
  static readonly KEY_DIRECT_BASE_URL: string = 'direct_base_url';

  /** 独立模式接口地址默认值（OpenAI 兼容 /chat/completions） */
  static readonly DIRECT_BASE_URL: string = 'https://api.deepseek.com/v1';
  /** 实验档位的产品名（上游 zh 词典的 auto.label 本身就是英文） */
  static readonly PERMISSION_AUTO_LABEL: string = 'Auto review';
  /** 风险确认弹层的确认勾选 / 取消 / 关闭文案（上游 accessZh 的 confirm.*） */
  static readonly PERMISSION_ACK: string = '我已了解风险，并愿意继续';
  static readonly PERMISSION_CANCEL: string = '取消';
  /** 历史消息加载上限（条，会话级） */
  static readonly HISTORY_MAX_MESSAGES: number = 200;
  /** 会话列表标题最长字符数（自动截断） */
  static readonly TITLE_MAX_CHARS: number = 32;
  /**
   * 工作区权限预设的显示名（上游 ui-permission-presets 的 displayPermissionPreset）：
   * 内置三档在部署名等于机器值/英文默认名时用上游 locales.ts 的中文标签；
   * 其余情况按上游 presentation.ts 的 displayPresetName 转 Title Case。
   * @param value - 机器值（read-only / workspace-write / danger-full-access / auto / 自定义）
   * @param name - 部署给定的名称（缺省用 value）
   */
  static permissionLabel(value: string, name: string = ''): string {
    const hostName: string = name.length > 0 ? name : value;
    const defaultName: string = Constants.permissionDefaultName(value);
    if (hostName === value || (defaultName.length > 0 && hostName === defaultName)) {
      if (value === 'read-only') {
        return '仅可查看';
      }
      if (value === 'workspace-write') {
        return '工作区内修改';
      }
      if (value === 'danger-full-access') {
        return '完全权限';
      }
      if (value === 'auto') {
        // 上游 zh 词典对 auto.label 本身就是英文（Auto review）
        return Constants.PERMISSION_AUTO_LABEL;
      }
    }
    return Constants.presetDisplayName(hostName);
  }

  /** 内置档位的英文默认名（上游 DEFAULT_PRESET_LABELS，用于判定部署名是否为默认名）。 */
  static permissionDefaultName(value: string): string {
    if (value === 'read-only') {
      return 'Read Only';
    }
    if (value === 'workspace-write') {
      return 'Workspace Write';
    }
    if (value === 'danger-full-access') {
      return 'Full access';
    }
    return '';
  }

  /** 上游 presentation.ts 的 displayPresetName：kebab-case → Title Case，其它原样。 */
  static presetDisplayName(name: string): string {
    const kebab: boolean = /^[a-z0-9]+(-[a-z0-9]+)*$/.test(name);
    if (!kebab) {
      return name;
    }
    const parts: string[] = name.split('-');
    let out: string = '';
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].length === 0) {
        continue;
      }
      if (out.length > 0) {
        out += ' ';
      }
      out += parts[i].charAt(0).toUpperCase() + parts[i].substring(1);
    }
    return out;
  }

  /** 实验档位的徽章（上游 optionBadge 的 auto.badge = EXP），其余档位无徽章。 */
  static permissionBadge(value: string): string {
    return value === 'auto' ? 'EXP' : '';
  }

  /** 需要风险确认的档位（上游 FULL_ACCESS_PRESET / AUTO_REVIEW_PRESET 走 RiskConfirmation）。 */
  static permissionNeedsRisk(value: string): boolean {
    return value === 'danger-full-access' || value === 'auto';
  }

  /** 风险确认文案（上游 ui-permission-presets/locales.ts 的 confirm.* / auto.confirm.*）。 */
  static permissionRisk(value: string): PermissionRisk {
    if (value === 'auto') {
      return new PermissionRisk(
        '确认启用 Auto review（实验）？',
        'Auto review 不使用沙箱。每次原生工具调用和 PTC 内层调用前，都会由与当前 agent 相同的模型进行审查；'
          + '审查拒绝的调用由你批准或拒绝。此功能仍属实验性，可能误放行或误拒绝，并会消耗额外 token。',
        '启用 Auto review'
      );
    }
    return new PermissionRisk(
      '确认启用完全权限？',
      '启用完全权限后，智能体将减少确认步骤，并且可以直接执行更多操作，包括敏感操作、文件修改或外部命令。'
        + '仅建议在你信任当前任务时使用。',
      '启用完全权限'
    );
  }
}

/** 权限风险确认的文案束（上游 RiskConfirmation 的 title / description / confirm）。 */
export class PermissionRisk {
  title: string = '';
  description: string = '';
  confirmLabel: string = '';

  constructor(title: string, description: string, confirmLabel: string) {
    this.title = title;
    this.description = description;
    this.confirmLabel = confirmLabel;
  }
}
