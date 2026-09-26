#!/bin/sh
# dsh 设置与更新页(3098):启动/重启。用法: sh scripts/dsh-update-web.sh [--print-node]
# node 不锁版本：公共段自动挑「本机能跑起来的最高版本」（Node 24 优先，起不来自动退 22）。
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/node-runtime.sh"
RUNTIME_DIR="${DSH_DIR:-$HOME/dsh-test}"
for a in "$@"; do
  case "$a" in
    --print-node|--print-runtime) node_runtime_detect; _rc=$?; node_runtime_print; exit $_rc ;;
    -h|--help) echo "用法: sh scripts/dsh-update-web.sh [--print-node]"; exit 0 ;;
  esac
done
PORT=3098
LOG="$HOME/dsh-update-web.log"
PIDF="$HOME/dsh-update-web.pid"

is_up() {
  /usr/bin/curl -s -o /dev/null --fail --max-time 1 "http://127.0.0.1:$PORT/" 2>/dev/null
}
if is_up; then
  echo "dsh-update-web: already running at http://127.0.0.1:$PORT/ (skip)"
  exit 0
fi

# 真要开服务了才探测运行时（已在跑就零开销退出）
if ! node_runtime_detect; then
  echo "dsh-update-web: 找不到能跑起来的 node$RUNTIME_LOG"
  node_runtime_hint
  exit 1
fi
echo "dsh-update-web: 运行时 $RUNTIME_NODE (v$RUNTIME_VER)"
ps -ef 2>/dev/null | grep -F "dsh-update-web.mjs" | grep -v grep \
  | awk '{print $2}' | while read p; do kill "$p" 2>/dev/null; done
sleep 0.3
# shellcheck disable=SC2086
nohup "$RUNTIME_NODE" $RUNTIME_FLAGS "$DIR/dsh-update-web.mjs" > "$LOG" 2>&1 &
echo $! > "$PIDF"
for i in 1 2 3 4 5 6 7 8 9 10; do
  is_up && break
  sleep 0.3
done
if is_up; then
  echo "dsh-update-web: http://127.0.0.1:$PORT/ (pid $(cat "$PIDF"))"
else
  echo "dsh-update-web: FAILED to start (see $LOG)"
  head -5 "$LOG"
  exit 1
fi
