# cc-handoff

[![CI](https://github.com/G-gwy/cc-handoff/actions/workflows/ci.yml/badge.svg)](https://github.com/G-gwy/cc-handoff/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

**Claude Code 的会话交接系统**：长会话前自动提醒、主动打包进度、新会话无缝续作。

## 为什么需要它

Claude Code 一次对话的 context 上限是有限的。你会遇到：

- 聊到后半段 AI 开始"失忆"，要反复复制粘贴之前的内容
- `/clear` 重开后，新会话完全不知道你做了啥，得从头交代
- 多个任务并行（feat A 做一半、bug B 插队），切换时丢失上下文

cc-handoff 解决这三件事：

1. **自动预警**：在上下文用量到阈值时，通过 UserPromptSubmit hook 注入提醒
2. **结构化打包**：`/handoff` 按固定模板写入交接文档（目标 / 已完成 / 下一步 / 决策 / 陷阱）
3. **无缝续作**：新会话首轮自动注入 handoff 指针，AI 读完直接接着干

## 核心特性

- 🔔 **五档上下文预警**（0 静默 / 1 温和 / 2 明确 / 3 危险 / 4 紧急）
- 📦 **多任务并行**：`<worktree-hash>__<task-id>.md` 命名，同 worktree 多 handoff 共存不串扰
- 🔄 **承前复用**：`/resume` 承接某 handoff 后，本会话 `/handoff` 自动复用同一 id（避免分叉）
- 🌐 **跨平台**：macOS bash 3.2 / Linux bash 4+/5+ / Windows Git Bash / WSL 全支持（见 [COMPATIBILITY.md](./COMPATIBILITY.md)）
- 🧹 **零侵入**：只注册 3 个 hook + 2 个 skill，卸载后无残留

## 安装

前置依赖：`jq` + `awk` + sha1 工具（`sha1sum`/`shasum`/`openssl` 任一）

```bash
# 任意位置 clone
git clone git@github.com:G-gwy/cc-handoff.git ~/code/cc-handoff
cd ~/code/cc-handoff
./install.sh
```

`install.sh` 会：
1. symlink `~/.claude/cc-handoff` → 你的 clone 位置（用户态入口稳定）
2. 注册三个 hook（UserPromptSubmit / PostToolUse / Stop）到 `~/.claude/settings.json`
3. symlink 两个 skill（`/handoff` / `/resume`）到 `~/.claude/skills/`
4. 生成默认配置 `config.json`（已存在则跳过）

> 也可以直接 clone 到 `~/.claude/cc-handoff`，此时 `install.sh` 会跳过 symlink 步骤。

**需要重启 Claude Code 会话**后 hook 才生效。

## 核心命令

### `/handoff` — 打包会话

在上下文接近上限或任务切换前执行。AI 会按模板写入 `~/.claude/projects/<slug>/handoffs/active/<hash>__<id>.md`：

```markdown
---
id: feat-payment-refactor
status: paused
updated: 2026-04-24T16:59:27+0800
---

## 🎯 目标
一句话本次会话在干啥

## ✅ 已完成 / 🔄 进行中 / 👉 下一步
## 📎 关键引用 / 🚫 已排除路径 / ❓ 开放决策
```

### `/resume` — 承接 / 删除 / 静默

列当前 worktree 所有未完成 handoff：

```
本 worktree (sales-isv) 有 2 个未完成交接：
  [1] feat-payment-refactor    paused    2026-04-24 16:59
      🎯 重构支付模块分离出库存锁逻辑
  [2] bug-login-npe            paused    2026-04-24 14:20
      🎯 修复登录 NPE

操作：
  N    → 承接第 N 个（后续 /handoff 会复用此 id）
  dN   → 删除第 N 个
  q    → 本会话静默（不再提示）
```

## 工作流全貌

```
┌─────────────────────────────────────────┐
│ 用户发话（UserPromptSubmit）             │
└────────────────┬────────────────────────┘
                 │
       ┌─────────▼──────────┐
       │ hook 检查：         │
       │  • 本会话是否静默？  │
       │  • 是否首次注入？    │
       │  • 当前 context %   │
       └─────────┬──────────┘
                 │
        ┌────────┴─────────┐
        │                  │
     未注入             已注入
        │                  │
        ▼                  ▼
┌──────────────┐    ┌──────────────┐
│ 0 handoff →  │    │ 按 tier 档位  │
│   静默       │    │ 注入用量预警  │
│ 1 handoff →  │    └──────────────┘
│   结构化摘要 │
│ 2+ handoff → │
│  提示 /resume│
└──────────────┘
```

## 配置

全局 `~/.claude/cc-handoff/config.json`：

```json
{
  "enabled": true,
  "threshold": 0.35,
  "model_limits": {
    "default": 200000,
    "claude-opus-4-7": 200000,
    "claude-sonnet-4-6": 200000
  }
}
```

项目级覆盖：在项目根放 `.claude/handoff.json`（同结构，深合并）。

档位阈值（默认 `threshold=0.35`）：
| tier | pct 区间 | 表现 |
|------|----------|------|
| 0 | <35% | 静默 |
| 1 | [35%, 50%) | 📊 温和提示，可以开始考虑 |
| 2 | [50%, 70%) | ⚠️ 建议尽早 |
| 3 | [70%, 90%) | 🚨 强烈建议立即 |
| 4 | ≥90% | ⛔ 即将耗尽！立即 |

## 卸载

```bash
~/.claude/cc-handoff/uninstall.sh
```

会从 `settings.json` 移除 hook + 清理 skill symlink。**数据（handoff 文件）保留**在 `~/.claude/projects/*/handoffs/`，手动删即可。

## 跨平台兼容

详见 [COMPATIBILITY.md](./COMPATIBILITY.md)。

- ✅ macOS (bash 3.2.57 系统自带 / bash 5 homebrew)
- ✅ Linux (bash 4/5)
- ✅ Windows (Git Bash / WSL2)

GitHub Actions 矩阵持续验证三平台。

## 设计原则

- **KISS**：文件系统即数据库（目录 = 索引），不做 SQLite/全局状态
- **零 ceremony**：不让 AI 写"探索过程"，只写"结论 + 指针"
- **防分叉**：id 绑定业务不绑定会话，承前必须复用
- **跨会话可恢复**：handoff 文档是 fresh 会话唯一 recovery path

## 贡献

欢迎 issue / PR。修改前请：

1. 读 [COMPATIBILITY.md](./COMPATIBILITY.md) 的贡献者禁用清单
2. 本地跑 `tests/smoke.sh` 通过
3. PR 触发 CI 三平台矩阵通过

## License

[MIT](./LICENSE)
