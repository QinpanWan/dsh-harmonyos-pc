#!/bin/sh
# dsh 检查更新：终端一键。用法: sh scripts/dsh-update.sh [check|patch|install|rollback]
# node 不锁版本：公共段自动挑「本机能跑起来的最高版本」（Node 24 优先，起不来自动退 22，
# 显式指定用 NODE_BIN/DSH_NODE_BIN）；只想看会选哪个：加 --print-node。
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/node-runtime.sh"
RUNTIME_DIR="${DSH_DIR:-$HOME/dsh-test}"
for a in "$@"; do
  case "$a" in
    --print-node|--print-runtime) node_runtime_detect; _rc=$?; node_runtime_print; exit $_rc ;;
    -h|--help) echo "用法: sh scripts/dsh-update.sh [check|patch|install|rollback|--print-node]"; exit 0 ;;
  esac
done
if ! node_runtime_detect; then
  echo "dsh-update: 找不到能跑起来的 node$RUNTIME_LOG"
  node_runtime_hint
  exit 1
fi
# shellcheck disable=SC2086
exec "$RUNTIME_NODE" $RUNTIME_FLAGS "$SCRIPT_DIR/dsh-update.mjs" "$@"
