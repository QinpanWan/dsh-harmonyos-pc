/**
 * DesktopCopy：桌面壳自有文案（中/英双语）。
 *
 * 上游 `apps/desktop/src/locale.ts` 里 341 行文案是「壳负责的文字」——菜单、关于、退出确认、
 * 托盘、欢迎登录、更新全状态。鸿蒙壳照搬同一套语义，只保留壳层真正会用到的键，
 * 保证同一产品在两个平台上说的是同一句话（译文逐字对齐上游 zh/en）。
 */
export class DesktopMessages {
  // —— 菜单 ——
  application: string = '';
  edit: string = '';
  viewMenu: string = '';
  helpMenu: string = '';
  fileMenu: string = '';
  closePage: string = '';
  aboutMenu: string = '';
  aboutProduct: string = '';
  aboutVersion: string = '';
  hideApplication: string = '';
  hideOtherApplications: string = '';
  showAllApplications: string = '';
  quitApplication: string = '';
  openApplication: string = '';
  quit: string = '';
  cancel: string = '';
  delete: string = '';
  undo: string = '';
  redo: string = '';
  cut: string = '';
  copy: string = '';
  paste: string = '';
  selectAll: string = '';
  // —— 退出确认 / 后台 ——
  quitTitle: string = '';
  quitActiveTasks: string = '';
  quitScheduledTasks: string = '';
  quitActiveAndScheduledTasks: string = '';
  backgroundNoticeBody: string = '';
  backgroundNoticeConfirm: string = '';
  // —— 更新 ——
  checkUpdatesMenu: string = '';
  reloadPageMenu: string = '';
  restartAppHostMenu: string = '';
  toggleFullscreenMenu: string = '';
  openDownloadPageMenu: string = '';
  updateTitle: string = '';
  updateChecking: string = '';
  updateCheckTitle: string = '';
  updateCurrent: string = '';
  updateAvailable: string = '';
  updateDetail: string = '';
  updateCheckFailedTitle: string = '';
  updateCheckFailed: string = '';
  updateCheckNetworkFailed: string = '';
  updateInstallFailed: string = '';
  updateTechnicalDetails: string = '';
  updateDownload: string = '';
  updateLater: string = '';
  // —— 崩溃 / 互斥 ——
  startupFailed: string = '';
  startupAddressInUse: string = '';
  unknownError: string = '';
  // —— 桌面目录 ——
  pickDirectoryTitle: string = '';
  pickDirectoryFailed: string = '';
}

/** 简体中文（与上游 `locale.ts > zh` 逐字一致）。 */
export const DESKTOP_ZH: DesktopMessages = {
  application: '应用',
  edit: '编辑',
  viewMenu: '视图',
  helpMenu: '帮助',
  fileMenu: '文件',
  closePage: '关闭页面或窗口',
  aboutMenu: '关于 DeepSeek Harness',
  aboutProduct: 'DeepSeek Harness',
  aboutVersion: '版本 V{version}',
  hideApplication: '隐藏 DeepSeek Harness',
  hideOtherApplications: '隐藏其他',
  showAllApplications: '显示全部',
  quitApplication: '退出 DeepSeek Harness',
  openApplication: '打开 DeepSeek Harness',
  quit: '退出',
  cancel: '取消',
  delete: '删除',
  undo: '撤销',
  redo: '重做',
  cut: '剪切',
  copy: '复制',
  paste: '粘贴',
  selectAll: '全选',
  quitTitle: '退出 DeepSeek Harness？',
  quitActiveTasks: '当前正在运行的任务将会中断',
  quitScheduledTasks: '应用关闭期间，定时任务不会运行',
  quitActiveAndScheduledTasks: '当前正在运行的任务将会中断，且应用关闭期间，定时任务不会运行',
  backgroundNoticeBody: '正在运行的任务不会中断，可在系统托盘中重新打开窗口',
  backgroundNoticeConfirm: '确认',
  checkUpdatesMenu: '检查更新…',
  reloadPageMenu: '刷新页面',
  restartAppHostMenu: '重启应用与 Host',
  toggleFullscreenMenu: '切换全屏',
  openDownloadPageMenu: '前往官网下载',
  updateTitle: 'DeepSeek Harness 更新',
  updateChecking: '正在检查更新…',
  updateCheckTitle: '检查更新',
  updateCurrent: '当前暂无可用更新。当前版本：V{version}',
  updateAvailable: '发现可用更新',
  updateDetail: 'DeepSeek Harness {version}\n\nDeepSeek Harness 将重启以完成更新。',
  updateCheckFailedTitle: '更新检查失败',
  updateCheckFailed: '检查更新失败，请稍后重试。',
  updateCheckNetworkFailed: '检查更新失败，请稍后重试。网络连接异常，请检查网络后重试。',
  updateInstallFailed: '安装更新失败，请稍后重试。',
  updateTechnicalDetails: '查看技术详情',
  updateDownload: '下载更新',
  updateLater: '稍后',
  startupFailed: 'DeepSeek Harness 无法使用',
  startupAddressInUse: '有其他正在运行的 DSH（如其他 dsh web、桌面端），无法同时启动，请退出其他正在运行的 DSH 后重启。',
  unknownError: '未知错误',
  pickDirectoryTitle: '选择工作目录',
  pickDirectoryFailed: '无法选择目录，请稍后重试。'
};

/** English（与上游 `locale.ts > en` 逐字一致）。 */
export const DESKTOP_EN: DesktopMessages = {
  application: 'Application',
  edit: 'Edit',
  viewMenu: 'View',
  helpMenu: 'Help',
  fileMenu: 'File',
  closePage: 'Close Page or Window',
  aboutMenu: 'About DeepSeek Harness',
  aboutProduct: 'DeepSeek Harness',
  aboutVersion: 'Version V{version}',
  hideApplication: 'Hide DeepSeek Harness',
  hideOtherApplications: 'Hide Others',
  showAllApplications: 'Show All',
  quitApplication: 'Quit DeepSeek Harness',
  openApplication: 'Open DeepSeek Harness',
  quit: 'Quit',
  cancel: 'Cancel',
  delete: 'Delete',
  undo: 'Undo',
  redo: 'Redo',
  cut: 'Cut',
  copy: 'Copy',
  paste: 'Paste',
  selectAll: 'Select All',
  quitTitle: 'Quit DeepSeek Harness?',
  quitActiveTasks: 'Running tasks will be interrupted.',
  quitScheduledTasks: 'Scheduled tasks will not run while the app is closed.',
  quitActiveAndScheduledTasks: 'Running tasks will be interrupted, and scheduled tasks will not run while the app is closed.',
  backgroundNoticeBody: 'Running tasks will continue. You can reopen the window from the system tray.',
  backgroundNoticeConfirm: 'Confirm',
  checkUpdatesMenu: 'Check for Updates…',
  reloadPageMenu: 'Reload Page',
  restartAppHostMenu: 'Restart App and Host',
  toggleFullscreenMenu: 'Toggle Full Screen',
  openDownloadPageMenu: 'Open Download Page',
  updateTitle: 'DeepSeek Harness Update',
  updateChecking: 'Checking for updates…',
  updateCheckTitle: 'Check for Updates',
  updateCurrent: 'DeepSeek Harness is up to date. Current version: V{version}',
  updateAvailable: 'Update available',
  updateDetail: 'DeepSeek Harness {version}\n\nDeepSeek Harness will restart to finish updating.',
  updateCheckFailedTitle: 'Update Check Failed',
  updateCheckFailed: 'Could not check for updates. Please try again later.',
  updateCheckNetworkFailed: 'Could not check for updates. Please try again later. The connection was interrupted. Check your network and try again.',
  updateInstallFailed: 'Could not install the update. Please try again later.',
  updateTechnicalDetails: 'View technical details',
  updateDownload: 'Download Update',
  updateLater: 'Later',
  startupFailed: 'DeepSeek Harness is unavailable',
  startupAddressInUse: 'Another DSH instance (such as dsh web or the desktop app) is running. They cannot start at the same time. Quit the other running DSH instance, then restart.',
  unknownError: 'Unknown error',
  pickDirectoryTitle: 'Choose Working Directory',
  pickDirectoryFailed: 'Could not choose a directory. Please try again.'
};

/**
 * 桌面壳文案表：按语言标签选一套。
 * 语言判定与上游 `resolveDesktopLocale` 同规则（`zh*` → 中文，其余英文）。
 */
export class DesktopCopy {
  /** 按 BCP-47 标签解析文案（`zh-CN`、`zh-Hans`… 都算中文）。 */
  static forLanguage(language: string): DesktopMessages {
    return language.toLowerCase().startsWith('zh') ? DESKTOP_ZH : DESKTOP_EN;
  }

  /** 取模板里 `{key}` 占位符的当前值（找不到返回空串，与上游 formatDesktopMessage 同语义）。 */
  static placeholder(template: string, key: string, value: string): string {
    return template.replace('{' + key + '}', value);
  }
}
