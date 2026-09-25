/**
 * Sidebar：左侧栏。逐条对齐上游开源实现
 * packages/client/ui-sidebar/src/client/SidebarRoot.module.css：
 * 列填充 --dsw-specific-sidebar-fill、右缘 0.5px border-l3、内边距 6/12、
 * 品牌排（鲸鱼 + 官方字标 + 折叠开关）/ 新建会话 38 / 会话区 / 脚部设置 42；
 * 折叠态是同文件定义的 56px 图标轨道（.root.collapsed，36x36 控制盒）。
 */
import { Theme } from '../common/Theme';
import { FishMark } from '../common/Brand';
import { DshSession } from '../model/Types';
import {
  IconBrandFull, IconChatLinesOutline, IconFolderOpen, IconNewChatOutline,
  IconSettingsOutline, IconTreeCorner,
} from '../common/Icons';

@Component
export struct Sidebar {
  @Link sessions: DshSession[];
  @Prop currentSessionId: string = '';
  @Prop connected: boolean = false;
  @Prop collapsed: boolean = false;
  /** 系统标题栏仍可见（藏不掉）时不再自绘品牌标：系统那栏已经画了同一枚图标 + 名称 */
  @Prop hideBrand: boolean = false;
  @Prop workspaceName: string = '';
  onSelect: (id: string) => void = (id: string) => {};
  onNew: () => void = () => {};
  onSettings: () => void = () => {};
  onToggle: () => void = () => {};
  @StorageProp('dshDarkTheme') dark: boolean = true;
  /** 指针悬停的行键（上游各排 :hover 填充 --dsw-alias-interactive-bg-hover）。 */
  @State hoverKey: string = '';

  build() {
    Column() {
      if (this.collapsed) {
        this.rail()
      } else {
        if (!this.hideBrand) {
          this.brandRow()
        }
        this.newSession()
        this.sessionRegion()
        this.foot()
      }
    }
    .width(this.collapsed ? Theme.SIDEBAR_COLLAPSED : Theme.SIDEBAR_DEFAULT)
    .height('100%')
    .padding(this.collapsed
      ? { top: 18, bottom: 6, left: 10, right: 10 }
      : {
        top: 6, bottom: 6,
        left: Theme.SIDEBAR_INLINE_PADDING, right: Theme.SIDEBAR_INLINE_PADDING
      })
    .backgroundColor(Theme.palette(this.dark).dswSpecificSidebarFill)
    .border({ width: { right: 0.5 }, color: Theme.palette(this.dark).dswAliasBorderL3 })
  }

  /**
   * 品牌排（.logoRow：Windows 标题栏形态 40 高 / margin 0 / 品牌身份左内边距 4）。
   * 开合控制在标题栏左端（DesktopMenuBar），这里只放品牌标。
   *
   * ⚠️ 只用 `IconBrandFull` 一幅（上游 BrandWordmark 含鲸鱼的整幅，viewBox 0 0 182 24）：
   * 之前是「FishMark 一枚 + includeMark=false 字标一枚」两个 Shape 叠着画，出过同一头鲸鱼
   * 出现两次的重影问题。整幅一次画完，几何与上游一致，也不存在第二次绘制。
   * 尺寸见 Theme.BRAND_NAME_HEIGHT（鲸鱼随整幅等比，约 0.97 × height）。
   */
  @Builder
  brandRow() {
    Row() {
      IconBrandFull({
        size: Theme.BRAND_NAME_HEIGHT,
        color: Theme.palette(this.dark).dswAliasLabelPrimary,
        alt: Theme.palette(this.dark).dswAliasLabelPrimaryInverted,
      })
    }
    .width('100%')
    .height(Theme.WINDOWS_TITLEBAR_HEIGHT)
    .padding({ left: 4 })
    .margin({ bottom: 8 })
  }

  /** 新建会话（.newSession：38 高 / 圆角 12 / elevated 填充 + 半像素描边）。 */
  @Builder
  newSession() {
    Row({ space: 6 }) {
      IconNewChatOutline({
        size: 16,
        color: Theme.palette(this.dark).dswAliasLabelPrimary,
        strokeWidth: 1.3,
      })
      Text('新会话')
        .fontSize(Theme.FONT_ROW)
        .fontWeight(FontWeight.Medium)
        .lineHeight(Theme.LINE_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
    }
    .width('100%')
    .height(Theme.NEW_SESSION_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .margin({ left: 2, right: 2, bottom: 12 })
    .borderRadius(Theme.RADIUS_MD)
    .border({ width: 0.5, color: Theme.palette(this.dark).dswAliasBorderL3 })
    .backgroundColor(this.hoverFill('new', Theme.palette(this.dark).dswAliasButtonElevatedFill))
    .onHover((isHover: boolean) => {
      this.setHover('new', isHover);
    })
    .onClick(() => {
      this.onNew();
    })
  }

  /** 会话区（工作区行 34 + 会话行 32，选中填充 = interactive-bg-hover）。 */
  @Builder
  sessionRegion() {
    Column() {
      Row({ space: Theme.ROW_GAP }) {
        IconFolderOpen({ size: 16, color: Theme.palette(this.dark).dswAliasLabelTertiary })
        Text(this.workspaceName.length > 0 ? this.workspaceName : '工作区')
          .fontSize(Theme.FONT_ROW)
          .lineHeight(20)
          .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(Theme.PROJECT_ROW_HEIGHT)
      .padding({ left: Theme.ROW_SIDE_PADDING, right: Theme.ROW_SIDE_PADDING })
      .borderRadius(Theme.RADIUS_MD)
      .backgroundColor(this.hoverFill('project', Color.Transparent))
      .onHover((isHover: boolean) => {
        this.setHover('project', isHover);
      })

      if (this.sessions.length === 0) {
        Row() {
          Text('还没有会话')
            .fontSize(Theme.FONT_SECONDARY)
            .lineHeight(Theme.LINE_SECONDARY)
            .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
        }
        .width('100%')
        .height(Theme.SESSION_ROW_HEIGHT)
        .padding({ left: 24, right: Theme.ROW_SIDE_PADDING })
      } else {
        List() {
          ForEach(this.sessions, (item: DshSession) => {
            ListItem() {
              this.sessionRow(item)
            }
          }, (item: DshSession) => item.sessionId)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
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

  @Builder
  sessionRow(item: DshSession) {
    Row() {
      // 行内缩进 16（--dsh-workspace-indent）+ 16px 槽 + 4px 标题间距（.sessionRow）。
      Row() {
        IconTreeCorner({ size: 11, color: Theme.palette(this.dark).dswAliasLabelTertiary })
      }
      .width(16)
      .justifyContent(FlexAlign.Center)

      Text(item.title.length > 0 ? item.title : '新会话')
        .fontSize(Theme.FONT_ROW)
        .lineHeight(20)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 4, right: 6 })

      if (item.running) {
        this.dot(Theme.palette(this.dark).dswAliasStateBusinessPrimary)
      } else if (item.updatedAt > 0) {
        Text(this.timeLabel(item.updatedAt))
          .fontSize(10)
          .lineHeight(16)
          .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
      }
    }
    .width('100%')
    .height(Theme.SESSION_ROW_HEIGHT)
    .padding({ left: 8, right: Theme.ROW_SIDE_PADDING })
    .borderRadius(Theme.RADIUS_MD)
    .backgroundColor(this.hoverFill('session:' + item.sessionId,
      item.sessionId === this.currentSessionId
        ? Theme.palette(this.dark).dswAliasInteractiveBgHover
        : Color.Transparent))
    .onHover((isHover: boolean) => {
      this.setHover('session:' + item.sessionId, isHover);
    })
    .onClick(() => {
      this.onSelect(item.sessionId);
    })
  }

  /** 脚部设置入口（SettingsRoot .trigger：42 高 / 图标 16 / 14-22 文本）。 */
  @Builder
  foot() {
    Row({ space: 8 }) {
      IconSettingsOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelPrimary })
      Text('设置')
        .fontSize(Theme.FONT_ROW)
        .lineHeight(Theme.LINE_ROW)
        .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
        .layoutWeight(1)
      this.dot(this.connected
        ? Theme.palette(this.dark).dswAliasStateSuccessPrimary
        : Theme.palette(this.dark).dswAliasStateErrorPrimary)
    }
    .width('100%')
    .height(Theme.SETTINGS_TRIGGER_HEIGHT)
    .padding({ left: 8, right: 10, top: 9, bottom: 9 })
    .borderRadius(Theme.RADIUS_MD)
    .backgroundColor(this.hoverFill('foot', Color.Transparent))
    .onHover((isHover: boolean) => {
      this.setHover('foot', isHover);
    })
    .onClick(() => {
      this.onSettings();
    })
  }

  /** 折叠轨道（.root.collapsed：36x36 控制盒、12px 竖向节奏、悬停 interactive-bg-hover）。 */
  @Builder
  rail() {
    Column({ space: 12 }) {
      Row() {
        FishMark({ size: 24, color: Theme.palette(this.dark).dswAliasLabelPrimary })
      }
      .margin({ bottom: 6 })

      Row() {
        IconChatLinesOutline({ size: 18, color: Theme.palette(this.dark).dswAliasLabelPrimary })
      }
      .width(Theme.CONTROL_BOX)
      .height(Theme.CONTROL_BOX)
      .justifyContent(FlexAlign.Center)
      .borderRadius(Theme.RADIUS_MD)
      .backgroundColor(this.hoverFill('rail-list', Color.Transparent))
      .onHover((isHover: boolean) => {
        this.setHover('rail-list', isHover);
      })
      .onClick(() => {
        // 折叠态下这一格就是「展开侧栏看会话列表」（上游 rail 的同一入口）
        this.onToggle();
      })

      Blank()

      Row() {
        IconSettingsOutline({ size: 18, color: Theme.palette(this.dark).dswAliasLabelPrimary })
      }
      .width(Theme.CONTROL_BOX)
      .height(Theme.CONTROL_BOX)
      .justifyContent(FlexAlign.Center)
      .borderRadius(Theme.RADIUS_MD)
      .backgroundColor(this.hoverFill('rail-settings', Color.Transparent))
      .onHover((isHover: boolean) => {
        this.setHover('rail-settings', isHover);
      })
      .onClick(() => {
        this.onSettings();
      })

    }
    .width('100%')
    .height('100%')
  }

  /** 行填充：悬停行 → interactive-bg-hover（新建会话是 button-floating-hover），其余沿用基准色。 */
  private hoverFill(key: string, base: ResourceColor): ResourceColor {
    if (this.hoverKey !== key) {
      return base;
    }
    return key === 'new'
      ? Theme.palette(this.dark).dswAliasButtonFloatingHover
      : Theme.palette(this.dark).dswAliasInteractiveBgHover;
  }

  /** 悬停进出：离开只清自己的键，避免快速移动时把刚进入的行清掉。 */
  private setHover(key: string, isHover: boolean): void {
    if (isHover) {
      this.hoverKey = key;
      return;
    }
    if (this.hoverKey === key) {
      this.hoverKey = '';
    }
  }

  private timeLabel(ts: number): string {
    const d: Date = new Date(ts);
    const now: Date = new Date();
    const pad = (n: number): string => {
      return n < 10 ? '0' + n.toString() : n.toString();
    };
    if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()) {
      return pad(d.getHours()) + ':' + pad(d.getMinutes());
    }
    return (d.getMonth() + 1).toString() + '/' + d.getDate().toString();
  }
}
