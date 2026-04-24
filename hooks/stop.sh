#!/usr/bin/env bash
# stop.sh —— AI 回合结束时
# Phase 0：只做日志，不做阻断；后续扩展可检测 todo 完成度 / 自动归档
set -u

CC_HANDOFF_DIR="$HOME/.claude/cc-handoff"
source "$CC_HANDOFF_DIR/lib/pwd-slug.sh"
source "$CC_HANDOFF_DIR/lib/config.sh"
source "$CC_HANDOFF_DIR/lib/handoff-io.sh"

input="$(cat)"
cwd="$(echo "$input" | jq -r '.cwd // empty')"
cwd="${cwd:-$(pwd)}"

cfg="$(cc_load_config "$cwd")"
cc_config_enabled "$cfg" || exit 0

# 清理过期状态文件，不打扰 AI
cc_cleanup_stale_state "$cwd" 7 || true

# 空响应即"允许停止"
echo '{}'
exit 0
