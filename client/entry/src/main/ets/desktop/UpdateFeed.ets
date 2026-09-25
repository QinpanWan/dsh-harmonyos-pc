/**
 * UpdateFeed：官方桌面端更新清单（electron-builder 生成的 nightly.yml）的解析与版本比较。
 *
 * 上游用 electron-updater 直接吃这份清单；鸿蒙端不能安装 exe/zip，但**版本事实是共享的**：
 * 壳读同一份 feed 判断「上游是否已发布更新」，据此提示用户走官网/应用市场更新。
 * 清单布局（实测 0.1.7-rc.2）：
 *   version: 0.1.7-rc.2
 *   files:
 *     - url: deepseek-harness-0.1.7-rc.2-win-x64.exe
 *       sha512: <base64>
 *       size: 288245480
 *   path: deepseek-harness-0.1.7-rc.2-win-x64.exe
 *   sha512: <base64>
 *   releaseDate: '2026-09-24T...'
 */
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';

/** 清单里的一个产物条目。 */
export class UpdateFile {
  url: string = '';
  sha512: string = '';
  size: number = 0;

  constructor(url: string, sha512: string, size: number) {
    this.url = url;
    this.sha512 = sha512;
    this.size = size;
  }
}

/** 解析后的清单。 */
export class UpdateManifest {
  version: string = '';
  path: string = '';
  sha512: string = '';
  releaseDate: string = '';
  files: UpdateFile[] = [];
}

/** feed 拉取结果：要么有清单，要么有错误原因（网络失败不抛给 UI）。 */
export class UpdateCheckResult {
  ok: boolean = false;
  manifest: UpdateManifest | null = null;
  failureKind: string = '';
  message: string = '';

  static success(manifest: UpdateManifest): UpdateCheckResult {
    const result = new UpdateCheckResult();
    result.ok = true;
    result.manifest = manifest;
    return result;
  }

  static failure(kind: string, message: string): UpdateCheckResult {
    const result = new UpdateCheckResult();
    result.ok = false;
    result.failureKind = kind;
    result.message = message;
    return result;
  }
}

export class UpdateFeed {
  /** 键名之后的第一个值（去掉引号与空白）。 */
  private static valueOf(line: string, key: string): string {
    const marker: string = key + ':';
    const at: number = line.indexOf(marker);
    if (at < 0) {
      return '';
    }
    let value: string = line.slice(at + marker.length).trim();
    if (value.startsWith("'") || value.startsWith('"')) {
      value = value.slice(1);
    }
    if (value.endsWith("'") || value.endsWith('"')) {
      value = value.slice(0, value.length - 1);
    }
    return value;
  }

  /** 逐行扫描 YAML（不引入 yaml 依赖：鸿蒙端只有纯 JS 包可用，见仓库 README 限制章节）。 */
  static parseManifest(text: string): UpdateManifest | null {
    const manifest = new UpdateManifest();
    const lines: string[] = text.split('\n');
    let current: UpdateFile | null = null;
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      const trimmed: string = line.trim();
      if (trimmed.length === 0 || trimmed.startsWith('#')) {
        continue;
      }
      const indented: boolean = line.startsWith(' ') || line.startsWith('\t');
      if (indented && trimmed.startsWith('- ')) {
        current = new UpdateFile('', '', 0);
        manifest.files.push(current);
        current.url = UpdateFeed.valueOf(trimmed.slice(2), 'url');
        current.sha512 = UpdateFeed.valueOf(trimmed.slice(2), 'sha512');
        const sizeAt: number = trimmed.indexOf('size:');
        if (sizeAt >= 0) {
          current.size = Number(trimmed.slice(sizeAt + 5).trim());
        }
        continue;
      }
      if (indented && current !== null) {
        if (trimmed.startsWith('url:')) {
          current.url = UpdateFeed.valueOf(trimmed, 'url');
        } else if (trimmed.startsWith('sha512:')) {
          current.sha512 = UpdateFeed.valueOf(trimmed, 'sha512');
        } else if (trimmed.startsWith('size:')) {
          current.size = Number(UpdateFeed.valueOf(trimmed, 'size'));
        }
        continue;
      }
      // 顶层键
      current = null;
      if (trimmed.startsWith('version:')) {
        manifest.version = UpdateFeed.valueOf(trimmed, 'version');
      } else if (trimmed.startsWith('path:')) {
        manifest.path = UpdateFeed.valueOf(trimmed, 'path');
      } else if (trimmed.startsWith('sha512:')) {
        manifest.sha512 = UpdateFeed.valueOf(trimmed, 'sha512');
      } else if (trimmed.startsWith('releaseDate:')) {
        manifest.releaseDate = UpdateFeed.valueOf(trimmed, 'releaseDate');
      }
    }
    return manifest.version.length === 0 ? null : manifest;
  }

  /** 预发布标识拆解：`0.1.7-rc.2` → ['rc','2']。 */
  private static prerelease(version: string): string[] {
    const dash: number = version.indexOf('-');
    if (dash < 0) {
      return [];
    }
    return version.slice(dash + 1).split('.');
  }

  private static numericParts(version: string): number[] {
    const dash: number = version.indexOf('-');
    const core: string = dash < 0 ? version : version.slice(0, dash);
    const chunks: string[] = core.split('.');
    const parts: number[] = [];
    for (let i = 0; i < chunks.length; i++) {
      const parsed: number = Number(chunks[i]);
      parts.push(Number.isFinite(parsed) ? parsed : 0);
    }
    return parts;
  }

  /**
   * semver 风格比较：返回 1（a 更新）/ 0（相等）/ -1（b 更新）。
   * 与 semver 一致的两条关键规则：预发布 **小于** 同号正式版；预发布标识按「数值优先、再字典序」比较。
   */
  static compare(a: string, b: string): number {
    const left: number[] = UpdateFeed.numericParts(a);
    const right: number[] = UpdateFeed.numericParts(b);
    const length: number = Math.max(left.length, right.length);
    for (let i = 0; i < length; i++) {
      const l: number = i < left.length ? left[i] : 0;
      const r: number = i < right.length ? right[i] : 0;
      if (l !== r) {
        return l > r ? 1 : -1;
      }
    }
    const leftPre: string[] = UpdateFeed.prerelease(a);
    const rightPre: string[] = UpdateFeed.prerelease(b);
    if (leftPre.length === 0 && rightPre.length === 0) {
      return 0;
    }
    if (leftPre.length === 0) {
      return 1;
    }
    if (rightPre.length === 0) {
      return -1;
    }
    const preLength: number = Math.max(leftPre.length, rightPre.length);
    for (let i = 0; i < preLength; i++) {
      if (i >= leftPre.length) {
        return -1;
      }
      if (i >= rightPre.length) {
        return 1;
      }
      const l: string = leftPre[i];
      const r: string = rightPre[i];
      const lNum: number = Number(l);
      const rNum: number = Number(r);
      const lIsNum: boolean = Number.isFinite(lNum) && l.length > 0;
      const rIsNum: boolean = Number.isFinite(rNum) && r.length > 0;
      if (lIsNum && rIsNum) {
        if (lNum !== rNum) {
          return lNum > rNum ? 1 : -1;
        }
      } else if (lIsNum !== rIsNum) {
        return lIsNum ? -1 : 1;
      } else if (l !== r) {
        return l > r ? 1 : -1;
      }
    }
    return 0;
  }

  /** 清单版本是否比当前版本更新。 */
  static isNewer(candidate: string, current: string): boolean {
    return UpdateFeed.compare(candidate, current) > 0;
  }

  /**
   * 拉取并解析清单（失败**不抛异常**，交给 UI 走「更新检查失败」文案）。
   * 失败分类对应上游 DesktopUpdateFailureKind 的 check / check-network 两支。
   */
  static async fetch(manifestUrl: string, timeoutMs: number): Promise<UpdateCheckResult> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(manifestUrl, {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'text/yaml, text/plain, */*' },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      });
      if (response.responseCode !== 200) {
        return UpdateCheckResult.failure('check', 'HTTP ' + response.responseCode.toString());
      }
      const manifest: UpdateManifest | null = UpdateFeed.parseManifest(response.result as string);
      if (manifest === null) {
        return UpdateCheckResult.failure('check', '清单格式无法识别');
      }
      return UpdateCheckResult.success(manifest);
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      return UpdateCheckResult.failure('check-network', error.message);
    } finally {
      request.destroy();
    }
  }
}
