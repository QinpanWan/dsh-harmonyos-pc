/**
 * DesktopDialogs：壳自有的三块浮层（关于 / 退出确认 / 更新），对应上游同名原生对话框。
 *
 * 用页面内浮层而不是系统弹窗：与「沉浸光感」主题一致（仓库既有的设置面板同风格），
 * 且浮层状态由壳自己持有，行为在两个平台上可逐条对照。
 */
import { Theme } from '../common/Theme';
import { DESKTOP_ZH, DesktopMessages } from '../desktop/DesktopCopy';

/** 关于面板：上游 macOS 走原生 About、Windows 自绘；这里只做自绘一条路径。 */
@Component
export struct DesktopAboutPanel {
  productName: string = 'DeepSeek Harness';
  versionLabel: string = '';
  appVersion: string = '';
  baselineVersion: string = '';
  upstreamCommit: string = '';
  hostProtocolVersion: number = 0;
  contractSource: string = '';
  messages: DesktopMessages = DESKTOP_ZH;
  @StorageProp('dshDarkTheme') dark: boolean = true;
  onClose: () => void = () => {};

  build() {
    Column() {
      Text(this.productName)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .margin({ bottom: 6 })
      Text(this.versionLabel)
        .fontSize(13)
        .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
        .margin({ bottom: 16 })
      this.row('客户端版本', 'V' + this.appVersion)
      this.row('适配基线（上游）', 'V' + this.baselineVersion)
      this.row('上游提交', this.upstreamCommit.length > 12 ? this.upstreamCommit.slice(0, 12) : this.upstreamCommit)
      this.row('Host 生命周期协议', 'v' + this.hostProtocolVersion.toString())
      this.row('契约来源', this.contractSource)
      Button(this.messages.backgroundNoticeConfirm)
        .width('100%')
        .height(36)
        .margin({ top: 18 })
        .backgroundColor(Theme.palette(this.dark).dswAliasButtonPrimaryFill)
        .fontColor('#FFFFFF')
        .onClick(() => {
          this.onClose();
        })
    }
    .width(420)
    .padding(20)
    .backgroundColor(Theme.palette(this.dark).dswAliasBgLayer2)
    .borderRadius(Theme.RADIUS_XL)
    .border({ width: 1, color: Theme.palette(this.dark).dswAliasBorderL3 })
    .shadow({ radius: 32, color: 'rgba(0, 0, 0, 0.16)', offsetY: 12 })
  }

  @Builder
  row(label: string, value: string) {
    Row() {
      Text(label).fontSize(12).fontColor(Theme.palette(this.dark).dswAliasLabelTertiary).width(140)
      Text(value).fontSize(12).fontColor(Theme.palette(this.dark).dswAliasLabelPrimary).layoutWeight(1).textAlign(TextAlign.End)
    }
    .width('100%')
    .margin({ bottom: 8 })
  }
}

/** 退出确认：上游 `quit-confirmation.ts` + `background-notice.ts` 的文案组合。 */
@Component
export struct DesktopQuitConfirmPanel {
  @StorageProp('dshDarkTheme') dark: boolean = true;
  title: string = '';
  body: string = '';
  confirmLabel: string = '';
  cancelLabel: string = '';
  onCancel: () => void = () => {};
  onConfirm: () => void = () => {};

  build() {
    Column() {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .margin({ bottom: 10 })
      Text(this.body)
        .fontSize(13)
        .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
        .margin({ bottom: 18 })
      Row() {
        Button(this.cancelLabel)
          .layoutWeight(1)
          .height(36)
          .backgroundColor(Theme.palette(this.dark).dswAliasInteractiveBgHoverSolid)
          .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
          .onClick(() => {
            this.onCancel();
          })
        Button(this.confirmLabel)
          .layoutWeight(1)
          .height(36)
          .margin({ left: 10 })
          .backgroundColor(Theme.palette(this.dark).dswAliasButtonPrimaryFill)
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.onConfirm();
          })
      }
      .width('100%')
    }
    .width(420)
    .padding(20)
    .backgroundColor(Theme.palette(this.dark).dswAliasBgLayer2)
    .borderRadius(Theme.RADIUS_XL)
    .border({ width: 1, color: Theme.palette(this.dark).dswAliasBorderL3 })
    .shadow({ radius: 32, color: 'rgba(0, 0, 0, 0.16)', offsetY: 12 })
  }
}

/** 更新面板：状态机文案与上游一致；鸿蒙端把「安装」映射为「前往官网下载」。 */
@Component
export struct DesktopUpdatePanel {
  @StorageProp('dshDarkTheme') dark: boolean = true;
  title: string = '';
  message: string = '';
  detail: string = '';
  technical: string = '';
  showTechnical: boolean = false;
  busy: boolean = false;
  canDownload: boolean = false;
  downloadLabel: string = '';
  closeLabel: string = '';
  onCheck: () => void = () => {};
  onDownload: () => void = () => {};
  onToggleTechnical: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Column() {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .margin({ bottom: 10 })
      Text(this.message)
        .fontSize(13)
        .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
      if (this.detail.length > 0) {
        Text(this.detail)
          .fontSize(12)
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
          .margin({ top: 8 })
      }
      if (this.showTechnical && this.technical.length > 0) {
        Text(this.technical)
          .fontSize(11)
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
          .fontFamily(Theme.FONT_MONO)
          .margin({ top: 10 })
          .padding(10)
          .width('100%')
          .backgroundColor(Theme.palette(this.dark).dswAliasMarkdownCodeBlock)
          .borderRadius(8)
      }
      Button(this.busy ? '…' : this.downloadLabel)
        .width('100%')
        .height(36)
        .margin({ top: 16 })
        .enabled(this.canDownload && !this.busy)
        .backgroundColor(this.canDownload ? Theme.palette(this.dark).dswAliasButtonPrimaryFill : Theme.palette(this.dark).dswAliasInteractiveBgHoverSolid)
        .fontColor(this.canDownload ? '#FFFFFF' : Theme.palette(this.dark).dswAliasLabelTertiary)
        .onClick(() => {
          this.onDownload();
        })
      Row() {
        Button(this.closeLabel)
          .layoutWeight(1)
          .height(34)
          .margin({ top: 10 })
          .backgroundColor(Theme.palette(this.dark).dswAliasInteractiveBgHoverSolid)
          .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
          .onClick(() => {
            this.onClose();
          })
        Button(this.showTechnical ? '隐藏技术详情' : '技术详情')
          .layoutWeight(1)
          .height(34)
          .margin({ top: 10, left: 10 })
          .backgroundColor(Theme.palette(this.dark).dswAliasInteractiveBgHoverSolid)
          .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
          .onClick(() => {
            this.onToggleTechnical();
          })
      }
      .width('100%')
    }
    .width(440)
    .padding(20)
    .backgroundColor(Theme.palette(this.dark).dswAliasBgLayer2)
    .borderRadius(Theme.RADIUS_XL)
    .border({ width: 1, color: Theme.palette(this.dark).dswAliasBorderL3 })
    .shadow({ radius: 32, color: 'rgba(0, 0, 0, 0.16)', offsetY: 12 })
  }
}

/**
 * 权限风险确认：上游 ui-permission-presets 的 RiskConfirmation
 * （danger-full-access / auto 两档必须先勾选「我已了解风险」才能启用）。
 */
@Component
export struct DesktopPermissionRiskPanel {
  @StorageProp('dshDarkTheme') dark: boolean = true;
  title: string = '';
  body: string = '';
  acknowledgeLabel: string = '';
  confirmLabel: string = '';
  cancelLabel: string = '';
  acknowledged: boolean = false;
  onAcknowledge: (value: boolean) => void = (value: boolean) => {};
  onCancel: () => void = () => {};
  onConfirm: () => void = () => {};

  build() {
    Column() {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .margin({ bottom: 10 })
      Text(this.body)
        .fontSize(13)
        .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
      Row({ space: 8 }) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.acknowledged })
          .width(18)
          .height(18)
          .selectedColor(Theme.palette(this.dark).dswAliasStateBusinessPrimary)
          .onChange((isOn: boolean) => {
            this.onAcknowledge(isOn);
          })
        Text(this.acknowledgeLabel)
          .fontSize(13)
          .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 16 })
      Row() {
        Button(this.cancelLabel)
          .layoutWeight(1)
          .height(36)
          .backgroundColor(Theme.palette(this.dark).dswAliasInteractiveBgHoverSolid)
          .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
          .onClick(() => {
            this.onCancel();
          })
        Button(this.confirmLabel)
          .layoutWeight(1)
          .height(36)
          .margin({ left: 10 })
          .enabled(this.acknowledged)
          .backgroundColor(this.acknowledged
            ? Theme.palette(this.dark).dswAliasButtonPrimaryFill
            : Theme.palette(this.dark).dswAliasInteractiveBgHoverSolid)
          .fontColor(this.acknowledged ? '#FFFFFF' : Theme.palette(this.dark).dswAliasLabelTertiary)
          .onClick(() => {
            this.onConfirm();
          })
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width(460)
    .padding(20)
    .backgroundColor(Theme.palette(this.dark).dswAliasBgLayer2)
    .borderRadius(Theme.RADIUS_XL)
    .border({ width: 1, color: Theme.palette(this.dark).dswAliasBorderL3 })
    .shadow({ radius: 32, color: 'rgba(0, 0, 0, 0.16)', offsetY: 12 })
  }
}
