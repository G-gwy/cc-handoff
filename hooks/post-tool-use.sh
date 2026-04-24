#!/usr/bin/env bash
# post-tool-use.sh —— 监测上下文用量，只写状态文件
# 不输出 systemMessage（Claude Code 对 PostToolUse 的注入机制不稳定，靠 UserPromptSubmit 统一注入）
set -u

CC_HANDOFF_DIR="$HOME/.claude/cc-handoff"
source "$CC_HANDOFF_DIR/lib/pwd-slug.sh"
source "$CC_HANDOFF_DIR/lib/config.sh"
source "$CC_HANDOFF_DIR/lib/usage.sh"
source "$CC_HANDOFF_DIR/lib/handoff-io.sh"

input="$(cat)"
cwd="$(echo "$input" | jq -r '.cwd // empty')"
cwd="${cwd:-$(pwd)}"
session_id="$(echo "$input" | jq -r '.session_id // "unknown"')"
transcript="$(echo "$input" | jq -r '.transcript_path // empty')"

cfg="$(cc_load_config "$cwd")"
cc_config_enabled "$cfg" || exit 0
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

usage_json="$(cc_latest_usage "$transcript" "$cfg")"
pct="$(echo "$usage_json" | jq -r '.pct // 0')"
threshold="$(cc_config_threshold "$cfg")"
tier="$(cc_compute_tier "$pct" "$threshold")"

# 追加 tier 字段后写状态
enriched="$(echo "$usage_json" | jq --argjson t "$tier" '. + {tier:$t}')"
usage_file="$(cc_state_file "$cwd" "$session_id" "usage")"
echo "$enriched" > "$usage_file" 2>/dev/null || true

cc_debug_log "PostToolUse" "session=$session_id pct=$pct tier=$tier"

# 不输出 systemMessage（不可靠），始终空响应
exit 0
