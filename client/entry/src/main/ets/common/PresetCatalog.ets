/**
 * PresetCatalog：内置对话模式目录（rawfile/presets.json）。
 *
 * 「独立模式」（内置直连）要能开箱即用，就不能依赖 dsh 服务端的 agentPresets/list：
 * 这份 JSON 由 `scripts/gen-client-presets.mjs` 从仓库 `presets/` 生成（产品名 + 说明 +
 * persona 系统提示），随 HAP 一起分发。三种用途：
 *   1. 对话模式胶囊的列表与显示名（中文产品名，不再是机器 id）；
 *   2. 独立模式下每次请求的 system 提示（真正的「对话模式」语义）；
 *   3. 术语说明（菜单里那行描述）。
 *
 * 读不到（rawfile 缺失 / 解析失败）时回落到 Constants.BUILTIN_PRESETS 的 id 列表：
 * 列表仍可切换，只是没有中文名与系统提示，绝不阻塞启动。
 */
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Constants } from './Constants';

/** 一套对话模式（独立模式下的「模式」= 一段固定 system 提示 + 显示名）。 */
export class PresetInfo {
  id: string = '';
  name: string = '';
  description: string = '';
  prompt: string = '';

  constructor(id: string, name: string, description: string, prompt: string) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.prompt = prompt;
  }
}

export class PresetCatalog {
  /** rawfile 名（随 HAP 打包）。 */
  static readonly FILE: string = 'presets.json';

  /**
   * 读取内置对话模式；失败时回落到 id 列表。
   * @param context - UIAbility 的 Context（resourceManager 入口）
   */
  static load(context: common.Context | undefined): PresetInfo[] {
    if (context === undefined || context === null) {
      return PresetCatalog.fallback();
    }
    try {
      const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(PresetCatalog.FILE);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeToString(bytes);
      const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const raw: Array<Record<string, Object>> = root['presets'] as Array<Record<string, Object>>;
      if (raw === undefined || raw === null || raw.length === 0) {
        return PresetCatalog.fallback();
      }
      const list: PresetInfo[] = [];
      for (let i = 0; i < raw.length; i++) {
        const item: Record<string, Object> = raw[i];
        const id: string = PresetCatalog.text(item['id']);
        if (id.length === 0) {
          continue;
        }
        list.push(new PresetInfo(
          id,
          PresetCatalog.text(item['name']).length > 0 ? PresetCatalog.text(item['name']) : id,
          PresetCatalog.text(item['description']),
          PresetCatalog.text(item['prompt'])
        ));
      }
      return list.length > 0 ? list : PresetCatalog.fallback();
    } catch (e) {
      return PresetCatalog.fallback();
    }
  }

  /** 回落目录：只有 id（没有中文名与提示）。 */
  static fallback(): PresetInfo[] {
    const list: PresetInfo[] = [];
    for (let i = 0; i < Constants.BUILTIN_PRESETS.length; i++) {
      const id: string = Constants.BUILTIN_PRESETS[i];
      list.push(new PresetInfo(id, id, '', ''));
    }
    return list;
  }

  /** 某个模式的显示名（找不到就原样返回 id）。 */
  static displayName(presets: PresetInfo[], id: string): string {
    for (let i = 0; i < presets.length; i++) {
      if (presets[i].id === id) {
        return presets[i].name.length > 0 ? presets[i].name : presets[i].id;
      }
    }
    return id;
  }

  /** 某个模式的说明（菜单里的那一行小字）。 */
  static describe(presets: PresetInfo[], id: string): string {
    for (let i = 0; i < presets.length; i++) {
      if (presets[i].id === id) {
        return presets[i].description;
      }
    }
    return '';
  }

  /**
   * 独立模式的系统提示：取该模式的 persona 前缀，并把 `{{model}}` / `{{cwd}}` 填成本地值
   * （服务端由 persona 插件做同一替换，这里是它在客户端侧的等价物）。
   */
  static systemPrompt(presets: PresetInfo[], id: string, model: string, cwd: string): string {
    let prompt: string = '';
    for (let i = 0; i < presets.length; i++) {
      if (presets[i].id === id) {
        prompt = presets[i].prompt;
        break;
      }
    }
    if (prompt.length === 0) {
      return '';
    }
    return prompt.split('{{model}}').join(model).split('{{cwd}}').join(cwd);
  }

  private static text(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value);
  }
}
