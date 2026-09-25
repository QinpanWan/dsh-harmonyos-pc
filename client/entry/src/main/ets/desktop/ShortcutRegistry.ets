/**
 * ShortcutRegistry：设备级快捷键偏好（对应上游 `keybindings.ts` + `@deepseek-ai/dsh-client-shortcuts/protocol`）。
 *
 * 上游语义（本文件逐条对齐）：
 * - 偏好存在设备本地（Electron userData/keybindings.json；鸿蒙用 preferences）；
 * - 配置是「默认定义 + 设备覆盖」的合并结果，带 **revision**，编辑走单写者事务（这里用一次写 + 版本号递增模拟）；
 * - 展示串由键名与修饰键生成（`Ctrl+Shift+W`），不散落在 UI 里。
 */
import { ShortcutSpec } from './DesktopShellContract';

/** 一条设备级绑定覆盖（id 指向默认定义）。 */
export class ShortcutBinding {
  id: string = '';
  key: string = '';
  ctrl: boolean = false;
  shift: boolean = false;
  alt: boolean = false;

  constructor(id: string, key: string, ctrl: boolean, shift: boolean, alt: boolean) {
    this.id = id;
    this.key = key;
    this.ctrl = ctrl;
    this.shift = shift;
    this.alt = alt;
  }
}

/** 配置快照：revision 单调递增，UI 只认最新一份。 */
export class ShortcutConfig {
  revision: number = 0;
  bindings: ShortcutBinding[] = [];
}

export class ShortcutRegistry {
  /** 展示串：`Ctrl+Alt+Shift+K`（与上游 presentBinding 的修饰键顺序一致：Ctrl → Alt → Shift）。 */
  static present(binding: ShortcutBinding): string {
    const parts: string[] = [];
    if (binding.ctrl) {
      parts.push('Ctrl');
    }
    if (binding.alt) {
      parts.push('Alt');
    }
    if (binding.shift) {
      parts.push('Shift');
    }
    parts.push(binding.key);
    return parts.join('+');
  }

  /** 用默认定义取展示串（无覆盖时）。 */
  static presentDefault(spec: ShortcutSpec): string {
    return ShortcutRegistry.present(new ShortcutBinding(spec.id, spec.key, spec.ctrl, spec.shift, spec.alt));
  }

  /** 一次按键是否命中某条定义（键名大小写不敏感，修饰键必须全等）。 */
  static matches(spec: ShortcutSpec, key: string, ctrl: boolean, shift: boolean, alt: boolean): boolean {
    return spec.key.toUpperCase() === key.toUpperCase() && spec.ctrl === ctrl && spec.shift === shift && spec.alt === alt;
  }

  /** 把设备覆盖合并进默认定义，得到「生效绑定」列表。 */
  static effective(defaults: ShortcutSpec[], config: ShortcutConfig): ShortcutBinding[] {
    const result: ShortcutBinding[] = [];
    for (let i = 0; i < defaults.length; i++) {
      const spec: ShortcutSpec = defaults[i];
      const override: ShortcutBinding | null = ShortcutRegistry.find(config, spec.id);
      if (override === null) {
        result.push(new ShortcutBinding(spec.id, spec.key, spec.ctrl, spec.shift, spec.alt));
      } else {
        result.push(override);
      }
    }
    return result;
  }

  /** 按 id 查覆盖。 */
  static find(config: ShortcutConfig, id: string): ShortcutBinding | null {
    for (let i = 0; i < config.bindings.length; i++) {
      if (config.bindings[i].id === id) {
        return config.bindings[i];
      }
    }
    return null;
  }

  /**
   * 写入一条覆盖（单写者：先读快照 → 改 → revision+1 → 序列化交给调用方落盘）。
   * @returns 递增 revision 后的新快照
   */
  static edit(config: ShortcutConfig, binding: ShortcutBinding): ShortcutConfig {
    const next = new ShortcutConfig();
    next.revision = config.revision + 1;
    let replaced: boolean = false;
    for (let i = 0; i < config.bindings.length; i++) {
      const current: ShortcutBinding = config.bindings[i];
      if (current.id === binding.id) {
        next.bindings.push(binding);
        replaced = true;
      } else {
        next.bindings.push(current);
      }
    }
    if (!replaced) {
      next.bindings.push(binding);
    }
    return next;
  }

  /** 序列化为偏好存储文本。 */
  static serialize(config: ShortcutConfig): string {
    const rows: string[] = [];
    for (let i = 0; i < config.bindings.length; i++) {
      const b: ShortcutBinding = config.bindings[i];
      rows.push('{"id":"' + b.id + '","key":"' + b.key + '","ctrl":' + (b.ctrl ? 'true' : 'false')
        + ',"shift":' + (b.shift ? 'true' : 'false') + ',"alt":' + (b.alt ? 'true' : 'false') + '}');
    }
    return '{"revision":' + config.revision.toString() + ',"bindings":[' + rows.join(',') + ']}';
  }

  /** 解析偏好文本；坏数据 → 空配置（回落到默认定义，不阻塞启动）。 */
  static parse(raw: string): ShortcutConfig {
    const config = new ShortcutConfig();
    if (raw.length === 0) {
      return config;
    }
    try {
      const root: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const revision: Object = root['revision'];
      config.revision = revision === undefined || revision === null ? 0 : Number(revision);
      const bindings: Object = root['bindings'];
      if (bindings !== undefined && bindings !== null) {
        const list: Object[] = bindings as Object[];
        for (let i = 0; i < list.length; i++) {
          const row: Record<string, Object> = list[i] as Record<string, Object>;
          config.bindings.push(new ShortcutBinding(String(row['id']), String(row['key']),
            row['ctrl'] === true, row['shift'] === true, row['alt'] === true));
        }
      }
    } catch (e) {
      return new ShortcutConfig();
    }
    return config;
  }
}
