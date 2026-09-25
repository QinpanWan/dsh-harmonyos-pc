/**
 * InputBar：输入卡。几何逐条对齐上游开源实现
 * packages/client/ui-conversation/src/client/skeleton/InputBar.tsx + InputBar.module.css：
 * 卡片（--dsw-specific-input-major / 圆角 28 / elevation-soft + l2 发丝描边 / 顶内边距 8）、
 * 草稿区（4/8/0/14 内边距，停靠态最小 36、hero 态 52，上限 336）、
 * 工具排（2/8/6 内边距）：
 *   左「+」28 圆（selector 填充）+ **工作区权限**（上游 conversation.input.permission 座位：
 *   ui-permission-presets 的 PermissionSelect）+ **工作区** + **对话模式** 三枚 28 高胶囊，
 *   右 模型胶囊（上游 conversation.input.model 座位，28 高 / 13-20 wt500 次级）+ 发送 34 圆
 *   （--dsw-alias-button-info-fill，白色字形；生成中同位置换成停止方块，上移 2）。
 *
 * 与上游的差异（主人点名要的）：上游把「工作区 / 对话模式」放在 hero 相位输入卡**上方**的
 * .heroWorkspaceRow 里，这里统一搬进工具排 —— 首页与停靠态共用同一排控件，不再出现
 * 「同一件事两个按钮」（一个在卡上方、一个在卡里）的重复入口。工具排用 Flex 换行，
 * 窄窗口下三枚胶囊自动折到第二行，不会互相压字。
 */
import { Constants } from '../common/Constants';
import { Theme } from '../common/Theme';
import {
  IconPlusOutline, IconChevronDownOutline, IconStopFill, IconFolderOpen, IconFolderClose,
  IconAgentPresetOutline,
  PermissionIconReadOnly, PermissionIconWorkspaceWrite, PermissionIconFullAccess,
} from '../common/Icons';
import { KeyCode } from '@kit.InputKit';

@Component
export struct InputBar {
  @Prop streaming: boolean = false;
  @Prop connected: boolean = false;
  @Prop hero: boolean = false;
  @Prop contentWidth: number = 748;
  @Prop modelLabel: string = '';
  @Prop placeholder: string = '';
  /** 工作区权限胶囊（上游 conversation.input.permission）：这里是**机器值**，显示名走 Constants.permissionLabel */
  @Prop permissionLabel: string = '';
  @Prop permissionOptions: string[] = [];
  @Prop permissionAvailable: boolean = false;
  /** 不可用时的原因（独立模式 / 未连接 / 还没有会话），显示在菜单第一行 */
  @Prop permissionReason: string = '';
  /** 独立模式（内置直连）：没有 dsh 会话，工作区/权限胶囊给原因并在菜单里留切换入口 */
  @Prop directMode: boolean = false;

  // —— 工作区胶囊 ——
  @Prop workspaceName: string = '';
  @Prop workspacePath: string = '';
  @Prop workspaceOptions: string[] = [];
  @Prop workspaceAvailable: boolean = false;
  @Prop workspaceReason: string = '';

  // —— 对话模式胶囊（agent preset）——
  @Prop presetLabel: string = '';
  @Prop presetIds: string[] = [];
  /** 与 presetIds 平行：产品显示名（来自 rawfile/presets.json） */
  @Prop presetNames: string[] = [];
  /** 当前模式的说明，菜单首行小字 */
  @Prop presetDescription: string = '';
  /** 已开聊：模式锁定（上游「首个回合后锁定」） */
  @Prop presetLocked: boolean = false;

  // —— 模型胶囊（上游 conversation.input.model 座位）——
  /** 菜单里每一项的键：独立模式 = 模型 id；dsh 服务模式 = `provider/model` */
  @Prop modelKeys: string[] = [];
  /** 当前模型所在的那一项键（用于打 ✓） */
  @Prop modelKey: string = '';

  onSend: (text: string) => void = (text: string) => {};
  onStop: () => void = () => {};
  onPickModel: (key: string) => void = (key: string) => {};
  onOpenModelSettings: () => void = () => {};
  onPickPermission: (preset: string) => void = (preset: string) => {};
  onPickWorkspace: (path: string) => void = (path: string) => {};
  onOpenWorkspace: () => void = () => {};
  onPickPreset: (preset: string) => void = (preset: string) => {};
  onSwitchToDsh: () => void = () => {};
  @State input: string = '';
  @StorageProp('dshDarkTheme') dark: boolean = true;
  @StorageProp('dshContentFontSize') contentFontSize: number = 14;

  /** 输入卡上限 = 正文列宽 + 32（--dsh-composer-card-max-width）。 */
  private cardWidth(): number {
    return this.contentWidth + Theme.COMPOSER_CARD_EXTRA;
  }

  private canSend(): boolean {
    return this.input.trim().length > 0 && !this.streaming && this.connected;
  }

  build() {
    Column() {
      Column() {
        TextArea({ text: this.input, placeholder: this.placeholder })
          .width('100%')
          .constraintSize({
            minHeight: this.hero ? Theme.COMPOSER_HERO_INPUT_MIN_HEIGHT : Theme.COMPOSER_INPUT_MIN_HEIGHT,
            maxHeight: Theme.COMPOSER_TEXT_MAX_HEIGHT
          })
          .fontSize(this.contentFontSize)
          .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
          .placeholderColor(Theme.palette(this.dark).dswAliasLabelCaption)
          .placeholderFont({ size: this.contentFontSize })
          .caretColor(Theme.palette(this.dark).dswAliasStateBusinessPrimary)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .padding({
            left: Theme.COMPOSER_INPUT_PADDING_LEFT,
            right: Theme.COMPOSER_INPUT_PADDING_RIGHT,
            top: Theme.COMPOSER_INPUT_PADDING_TOP,
            bottom: 0
          })
          .onChange((value: string) => {
            this.input = value;
          })
          .onKeyEvent((event: KeyEvent) => {
            // 上游 Enter = 发送（Shift/Ctrl+Enter 的插话发送在鸿蒙端由按钮承担）
            if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ENTER) {
              this.doSend();
            }
          })

        Row() {
          // 左侧工具组（上游 .tools：+ 28 圆 + .modes 权限/计划胶囊 + input.left）。
          // 主人要求的布局：工作区 / 对话模式两枚也搬到这里，和工作区权限排在一起；
          // 用 Flex 换行，窄窗口自动折行，不会把胶囊压成豆腐块。
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Row() {
              IconPlusOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelPrimary })
            }
            .width(Theme.COMPOSER_ADD_SIZE)
            .height(Theme.COMPOSER_ADD_SIZE)
            .justifyContent(FlexAlign.Center)
            .borderRadius(999)
            .backgroundColor(Theme.palette(this.dark).dswSpecificSelector)
            .margin({ right: 8 })

            this.permissionChip()
            this.workspaceChip()
            this.presetChip()
          }
          .layoutWeight(1)

          // 右侧（trailing gap 12，整体上移 2 由发送键承担）
          Row({ space: 12 }) {
            // 模型胶囊：真菜单（独立模式=模型列表；dsh 服务模式=服务端模型目录 + selectModel）
            Row({ space: 4 }) {
              Text(this.modelLabel.length > 0 ? this.modelLabel : '选择模型')
                .fontSize(Theme.FONT_SECONDARY)
                .lineHeight(20)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.palette(this.dark).dswAliasLabelSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              IconChevronDownOutline({ size: 12, color: Theme.palette(this.dark).dswAliasLabelSecondary })
            }
            .height(Theme.COMPOSER_SELECT_HEIGHT)
            .constraintSize({ maxWidth: Theme.COMPOSER_SELECT_MAX_WIDTH })
            .padding({ left: 8, right: 4 })
            .borderRadius(Theme.RADIUS_SM)
            .hoverEffect(HoverEffect.Highlight)
            .bindMenu(this.modelMenu())

            // 主按钮（34 圆 / info-fill / 白色字形）——生成中为停止方块。
            Row() {
              if (this.streaming) {
                Row() {
                  IconStopFill({ size: 16, color: '#FFFFFF' })
                }
                .width(16)
                .height(16)
              } else {
                Shape() {
                  Path()
                    .commands(SEND_ARROW_PATH)
                    .fill('#FFFFFF')
                    // ArkUI 每个 Path 都会「填色 + 默认黑色 pen 描边」画两遍，白色箭头上会多一圈黑边
                    .strokeWidth(0)
                }
                .viewPort({ x: 0, y: 0, width: 16, height: 16 })
                .width(16)
                .height(16)
              }
            }
            .width(Theme.COMPOSER_SEND_SIZE)
            .height(Theme.COMPOSER_SEND_SIZE)
            .justifyContent(FlexAlign.Center)
            .borderRadius(999)
            .backgroundColor(Theme.palette(this.dark).dswAliasButtonInfoFill)
            .opacity(this.streaming || this.canSend() ? 1 : 0.4)
            .translate({ y: -2 })
            .onClick(() => {
              if (this.streaming) {
                this.onStop();
              } else {
                this.doSend();
              }
            })
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({
          left: Theme.COMPOSER_ROW_PADDING_SIDE,
          right: Theme.COMPOSER_ROW_PADDING_SIDE,
          top: Theme.COMPOSER_ROW_PADDING_TOP,
          bottom: Theme.COMPOSER_ROW_PADDING_BOTTOM
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: this.cardWidth() })
      .padding({ top: Theme.COMPOSER_PADDING_TOP })
      .borderRadius(Theme.RADIUS_PANEL)
      .backgroundColor(Theme.palette(this.dark).dswSpecificInputMajor)
      // elevation-soft：发丝描边（l2）+ 两层极淡柔光
      .border({ width: 0.5, color: Theme.palette(this.dark).dswAliasBorderL2 })
      .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.03)', offsetY: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: Theme.COMPOSER_SIDE_CLEARANCE,
      right: Theme.COMPOSER_SIDE_CLEARANCE,
      bottom: this.hero ? 0 : 4
    })
  }

  /**
   * 工作区权限胶囊（ui-permission-presets 的 PermissionSelect trigger）：
   * 权限字形 + 名称 + 下箭头；菜单列出目录里的每一档（✓ 标当前）。
   * 独立模式 / 未连接时置灰并给出原因（不隐藏，避免「找不到入口」）。
   */
  @Builder
  permissionChip() {
    Row({ space: 4 }) {
      this.permissionGlyph()
      Text(this.permissionText())
        .fontSize(Theme.FONT_SECONDARY)
        .lineHeight(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.palette(this.dark).dswAliasLabelSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.permissionBadgeText().length > 0) {
        // 上游 optionBadge：实验档位右上角 EXP 上标
        Text(this.permissionBadgeText())
          .fontSize(9)
          .lineHeight(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.palette(this.dark).dswAliasLabelCaption)
          .translate({ y: -6 })
      }
      IconChevronDownOutline({ size: 12, color: Theme.palette(this.dark).dswAliasLabelCaption })
    }
    .height(Theme.COMPOSER_SELECT_HEIGHT)
    .constraintSize({ maxWidth: Theme.COMPOSER_SELECT_MAX_WIDTH })
    .padding({ left: 8, right: 4 })
    .borderRadius(Theme.RADIUS_SM)
    .margin({ right: 8, bottom: 2 })
    .opacity(this.permissionAvailable ? 1 : 0.4)
    .hoverEffect(HoverEffect.Highlight)
    .bindMenu(this.permissionMenu())
  }

  /**
   * 工作区胶囊（上游 EmptyHero 的 WorkspaceChip，按主人要求搬进工具排）：
   * 目录字形 + 工作区名 + 下箭头；菜单里已有工作区（✓ 标当前）+「选择文件夹…」。
   * 独立模式没有 dsh 会话工作区 → 置灰 + 原因 + 一键切到 dsh 服务模式。
   */
  @Builder
  workspaceChip() {
    Row({ space: 4 }) {
      if (this.workspacePath.length > 0) {
        IconFolderOpen({ size: 16, color: Theme.palette(this.dark).dswAliasLabelSecondary })
      } else {
        IconFolderClose({ size: 16, color: Theme.palette(this.dark).dswAliasLabelSecondary })
      }
      Text(this.workspaceName.length > 0 ? this.workspaceName : '工作区')
        .fontSize(Theme.FONT_SECONDARY)
        .lineHeight(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.palette(this.dark).dswAliasLabelSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      IconChevronDownOutline({ size: 12, color: Theme.palette(this.dark).dswAliasLabelCaption })
    }
    .height(Theme.COMPOSER_SELECT_HEIGHT)
    .constraintSize({ maxWidth: Theme.COMPOSER_SELECT_MAX_WIDTH })
    .padding({ left: 8, right: 4 })
    .borderRadius(Theme.RADIUS_SM)
    .margin({ right: 8, bottom: 2 })
    .opacity(this.workspaceAvailable ? 1 : 0.4)
    .hoverEffect(HoverEffect.Highlight)
    .bindMenu(this.workspaceMenu())
  }

  /**
   * 对话模式胶囊（ui-agent-preset 的 AgentPresetSeat，按主人要求搬进工具排）：
   * 模式字形 + 产品名 + 下箭头；菜单里列出部署可用的每一套（✓ 标当前）。
   * 独立模式下它决定系统提示（rawfile/presets.json 的 persona 前缀）；dsh 服务模式下
   * 是新建会话的 agentPreset。首个回合之后锁定（与上游同语义）。
   */
  @Builder
  presetChip() {
    Row({ space: 4 }) {
      IconAgentPresetOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelSecondary })
      Text(this.presetText())
        .fontSize(Theme.FONT_SECONDARY)
        .lineHeight(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.palette(this.dark).dswAliasLabelSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      IconChevronDownOutline({ size: 12, color: Theme.palette(this.dark).dswAliasLabelCaption })
    }
    .height(Theme.COMPOSER_SELECT_HEIGHT)
    .constraintSize({ maxWidth: Theme.COMPOSER_SELECT_MAX_WIDTH })
    .padding({ left: 8, right: 4 })
    .borderRadius(Theme.RADIUS_SM)
    .margin({ right: 8, bottom: 2 })
    .opacity(this.presetLocked ? 0.4 : 1)
    .hoverEffect(HoverEffect.Highlight)
    .bindMenu(this.presetMenu())
  }

  /** 对话模式胶囊文案：已绑定会话的用会话的，否则用暂存值，都没有则占位。 */
  private presetText(): string {
    if (this.presetLabel.length > 0) {
      return this.presetLabel;
    }
    return '对话模式';
  }

  /** 工作区菜单：已有工作区（✓ 标当前）+「选择文件夹…」 */
  private workspaceMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    if (!this.workspaceAvailable) {
      items.push({
        value: this.workspaceReason.length > 0 ? this.workspaceReason : '当前不可选择工作区',
        enabled: false,
        action: () => {
        }
      });
      if (this.directMode) {
        items.push({
          value: '切换到 dsh 服务模式…',
          action: () => {
            this.onSwitchToDsh();
          }
        });
      }
      return items;
    }
    for (let i = 0; i < this.workspaceOptions.length; i++) {
      const path: string = this.workspaceOptions[i];
      items.push({
        value: (path === this.workspacePath ? '✓ ' : '') + InputBar.basenameOf(path),
        action: () => {
          this.onPickWorkspace(path);
        }
      });
    }
    items.push({
      value: '选择文件夹…',
      action: () => {
        this.onOpenWorkspace();
      }
    });
    return items;
  }

  /** 对话模式菜单：首个回合之前可选，之后锁定（与上游 AgentPresetSeat 同语义）。 */
  private presetMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    if (this.presetLocked) {
      items.push({
        value: '对话已开始，模式不可更改（新建会话后生效）',
        enabled: false,
        action: () => {
        }
      });
      return items;
    }
    if (this.presetIds.length === 0) {
      items.push({
        value: '读取对话模式目录中…',
        enabled: false,
        action: () => {
        }
      });
      return items;
    }
    if (this.presetDescription.length > 0) {
      items.push({
        value: this.presetDescription,
        enabled: false,
        action: () => {
        }
      });
    }
    for (let i = 0; i < this.presetIds.length; i++) {
      const id: string = this.presetIds[i];
      const name: string = i < this.presetNames.length && this.presetNames[i].length > 0
        ? this.presetNames[i] : id;
      items.push({
        value: (name === this.presetText() ? '✓ ' : '') + name,
        action: () => {
          this.onPickPreset(id);
        }
      });
    }
    return items;
  }

  /**
   * 模型菜单（上游 conversation.input.model 座位的鸿蒙等价物）：
   * 独立模式列内置模型，dsh 服务模式列服务端 `session/modelCatalog` 的 provider/model，
   * 选中即切换（dsh 走 `session/selectModel`）；末行是「接口与 API Key…」。
   */
  private modelMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    if (this.modelKeys.length === 0) {
      items.push({
        value: this.modelMenuEmptyText(),
        enabled: false,
        action: () => {
        }
      });
    } else {
      for (let i = 0; i < this.modelKeys.length; i++) {
        const key: string = this.modelKeys[i];
        items.push({
          value: (key === this.modelKey ? '✓ ' : '') + key,
          action: () => {
            this.onPickModel(key);
          }
        });
      }
    }
    items.push({
      value: this.directMode ? '模型与 API Key…' : '模型与连接设置…',
      action: () => {
        this.onOpenModelSettings();
      }
    });
    return items;
  }

  private modelMenuEmptyText(): string {
    if (this.directMode) {
      return '内置模型列表不可用';
    }
    return '服务端模型目录未就绪（连接后自动读取）';
  }

  /** 路径末段（工作区胶囊显示目录名） */
  private static basenameOf(path: string): string {
    const parts: string[] = path.split('/');
    for (let i = parts.length - 1; i >= 0; i--) {
      if (parts[i].length > 0) {
        return parts[i];
      }
    }
    return path;
  }

  /** 权限字形：read-only / workspace-write / danger-full-access 各一枚（其余档位不画图标）。 */
  @Builder
  permissionGlyph() {
    if (this.permissionLabel === 'read-only') {
      PermissionIconReadOnly({ size: 14, color: Theme.palette(this.dark).dswAliasLabelSecondary })
    } else if (this.permissionLabel === 'workspace-write') {
      PermissionIconWorkspaceWrite({ size: 14, color: Theme.palette(this.dark).dswAliasLabelSecondary })
    } else if (this.permissionLabel === 'danger-full-access') {
      PermissionIconFullAccess({ size: 14, color: Theme.palette(this.dark).dswAliasLabelSecondary })
    }
  }

  /** 胶囊文案：机器值 → 产品显示名（上游 displayPermissionPreset） */
  private permissionText(): string {
    return this.permissionLabel.length > 0 ? Constants.permissionLabel(this.permissionLabel) : '工作区权限';
  }

  /** EXP 徽章（仅 auto 档位） */
  private permissionBadgeText(): string {
    return this.permissionLabel.length > 0 ? Constants.permissionBadge(this.permissionLabel) : '';
  }

  private permissionMenu(): MenuElement[] {
    const items: MenuElement[] = [];
    if (!this.permissionAvailable) {
      items.push({
        value: this.permissionReason.length > 0
          ? this.permissionReason
          : '当前不可切换工作区权限',
        enabled: false,
        action: () => {
        }
      });
      if (this.directMode) {
        items.push({
          value: '切换到 dsh 服务模式…',
          action: () => {
            this.onSwitchToDsh();
          }
        });
      }
      return items;
    }
    if (this.permissionOptions.length === 0) {
      items.push({
        value: '读取权限目录中…',
        enabled: false,
        action: () => {
        }
      });
      return items;
    }
    for (let i = 0; i < this.permissionOptions.length; i++) {
      const preset: string = this.permissionOptions[i];
      const badge: string = Constants.permissionBadge(preset);
      items.push({
        value: (preset === this.permissionLabel ? '✓ ' : '')
          + Constants.permissionLabel(preset) + (badge.length > 0 ? '  ' + badge : ''),
        action: () => {
          this.onPickPermission(preset);
        }
      });
    }
    return items;
  }

  private doSend(): void {
    const text: string = this.input.trim();
    if (text.length === 0 || this.streaming || !this.connected) {
      return;
    }
    this.onSend(text);
    this.input = '';
  }
}

/** 发送箭头（上游 InputBar primary 内联 svg，viewBox 0 0 16 16）。 */
const SEND_ARROW_PATH: string =
  'M8.3125 0.980183C8.66767 1.0531 8.97902 1.20418 9.2627 1.43233C9.48724 1.61297 9.73029 1.85793 9.97949 2.10714L14.707 6.83468L13.293 8.24874L9 3.95577V15.0417H7V3.95577L2.70703 8.24874L1.29297 6.83468L6.02051 2.10714C6.26971 1.85793 6.51277 1.61297 6.7373 1.43233C6.97662 1.23986 7.28445 1.04402 7.6875 0.980183C7.8973 0.947006 8.1031 0.95516 8.3125 0.980183Z';
