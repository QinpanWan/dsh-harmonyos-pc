#!/usr/bin/env node
/**
 * 生成鸿蒙端 UI 资源（设计令牌 + 图标字形），**全部来自上游开源源码**，不做二次设计：
 *
 *   --tokens  packages/client/ui-theme/src/styles/design-platform.css
 *             → client/entry/src/main/ets/common/Tokens.ets（浅色/深色两套 --dsw-* 令牌，已解析 var()/color-mix）
 *   --app-icon apps/desktop/resources/icon-windows.svg
 *             → client/{entry/src/main/resources/base/media/icon.svg,startIcon.svg}
 *               + client/AppScope/resources/base/media/app_icon.svg（应用图标，零 transform 扁平化）
 *   --icons   packages/client/ui-primitives/src/icons/{index,shared-artwork}.tsx
 *             → client/entry/src/main/ets/common/Icons.ets（每个字形一个全局 @Builder，走 Shape.viewPort 缩放）
 *
 * ⚠️ 每个字形**必须**带 `strokeWidth`，纯填充字形写 `strokeWidth(0)`：
 *   ArkUI 的 `DrawingPainter::DrawPath`（arkui_ace_engine / drawing_painter.cpp）对每个 Path 固定
 *   「先用 brush 填色、再用 pen 描边」两次绘制，`SetPen()` 只在 `HasStrokeWidth() && NearZero(width)`
 *   时才返回 false 跳过一次。不写 strokeWidth 时 pen 取默认值 —— `STROKE_WIDTH_DEFAULT = 1.0_vp`、
 *   颜色 `GetStrokeValue(Color::BLACK)` ⇒ 浅色字形外会再套一圈 1vp 黑描边，观感就是「重影 + 不清晰」
 *   （2026-09-26 主人反馈的侧栏左上角 deepseekharness logo 即此）。strokeWidth(0) 不是「更细的描边」，
 *   而是**关掉第二次绘制**。
 *
 * 用法：node scripts/gen-harmony-ui-assets.mjs [--upstream <dsh 官方仓库根>] [--check]
 *   --upstream 默认取环境变量 DSH_UPSTREAM，回退到 ~/dsh-desktop-src/deepseek-harness-master
 *   --check    只校验生成结果与磁盘一致（CI/回归用），不写文件
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const repo = path.resolve(import.meta.dirname, '..')
const argv = process.argv.slice(2)
const argOf = (name, fallback) => {
  const i = argv.indexOf(name)
  return i === -1 ? fallback : argv[i + 1]
}
const checkOnly = argv.includes('--check')
const upstream = path.resolve(argOf('--upstream', process.env.DSH_UPSTREAM
  ?? path.join(os.homedir(), 'dsh-desktop-src', 'deepseek-harness-master')))

const APP_ICON = 'client/AppScope/resources/base/media/app_icon.svg'
const OUT_TOKENS = path.join(repo, 'client/entry/src/main/ets/common/Tokens.ets')
const OUT_ICONS = path.join(repo, 'client/entry/src/main/ets/common/Icons.ets')
const HEADER = `/* eslint-disable */
/**
 * 本文件由 scripts/gen-harmony-ui-assets.mjs 生成，请勿手改。
 * 数据源：${path.relative(os.homedir(), upstream)}（dsh 官方开源仓库）
 * 重新生成：node scripts/gen-harmony-ui-assets.mjs
 */
`

/* ---------------------------------------------------------------- CSS 解析 */

/** 去掉注释并切成 [selector, body] 列表（本仓库令牌表无嵌套规则）。 */
function cssBlocks(text) {
  const clean = text.replace(/\/\*[\s\S]*?\*\//g, '')
  const blocks = []
  const re = /([^{}]+)\{([^{}]*)\}/g
  let match
  while ((match = re.exec(clean)) !== null) {
    blocks.push([match[1].trim(), match[2]])
  }
  return blocks
}

/** body 声明块 → { '--token': rawValue } */
function declarations(body) {
  const out = new Map()
  for (const line of body.split(';')) {
    const at = line.indexOf(':')
    if (at === -1) continue
    const name = line.slice(0, at).trim()
    if (!name.startsWith('--')) continue
    out.set(name, line.slice(at + 1).trim())
  }
  return out
}

const clamp255 = (n) => Math.max(0, Math.min(255, Math.round(n)))

/** 归一化成 ArkUI 认识的颜色：#RRGGBB / #AARRGGBB / rgba(r,g,b,a) */
function normalizeColor(input) {
  const value = input.trim()
  const hex = value.match(/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i)
  if (hex !== null) {
    const digits = hex[1]
    if (digits.length === 3) return '#' + digits.split('').map((d) => d + d).join('').toUpperCase()
    if (digits.length === 8) return '#' + digits.slice(2).toUpperCase() + digits.slice(0, 2).toUpperCase()
    return '#' + digits.toUpperCase()
  }
  const rgb = value.match(/^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)\s*(?:[,/]\s*([\d.]+%?)\s*)?\)$/i)
  if (rgb !== null) {
    const [r, g, b] = [rgb[1], rgb[2], rgb[3]].map((part) => clamp255(Number(part)))
    const rawAlpha = rgb[4]
    if (rawAlpha === undefined) return '#' + [r, g, b].map((c) => c.toString(16).padStart(2, '0')).join('').toUpperCase()
    const alpha = rawAlpha.endsWith('%') ? Number(rawAlpha.slice(0, -1)) / 100 : Number(rawAlpha)
    if (alpha >= 1) return '#' + [r, g, b].map((c) => c.toString(16).padStart(2, '0')).join('').toUpperCase()
    return `rgba(${r}, ${g}, ${b}, ${Number(alpha.toFixed(4))})`
  }
  return value
}

/** 颜色字符串 → { r, g, b, a }（只处理归一化后的形式） */
function toRgba(color) {
  const hex = color.match(/^#([0-9a-f]{6})$/i)
  if (hex !== null) {
    const n = parseInt(hex[1], 16)
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255, a: 1 }
  }
  const rgba = color.match(/^rgba\((\d+), (\d+), (\d+), ([\d.]+)\)$/)
  if (rgba !== null) {
    return { r: Number(rgba[1]), g: Number(rgba[2]), b: Number(rgba[3]), a: Number(rgba[4]) }
  }
  return null
}

/** color-mix(in srgb, A [n%], B [m%])，本表只出现两参混合。 */
function mixColors(raw, resolve) {
  const inner = raw.replace(/^color-mix\(in srgb,\s*/i, '').replace(/\)\s*$/, '')
  const parts = []
  let depth = 0
  let current = ''
  for (const char of inner) {
    if (char === '(') depth += 1
    if (char === ')') depth -= 1
    if (char === ',' && depth === 0) {
      parts.push(current.trim())
      current = ''
      continue
    }
    current += char
  }
  parts.push(current.trim())
  if (parts.length !== 2) return null
  const weight = (part) => {
    const m = part.match(/\s([\d.]+)%$/)
    return m === null ? null : Number(m[1]) / 100
  }
  const leftColor = toRgba(normalizeColor(resolve(parts[0].replace(/\s[\d.]+%$/, '').trim())))
  const rightColor = toRgba(normalizeColor(resolve(parts[1].replace(/\s[\d.]+%$/, '').trim())))
  if (leftColor === null || rightColor === null) return null
  const p = weight(parts[1]) === null ? 0.5 : 1 - weight(parts[1])
  const mix = (key) => clamp255(leftColor[key] * p + rightColor[key] * (1 - p))
  const alpha = Number((leftColor.a * p + rightColor.a * (1 - p)).toFixed(4))
  if (alpha >= 1) {
    return '#' + [mix('r'), mix('g'), mix('b')].map((c) => c.toString(16).padStart(2, '0')).join('').toUpperCase()
  }
  return `rgba(${mix('r')}, ${mix('g')}, ${mix('b')}, ${alpha})`
}

/** 解析 var(--x) / var(--x, fallback) 与 color-mix，允许多层嵌套。 */
function resolveValue(raw, table, depth = 0) {
  if (depth > 12) return null
  const value = raw.trim()
  if (value.startsWith('color-mix(')) {
    return mixColors(value, (inner) => resolveValue(inner, table, depth + 1) ?? 'transparent')
  }
  if (!value.startsWith('var(')) return normalizeColor(value)
  const inner = value.slice(4, -1)
  const comma = inner.indexOf(',')
  const name = (comma === -1 ? inner : inner.slice(0, comma)).trim()
  const fallback = comma === -1 ? undefined : inner.slice(comma + 1).trim()
  const next = table.get(name)
  if (next !== undefined && next !== value) {
    const resolved = resolveValue(next, table, depth + 1)
    if (resolved !== null) return resolved
  }
  if (fallback !== undefined) return resolveValue(fallback, table, depth + 1)
  return null
}

/* --------------------------------------------------------------- 令牌生成 */

function tokenField(name) {
  const camel = name.replace(/^--/, '').split('-').map((part, index) => {
    if (index === 0) return part
    return part.length === 0 ? '' : part[0].toUpperCase() + part.slice(1)
  }).join('')
  return /^[0-9]/.test(camel) ? 't' + camel : camel
}

function buildPalettes() {
  const css = fs.readFileSync(path.join(upstream, 'packages/client/ui-theme/src/styles/design-platform.css'), 'utf8')
  const statics = { light: new Map(), dark: new Map() }
  const aliases = { light: new Map(), dark: new Map() }
  for (const [selector, body] of cssBlocks(css)) {
    // 只认 body / body[data-ds-dark-theme]；darwin 覆盖层留给桌面壳单独处理。
    if (/^body(\[data-ds-dark-theme\])?$/.test(selector) === false) continue
    const mode = selector.includes('data-ds-dark-theme') ? 'dark' : 'light'
    for (const [name, value] of declarations(body)) {
      if (name.startsWith('--dsw-static-')) statics[mode].set(name, value)
      else if (/^--dsw-(alias|specific|menu)-/.test(name)) aliases[mode].set(name, value)
    }
  }
  const palettes = {}
  for (const mode of ['light', 'dark']) {
    const table = new Map(statics[mode])
    for (const [name, value] of aliases[mode]) table.set(name, value)
    const resolved = new Map()
    for (const [name, value] of table) {
      const out = resolveValue(value, table)
      if (out !== null && !out.includes('var(')) resolved.set(name, out)
    }
    palettes[mode] = resolved
  }
  return palettes
}

function emitTokens(palettes) {
  const names = [...palettes.light.keys()].filter((name) => name.startsWith('--dsw-alias-') || name.startsWith('--dsw-specific-') || name.startsWith('--dsw-menu-'))
  const lines = [HEADER, '', '/** 上游 --dsw-* 令牌（design-platform.css），已解析为字面量。 */', 'export class Palette {']
  for (const name of names) {
    lines.push(`  /** ${name} */`)
    lines.push(`  ${tokenField(name)}: string = '${palettes.light.get(name)}';`)
  }
  lines.push('}', '')
  for (const mode of ['light', 'dark']) {
    const fn = mode === 'light' ? 'buildLight' : 'buildDark'
    lines.push(`function ${fn}(): Palette {`, '  const p: Palette = new Palette();')
    for (const name of names) {
      const value = palettes[mode].get(name)
      if (value === undefined) continue
      lines.push(`  p.${tokenField(name)} = '${value}';`)
    }
    lines.push('  return p;', '}', '')
  }
  lines.push('/** 浅色（上游 body 默认表）。 */', 'export const LIGHT: Palette = buildLight();', '')
  lines.push('/** 深色（上游 body[data-ds-dark-theme]）。 */', 'export const DARK: Palette = buildDark();', '')
  return lines.join('\n')
}

/* --------------------------------------------------------------- 图标生成 */

/** 一个 <svg> 的路径列表（fill=currentColor → 填充字形，否则描边字形）。 */
function svgPaths(svg) {
  const paths = []
  const pathRe = /<path([^>]*)\/>/g
  let pathMatch
  while ((pathMatch = pathRe.exec(svg)) !== null) {
    const attrs = pathMatch[1]
    const d = attrs.match(/\sd="([^"]+)"/)?.[1]
    if (d === undefined) continue
    const fill = /fill="currentColor"/.test(attrs)
    paths.push({
      d,
      fill,
      cap: /strokeLinecap="square"/.test(attrs) ? 'square' : (/strokeLinecap="round"/.test(attrs) ? 'round' : undefined),
    })
  }
  return paths
}

/** viewBox + width 表达式 → { width, height, ratio } */
function svgBox(svg) {
  const viewBox = svg.match(/viewBox="([^"]+)"/)
  if (viewBox === null) return undefined
  const [, , width, height] = viewBox[1].split(/\s+/).map(Number)
  const widthExpr = svg.match(/width=(\{[^}]*\}|"[^"]*")/)?.[1] ?? '{size}'
  const ratio = widthExpr.startsWith('"') ? Number(widthExpr.slice(1, -1)) / height
    : Number(/\*\s*([\d.]+)\s*\)\s*\/\s*([\d.]+)/.test(widthExpr)
      ? (Number(widthExpr.match(/\*\s*([\d.]+)/)[1]) / Number(widthExpr.match(/\/\s*([\d.]+)/)[1]))
      : 1)
  return { width, height, ratio }
}

function parseIcons() {
  const dir = path.join(upstream, 'packages/client/ui-primitives/src/icons')
  const source = ['index.tsx', 'shared-artwork.tsx']
    .map((file) => fs.readFileSync(path.join(dir, file), 'utf8'))
    .join('\n')
  const icons = new Map()
  const re = /(?:export\s+)?const\s+(\w+)\s*=\s*\([^)]*\)\s*=>\s*\(\s*<svg([\s\S]*?)<\/svg>\s*\)/g
  let match
  while ((match = re.exec(source)) !== null) {
    const rawName = match[1]
    const svg = match[2]
    if (icons.has(rawName)) continue
    const box = svgBox(svg)
    if (box === undefined) continue
    const paths = svgPaths(svg)
    if (paths.length === 0) continue
    icons.set(rawName, { width: box.width, height: box.height, ratio: box.ratio, paths })
  }
  // 权限字形不在 icons/ 目录（ui-primitives/src/PermissionIcon.tsx 的三个 Artwork），
  // 但 composer 的「工作区权限」胶囊要用（上游 PermissionIcon{ReadOnly,WorkspaceWrite,FullAccess}Regular）。
  const permissionFile = path.join(upstream, 'packages/client/ui-primitives/src/PermissionIcon.tsx')
  const permissionSource = fs.readFileSync(permissionFile, 'utf8')
  const permissionRe = /function\s+(\w+)Artwork\s*\([^)]*\)[^{]*\{[\s\S]*?<svg([\s\S]*?)<\/svg>/g
  while ((match = permissionRe.exec(permissionSource)) !== null) {
    const rawName = 'PermissionIcon' + match[1]
    const svg = match[2]
    if (icons.has(rawName)) continue
    const box = svgBox(svg)
    if (box === undefined) continue
    const paths = svgPaths(svg)
    if (paths.length === 0) continue
    icons.set(rawName, { width: box.width, height: box.height, ratio: box.ratio, paths, name: rawName })
  }
  return icons
}

function iconBuilderName(rawName) {
  const base = rawName.replace(/Artwork$/, '')
  return base.startsWith('Icon') ? base : 'Icon' + base
}

function emitIcons(icons) {
  const lines = [HEADER, '', '/** 图标入参：尺寸（vp）、颜色、描边宽度（上游 Regular=1 / Medium=1.3）。 */', 'export interface IconArgs {', '  size: number;', '  color: string;', '  strokeWidth?: number;', '  /** 反色（品牌字标「HARNESS」徽章 = --dsw-alias-label-primary-inverted）。 */', '  alt?: string;', '}', '']
  const emitted = []
  for (const [rawName, icon] of icons) {
    const name = icon.name === undefined ? iconBuilderName(rawName) : icon.name
    if (emitted.includes(name)) continue
    emitted.push(name)
    lines.push(`/** 上游 ${rawName}（viewBox 0 0 ${icon.width} ${icon.height}）。 */`)
    lines.push('@Builder')
    lines.push(`export function ${name}($$: IconArgs) {`)
    lines.push(`  Shape() {`)
    for (const path of icon.paths) {
      lines.push(`    Path()`)
      lines.push(`      .commands('${path.d}')`)
      if (path.fill) {
        lines.push('      .fill($$.color)')
        // 关掉 ArkUI 的第二次绘制（默认 pen = 黑色 1vp），否则字形被填色 + 描边画两遍 = 重影
        lines.push('      .strokeWidth(0)')
      } else {
        lines.push('      .fill(Color.Transparent)')
        lines.push('      .stroke($$.color)')
        lines.push('      .strokeWidth($$.strokeWidth ?? 1)')
        if (path.cap !== undefined) lines.push(`      .strokeLineCap(LineCapStyle.${path.cap === 'square' ? 'Square' : 'Round'})`)
        lines.push('      .strokeLineJoin(LineJoinStyle.Round)')
      }
    }
    lines.push('  }')
    lines.push(`  .viewPort({ x: 0, y: 0, width: ${icon.width}, height: ${icon.height} })`)
    lines.push('  .width($$.size)')
    lines.push(`  .height($$.size * ${(icon.height / icon.width).toFixed(6)})`)
    lines.push('}', '')
  }
  lines.push('/** 全部字形名（供检查/回退用）。 */')
  lines.push('export const ICON_NAMES: string[] = [')
  for (const name of emitted) lines.push(`  '${name}',`)
  lines.push(']', '')
  return lines.join('\n')
}

/**
 * 品牌字标：ui-primitives/src/BrandWordmark.tsx。
 *
 * 同一份美术，上游按 `includeMark` 给出两种 viewBox：
 *   mark=false → viewBox `26 0 156 24`：只有「DeepSeek HARNESS」字标 + 反色徽章，
 *                鲸鱼由 `sidebar.brand.mark` 槽位单独画（ui-sidebar 用的就是这一形态）。
 *   mark=true  → viewBox `0 0 182 24`：字标里**自带**那枚鲸鱼（上游默认值）。
 *
 * 产出两个 @Builder，宿主**同一次渲染只许用一套**：之前出过的 bug 正是「取了 mark=true 的整幅、
 * 又额外单独画了一枚鲸鱼」——同一头鲸鱼出现两次（主人看到的「重影」）。侧栏现在只用
 * `IconBrandFull`（一次画完），物理上不可能重影。
 */
function parseBrandParts() {
  const file = path.join(upstream, 'packages/client/ui-primitives/src/BrandWordmark.tsx')
  const source = fs.readFileSync(file, 'utf8')
  const svg = source.slice(source.indexOf('<svg'), source.indexOf('</svg>'))
  const body = svg.replace(/<defs>[\s\S]*?<\/defs>/, '')

  /** 把一段 svg 片段里的 path / rect 收集成扁平字形（mark 标记它是否属于鲸鱼）。 */
  const collect = (fragment, mark) => {
    const found = []
    const re = /<(path|rect)([^>]*)\/>/g
    let match
    while ((match = re.exec(fragment)) !== null) {
      const attrs = match[2]
      const fillRaw = attrs.match(/fill="([^"]*)"/)?.[1] ?? 'currentColor'
      const fill = fillRaw === 'currentColor' ? 'current' : (fillRaw.startsWith('var(') ? 'alt' : null)
      if (fill === null) continue
      if (match[1] === 'path') {
        const d = attrs.match(/\sd="([^"]+)"/)?.[1]
        if (d !== undefined) found.push({ d, fill, mark })
        continue
      }
      const num = (name, fallback = 0) => {
        const raw = attrs.match(new RegExp(`\\s${name}="([\\d.]+)"`))
        return raw === null ? fallback : Number(raw[1])
      }
      const [x, y, w, h, r] = [num('x'), num('y'), num('width'), num('height'), num('rx')]
      if (w > 0 && h > 0) {
        found.push({
          d: `M${x + r} ${y} L${x + w - r} ${y} A${r} ${r} 0 0 1 ${x + w} ${y + r} L${x + w} ${y + h - r}`
            + ` A${r} ${r} 0 0 1 ${x + w - r} ${y + h} L${x + r} ${y + h} A${r} ${r} 0 0 1 ${x} ${y + h - r}`
            + ` L${x} ${y + r} A${r} ${r} 0 0 1 ${x + r} ${y} Z`,
          fill,
          mark,
        })
      }
    }
    return found
  }

  // 鲸鱼在 `<g clipPath="url(#dsh-wordmark-whale-clip)">` 里；路径已由上游预平移好
  // （与 FishLogo 同一份轮廓，平移量 = clipPath 的 (0.1416, 3.52185)），无需再套 transform。
  const whale = /<g[^>]*dsh-wordmark-whale-clip[^>]*>([\s\S]*?)<\/g>/.exec(body)
  const mark = whale === null ? [] : collect(whale[1], true)
  const rest = whale === null ? body : body.replace(whale[0], '')
  return mark.concat(collect(rest, false))
}

/** 输出不含鲸鱼的字标（viewBox 26 0 156 24 = 上游 includeMark=false）。 */
function emitBrand(parts) {
  const lines = ['/** 上游 BrandWordmark includeMark=false（viewBox 26 0 156 24）——「DeepSeek HARNESS」字标，鲸鱼见 IconBrandFull / FishMark。 */', '@Builder', 'export function IconBrandWordmark($$: IconArgs) {', '  Shape() {']
  for (const part of parts) {
    if (part.mark) continue
    lines.push('    Path()')
    lines.push(`      .commands('${part.d}')`)
    lines.push(part.fill === 'alt' ? "      .fill($$.alt ?? '#FFFFFF')" : '      .fill($$.color)')
    lines.push('      .strokeWidth(0)')
  }
  lines.push('  }')
  lines.push('  .viewPort({ x: 26, y: 0, width: 156, height: 24 })')
  lines.push('  .width($$.size * 156 / 24)')
  lines.push('  .height($$.size)')
  lines.push('}', '')
  return lines.join('\n')
}

/** 输出整幅品牌标（viewBox 0 0 182 24 = 上游 includeMark 默认）——鲸鱼 + 字标，侧栏专用。 */
function emitBrandFull(parts) {
  const lines = ['/** 上游 BrandWordmark includeMark=true（viewBox 0 0 182 24）——鲸鱼 +「DeepSeek HARNESS」整幅。 */', '@Builder', 'export function IconBrandFull($$: IconArgs) {', '  Shape() {']
  for (const part of parts) {
    lines.push('    Path()')
    lines.push(`      .commands('${part.d}')`)
    lines.push(part.fill === 'alt' ? "      .fill($$.alt ?? '#FFFFFF')" : '      .fill($$.color)')
    lines.push('      .strokeWidth(0)')
  }
  lines.push('  }')
  lines.push('  .viewPort({ x: 0, y: 0, width: 182, height: 24 })')
  lines.push('  .width($$.size * 182 / 24)')
  lines.push('  .height($$.size)')
  lines.push('}', '')
  return lines.join('\n')
}

/* ---------------------------------------------------- 应用图标（零 transform 扁平版） */

const IDENTITY = { a: 1, b: 0, c: 0, d: 1, e: 0, f: 0 }

/** 矩阵合成：先 right 再做 left。 */
function multiply(left, right) {
  return {
    a: left.a * right.a + left.c * right.b,
    b: left.b * right.a + left.d * right.b,
    c: left.a * right.c + left.c * right.d,
    d: left.b * right.c + left.d * right.d,
    e: left.a * right.e + left.c * right.f + left.e,
    f: left.b * right.e + left.d * right.f + left.f,
  }
}

/** 只认本文件用到的 translate/scale（无旋转/斜切）。 */
function parseTransform(raw) {
  let matrix = IDENTITY
  for (const [, name, args] of raw.matchAll(/(translate|scale)\s*\(([^)]*)\)/g)) {
    const values = args.split(/[\s,]+/).filter((part) => part !== '').map(Number)
    matrix = name === 'translate'
      ? multiply(matrix, { ...IDENTITY, e: values[0] ?? 0, f: values[1] ?? 0 })
      : multiply(matrix, { ...IDENTITY, a: values[0] ?? 1, d: values[1] ?? values[0] ?? 1 })
  }
  return matrix
}

/** 数字字面量：三位小数、去掉负零。 */
function number(value) {
  const out = Number(Number(value).toFixed(3)) + 0
  return String(out === 0 ? 0 : out)
}

/** 把矩阵烘焙进 path 的 d：相对指令只缩放，绝对指令缩放后平移，圆弧 rx/ry 一并缩放。 */
function transformPathData(d, matrix) {
  const arity = { m: 2, l: 2, h: 1, v: 1, c: 6, s: 4, q: 4, t: 2, a: 7, z: 0 }
  const tokens = d.match(/[MmLlHhVvCcSsQqTtAaZz]|-?\d*\.?\d+(?:e[-+]?\d+)?/g) ?? []
  const out = []
  let command = 'M'
  let index = 0
  const absoluteX = (value) => number(matrix.a * value + matrix.e)
  const absoluteY = (value) => number(matrix.d * value + matrix.f)
  const scaledX = (value) => number(matrix.a * value)
  const scaledY = (value) => number(matrix.d * value)
  while (index < tokens.length) {
    if (/^[A-Za-z]$/.test(tokens[index])) {
      command = tokens[index]
      out.push(command)
      index += 1
      if (command.toLowerCase() === 'z') continue
    }
    const step = arity[command.toLowerCase()]
    if (step === undefined) break
    const args = tokens.slice(index, index + step)
    index += step
    const relative = command !== command.toUpperCase()
    const at = (value, axis) => (relative
      ? (axis === 'x' ? scaledX(value) : scaledY(value))
      : (axis === 'x' ? absoluteX(value) : absoluteY(value)))
    const lower = command.toLowerCase()
    if (lower === 'a') {
      out.push(scaledX(args[0]), scaledY(args[1]), number(args[2]), args[3], args[4], at(args[5], 'x'), at(args[6], 'y'))
    } else if (lower === 'h') {
      out.push(at(args[0], 'x'))
    } else if (lower === 'v') {
      out.push(at(args[0], 'y'))
    } else {
      for (let i = 0; i < args.length; i += 1) out.push(at(args[i], i % 2 === 0 ? 'x' : 'y'))
    }
  }
  return out.join(' ')
}

/** linearGradient → 各 stop 中值实色：ArkUI 对 SVG 渐变支持不保证，实色保证不会整块变黑。 */
function flattenGradients(source) {
  const flat = new Map()
  for (const [, id, body] of source.matchAll(/<linearGradient[^>]*\bid="([^"]+)"[^>]*>([\s\S]*?)<\/linearGradient>/g)) {
    const stops = [...body.matchAll(/stop-color="(#[\dA-Fa-f]{6})"/g)].map((stop) => stop[1])
    if (stops.length === 0) continue
    const mixed = [1, 3, 5].map((at) => Math.round(stops
      .reduce((sum, stop) => sum + parseInt(stop.slice(at, at + 2), 16), 0) / stops.length))
    flat.set(id, '#' + mixed.map((value) => value.toString(16).padStart(2, '0').toUpperCase()).join(''))
  }
  return flat
}

/** 应用图标：上游 apps/desktop/resources/icon-windows.svg（1024 圆角瓦片 + 官方鲸鱼）。
 *  只做三处「渲染器适配」，图形与上游逐点一致：
 *    ① 剥掉 filter/feGaussianBlur 投影层（ArkUI 不渲染 filter）；
 *    ② linearGradient 折成实色（ArkUI 对 SVG 渐变支持不保证）；
 *    ③ 把 <g>/<rect> 的 transform 烘焙进坐标 → 输出的 SVG 零 transform。 */
function emitAppIcon() {
  const source = fs.readFileSync(path.join(upstream, 'apps/desktop/resources/icon-windows.svg'), 'utf8')
  const flat = flattenGradients(source)
  const body = source
    .slice(source.indexOf('>', source.indexOf('<svg')) + 1, source.lastIndexOf('</svg>'))
    .replace(/<filter[\s\S]*?<\/filter>/g, '')
    .replace(/<defs>[\s\S]*?<\/defs>/g, '')
  const lines = ['<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">']
  let matrix = IDENTITY
  const stack = []
  const re = /<(\/?)(g|rect|path)\b([^>]*?)(\/?)>/g
  let match
  while ((match = re.exec(body)) !== null) {
    const [, closing, name, attrs, selfClosing] = match
    if (closing === '/') {
      matrix = stack.pop() ?? IDENTITY
      continue
    }
    const raw = attrs.match(/\stransform="([^"]+)"/)?.[1]
    if (name === 'g' && selfClosing === '') {
      stack.push(matrix)
      matrix = raw === undefined ? matrix : multiply(matrix, parseTransform(raw))
      continue
    }
    const local = raw === undefined ? matrix : multiply(matrix, parseTransform(raw))
    const style = attrs.match(/\sfill="([^"]+)"/)?.[1] ?? 'none'
    const fill = style.startsWith('url(#') ? flat.get(style.slice(5, -1)) ?? '#000000' : style
    const opacity = attrs.match(/\sfill-opacity="([^"]+)"/)?.[1]
    const paint = `fill="${fill}"${fill === 'none' || opacity === undefined ? '' : ` fill-opacity="${opacity}"`}`
    if (name === 'path') {
      lines.push(`<path d="${transformPathData(attrs.match(/\sd="([^"]+)"/)[1], local)}" ${paint}/>`)
      continue
    }
    const size = (key, fallback) => {
      const value = attrs.match(new RegExp(`\\s${key}="([\\d.]+)"`))
      return value === null ? fallback : Number(value[1])
    }
    const x = number(local.a * size('x', 0) + local.e)
    const y = number(local.d * size('y', 0) + local.f)
    const width = number(local.a * size('width', 0))
    const height = number(local.d * size('height', 0))
    const rx = size('rx', 0) === 0 ? null : number(local.a * size('rx', 0))
    lines.push(`<rect x="${x}" y="${y}" width="${width}" height="${height}"${rx === null ? '' : ` rx="${rx}"`} ${paint}/>`)
  }
  lines.push('</svg>', '')
  return lines.join('\n')
}

/* ------------------------------------------------------------------ 主流程 */

function write(file, content) {
  const existing = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null
  if (checkOnly) {
    if (existing !== content) {
      console.error(`[gen-ui-assets] 生成结果与磁盘不一致：${path.relative(repo, file)}`)
      process.exitCode = 1
      return
    }
    console.log(`[gen-ui-assets] 校验通过：${path.relative(repo, file)}`)
    return
  }
  fs.writeFileSync(file, content)
  console.log(`[gen-ui-assets] 已写入 ${path.relative(repo, file)}（${content.split('\n').length} 行）`)
}

const palettes = buildPalettes()
const icons = parseIcons()
write(OUT_TOKENS, emitTokens(palettes))
const brandParts = parseBrandParts()
write(OUT_ICONS, emitIcons(icons) + '\n' + emitBrand(brandParts) + '\n' + emitBrandFull(brandParts))
const icon = emitAppIcon()
write(path.join(repo, 'client/entry/src/main/resources/base/media/icon.svg'), icon)
write(path.join(repo, 'client/entry/src/main/resources/base/media/startIcon.svg'), icon)
write(path.join(repo, APP_ICON), icon)
console.log(`[gen-ui-assets] 令牌 ${palettes.light.size} 项 · 图标 ${icons.size} 个字形 · 来源 ${upstream}`)
