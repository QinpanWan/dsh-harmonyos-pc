/**
 * DesktopLabels：把契约里的 labelKey 解析成当前语言的文案。
 *
 * 为什么不让 UI 直接读字段：菜单结构来自 `desktop-shell.json`（数据），文案来自语言表（DesktopCopy）。
 * 两者用「键」解耦，新增菜单项时只动 JSON + 语言表，不动 UI 代码。
 */
import { DesktopMessages } from './DesktopCopy';

/** 键 → 文案；未知键原样返回（便于发现契约与语言表不同步）。 */
export function desktopLabel(messages: DesktopMessages, key: string): string {
  switch (key) {
    case 'application': return messages.application;
    case 'edit': return messages.edit;
    case 'viewMenu': return messages.viewMenu;
    case 'helpMenu': return messages.helpMenu;
    case 'fileMenu': return messages.fileMenu;
    case 'closePage': return messages.closePage;
    case 'aboutMenu': return messages.aboutMenu;
    case 'aboutProduct': return messages.aboutProduct;
    case 'aboutVersion': return messages.aboutVersion;
    case 'hideApplication': return messages.hideApplication;
    case 'hideOtherApplications': return messages.hideOtherApplications;
    case 'showAllApplications': return messages.showAllApplications;
    case 'quitApplication': return messages.quitApplication;
    case 'openApplication': return messages.openApplication;
    case 'quit': return messages.quit;
    case 'cancel': return messages.cancel;
    case 'delete': return messages.delete;
    case 'undo': return messages.undo;
    case 'redo': return messages.redo;
    case 'cut': return messages.cut;
    case 'copy': return messages.copy;
    case 'paste': return messages.paste;
    case 'selectAll': return messages.selectAll;
    case 'quitTitle': return messages.quitTitle;
    case 'quitActiveTasks': return messages.quitActiveTasks;
    case 'quitScheduledTasks': return messages.quitScheduledTasks;
    case 'quitActiveAndScheduledTasks': return messages.quitActiveAndScheduledTasks;
    case 'backgroundNoticeBody': return messages.backgroundNoticeBody;
    case 'backgroundNoticeConfirm': return messages.backgroundNoticeConfirm;
    case 'checkUpdatesMenu': return messages.checkUpdatesMenu;
    case 'reloadPageMenu': return messages.reloadPageMenu;
    case 'restartAppHostMenu': return messages.restartAppHostMenu;
    case 'toggleFullscreenMenu': return messages.toggleFullscreenMenu;
    case 'openDownloadPageMenu': return messages.openDownloadPageMenu;
    case 'updateTitle': return messages.updateTitle;
    case 'updateChecking': return messages.updateChecking;
    case 'updateCheckTitle': return messages.updateCheckTitle;
    case 'updateCurrent': return messages.updateCurrent;
    case 'updateAvailable': return messages.updateAvailable;
    case 'updateDetail': return messages.updateDetail;
    case 'updateCheckFailedTitle': return messages.updateCheckFailedTitle;
    case 'updateCheckFailed': return messages.updateCheckFailed;
    case 'updateCheckNetworkFailed': return messages.updateCheckNetworkFailed;
    case 'updateInstallFailed': return messages.updateInstallFailed;
    case 'updateTechnicalDetails': return messages.updateTechnicalDetails;
    case 'updateDownload': return messages.updateDownload;
    case 'updateLater': return messages.updateLater;
    case 'startupFailed': return messages.startupFailed;
    case 'startupAddressInUse': return messages.startupAddressInUse;
    case 'unknownError': return messages.unknownError;
    case 'pickDirectoryTitle': return messages.pickDirectoryTitle;
    case 'pickDirectoryFailed': return messages.pickDirectoryFailed;
    default: return key;
  }
}
