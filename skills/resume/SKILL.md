---
name: resume
description: 列出当前 worktree 所有未完成 handoff，支持承接/删除/静默（cc-handoff）。当用户说「/resume」「看下有哪些交接」「我有哪些未完成」「别管之前的」「这次不相关」时调用。
---

# /resume —— 列表 + 承接 + 删除 + 静默

## 核心逻辑

扫当前 worktree 所有未完成 handoff，列给用户，响应「数字=承接 / dN=删除 / q=本会话静默」。

本 skill **同时承担了旧 `/fresh` 的职责**（用 `q` 实现）。

## 执行步骤

### 1. 列出当前 worktree 的所有 handoff

```bash
source ~/.claude/cc-handoff/lib/pwd-slug.sh
source ~/.claude/cc-handoff/lib/handoff-io.sh

# 跨平台：不用 mapfile（bash 4+ only），用 while read 构建数组；macOS bash 3.2 / zsh 也能跑
FILES=()
while IFS= read -r line; do
    [ -n "$line" ] && FILES+=("$line")
done < <(cc_list_active_for_hash)

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "（本 worktree 暂无未完成交接）"
    exit 0
fi
```

**备选（避免数组的纯 POSIX 实现）**：若环境不支持数组，也可全程用行号 + `sed -n "${N}p"` 取第 N 个，不必先 load 进数组。

### 2. 读每个文件 frontmatter 展示摘要

对 `FILES` 数组里每个文件，用 `Read` 或 `sed/awk` 提取：

- `id`（业务标识）
- `status`（paused / truncated / completed）
- `updated`（时间戳，取前 16 字符 + T→空格）
- `## 🎯 目标` 首行（截 60 字）

提取命令范式：

```bash
i=0
for f in "${FILES[@]}"; do
    i=$((i+1))
    id=$(sed -n 's/^id: *//p' "$f" | head -1)
    status=$(sed -n 's/^status: *//p' "$f" | head -1)
    updated=$(sed -n 's/^updated: *//p' "$f" | head -1 | cut -c1-16 | tr 'T' ' ')
    goal=$(awk '/^## 🎯/{flag=1;next} flag && NF>0 && !/^#/{print; exit}' "$f" | cut -c1-60)
    echo "[$i] $id | $status | $updated | $goal"
done
```

按如下格式展示：

```
本 worktree (<basename>) 有 N 个未完成交接：

  [1] <id>    <status>    <updated>
      🎯 <goal>
  [2] <id>    <status>    <updated>
      🎯 <goal>
  ...

操作：
  输入数字 N   → 承接第 N 个（Read 全文 + 按「👉 下一步」续作）
  输入 dN      → 删除第 N 个（如 d2）
  输入 q       → 本会话静默（后续不再注入 handoff 提示，文件不动）
```

### 3. 响应用户输入

- **数字 N**：
  - `Read` 对应 `FILES[N-1]` 的**全文**
  - **必须记住该 handoff 的 `id`**，本会话后续若 `/handoff`，必须复用此 id（避免 handoff 分叉）
  - 按文档「👉 下一步」开始干活
  - 告知用户"正在承接 handoff `<id>`，后续 /handoff 将复用此 id"

- **dN（删除）**：
  - 执行 `rm "${FILES[N-1]}"`
  - 告知"已删除 `<id>`"
  - **重新列表**（从步骤 1 再来一次）直到用户选数字 / q / 列表为空

- **q（静默本会话）**：
  - 吸收旧 `/fresh` 功能：
    ```bash
    # 推断 session_id（从 ~/.claude/projects/<slug>/*.jsonl 取最新）
    STORAGE="$(cc_storage_dir)"
    SLUG_DIR="$(dirname "$STORAGE")"
    SESSION_ID="$(ls -t "$SLUG_DIR"/*.jsonl 2>/dev/null | head -1 | xargs -I{} basename {} .jsonl)"
    fresh_file="$(cc_state_file "$(pwd)" "$SESSION_ID" "fresh")"
    touch "$fresh_file"
    ```
  - 告知"本会话已静默，后续用户输入不再触发 handoff 注入；handoff 文件未动"

## 设计原则

- **只操作当前 worktree**：不跨 worktree 列表（git worktree 已独立隔离）
- **删除 = 物理 rm**：不归档（KISS，handoff 是轻量交接）
- **不修改 handoff 内容**：只读 + 删 + 静默标记
- **承接时强调 id 复用**：这是防止 handoff 分叉的关键约束，AI 必须在回复里明示"将复用 id=xxx"
