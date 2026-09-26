/**
 * MessageItem：单条消息。对齐上游 packages/client/ui-chat/src/client/chat/MessageItem.module.css：
 * - 用户：右对齐列（.userRow gap 6 / .userStack gap 8，最大宽度 = 内容宽 × 0.702 且 ≤82%），
 *   气泡 --dsw-specific-bubble + 圆角 20 + 内边距 10/16 + 正文档位；
 * - 助手：正文按 markdown 阶梯（14/24），代码块走 --dsw-alias-markdown-code-block；
 * - 工具：13px 披露行（图标 + 名称 + 摘要），悬停填充 interactive-bg-hover。
 */
import { Theme } from '../common/Theme';
import { ChatMessage, TextBlock } from '../model/Types';
import {
  IconCheckCircleOutline, IconChevronDownOutline, IconChevronUpOutline, IconCodeOutline,
  IconCopyOutline, IconLoadingOutline, IconThinkOutline,
} from '../common/Icons';

@Component
export struct MessageItem {
  @ObjectLink message: ChatMessage;
  @Prop contentWidth: number = 748;
  onCopy: (text: string) => void = (text: string) => {};
  @StorageProp('dshDarkTheme') dark: boolean = true;
  @StorageProp('dshContentFontSize') contentFontSize: number = 14;
  /** 思维链是否展开（上游 ReasoningRow 的 data-expanded：默认收起，只露一行实时摘要） */
  @State thinkOpen: boolean = false;

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

  /**
   * 消息正文的 ForEach 键。
   * **必须带上内容**：ArkUI 的 ForEach 只按 key 判等，key 不变就当成「同一个 item」不重绘；
   * 流式正文在长，若键只有 `消息id-下标`，助手气泡会一直空着（主人报的「发了没反应」就是这个）。
   * 键里带 `isCode` 与文本长度 → 每个增量都换键，正文才会跟着刷。
   */
  private blockKey(block: TextBlock, index: number): string {
    return this.message.id + '-' + index.toString()
      + (block.isCode ? '-c-' : '-t-') + block.text.length.toString();
  }

  /** 助手消息：正文（markdown 阶梯）+ 动作排。 */
  @Builder
  assistantRow() {
    Column({ space: 6 }) {
      if (this.message.reasoning.length > 0) {
        this.reasoningRow()
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
      }, (block: TextBlock, index: number) => this.blockKey(block, index))

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

  /**
   * 思维链披露行（对齐上游 packages/client/ui-chat/src/client/chat/ReasoningRow）：
   * 图标 + 「思考」标题 + **一行实时摘要**；点标题展开看完整思考，再点收起。
   *
   * 摘要取哪一行与上游同一取舍：生成中取**最后一行**（跟着模型的思考尾巴走，这就是「实时」），
   * 结束取**首行**（一眼看出这段思考在解决什么）。`**` 粗体记号按上游去掉。
   * 展开的正文由外层消息列表滚动（列表跟随到底部 = 思考内容一直在视野里），不再套内层滚动条。
   */
  @Builder
  reasoningRow() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        IconThinkOutline({ size: 14, color: Theme.palette(this.dark).dswAliasLabelSecondary })
        Text(this.reasoningTitle())
          .fontSize(Theme.secondaryFontSize())
          .lineHeight(20 + Theme.secondaryDelta())
          .fontColor(Theme.palette(this.dark).dswAliasLabelSecondary)
        Text(this.reasoningSummary())
          .fontSize(Theme.secondaryFontSize())
          .lineHeight(20 + Theme.secondaryDelta())
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
          .maxLines(this.message.status === 'streaming' ? 2 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.thinkOpen) {
          IconChevronUpOutline({ size: 14, color: Theme.palette(this.dark).dswAliasLabelSecondary })
        } else {
          IconChevronDownOutline({ size: 14, color: Theme.palette(this.dark).dswAliasLabelSecondary })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .borderRadius(Theme.RADIUS_SM)
      .onClick(() => {
        this.thinkOpen = !this.thinkOpen;
      })

      if (this.thinkOpen) {
        Text(this.message.reasoning)
          .fontSize(Theme.secondaryFontSize())
          .lineHeight(20 + Theme.secondaryDelta())
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
          .width('100%')
          .padding({ left: 20 })
          .copyOption(CopyOptions.LocalDevice)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 2 })
  }

  /** 披露行标题：生成中说「思考中」，落库后说「思考」（上游 message.think）。 */
  private reasoningTitle(): string {
    return this.message.status === 'streaming' ? '思考中' : '思考';
  }

  /** 摘要行：生成中=最后一行（实时尾巴），结束=首行；去掉 `**` 并限长，避免超长单行拖慢布局。 */
  private reasoningSummary(): string {
    const text: string = this.message.reasoning;
    if (text.length === 0) {
      return '';
    }
    const line: string = this.message.status === 'streaming' ? MessageItem.lastLine(text) : MessageItem.firstLine(text);
    const plain: string = line.split('**').join('').trim();
    return plain.length > 160 ? plain.slice(0, 160) : plain;
  }

  private static firstLine(text: string): string {
    const newline: number = text.indexOf('\n');
    const line: string = newline === -1 ? text : text.slice(0, newline);
    return line.charAt(line.length - 1) === '\r' ? line.slice(0, line.length - 1) : line;
  }

  private static lastLine(text: string): string {
    // 去掉行尾空白（最后一段可能刚好停在换行/缩进上），再取最后一行
    let end: number = text.length;
    while (end > 0) {
      const ch: string = text.charAt(end - 1);
      if (ch !== '\n' && ch !== '\r' && ch !== ' ' && ch !== '\t') {
        break;
      }
      end--;
    }
    const visible: string = text.slice(0, end);
    const newline: number = visible.lastIndexOf('\n');
    const line: string = newline === -1 ? visible : visible.slice(newline + 1);
    return line.charAt(0) === '\r' ? line.slice(1) : line;
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
