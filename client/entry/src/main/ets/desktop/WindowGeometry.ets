/**
 * WindowGeometry：窗口几何的记忆与恢复（对应上游 `windows-layout.ts` + `createWindow` 的约束）。
 *
 * 上游把 1280x820 / 最小 520x600 交给 Electron；鸿蒙侧由壳自己记住上次位置与大小，
 * 并在显示器变化（分辨率变小、外接屏拔出）时把窗口夹回可视区域，避免窗口「跑到屏幕外」。
 *
 * 单位约定（官方文档 arkts-apis-window-Window.md / arkts-apis-window-i.md）：
 * - 本文件所有字段一律 **vp**（与上游 Electron 的 CSS px 等价），落盘的也是 vp；
 * - 窗口 API 一律吃 **px**：`resize()` / `resizeAsync()` / `moveWindowTo()` 的参数、
 *   `getWindowProperties().windowRect` / `getLastWindowRect`、`windowSizeChange` 的 `Size`、
 *   `WindowLimits` 的 min/maxWidth/Height 全部标注为 px（`SizeInVP` / `RectInVP` / `getWindowLimitsVP`
 *   是 API 22/23 才有的新接口，当前 SDK 不用）；
 * - `Display.densityPixels`（px / vp）是两者的唯一缩放系数。
 * 历史上把 vp 值直接传给这些 px API（既没乘也没除），效果是每次重启窗口都被缩小 density 倍，
 * 两三下就被最小尺寸夹死 → 用户看到的正是「窗口拖不小」，位置还一轮轮往左上漂。
 * 换算只走本文件的两个静态方法，别在别处写 `* density` / `/ density`。
 */
import { WindowPolicy } from './DesktopShellContract';

/** 显示器度量：可视区尺寸（vp）+ 像素密度（px / vp）。 */
export class DisplayMetrics {
  widthVp: number = 0;
  heightVp: number = 0;
  density: number = 1;

  constructor(widthVp: number, heightVp: number, density: number) {
    this.widthVp = widthVp;
    this.heightVp = heightVp;
    this.density = density;
  }

  /** 密度缺失（0/NaN）时按 1 处理，避免除零把窗口算成 0。 */
  static normalizeDensity(density: number): number {
    return Number.isFinite(density) && density > 0 ? density : 1;
  }
}

/** 一份窗口几何（单位：vp）。 */
export class WindowGeometry {
  /**
   * 落盘格式版本。1 → 2 的原因：1 版曾把「px 当 vp」的值写进同一个键，
   * 那些数字（例如 2880x1920 屏幕上的 2560x1640）夹取后仍会还原成铺满屏幕的大窗口；
   * 版本不匹配时整条丢弃、回到默认几何，比猜「这个数是不是脏数据」可靠。
   */
  static readonly SCHEMA_VERSION: number = 2;

  x: number = 0;
  y: number = 0;
  width: number = 1280;
  height: number = 820;

  constructor(x: number, y: number, width: number, height: number) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }

  /** 按策略给出默认几何（居中由调用方用窗口 API 完成）。 */
  static defaults(policy: WindowPolicy, displayWidth: number = -1, displayHeight: number = -1): WindowGeometry {
    const geometry = new WindowGeometry(-1, -1, policy.defaultWidth, policy.defaultHeight);
    return geometry.clamp(policy, displayWidth, displayHeight);
  }

  /** px → vp（`Rect` / `Size` / `WindowLimits` 都是 px）。 */
  static vpFromPx(px: number, density: number): number {
    return Math.round(px / DisplayMetrics.normalizeDensity(density));
  }

  /** vp → px（`resize` / `moveWindowTo` / `WindowLimits` 都吃 px）。 */
  static pxFromVp(vp: number, density: number): number {
    return Math.round(vp * DisplayMetrics.normalizeDensity(density));
  }

  /** 由窗口 rect（px）构造 vp 几何：退出/尺寸变化时落盘用。 */
  static fromPixelRect(left: number, top: number, width: number, height: number, density: number): WindowGeometry {
    return new WindowGeometry(
      WindowGeometry.vpFromPx(left, density),
      WindowGeometry.vpFromPx(top, density),
      WindowGeometry.vpFromPx(width, density),
      WindowGeometry.vpFromPx(height, density));
  }

  /** 序列化为偏好存储用的 JSON；-1 坐标表示「交给系统居中」。 */
  static serialize(geometry: WindowGeometry): string {
    return '{"v":' + WindowGeometry.SCHEMA_VERSION.toString()
      + ',"x":' + geometry.x.toString() + ',"y":' + geometry.y.toString()
      + ',"width":' + geometry.width.toString() + ',"height":' + geometry.height.toString() + '}';
  }

  /**
   * 从偏好存储的 JSON 解析；缺字段/坏数据一律回到默认几何（不抛异常）。
   * @param raw - 之前由 `serialize` 写入的文本
   * @param policy - 窗口策略（决定默认值与最小尺寸）
   * @param displayWidth - 显示器可视区宽（vp，<=0 表示未知）
   * @param displayHeight - 显示器可视区高（vp，<=0 表示未知）
   */
  static parse(raw: string, policy: WindowPolicy, displayWidth: number = -1, displayHeight: number = -1): WindowGeometry {
    const fallback: WindowGeometry = WindowGeometry.defaults(policy, displayWidth, displayHeight);
    if (raw.length === 0) {
      return fallback;
    }
    try {
      const fields: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      // 版本缺失或过期 = 早期 px/vp 混用写下的脏数据，直接回到默认几何。
      if (WindowGeometry.numberField(fields, 'v', 0) < WindowGeometry.SCHEMA_VERSION) {
        return fallback;
      }
      const width: number = WindowGeometry.numberField(fields, 'width', fallback.width);
      const height: number = WindowGeometry.numberField(fields, 'height', fallback.height);
      const x: number = WindowGeometry.numberField(fields, 'x', fallback.x);
      const y: number = WindowGeometry.numberField(fields, 'y', fallback.y);
      const parsed = new WindowGeometry(x, y, width, height);
      // 上次记录过大的几何（早期版本 px/vp 混用留下的脏数据）在这里直接被夹回可视区。
      return parsed.clamp(policy, displayWidth, displayHeight);
    } catch (e) {
      return fallback;
    }
  }

  private static numberField(fields: Record<string, Object>, key: string, fallback: number): number {
    const value: Object = fields[key];
    if (value === undefined || value === null) {
      return fallback;
    }
    const parsed: number = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  /**
   * 夹到「最小尺寸 + 显示器可视区域」内。
   * @param policy - 最小宽高来源
   * @param displayWidth - 显示器宽（<=0 表示未知，跳过横向夹取）
   * @param displayHeight - 显示器高（<=0 表示未知，跳过纵向夹取）
   */
  clamp(policy: WindowPolicy, displayWidth: number, displayHeight: number): WindowGeometry {
    let width: number = this.width;
    let height: number = this.height;
    if (width < policy.minWidth) {
      width = policy.minWidth;
    }
    if (height < policy.minHeight) {
      height = policy.minHeight;
    }
    // 显示器比设计最小尺寸还小时以显示器为准：窗口一旦整体大于屏幕，边角就拖不到，
    // 用户能看到的现象就是「窗口无法缩小」。
    if (displayWidth > 0 && width > displayWidth) {
      width = Math.max(1, displayWidth);
    }
    if (displayHeight > 0 && height > displayHeight) {
      height = Math.max(1, displayHeight);
    }
    let x: number = this.x;
    let y: number = this.y;
    // 坐标 -1 是「让系统居中」的约定值，不参与夹取。
    if (x < -1) {
      x = -1;
    }
    if (y < -1) {
      y = -1;
    }
    if (x >= 0 && displayWidth > 0 && x + width > displayWidth) {
      x = Math.max(0, displayWidth - width);
    }
    if (y >= 0 && displayHeight > 0 && y + height > displayHeight) {
      y = Math.max(0, displayHeight - height);
    }
    return new WindowGeometry(x, y, width, height);
  }
}
