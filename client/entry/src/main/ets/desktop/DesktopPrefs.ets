/**
 * DesktopPrefs：桌面壳的设备级偏好（对应上游 Electron `userData/` 下的若干文件）。
 *
 * 上游把壳状态放在 userData：`keybindings.json`、`background-close-confirmed`、窗口几何等。
 * 鸿蒙端统一进一个 preferences 存储，键名固定，读失败一律回落默认值（启动不能被偏好损坏拖死）。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 存储键（改名即数据结构变更，需在 README 更新记录里写明）。 */
export class DesktopPrefKeys {
  /** 存储名 */
  static readonly STORE: string = 'dsh_desktop_shell';
  /** 窗口几何 JSON（WindowGeometry.serialize） */
  static readonly WINDOW_GEOMETRY: string = 'window_geometry';
  /** 快捷键覆盖 JSON（ShortcutRegistry.serialize） */
  static readonly SHORTCUTS: string = 'shortcuts';
  /** 界面语言（'zh-CN' / 'en-US'） */
  static readonly LOCALE: string = 'locale';
  /** 关闭前确认标记（对应上游 background-close-confirmed） */
  static readonly CLOSE_CONFIRMED: string = 'close_confirmed';
  /** 最近一次成功检查更新的时间戳 */
  static readonly LAST_UPDATE_CHECK: string = 'last_update_check';
  /** 上次选择的工作目录（对应上游 directory-picker 选中的工作区） */
  static readonly WORKSPACE_DIRECTORY: string = 'workspace_directory';
}

export class DesktopPrefs {
  private store: preferences.Preferences | null = null;

  /** 打开（或创建）存储；上下文不可用时保持 null，所有读写退化为默认值。 */
  constructor(context: common.UIAbilityContext | common.Context) {
    try {
      this.store = preferences.getPreferencesSync(context, { name: DesktopPrefKeys.STORE });
    } catch (e) {
      this.store = null;
    }
  }

  /** 是否可用（不可用时 UI 应有降级表现，而不是崩溃）。 */
  available(): boolean {
    return this.store !== null;
  }

  getString(key: string, fallback: string = ''): string {
    if (this.store === null) {
      return fallback;
    }
    try {
      return this.store.getSync(key, fallback) as string;
    } catch (e) {
      return fallback;
    }
  }

  putString(key: string, value: string): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(key, value);
      this.store.flush();
    } catch (e) {
      // 写失败不阻断交互（与上游「偏好写失败不影响页面」一致）
    }
  }

  getNumber(key: string, fallback: number): number {
    if (this.store === null) {
      return fallback;
    }
    try {
      return this.store.getSync(key, fallback) as number;
    } catch (e) {
      return fallback;
    }
  }

  putNumber(key: string, value: number): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(key, value);
      this.store.flush();
    } catch (e) {
      // 同上
    }
  }

  getBoolean(key: string, fallback: boolean): boolean {
    if (this.store === null) {
      return fallback;
    }
    try {
      return this.store.getSync(key, fallback) as boolean;
    } catch (e) {
      return fallback;
    }
  }

  putBoolean(key: string, value: boolean): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(key, value);
      this.store.flush();
    } catch (e) {
      // 同上
    }
  }
}
