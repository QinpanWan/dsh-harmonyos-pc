#!/bin/sh
# dsh-harmonyos 一键更新:官方 dsh 升级 + 本仓库预设/插件/补丁同步。
# 用法: sh scripts/dsh-hm-update.sh [check|update|--print-node]   （默认 update）
# node 不锁版本：公共段自动挑「本机能跑起来的最高版本」（Node 24 优先，起不来自动退 22）。
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/node-runtime.sh"
RUNTIME_DIR="${DSH_DIR:-$HOME/dsh-test}"
for a in "$@"; do
  case "$a" in
    --print-node|--print-runtime) node_runtime_detect; _rc=$?; node_runtime_print; exit $_rc ;;
    -h|--help) echo "用法: sh scripts/dsh-hm-update.sh [check|update|--print-node]"; exit 0 ;;
  esac
done
if ! node_runtime_detect; then
  echo "dsh-hm-update: 找不到能跑起来的 node$RUNTIME_LOG"
  node_runtime_hint
  exit 1
fi
# shellcheck disable=SC2086
exec "$RUNTIME_NODE" $RUNTIME_FLAGS "$SCRIPT_DIR/dsh-hm-update.mjs" "$@"
