#!/usr/bin/env node
/**
 * session-live-check.mjs —— 「实时」两条链路的回归检查（零依赖，node 直接跑）。
 *
 * 背景（2026-09-26 主人报「没有实时显示和滚动思维链，左侧没实时刷新出最新会话」）：
 *   ① 思维链：官方的思考内容有两个来源 —— 实时 `assistant-stream` 的 `reasoning-delta`
 *      增量，以及落库 `assistant/message` 里的 `reasoning` 内容块（切会话/重连只剩这一份）。
 *      只认 text 块、不渲染 reasoning，界面表现就是「思考看不见」；
 *   ② 会话列表：宿主通过 `$events` 把 `api-session/added|removed|status|activity`
 *      转发给客户端（官方 web 端 `ctx.remote.$on` 同一路）。不订这条流，侧栏只在
 *      「当前会话 turn/end / session/title」时才刷新，新会话要等下一次全量才出现。
 *
 * 本脚本做两件事：
 *   ① 静态契约：`$events` 订阅、四种会话事件的就地更新、`session/list` 去抖（不许每条事件
 *      全量重拉）、思维链落库抽取、列表跟随/「回到底部」的接线；
 *   ② 功能回归：把 `.ets` 里**真的** `blocksToReasoning` / `blocksToText` /
 *      `applyAssistantFrame` / `reasoningSummary` / `firstLine` / `lastLine` 抠出来
 *      （node --experimental-strip-types 剥掉类型直接跑），喂真机抓下来的帧序列与内容块。
 *
 * 用法：node scripts/session-live-check.mjs
 * 退出码：0 = 全部通过；1 = 有检查失败（失败项逐条打印）。
 */
import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const indexSource = readFileSync(join(root, 'client/entry/src/main/ets/pages/Index.ets'), 'utf8')
const apiSource = readFileSync(join(root, 'client/entry/src/main/ets/service/DshApiClient.ets'), 'utf8')
const chatSource = readFileSync(join(root, 'client/entry/src/main/ets/view/ChatView.ets'), 'utf8')
const itemSource = readFileSync(join(root, 'client/entry/src/main/ets/view/MessageItem.ets'), 'utf8')
const sidebarSource = readFileSync(join(root, 'client/entry/src/main/ets/view/Sidebar.ets'), 'utf8')
const abilitySource = readFileSync(join(root, 'client/entry/src/main/ets/entryability/EntryAbility.ets'), 'utf8')
const failures = []
const notes = []

function check(name, ok, detail = '') {
  if (ok) {
    notes.push(`  ✅ ${name}`)
  } else {
    failures.push(`  ❌ ${name}${detail === '' ? '' : ` —— ${detail}`}`)
  }
}

/**
 * 去掉注释后的真代码。**只用于结构检查**：字符串字面量的内容会被替换成 `x`
 * （`maskLiterals` 的副作用），凡是检查「某字面量出现了没有」的条目一律用原文。
 */
function strip(text) {
  const masked = maskLiterals(text)
  const out = [...masked]
  let i = 0
  while (i < masked.length) {
    if (masked[i] === '/' && masked[i + 1] === '*') {
      const close = masked.indexOf('*/', i + 2)
      const stop = close === -1 ? masked.length : close + 2
      for (let k = i; k < stop; k += 1) {
        out[k] = masked[k] === '\n' ? '\n' : ' '
      }
      i = stop
      continue
    }
    if (masked[i] === '/' && masked[i + 1] === '/') {
      let k = i
      while (k < masked.length && masked[k] !== '\n') {
        out[k] = ' '
        k += 1
      }
      i = k
      continue
    }
    i += 1
  }
  return out.join('')
}

// 结构检查用剥注释后的代码，字面量检查用原文（见 strip 的说明）
const api = apiSource
const index = indexSource
const chat = chatSource
const item = itemSource
const apiCode = strip(apiSource)
const indexCode = strip(indexSource)

// ——— ① 静态契约：$events（侧栏实时会话列表） ———
check('DshApiClient 会打开宿主事件流 $events（args 必须为空对象）',
  /\$events/.test(api) && /openHostEvents\(sink: DshStreamSink\): string \{/.test(api))
check('页面连上事件流就订 $events（重连由 reopenStreams 原样重开）',
  /this\.openHostEvents\(\);/.test(index) && /private openHostEvents\(\): void \{/.test(index))
check('四种会话事件都处理了（added / removed / status / activity）',
  ['api-session/added', 'api-session/removed', 'api-session/status', 'api-session/activity']
    .every((name) => index.includes(`'${name}'`)))
check('新会话事件按权威摘要就地插入（与 session/list 共用一套字段解析）',
  /parseSessionSummary\(raw: Record<string, Object>\): DshSession/.test(index) &&
  /this\.upsertSession\(this\.parseSessionSummary\(raw\)\);/.test(index))
check('全量 session/list 有去抖 + 并发闸门（不许每条事件重拉 190KB）',
  /private scheduleSessionRefresh\(delay: number\): void/.test(index) &&
  /private sessionRefreshInFlight: boolean = false;/.test(index) &&
  /if \(client === null \|\| this\.sessionRefreshInFlight\) \{\s*\n\s*return;/.test(index))
check('activity 只前移该行并重排（不整表重拉）',
  /private touchSession\(sessionId: string, updatedAt: number\): void/.test(index) &&
  /this\.touchSession\(sessionId, at\);/.test(index))
check('status 只翻运行位（侧栏那一行的小圆点）',
  /private markSessionRunning\(sessionId: string, running: boolean\): void/.test(index) &&
  /this\.markSessionRunning\(sessionId, args\.length > 1 && args\[1\] === true\);/.test(index))
check('列表行按 updatedAt 降序（最新会话排最前）',
  /sorted\.sort\(\(a: DshSession, b: DshSession\): number => b\.updatedAt - a\.updatedAt\);/.test(index))

// ——— ① 静态契约：思维链（落库抽取 + 实时增量） ———
check('assistant/message 的 reasoning 内容块会被抽出来（切会话/重连不丢思维链）',
  /const reasoning: string = this\.blocksToReasoning\(blocks\);/.test(indexCode) &&
  /msg\.reasoning = reasoning;/.test(index))
check('blocksToReasoning 只认 reasoning 块', /=== 'reasoning'\) \{/.test(index))
check('实时帧 block-start 换行接上（同一次尝试的第 2..n 段思考不粘成一行）',
  /blockType.*=== 'reasoning'/.test(index) && index.includes("current.reasoning += '\\n\\n';"))
check('MessageItem 渲染思维链披露行（图标 + 标题 + 实时摘要 + 展开正文）',
  /reasoningRow\(\) \{/.test(item) && /IconThinkOutline\(\{ size: 14/.test(item) &&
  /this\.message\.reasoning\.length > 0\) \{\s*\n\s*this\.reasoningRow\(\)/.test(item))
check('披露行标题区分生成中/已完成（思考中 / 思考）',
  /reasoningTitle\(\): string \{\s*\n\s*return this\.message\.status === 'streaming' \? '思考中' : '思考';/.test(item))
check('摘要生成中取最后一行、结束取首行（与上游 ReasoningRow 同一取舍）',
  /this\.message\.status === 'streaming' \? MessageItem\.lastLine\(text\) : MessageItem\.firstLine\(text\);/.test(item))
check('摘要去掉 ** 粗体记号并限长', /line\.split\('\*\*'\)\.join\(''\)\.trim\(\)/.test(item) &&
  /plain\.length > 160 \? plain\.slice\(0, 160\) : plain/.test(item))

// ——— ① 静态契约：跟随滚动（不抢读者上翻） ———
check('正文列表把「是否在底部」回报给页面（onDidScroll + isAtEnd）',
  /onFollowState: \(atEnd: boolean\) => void/.test(chat) &&
  /atEnd = this\.scroller\.isAtEnd\(\);/.test(chat) &&
  /onFollowState: \(atEnd: boolean\) => \{ this\.followBottom = atEnd; \}/.test(index))
check('增量滚动只在跟随中发生（读者上翻后不把人拽回底部）',
  /private scrollToBottom\(force: boolean = false\): void \{\s*\n\s*if \(force\) \{\s*\n\s*this\.followBottom = true;/.test(index) &&
  /if \(!this\.followBottom\) \{\s*\n\s*return;/.test(index))
check('发消息 / 切会话强制恢复跟随', /this\.scrollToBottom\(true\);/.test(index) &&
  /this\.followBottom = true;\s*\n\s*this\.currentPermission = '';/.test(index))
check('上翻后出现「回到底部」浮标（上游 .toBottom：34x34 圆 + floating 填充）',
  /if \(!this\.atEnd\) \{\s*\n\s*this\.toBottom\(\)/.test(chat) &&
  /Theme\.TO_BOTTOM_SIZE/.test(chat) && /dswAliasButtonFloatingFill/.test(chat))

// ——— ② 功能回归（跑真代码） ———
/** 把字符串字面量替换成等长占位，便于按括号配对抠方法体。 */
function maskLiterals(text) {
  const out = [...text]
  let i = 0
  while (i < text.length) {
    const ch = text[i]
    if (ch === "'" || ch === '"' || ch === '`') {
      const quote = ch
      i += 1
      while (i < text.length && text[i] !== quote) {
        if (text[i] === '\\') {
          out[i] = 'x'
          i += 1
        }
        out[i] = 'x'
        i += 1
      }
      i += 1
      continue
    }
    if (ch === '/' && text[i + 1] === '/') {
      while (i < text.length && text[i] !== '\n') {
        out[i] = 'x'
        i += 1
      }
      continue
    }
    i += 1
  }
  return out.join('')
}

/** 抠出 `签名 { body }` 的方法体（按括号配对，字面量已掩码）。 */
function methodBody(source, signature) {
  const masked = maskLiterals(source)
  const start = masked.indexOf(signature)
  if (start === -1) {
    throw new Error(`找不到方法签名：${signature}`)
  }
  const open = masked.indexOf('{', start)
  let depth = 0
  for (let i = open; i < masked.length; i += 1) {
    if (masked[i] === '{') {
      depth += 1
    } else if (masked[i] === '}') {
      depth -= 1
      if (depth === 0) {
        return source.slice(open + 1, i)
      }
    }
  }
  throw new Error(`方法体不闭合：${signature}`)
}

/** 取真实的类定义（@Observed 装饰器天然被排除：node 只剥类型，不认装饰器）。 */
const typesSource = readFileSync(join(root, 'client/entry/src/main/ets/model/Types.ets'), 'utf8')

function classSource(name) {
  const from = typesSource.indexOf(`export class ${name}`)
  return typesSource.slice(from, typesSource.indexOf('\n}', from) + 2)
}
const chatMessageClass = classSource('ChatMessage')
const dshSessionClass = classSource('DshSession')

const extracted = [
  chatMessageClass,
  dshSessionClass,
  `export function blocksToText(blocks: Array<Record<string, Object>>): string {${methodBody(indexSource, 'private blocksToText(blocks: Array<Record<string, Object>>): string {')}}`,
  `export function blocksToReasoning(blocks: Array<Record<string, Object>>): string {${methodBody(indexSource, 'private blocksToReasoning(blocks: Array<Record<string, Object>>): string {')}}`,
  `export function applyAssistantFrame(frame: Record<string, Object>): void {${methodBody(indexSource, 'private applyAssistantFrame(frame: Record<string, Object>): void {')}}`,
  `export function parseSessionSummary(raw: Record<string, Object>): DshSession {${methodBody(indexSource, 'private parseSessionSummary(raw: Record<string, Object>): DshSession {')}}`,
  `export function sortSessions(list: DshSession[]): DshSession[] {${methodBody(indexSource, 'private sortSessions(list: DshSession[]): DshSession[] {')}}`,
  `export function upsertSession(session: DshSession): void {${methodBody(indexSource, 'private upsertSession(session: DshSession): void {')}}`,
  `export function touchSession(sessionId: string, updatedAt: number): void {${methodBody(indexSource, 'private touchSession(sessionId: string, updatedAt: number): void {')}}`,
  `export function markSessionRunning(sessionId: string, running: boolean): void {${methodBody(indexSource, 'private markSessionRunning(sessionId: string, running: boolean): void {')}}`,
  `export function reasoningSummary(): string {${methodBody(itemSource, 'private reasoningSummary(): string {')}}`,
  `export function firstLine(text: string): string {${methodBody(itemSource, 'private static firstLine(text: string): string {')}}`,
  `export function lastLine(text: string): string {${methodBody(itemSource, 'private static lastLine(text: string): string {')}}`,
  'export const MessageItem = { firstLine, lastLine };',
].join('\n')

// 真机抓下来的固件（2026-09-26 用 `session/follow` + `assistantStream:true` 实跑 deepseek-flash）
const REAL_MESSAGE_BLOCKS = [
  { type: 'reasoning', text: 'The user asked only to reply "收到" — but there is the system-reminder about 强制规则.' },
  { type: 'reasoning', text: '\n\nSecond thinking block: keep it short.' },
  { type: 'text', text: '收到' },
]
const REASONING_TEXT = REAL_MESSAGE_BLOCKS[0].text + REAL_MESSAGE_BLOCKS[1].text
const REAL_FRAMES = [
  { type: 'start', attemptId: 'session-x:1', revision: 1, startedAfterSeq: 0, turn: 1, step: 1 },
  { type: 'chunk', attemptId: 'session-x:1', revision: 2, index: 0, time: 1, chunk: { type: 'block-start', index: 0, blockType: 'reasoning' } },
  { type: 'chunk', attemptId: 'session-x:1', revision: 3, index: 1, time: 2, chunk: { type: 'reasoning-delta', index: 0, text: 'The user' } },
  { type: 'chunk', attemptId: 'session-x:1', revision: 4, index: 2, time: 3, chunk: { type: 'reasoning-delta', index: 0, text: ' asked' } },
  { type: 'chunk', attemptId: 'session-x:1', revision: 5, index: 3, time: 4, chunk: { type: 'block-end', index: 0, block: { type: 'reasoning', text: 'The user asked' } } },
  { type: 'chunk', attemptId: 'session-x:1', revision: 6, index: 4, time: 5, chunk: { type: 'block-start', index: 1, blockType: 'text' } },
  { type: 'chunk', attemptId: 'session-x:1', revision: 7, index: 5, time: 6, chunk: { type: 'text-delta', index: 1, text: '收到' } },
  { type: 'chunk', attemptId: 'session-x:1', revision: 8, index: 6, time: 7, chunk: { type: 'usage', usage: { inputTokens: 18155, outputTokens: 195 } } },
  { type: 'end', attemptId: 'session-x:1', revision: 9, index: 7, outcome: { kind: 'committed', eventType: 'assistant/message', seq: 22 } },
]
const EXPECTED_LIVE_REASONING = 'The user asked'
const EXPECTED_LIVE_TEXT = '收到'

// 真机 `session/list` / `api-session/added` 的行（同一份权威结构，字段原样抓取）
const REAL_SUMMARY = {
  sessionId: 'session-e6cdecc2-65d6-4212-9ffa-0dbeb5265e56',
  updatedAt: 1790352346706,
  running: true,
  blank: false,
  cwd: '/storage/Users/currentUser',
  projections: {
    asOfSeq: 18,
    values: {
      title: '只回复两个字：收到',
      agentPreset: 'harmony-chat',
      permissions: { currentValue: 'workspace-write' },
      modelSelection: { lastUsed: null, next: { provider: 'deepseek-official', model: 'deepseek-flash', reasoningEffort: 'high' } },
    },
  },
}
const OLDER_SUMMARY = {
  sessionId: 'session-01618773-01d7-43e4-b038-62053a3fe03c',
  updatedAt: 1790346335853,
  running: false,
  blank: false,
  cwd: '/storage/Users/currentUser',
  projections: { values: { title: '旧会话', permissions: { currentValue: 'read-only' } } },
}

const driver = `
import { blocksToText, blocksToReasoning, applyAssistantFrame, reasoningSummary, firstLine, lastLine, MessageItem, ChatMessage, DshSession, parseSessionSummary, sortSessions, upsertSession, touchSession, markSessionRunning } from './code.ts'

const BLOCKS = ${JSON.stringify(REAL_MESSAGE_BLOCKS)}
const FRAMES = ${JSON.stringify(REAL_FRAMES)}
const results = []
function ok(name, value, detail) { results.push({ name, pass: value === true, detail: value === true ? '' : detail }) }
function eq(name, actual, expected) { ok(name, actual === expected, 'got ' + JSON.stringify(actual) + ' want ' + JSON.stringify(expected)) }

// 1. 落库内容块 → 思维链正文 / 正文（回归：thinking 不再只认 text）
eq('blocksToReasoning 按顺序拼出两段思考', blocksToReasoning(BLOCKS), ${JSON.stringify(REASONING_TEXT)})
eq('blocksToText 只取 text 块（思考不混进正文）', blocksToText(BLOCKS), '收到')
eq('空内容块安全', blocksToReasoning([]) + blocksToText([]), '')

// 2. 摘要取行（与上游 ReasoningRow 同一取舍）
const LONG = '第一行摘要\\n' + 'x'.repeat(200) + '**粗体**结尾'
eq('生成中取最后一行并去掉 ** 记号', reasoningSummary.call({ message: { reasoning: LONG, status: 'streaming' } }), 'x'.repeat(160))
eq('结束后取首行', reasoningSummary.call({ message: { reasoning: LONG, status: 'done' } }), '第一行摘要')
eq('尾部只剩换行/空白时回落到上一行', reasoningSummary.call({ message: { reasoning: '想完了\\n\\n', status: 'streaming' } }), '想完了')
eq('空思考返回空串', reasoningSummary.call({ message: { reasoning: '', status: 'streaming' } }), '')
eq('单行不换行也安全', reasoningSummary.call({ message: { reasoning: '一句话', status: 'done' } }), '一句话')
eq('firstLine/lastLine 对 \\\\r\\\\n 也成立', firstLine('甲\\r\\n乙') + '|' + MessageItem.lastLine('甲\\r\\n乙'), '甲|乙')

// 3. 实时帧折叠（真 applyAssistantFrame）
const host = { messages: [new ChatMessage('local-1', 'user', 1)], streaming: false, scrolls: 0, scrollToBottom() { this.scrolls += 1 } }
for (const frame of FRAMES) applyAssistantFrame.call(host, frame)
const assistants = host.messages.filter((m) => m.role === 'assistant')
eq('一个回合只建一个助手气泡', assistants.length, 1)
eq('思考增量全部落进 reasoning', assistants[0].reasoning, ${JSON.stringify(EXPECTED_LIVE_REASONING)})
eq('正文增量落进 text', assistants[0].text, ${JSON.stringify(EXPECTED_LIVE_TEXT)})
eq('气泡处于 streaming 状态（界面上就是那个光标）', assistants[0].status, 'streaming')
eq('end 帧把 streaming 归零', host.streaming, false)
eq('每条内容增量都请求了跟随滚动（block-start / usage 不滚）', host.scrolls, 3)
eq('单条 block-start 不造空气泡', (() => {
  const solo = { messages: [], streaming: false, scrollToBottom() {} }
  applyAssistantFrame.call(solo, { type: 'chunk', chunk: { type: 'block-start', index: 0, blockType: 'reasoning' } })
  return solo.messages.length
})(), 0)
eq('同一尝试第二段思考换行接上', (() => {
  const two = { messages: [], streaming: false, scrollToBottom() {} }
  applyAssistantFrame.call(two, { type: 'chunk', chunk: { type: 'reasoning-delta', index: 0, text: '甲' } })
  applyAssistantFrame.call(two, { type: 'chunk', chunk: { type: 'block-start', index: 1, blockType: 'reasoning' } })
  applyAssistantFrame.call(two, { type: 'chunk', chunk: { type: 'reasoning-delta', index: 1, text: '乙' } })
  return two.messages[0].reasoning
})(), '甲\\n\\n乙')


// 4. 侧栏会话列表：真 parseSessionSummary / upsertSession / touchSession / markSessionRunning
function makeHost(rows) {
  return {
    sessions: rows === undefined ? [] : rows,
    refreshes: [],
    workspaces: 0,
    syncWorkspaceOptions() { this.workspaces += 1 },
    scheduleSessionRefresh(delay) { this.refreshes.push(delay) },
    sortSessions(list) { return sortSessions.call(null, list) },
  }
}
const parsed = parseSessionSummary.call(makeHost(), ${JSON.stringify(REAL_SUMMARY)})
eq('摘要行解析出 id', parsed.sessionId, ${JSON.stringify(REAL_SUMMARY.sessionId)})
eq('摘要行解析出 updatedAt / running / blank', [parsed.updatedAt, parsed.running, parsed.blank].join(','), '1790352346706,true,false')
eq('摘要行解析出标题 / 对话模式 / 工作区权限', [parsed.title, parsed.agentPreset, parsed.permission].join('|'), '只回复两个字：收到|harmony-chat|workspace-write')
eq('模型取 next 兜底（lastUsed 为空）', parsed.modelProvider + '/' + parsed.model, 'deepseek-official/deepseek-flash')

const added = makeHost([])
upsertSession.call(added, parseSessionSummary.call(added, ${JSON.stringify(REAL_SUMMARY)}))
eq('新会话事件进侧栏（不重拉全表）', added.sessions.length + ':' + added.refreshes.length, '1:0')
eq('新会话按 updatedAt 排到最前', added.sessions[0].sessionId, ${JSON.stringify(REAL_SUMMARY.sessionId)})

const mixed = makeHost([])
upsertSession.call(mixed, parseSessionSummary.call(mixed, ${JSON.stringify(OLDER_SUMMARY)}))
upsertSession.call(mixed, parseSessionSummary.call(mixed, ${JSON.stringify(REAL_SUMMARY)}))
eq('两行按 updatedAt 降序（最新在最前）', mixed.sessions.map((row) => row.updatedAt).join(','), '1790352346706,1790346335853')
upsertSession.call(mixed, parseSessionSummary.call(mixed, ${JSON.stringify(REAL_SUMMARY)}))
eq('同一会话再 added 不产生重复行', mixed.sessions.length, 2)

const touched = makeHost([])
upsertSession.call(touched, parseSessionSummary.call(touched, ${JSON.stringify(OLDER_SUMMARY)}))
upsertSession.call(touched, parseSessionSummary.call(touched, ${JSON.stringify(REAL_SUMMARY)}))
touchSession.call(touched, ${JSON.stringify(OLDER_SUMMARY.sessionId)}, 1790399999999)
eq('activity 把该行提到最前', touched.sessions[0].sessionId, ${JSON.stringify(OLDER_SUMMARY.sessionId)})
eq('activity 更新该行时间', touched.sessions[0].updatedAt, 1790399999999)
eq('activity 不重拉全表', touched.refreshes.length, 0)

const unknown = makeHost([])
touchSession.call(unknown, 'session-unknown', 1)
eq('本地没有这一行时兜底全量刷新', unknown.refreshes.length, 1)

const running = makeHost([])
upsertSession.call(running, parseSessionSummary.call(running, ${JSON.stringify(OLDER_SUMMARY)}))
markSessionRunning.call(running, ${JSON.stringify(OLDER_SUMMARY.sessionId)}, true)
eq('status 只翻运行位（时间不动）', running.sessions[0].running + ':' + running.sessions[0].updatedAt, 'true:1790346335853')
eq('status 不重拉全表', running.refreshes.length, 0)

for (const item of results) {
  console.log((item.pass ? 'PASS\\t' : 'FAIL\\t') + item.name + (item.pass ? '' : '\\t' + item.detail))
}
process.exit(results.some((item) => !item.pass) ? 1 : 0)
`

const workDir = join(root, '.gen-tmp', `session-live-check-${process.env.SESSION_LIVE_CHECK_KEEP === '1' ? 'keep' : process.pid}`)
try {
  mkdirSync(workDir, { recursive: true })
  writeFileSync(join(workDir, 'code.ts'), extracted)
  writeFileSync(join(workDir, 'driver.mjs'), driver)
  let output = ''
  try {
    output = execFileSync(process.execPath,
      ['--no-warnings', '--experimental-strip-types', join(workDir, 'driver.mjs')],
      { encoding: 'utf8' })
  } catch (error) {
    output = typeof error.stdout === 'string' ? error.stdout : ''
    const stderr = typeof error.stderr === 'string' ? error.stderr.trim() : ''
    if (stderr !== '') {
      failures.push(`  ❌ 跑真代码出错：${stderr.split('\n').slice(0, 3).join(' / ')}`)
    }
  }
  for (const line of output.split('\n')) {
    if (line.startsWith('PASS\t')) {
      notes.push(`  ✅ ${line.slice(5)}`)
    } else if (line.startsWith('FAIL\t')) {
      const [name, detail] = line.slice(5).split('\t')
      failures.push(`  ❌ ${name}${detail === undefined ? '' : ` —— ${detail}`}`)
    }
  }
} catch (error) {
  failures.push(`  ❌ 跑真代码失败：${String(error.message).split('\n')[0]}`)
} finally {
  if (process.env.SESSION_LIVE_CHECK_KEEP !== '1') {
    rmSync(workDir, { recursive: true, force: true })
  }
}

// ——— ③ 静态契约：事件流握手 / $events 载荷 / 独立模式本机会话 ——
// 背景（2026-09-26 主人第二次报「发送消息之后左边还是没有显示出现在的对话」）：
//   真机实测两条硬故障 ——
//   ① 握手：ArkTS netstack 默认把 `Origin` 写成**不带端口**的 `http://<host>`，
//      dsh 的 Host/Origin fence（`new URL(origin).host === host`）拿它跟 `host:port` 比 → 403，
//      事件流永远连不上（`supportOriginPort: true` 才会带上端口）；
//   ② 载荷：`$events` 只收空 args，多包一层 `{args:{}}` 会被网关注回
//      `gateway/arguments-invalid: forwarded Remote event stream requires an empty args object`。
// 两条都只能靠真机抓帧发现，所以在这里钉住，防止又被改回去。
const apiCodeC = strip(apiSource)
const indexCodeC = strip(indexSource)

check('事件流握手带 supportOriginPort（否则 Origin 缺端口，被 dsh 的 Host/Origin fence 403）',
  /supportOriginPort:\s*true/.test(apiCodeC))
check('$events 的 stream args 就是那个空对象（payload.args 那一层由 sendOpen 补）',
  /const args: Record<string, Object> = \{\};/.test(apiCodeC)
  && !/'args': empty/.test(apiCodeC)
  && !/\{ 'args': empty \}/.test(apiCodeC))
check('独立模式有本机会话清单（左侧那几行不依赖 dsh 服务端）',
  /export class DirectConversation \{/.test(typesSource)
  && /private directConversations: DirectConversation\[\] = \[\];/.test(indexCodeC))
check('独立模式发第一条消息就地建会话（无历史时左侧立刻出现最新会话）',
  /this\.beginDirectConversation\(text\);/.test(indexCodeC)
  && /this\.publishDirectSessions\(\);/.test(indexCodeC))
check('独立模式「新会话」把当前这轮收进清单再开空的（往后添加会话同理）',
  /this\.syncDirectCurrent\(\);\n\s*this\.messages = \[\];/.test(indexCodeC))
check('独立模式点侧栏那几行能切回对应会话的正文',
  /this\.selectDirectSession\(sessionId\);/.test(indexCodeC))
check('侧栏行键编进标题/时间/运行位/选中态（ForEach 同键复用，不换键就不重绘）',
  /Sidebar\.rowKey\(item, this\.currentSessionId\)/.test(sidebarSource)
  && /item\.title \+ '\|'/.test(sidebarSource)
  && /item\.updatedAt\.toString\(\)/.test(sidebarSource))
check('hilog 域落在应用域范围 [0x0, 0xFFFF]（5 位十六进制的域会被静默丢弃）',
  !/0xD0042/.test(apiCodeC) && !/0xD0042/.test(strip(abilitySource))
  && /const MUX_LOG_DOMAIN: number = 0xD004;/.test(apiCodeC)
  && /static readonly LOG_DOMAIN: number = 0xD004;/.test(apiCodeC)
  && /const DOMAIN: number = 0xD004;/.test(strip(abilitySource)))

// ——— 输出 ———
console.log('实时（思维链 / 会话列表）回归检查')
console.log('源码：pages/Index.ets · service/DshApiClient.ets · view/ChatView.ets · view/MessageItem.ets')
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
