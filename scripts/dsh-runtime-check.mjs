#!/usr/bin/env node
/**
 * dsh-runtime-check.mjs —— `scripts/dsh-web.sh` 的「运行时选择」回归检查（零依赖）。
 *
 * 背景：老版 dsh-web.sh 把 node 路径写死（先 v24、后 v22），用户被迫降级；而鸿蒙上 node v24 会**偶发**
 * 起不来（V8 code-range 预留 mmap 失败 → `Fatal error in , line 0`）。新逻辑是「版本降序探测 + 启动失败
 * 自动换下一个」，本脚本用**假 node**（几行 shell）把每个分支跑出来：
 *
 *   ① 高版本起不来 → 自动退到能跑的版本（并把失败原因打进日志）
 *   ② 高版本能跑 → 用最高的那个（**这就是「兼容最新 node」**）
 *   ③ 开关按能力探测：原生有 `node:sqlite` 就不塞 `--experimental-sqlite`；loader 只在文件存在时挂
 *   ④ `NODE_BIN` 显式指定永远最先试，但它起不来时仍会自动兜底（不会把服务卡死）
 *   ⑤ 全都不行 → 退出码 1 + 明确提示
 *   ⑥ compat-loader 的垫片本身也按运行时能力分流（有原生 zstd 就不覆盖）
 *   ⑦ 每个启动脚本（dsh-web / dsh-update / dsh-hm-update / dsh-update-web）都走公共段 `node-runtime.sh`、
 *      都不写死 node 路径，且 `--print-node` 都挑「能跑的最高版本」（mjs 侧跟随 `process.execPath`）
 *   ⑧ 真机一致性：本机探测能给出报告（选不出来也要说清原因）
 *
 * 用法：node scripts/dsh-runtime-check.mjs
 * 退出码：0 = 全部通过；1 = 有检查失败。
 */
import { execFileSync, spawnSync } from 'node:child_process'
import { chmodSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const script = join(root, 'scripts', 'dsh-web.sh')
const work = join(root, '.gen-tmp', `runtime-check-${process.pid}`)
const failures = []
const notes = []

function check(name, ok, detail = '') {
  if (ok) notes.push(`  ✅ ${name}`)
  else failures.push(`  ❌ ${name}${detail === '' ? '' : ` —— ${detail}`}`)
}

/** 造一个假 node：`fakeNode(<版本>, { boots, nativeSqlite, acceptsSqliteFlag, acceptsLoader })` */
function fakeNode(file, { version, boots = true, nativeSqlite = false, acceptsSqliteFlag = true, acceptsLoader = true }) {
  const src = `#!/bin/sh
# 假 node ${version}
case "$1" in
  --version) echo "v${version}"; exit 0 ;;
esac
${boots ? '' : 'exit 1   # 模拟 V8 code-range 崩：任何调用都直接死'}
sqlite_flag=0
if [ "$1" = "--experimental-sqlite" ]; then
  ${acceptsSqliteFlag ? 'sqlite_flag=1; shift' : 'exit 1'}   # 认不认这个开关
fi
if [ "$1" = "--experimental-loader" ]; then
  ${acceptsLoader ? 'shift; shift' : 'exit 1'}
fi
case "$2" in
  *node:sqlite*)
    if [ "$sqlite_flag" = 1 ]; then exit 0; fi
    ${nativeSqlite ? 'exit 0' : 'exit 1'} ;;
esac
exit 0
`
  writeFileSync(file, src)
  chmodSync(file, 0o755)
  return file
}

function printNode(env) {
  const r = spawnSync('sh', [script, '--print-node'], {
    encoding: 'utf8',
    env: { ...process.env, ...env },
  })
  return { code: r.status, out: `${r.stdout || ''}${r.stderr || ''}` }
}

mkdirSync(work, { recursive: true })
const dshDir = join(work, 'dsh')
mkdirSync(dshDir, { recursive: true })
writeFileSync(join(dshDir, 'compat-loader.mjs'), '// 占位：让脚本认为这是鸿蒙部署（loader 存在）\n')

try {
  const old22 = fakeNode(join(work, 'node-v22'), { version: '22.7.0', nativeSqlite: false, acceptsSqliteFlag: true })
  const broken24 = fakeNode(join(work, 'node-v24-crash'), { version: '24.13.0', boots: false })
  const good24 = fakeNode(join(work, 'node-v24-ok'), { version: '24.13.0', nativeSqlite: true, acceptsSqliteFlag: false })
  // PORT 指向一个没人监听的端口：让「已在跑就幂等退出」这条捷径在测试里永远不生效（结果与本机是否正跑着 dsh 无关）
  const env = { DSH_DIR: dshDir, DSH_NODE_CANDIDATES: '', NODE_BIN: '', DSH_NODE_BIN: '', PORT: '59999' }

  // ① 高版本起不来 → 退到能跑的
  let r = printNode({ ...env, DSH_NODE_CANDIDATES: `${broken24}:${old22}` })
  check('node 24 起不来时自动退到 node 22（并说明失败原因）',
    r.code === 0 && r.out.includes(`选中：${old22}`) && /V8 code-range/.test(r.out),
    `code=${r.code} · ${r.out.split('\n').slice(0, 4).join(' / ')}`)
  check('v22 走能力探测：缺原生 node:sqlite → 自动补 --experimental-sqlite + compat-loader',
    r.out.includes('--experimental-sqlite') && r.out.includes('--experimental-loader'), r.out)

  // ② 高版本能跑 → 用最高的（兼容最新 node）
  r = printNode({ ...env, DSH_NODE_CANDIDATES: `${old22}:${good24}` })
  check('候选顺序无关：能跑的 node 24 一定被选中（这就是「支持最新 node」）',
    r.code === 0 && r.out.includes(`选中：${good24}`), r.out)
  check('node 24 原生有 node:sqlite → 不塞它可能不认的 --experimental-sqlite',
    !/--experimental-sqlite/.test(r.out), r.out)
  check('始终带 --expose-internals（dsh 的内部 loader 需要）', r.out.includes('--expose-internals'), r.out)

  // ③ loader 只在存在时挂
  r = printNode({ ...env, DSH_DIR: work, DSH_NODE_CANDIDATES: good24 })
  check('DSH_DIR 里没有 compat-loader.mjs 时不挂 loader（非鸿蒙部署按原生能力跑）',
    r.code === 0 && !/compat-loader/.test(r.out), r.out)

  // ④ 显式指定：最先试，起不来仍兜底
  r = printNode({ ...env, NODE_BIN: broken24, DSH_NODE_CANDIDATES: `${broken24}:${old22}` })
  check('NODE_BIN 显式指定起不来时自动兜底（服务不会卡死在坏二进制上）',
    r.code === 0 && r.out.includes(`选中：${old22}`), r.out)

  // ⑤ 全都不行 → 失败退出
  r = printNode({ ...env, DSH_NODE_CANDIDATES: broken24 })
  check('没有可用运行时 → 退出码 1 且给出指定办法',
    r.code === 1 && r.out.includes('DSH_NODE_BIN'), `code=${r.code} · ${r.out}`)

  // ⑥ compat-loader 必须是「运行时自适应」的：有原生 zstd 的运行时（node 24）走原生，缺的才落垫片
  const loader = readFileSync(join(root, 'scripts', 'compat-loader.mjs'), 'utf8')
  check('compat-loader 的 zlib 垫片按运行时能力分流（node 24 用原生 zstd，不再被纯 JS/WASM 覆盖）',
    /const HAS = \{/.test(loader) &&
    ['decompressSync', 'decompress', 'compress', 'compressSync', 'streamDecompress', 'streamCompress']
      .every((k) => loader.includes(`HAS.${k}`)),
    '缺少原生优先分流')
  const cjs = readFileSync(join(root, 'scripts', 'compat-loader-cjs.cjs'), 'utf8')
  check('CJS 孪生只在原生缺失时才补 zstd（worker 路径同样对 node 24 友好）',
    (cjs.match(/if \(typeof zlib\.\w*[Zz]std\w+ !== 'function'\)/g) || []).length >= 5, cjs.slice(-600))

  // ⑦ 每个启动脚本都走同一套自适应（别再有脚本把 node 路径写死成某一个版本）
  const launchers = ['dsh-web.sh', 'dsh-update.sh', 'dsh-hm-update.sh', 'dsh-update-web.sh']
  for (const name of launchers) {
    const src = readFileSync(join(root, 'scripts', name), 'utf8')
    check(`scripts/${name} source 公共运行时解析、不写死 node 路径`,
      /node-runtime\.sh/.test(src) && !/NODE="\$\{NODE_BIN:-\/data\//.test(src),
      '仍写死路径或没接公共段')
  }
  for (const name of ['dsh-update.sh', 'dsh-hm-update.sh', 'dsh-update-web.sh']) {
    const r = spawnSync('sh', [join(root, 'scripts', name), '--print-node'], {
      encoding: 'utf8', env: { ...process.env, ...env, DSH_NODE_CANDIDATES: `${broken24}:${old22}` },
    })
    check(`sh scripts/${name} --print-node 也会挑「能跑的最高版本」`,
      r.status === 0 && `${r.stdout || ''}`.includes(`选中：${old22}`),
      `code=${r.status} · ${`${r.stdout || ''}`.split('\n').slice(0, 3).join(' / ')}`)
  }
  // ⑧ `--print-node` 必须在「已在跑就幂等退出」之前；而真正开服时才探测（服务在跑时不做 3 次冒烟）
  const webSrc = readFileSync(join(root, 'scripts', 'dsh-web.sh'), 'utf8')
  const iPrint = webSrc.indexOf('if [ "$PRINT_ONLY" -eq 1 ]')
  const iUp = webSrc.indexOf('dsh-web: already running')
  const iDetect = webSrc.indexOf('node_runtime_detect ||')
  check('dsh-web.sh：--print-node 早于幂等退出、探测晚于幂等退出（服务在跑时零探测开销）',
    iPrint >= 0 && iUp > iPrint && iDetect > iUp,
    `print=${iPrint} up=${iUp} detect=${iDetect}`)

  const hmUpdate = readFileSync(join(root, 'scripts', 'dsh-hm-update.mjs'), 'utf8')
  check('dsh-hm-update.mjs 的子进程 node 跟随 process.execPath（不再写死 hnp v24 路径）',
    /process\.env\.NODE_BIN \|\| process\.execPath/.test(hmUpdate), '仍写死 node 路径')
  const hmInstall = readFileSync(join(root, 'scripts', 'dsh-hm-install.mjs'), 'utf8')
  check('dsh-hm-install.mjs 找 npm 先看当前 node 的 bin 目录',
    /join\(dirname\(process\.execPath\), name\)/.test(hmInstall), '没有跟随当前 node')
  check('dsh-hm-install.mjs 的 hnp 回退路径按版本 glob（hnp 升到 26 也不用改代码）',
    /readdirSync\(base\)/.test(hmInstall) && !/node_v\d/.test(hmInstall), '仍写死 hnp 版本')
  // 支持最新 node 的前提：哪都不许把版本钉死（node_v<数字> 就是 hnp 的某个具体版本目录）
  const pinned = readdirSync(join(root, 'scripts'))
    .filter((f) => /\.(sh|mjs|cjs)$/.test(f))
    .filter((f) => /node_v\d/.test(readFileSync(join(root, 'scripts', f), 'utf8')))
  check('scripts/ 下没有任何脚本写死 hnp 的 node 版本目录（node_v<数字>）',
    pinned.length === 0, pinned.join(', '))

  // ⑦ 真机一致性：本机（鸿蒙 PC）的真实探测结果
  const real = spawnSync('sh', [script, '--print-node'], { encoding: 'utf8' })
  check('真机探测不报错、能给出一份运行时报告（选不出来也要有原因）',
    real.status === 0 ? /选中：/.test(real.stdout) : /没有可用的 node/.test(real.stdout), real.stdout)
  notes.push(`  · 本机真实探测：${(real.stdout || '').split('\n').filter((l) => l.trim()).join(' | ')}`)
} finally {
  rmSync(work, { recursive: true, force: true })
}

console.log('dsh 运行时选择回归检查')
console.log(`被检对象：${script.replace(root + '/', '')} + 其它启动脚本 / 公共段 scripts/node-runtime.sh`)
console.log('')
for (const line of notes) console.log(line)
if (failures.length > 0) {
  console.log('')
  console.log('失败项：')
  for (const line of failures) console.log(line)
  console.log('')
  console.log(`结果：${notes.length} 项通过，${failures.length} 项失败`)
  process.exit(1)
}
console.log('')
console.log(`结果：全部 ${notes.length} 项通过`)
