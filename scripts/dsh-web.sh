#!/bin/sh
mkdir -p "$HOME/dsh-diag/reports" 2>/dev/null
# dsh web 服务:启动/重启 (127.0.0.1:3080)。用法: sh scripts/dsh-web.sh [--print-node]
# 环境变量可覆盖: NODE_BIN / DSH_NODE_BIN(指定 node) DSH_NODE_CANDIDATES(冒号分隔候选)
#                 DSH_DIR(dsh 安装目录) PATCH_YML(适配补丁) PORT LOG START_TIMEOUT
# Node 版本：**不锁定版本**。脚本自动探测本机可用的 node（hnp 自带 v24 / deveco 自带 v22 / PATH 里的），
#   按版本从高到低试，先跑一个 `-e` 冒烟（鸿蒙上 node v24 有 V8 code-range 偶发原生崩），
#   选定后起服务；起不来就自动换下一个候选 —— 用户**不需要为了跑 dsh 去降 node 版本**。
#   想知道会选哪个：`sh scripts/dsh-web.sh --print-node`（只探测、不启动、不动在跑的服务）。
# 补丁默认定位仓库内 harmony.patch.yml；日志采用追加+run 头部, 避免每次重启清空导致无法看崩溃现场。
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DIR="${DSH_DIR:-$HOME/dsh-test}"
. "$SCRIPT_DIR/node-runtime.sh"
PATCH="${PATCH_YML:-$SCRIPT_DIR/../harmony.patch.yml}"
PORT="${PORT:-3080}"
LOG="${LOG:-$HOME/dsh-web.log}"
PIDF="$HOME/dsh-web.pid"
START_TIMEOUT="${START_TIMEOUT:-30}"     # 每个候选运行时的健康检查窗口（秒）
PRINT_ONLY=0
for a in "$@"; do
  case "$a" in
    --print-node|--print-runtime) PRINT_ONLY=1 ;;
    -h|--help) echo "用法: sh scripts/dsh-web.sh [--print-node]"; echo "  环境变量: NODE_BIN/DSH_NODE_BIN(指定 node) DSH_NODE_CANDIDATES(冒号分隔候选)"; echo "            DSH_DIR PATCH_YML PORT LOG START_TIMEOUT"; exit 0 ;;
  esac
done

is_up() {
  /usr/bin/curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/" 2>/dev/null
}

# ——— 运行时解析：公共段在 scripts/node-runtime.sh（各启动脚本共用；Node 24 优先、22 兜底）———
RUNTIME_DIR="$DIR"

if [ "$PRINT_ONLY" -eq 1 ]; then
  node_runtime_detect; _rc=$?
  node_runtime_print
  exit $_rc
fi

# 已经在跑就直接幂等退出 —— 不探测（省掉「v24 崩三次」那点冒烟开销），也不动在跑的服务
if is_up; then
  echo "dsh-web: already running at http://127.0.0.1:$PORT/ (skip)"
  exit 0
fi

node_runtime_detect || { echo "dsh-web: 找不到能跑起来的 node$RUNTIME_LOG"; node_runtime_hint; exit 1; }
NODE="$RUNTIME_NODE"; NODE_VER="$RUNTIME_VER"; NODE_FLAGS="$RUNTIME_FLAGS"; OK_BINS="$RUNTIME_OK_BINS"
echo "dsh-web: 运行时 $NODE (v$NODE_VER)"

# 孤儿锁清理：dsh 的 atomic-write 从不回收孤儿锁（SIGKILL/崩溃退出会留下 .dsh/profiles/*.lock、
# ~/.dsh/.credentials.yaml.lock），不清下次启动即「timed out waiting for the writer lock」。
# 仅在确认本脚本要拉起服务(无 dsh 在跑)时调用，避免误删在跑进程持有的锁。
clear_stale_locks() {
  for lk in "$HOME/.dsh"/profiles/*.lock "$HOME/.dsh"/profiles/*/*.lock "$HOME/.dsh"/.credentials.yaml.lock; do
    [ -e "$lk" ] && rm -f "$lk"
  done
}

cd "$DIR" || { echo "dsh-web: no dir $DIR"; exit 1; }
if [ ! -d "$DIR/node_modules/@deepseek-ai/dsh" ]; then
  echo "dsh-web: dsh not installed at $DIR"
  exit 1
fi
ps -ef 2>/dev/null | grep -F "dsh/lib/bin.js" | grep -v grep \
  | awk '{print $2}' | while read p; do kill "$p" 2>/dev/null; done
sleep 0.3
clear_stale_locks

# 插件市场目录本地镜像（鸿蒙上 node 直连外网 fetch 不可靠，用 curl 下载到本地再走 127.0.0.1 静态服务）
MC_DIR="$HOME/.dsh/market-catalog"
MC_PORT=3988
MC_LOG="$MC_DIR/server.log"
mkdir -p "$MC_DIR"
if command -v curl >/dev/null 2>&1; then
  curl -s --max-time 25 -o "$MC_DIR/plugins.json.tmp" https://awesome-dsh-plugin.com/plugins.json \
    && mv "$MC_DIR/plugins.json.tmp" "$MC_DIR/plugins.json" 2>/dev/null
  rm -f "$MC_DIR/plugins.json.tmp"
fi
if ! curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$MC_PORT/plugins.json"; then
  pkill -f "http.server $MC_PORT" 2>/dev/null
  nohup python3 -m http.server "$MC_PORT" --bind 127.0.0.1 --directory "$MC_DIR" > "$MC_LOG" 2>&1 &
fi
export DSHM_REGISTRY_URL="http://127.0.0.1:$MC_PORT/plugins.json"

# 逐个候选运行时试：起不来（含 node 24 那类偶发原生崩）就自动换下一个，换完还不行才报失败
STARTED=0
for _bin in $OK_BINS; do
  _flags=$(node_flags_for "$_bin")
  _ver=$("$_bin" --version 2>/dev/null | tr -d 'v')
  echo "===== dsh-web start $(date '+%F %T') runtime=$_bin v$_ver =====" >> "$LOG"
  # shellcheck disable=SC2086
  nohup "$_bin" $_flags \
    --report-on-fatalerror --report-uncaught-exception --report-directory="$HOME/dsh-diag/reports" \
    node_modules/@deepseek-ai/dsh/lib/bin.js \
    --profile web --patch "$PATCH" --no-open >> "$LOG" 2>&1 &
  _pid=$!
  echo "$_pid" > "$PIDF"

  _n=0
  while [ "$_n" -lt "$START_TIMEOUT" ]; do
    is_up && break
    kill -0 "$_pid" 2>/dev/null || break      # 进程已退出（原生崩/启动报错），别干等
    _n=$((_n + 1)); sleep 1
  done

  if is_up; then
    STARTED=1
    NODE="$_bin"; NODE_VER="$_ver"; NODE_FLAGS="$_flags"
    echo "dsh-web: http://127.0.0.1:$PORT/ (pid $_pid, $NODE v$NODE_VER)"
    break
  fi

  kill "$_pid" 2>/dev/null
  echo "dsh-web: $_bin (v$_ver) 没起来，换下一个候选运行时" >&2
  tail -n 3 "$LOG" >&2
done

if [ "$STARTED" -eq 0 ]; then
  echo "dsh-web: FAILED to start（候选运行时都试过了，见 $LOG）"
  tail -n 5 "$LOG"
  exit 1
fi
