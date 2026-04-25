# cc-handoff (AI 协作指南)

> **任务级状态**（在做什么 / 进度 / 下一步）写 handoff；**项目级知识**（架构 / 禁用清单 / 调试入口）写本文件。

## 项目定位

Claude Code 会话交接系统：上下文预警 + 结构化打包 + 新会话续作。详见 [README.md](./README.md)。

## 关键架构决策

| 决策 | 为什么 |
|------|--------|
| 安装位 `~/.claude/cc-handoff/` 强制 symlink → 开发位 | hook/SKILL.md 文档里路径硬编码到这；symlink 透明，开发位仍可灵活 |
| id 绑**业务**不绑会话；同 id 覆盖，不同 id 共存 | 防分叉。一个业务一个 id，多会话推进同一进度 |
| 跨平台基线 = **macOS bash 3.2.57** + BSD coreutils | macOS 系统 bash 是最苛刻下限（Apple 因 GPL v3 不升级），能跑则全平台跑 |
| 文件系统即索引（目录 = 列表，文件名 = `<hash>__<id>.md`） | KISS，不引 SQLite / 状态服务 |
| **UserPromptSubmit** 是唯一可靠注入点 | PostToolUse 的 systemMessage 客户端展示不稳；Stop 不支持注入 |
| systemMessage 只放**指针**（<300B），让 AI 主动 Read 文件 | 实测 ~4.5KB systemMessage 会被客户端静默吞 |

## 已排除路径（禁用 + 原因）

完整"贡献者禁用清单"在 [COMPATIBILITY.md](./COMPATIBILITY.md)。要点速查：

- ❌ `mapfile` / `readarray` → bash 4+ only（macOS bash 3.2 没有）
- ❌ `stat -f` / `stat -c` → BSD/GNU 分歧，用 `ls -t` 替代
- ❌ `find -delete` → MSYS find 不一定支持，用 `-exec rm -f`
- ❌ 硬依赖 `shasum` → Linux 通常无，需探测 `sha1sum` / `shasum` / `openssl`
- ❌ PostToolUse 注入 systemMessage → 客户端不稳，统一走 UserPromptSubmit
- ❌ id 从 TAPD/Jira 等特定平台派生 → 工具必须跨平台中立
- ❌ handoff 文件名仅用 worktree hash → 多任务互覆盖（必须 `<hash>__<id>.md`）
- ❌ SKILL.md `name` 与 slash command 文件名同名 → `/xxx` 列表重复
- ❌ `trap 'exit 0' ERR` → bash 复合语句失败误触发，改 lib 函数显式 `return 0`

## 调试入口

| 现象 | 第一步看哪 |
|------|------------|
| hook 没触发 / 注入丢失 | `~/.claude/cc-handoff/debug.log`（最近 500 行） |
| install 跑完不生效 | `~/.claude/settings.json` 的 `hooks.UserPromptSubmit` ；`~/.claude/cc-handoff` 是否 symlink |
| lib 函数行为异常 | `bash tests/smoke.sh`（9 断言冒烟） |
| 兼容性 warning | `shellcheck --severity=warning lib/*.sh hooks/*.sh install.sh uninstall.sh tests/smoke.sh` |
| handoff 文件丢失 | `~/.claude/projects/<slug>/handoffs/active/`（slug = pwd 把 `/` 替 `-`） |

## 改代码前的清单

1. 改动是否触碰禁用清单？查 COMPATIBILITY.md
2. 影响 lib / hooks / install？跑 `tests/smoke.sh` 通过
3. 新增 lib 函数？扩 `tests/smoke.sh` 断言覆盖
4. 改 SKILL.md 示例？必须在 macOS bash 3.2.57 能跑通（不能用 mapfile / declare -A 等）
5. PR 前本地 `shellcheck --severity=warning ...` 零 warning

## 别在哪写

- ❌ 不要把"项目背景 / 架构决策 / 禁用清单"写进单个 handoff（应在本文件）
- ❌ 不要把"这次任务的具体进度 / 下一步动作"写进本文件（应在 handoff）
- ❌ 不要在 commit message 里加 "Co-Authored-By: Claude" 等 AI 痕迹（公开 repo 保持中性）
