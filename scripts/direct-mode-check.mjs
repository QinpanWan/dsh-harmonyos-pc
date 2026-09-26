#!/usr/bin/env node
/**
 * direct-mode-check.mjs —— 独立模式（内置直连，开箱即用）回归检查（零依赖）。
 *
 * 背景（2026-09-26 主人报「开箱即用的模式发消息不回复，配好密钥也这样」的根因）：
 * ArkTS 的 `@ohos.net.http` 只在**流式请求**下派发 `dataReceive` / `dataEnd`。
 * 实锤在 communication_netstack：`http_exec.cpp` 的 `OnWritingMemoryBody` 与
 * `ProcessResponseBodyAndEmitEvents` 都以 `context->IsRequestInStream()` 为前提，
 * `ON_DATA_END` 更只在 `AsyncWorkRequestInStreamCallback` 里发出；而
 * `EnableRequestInStream()` 只被 `http_module.cpp` 的 `requestInStream` 调用。
 * 用 `request()` 发 SSE 的后果是：请求**成功返回 200**、`resp.result` 里还有整段文本，
 * 但一个字节都到不了 `on('dataReceive')` —— 界面表现就是「发出去没反应、也不报错」。
 *
 * 本脚本做两件事：
 *   ① 静态契约：`DeepSeekClient` 必须用 `requestInStream`、订阅顺序正确、取消不报错、
 *      错误详情自己攒（流式模式没有 `resp.result`）；
 *   ② 功能回归：把 `.ets` 里真的 `frameBoundary/frameField/frameText/frameReasoning/streamText/streamReasoning/completionField/completionReasoning/completionText`
 *      抠出来（node --experimental-strip-types 直接把 TS 类型剥掉跑），喂官方 API 抓下来的
 *      **真实 SSE 固件**，按任意字节边界切块，检查拼回来的文本与兜底路径。
 *
 * 用法：node scripts/direct-mode-check.mjs
 * 退出码：0 = 全部通过；1 = 有检查失败（失败项逐条打印）。
 */
import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const clientPath = 'client/entry/src/main/ets/service/DshApiClient.ets'
const failures = []
const notes = []

function check(name, ok, detail = '') {
  if (ok) {
    notes.push(`  ✅ ${name}`)
  } else {
    failures.push(`  ❌ ${name}${detail === '' ? '' : ` —— ${detail}`}`)
  }
}

const source = readFileSync(join(root, clientPath), 'utf8')
const classStart = source.indexOf('export class DeepSeekClient')
if (classStart === -1) {
  console.error(`找不到 export class DeepSeekClient（${clientPath}）`)
  process.exit(1)
}
const deepseek = source.slice(classStart)
/** 去掉注释后的代码（契约检查只看真代码，不看注释里的反例描述）。 */
const code = deepseek.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '')

// ——— ① 静态契约 ———
check('独立模式走 requestInStream（非流式 request 不派发 dataReceive/dataEnd）',
  code.includes('req.requestInStream('))
check('DeepSeekClient 里没有残留的非流式 req.request(',
  !/req\.request\(/.test(code))
check('dataReceive 订阅发生在 requestInStream 之前',
  code.includes("req.on('dataReceive'") &&
  code.indexOf("req.on('dataReceive'") < code.indexOf('req.requestInStream('))
check('请求头带 Authorization: Bearer',
  /'Authorization':\s*'Bearer '\s*\+\s*apiKey/.test(code))
check('请求体 stream: true', /'stream':\s*true/.test(code))
const timeoutMatch = /READ_TIMEOUT_MS:\s*number\s*=\s*(\d+)/.exec(code)
check('读超时 ≥ 300s（netstack 把它当整条响应的总时限，长回复别被掐断）',
  timeoutMatch !== null && Number(timeoutMatch[1]) >= 300000,
  timeoutMatch === null ? '没找到 READ_TIMEOUT_MS' : `实际 ${timeoutMatch[1]}ms`)
check('收尾只生效一次（finished 闸门 + settle）',
  /const settle = \(err: string, flush: boolean\): void => \{\s*\n\s*if \(finished\)/.test(code))
check('用户「停止」/ 开新回合按正常结束收尾（不把主动中止报成失败）',
  code.includes('cancelHook'))
check('HTTP 非 2xx 用自己攒的原文报错（流式模式没有 resp.result）',
  /code >= 300/.test(code) && /raw\.length > 0 \? '：' \+ raw/.test(code))
check('HTTP 200 但没有数据块时报出来（曾经的静默假成功）',
  code.includes('服务端没有返回任何内容'))
check('非 SSE 端点有整段 JSON 兜底', code.includes('completionText'))
check('流式里认 `delta.reasoning_content`（推理模型的思维链，独立模式曾经整条丢掉）',
  code.includes("'reasoning_content'") && code.includes('frameReasoning('))

// ——— ①b 独立模式侧栏出行：切模式带过来的「悬挂会话 id」（2026-09-26 第七轮） ———
// 症状：dsh 服务模式里点过「新会话」/选过会话，再切回独立模式发消息 —— 正文照常流式，侧栏却一直「还没有会话」。
// 根因：`currentSessionId` 还停在 dsh 的会话 id 上（非空，但本地本机会话清单里没有这一行），
// 而 `sendDirect()` 只看「id 空不空」来决定要不要就地建会话 ⇒ 漏建。判据必须是「这条 id 在不在清单里」。
const indexSource = readFileSync(join(root, 'client/entry/src/main/ets/pages/Index.ets'), 'utf8')
const index = indexSource.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '')
check('sendDirect 按「当前 id 在不在本机会话清单里」判要不要就地建会话',
  /if \(this\.findDirectConversation\(this\.currentSessionId\) === null\) \{\s*this\.beginDirectConversation\(/.test(index))
check('sendDirect 不再按「id 是否为空」判（dsh 会话 id 非空但本地没这一行）',
  !/if \(this\.currentSessionId\.length === 0\) \{\s*this\.beginDirectConversation\(/.test(index))
check('adoptDirectConversation 先把不属于本机会话的悬挂 id 清掉',
  /private adoptDirectConversation\(\): void \{[\s\S]{0,700}?findDirectConversation\(this\.currentSessionId\) === null[\s\S]{0,240}?this\.currentSessionId = ''/.test(index))
check('模式隔离：session/list 全量回包落在独立模式时丢弃（不盖掉本机会话投影）',
  /listSessions\(\)\.then\([\s\S]{0,220}?if \(this\.mode !== 'dsh'\) \{/.test(index))
check('模式隔离：当前会话 follow 流在独立模式下不再改写正文',
  /private onFollowValue\(value: Record<string, Object>\): void \{\s*if \(this\.mode !== 'dsh'\) \{/.test(index))
check('模式隔离：宿主 $events 在独立模式下不再往侧栏加服务端行',
  /private onHostEvent\(value: Record<string, Object>\): void \{\s*if \(this\.mode !== 'dsh'\) \{/.test(index))

// ——— ② 功能回归（跑真解析器） ———
/** 把字符串字面量/注释替换成等长占位，便于按括号配对抠方法体。 */
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

const masked = maskLiterals(deepseek)

/** 抠出 `static xxx(...) { body }` 的方法体。 */
function methodBody(signature) {
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
        return deepseek.slice(open + 1, i)
      }
    }
  }
  throw new Error(`方法体不闭合：${signature}`)
}

const extracted = [
  `export function frameBoundary(buffer: string): number {${methodBody('static frameBoundary(buffer: string): number {')}}`,
  `export function frameField(frame: string, field: string): string {${methodBody('static frameField(frame: string, field: string): string {')}}`,
  `export function frameText(frame: string): string {${methodBody('static frameText(frame: string): string {')}}`,
  `export function frameReasoning(frame: string): string {${methodBody('static frameReasoning(frame: string): string {')}}`,
  `export function streamText(raw: string): string {${methodBody('static streamText(raw: string): string {')}}`,
  `export function streamReasoning(raw: string): string {${methodBody('static streamReasoning(raw: string): string {')}}`,
  `export function completionField(raw: string, field: string): string {${methodBody('static completionField(raw: string, field: string): string {')}}`,
  `export function completionReasoning(raw: string): string {${methodBody('static completionReasoning(raw: string): string {')}}`,
  `export function completionText(raw: string): string {${methodBody('static completionText(raw: string): string {')}}`,
  'const DeepSeekClient = { frameBoundary, frameField, frameText, frameReasoning, streamText, streamReasoning, completionField, completionReasoning, completionText };',
].join('\n')

// 真实固件：原样抓自官方 API（deepseek-v4-flash / stream:true），含中文增量、收尾帧与 [DONE]
const REAL_FRAMES = [
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":"鲸"},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":"鱼"},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":"不是"},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":"鱼"},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":"，"},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":"因为"},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":"它是"},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":"哺乳"},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":"动物"},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":"。"},"logprobs":null,"finish_reason":null}]}',
  'data: {"id":"b262ca70-d89e-4f8c-a369-04c5718e06a2","object":"chat.completion.chunk","created":1790350601,"model":"deepseek-flash","system_fingerprint":"aeb56401ca74e127821c4f9126dcb669","choices":[{"index":0,"delta":{"content":""},"logprobs":null,"finish_reason":"stop"}],"usage":{"prompt_tokens":18,"completion_tokens":10,"total_tokens":28}}',
  'data: [DONE]',
]
const EXPECTED = '鲸鱼不是鱼，因为它是哺乳动物。'

const driver = `
import { TextDecoder } from 'node:util'
import { frameBoundary, frameText, frameReasoning, streamText, streamReasoning, completionText, completionReasoning } from './code.ts'

const REAL_FRAMES = ${JSON.stringify(REAL_FRAMES)}
const EXPECTED = ${JSON.stringify(EXPECTED)}
const REAL_SSE = REAL_FRAMES.join('\\n\\n') + '\\n\\n'
const results = []
function ok(name, value, detail) { results.push({ name, pass: value === true, detail: value === true ? '' : detail }) }
function eq(name, actual, expected) { ok(name, actual === expected, 'got ' + JSON.stringify(actual) + ' want ' + JSON.stringify(expected)) }

// 1. 整段原文（= settle 的兜底路径）
eq('streamText 拼出完整回复', streamText(REAL_SSE), EXPECTED)
// 2. 逐帧解析（dataReceive 的常规路径）
ok('frameText 逐帧解析一致', REAL_FRAMES.map(frameText).join('') === EXPECTED, '逐帧拼回来是 ' + REAL_FRAMES.map(frameText).join(''))
// 3. 任意字节边界切块（模拟 dataReceive 的分块，含多字节字符被劈开）
const encoder = new TextEncoder()
const bytes = encoder.encode(REAL_SSE)
for (const size of [1, 2, 3, 4, 5, 7, 13, 64, 999]) {
  const decoder = new TextDecoder('utf-8')
  let buffer = ''
  let text = ''
  for (let at = 0; at < bytes.length; at += size) {
    buffer += decoder.decode(bytes.slice(at, at + size), { stream: true })
    const end = frameBoundary(buffer)
    if (end <= 0) continue
    for (const frame of buffer.slice(0, end).split('\\n\\n')) text += frameText(frame)
    buffer = buffer.slice(end)
  }
  text += streamText(buffer)   // 残帧（settle 的收尾）
  eq('按 ' + size + ' 字节切块仍拼出完整回复', text, EXPECTED)
}
// 4. keep-alive 心跳（长思考时服务端会插 SSE 注释帧）
const withHeartbeat = ': keep-alive\\n\\n' + REAL_FRAMES.slice(1, 4).join('\\n\\n') + '\\n\\n'
eq('跳过 keep-alive 注释帧', streamText(withHeartbeat), '鲸鱼不是')
// 5. [DONE] 不算内容
eq('[DONE] 帧解析为空', streamText('data: [DONE]\\n\\n'), '')
// 6. 服务端没补最后的空行（残帧兜底）
eq('半帧结尾也能吃下（trimEnd）', streamText(REAL_SSE.slice(0, -1)), EXPECTED)
// 7. data: 不带空格 / 多行 data 仍按 SSE 规范拼接
eq('data: 不带空格也认', streamText('data:{"choices":[{"delta":{"content":"行"}}]}\\n\\n'), '行')
eq('同一帧多行 data 依次拼接',
  streamText('data: {"choices":[{"delta":{"content":"甲"}}]}\\ndata: {"choices":[{"delta":{"content":"乙"}}]}\\n\\n'), '甲乙')
// 8. 非 SSE 端点兜底（忽略 stream:true，一次返回整段 JSON）
eq('非 SSE 整段 JSON 兜底', completionText('{"choices":[{"message":{"content":"整段一次返回"}}]}'), '整段一次返回')
eq('SSE 文本不会被当整段 JSON', completionText(REAL_SSE), '')
eq('错误体（没有 choices）不产出内容', completionText('{"error":{"message":"Authentication Fails"}}'), '')
eq('错误体过 streamText 也不产出内容', streamText('{"error":{"message":"Model Not Exist"}}'), '')
eq('空串两种兜底都安全', streamText('') + completionText(''), '')

// 9. 思维链（推理模型先吐 delta.reasoning_content，之前整条被丢掉 → 界面只看得到「思考中」）
const REAL_COT_FRAMES = [
  'data: {"choices":[{"delta":{"role":"assistant","content":"","reasoning_content":"用户"}}]}',
  'data: {"choices":[{"delta":{"reasoning_content":"让我"}}]}',
  'data: {"choices":[{"delta":{"reasoning_content":"说一句你好。"}}]}',
  'data: {"choices":[{"delta":{"content":"你好！"}}]}',
  'data: {"choices":[{"delta":{"content":"有什么需要帮忙的？"},"finish_reason":"stop"}],"usage":{"completion_tokens":9}}',
  'data: [DONE]',
]
const COT = '用户让我说一句你好。'
const ANSWER = '你好！有什么需要帮忙的？'
eq('frameReasoning 逐帧取思维链', REAL_COT_FRAMES.map(frameReasoning).join(''), COT)
eq('思维链帧不污染正文', REAL_COT_FRAMES.map(frameText).join(''), ANSWER)
eq('streamReasoning 吃下整条流（含残帧）', streamReasoning(REAL_COT_FRAMES.join('\\n\\n')), COT)
eq('正文里的 reasoning_content 不会被当回答', streamText(REAL_COT_FRAMES.slice(0, 3).join('\\n\\n')), '')
eq('非推理模型（无该字段）思维链为空', streamReasoning(REAL_FRAMES.join('\\n\\n')), '')
eq('keep-alive 心跳不影响思维链解析', frameReasoning(': keep-alive'), '')
eq('非 SSE 整段 JSON 的思维链兜底', completionReasoning('{"choices":[{"message":{"content":"答","reasoning_content":"想"}}]}'), '想')
eq('标准 SSE 文本不会被当整段 JSON 取思维链', completionReasoning(REAL_COT_FRAMES.join('\\n\\n')), '')

for (const item of results) {
  console.log((item.pass ? 'PASS\\t' : 'FAIL\\t') + item.name + (item.pass ? '' : '\\t' + item.detail))
}
process.exit(results.some((item) => !item.pass) ? 1 : 0)
`

const workDir = join(root, '.gen-tmp', `direct-check-${process.env.DIRECT_CHECK_KEEP === '1' ? 'keep' : process.pid}`)
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
    // 驱动脚本失败时它自己会打印逐项 FAIL，stderr 里才是语法/运行错误
    output = typeof error.stdout === 'string' ? error.stdout : ''
    const stderr = typeof error.stderr === 'string' ? error.stderr.trim() : ''
    if (stderr !== '') {
      failures.push(`  ❌ 跑真解析器出错：${stderr.split('\n').slice(0, 3).join(' / ')}`)
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
  failures.push(`  ❌ 跑真解析器失败：${String(error.message).split('\n')[0]}`)
} finally {
  if (process.env.DIRECT_CHECK_KEEP !== '1') {
    rmSync(workDir, { recursive: true, force: true })
  }
}

// ——— 输出 ———
console.log('独立模式（内置直连）回归检查')
console.log(`源码：${clientPath}`)
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
