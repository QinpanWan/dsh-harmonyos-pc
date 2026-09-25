/**
 * DesktopDirectoryPicker：原生目录选择（上游 `directory-picker.ts` 的鸿蒙等价实现）。
 *
 * 上游用 `dialog.showOpenDialog(window, { properties: ['openDirectory','createDirectory'] })`，
 * 并且：① 同一窗口的并发请求**合并**成一次对话框；② 非主 frame 的调用直接拒绝。
 * 鸿蒙侧用 `@ohos.file.picker` 的 DocumentViewPicker + DocumentSelectMode.FOLDER 实现同样的「选文件夹」语义。
 */
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 一次选择结果：canceled 表示用户取消（与上游返回 null 对应）。 */
export class DirectoryPickResult {
  canceled: boolean = true;
  path: string = '';
  error: string = '';

  static cancelled(): DirectoryPickResult {
    const result = new DirectoryPickResult();
    return result;
  }

  static picked(path: string): DirectoryPickResult {
    const result = new DirectoryPickResult();
    result.canceled = false;
    result.path = path;
    return result;
  }

  static failed(message: string): DirectoryPickResult {
    const result = new DirectoryPickResult();
    result.error = message;
    return result;
  }
}

/** 在飞的对话框（同一时刻只有一个，后到的请求复用同一个 Promise）。 */
let inFlight: Promise<DirectoryPickResult> | null = null;

export class DesktopDirectoryPicker {
  /**
   * 选择工作目录。
   * @param context - UIAbilityContext（分帧对话框归属）
   * @returns 选择结果；取消与失败都**不抛异常**
   */
  static pick(context: common.UIAbilityContext): Promise<DirectoryPickResult> {
    if (inFlight !== null) {
      return inFlight;
    }
    const pending: Promise<DirectoryPickResult> = DesktopDirectoryPicker.open(context).then(
      (result: DirectoryPickResult) => {
        inFlight = null;
        return result;
      },
      (error: Object) => {
        inFlight = null;
        return DirectoryPickResult.failed(String(error));
      }
    );
    inFlight = pending;
    return pending;
  }

  /** 是否已有对话框在飞（UI 可据此避免重复点击）。 */
  static busy(): boolean {
    return inFlight !== null;
  }

  private static async open(context: common.UIAbilityContext): Promise<DirectoryPickResult> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.selectMode = picker.DocumentSelectMode.FOLDER;
    const viewPicker = new picker.DocumentViewPicker(context);
    try {
      const selected: string[] = await viewPicker.select(options);
      if (selected.length === 0) {
        return DirectoryPickResult.cancelled();
      }
      return DirectoryPickResult.picked(selected[0]);
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      // 用户取消在部分版本上表现为异常码 13900042/13900020，一律按取消处理。
      if (error.code === 13900042 || error.code === 13900020) {
        return DirectoryPickResult.cancelled();
      }
      return DirectoryPickResult.failed(error.message);
    }
  }
}
