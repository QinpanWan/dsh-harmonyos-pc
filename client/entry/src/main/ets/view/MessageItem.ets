/**
 * MessageItem：单条消息。对齐上游 packages/client/ui-chat/src/client/chat/MessageItem.module.css：
 * - 用户：右对齐列（.userRow gap 6 / .userStack gap 8，最大宽度 = 内容宽 × 0.702 且 ≤82%），
 *   气泡 --dsw-specific-bubble + 圆角 20 + 内边距 10/16 + 正文档位；
 * - 助手：正文按 markdown 阶梯（14/24），代码块走 --dsw-alias-markdown-code-block；
 * - 工具：13px 披露行（图标 + 名称 + 摘要），悬停填充 interactive-bg-hover。
 */
import { Theme } from '../common/Theme';
import { ChatMessage, TextBlock } from '../model/Types';
import { IconCopyOutline, IconCodeOutline, IconCheckCircleOutline, IconLoadingOutline } from '../common/Icons';

@Component
export struct MessageItem {
  @ObjectLink message: ChatMessage;
  @Prop contentWidth: number = 748;
  onCopy: (text: string) => void = (text: string) => {};
  @StorageProp('dshDarkTheme') dark: boolean = true;
  @StorageProp('dshContentFontSize') contentFontSize: number = 14;

  build() {
    Column() {
      if (this.message.role === 'user') {
        this.userRow()
      } else if (this.message.role === 'tool') {
        this.toolRow()
      } else {
        this.assistantRow()
      }
    }
    .width('100%')
    .alignItems(this.message.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  /** 用户消息：气泡右对齐 + 下方动作排（时间在左）。 */
  @Builder
  userRow() {
    Column({ space: 6 }) {
      Text(this.message.text)
        .fontSize(this.contentFontSize)
        .lineHeight(Theme.LINE_ROW + Theme.fontDelta())
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .padding({
          left: Theme.BUBBLE_PADDING_H, right: Theme.BUBBLE_PADDING_H,
          top: Theme.BUBBLE_PADDING_V, bottom: Theme.BUBBLE_PADDING_V
        })
        .borderRadius(Theme.RADIUS_XL)
        .backgroundColor(Theme.palette(this.dark).dswSpecificBubble)
        .constraintSize({
          maxWidth: Math.min(this.contentWidth * Theme.BUBBLE_MAX_RATIO, this.contentWidth * 0.82)
        })
        .copyOption(CopyOptions.LocalDevice)

      Row({ space: 8 }) {
        Text(this.timeLabel())
          .fontSize(Theme.secondaryFontSize())
          .lineHeight(Theme.LINE_BODY + Theme.fontDelta())
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
          .margin({ right: 4 })
        Row() {
          IconCopyOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelTertiary })
        }
        .width(24)
        .height(24)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Theme.RADIUS_SM)
        .onClick(() => {
          this.onCopy(this.message.text);
        })
      }
      .height(Theme.ACTIONS_HEIGHT)
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.End)
  }

  /** 助手消息：正文（markdown 阶梯）+ 动作排。 */
  @Builder
  assistantRow() {
    Column({ space: 6 }) {
      if (this.message.reasoning.length > 0 && this.message.text.length === 0) {
        Row({ space: 6 }) {
          Text('思考中')
            .fontSize(Theme.secondaryFontSize())
            .lineHeight(Theme.LINE_SECONDARY + Theme.secondaryDelta())
            .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
        }
        .margin({ bottom: 2 })
      }
      ForEach(this.splitBlocks(this.message.text), (block: TextBlock, index: number) => {
        if (block.isCode) {
          this.codeBlock(block.text)
        } else {
          Text(block.text)
            .fontSize(this.contentFontSize)
            .lineHeight(Theme.LINE_BODY + Theme.fontDelta())
            .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
        }
      }, (block: TextBlock, index: number) => this.message.id + '-' + index.toString())

      if (this.message.status === 'streaming') {
        Text('▍')
          .fontSize(this.contentFontSize)
          .lineHeight(Theme.LINE_BODY + Theme.fontDelta())
          .fontColor(Theme.palette(this.dark).dswAliasStateBusinessPrimary)
      }

      Row({ space: 8 }) {
        Row() {
          IconCopyOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelTertiary })
        }
        .width(24)
        .height(24)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Theme.RADIUS_SM)
        .onClick(() => {
          this.onCopy(this.message.text);
        })

        Text(this.timeLabel())
          .fontSize(Theme.FONT_SMALL)
          .lineHeight(Theme.LINE_BODY + Theme.fontDelta())
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
      }
      .height(Theme.ACTIONS_HEIGHT)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 代码块（--dsw-alias-markdown-code-block + banner）。 */
  @Builder
  codeBlock(code: string) {
    Column() {
      Row() {
        Text(this.codeLanguage(code))
          .fontSize(Theme.FONT_SECONDARY)
          .lineHeight(Theme.LINE_SECONDARY)
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
          .layoutWeight(1)
        Row() {
          IconCopyOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelTertiary })
        }
        .width(24)
        .height(24)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Theme.RADIUS_SM)
        .onClick(() => {
          this.onCopy(this.codeBody(code));
        })
      }
      .width('100%')
      .padding({ left: 12, right: 8, top: 6, bottom: 6 })
      .backgroundColor(Theme.palette(this.dark).dswAliasMarkdownCodeBlockBanner)

      Text(this.codeBody(code))
        .fontSize(Theme.FONT_SECONDARY)
        .fontFamily(Theme.FONT_MONO)
        .lineHeight(20)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .width('100%')
        .padding(12)
        .backgroundColor(Theme.palette(this.dark).dswAliasMarkdownCodeBlock)
        .copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .margin({ top: 4, bottom: 4 })
    .borderRadius(Theme.RADIUS_SM)
    .clip(true)
  }

  /** 工具/流程行（13px 披露行，图标 + 名称 + 摘要）。 */
  @Builder
  toolRow() {
    Row({ space: 6 }) {
      if (this.message.status === 'running') {
        IconLoadingOutline({ size: 14, color: Theme.palette(this.dark).dswAliasLabelSecondary })
      } else if (this.message.status === 'error') {
        IconCodeOutline({ size: 14, color: Theme.palette(this.dark).dswAliasStateErrorPrimary })
      } else {
        IconCheckCircleOutline({ size: 14, color: Theme.palette(this.dark).dswAliasStateSuccessPrimary })
      }
      Text(this.message.toolName.length > 0 ? this.message.toolName : '工具')
        .fontSize(Theme.secondaryFontSize())
        .lineHeight(Theme.LINE_BODY + Theme.fontDelta())
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimaryDimmed)
      if (this.message.toolArgs.length > 0) {
        Text(this.message.toolArgs)
          .fontSize(Theme.secondaryFontSize())
          .lineHeight(Theme.LINE_BODY + Theme.fontDelta())
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 8 })
      }
    }
    .width('100%')
    .height(Theme.LINE_BODY + Theme.fontDelta())
    .padding({ left: 4, right: 8 })
    .borderRadius(Theme.RADIUS_SM)
    .margin({ top: 2, bottom: 2 })
  }

  private codeLanguage(code: string): string {
    return '代码';
  }

  private codeBody(code: string): string {
    return code;
  }

  private timeLabel(): string {
    if (this.message.time <= 0) {
      return '';
    }
    const d: Date = new Date(this.message.time);
    const pad = (n: number): string => {
      return n < 10 ? '0' + n.toString() : n.toString();
    };
    return pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  /** 轻量 Markdown 切分：``` 围栏代码块与普通文本分开渲染。 */
  private splitBlocks(text: string): TextBlock[] {
    const blocks: TextBlock[] = [];
    if (text.length === 0) {
      blocks.push(new TextBlock('', false));
      return blocks;
    }
    let remaining: string = text;
    while (remaining.length > 0) {
      const marker: number = remaining.indexOf('```');
      if (marker === -1) {
        blocks.push(new TextBlock(remaining, false));
        break;
      }
      if (marker > 0) {
        blocks.push(new TextBlock(remaining.slice(0, marker), false));
      }
      const end: number = remaining.indexOf('```', marker + 3);
      if (end === -1) {
        blocks.push(new TextBlock(remaining.slice(marker), false));
        break;
      }
      let code: string = remaining.slice(marker + 3, end);
      const nl: number = code.indexOf('\n');
      if (nl !== -1) {
        const lang: string = code.slice(0, nl).trim();
        if (lang.length > 0 && !lang.includes(' ')) {
          code = code.slice(nl + 1);
        }
      }
      blocks.push(new TextBlock(code, true));
      remaining = remaining.slice(end + 3);
    }
    return blocks;
  }
}
