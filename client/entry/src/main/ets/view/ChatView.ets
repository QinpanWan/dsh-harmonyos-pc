/**
 * ChatView：会话主列。对齐上游开源实现
 * packages/client/ui-conversation/src/client/skeleton/ConversationRoot.module.css（.header / .body / .viewArea）
 * 与 ui-chat/src/client/chat/ChatView.module.css（.scroll / .column / flow-gap）。
 *
 * 几何：正文列宽 --dsh-chat-content-width = clamp(680, 列宽 × 0.64, 920)；
 * 输入卡上限 = 正文列宽 + 32；正文两侧 16 + 停靠留白。
 *
 * 首页（空会话）= 上游 hero 相位：HeroShell（鲸鱼 + 标题 + 预览徽章）→ **同一张**输入卡；
 * 有消息 = 正文 + 底部停靠的同一张输入卡。整列**只有一张输入卡**（上游「composer 常驻」）。
 * 工作区 / 工作区权限 / 对话模式 / 模型四枚胶囊都在输入卡的工具排里（见 InputBar）：
 * 上游 hero 相位的 .heroWorkspaceRow 已按主人要求合并进去，首页不再有卡外的重复入口。
 */
import { Theme } from '../common/Theme';
import { FishMark } from '../common/Brand';
import { ChatMessage } from '../model/Types';
import { MessageItem } from './MessageItem';
import { InputBar } from './InputBar';
import { IconChevronRightOutline, IconShareOutline } from '../common/Icons';

@Component
export struct ChatView {
  @Prop title: string = '';
  @Link messages: ChatMessage[];
  @Prop streaming: boolean = false;
  @Prop connected: boolean = false;
  @Prop directMode: boolean = false;
  @Prop modelLabel: string = '';
  @Prop presetLabel: string = '';
  @Prop workspaceName: string = '';
  @Prop workspacePath: string = '';
  @Prop statusText: string = '';
  @Prop columnWidth: number = 1200;
  /** 工作区候选（会话 cwd + 手选目录）与可点性 */
  @Prop workspaceOptions: string[] = [];
  @Prop workspaceAvailable: boolean = false;
  @Prop workspaceReason: string = '';
  /** 部署可用的对话模式（agent preset）：ids 与产品名平行数组 + 当前模式说明 */
  @Prop presetIds: string[] = [];
  @Prop presetNames: string[] = [];
  @Prop presetDescription: string = '';
  @Prop presetLocked: boolean = false;
  /** 工作区权限（沙箱 + 审批）目录与当前值 */
  @Prop permissionOptions: string[] = [];
  @Prop permissionLabel: string = '';
  /** 权限胶囊不可用时菜单里的原因（独立模式 / 未连接 / 还没有会话） */
  @Prop permissionReason: string = '';
  /** 权限胶囊是否可点（dsh 服务 + 已连接 + 当前有会话；与上游「无会话不渲染」等价） */
  @Prop permissionEnabled: boolean = false;
  /** 模型胶囊：候选键（独立模式=模型 id；dsh 服务模式=provider/model）与当前键 */
  @Prop modelKeys: string[] = [];
  @Prop modelKey: string = '';
  /** 卡下方的提示（独立模式没填 API Key 之类），空串则不显示 */
  @Prop hint: string = '';
  scroller: Scroller = new Scroller();
  onSend: (text: string) => void = (text: string) => {};
  onStop: () => void = () => {};
  onPickModel: (key: string) => void = (key: string) => {};
  onOpenModelSettings: () => void = () => {};
  onCopy: (text: string) => void = () => {};
  onOpenWorkspace: () => void = () => {};
  onPickWorkspace: (path: string) => void = (path: string) => {};
  onPickPreset: (preset: string) => void = (preset: string) => {};
  onPickPermission: (preset: string) => void = (preset: string) => {};
  onSwitchToDsh: () => void = () => {};
  @StorageProp('dshDarkTheme') dark: boolean = true;
  @StorageProp('dshContentFontSize') contentFontSize: number = 14;

  /** --dsh-chat-content-width：正文列宽。 */
  private contentWidth(): number {
    const ratio: number = this.columnWidth * Theme.CHAT_CONTENT_RATIO;
    return Math.min(Theme.CHAT_CONTENT_MAX, Math.max(Theme.CHAT_CONTENT_MIN, ratio));
  }

  private empty(): boolean {
    return this.messages.length === 0;
  }

  build() {
    Column() {
      this.header()
      if (this.empty()) {
        // hero 相位：整块（壳 + 输入卡）在列内居中，底部留 32（.composerHero）
        Column({ space: 8 }) {
          this.heroChrome()
          this.composer(true)
          this.hintLine()
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ bottom: 32 })
      } else {
        this.transcript()
        this.composer(false)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.palette(this.dark).dswAliasBgBase)
  }

  /** 输入卡（全列唯一实例；hero=true 时空会话态，min 高度与占位文案不同）。 */
  @Builder
  composer(hero: boolean) {
    InputBar({
      streaming: this.streaming,
      connected: this.connected,
      hero: hero,
      contentWidth: this.contentWidth(),
      modelLabel: this.modelLabel,
      modelKeys: this.modelKeys,
      modelKey: this.modelKey,
      permissionLabel: this.permissionLabel,
      permissionOptions: this.permissionOptions,
      permissionAvailable: this.permissionEnabled,
      permissionReason: this.permissionReason,
      workspaceName: this.workspaceName,
      workspacePath: this.workspacePath,
      workspaceOptions: this.workspaceOptions,
      workspaceAvailable: this.workspaceAvailable,
      workspaceReason: this.workspaceReason,
      presetLabel: this.presetLabel,
      presetIds: this.presetIds,
      presetNames: this.presetNames,
      presetDescription: this.presetDescription,
      presetLocked: this.presetLocked,
      directMode: this.directMode,
      placeholder: hero ? this.heroPlaceholder() : this.placeholder(),
      onSend: (text: string) => {
        this.onSend(text);
      },
      onStop: () => {
        this.onStop();
      },
      onPickModel: (key: string) => {
        this.onPickModel(key);
      },
      onOpenModelSettings: () => {
        this.onOpenModelSettings();
      },
      onPickPermission: (preset: string) => {
        this.onPickPermission(preset);
      },
      onPickWorkspace: (path: string) => {
        this.onPickWorkspace(path);
      },
      onOpenWorkspace: () => {
        this.onOpenWorkspace();
      },
      onPickPreset: (preset: string) => {
        this.onPickPreset(preset);
      },
      onSwitchToDsh: () => {
        this.onSwitchToDsh();
      }
    })
  }

  /**
   * 会话头（.header）：20/28 内边距 + 10 上留白 + 30 标题行 + 0.5px 分隔线。
   * 左：面包屑（工作区 › 会话标题）；右：操作组 + 工具组 + 角位。
   */
  @Builder
  header() {
    Row({ space: Theme.TITLE_GAP }) {
      Row({ space: 4 }) {
        Text(this.workspaceName.length > 0 ? this.workspaceName : '工作区')
          .fontSize(Theme.TITLE_FONT_SIZE)
          .lineHeight(20)
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        IconChevronRightOutline({ size: 14, color: Theme.palette(this.dark).dswAliasLabelCaption })
        Text(this.title.length > 0 ? this.title : '新会话')
          .fontSize(Theme.TITLE_FONT_SIZE)
          .lineHeight(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .layoutWeight(1)
      }
      .layoutWeight(1)

      // headerActions（gap 8）：连接指示 + 分享
      Row({ space: 8 }) {
        Row({ space: 6 }) {
          this.dot(this.connected
            ? Theme.palette(this.dark).dswAliasStateSuccessPrimary
            : Theme.palette(this.dark).dswAliasStateErrorPrimary)
          Text(this.statusText)
            .fontSize(Theme.FONT_SMALL)
            .lineHeight(Theme.LINE_SECONDARY)
            .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })

        Row() {
          IconShareOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelSecondary })
        }
        .width(28)
        .height(28)
        .justifyContent(FlexAlign.Center)
        .borderRadius(Theme.RADIUS_SM)
      }
    }
    .width('100%')
    .height(Theme.TITLE_ROW_HEIGHT)
    .padding({
      left: Theme.HEADER_PADDING_LEFT,
      right: Theme.HEADER_PADDING_RIGHT,
      top: Theme.HEADER_PADDING_TOP,
      bottom: Theme.HEADER_PADDING_BOTTOM
    })
    .border({ width: { bottom: 0.5 }, color: Theme.palette(this.dark).dswAliasBorderL3 })
  }

  /**
   * HeroShell：居中鱼标 + 标题 26/32 wt500 + 预览徽章
   * （上游 EmptyHero.tsx 的 .hero / .titleRow / .previewBadge）。
   */
  @Builder
  heroChrome() {
    Row({ space: 10 }) {
      FishMark({ size: 34, color: Theme.palette(this.dark).dswAliasLabelPrimary })
      Text('探索未至之境')
        .fontSize(Theme.FONT_HERO)
        .lineHeight(Theme.LINE_HERO)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
      Text('预览版')
        .fontSize(Theme.FONT_SMALL)
        .lineHeight(Theme.LINE_SECONDARY)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimaryBluish)
        .padding({ left: 7, right: 7, top: 1, bottom: 1 })
        .borderRadius(999)
        .border({ width: 0.5, color: Theme.palette(this.dark).dswAliasInteractiveBgHover })
        .backgroundColor(Theme.palette(this.dark).dswAliasStateBusinessTertiary)
        .margin({ top: 2 })
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 卡下提示（仅 hero 相位）：独立模式没填 API Key / 服务未连接时给一句人话，
   * 别让主人对着一个灰色的发送键猜。空串不渲染任何东西。
   */
  @Builder
  hintLine() {
    if (this.hint.length > 0) {
      Text(this.hint)
        .fontSize(Theme.FONT_SMALL)
        .lineHeight(Theme.LINE_SECONDARY)
        .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
    }
  }

  /** 状态圆点（6px，替代 Circle+fill：fill 需 SDK 26，5.0.0(12) 不可用）。 */
  @Builder
  dot(color: string) {
    Row()
      .width(6)
      .height(6)
      .borderRadius(3)
      .backgroundColor(color)
  }

  /** 消息流：正文列居中，节流间距 16（.column flow-gap）。 */
  @Builder
  transcript() {
    List({ space: Theme.CHAT_FLOW_GAP, scroller: this.scroller }) {
      ForEach(this.messages, (msg: ChatMessage) => {
        ListItem() {
          MessageItem({
            message: msg,
            contentWidth: this.contentWidth(),
            onCopy: (text: string) => {
              this.onCopy(text);
            }
          })
          .width(this.contentWidth())
        }
      }, (msg: ChatMessage) => msg.id)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: Theme.COMPOSER_SIDE_CLEARANCE + 16, right: Theme.COMPOSER_SIDE_CLEARANCE + 16, top: 16, bottom: 16 })
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .alignListItem(ListItemAlign.Center)
  }

  private placeholder(): string {
    if (!this.connected) {
      return '会话不可用';
    }
    return '发消息或创建任务, / 调用指令, @ 文件或对话';
  }

  private heroPlaceholder(): string {
    if (!this.connected) {
      return '会话不可用';
    }
    return '描述你想要构建的内容, / 调用指令, @ 文件或对话';
  }
}

