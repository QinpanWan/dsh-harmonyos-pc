/**
 * UpdateSchedule：更新检查调度（上游 `update-schedule.ts` 的鸿蒙等价实现）。
 *
 * 对齐上游的语义，一条不漏：
 * - 默认 **10 分钟**轮询，失败指数退避封顶 **1 小时**，每次延迟带 **±20% 抖动**；
 * - 手动检查立即执行，并与自动检查**合并成同一次飞行请求**（不重复打网络）；
 * - 完成才算一次调度周期（completion-based deadline），避免「慢请求 + 定时器」叠加；
 * - `dispose()` 后不再有新请求，迟到的完成也不会重新武装定时器。
 * 参数来自 `desktop-shell.json`，越界值按上游同样的边界做校验。
 */
import { UpdatePolicy } from './DesktopShellContract';
import { UpdateCheckResult } from './UpdateFeed';

/** 参数校验结果：'' 表示通过，否则是可直接展示的原因（与上游异常文案同构）。 */
export class UpdatePolicyCheck {
  ok: boolean = false;
  message: string = '';

  constructor(ok: boolean, message: string) {
    this.ok = ok;
    this.message = message;
  }
}

export class DesktopUpdateSchedule {
  private policy: UpdatePolicy;
  private runCheck: (manual: boolean) => Promise<UpdateCheckResult>;
  private timer: number = -1;
  private pending: Promise<UpdateCheckResult> | null = null;
  private activeChecks: number = 0;
  private disposed: boolean = false;
  private hasDeadline: boolean = false;
  private nextCheck: number = 0;
  private delay: number = 0;
  /** 最近一次结果，供 UI 直接读（对应上游 coordinator.state）。 */
  last: UpdateCheckResult | null = null;

  /**
   * @param policy - 契约里的更新策略
   * @param runCheck - 真正执行一次网络检查的闭包（manual=true 时失败必须可见）
   */
  constructor(policy: UpdatePolicy, runCheck: (manual: boolean) => Promise<UpdateCheckResult>) {
    this.policy = policy;
    this.runCheck = runCheck;
    this.delay = policy.intervalMs;
  }

  /** 上游同款范围校验：整数、[1000, 2147483647]、抖动 ∈ [0,1]、退避不小于间隔。 */
  static validate(policy: UpdatePolicy): UpdatePolicyCheck {
    const values: number[] = [policy.intervalMs, policy.maxBackoffMs, policy.minIntervalMs, policy.maxIntervalMs];
    for (let i = 0; i < values.length; i++) {
      const value: number = values[i];
      if (!Number.isSafeInteger(value) || value < 1000 || value > 2147483647) {
        return new UpdatePolicyCheck(false, '更新检查间隔必须是 1000 到 2147483647 之间的整数');
      }
    }
    if (!Number.isFinite(policy.jitter) || policy.jitter < 0 || policy.jitter > 1) {
      return new UpdatePolicyCheck(false, '更新检查抖动必须落在 [0, 1]');
    }
    if (policy.maxBackoffMs < policy.intervalMs) {
      return new UpdatePolicyCheck(false, '更新检查退避上限必须覆盖检查间隔');
    }
    return new UpdatePolicyCheck(true, '');
  }

  /** 当前状态里是否已经有可用的结论（UI 用来决定要不要重画）。 */
  hasResult(): boolean {
    return this.last !== null;
  }

  /**
   * 触发一次检查。
   * @param manual - 用户显式触发（绕过截止时间、失败要可见）
   * @returns 本次（或合并中的）检查结果
   */
  async check(manual: boolean = false): Promise<UpdateCheckResult> {
    if (this.disposed) {
      return UpdateCheckResult.failure('check', '更新检查已停止');
    }
    if (this.pending !== null && !manual) {
      return this.pending;
    }
    if (!manual && this.hasDeadline && Date.now() < this.nextCheck) {
      return this.last === null ? UpdateCheckResult.failure('check', '尚未到检查时间') : this.last;
    }
    this.clearTimer();
    this.activeChecks++;
    const started: Promise<UpdateCheckResult> = this.runCheck(manual);
    this.pending = started.then((result: UpdateCheckResult) => {
      this.last = result;
      this.complete(!result.ok && result.failureKind !== 'check-no-update');
      return result;
    }).catch((error: Object) => {
      const failed: UpdateCheckResult = UpdateCheckResult.failure('check', String(error));
      this.last = failed;
      this.complete(true);
      return failed;
    });
    return this.pending;
  }

  /** 停止调度；已在飞的请求结果不再触发重排。 */
  dispose(): void {
    this.disposed = true;
    this.clearTimer();
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  private complete(failed: boolean): void {
    this.activeChecks--;
    if (this.activeChecks !== 0) {
      return;
    }
    this.pending = null;
    this.schedule(failed);
  }

  /** 抖动在 [lower, upper] 内均匀取值（对应上游 random() 采样）。 */
  private schedule(failed: boolean): void {
    if (this.disposed) {
      return;
    }
    this.delay = failed ? Math.min(this.policy.maxBackoffMs, this.delay * 2) : this.policy.intervalMs;
    const lower: number = Math.max(this.policy.minIntervalMs, this.delay * (1 - this.policy.jitter));
    const upper: number = Math.min(this.policy.maxBackoffMs, this.delay * (1 + this.policy.jitter));
    const delay: number = Math.round(lower + (upper - lower) * Math.random());
    this.nextCheck = Date.now() + delay;
    this.hasDeadline = true;
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.check(false).catch((error: Object) => {
        this.last = UpdateCheckResult.failure('check', String(error));
      });
    }, delay);
  }
}
