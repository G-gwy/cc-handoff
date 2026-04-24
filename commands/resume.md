---
description: 列出当前项目所有 worktree 的未完成 handoff，选择要继承哪个（cc-handoff）
allowed-tools: Read, Bash, Glob
---

# /resume —— 列出未完成 handoff

## 1. 列出所有 handoff

```bash
source ~/.claude/cc-handoff/lib/pwd-slug.sh
STORAGE="$(cc_storage_dir)"
CURRENT_HASH="$(cc_worktree_hash)"

if [ ! -d "$STORAGE/active" ] || [ -z "$(ls -A "$STORAGE/active" 2>/dev/null)" ]; then
    echo "（本项目暂无任何 handoff）"
    exit 0
fi

ls -t "$STORAGE/active/"*.md 2>/dev/null | while read -r f; do
    hash=$(basename "$f" .md)
    marker=""
    [ "$hash" = "$CURRENT_HASH" ] && marker=" ← 当前 worktree"
    echo "=== $hash$marker ==="
    head -15 "$f"
    echo
done
```

## 2. 给用户展示清单

表格或列表形式：
- worktree 标识（含 basename）
- 最后更新时间
- status（paused / truncated / completed）
- next_action 摘要

## 3. 用户选择后

- 若选**当前 worktree** 的 handoff：cat 全文展示，按「👉 下一步」继续
- 若选**其他 worktree**：提醒用户实际任务在别的目录，建议先 `cd` 过去再重开会话

## 4. 若当前 worktree 无 handoff

输出：
```
本 worktree 暂无 handoff。
同项目其他 worktree 的 handoff 列表如上。
若想重新开始，直接告诉我任务即可。
```

## 边界

- **只读**：此命令不修改任何 handoff 文件
- 想删除 handoff：让用户手动 `rm ~/.claude/projects/<slug>/handoffs/active/<hash>.md`
- 想关闭自动注入：改项目 `.claude/handoff.json` 的 `enabled: false`
