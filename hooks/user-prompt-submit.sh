#!/usr/bin/env bash
# user-prompt-submit.sh —— 唯一可靠的注入点
# 职责：
#   1) 首次注入未完成 handoff（保留原逻辑）
#   2) 按档位持续注入警告（每次用户发话都检查，档位越高语气越强）
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

# /fresh 标记本会话关闭
fresh_file="$(cc_state_file "$cwd" "$session_id" "fresh")"
[ -f "$fresh_file" ] && { cc_debug_log "UserPromptSubmit" "session=$session_id skipped=fresh"; exit 0; }

# ========== 组装要注入的消息（可能包含 handoff + tier 警告两段）==========
msg_parts=()

# -- 段 1：首次注入 handoff --
# 0 个 → 静默；1 个 → 注入结构化摘要 + id；2+ 个 → 提示用户敲 /resume 选择
injected_file="$(cc_state_file "$cwd" "$session_id" "injected")"
if [ ! -f "$injected_file" ]; then
    count="$(cc_count_active_for_hash "$cwd" | tr -d '[:space:]')"
    count="${count:-0}"
    if [ "$count" = "1" ]; then
        handoff="$(cc_find_handoff "$cwd")"
        if [ -n "$handoff" ] && [ -f "$handoff" ]; then
            touch "$injected_file"
            cc_cleanup_stale_state "$cwd" 7
            # 提取 frontmatter 关键字段与 🎯 目标首行（sed 保留冒号后完整值）
            h_id="$(sed -n 's/^id: *//p' "$handoff" | head -1)"
            h_status="$(sed -n 's/^status: *//p' "$handoff" | head -1)"
            h_updated="$(sed -n 's/^updated: *//p' "$handoff" | head -1 | cut -c1-16 | tr 'T' ' ')"
            h_goal="$(awk '/^## 🎯/{flag=1;next} flag && NF>0 && !/^#/{print; exit}' "$handoff" | cut -c1-80)"
            [ -z "$h_goal" ] && h_goal="(未填写 🎯 目标)"
            msg_parts+=("⚡ cc-handoff：承接中（id: ${h_id:-unknown}）

  🎯 ${h_goal}
  ⏰ ${h_updated:-?} · ${h_status:-?}

AI 请 Read 续作：${handoff}
/handoff 时复用 id=${h_id:-unknown}（推进同一业务，避免分叉）。
管理（切换/删除/静默本会话）→ /resume")
        fi
    elif [ "$count" != "0" ]; then
        touch "$injected_file"
        cc_cleanup_stale_state "$cwd" 7
        msg_parts+=("⚡ cc-handoff：本 worktree 有 ${count} 个未完成交接。
请敲 /resume 选择承接 / 删除 / 静默。")
    fi
fi

# -- 段 2：档位警告 --
# 自己从 transcript 算 usage（权威来源），不依赖 PostToolUse 的缓存（可能过期或缺字段）
pct="0"
tokens=0
limit=200000
tier=0
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    usage_json="$(cc_latest_usage "$transcript" "$cfg")"
    pct="$(echo "$usage_json" | jq -r '.pct // 0')"
    tokens="$(echo "$usage_json" | jq -r '.tokens // 0')"
    limit="$(echo "$usage_json" | jq -r '.limit // 200000')"
    threshold="$(cc_config_threshold "$cfg")"
    tier="$(cc_compute_tier "$pct" "$threshold")"

    # 同步写 .usage 缓存文件（供 ccline 等外部工具读）
    usage_file="$(cc_state_file "$cwd" "$session_id" "usage")"
    echo "$usage_json" | jq --argjson t "$tier" '. + {tier:$t}' > "$usage_file" 2>/dev/null || true
fi

if [ "$tier" -gt 0 ] 2>/dev/null; then
    pct_fmt="$(cc_format_pct "$pct")"

    # 说明：Claude Code 会把 systemMessage 用 "⎿ UserPromptSubmit says: ..." 的形式
    # 直接展示给用户（而不是作为"给 AI 的指令"注入）。因此这里不要写给 AI 的指令，
    # 直接把预警写成面向用户的一行短信息即可——档位越高越醒目。
    case "$tier" in
        1)
            msg_parts+=("📊 上下文 ${pct_fmt} · 可以开始考虑 /handoff 交接")
            ;;
        2)
            msg_parts+=("⚠️ 上下文 ${pct_fmt} · 建议尽早 /handoff 打包 + /clear 新开会话")
            ;;
        3)
            msg_parts+=("🚨 上下文 ${pct_fmt} · 已进入危险区，强烈建议立即 /handoff + /clear（避免回答质量下降）")
            ;;
        4)
            msg_parts+=("⛔ 上下文 ${pct_fmt} · 即将耗尽！请立即 /handoff 打包后 /clear 重开会话")
            ;;
    esac
fi

cc_debug_log "UserPromptSubmit" "session=$session_id pct=$pct tier=$tier msg_count=${#msg_parts[@]}"

# 输出（只有 msg_parts 非空才输出 systemMessage）
if [ ${#msg_parts[@]} -gt 0 ]; then
    # 用两个空行拼接各段
    combined=""
    for p in "${msg_parts[@]}"; do
        if [ -z "$combined" ]; then
            combined="$p"
        else
            combined="$combined

---

$p"
        fi
    done
    jq -n --arg msg "$combined" '{systemMessage: $msg}'
fi

exit 0
