# Compatibility

cc-handoff 的目标是 **Claude Code 跑在哪，它就能跑在哪**。

## 支持矩阵

| 平台 | Shell | 备注 |
|------|-------|------|
| macOS | `/bin/bash` 3.2.57（Apple 内置） | **最苛刻下限**，CI 必测 |
| macOS | `/opt/homebrew/bin/bash` 5.x | 可选，推荐 |
| macOS | `/bin/zsh` | Claude Code 默认调用 Bash 工具时可能走 zsh |
| Linux | bash 4/5（Ubuntu、Debian、Arch 等） | 主流 |
| Windows | Git Bash（MSYS2 bash 4+） | Claude Code 官方推荐 |
| Windows | WSL2（标准 Linux bash） | 等价 Linux |

> PowerShell / cmd.exe 不受支持。使用 Claude Code on Windows 的前提就是 Git Bash 或 WSL。

## 运行时依赖

| 命令 | 用途 | 说明 |
|------|------|------|
| `jq` | 解析/改写 settings.json、transcript、配置 | 硬依赖，需用户自行安装（`brew/apt/choco install jq`） |
| `awk` | 百分比/字段处理 | 系统自带 |
| sha1 工具 | `cc_worktree_hash` | `sha1sum` / `shasum` / `openssl` 三选一，`install.sh` 会探测 |
| `find` | 清理过期状态文件 | BSD/GNU/MSYS find 都行（不依赖 `-delete` / `-printf`） |
| `sed` / `cut` / `tr` / `tail` / `head` / `wc` | 文本处理 | POSIX 通用 |

## 贡献者禁用清单（Do NOT use）

以下写法会在 macOS bash 3.2 或 BSD coreutils 下失败：

| ❌ 禁用 | ✅ 改用 | 原因 |
|---------|---------|------|
| `mapfile -t FILES < <(...)` | `while IFS= read -r line; do FILES+=("$line"); done < <(...)` | `mapfile` 是 Bash 4+ 内置，macOS 原生 bash 3.2 / zsh 均无 |
| `readarray` | 同上 | Bash 4+ |
| `stat -f "%m %N"` / `stat -c "%Y %n"` | `ls -t` + glob | 前者 BSD-only，后者 GNU-only |
| `find ... -delete` | `find ... -exec rm -f {} \;` | MSYS find 的某些发行不支持 `-delete` |
| `find ... -printf` | `find ... -exec echo {} \;` 或 `find -print` | GNU-only |
| `sed -i 's/.../.../g' file` | 临时文件 + `mv`，或 `perl -i -pe '...'` | BSD 要 `-i ''`，GNU 不能有空字串参数 |
| `readlink -f path` | `cd` + `pwd -P`，或自写 canonicalize | BSD 无 `-f` |
| `declare -A` 关联数组 | 双数组或 `eval` | Bash 4+ |
| `${var,,}` / `${var^^}` | `tr '[:upper:]' '[:lower:]'` | Bash 4+ |
| `echo -n "$x" \| tool` | `printf '%s' "$x" \| tool` | `echo -n` 在某些 `sh` 里不被识别为 flag |
| `shasum` 硬依赖 | 探测 `sha1sum` → `shasum` → `openssl` | Linux 通常没 `shasum`，只有 `sha1sum` |
| `#!/bin/bash` | `#!/usr/bin/env bash` | macOS 某些用户装 brew bash 后 `/bin/bash` 仍是 3.2 |
| 变量名 `status` / `path` / `prompt` / `argv` / `pipestatus` / `signals` | 加前缀如 `ho_status` | zsh 把这些当**只读特殊变量**，赋值会报 `read-only variable`。Claude Code 的 Bash 工具在 macOS 默认走 zsh 时会触发 |

## shell-isms 提醒

- `local` 是 bash 特性（POSIX sh 无），但本项目 shebang 都是 `bash`，OK。
- `${var//from/to}` 是 bash 3.2+ 支持的 parameter expansion，OK。
- `[[ ... ]]` 是 bash/zsh 扩展，OK；若考虑 POSIX sh 需改 `[ ... ]`。
- 数组 `arr=()` / `arr+=(x)` / `"${arr[@]}"` 在 bash 3.2+ / zsh 都能用，OK。**但 zsh 默认数组下标从 1 开始**（不影响我们当前代码，仅注意）。

## 测试保障

- 所有改动通过 `tests/smoke.sh` 冒烟。
- GitHub Actions 矩阵覆盖 **ubuntu-latest / macos-latest (bash 3.2 + homebrew 5) / windows-latest (Git Bash)**。
- `shellcheck` 扫 lib/hooks/install 全部 `.sh`，warning 级零容忍。

## 诊断跨平台问题

1. 先看 `~/.claude/cc-handoff/debug.log`
2. 手动 `bash --version`，若 `< 4.0` 就启用 bash 3.2 兼容路径
3. 提交 issue 时附 `uname -a` / `bash --version` / 相关 `debug.log` 片段
