/**
 * DesktopMenuBar：Windows 形态窗口标题栏（上游 apps/desktop/src/preload-menu.ts + preload-windows.ts
 * 的鸿蒙等价物）。几何逐条对齐：栏高 40（WINDOWS_TITLEBAR_HEIGHT）、菜单起始 x 48（收起侧栏时 84）、
 * 菜单项 28 高 / 左右内边距 10 / 圆角 6 / 14px --dsw-alias-label-secondary，
 * 悬停或展开时填充 --dsw-alias-interactive-bg-hover 并转 --dsw-alias-label-primary；
 * 右端补上系统标题栏按钮（最小化 / 最大化 / 关闭），关闭走既有的退出确认。
 *
 * 结构与文案取自 desktop-shell.json（契约）+ DesktopCopy（语言表），快捷键提示来自 ShortcutRegistry，
 * 因此菜单里写的键位与真实注册的键位永远一致。
 */
import { MenuItemSpec, MenuSpec, ShortcutSpec } from '../desktop/DesktopShellContract';
import { DESKTOP_ZH, DesktopMessages } from '../desktop/DesktopCopy';
import { desktopLabel } from '../desktop/DesktopLabels';
import { ShortcutRegistry } from '../desktop/ShortcutRegistry';
import { Theme } from '../common/Theme';
import {
  IconCloseFill, IconFullscreenOutline, IconNewChatOutline, IconNowrapFill, IconPanelLeftOutline,
} from '../common/Icons';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/** 标题栏高度（vp），等于上游 --dsh-windows-titlebar-height。 */
export const DESKTOP_MENUBAR_HEIGHT: number = Theme.WINDOWS_TITLEBAR_HEIGHT;

@Component
export struct DesktopMenuBar {
  menus: MenuSpec[] = [];
  shortcuts: ShortcutSpec[] = [];
  messages: DesktopMessages = DESKTOP_ZH;
  /** 当前展开的菜单 id，'' 表示全部收起 */
  openMenuId: string = '';
  /** 菜单起始 x（--dsh-windows-menu-start） */
  menuStart: number = Theme.WINDOWS_MENU_START;
  /** 上报每个菜单按钮的窗口坐标（供下拉层定位） */
  onMenuMeasure: (menuId: string, x: number) => void = (menuId: string, x: number) => {};
  onToggle: (menuId: string) => void = (menuId: string) => {};
  /** 侧栏是否收起（收起时标题栏左端多一个 28 号的新建会话控制盒） */
  collapsed: boolean = false;
  /** 窗口是否已最大化（同一按键切换最大化/还原，字形随之翻转） */
  maximized: boolean = false;
  onToggleSidebar: () => void = () => {};
  onNewSession: () => void = () => {};
  onMinimize: () => void = () => {};
  onToggleMaximize: () => void = () => {};
  onClose: () => void = () => {};
  @StorageProp('dshDarkTheme') dark: boolean = true;
  /** 指针悬停的菜单 id（上游 button:hover 与展开态同一填充）。 */
  @State hoverMenuId: string = '';
  /** 指针悬停的标题栏左端控制盒（'' / 'toggle' / 'new'）。 */
  @State hoverLeading: string = '';
  /** 指针悬停的窗口三键（'' / 'min' / 'max' / 'close'）。 */
  @State hoverCaption: string = '';

  build() {
    Row() {
      // 标题栏左端（上游 .toggle：固定在 x=12 的 28x28 盒；收起时 .newSession 落在 x=48）
      Row({ space: 8 }) {
        Row() {
          IconPanelLeftOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelSecondary })
        }
        .width(28)
        .height(28)
        .justifyContent(FlexAlign.Center)
        // 收起态上游把这两个控制盒画成圆（.collapsed .toggle / .newSession）
        .borderRadius(this.collapsed ? 999 : Theme.RADIUS_SM)
        .backgroundColor(this.leadingFill('toggle'))
        .onHover((isHover: boolean) => {
          this.hoverLeading = isHover ? 'toggle' : (this.hoverLeading === 'toggle' ? '' : this.hoverLeading);
        })
        .onClick(() => {
          this.onToggleSidebar();
        })

        if (this.collapsed) {
          Row() {
            IconNewChatOutline({ size: 16, color: Theme.palette(this.dark).dswAliasLabelSecondary })
          }
          .width(28)
          .height(28)
          .justifyContent(FlexAlign.Center)
          .borderRadius(999)
          .backgroundColor(this.leadingFill('new'))
          .onHover((isHover: boolean) => {
            this.hoverLeading = isHover ? 'new' : (this.hoverLeading === 'new' ? '' : this.hoverLeading);
          })
          .onClick(() => {
            this.onNewSession();
          })
        }
      }
      .padding({ left: 12 })
      .margin({ right: this.menuStart - (this.collapsed ? 76 : 40) })
      .alignItems(VerticalAlign.Center)

      Row({ space: 2 }) {
        ForEach(this.menus, (menu: MenuSpec) => {
          Text(desktopLabel(this.messages, menu.labelKey))
            .fontSize(Theme.FONT_ROW)
            .fontColor(this.menuActive(menu.id)
              ? Theme.palette(this.dark).dswAliasLabelPrimary
              : Theme.palette(this.dark).dswAliasLabelSecondary)
            .height(Theme.CAPTION_MENU_HEIGHT)
            .padding({ left: Theme.CAPTION_MENU_PADDING, right: Theme.CAPTION_MENU_PADDING })
            .borderRadius(Theme.CAPTION_MENU_RADIUS)
            .backgroundColor(this.menuActive(menu.id)
              ? Theme.palette(this.dark).dswAliasInteractiveBgHover
              : Color.Transparent)
            .onHover((isHover: boolean) => {
              if (isHover) {
                this.hoverMenuId = menu.id;
              } else if (this.hoverMenuId === menu.id) {
                this.hoverMenuId = '';
              }
            })
            .onClick(() => {
              this.onToggle(menu.id);
            })
            .onAreaChange((oldArea: Area, newArea: Area) => {
              const raw: Length | undefined = newArea.globalPosition.x;
              if (raw === undefined) {
                return;
              }
              const x: number = Number(raw.toString());
              this.onMenuMeasure(menu.id, Number.isFinite(x) ? x : 0);
            })
        }, (menu: MenuSpec) => menu.id)
      }
      .alignItems(VerticalAlign.Center)

      // 拖动区（Windows 标题栏的等价物）：仅空白处按下时拖动窗口，按钮区域保持点击语义
      Row()
        .layoutWeight(1)
        .height(DESKTOP_MENUBAR_HEIGHT)
        .onTouch((event: TouchEvent) => {
          // startMoving 起于 API 14（低版本设备由系统标题栏承担拖动，这里静默跳过）
          if (event.type !== TouchType.Down || deviceInfo.sdkApiVersion < 14) {
            return;
          }
          const host = this.getUIContext().getHostContext() as common.UIAbilityContext;
          if (host === undefined || host === null) {
            return;
          }
          window.getLastWindow(host).then((win: window.Window) => {
            win.startMoving();
          }).catch(() => {
          });
        })

      // 窗口按钮（Windows 系统标题栏的鸿蒙等价物）
      Row() {
        Row() {
          IconNowrapFill({ size: 10, color: Theme.palette(this.dark).dswAliasLabelPrimary })
        }
        .width(46)
        .height(DESKTOP_MENUBAR_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.captionFill('min'))
        .onHover((isHover: boolean) => {
          this.setCaptionHover('min', isHover);
        })
        .onClick(() => {
          this.onMinimize();
        })

        Row() {
          // 已最大化时把同一份「展开」字形旋转 180° 当作「还原」（上游这枚键由 Windows 系统绘制，
          // 图标集里没有单独的还原字形，复用上游字形比另造一枚更贴合设计源）
          Row() {
            IconFullscreenOutline({ size: 14, color: Theme.palette(this.dark).dswAliasLabelPrimary })
          }
          .rotate({ angle: this.maximized ? 180 : 0 })
        }
        .width(46)
        .height(DESKTOP_MENUBAR_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.captionFill('max'))
        .onHover((isHover: boolean) => {
          this.setCaptionHover('max', isHover);
        })
        .onClick(() => {
          this.onToggleMaximize();
        })

        Row() {
          IconCloseFill({ size: 12, color: Theme.palette(this.dark).dswAliasLabelPrimary })
        }
        .width(46)
        .height(DESKTOP_MENUBAR_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.closeFill)
        .onClick(() => {
          this.onClose();
        })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(DESKTOP_MENUBAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Theme.palette(this.dark).dswSpecificSidebarFill)
  }

  /** 左端控制盒填充（.iconButton:hover = interactive-bg-hover）。 */
  private leadingFill(key: string): ResourceColor {
    return this.hoverLeading === key
      ? Theme.palette(this.dark).dswAliasInteractiveBgHover
      : Color.Transparent;
  }

  /** 展开或悬停：上游 button:hover / button[aria-expanded=true] 同一填充。 */
  private menuActive(menuId: string): boolean {
    return this.openMenuId === menuId || this.hoverMenuId === menuId;
  }

  /** 关闭键底色（Windows 11 关闭键的固定红；其余两键默认透明）。 */
  private get closeFill(): ResourceColor {
    return '#C42B1C';
  }

  /** 最小化/最大化悬停填充（与菜单项、左端控制盒同一枚交互色）。 */
  private captionFill(key: string): ResourceColor {
    return this.hoverCaption === key ? Theme.palette(this.dark).dswAliasInteractiveBgHover : Color.Transparent;
  }

  private setCaptionHover(key: string, isHover: boolean): void {
    this.hoverCaption = isHover ? key : (this.hoverCaption === key ? '' : this.hoverCaption);
  }
}

@Component
export struct DesktopMenuDropdown {
  menu: MenuSpec = new MenuSpec('', '');
  shortcuts: ShortcutSpec[] = [];
  messages: DesktopMessages = DESKTOP_ZH;
  onAction: (itemId: string) => void = (itemId: string) => {};
  @StorageProp('dshDarkTheme') dark: boolean = true;
  /** 指针悬停的项序号（上游菜单项 hover = interactive-bg-hover）。 */
  @State hoverIndex: number = -1;

  build() {
    Column() {
      ForEach(this.menu.items, (item: MenuItemSpec, index: number) => {
        if (item.separator) {
          Divider()
            .color(Theme.palette(this.dark).dswAliasBorderL3)
            .margin({ top: 4, bottom: 4 })
        } else {
          Row() {
            Text(desktopLabel(this.messages, item.labelKey))
              .fontSize(Theme.FONT_ROW)
              .lineHeight(Theme.LINE_ROW)
              .fontColor(Theme.palette(this.dark).dswAliasLabelPrimary)
              .layoutWeight(1)
            if (item.shortcutId.length > 0) {
              Text(this.hint(item.shortcutId))
                .fontSize(Theme.FONT_SMALL)
                .fontColor(Theme.palette(this.dark).dswAliasLabelTertiary)
                .margin({ left: 16 })
            }
          }
          .width('100%')
          .height(30)
          .padding({ left: 12, right: 12 })
          .borderRadius(Theme.RADIUS_SM)
          .backgroundColor(this.hoverIndex === index
            ? Theme.palette(this.dark).dswAliasInteractiveBgHover
            : Color.Transparent)
          .onHover((isHover: boolean) => {
            if (isHover) {
              this.hoverIndex = index;
            } else if (this.hoverIndex === index) {
              this.hoverIndex = -1;
            }
          })
          .onClick(() => {
            this.onAction(item.id);
          })
        }
      }, (item: MenuItemSpec, index: number) => index.toString() + '-' + item.id)
    }
    .width(248)
    .padding(6)
    // 菜单面：--dsw-specific-menu + --dsw-elevation-panel 的发丝描边与柔光
    .backgroundColor(Theme.palette(this.dark).dswSpecificMenu)
    .borderRadius(Theme.RADIUS_LG)
    .border({ width: 0.5, color: Theme.palette(this.dark).dswAliasBorderL1 })
    .shadow({ radius: 24, color: 'rgba(0, 0, 0, 0.12)', offsetY: 8 })
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
  }

  /** 快捷键提示文本（无绑定返回空）。 */
  private hint(shortcutId: string): string {
    for (let i = 0; i < this.shortcuts.length; i++) {
      const spec: ShortcutSpec = this.shortcuts[i];
      if (spec.id === shortcutId) {
        return ShortcutRegistry.presentDefault(spec);
      }
    }
    return '';
  }
}
