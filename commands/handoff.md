---
description: 产出会话交接文档（cc-handoff），把当前工作状态打包到用户级存储，供下个会话恢复
allowed-tools: Read, Write, Bash, Grep, Glob, TodoWrite
---

# /handoff —— 产出会话交接文档

按以下步骤执行：

## 1. 计算 handoff 文件路径

```bash
source ~/.claude/cc-handoff/lib/pwd-slug.sh
source ~/.claude/cc-handoff/lib/handoff-io.sh
HANDOFF_PATH="$(cc_handoff_path)"
mkdir -p "$(dirname "$HANDOFF_PATH")"
echo "$HANDOFF_PATH"
```

## 2. 收集当前工作状态

用以下信息填写 handoff，**指针化**，不要复制代码内容：

- 当前 git 分支、未 push commit 数（`git rev-parse --abbrev-ref HEAD` / `git log @{u}..HEAD --oneline | wc -l`）
- 最近一次 /handoff 以来做了什么（读 `.claude/plan/tasks.md` 或 journal，如有）
- 本会话正在处理的任务 + 完成度
- 下一步具体动作（文件:行号）
- 已排除的错误路径（别再试什么）
- 待用户决策的开放项

## 3. 按模板写入 handoff 文件

用 Write 工具写入第 1 步拿到的路径，内容为：

```markdown
---
id: <任务标识，如 STORY-888-impl 或自由描述>
worktree: <pwd>
branch: <git 分支>
task_id: <TAPD/Jira id，可选>
status: paused
context_pct: <当前百分比，从 ~/.claude/cc-handoff/debug.log 最新一行读，可选>
updated: <ISO 8601 时间戳>
session_id: <当前 session 前 8 位>
---

## 🎯 目标
一句话（≤30 字）。

## ✅ 已完成
- [x] 动作 1（带 commit hash 或文件路径）
- [x] 动作 2

## 🔄 进行中
- [ ] 正在做的事 + 完成度 + 卡点

## 👉 下一步（新会话第一件事）
1. 具体动作 1（带文件:行号）
2. 具体动作 2

## 📎 关键引用
- `path/to/file:N` — 原因
- `path/to/other:section` — 原因

## 🚫 已排除路径
- 试过 X，不行，因为 Y

## ❓ 开放决策
- 待确认项（若有 PM/同事反馈引用，附出处）
```

## 4. 写完后输出给用户

- 确认 handoff 文件路径
- 提示可以 `/clear` 然后在相同目录重开会话
- 新会话首次发话时会自动注入本 handoff

## 填写原则（重要）

- **指针化**：引用路径 + 行号，不复制代码内容
- **去过程化**：不记探索过程，只记结论
- **可验证**：「已完成」项要能被 grep 或 git log 验证
- **next action 单义**：具体到「打开什么文件，跑什么命令」

## 特殊情况

- 若任务已完全交付：把 `status: paused` 改为 `status: completed`
- 若因上下文熔断触发：`status: truncated`，context_pct 填当前百分比
