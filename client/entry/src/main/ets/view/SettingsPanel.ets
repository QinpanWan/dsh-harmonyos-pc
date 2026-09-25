/**
 * SettingsPanel：设置。对齐上游开源实现
 * packages/client/ui-settings-general/src/client/SettingsRoot.module.css：
 * 800x800 面板（圆角 28 / --dsw-alias-bg-layer-2 / elevation-prominent）、
 * 左侧 188 导航（标题 16/24 + 导航格 40 高圆角 12）、右侧内容（头 54 + 选项区 24 内边距）。
 * 行样式取自 ui-theme 的 AppearanceRow（外观立方 20/32 内边距 + 圆角 20）
 * 与 FontSizeRow（ステッパー 72x36 圆角 12），文案遵循 zh 语言表。
 */
import { Constants } from '../common/Constants';
import { Theme, Appearance } from '../common/Theme';
import { DshApiClient } from '../service/DshApiClient';
import {
  IconPersonalizationOutline, IconApiOutline, IconCloseOutline, IconLightOutline,
  IconDarkOutline, IconFollowsystemOutline, IconChevronUpOutline, IconChevronDownOutline,
} from '../common/Icons';
import { BusinessError } from '@kit.BasicServicesKit';

/** 导航区块。 */
const SECTION_GENERAL: number = 0;
const SECTION_MODELS: number = 1;

@Component
export struct SettingsPanel {
  @Prop serverUrl: string = '';
  @Prop connected: boolean = false;
  @Prop statusText: string = '';
  @Prop @Watch('onPresetsChanged') presetIds: string[] = [];
  @Prop currentPreset: string = '';
  @Prop mode: string = 'direct';
  @Prop directApiKey: string = '';
  @Prop directModel: string = 'deepseek-chat';
  @Prop directModels: string[] = [];
  /** 独立模式接口地址（OpenAI 兼容端点，默认官方 DeepSeek） */
  @Prop directBaseUrl: string = '';
  @Prop appearance: string = Appearance.SYSTEM;
  @Prop contentFontSize: number = 14;
  @Prop appVersion: string = '';
  @Prop baselineVersion: string = '';
  client: DshApiClient | null = null;
  onModeChange: (mode: string) => void = () => {};
  onSaveDirect: (key: string, model: string, baseUrl: string) => void = () => {};
  onSave: (url: string) => void = () => {};
  onPresetSelect: (preset: string) => void = () => {};
  onAppearanceChange: (appearance: string) => void = () => {};
  onFontSizeChange: (size: number) => void = () => {};
  onClose: () => void = () => {};
  /** 订阅深浅色：palette(this.dark) 才会在切换外观时重建本组件。 */
  @StorageProp('dshDarkTheme') dark: boolean = true;
  @State section: number = SECTION_GENERAL;
  @State urlInput: string = '';
  @State presetIndex: number = 0;
  @State presetOptions: SelectOption[] = [];
  @State modeIndex: number = 0;
  @State directKeyInput: string = '';
  @State directBaseInput: string = '';
  @State directModelIndex: number = 0;
  // —— dsh 服务端模型配置状态 ——
  @State providerName: string = '';
  @State providerActive: boolean = false;
  @State apiKeySet: boolean = false;
  @State apiKeyInput: string = '';
  @State modelIds: string[] = [];
  @State modelOptions: SelectOption[] = [];
  @State modelIndex: number = 0;
  @State currentModel: string = '';
  @State modelStatus: string = '';
  private settingsNs: string = '';
  private expectedRevision: number = 0;

  aboutToAppear(): void {
    this.urlInput = this.serverUrl;
    this.rebuildPreset();
    this.modeIndex = this.mode === 'dsh' ? 1 : 0;
    this.directKeyInput = '';
    this.directBaseInput = this.directBaseUrl.length > 0 ? this.directBaseUrl : Constants.DIRECT_BASE_URL;
    this.directModelIndex = 0;
    for (let i = 0; i < this.directModels.length; i++) {
      if (this.directModels[i] === this.directModel) {
        this.directModelIndex = i;
        break;
      }
    }
    if (this.mode === 'dsh') {
      this.loadModelConfig();
    }
  }

  onPresetsChanged(): void {
    this.rebuildPreset();
  }

  /** 重建预设下拉选项并校正选中索引（@Watch 响应预设列表异步加载完成） */
  private rebuildPreset(): void {
    const opts: SelectOption[] = [];
    for (let i = 0; i < this.presetIds.length; i++) {
      opts.push({ value: this.presetIds[i] });
    }
    this.presetOptions = opts;
    this.presetIndex = 0;
    for (let i = 0; i < this.presetIds.length; i++) {
      if (this.presetIds[i] === this.currentPreset) {
        this.presetIndex = i;
        break;
      }
    }
  }

  private buildDirectModelOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (let i = 0; i < this.directModels.length; i++) {
      opts.push({ value: this.directModels[i] });
    }
    return opts;
  }

  /** 保存独立模式配置（API Key + 模型 + 接口地址），回调 Index 持久化到本地 */
  private saveDirect(): void {
    const key: string = this.directKeyInput.trim().length > 0 ? this.directKeyInput.trim() : this.directApiKey;
    let model: string = this.directModel;
    if (this.directModelIndex >= 0 && this.directModelIndex < this.directModels.length) {
      model = this.directModels[this.directModelIndex];
    }
    const base: string = this.directBaseInput.trim().length > 0
      ? this.directBaseInput.trim() : Constants.DIRECT_BASE_URL;
    this.onSaveDirect(key, model, base);
    this.directKeyInput = '';
    this.modelStatus = key.length > 0
      ? '独立模式配置已保存（API Key 存于本机）'
      : '已保存模型与接口地址；还差 API Key 才能开聊';
  }

  /**
   * 加载 dsh 服务端模型配置：llm.providers → llm.models → settings.describe
   */
  private loadModelConfig(): void {
    const c = this.client;
    if (c === null) {
      return;
    }
    c.call('llm.providers', {}).then((v: Record<string, Object>) => {
      const providers: Array<Record<string, Object>> = v['providers'] as Array<Record<string, Object>>;
      if (providers !== undefined && providers !== null && providers.length > 0) {
        const p: Record<string, Object> = providers[0];
        const name = p['displayName'];
        this.providerName = name !== undefined && name !== null ? String(name) : String(p['provider']);
        this.providerActive = p['active'] === true;
        const ns = p['settingsNs'];
        this.settingsNs = ns !== undefined && ns !== null ? String(ns) : '';
      } else {
        this.providerName = '（未检测到可配置的模型提供商）';
      }
      return c.call('llm.models', {});
    }).then((v2: Record<string, Object>) => {
      const groups: Array<Record<string, Object>> = v2['groups'] as Array<Record<string, Object>>;
      const ids: string[] = [];
      if (groups !== undefined && groups !== null) {
        for (let i = 0; i < groups.length; i++) {
          const models: Array<Record<string, Object>> = groups[i]['models'] as Array<Record<string, Object>>;
          if (models === undefined || models === null) {
            continue;
          }
          for (let j = 0; j < models.length; j++) {
            ids.push(String(models[j]['id']));
          }
        }
      }
      this.modelIds = ids;
      const opts: SelectOption[] = [];
      for (let i = 0; i < ids.length; i++) {
        opts.push({ value: ids[i] });
      }
      this.modelOptions = opts;
      return c.call('settings.describe', {});
    }).then((v3: Record<string, Object>) => {
      if (this.settingsNs.length === 0) {
        return;
      }
      const namespaces: Array<Record<string, Object>> = v3['namespaces'] as Array<Record<string, Object>>;
      if (namespaces === undefined || namespaces === null) {
        return;
      }
      for (let i = 0; i < namespaces.length; i++) {
        const ns: Record<string, Object> = namespaces[i];
        if (String(ns['ns']) !== this.settingsNs) {
          continue;
        }
        this.expectedRevision = Number(ns['revision']);
        const secrets: Array<Record<string, Object>> = ns['secrets'] as Array<Record<string, Object>>;
        if (secrets !== undefined && secrets !== null) {
          for (let j = 0; j < secrets.length; j++) {
            const path: string[] = secrets[j]['path'] as string[];
            if (path !== undefined && path !== null && path.length > 0 && path[0] === 'apiKey') {
              this.apiKeySet = secrets[j]['set'] === true;
            }
          }
        }
        const value: Record<string, Object> = ns['value'] as Record<string, Object>;
        if (value !== undefined && value !== null) {
          const model = value['model'];
          if (model !== undefined && model !== null) {
            this.currentModel = String(model);
            for (let k = 0; k < this.modelIds.length; k++) {
              if (this.modelIds[k] === this.currentModel) {
                this.modelIndex = k;
                break;
              }
            }
          }
        }
        break;
      }
    }).catch((e: BusinessError) => {
      this.modelStatus = '模型配置加载失败（请确认已连接）';
    });
  }

  /** 写入 dsh 服务端 API Key：settings.update({ns, patch: {apiKey}}) */
  private saveApiKey(): void {
    const c = this.client;
    const key: string = this.apiKeyInput.trim();
    if (c === null || this.settingsNs.length === 0 || key.length === 0) {
      return;
    }
    const patch: Record<string, Object> = { 'apiKey': key };
    c.call('settings.update', {
      'ns': this.settingsNs,
      'patch': patch,
      'expectedRevision': this.expectedRevision
    }).then((v: Record<string, Object>) => {
      this.apiKeySet = true;
      this.apiKeyInput = '';
      this.expectedRevision = Number(v['revision']);
      this.modelStatus = 'API Key 已保存';
    }).catch((e: BusinessError) => {
      this.modelStatus = 'API Key 保存失败：' + String(e);
    });
  }

  /** 写入 dsh 服务端默认模型：settings.update({ns, patch: {model}}) */
  private saveModel(): void {
    const c = this.client;
    if (c === null || this.settingsNs.length === 0) {
      return;
    }
    if (this.modelIndex < 0 || this.modelIndex >= this.modelIds.length) {
      return;
    }
    const modelId: string = this.modelIds[this.modelIndex];
    const patch: Record<string, Object> = { 'model': modelId };
    c.call('settings.update', {
      'ns': this.settingsNs,
      'patch': patch,
      'expectedRevision': this.expectedRevision
    }).then((v: Record<string, Object>) => {
      this.currentModel = modelId;
      this.expectedRevision = Number(v['revision']);
      this.modelStatus = '模型已切换：' + modelId;
    }).catch((e: BusinessError) => {
      this.modelStatus = '模型保存失败：' + String(e);
    });
  }

  build() {
    Column() {
      Row() {
        // —— 左侧导航（188 宽 / 22 上内边距 / 标题 16-24 / 格 40 高圆角 12）——
        Column({ space: 18 }) {
          Text('设置')
            .fontSize(16)
            .lineHeight(24)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
            .width('100%')
            .padding({ left: 12 })
          Column({ space: 4 }) {
            this.navCell(SECTION_GENERAL, '通用设置', 0)
            this.navCell(SECTION_MODELS, '模型与连接', 1)
          }
          .width('100%')
        }
        .width(Theme.SETTINGS_NAV_WIDTH)
        .height('100%')
        .padding({ left: 12, right: 12, top: 22 })
        .alignItems(HorizontalAlign.Start)

        // —— 右侧内容（头 54 + 选项区滚动）——
        Column() {
          Row() {
            Text(this.section === SECTION_GENERAL ? '通用设置' : '模型与连接')
              .fontSize(16)
              .lineHeight(24)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
            Blank()
            Row() {
              IconCloseOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelPrimary })
            }
            .width(28)
            .height(28)
            .justifyContent(FlexAlign.Center)
            .borderRadius(Theme.RADIUS_SM)
            .onClick(() => {
              this.onClose();
            })
          }
          .width('100%')
          .height(Theme.SETTINGS_HEADER_HEIGHT)
          .padding({ left: 20, right: 14, top: 20, bottom: 8 })

          Scroll() {
            Column() {
              if (this.section === SECTION_GENERAL) {
                this.generalSection()
              } else {
                this.modelsSection()
              }
            }
            .width('100%')
            .padding({ left: 24, right: 24, bottom: 24 })
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .align(Alignment.TopStart)
        }
        .layoutWeight(1)
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .constraintSize({ maxWidth: Theme.SETTINGS_PANEL_SIZE })
    .height('100%')
    .constraintSize({ maxHeight: Theme.SETTINGS_PANEL_SIZE })
    .borderRadius(Theme.RADIUS_PANEL)
    .backgroundColor(Theme.palette(this.dark).dswAliasBgLayer2)
    .shadow({ radius: 32, color: 'rgba(0, 0, 0, 0.08)', offsetY: 12 })
    .clip(true)
  }

  /** 导航格（.navCell：40 高 / 圆角 12 / 内边距 9-16-9-12 / 图标 + 14-22 文本）。 */
  @Builder
  navCell(section: number, label: string, glyph: number) {
    Row({ space: 8 }) {
      if (glyph === 0) {
        IconPersonalizationOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelPrimary })
      } else {
        IconApiOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelPrimary })
      }
      Text(label)
        .fontSize(Theme.FONT_ROW)
        .lineHeight(Theme.LINE_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(Theme.SETTINGS_NAV_CELL_HEIGHT)
    .padding({ left: 12, right: 16, top: 9, bottom: 9 })
    .borderRadius(Theme.RADIUS_MD)
    .backgroundColor(this.section === section
      ? Theme.palette(this.dark).dswSpecificSidebarNavItemActive
      : Color.Transparent)
    .onClick(() => {
      this.section = section;
    })
  }

  // —— 通用设置：外观立方 / 正文字号 / 当前版本 ——
  @Builder
  generalSection() {
    Column({ space: 8 }) {
      Text('外观')
        .fontSize(Theme.FONT_ROW)
        .lineHeight(Theme.LINE_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .width('100%')
        .margin({ bottom: 0 })
      Row({ space: 8 }) {
        this.themeCube(Appearance.LIGHT, '浅色', 0)
        this.themeCube(Appearance.DARK, '深色', 1)
        this.themeCube(Appearance.SYSTEM, '跟随系统', 2)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .border({ width: { bottom: 0.5 }, color: Theme.palette(this.dark).dswAliasBorderL2 })

    Row({ space: 8 }) {
      Column({ space: 4 }) {
        Text('正文字号')
          .fontSize(Theme.FONT_ROW)
          .lineHeight(Theme.LINE_ROW)
          .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        Text('会话正文与输入稿的字号（12–17）')
          .fontSize(Theme.FONT_SMALL)
          .lineHeight(Theme.LINE_SECONDARY)
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        Row({ space: 2 }) {
          Text(this.contentFontSize.toString())
            .fontSize(Theme.FONT_ROW)
            .lineHeight(Theme.LINE_ROW)
            .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
            .minFontSize(0)
          Column({ space: 2 }) {
            Row() {
              IconChevronUpOutline({ size: 12, color: Theme.palette(this.dark).dswAliasLabelPrimary })
            }
            .width(17)
            .height(12)
            .justifyContent(FlexAlign.Center)
            .borderRadius(Theme.RADIUS_XS)
            .onClick(() => {
              if (this.contentFontSize < 17) {
                this.onFontSizeChange(this.contentFontSize + 1);
              }
            })
            Row() {
              IconChevronDownOutline({ size: 12, color: Theme.palette(this.dark).dswAliasLabelPrimary })
            }
            .width(17)
            .height(12)
            .justifyContent(FlexAlign.Center)
            .borderRadius(Theme.RADIUS_XS)
            .onClick(() => {
              if (this.contentFontSize > 12) {
                this.onFontSizeChange(this.contentFontSize - 1);
              }
            })
          }
        }
        .width(72)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Theme.RADIUS_MD)
        .backgroundColor(Theme.palette(this.dark).dswAliasBgModulePlatform)

        Text('px')
          .fontSize(Theme.FONT_ROW)
          .lineHeight(Theme.LINE_ROW)
          .fontColor(Theme.palette(this.dark).dswAliasLabelSecondary)
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .border({ width: { bottom: 0.5 }, color: Theme.palette(this.dark).dswAliasBorderL2 })

    Row() {
      Text('当前版本')
        .fontSize(Theme.FONT_ROW)
        .lineHeight(Theme.LINE_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .layoutWeight(1)
      Text(this.appVersion.length > 0 ? this.appVersion : '—')
        .fontSize(Theme.FONT_ROW)
        .lineHeight(Theme.LINE_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
  }

  /** 外观立方（AppearanceRow .themeCube：20/32 内边距、圆角 20、选中填充 module-platform）。 */
  @Builder
  themeCube(value: string, label: string, glyph: number) {
    Column({ space: 4 }) {
      if (glyph === 0) {
        IconLightOutline({ size: 20, color: Theme.palette(this.dark).dswAliasLabelPrimary })
      } else if (glyph === 1) {
        IconDarkOutline({ size: 20, color: Theme.palette(this.dark).dswAliasLabelPrimary })
      } else {
        IconFollowsystemOutline({ size: 20, color: Theme.palette(this.dark).dswAliasLabelPrimary })
      }
      Text(label)
        .fontSize(Theme.FONT_ROW)
        .lineHeight(Theme.LINE_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
    }
    .layoutWeight(1)
    .padding({ left: 32, right: 32, top: 20, bottom: 20 })
    .borderRadius(Theme.RADIUS_XL)
    .border({
      width: 0.5,
      color: this.appearance === value ? '#ADB2B8' : Theme.palette(this.dark).dswAliasBorderL4
    })
    .backgroundColor(this.appearance === value ? Theme.palette(this.dark).dswAliasBgModulePlatform : Color.Transparent)
    .onClick(() => {
      this.onAppearanceChange(value);
    })
  }

  // —— 模型与连接 ——
  @Builder
  modelsSection() {
    this.formRow('连接模式', '独立模式内置对话模式与提示、打开即用；dsh 服务模式对接本机或局域网实例')
    Select([{ value: '独立模式（内置，开箱即用）' }, { value: 'dsh 服务模式' }])
      .selected(this.modeIndex)
      .value(this.mode === 'dsh' ? 'dsh 服务模式' : '独立模式（内置，开箱即用）')
      .font({ size: Theme.FONT_ROW })
      .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
      .selectedOptionFont({ size: Theme.FONT_ROW })
      .optionFont({ size: Theme.FONT_ROW })
      .width('100%')
      .height(44)
      .backgroundColor(Theme.palette(this.dark).dswAliasBgModulePlatform)
      .borderRadius(Theme.RADIUS_MD)
      .margin({ bottom: 16 })
      .onSelect((index: number, value: string) => {
        this.modeIndex = index;
        this.onModeChange(index === 1 ? 'dsh' : 'direct');
        if (index === 1) {
          this.loadModelConfig();
        }
      })

    if (this.mode === 'direct') {
      this.formRow('独立模式', 'API Key 与接口地址仅存本机，不经过服务端；对话模式随包内置')
      TextInput({ text: this.directBaseInput, placeholder: Constants.DIRECT_BASE_URL })
        .height(44)
        .fontSize(Theme.FONT_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .placeholderColor(Theme.palette(this.dark).dswAliasLabelCaption)
        .backgroundColor(Color.Transparent)
        .borderRadius(Theme.RADIUS_LG)
        .border({ width: 0.5, color: Theme.palette(this.dark).dswAliasBorderL4 })
        .padding({ left: 14, right: 14 })
        .margin({ bottom: 8 })
        .onChange((value: string) => {
          this.directBaseInput = value;
        })
      TextInput({ text: this.directKeyInput, placeholder: 'DeepSeek API Key' })
        .type(InputType.Password)
        .height(44)
        .fontSize(Theme.FONT_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .placeholderColor(Theme.palette(this.dark).dswAliasLabelCaption)
        .backgroundColor(Color.Transparent)
        .borderRadius(Theme.RADIUS_LG)
        .border({ width: 0.5, color: Theme.palette(this.dark).dswAliasBorderL4 })
        .padding({ left: 14, right: 14 })
        .margin({ bottom: 8 })
        .onChange((value: string) => {
          this.directKeyInput = value;
        })
      Select(this.buildDirectModelOptions())
        .selected(this.directModelIndex)
        .value(this.directModel)
        .font({ size: Theme.FONT_ROW })
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .selectedOptionFont({ size: Theme.FONT_ROW })
        .optionFont({ size: Theme.FONT_ROW })
        .width('100%')
        .height(44)
        .backgroundColor(Theme.palette(this.dark).dswAliasBgModulePlatform)
        .borderRadius(Theme.RADIUS_MD)
        .margin({ bottom: 8 })
        .onSelect((index: number, value: string) => {
          this.directModelIndex = index;
        })
      Button('保存独立模式配置')
        .height(36)
        .fontSize(Theme.FONT_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimaryForeground)
        .backgroundColor(Theme.palette(this.dark).dswAliasButtonPrimaryFill)
        .borderRadius(Theme.RADIUS_MD)
        .margin({ bottom: 16 })
        .onClick(() => {
          this.saveDirect();
        })
    } else {
      this.formRow('dsh 服务地址', this.statusText)
      TextInput({ text: this.urlInput, placeholder: 'http://127.0.0.1:3080' })
        .height(44)
        .fontSize(Theme.FONT_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .placeholderColor(Theme.palette(this.dark).dswAliasLabelCaption)
        .backgroundColor(Color.Transparent)
        .borderRadius(Theme.RADIUS_LG)
        .border({ width: 0.5, color: Theme.palette(this.dark).dswAliasBorderL4 })
        .padding({ left: 14, right: 14 })
        .margin({ bottom: 8 })
        .onChange((value: string) => {
          this.urlInput = value;
        })
      Button('保存并连接')
        .height(36)
        .fontSize(Theme.FONT_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimaryForeground)
        .backgroundColor(Theme.palette(this.dark).dswAliasButtonPrimaryFill)
        .borderRadius(Theme.RADIUS_MD)
        .margin({ bottom: 16 })
        .onClick(() => {
          this.onSave(this.urlInput.trim());
        })

      this.formRow('服务端模型', this.providerName.length > 0
        ? (this.providerName + (this.providerActive ? '（已启用）' : '（未启用）'))
        : '加载中…')
      TextInput({ text: this.apiKeyInput, placeholder: this.apiKeySet ? 'API Key 已设置（输入可覆盖）' : 'API Key' })
        .type(InputType.Password)
        .height(44)
        .fontSize(Theme.FONT_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .placeholderColor(Theme.palette(this.dark).dswAliasLabelCaption)
        .backgroundColor(Color.Transparent)
        .borderRadius(Theme.RADIUS_LG)
        .border({ width: 0.5, color: Theme.palette(this.dark).dswAliasBorderL4 })
        .padding({ left: 14, right: 14 })
        .margin({ bottom: 8 })
        .onChange((value: string) => {
          this.apiKeyInput = value;
        })
      Button('保存 API Key')
        .height(36)
        .fontSize(Theme.FONT_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimaryForeground)
        .backgroundColor(Theme.palette(this.dark).dswAliasButtonPrimaryFill)
        .borderRadius(Theme.RADIUS_MD)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.saveApiKey();
        })
      if (this.modelOptions.length > 0) {
        Select(this.modelOptions)
          .selected(this.modelIndex)
          .value(this.currentModel.length > 0 ? this.currentModel : '选择模型')
          .font({ size: Theme.FONT_ROW })
          .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
          .selectedOptionFont({ size: Theme.FONT_ROW })
          .optionFont({ size: Theme.FONT_ROW })
          .width('100%')
          .height(44)
          .backgroundColor(Theme.palette(this.dark).dswAliasBgModulePlatform)
          .borderRadius(Theme.RADIUS_MD)
          .margin({ bottom: 8 })
          .onSelect((index: number, value: string) => {
            this.modelIndex = index;
            this.saveModel();
          })
      }
    }

    this.formRow('默认对话模式', '鸿蒙 harmony-* 预设，切换后新建对话生效')
    if (this.presetIds.length > 0) {
      Select(this.presetOptions)
        .selected(this.presetIndex)
        .value(this.currentPreset.length > 0 ? this.currentPreset : '（使用部署默认）')
        .font({ size: Theme.FONT_ROW })
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .selectedOptionFont({ size: Theme.FONT_ROW })
        .optionFont({ size: Theme.FONT_ROW })
        .width('100%')
        .height(44)
        .backgroundColor(Theme.palette(this.dark).dswAliasBgModulePlatform)
        .borderRadius(Theme.RADIUS_MD)
        .onSelect((index: number, value: string) => {
          this.presetIndex = index;
          if (index >= 0 && index < this.presetIds.length) {
            this.onPresetSelect(this.presetIds[index]);
          }
        })
    } else {
      Text('（预设列表不可用）')
        .fontSize(Theme.FONT_SMALL)
        .lineHeight(Theme.LINE_SECONDARY)
        .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
    }

    if (this.modelStatus.length > 0) {
      Text(this.modelStatus)
        .fontSize(Theme.FONT_SMALL)
        .lineHeight(Theme.LINE_SECONDARY)
        .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
        .width('100%')
        .margin({ top: 12 })
    }
  }

  /** 行标题 + 说明（FontSizeRow：标题 14/22、说明 12/18 三级色）。 */
  @Builder
  formRow(title: string, desc: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(Theme.FONT_ROW)
        .lineHeight(Theme.LINE_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
      if (desc.length > 0) {
        Text(desc)
          .fontSize(Theme.FONT_SMALL)
          .lineHeight(Theme.LINE_SECONDARY)
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 4, bottom: 8 })
  }
}
