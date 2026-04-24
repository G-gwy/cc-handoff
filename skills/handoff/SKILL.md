---
name: handoff
description: 产出会话交接文档（cc-handoff）。用户主动调用或 AI 自主判断上下文接近阈值时调用，把当前工作状态打包到 ~/.claude/projects/<slug>/handoffs/active/ 供下一个会话恢复。
---

# /handoff —— 产出交接文档

## 何时调用

1. **用户主动**：直接说「/handoff」或「打包一下」「收尾交接」
2. **AI 自主**：收到 `⚠️ cc-handoff：上下文已达 XX%` 提醒后，本轮工作收尾时调用
3. **阶段切换**：一个子任务完成，准备换上下文前

## 确定业务 id（关键，必须遵守）

id 绑定**业务/任务**，不绑定会话。同 id 覆盖（推进），不同 id 共存（分叉）。

### 第一步：扫当前 worktree 的既有 handoff

```bash
source ~/.claude/cc-handoff/lib/pwd-slug.sh
source ~/.claude/cc-handoff/lib/handoff-io.sh
# 跨平台：while read 替代 mapfile（bash 4+ only），macOS bash 3.2 / zsh 也能跑
cc_list_active_for_hash | while IFS= read -r f; do
    [ -n "$f" ] || continue
    id=$(sed -n 's/^id: *//p' "$f" | head -1)
    goal=$(awk '/^## 🎯/{flag=1;next} flag && NF>0 && !/^#/{print; exit}' "$f" | cut -c1-60)
    echo "  • $id  —  $goal"
done
```

### 第二步：判定复用还是新建

**优先级顺序：**

1. **承前复用（最高优先级）**：
   - 本会话若是通过 `/resume` 承接而来 → **强制复用**那个 id
   - 本会话若是通过新会话自动注入 Read 过某 handoff → **强制复用**那个 id
   - hook 注入文本里的 `id=xxx` 就是信号

2. **相同业务新阶段**：与某既有 id 业务相关（只是阶段不同），可加后缀：`story-impl` / `story-qa` / `story-hotfix`

3. **首次新建**：与所有既有 id 都无关 → 派生新 kebab-case：
   - `feat-payment-refactor` / `bug-login-npe` / `cc-handoff-phase1`
   - 若项目 CLAUDE.md 定义了任务跟踪约定，按项目约定生成

### 约束

- id 只含字母数字、`-`、`_`、`.`，长度 ≤ 40
- **拿不准就用承前复用**：重复推进是正常的，分叉是问题
- 用户若已通过 `/resume` 选定某 handoff，你回复里必须明示"承接 id=xxx"——这是本会话的契约

## 产出位置

用**业务 id** 派生路径（而非 worktree hash 单一文件）：

```bash
source ~/.claude/cc-handoff/lib/pwd-slug.sh
source ~/.claude/cc-handoff/lib/handoff-io.sh
HANDOFF_PATH="$(cc_handoff_path_for_id "<上面确定的 id>")"
mkdir -p "$(dirname "$HANDOFF_PATH")"
echo "$HANDOFF_PATH"
```

**覆盖规则**：若 `$HANDOFF_PATH` 已存在，直接覆盖（同 id 代表同业务进度推进）。**不要**问用户"是否覆盖"，那是会话视角的误区。

## 产出模板（严格按此结构）

用 Write 工具写入上面计算出的路径，内容为：

```markdown
---
id: <业务 id，必须与文件名 <hash>__<id>.md 中的 <id> 完全一致>
worktree: <当前 pwd>
branch: <git 当前分支>
task_id: <外部任务跟踪系统的 ID，若有（issue/ticket/card 等）>
status: <completed | paused | truncated>
context_pct: <如果是因为上下文触发，填当前百分比；否则 0>
updated: <ISO 8601 时间戳>
session_id: <当前 session 的前 8 位（仅供溯源，不决定文件名）>
---

## 🎯 目标
一句话描述本次会话在做什么（最多 30 字）。

## ✅ 已完成
- [x] 具体动作 1（可附 commit hash 或文件路径）
- [x] 具体动作 2

## 🔄 进行中
- [ ] 正在做的事 + 完成度 + 卡点（如「60% 完成，卡在 xxx」）

## 👉 下一步（新会话第一件事）
1. 具体动作 1（带文件:行号）
2. 具体动作 2

## 📎 关键引用
- `path/to/file.java:N` — 为什么重要
- `path/to/other.md:section` — 为什么重要

## 🚫 已排除路径
- 试过 X，不行，因为 Y（别再试）

## ❓ 开放决策
- 待确认项 1
- 待确认项 2（若有 TAPD 评论/PM 反馈引用，写出来）
```

## 填写原则

- **指针化**：引用现有文件 + 行号，**不要复制代码内容**
- **去过程化**：不要记录探索过程，只记结论
- **可验证**：每个「已完成」都要能被新会话 grep/git log 验证
- **next action 单义**：下一步必须具体到「打开什么文件，跑什么命令」

## 写完后输出给用户

告知用户：
1. handoff 文件已写入路径 `<path>`
2. 本次会话可 `/clear` 后重开（同一 worktree 目录）
3. 新会话首次输入时会自动注入本 handoff
4. 若任务已完全交付，把 `status: paused` 改为 `status: completed`
