/**
 * EntryAbility：应用入口 Ability（Stage 模型）+ 桌面壳的窗口级职责。
 *
 * 与上游 Electron 主进程的对应关系：
 * - `createWindow` 的 1280x820 / 最小 520x600 → 这里用 `setWindowLimits` + 记忆几何还原；
 * - 窗口几何持久化（上游由 Electron 自己记）→ 这里写进 `DesktopPrefs`，退出/重启后还原并夹回屏幕内；
 * - 关闭窗口前确认（上游 `windowStageClose` 等价于 Electron 的 `close` + background-notice）→
 *   拦截窗口关闭事件，交给页面弹确认，再由页面回传决定。
 * - 自绘标题栏（上游 Windows 上由系统绘制标题栏与三键）→ 隐藏系统标题栏**与三键区**，
 *   三键由 `DesktopMenuBar` 自绘，因此必须调 `setWindowTitleButtonVisible(false, false, false)`，
 *   否则系统三键会压在自绘标题栏上（点到的其实是系统按钮）。
 *
 * 参照华为开发者文档《Ability 开发》《窗口管理》：UIAbility 负责窗口生命周期，Window 负责几何。
 */
import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { DesktopShellContract } from '../desktop/DesktopShellContract';
import { DesktopPrefs, DesktopPrefKeys } from '../desktop/DesktopPrefs';
import { DisplayMetrics, WindowGeometry } from '../desktop/WindowGeometry';

const DOMAIN: number = 0x0000;
const TAG: string = 'DshEntryAbility';

/** 页面 → Ability：请求确认关闭（页面负责弹确认框） */
export const DESKTOP_QUIT_REQUEST: string = 'dsh-desktop:quit-request';
/** 页面 → Ability：关闭决定（true = 允许退出） */
export const DESKTOP_QUIT_DECISION: string = 'dsh-desktop:quit-decision';
/** 页面 → Ability：页面已就绪（未就绪时不拦截关闭，避免窗口关不掉） */
export const DESKTOP_PAGE_READY: string = 'dsh-desktop:page-ready';
/** Ability → 页面：系统配置变化（外观跟随系统时据此重算深浅色） */
export const DESKTOP_CONFIG_CHANGED: string = 'dsh-desktop:config-changed';
/**
 * Ability → 页面：窗口装饰（系统标题栏）是否仍然可见。
 * 系统标题栏会显示应用图标 + 名称；它没被藏掉时页面**不能再自绘品牌标**，
 * 否则同一个 logo 会在左上角出现两次（主人报的「重影」）。
 */
export const DESKTOP_CHROME_CHANGED: string = 'dsh-desktop:chrome';

export default class EntryAbility extends UIAbility {
  private prefs: DesktopPrefs | null = null;
  private contract: DesktopShellContract = new DesktopShellContract();
  private geometry: WindowGeometry = new WindowGeometry(-1, -1, 1280, 820);
  private saveTimer: number = -1;
  /** 当前窗口所在显示器的像素密度（px / vp），几何换算的唯一依据。 */
  private density: number = 1;
  /** 页面就绪前不拦截关闭：宁可让系统关掉，也不能把窗口卡死。 */
  private pageReady: boolean = false;
  private mainWindow: window.Window | null = null;
  /** 系统标题栏是否仍可见（最近一次探测结果，供页面就绪后补发） */
  private decorVisible: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    this.contract = DesktopShellContract.load(this.context.resourceManager);
    this.prefs = new DesktopPrefs(this.context);
    const metrics: DisplayMetrics = this.displayMetrics(null);
    this.density = metrics.density;
    this.geometry = WindowGeometry.parse(
      this.prefs.getString(DesktopPrefKeys.WINDOW_GEOMETRY, ''), this.contract.window,
      metrics.widthVp, metrics.heightVp);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
      this.applyDesktopWindow(windowStage);
    });

    // 关闭拦截：注册成功则窗口不再直接消失，而是先走「退出确认」。
    try {
      windowStage.on('windowStageClose', () => {
        return this.interceptClose();
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'windowStageClose unavailable: %{public}s', String(e));
    }

    this.context.eventHub.on(DESKTOP_QUIT_DECISION, (allow: boolean) => {
      if (allow) {
        this.context.terminateSelf();
      }
    });
    this.context.eventHub.on(DESKTOP_PAGE_READY, () => {
      this.pageReady = true;
      // 页面可能错过早期那次广播：就绪后补发一次，并再试一轮隐藏系统标题栏
      this.emitChrome(this.decorVisible);
      const mainWindow: window.Window | null = this.mainWindow;
      if (mainWindow !== null) {
        this.applySystemChrome(mainWindow, 1);
      }
    });
  }

  /**
   * 应用桌面窗口策略：最小尺寸、记忆的几何、尺寸变化时落盘。
   * @param windowStage - Ability 的窗口舞台
   */
  private applyDesktopWindow(windowStage: window.WindowStage): void {
    windowStage.getMainWindow((winErr: BusinessError, mainWindow: window.Window) => {
      if (winErr.code !== 0) {
        hilog.warn(DOMAIN, TAG, 'getMainWindow failed: %{public}s', JSON.stringify(winErr));
        return;
      }
      this.mainWindow = mainWindow;
      const metrics: DisplayMetrics = this.displayMetrics(mainWindow);
      this.density = metrics.density;
      // 记忆的几何先夹回可视区：窗口整体大于屏幕时边角拖不到，用户看到的就是「窗口无法缩小」。
      this.geometry = this.geometry.clamp(this.contract.window, metrics.widthVp, metrics.heightVp);
      // Windows 形态：隐藏系统标题栏，改由页面自绘标题栏（DesktopMenuBar）承担菜单与窗口按钮，
      // 空白处按下走 startWindowDrag 拖动窗口。失败则退回系统标题栏（仍可拖动，不阻塞启动）。
      // 自绘标题栏的前提是能自己拖动窗口：startMoving 起于 API 14，低版本设备保留系统标题栏。
      this.applySystemChrome(mainWindow, 0);
      // 上游 520x600 是设计最小尺寸（vp）；WindowLimits 的默认单位是 px，必须按密度换算，
      // 上限取显示器可视区，保证窗口永远留在屏幕内（能拖到边角 = 能继续缩小）。
      const limits: window.WindowLimits = {
        minWidth: WindowGeometry.pxFromVp(Math.min(this.contract.window.minWidth, metrics.widthVp), metrics.density),
        minHeight: WindowGeometry.pxFromVp(Math.min(this.contract.window.minHeight, metrics.heightVp), metrics.density),
        maxWidth: WindowGeometry.pxFromVp(metrics.widthVp, metrics.density),
        maxHeight: WindowGeometry.pxFromVp(metrics.heightVp, metrics.density)
      };
      mainWindow.setWindowLimits(limits).catch((error: Object) => {
        hilog.warn(DOMAIN, TAG, 'setWindowLimits failed: %{public}s', String(error));
      });
      // resize / moveWindowTo 的参数单位是 px（与存盘用的 vp 不同，见 WindowGeometry 顶部说明）：
      // 不换算就等于把 vp 值当 px 传，窗口每次重启都被缩小 density 倍、终被最小值夹死，
      // 用户看到的就是「窗口无法缩小」（位置也会跟着往左上漂）。
      if (this.geometry.x >= 0 && this.geometry.y >= 0) {
        mainWindow.moveWindowTo(
          WindowGeometry.pxFromVp(this.geometry.x, metrics.density),
          WindowGeometry.pxFromVp(this.geometry.y, metrics.density)).catch((error: Object) => {
            hilog.warn(DOMAIN, TAG, 'moveWindowTo failed: %{public}s', String(error));
          });
      }
      mainWindow.resize(
        WindowGeometry.pxFromVp(this.geometry.width, metrics.density),
        WindowGeometry.pxFromVp(this.geometry.height, metrics.density)).catch((error: Object) => {
          hilog.warn(DOMAIN, TAG, 'resize failed: %{public}s', String(error));
        });
      // 尺寸变化只用来触发落盘：真值从 windowRect（px）读回来换算，避免事件与 rect 的单位差异
      mainWindow.on('windowSizeChange', (size: window.Size) => {
        this.scheduleGeometrySave();
      });
    });
  }

  /** 当前窗口所在显示器（拿不到就退回主显示器）的尺寸与密度。 */
  private displayMetrics(mainWindow: window.Window | null): DisplayMetrics {
    try {
      let displayId: number = -1;
      if (mainWindow !== null) {
        const properties: window.WindowProperties = mainWindow.getWindowProperties();
        if (properties.displayId !== undefined) {
          displayId = properties.displayId;
        }
      }
      const target: display.Display = displayId >= 0 && deviceInfo.sdkApiVersion >= 12
        ? display.getDisplayByIdSync(displayId)
        : (deviceInfo.sdkApiVersion >= 14 ? display.getPrimaryDisplaySync() : display.getDefaultDisplaySync());
      const density: number = DisplayMetrics.normalizeDensity(target.densityPixels);
      // availableWidth/Height 已排除 Dock 等系统区域，比整屏尺寸更适合当可视区上限
      const widthPx: number = target.availableWidth > 0 ? target.availableWidth : target.width;
      const heightPx: number = target.availableHeight > 0 ? target.availableHeight : target.height;
      return new DisplayMetrics(
        WindowGeometry.vpFromPx(widthPx, density), WindowGeometry.vpFromPx(heightPx, density), density);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'display metrics unavailable: %{public}s', String(e));
      return new DisplayMetrics(this.geometry.width, this.geometry.height, 1);
    }
  }

  /**
   * 自绘标题栏：藏掉系统装饰与系统三键，并**核实结果**。
   *
   * 以前只在 loadContent 回调里调一次、异常只写日志：设备上如果这一下没生效（或又被系统
   * 还原），系统标题栏会带着应用图标 + 名称留在左上角，而页面里还有自绘的品牌标与菜单栏，
   * 同一枚 logo 就出现两次（主人报的「重影」）。现在：探测 → 没藏掉就重试 → 结果广播给页面。
   *
   * @param mainWindow - 主窗口
   * @param attempt - 第几次尝试（0 起，最多 3 次）
   */
  private applySystemChrome(mainWindow: window.Window, attempt: number): void {
    if (deviceInfo.sdkApiVersion < 14) {
      // 低版本没有 startMoving，保留系统标题栏（仍可拖动），页面据此不自绘品牌标
      this.decorVisible = true;
      this.emitChrome(true);
      return;
    }
    try {
      mainWindow.setWindowDecorVisible(false);
      // 官方《自由窗口下如何自定义窗口标题栏》：自绘三键时必须连系统三键一起隐藏，
      // 否则系统三键会盖在自绘标题栏上（点最大化/最小化命中的是系统按钮）。
      mainWindow.setWindowTitleButtonVisible(false, false, false);
    } catch (decorError) {
      hilog.warn(DOMAIN, TAG, 'hide system decor failed: %{public}s', String(decorError));
    }
    const visible: boolean = this.systemDecorVisible(mainWindow);
    if (visible && attempt < 3) {
      // 窗口刚创建时可能还没准备好，稍后再试（最多 3 次，之后不再纠缠）
      setTimeout(() => {
        this.applySystemChrome(mainWindow, attempt + 1);
      }, 400);
      return;
    }
    if (visible) {
      // 藏不掉：退回到「系统标题栏 + 自绘控件」共存，但至少让系统标题栏高度与契约一致，
      // 并且不再自绘品牌标（页面收到 true 后会隐藏它）。
      try {
        mainWindow.setWindowDecorHeight(this.contract.window.titlebarHeight);
      } catch (heightError) {
        hilog.warn(DOMAIN, TAG, 'setWindowDecorHeight unavailable: %{public}s', String(heightError));
      }
    }
    if (this.decorVisible !== visible) {
      hilog.info(DOMAIN, TAG, 'system decor visible: %{public}s', String(visible));
    }
    this.decorVisible = visible;
    this.emitChrome(visible);
  }

  /** 系统标题栏是否仍可见（API 18 起可查询；查不到按「已隐藏」处理，保持既有观感）。 */
  private systemDecorVisible(mainWindow: window.Window): boolean {
    if (deviceInfo.sdkApiVersion < 18) {
      return false;
    }
    try {
      return mainWindow.getWindowDecorVisible();
    } catch (e) {
      return false;
    }
  }

  /** 把窗口装饰状态广播给页面（页面据此决定是否自绘品牌标）。 */
  private emitChrome(decorVisible: boolean): void {
    try {
      this.context.eventHub.emit(DESKTOP_CHROME_CHANGED, decorVisible);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'emit chrome failed: %{public}s', String(e));
    }
  }

  /** 尺寸变化按策略里的抖动窗口合并落盘（上游 keybindings/几何写盘同样是合并写）。 */
  private scheduleGeometrySave(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.persistGeometry();
    }, this.contract.window.saveDebounceMs);
  }

  private persistGeometry(): void {
    const prefs: DesktopPrefs | null = this.prefs;
    if (prefs === null) {
      return;
    }
    try {
      const mainWindow: window.Window | null = this.mainWindow;
      if (mainWindow === null) {
        return;
      }
      // 最大化/全屏/分屏下记的是「铺满屏幕」的矩形，还原时不该拿它当自由窗口尺寸
      if (this.maximizedState(mainWindow)) {
        return;
      }
      const rect: window.Rect = mainWindow.getWindowProperties().windowRect;
      this.geometry = WindowGeometry.fromPixelRect(rect.left, rect.top, rect.width, rect.height, this.density);
      prefs.putString(DesktopPrefKeys.WINDOW_GEOMETRY, WindowGeometry.serialize(this.geometry));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'persist geometry failed: %{public}s', String(e));
    }
  }

  /** 是否处于最大化/全屏/分屏（这些状态下不写几何）。 */
  private maximizedState(mainWindow: window.Window): boolean {
    try {
      const status: window.WindowStatusType = mainWindow.getWindowStatus();
      return status === window.WindowStatusType.FULL_SCREEN
        || status === window.WindowStatusType.MAXIMIZE
        || status === window.WindowStatusType.SPLIT_SCREEN;
    } catch (e) {
      return false;
    }
  }

  /** 关闭拦截：页面就绪则交给页面确认（返回 true 取消本次终止）。 */
  private interceptClose(): boolean {
    if (!this.pageReady) {
      this.persistGeometry();
      return false;
    }
    this.context.eventHub.emit(DESKTOP_QUIT_REQUEST);
    return true;
  }

  /** 系统深浅色/语言变化：交给页面重算外观（跟随系统时即时生效）。 */
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate colorMode=%{public}s', String(newConfig.colorMode));
    this.context.eventHub.emit(DESKTOP_CONFIG_CHANGED);
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
    this.persistGeometry();
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
