---
description: 本次会话忽略自动注入的 handoff（cc-handoff）。仅影响当前会话，不删除文件
allowed-tools: Bash
---

# /fresh —— 忽略本次会话的 handoff 注入

## 语义

- **仅本次会话**：标记当前 session_id 跳过注入
- **不删除 handoff 文件**：下一个新会话（同 worktree）仍会收到注入
- 想永久关闭：改项目 `.claude/handoff.json` 的 `enabled: false`

## 执行

```bash
source ~/.claude/cc-handoff/lib/pwd-slug.sh
source ~/.claude/cc-handoff/lib/handoff-io.sh

# 推断当前 session_id：读 ~/.claude/projects/<slug>/ 下最新的 *.jsonl
STORAGE="$(cc_storage_dir)"
SLUG_DIR="$(dirname "$STORAGE")"
SESSION_ID="$(ls -t "$SLUG_DIR"/*.jsonl 2>/dev/null | head -1 | xargs -I{} basename {} .jsonl)"

if [ -z "$SESSION_ID" ]; then
    echo "❌ 无法识别当前 session_id"
    exit 1
fi

fresh_file="$(cc_state_file "$(pwd)" "$SESSION_ID" "fresh")"
touch "$fresh_file"
echo "✅ 本次会话已标记 /fresh (session: $SESSION_ID)"
echo "   后续用户输入将不再触发 handoff 注入（档位预警仍会继续）"
```

## 告知用户

- 已跳过本次会话的**首次 handoff 注入**
- **档位预警仍正常工作**（/fresh 不影响 token 监控）
- 想连档位预警也关闭：改 `.claude/handoff.json` `enabled: false`
