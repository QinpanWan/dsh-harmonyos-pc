#!/usr/bin/env node
/**
 * 生成客户端内置对话模式目录（独立模式「开箱即用」的那份环境）。
 *
 * 数据源 = 本仓库 `presets/<id>/{preset.yml,agent.cordis.yml}`（dsh 部署侧真正在用的那套预设）：
 *   preset.yml        → id / name（产品名）/ description / order
 *   agent.cordis.yml  → persona 的 `prefix`（系统提示），支持 `>` / `>-` / `|` / `|-` / 行内标量
 *
 * 产物 = `client/entry/src/main/resources/rawfile/presets.json`，由客户端
 * `common/PresetCatalog.ets` 在启动时读入 → 对话模式胶囊的列表与文案、以及
 * 独立模式（内置直连）每次请求的 system 提示，都来自这份**唯一事实来源**：
 * 预设改了名字/提示，重新跑一次这个脚本即可，客户端不需要手改字符串。
 *
 * 用法：node scripts/gen-client-presets.mjs [--check]
 *   --check  只校验生成结果与磁盘一致（回归用），不写文件
 */
import fs from 'node:fs'
import path from 'node:path'

const repo = path.resolve(import.meta.dirname, '..')
const checkOnly = process.argv.slice(2).includes('--check')
const PRESETS_DIR = path.join(repo, 'presets')
const OUT = path.join(repo, 'client/entry/src/main/resources/rawfile/presets.json')

/** 取 yml 顶层标量（`key: value`，只看行首不缩进的那一行）。 */
function topScalar(text, key) {
  const match = new RegExp(`^${key}:\\s*(.*)$`, 'm').exec(text)
  if (match === null) return ''
  return unquote(match[1].trim())
}

function unquote(value) {
  if (value.length >= 2 && ((value.startsWith("'") && value.endsWith("'"))
    || (value.startsWith('"') && value.endsWith('"')))) {
    return value.slice(1, -1)
  }
  return value
}

/**
 * 取 persona 的 prefix：定位 `prefix:` 那一行，按 YAML 标量风格拼接后续缩进块。
 * `>` 折行成空格（空行成换行），`|` 原样保留换行；行内标量直接取值。
 */
function personaPrefix(text) {
  const lines = text.split('\n')
  let start = -1
  for (let i = 0; i < lines.length; i++) {
    if (/^\s+prefix:\s*/.test(lines[i])) {
      start = i
      break
    }
  }
  if (start === -1) return ''
  const head = /^\s+prefix:\s*(.*)$/.exec(lines[start])[1].trim()
  if (head.length > 0 && !/^[>|][+-]?$/.test(head)) {
    return unquote(head)
  }
  const folded = head.startsWith('>')
  const baseIndent = lines[start].length - lines[start].trimStart().length
  const body = []
  for (let i = start + 1; i < lines.length; i++) {
    const line = lines[i]
    if (line.trim().length === 0) {
      body.push('')
      continue
    }
    const indent = line.length - line.trimStart().length
    if (indent <= baseIndent) break
    body.push(line.trim())
  }
  const out = folded ? body.join('\n').replace(/([^\n])\n(?!\n)/g, '$1 ') : body.join('\n')
  return out.trim()
}

/** 客户端里 `{{model}}` / `{{cwd}}` 由 PresetCatalog 运行时替换，这里只做归一化空白。 */
function collect() {
  const ids = fs.readdirSync(PRESETS_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort()
  const presets = []
  for (const id of ids) {
    const presetFile = path.join(PRESETS_DIR, id, 'preset.yml')
    const agentFile = path.join(PRESETS_DIR, id, 'agent.cordis.yml')
    if (!fs.existsSync(presetFile) || !fs.existsSync(agentFile)) continue
    const presetText = fs.readFileSync(presetFile, 'utf8')
    const agentText = fs.readFileSync(agentFile, 'utf8')
    const orderRaw = topScalar(presetText, 'order')
    const order = orderRaw.length > 0 && Number.isFinite(Number(orderRaw)) ? Number(orderRaw) : 999
    presets.push({
      id,
      name: topScalar(presetText, 'name') || id,
      description: topScalar(presetText, 'description'),
      prompt: personaPrefix(agentText),
      order,
    })
  }
  presets.sort((a, b) => (a.order - b.order) || a.id.localeCompare(b.id))
  return {
    version: 1,
    source: 'presets/',
    note: '由 scripts/gen-client-presets.mjs 生成，勿手改；改了 presets/ 后重新生成。',
    presets: presets.map(({ id, name, description, prompt }) => ({ id, name, description, prompt })),
  }
}

const content = JSON.stringify(collect(), null, 2) + '\n'
if (checkOnly) {
  const current = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : ''
  if (current !== content) {
    console.error(`[gen-client-presets] 生成结果与磁盘不一致：${path.relative(repo, OUT)}`)
    process.exitCode = 1
  } else {
    console.log(`[gen-client-presets] 校验通过：${path.relative(repo, OUT)}`)
  }
} else {
  fs.mkdirSync(path.dirname(OUT), { recursive: true })
  fs.writeFileSync(OUT, content)
  const parsed = JSON.parse(content)
  const withPrompt = parsed.presets.filter((p) => p.prompt.length > 0).length
  console.log(`[gen-client-presets] 已写入 ${path.relative(repo, OUT)}：`
    + `${parsed.presets.length} 套对话模式（${withPrompt} 套带系统提示）`)
}
