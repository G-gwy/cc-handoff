#!/usr/bin/env bash
# install.sh —— 把 cc-handoff 注册到 ~/.claude/settings.json
# 幂等：重跑不会重复注册
# 支持任意源位置：clone 到 ~/code/cc-handoff 或 ~/.claude/cc-handoff 都可
# 会把源目录 symlink 到 ~/.claude/cc-handoff 作为稳定入口
set -euo pipefail

# 源目录 = 本脚本所在目录（无论用户把 repo clone 到哪，都能正确定位）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 用户态固定入口（hooks / skills 的所有文档、路径都假设在这里）
INSTALL_TARGET="$HOME/.claude/cc-handoff"

SETTINGS="$HOME/.claude/settings.json"
MARKER="cc-handoff"  # 幂等识别标记（command 路径含此字符串）

# --- 建立 INSTALL_TARGET symlink，指向实际源目录 ---
# 三种情况：
#   1) SCRIPT_DIR == INSTALL_TARGET：用户就在 ~/.claude/cc-handoff/ 安装，不处理
#   2) INSTALL_TARGET 已是 symlink：
#      - 指向正确：跳过
#      - 指向错误：更新
#   3) INSTALL_TARGET 是真实目录/文件：备份后 symlink
ensure_symlink() {
    if [ "$SCRIPT_DIR" = "$INSTALL_TARGET" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$INSTALL_TARGET")"
    if [ -L "$INSTALL_TARGET" ]; then
        local current
        current="$(readlink "$INSTALL_TARGET")"
        if [ "$current" = "$SCRIPT_DIR" ]; then
            echo "🔗 symlink 已正确: $INSTALL_TARGET -> $SCRIPT_DIR"
            return 0
        fi
        rm "$INSTALL_TARGET"
        ln -s "$SCRIPT_DIR" "$INSTALL_TARGET"
        echo "🔗 symlink 已更新: $INSTALL_TARGET -> $SCRIPT_DIR"
    elif [ -e "$INSTALL_TARGET" ]; then
        local bak
        bak="$INSTALL_TARGET.bak-$(date +%Y%m%d-%H%M%S)"
        mv "$INSTALL_TARGET" "$bak"
        ln -s "$SCRIPT_DIR" "$INSTALL_TARGET"
        echo "📦 已备份旧安装: $bak"
        echo "🔗 symlink 已创建: $INSTALL_TARGET -> $SCRIPT_DIR"
    else
        ln -s "$SCRIPT_DIR" "$INSTALL_TARGET"
        echo "🔗 symlink 已创建: $INSTALL_TARGET -> $SCRIPT_DIR"
    fi
}
ensure_symlink

# 后续所有逻辑都通过 INSTALL_TARGET 访问，保证用户态路径稳定
CC_HANDOFF_DIR="$INSTALL_TARGET"

# --- 依赖检查 ---
for cmd in jq awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ 缺少依赖: $cmd" >&2
        exit 1
    fi
done
# sha1 工具：sha1sum（Linux/Git Bash）/ shasum（macOS）/ openssl（通用回退），三选一即可
if ! command -v sha1sum >/dev/null 2>&1 \
   && ! command -v shasum >/dev/null 2>&1 \
   && ! command -v openssl >/dev/null 2>&1; then
    echo "❌ 缺少 sha1 工具（sha1sum/shasum/openssl 三选一）" >&2
    exit 1
fi

# --- 结构自检 ---
[ -d "$CC_HANDOFF_DIR/hooks" ] || { echo "❌ hooks 目录不存在: $CC_HANDOFF_DIR/hooks" >&2; exit 1; }
for f in user-prompt-submit.sh post-tool-use.sh stop.sh; do
    [ -x "$CC_HANDOFF_DIR/hooks/$f" ] || { echo "❌ hook 不存在或无执行权: $f" >&2; exit 1; }
done

# --- 备份 settings.json ---
if [ -f "$SETTINGS" ]; then
    backup="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS" "$backup"
    echo "📁 已备份: $backup"
else
    echo '{}' > "$SETTINGS"
fi

# --- 幂等追加 hooks ---
# 对每个事件：先过滤掉已注册的 cc-handoff 条目，再追加新的
jq --arg h "$CC_HANDOFF_DIR/hooks" --arg m "$MARKER" '
  def strip_cc(evt):
    (.hooks[evt] // [])
    | map(select((.hooks // []) | map(.command // "") | all(. | contains($m) | not)));

  .hooks.UserPromptSubmit = (strip_cc("UserPromptSubmit") + [{
    hooks: [{type:"command", command:($h+"/user-prompt-submit.sh"), timeout:5}]
  }]) |
  .hooks.PostToolUse = (strip_cc("PostToolUse") + [{
    hooks: [{type:"command", command:($h+"/post-tool-use.sh"), timeout:5}]
  }]) |
  .hooks.Stop = (strip_cc("Stop") + [{
    hooks: [{type:"command", command:($h+"/stop.sh"), timeout:5}]
  }])
' "$SETTINGS" > "$SETTINGS.tmp"

# 校验 JSON 有效性
if ! jq empty "$SETTINGS.tmp" 2>/dev/null; then
    echo "❌ 生成的 settings.json 无效，已保留原文件" >&2
    rm -f "$SETTINGS.tmp"
    exit 1
fi

mv "$SETTINGS.tmp" "$SETTINGS"
echo "✅ hooks 注册完成"

# --- symlink skills 到 ~/.claude/skills/ ---
# Claude Code 把 skill 作为 /xxx 入口：用户敲 /handoff /resume 即触发对应 skill
# 同时 AI 也可识别自然语言关键词自主调用（tier 档位高时）
# 目录用 cc-handoff-* 命名空间避免与其他插件冲突；SKILL.md 的 name 字段决定 /xxx 入口名
# 注：旧 /fresh 已合并进 /resume 的 q 选项，不再独立注册
mkdir -p "$HOME/.claude/skills"
# 清理可能残留的 fresh symlink（从旧版本升级）
rm -f "$HOME/.claude/skills/cc-handoff-fresh"
for skill in handoff resume; do
    target="$HOME/.claude/skills/cc-handoff-$skill"
    if [ -L "$target" ] || [ -e "$target" ]; then
        rm -f "$target"
    fi
    ln -s "$CC_HANDOFF_DIR/skills/$skill" "$target"
done
echo "✅ skills 注册完成：/handoff /resume（用户主动 + AI 自主）"

# --- 复制默认配置（不覆盖已有）---
if [ ! -f "$CC_HANDOFF_DIR/config.json" ] && [ ! -f "$CC_HANDOFF_DIR/config.yaml" ]; then
    cp "$CC_HANDOFF_DIR/config.default.json" "$CC_HANDOFF_DIR/config.json"
    echo "✅ 默认配置已创建: $CC_HANDOFF_DIR/config.json"
fi

echo
echo "🎉 cc-handoff 安装完成"
echo "   · 下次启动 Claude Code 会话时生效（当前会话不受影响）"
echo "   · 查看状态：ls ~/.claude/projects/<slug>/handoffs/"
echo "   · 卸载：$CC_HANDOFF_DIR/uninstall.sh"
