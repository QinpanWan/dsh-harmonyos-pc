#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# node 运行时自适应（各脚本 source 用；POSIX sh，零依赖）。
#
# 本方案**不锁 node 版本**：能用最新的就用最新的（官方基线要求 ≥22.18，上限跟着本机能跑的最高版本走 ——
# 当前最新线是 Node 26，现役 LTS 是 24），只有在某个二进制真起不来时才退到下一个 —— 用户不需要为了跑 dsh 去降级 node。
#
# 为什么需要自动降级：鸿蒙自带的 hnp node（v24.13）与 deveco 自带的 node（v22.7）都不在 PATH 里；
# 其中 node v24 在部分鸿蒙设备/受限通道上会在 V8 初始化阶段**偶发**原生崩
# （code-range 预留 mmap 失败 → `Fatal error in , line 0` / `Check failed: 12 == (*__errno_location())`，
# 没有官方开关可关；`--jitless` 能绕，代价是关 JIT + 没有 WASM），v22.7 反而稳定。
# 老脚本把路径写死成某一个版本 ⇒ 机器上正好是那个版本起不来时，用户被迫手动改路径。
#
# 做法：列出本机所有能找的 node（显式指定 > DSH_NODE_CANDIDATES > 自动扫 hnp/PATH/deveco/常见路径），
# 按**版本从高到低**逐个做 `-e 'process.exit(0)'` 冒烟（崩是偶发的，给 3 次机会），第一个真能起来的即选定。
#
# 环境变量：
#   NODE_BIN / DSH_NODE_BIN       显式指定（永远最先试，但起不来时仍会自动兜底，不会把服务卡死）
#   DSH_NODE_CANDIDATES           冒号分隔，只试这些
#   RUNTIME_DIR                   去哪找 compat-loader.mjs（默认 ${DSH_DIR:-$HOME/dsh-test}）
#
# 供外部使用：
#   node_runtime_detect           探测，设置 RUNTIME_NODE / RUNTIME_VER / RUNTIME_FLAGS /
#                                RUNTIME_OK_BINS（按偏好顺序，起不来的已剔除）/ RUNTIME_LOG
#                                返回码 0 = 有可用运行时，1 = 一个都没有
#   node_runtime_print            打印探测报告（`--print-node` 用；失败时给出候选来源与指定办法）
#   node_runtime_hint             打印「怎么显式指定」的提示
# ─────────────────────────────────────────────────────────────────────────────

# 版本比较：node_ver_gt A B → A > B（逐段比 major/minor/patch）
node_ver_gt() {
  _a=$(printf '%s' "$1" | tr -cd '0-9.'); _b=$(printf '%s' "$2" | tr -cd '0-9.')
  _i=1
  while [ "$_i" -le 3 ]; do
    _x=$(printf '%s' "$_a" | cut -d. -f"$_i"); _y=$(printf '%s' "$_b" | cut -d. -f"$_i")
    [ -z "$_x" ] && _x=0
    [ -z "$_y" ] && _y=0
    [ "$_x" -gt "$_y" ] 2>/dev/null && return 0
    [ "$_x" -lt "$_y" ] 2>/dev/null && return 1
    _i=$((_i + 1))
  done
  return 1
}

# 真能起进程吗？V8 code-range 崩是偶发的，给三次机会（起来过一次就算这二进制能用）
node_boots() {
  _nb=0
  while [ "$_nb" -lt 3 ]; do
    "$1" -e 'process.exit(0)' >/dev/null 2>&1 && return 0
    _nb=$((_nb + 1)); sleep 0.2
  done
  return 1
}

# 这个运行时该带哪些开关：能力探测决定，绝不塞它不认的参数
#   node:sqlite —— 22.x 要 --experimental-sqlite，23.4+ 默认可用
#   compat-loader —— 只在 RUNTIME_DIR 里存在时启用（鸿蒙运行时缺 zstd / fs-ext / flock 原生件才需要；
#                    非鸿蒙部署没有这个文件，就按运行时原生能力跑）
node_flags_for() {
  _rf='--expose-internals'
  if ! "$1" -e "require('node:sqlite');process.exit(0)" >/dev/null 2>&1; then
    if "$1" --experimental-sqlite -e "require('node:sqlite');process.exit(0)" >/dev/null 2>&1; then
      _rf="$_rf --experimental-sqlite"
    fi
  fi
  _rdir="${RUNTIME_DIR:-${DSH_DIR:-$HOME/dsh-test}}"
  if [ -f "$_rdir/compat-loader.mjs" ] && "$1" --experimental-loader "$_rdir/compat-loader.mjs" -e 'process.exit(0)' >/dev/null 2>&1; then
    _rf="$_rf --experimental-loader $_rdir/compat-loader.mjs"
  fi
  printf '%s' "$_rf"
}

node_runtime_hint() {
  echo "  也可显式指定：DSH_NODE_BIN=/path/to/node sh $0"
  echo "  （或 DSH_NODE_CANDIDATES=a:b 给出候选；只想看会选哪个：加 --print-node）"
}

node_runtime_detect() {
  # 候选：显式指定 > DSH_NODE_CANDIDATES > 自动扫（hnp 各版本 + PATH + deveco 自带 + 常见路径）
  _explicit=''
  [ -n "${NODE_BIN:-}" ] && _explicit="$NODE_BIN"
  [ -n "${DSH_NODE_BIN:-}" ] && _explicit="$_explicit $DSH_NODE_BIN"
  _pool=''
  if [ -n "${DSH_NODE_CANDIDATES:-}" ]; then
    _pool=$(printf '%s' "$DSH_NODE_CANDIDATES" | tr ':' ' ')
  else
    for _p in /data/service/hnp/node.org/node_*/bin/node; do
      [ -x "$_p" ] && _pool="$_pool $_p"
    done
    _sc=$(command -v node 2>/dev/null || true)
    [ -n "$_sc" ] && _pool="$_pool $_sc"
    for _p in "$HOME/deveco/deveco_tools/node/bin/node" /usr/local/bin/node /usr/bin/node "$HOME/.dsh/node/bin/node" "$HOME/.local/node/bin/node"; do
      [ -x "$_p" ] && _pool="$_pool $_p"
    done
  fi

  # 去重，然后按版本降序（选择排序；不依赖 sort 的 -V，鸿蒙的 busybox sort 不一定有）
  _uniq=''
  for _p in $_explicit $_pool; do
    _skip=0
    for _q in $_uniq; do [ "$_p" = "$_q" ] && _skip=1; done
    [ "$_skip" -eq 0 ] && _uniq="$_uniq $_p"
  done
  _sorted=''
  for _p in $_uniq; do
    _v=$("$_p" --version 2>/dev/null | tr -d 'v'); [ -z "$_v" ] && _v=0
    _placed=0; _new=''
    for _q in $_sorted; do
      if [ "$_placed" -eq 0 ]; then
        _qv=$("$_q" --version 2>/dev/null | tr -d 'v'); [ -z "$_qv" ] && _qv=0
        if node_ver_gt "$_v" "$_qv"; then _new="$_new $_p"; _placed=1; fi
      fi
      _new="$_new $_q"
    done
    [ "$_placed" -eq 0 ] && _new="$_new $_p"
    _sorted="$_new"
  done
  # 显式指定的排最前（用户说了算），其余按版本降序
  _ordered=''
  for _p in $_explicit; do _ordered="$_ordered $_p"; done
  for _p in $_sorted; do
    _dup=0
    for _q in $_explicit; do [ "$_p" = "$_q" ] && _dup=1; done
    [ "$_dup" -eq 0 ] && _ordered="$_ordered $_p"
  done

  # 逐个探测：起不来就记一笔，能起来就进候选（按偏好顺序）
  RUNTIME_LOG=''; RUNTIME_OK_BINS=''
  for _p in $_ordered; do
    _v=$("$_p" --version 2>/dev/null | tr -d 'v')
    if [ -z "$_v" ]; then
      RUNTIME_LOG="$RUNTIME_LOG
  ✗ $_p —— 不是可执行的 node（--version 失败）"
      continue
    fi
    if ! node_boots "$_p"; then
      RUNTIME_LOG="$RUNTIME_LOG
  ✗ $_p (v$_v) —— 起不来（V8 code-range/mmap 崩，连续三次都失败）"
      continue
    fi
    RUNTIME_OK_BINS="$RUNTIME_OK_BINS $_p"
    RUNTIME_LOG="$RUNTIME_LOG
  ✓ $_p (v$_v) —— 可用"
  done

  RUNTIME_NODE=$(printf '%s' "$RUNTIME_OK_BINS" | awk '{print $1}')
  RUNTIME_VER=''
  RUNTIME_FLAGS=''
  [ -z "$RUNTIME_NODE" ] && return 1
  RUNTIME_VER=$("$RUNTIME_NODE" --version 2>/dev/null | tr -d 'v')
  RUNTIME_FLAGS=$(node_flags_for "$RUNTIME_NODE")
  return 0
}

# 只探测、不启动（`--print-node`）：把「选了谁 / 带什么开关 / 备选是谁」讲清楚
node_runtime_print() {
  echo "运行时探测（显式指定优先，其余按版本从高到低）："
  printf '%s\n' "$RUNTIME_LOG" | sed '/^$/d'
  if [ -n "$RUNTIME_NODE" ]; then
    echo "选中：$RUNTIME_NODE (v$RUNTIME_VER)"
    echo "开关：$RUNTIME_FLAGS"
    echo "备用：$RUNTIME_OK_BINS"
    return 0
  fi
  echo "没有可用的 node。候选来源：hnp(/data/service/hnp/node.org/node_*/bin/node)、deveco(~/deveco/deveco_tools/node/bin/node)、PATH 里的 node"
  node_runtime_hint
  return 1
}
