#!/usr/bin/env node
/**
 * desktop-shell-check.mjs —— 桌面壳契约一致性检查（零依赖，node 直接跑）。
 *
 * 背景：鸿蒙桌面壳有三处「必须同时成立」的事实来源：
 *   ① `desktop-upstream/`（上游 Electron 壳源码快照，事实来源）
 *   ② `client/entry/src/main/resources/rawfile/desktop-shell.json`（壳运行时读的契约）
 *   ③ `client/entry/src/main/ets/**`（ArkTS 实现：文案表、菜单分发、契约加载器）
 * 三者任意一处单独改动都会造成「菜单写着有、实际没有」这类静默漂移。本脚本把三者对起来。
 *
 * 用法：node scripts/desktop-shell-check.mjs
 * 退出码：0 = 全部通过；1 = 有检查失败（失败项逐条打印）。
 */
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const failures = []
const notes = []

function check(name, ok, detail = '') {
  if (ok) {
    notes.push(`  ✅ ${name}`)
  } else {
    failures.push(`  ❌ ${name}${detail === '' ? '' : ` —— ${detail}`}`)
  }
}

function read(relative) {
  return readFileSync(join(root, relative), 'utf8')
}

/** 从上游 TypeScript 里抠一个数字常量（`export const X = 40`）。 */
function upstreamNumber(source, name) {
  const match = new RegExp(`${name}\\s*=\\s*(\\d+)`).exec(source)
  return match === null ? null : Number(match[1])
}

const contractPath = 'client/entry/src/main/resources/rawfile/desktop-shell.json'
const contract = JSON.parse(read(contractPath))

// ——— 1. 契约自身 ———
check('契约 schemaVersion 为 1', contract.schemaVersion === 1, `实际 ${contract.schemaVersion}`)
check('契约记录了上游仓库与提交', typeof contract.upstream.commit === 'string' && contract.upstream.commit.length === 40,
  `commit=${contract.upstream.commit}`)
check('契约分支是 master（上游默认分支不是 main）', contract.upstream.branch === 'master')
check('桌面端口 19387 / Web 端口 3080 分开', contract.upstream.desktopPort === 19387 && contract.upstream.webPort === 3080)
check('scheme 为 dsh-app', contract.upstream.scheme === 'dsh-app')

// ——— 2. 与上游源码快照交叉核对 ———
const upstream = {
  main: read('desktop-upstream/apps/desktop/src/main.ts'),
  windowsLayout: read('desktop-upstream/apps/desktop/src/windows-layout.ts'),
  hostProtocol: read('desktop-upstream/apps/desktop/src/host-protocol.ts'),
  updateSchedule: read('desktop-upstream/apps/desktop/src/update-schedule.ts'),
  paths: read('desktop-upstream/apps/desktop/src/paths.ts'),
  desktopPackage: JSON.parse(read('desktop-upstream/apps/desktop/package.json')),
}

check('窗口默认宽高与上游 createWindow 一致',
  upstream.main.includes(`width: ${contract.window.defaultWidth}`) &&
  upstream.main.includes(`height: ${contract.window.defaultHeight}`),
  `契约 ${contract.window.defaultWidth}x${contract.window.defaultHeight}`)
check('窗口最小尺寸与上游一致',
  upstream.main.includes(`minWidth: ${contract.window.minWidth}`) &&
  upstream.main.includes(`minHeight: ${contract.window.minHeight}`),
  `契约 ${contract.window.minWidth}x${contract.window.minHeight}`)
check('标题栏高度常量与上游一致',
  upstreamNumber(upstream.windowsLayout, 'WINDOWS_TITLEBAR_HEIGHT') === contract.window.titlebarHeight)
check('Host 生命周期协议版本与上游一致',
  upstreamNumber(upstream.hostProtocol, 'DESKTOP_HOST_PROTOCOL_VERSION') === contract.upstream.hostProtocolVersion)
check('更新轮询默认间隔与上游一致（600000）',
  upstream.updateSchedule.includes(`'DSH_DESKTOP_UPDATE_CHECK_INTERVAL_MS', ${contract.update.intervalMs}`) ||
  upstream.updateSchedule.includes(`${contract.update.intervalMs}_000`) ||
  upstream.updateSchedule.includes(`600_000`),
  `契约 ${contract.update.intervalMs}`)
check('更新最大退避与上游一致（3600000）',
  upstream.updateSchedule.includes('3_600_000') && contract.update.maxBackoffMs === 3600000)
check('更新抖动默认值与上游一致（0.2）',
  upstream.updateSchedule.includes(`DSH_DESKTOP_UPDATE_CHECK_JITTER ?? ${contract.update.jitter}`))
check('profile 归属路径为 $DSH_HOME/profiles/desktop',
  upstream.paths.includes(`'profiles'`) && upstream.paths.includes(`'desktop'`))
check('上游桌面端版本与契约记录的基线版本一致',
  upstream.desktopPackage.version === contract.upstream.appVersion,
  `上游 ${upstream.desktopPackage.version} vs 契约 ${contract.upstream.appVersion}`)

// ——— 3. 契约 ↔ ArkTS 文案表 / 标签解析器 ———
const copySource = read('client/entry/src/main/ets/desktop/DesktopCopy.ets')
const labelSource = read('client/entry/src/main/ets/desktop/DesktopLabels.ets')
const messageFields = new Set()
for (const match of copySource.matchAll(/^  (\w+): string = '';$/gmu)) {
  messageFields.add(match[1])
}
const labelKeys = new Set([...labelSource.matchAll(/case '([^']+)':/g)].map((m) => m[1]))

const menuItems = contract.menus.flatMap((menu) => menu.items).filter((item) => !item.separator)
const missingFields = [...new Set(menuItems.map((item) => item.labelKey))]
  .filter((key) => !messageFields.has(key))
check('菜单用到的每个 labelKey 都在 DesktopMessages 里有字段', missingFields.length === 0, missingFields.join(', '))
const missingCases = [...new Set(menuItems.map((item) => item.labelKey))].filter((key) => !labelKeys.has(key))
check('菜单用到的每个 labelKey 都能被 desktopLabel 解析', missingCases.length === 0, missingCases.join(', '))

// ——— 4. 契约 ↔ 快捷键 ———
const shortcutIds = new Set(contract.shortcuts.map((shortcut) => shortcut.id))
const referenced = menuItems.map((item) => item.shortcutId).filter((id) => id !== undefined && id !== '')
const unknownShortcuts = [...new Set(referenced)].filter((id) => !shortcutIds.has(id))
check('菜单引用的 shortcutId 都在 shortcuts 列表里', unknownShortcuts.length === 0, unknownShortcuts.join(', '))

// ——— 5. 契约 ↔ 菜单分发（不许有「点了没反应」的条目） ———
const indexSource = read('client/entry/src/main/ets/pages/Index.ets')
const handled = new Set([...indexSource.matchAll(/itemId === '([^']+)'/g)].map((m) => m[1]))
const editMenuIds = new Set((contract.menus.find((menu) => menu.id === 'edit')?.items ?? [])
  .filter((item) => !item.separator).map((item) => item.id))
const unhandled = [...new Set(menuItems.map((item) => item.id))]
  .filter((id) => !handled.has(id) && !editMenuIds.has(id))
check('每个菜单项要么被显式处理、要么属于「编辑动作走系统快捷键」的集合',
  unhandled.length === 0, unhandled.join(', '))

// ——— 6. 契约 ↔ ArkTS 加载器（新增键必须被真的读到） ———
const contractSource = read('client/entry/src/main/ets/desktop/DesktopShellContract.ets')
const loaderKeys = [
  ['window', ['defaultWidth', 'defaultHeight', 'minWidth', 'minHeight', 'titlebarHeight', 'saveDebounceMs']],
  ['update', ['feedBase', 'defaultTarget', 'manifestName', 'downloadPage', 'intervalMs', 'maxBackoffMs',
    'jitter', 'minIntervalMs', 'maxIntervalMs', 'quitInspectionDeadlineMs', 'requestTimeoutMs']],
]
for (const [section, keys] of loaderKeys) {
  const absent = keys.filter((key) => !contractSource.includes(`['${key}']`))
  check(`契约 ${section} 段的每个键都被 DesktopShellContract 读取`, absent.length === 0, absent.join(', '))
  const undeclared = Object.keys(contract[section]).filter((key) => !keys.includes(key))
  check(`契约 ${section} 段没有「写了但没人读」的键`, undeclared.length === 0, undeclared.join(', '))
}

// ——— 7. 归档快照与出处文件一致 ———
const provenance = read('desktop-upstream/README.md')
check('归档出处文件记录的提交与契约一致', provenance.includes(contract.upstream.commit))
check('归档出处文件记录的版本与契约一致', provenance.includes(contract.upstream.appVersion))

// ——— 8. 窗口几何的单位（px API ↔ vp 内部，曾经踩过的坑） ———
// 官方：resize()/moveWindowTo()/windowRect/Size/WindowLimits 全是 px，只有 API 22+ 的 *InVP 才是 vp。
// 内部一律 vp，所以每个调用点都必须过 WindowGeometry.pxFromVp()；漏一个就是「重启后窗口缩一半」。
const geometrySource = read('client/entry/src/main/ets/desktop/WindowGeometry.ets')
const entrySource = read('client/entry/src/main/ets/entryability/EntryAbility.ets')

const bareResize = /(?:mainWindow|windowClass|win)\.(resize|resizeAsync|moveWindowTo|moveWindowToAsync)\(\s*this\.geometry/
check('resize/moveWindowTo 的实参不是裸 vp 值（必须过 pxFromVp）', !bareResize.test(entrySource))
const pxCalls = [...entrySource.matchAll(/\.(?:resize|moveWindowTo)\(([\s\S]{0,200}?)\.catch/g)]
  .filter((match) => !match[1].includes('pxFromVp('))
check('EntryAbility 里每个 resize/moveWindowTo 调用都做了 px 换算',
  pxCalls.length === 0 && /pxFromVp\(this\.geometry\.width/.test(entrySource))
check('落盘/夹取仍在 vp 域（windowRect 经 vpFromPx 换算）',
  /WindowGeometry\.fromPixelRect\(/.test(entrySource) && /static vpFromPx\(/.test(geometrySource))
check('落盘 JSON 带版本号，旧格式脏数据整条丢弃',
  /static readonly SCHEMA_VERSION: number = \d+;/.test(geometrySource) &&
  /'\{"v":' \+ WindowGeometry\.SCHEMA_VERSION/.test(geometrySource) &&
  /numberField\(fields, 'v', 0\) < WindowGeometry\.SCHEMA_VERSION/.test(geometrySource))
// 换算只能发生在 WindowGeometry 内部：其他地方出现 `* density` / `/ density` 即是漏网之鱼。
const etsRoot = 'client/entry/src/main/ets'
const strayDensity = []
const walk = (dir) => {
  for (const entry of readdirSync(join(root, dir), { withFileTypes: true })) {
    const relative = `${dir}/${entry.name}`
    if (entry.isDirectory()) {
      walk(relative)
    } else if (entry.name.endsWith('.ets') && relative !== `${etsRoot}/desktop/WindowGeometry.ets`) {
      // 注释里的说明文字不算（去掉行注释与块注释后再看代码）
      const code = read(relative).replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '')
      if (/[*/]\s*[\w.]*density/.test(code)) {
        strayDensity.push(relative)
      }
    }
  }
}
walk(etsRoot)
check('px/vp 换算只出现在 WindowGeometry 内部', strayDensity.length === 0, strayDensity.join(', '))

// ——— 字形绘制契约（Shape/Path 的「重影」防线） ———
// ArkUI 的 DrawingPainter::DrawPath 对每个 Path 固定做两次绘制：先 brush 填色、再 pen 描边；
// 只有 HasStrokeWidth() 且宽度≈0 时 SetPen() 才返回 false 跳过一次。所以**每个 Path 都必须显式带
// strokeWidth**：纯填充字形写 strokeWidth(0)（关掉默认 black/1vp 描边 = 消重影），
// 描边字形写 strokeWidth($$.strokeWidth ?? 1)。
const iconsSource = read('client/entry/src/main/ets/common/Icons.ets')
const iconPaths = iconsSource.match(/\.commands\(/g)?.length ?? 0
const iconPens = iconsSource.match(/\.strokeWidth\(/g)?.length ?? 0
check('Icons.ets 每个字形都显式设置了 strokeWidth（否则 ArkUI 会填色 + 默认黑描边画两遍）',
  iconPaths > 0 && iconPaths === iconPens, `Path=${iconPaths} strokeWidth=${iconPens}`)

/** 每个 `.fill(` 行之后（同一 Path 的属性链内）都必须出现 strokeWidth。 */
function shapePathsWithoutPen(source) {
  const lines = source.split('\n')
  const bad = []
  for (let i = 0; i < lines.length; i++) {
    if (!/^\s*\.fill\(/.test(lines[i])) continue
    const chain = lines.slice(i, i + 5).join('\n')
    if (!/\.strokeWidth\(/.test(chain)) bad.push(i + 1)
  }
  return bad
}
for (const file of ['client/entry/src/main/ets/common/Brand.ets', 'client/entry/src/main/ets/view/InputBar.ets']) {
  const bad = shapePathsWithoutPen(read(file))
  check(`${file} 的填充 Path 都写了 strokeWidth(0)`, bad.length === 0, `行 ${bad.join(', ')}`)
}

// ——— 独立模式的流式契约（「开箱即用发消息不回复」的根因防线） ———
// ArkTS 的 @ohos.net.http 只在流式请求下派发 dataReceive/dataEnd：用 request() 会「200 但零回调」，
// 界面就是「发出去没反应」。这里只留一条守门检查，细节（含真流固件的分块解析）在 direct-mode-check.mjs。
// 只看 DeepSeekClient 段：同一个文件里的 DshApiClient（服务模式单次 RPC）本来就该用 request()
const apiSource = read('client/entry/src/main/ets/service/DshApiClient.ets')
const directSource = apiSource.slice(apiSource.indexOf('export class DeepSeekClient'))
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '')
check('独立模式直连用 requestInStream（非流式 request 不派发 dataReceive/dataEnd）',
  directSource.includes('req.requestInStream(') && !/req\.request\(/.test(directSource),
  '细节见 node scripts/direct-mode-check.mjs')

// ——— 输出 ———
console.log('桌面壳契约一致性检查')
console.log(`契约：${contractPath}`)
console.log(`上游：${contract.upstream.repository}@${contract.upstream.commit.slice(0, 12)} (v${contract.upstream.appVersion})`)
console.log('')
for (const line of notes) {
  console.log(line)
}
if (failures.length > 0) {
  console.log('')
  console.log('失败项：')
  for (const line of failures) {
    console.log(line)
  }
  console.log('')
  console.log(`结果：${notes.length} 项通过，${failures.length} 项失败`)
  process.exit(1)
}
console.log('')
console.log(`结果：全部 ${notes.length} 项通过`)
