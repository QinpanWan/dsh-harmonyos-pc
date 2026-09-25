/**
 * DesktopUpdateService：桌面壳的更新检查（上游 `update-coordinator.ts` + `electron-updater` 的鸿蒙等价物）。
 *
 * 差异是**能力**而不是**事实**：鸿蒙端不能安装 Electron 的 exe/zip 更新包，
 * 因此壳只做「上游是否发布了新版本」的判断与提示，安装交给官网/应用市场。
 * 比较基准 = 本适配基线版本（`desktop-shell.json > upstream.appVersion`，即本仓验证过的上游版本）。
 */
import { DesktopShellContract } from '../desktop/DesktopShellContract';
import { UpdateCheckResult, UpdateFeed, UpdateManifest } from '../desktop/UpdateFeed';
import { DesktopUpdateSchedule } from '../desktop/UpdateSchedule';
import { DesktopPrefs, DesktopPrefKeys } from '../desktop/DesktopPrefs';

/** 检查状态机（与上游 DesktopUpdateState.phase 同名，便于对照）。 */
export class DesktopUpdatePhase {
  static readonly IDLE: string = 'idle';
  static readonly CHECKING: string = 'checking';
  static readonly AVAILABLE: string = 'available';
  static readonly CURRENT: string = 'current';
  static readonly ERROR: string = 'error';
}

export class DesktopUpdateService {
  private contract: DesktopShellContract;
  private prefs: DesktopPrefs;
  private schedule: DesktopUpdateSchedule;
  /** 状态变化通知（UI 侧刷新） */
  private notify: () => void;
  private state: string = DesktopUpdatePhase.IDLE;
  private manifest: UpdateManifest | null = null;
  private failureKind: string = '';
  private failureMessage: string = '';
  private checking: boolean = false;

  constructor(contract: DesktopShellContract, prefs: DesktopPrefs, notify: () => void) {
    this.contract = contract;
    this.prefs = prefs;
    this.notify = notify;
    this.schedule = new DesktopUpdateSchedule(contract.update, (manual: boolean) => this.runCheck(manual));
  }

  /** 当前状态。 */
  phase(): string {
    return this.state;
  }

  /** 是否正在检查（UI 用来自锁按钮）。 */
  isChecking(): boolean {
    return this.checking;
  }

  /** 本适配基线版本（即契约里记录的上游版本）。 */
  baselineVersion(): string {
    return this.contract.upstream.appVersion;
  }

  /** 最近一次拿到的上游版本。 */
  latestVersion(): string {
    return this.manifest === null ? '' : this.manifest.version;
  }

  /** 上游清单 URL（技术详情里展示，便于人工核对）。 */
  manifestUrl(): string {
    return this.contract.manifestUrl();
  }

  /** 最近一次失败分类：'check' | 'check-network' | ''（对应上游 failedOperation）。 */
  lastFailureKind(): string {
    return this.failureKind;
  }

  /** 最近一次失败原因（技术详情）。 */
  lastFailureMessage(): string {
    return this.failureMessage;
  }

  /** 上次成功检查时间（0 表示从未成功过）。 */
  lastCheckTime(): number {
    return this.prefs.getNumber(DesktopPrefKeys.LAST_UPDATE_CHECK, 0);
  }

  /** 启动定时调度（上游壳启动即开始轮询；首轮不立刻打网络）。 */
  start(): void {
    this.schedule.check(false).catch((error: Object) => {
      this.failureKind = 'check';
      this.failureMessage = String(error);
      this.notify();
    });
  }

  /** 用户显式检查：立即执行、失败可见。 */
  async checkNow(): Promise<void> {
    this.checking = true;
    this.state = DesktopUpdatePhase.CHECKING;
    this.notify();
    await this.schedule.check(true);
    this.checking = false;
    this.notify();
  }

  /** 打开应用时若已过期（超过一个轮询间隔）则顺手检查一次。 */
  startIfDue(): void {
    const last: number = this.lastCheckTime();
    const due: boolean = last === 0 || Date.now() - last >= this.contract.update.intervalMs;
    if (due) {
      this.start();
    }
  }

  dispose(): void {
    this.schedule.dispose();
  }

  /** 真正的一次网络检查：拉清单 → 与基线版本比较。 */
  private async runCheck(manual: boolean): Promise<UpdateCheckResult> {
    const result: UpdateCheckResult = await UpdateFeed.fetch(this.contract.manifestUrl(), this.contract.update.requestTimeoutMs);
    if (!result.ok) {
      this.failureKind = result.failureKind;
      this.failureMessage = result.message;
      this.state = DesktopUpdatePhase.ERROR;
      return result;
    }
    const manifest: UpdateManifest = result.manifest as UpdateManifest;
    this.manifest = manifest;
    this.failureKind = '';
    this.failureMessage = '';
    this.prefs.putNumber(DesktopPrefKeys.LAST_UPDATE_CHECK, Date.now());
    if (UpdateFeed.isNewer(manifest.version, this.contract.upstream.appVersion)) {
      this.state = DesktopUpdatePhase.AVAILABLE;
    } else {
      this.state = DesktopUpdatePhase.CURRENT;
    }
    return result;
  }
}
