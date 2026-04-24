#!/usr/bin/env bash
# usage.sh —— 从 transcript.jsonl 提取最新上下文用量
# 真实上下文 = input_tokens + cache_creation_input_tokens + cache_read_input_tokens

# 从 transcript 尾部往上找最近一条带 usage 的 assistant message
# 返回：JSON { "tokens": N, "model": "xxx", "pct": 0.xx }
cc_latest_usage() {
    local transcript="$1"
    local config="$2"

    [ -f "$transcript" ] || { echo '{"tokens":0,"model":"","pct":0,"error":"no_transcript"}'; return; }

    # tail -200 覆盖常见场景，避免全文扫描
    local usage_line
    usage_line="$(tail -200 "$transcript" 2>/dev/null \
        | jq -c 'select(.type=="assistant" and .message.usage) | .message.usage + {model:.message.model}' 2>/dev/null \
        | tail -1)"

    if [ -z "$usage_line" ]; then
        echo '{"tokens":0,"model":"","pct":0,"error":"no_usage"}'
        return
    fi

    local tokens model limit pct
    tokens="$(echo "$usage_line" | jq -r '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')"
    model="$(echo "$usage_line" | jq -r '.message.model // .model // ""')"

    # 上限决策顺序：config.context_limit > settings.model 别名（含 [1m]）> model_limits[model] > default
    limit="$(echo "$config" | jq -r '.context_limit // empty')"

    if [ -z "$limit" ] || [ "$limit" = "null" ]; then
        # 读 Claude Code 的模型别名（opus[1m] / sonnet[1m] / opus 等）
        local alias=""
        if [ -f "$HOME/.claude/settings.json" ]; then
            alias="$(jq -r '.model // ""' "$HOME/.claude/settings.json" 2>/dev/null)"
        fi

        if [[ "$alias" == *"[1m]"* ]]; then
            limit=1000000
        else
            limit="$(echo "$config" | jq -r --arg m "$model" '.model_limits[$m] // .model_limits.default // 200000')"
        fi
    fi

    if [ -z "$limit" ] || [ "$limit" -le 0 ] 2>/dev/null; then
        limit=200000
    fi

    pct="$(awk -v t="$tokens" -v l="$limit" 'BEGIN { printf "%.4f", t/l }')"

    jq -n \
        --argjson tokens "$tokens" \
        --arg model "$model" \
        --argjson limit "$limit" \
        --argjson pct "$pct" \
        '{tokens:$tokens, model:$model, limit:$limit, pct:$pct}'
}

cc_format_pct() {
    local pct="$1"
    awk -v p="$pct" 'BEGIN { printf "%.1f%%", p*100 }'
}

# 档位计算：0=静默 / 1=温和 / 2=明确 / 3=强制 / 4=紧急
# 阈值可由 config.threshold 决定 Tier 1 起点，后续档位在 Tier1 之上按 +15% / +35% / +55% 线性
# 默认（threshold=0.35）：1=[35,50) 2=[50,70) 3=[70,90) 4=>=90
cc_compute_tier() {
    local pct="$1"
    local threshold="${2:-0.35}"
    awk -v p="$pct" -v t="$threshold" 'BEGIN {
        if (p < t)           print 0
        else if (p < 0.50)   print 1
        else if (p < 0.70)   print 2
        else if (p < 0.90)   print 3
        else                 print 4
    }'
}

# debug 日志：两个 hook 都写，便于排查"消息到底有没有被 AI 看到"
cc_debug_log() {
    local event="$1"
    local payload="$2"   # 可选 JSON 字符串
    local log="$HOME/.claude/cc-handoff/debug.log"
    # 只保留最近 500 行
    if [ -f "$log" ] && [ "$(wc -l <"$log")" -gt 500 ]; then
        tail -400 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
    fi
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "$ts [$event] $payload" >> "$log" 2>/dev/null || true
}
