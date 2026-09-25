/**
 * DesktopShellContract：桌面壳契约（单一事实来源）。
 *
 * 上游 Electron 壳把「窗口默认几何 / 更新调度参数 / 菜单结构 / 快捷键绑定」写死在
 * TypeScript 里（main.ts、update-schedule.ts、locale.ts）。鸿蒙侧把这些可被外部核对的常量
 * 集中到 `resources/rawfile/desktop-shell.json`：
 * - ArkTS 运行时读取它（本文件），行为参数只有一处定义；
 * - 仓库脚本 `scripts/desktop-shell-check.mjs` 用 Node 校验同一份文件与上游事实是否仍一致。
 *
 * 参照华为开发者文档《资源管理》：rawfile 目录资源通过 resourceManager 读取，
 * 不参与资源编译索引，适合放需要保持可读的配置契约。
 */
import { resourceManager } from '@kit.LocalizationKit';
import { util } from '@kit.ArkTS';

/** 上游桌面壳（Electron）事实：仓库、版本、端口与协议版本。 */
export class UpstreamFacts {
  repository: string = 'deepseek-ai/deepseek-harness';
  branch: string = 'master';
  commit: string = '';
  appVersion: string = '';
  hostProtocolVersion: number = 4;
  scheme: string = 'dsh-app';
  desktopPort: number = 19387;
  webPort: number = 3080;
}

/** 窗口几何策略（对应上游 createWindow 的 width/height/minWidth/minHeight）。 */
export class WindowPolicy {
  defaultWidth: number = 1280;
  defaultHeight: number = 820;
  minWidth: number = 520;
  minHeight: number = 600;
  titlebarHeight: number = 40;
  saveDebounceMs: number = 400;
}

/** 更新策略（对应上游 update-schedule.ts 的可校验延迟与 feed 布局）。 */
export class UpdatePolicy {
  feedBase: string = 'https://download.deepseek.com/dsh-desk/feeds';
  defaultTarget: string = 'win-x64';
  manifestName: string = 'nightly.yml';
  downloadPage: string = 'https://download.deepseek.com/';
  intervalMs: number = 600000;
  maxBackoffMs: number = 3600000;
  jitter: number = 0.2;
  minIntervalMs: number = 1000;
  maxIntervalMs: number = 2147483647;
  quitInspectionDeadlineMs: number = 2000;
  requestTimeoutMs: number = 15000;
}

/** 一个菜单项（separator 为 true 时忽略 labelKey）。 */
export class MenuItemSpec {
  id: string = '';
  labelKey: string = '';
  separator: boolean = false;
  shortcutId: string = '';

  constructor(id: string, labelKey: string, separator: boolean, shortcutId: string) {
    this.id = id;
    this.labelKey = labelKey;
    this.separator = separator;
    this.shortcutId = shortcutId;
  }
}

/** 一个顶层菜单。 */
export class MenuSpec {
  id: string = '';
  labelKey: string = '';
  items: MenuItemSpec[] = [];

  constructor(id: string, labelKey: string) {
    this.id = id;
    this.labelKey = labelKey;
  }
}

/** 一条快捷键定义（键名 + 修饰键；展示串由 ShortcutRegistry 生成）。 */
export class ShortcutSpec {
  id: string = '';
  labelKey: string = '';
  key: string = '';
  ctrl: boolean = false;
  shift: boolean = false;
  alt: boolean = false;

  constructor(id: string, labelKey: string, key: string, ctrl: boolean, shift: boolean, alt: boolean) {
    this.id = id;
    this.labelKey = labelKey;
    this.key = key;
    this.ctrl = ctrl;
    this.shift = shift;
    this.alt = alt;
  }
}

/** 契约根对象；`load()` 失败时回落到与上游一致的默认值（绝不静默降到 0 值）。 */
export class DesktopShellContract {
  schemaVersion: number = 1;
  upstream: UpstreamFacts = new UpstreamFacts();
  window: WindowPolicy = new WindowPolicy();
  update: UpdatePolicy = new UpdatePolicy();
  menus: MenuSpec[] = [];
  shortcuts: ShortcutSpec[] = [];
  /** 读取失败时的原因，供「关于」面板与诊断展示。 */
  loadError: string = '';

  static readonly RAWFILE: string = 'desktop-shell.json';

  /**
   * 从 rawfile 读取契约；任何异常都不抛出，而是记录 loadError 并返回默认值。
   * @param rm - 应用资源管理器（Ability 用 context.resourceManager，页面用 getContext(this).resourceManager）
   */
  static load(rm: resourceManager.ResourceManager): DesktopShellContract {
    const contract = new DesktopShellContract();
    try {
      const bytes: Uint8Array = rm.getRawFileContentSync(DesktopShellContract.RAWFILE);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeToString(bytes);
      contract.apply(text);
    } catch (e) {
      contract.loadError = String(e);
    }
    if (contract.menus.length === 0) {
      contract.menus = DesktopShellContract.fallbackMenus();
    }
    if (contract.shortcuts.length === 0) {
      contract.shortcuts = DesktopShellContract.fallbackShortcuts();
    }
    return contract;
  }

  /** 载入失败时的菜单兜底（与 rawfile 中同一顺序，保证 UI 不空）。 */
  private static fallbackMenus(): MenuSpec[] {
    const application = new MenuSpec('application', 'application');
    application.items = [
      new MenuItemSpec('about', 'aboutMenu', false, ''),
      new MenuItemSpec('separator', '', true, ''),
      new MenuItemSpec('checkUpdates', 'checkUpdatesMenu', false, ''),
      new MenuItemSpec('separator', '', true, ''),
      new MenuItemSpec('quit', 'quitApplication', false, '')
    ];
    const edit = new MenuSpec('edit', 'edit');
    edit.items = [
      new MenuItemSpec('undo', 'undo', false, 'undo'),
      new MenuItemSpec('redo', 'redo', false, 'redo'),
      new MenuItemSpec('separator', '', true, ''),
      new MenuItemSpec('cut', 'cut', false, 'cut'),
      new MenuItemSpec('copy', 'copy', false, 'copy'),
      new MenuItemSpec('paste', 'paste', false, 'paste'),
      new MenuItemSpec('delete', 'delete', false, ''),
      new MenuItemSpec('separator', '', true, ''),
      new MenuItemSpec('selectAll', 'selectAll', false, 'selectAll')
    ];
    const view = new MenuSpec('view', 'viewMenu');
    view.items = [
      new MenuItemSpec('reloadPage', 'reloadPageMenu', false, 'reloadPage'),
      new MenuItemSpec('pickDirectory', 'pickDirectoryTitle', false, ''),
      new MenuItemSpec('restartAppHost', 'restartAppHostMenu', false, ''),
      new MenuItemSpec('separator', '', true, ''),
      new MenuItemSpec('toggleFullscreen', 'toggleFullscreenMenu', false, 'toggleFullscreen')
    ];
    const help = new MenuSpec('help', 'helpMenu');
    help.items = [
      new MenuItemSpec('checkUpdates', 'checkUpdatesMenu', false, ''),
      new MenuItemSpec('openDownloadPage', 'openDownloadPageMenu', false, ''),
      new MenuItemSpec('about', 'aboutMenu', false, '')
    ];
    const result: MenuSpec[] = [];
    result.push(application);
    result.push(edit);
    result.push(view);
    result.push(help);
    return result;
  }

  /** 载入失败时的快捷键兜底（壳层自有项 + 编辑动作项）。 */
  private static fallbackShortcuts(): ShortcutSpec[] {
    const result: ShortcutSpec[] = [];
    result.push(new ShortcutSpec('closePage', 'closePage', 'W', true, false, false));
    result.push(new ShortcutSpec('reloadPage', 'reloadPageMenu', 'R', true, false, false));
    result.push(new ShortcutSpec('toggleFullscreen', 'toggleFullscreenMenu', 'F11', false, false, false));
    result.push(new ShortcutSpec('undo', 'undo', 'Z', true, false, false));
    result.push(new ShortcutSpec('redo', 'redo', 'Y', true, false, false));
    result.push(new ShortcutSpec('cut', 'cut', 'X', true, false, false));
    result.push(new ShortcutSpec('copy', 'copy', 'C', true, false, false));
    result.push(new ShortcutSpec('paste', 'paste', 'V', true, false, false));
    result.push(new ShortcutSpec('selectAll', 'selectAll', 'A', true, false, false));
    return result;
  }

  /** 解析 JSON 文本并就地填充（字段缺失时保留类默认值）。 */
  private apply(text: string): void {
    const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    this.schemaVersion = Number(root['schemaVersion']);

    const upstream: Object = root['upstream'];
    if (upstream !== undefined && upstream !== null) {
      const u: Record<string, Object> = upstream as Record<string, Object>;
      this.upstream.repository = String(u['repository']);
      this.upstream.branch = String(u['branch']);
      this.upstream.commit = String(u['commit']);
      this.upstream.appVersion = String(u['appVersion']);
      this.upstream.hostProtocolVersion = Number(u['hostProtocolVersion']);
      this.upstream.scheme = String(u['scheme']);
      this.upstream.desktopPort = Number(u['desktopPort']);
      this.upstream.webPort = Number(u['webPort']);
    }

    const windowNode: Object = root['window'];
    if (windowNode !== undefined && windowNode !== null) {
      const w: Record<string, Object> = windowNode as Record<string, Object>;
      this.window.defaultWidth = Number(w['defaultWidth']);
      this.window.defaultHeight = Number(w['defaultHeight']);
      this.window.minWidth = Number(w['minWidth']);
      this.window.minHeight = Number(w['minHeight']);
      this.window.titlebarHeight = Number(w['titlebarHeight']);
      this.window.saveDebounceMs = Number(w['saveDebounceMs']);
    }

    const updateNode: Object = root['update'];
    if (updateNode !== undefined && updateNode !== null) {
      const p: Record<string, Object> = updateNode as Record<string, Object>;
      this.update.feedBase = String(p['feedBase']);
      this.update.defaultTarget = String(p['defaultTarget']);
      this.update.manifestName = String(p['manifestName']);
      this.update.downloadPage = String(p['downloadPage']);
      this.update.intervalMs = Number(p['intervalMs']);
      this.update.maxBackoffMs = Number(p['maxBackoffMs']);
      this.update.jitter = Number(p['jitter']);
      this.update.minIntervalMs = Number(p['minIntervalMs']);
      this.update.maxIntervalMs = Number(p['maxIntervalMs']);
      this.update.quitInspectionDeadlineMs = Number(p['quitInspectionDeadlineMs']);
      this.update.requestTimeoutMs = Number(p['requestTimeoutMs']);
    }

    const menus: Object = root['menus'];
    if (menus !== undefined && menus !== null) {
      const list: Object[] = menus as Object[];
      const parsed: MenuSpec[] = [];
      for (let i = 0; i < list.length; i++) {
        const m: Record<string, Object> = list[i] as Record<string, Object>;
        const menu = new MenuSpec(String(m['id']), String(m['labelKey']));
        const items: Object = m['items'];
        if (items !== undefined && items !== null) {
          const rawItems: Object[] = items as Object[];
          for (let j = 0; j < rawItems.length; j++) {
            const it: Record<string, Object> = rawItems[j] as Record<string, Object>;
            const separatorValue: Object = it['separator'];
            const separator: boolean = separatorValue !== undefined && separatorValue !== null && separatorValue === true;
            const shortcutValue: Object = it['shortcutId'];
            const shortcutId: string = shortcutValue === undefined || shortcutValue === null ? '' : String(shortcutValue);
            menu.items.push(new MenuItemSpec(String(it['id']), String(it['labelKey']), separator, shortcutId));
          }
        }
        parsed.push(menu);
      }
      this.menus = parsed;
    }

    const shortcuts: Object = root['shortcuts'];
    if (shortcuts !== undefined && shortcuts !== null) {
      const list: Object[] = shortcuts as Object[];
      const parsed: ShortcutSpec[] = [];
      for (let i = 0; i < list.length; i++) {
        const s: Record<string, Object> = list[i] as Record<string, Object>;
        parsed.push(new ShortcutSpec(String(s['id']), String(s['labelKey']), String(s['key']),
          s['ctrl'] === true, s['shift'] === true, s['alt'] === true));
      }
      this.shortcuts = parsed;
    }
  }

  /** 按 id 查快捷键定义；不存在返回 null。 */
  shortcut(id: string): ShortcutSpec | null {
    for (let i = 0; i < this.shortcuts.length; i++) {
      if (this.shortcuts[i].id === id) {
        return this.shortcuts[i];
      }
    }
    return null;
  }

  /** 按 id 查顶层菜单；不存在返回 null。 */
  menu(id: string): MenuSpec | null {
    for (let i = 0; i < this.menus.length; i++) {
      if (this.menus[i].id === id) {
        return this.menus[i];
      }
    }
    return null;
  }

  /** 更新清单 URL（`<feedBase>/<target>/<manifestName>`），与上游 feed 布局一致。 */
  manifestUrl(target: string = this.update.defaultTarget): string {
    return this.update.feedBase + '/' + target + '/' + this.update.manifestName;
  }
}
