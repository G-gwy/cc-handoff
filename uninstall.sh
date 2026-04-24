#!/usr/bin/env bash
# uninstall.sh —— 从 ~/.claude/settings.json 移除 cc-handoff hooks
# 数据（handoff 文件）保留不删
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
MARKER="cc-handoff"

if [ ! -f "$SETTINGS" ]; then
    echo "无 settings.json，无需操作"
    exit 0
fi

# 备份
backup="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)-uninstall"
cp "$SETTINGS" "$backup"
echo "📁 已备份: $backup"

# 删除所有 command 含 cc-handoff 的 hook 条目
jq --arg m "$MARKER" '
  def strip_cc(evt):
    (.hooks[evt] // [])
    | map(select((.hooks // []) | map(.command // "") | all(. | contains($m) | not)))
    | if length == 0 then null else . end;

  .hooks.UserPromptSubmit = (strip_cc("UserPromptSubmit") // []) |
  .hooks.PostToolUse = (strip_cc("PostToolUse") // []) |
  .hooks.Stop = (strip_cc("Stop") // [])
' "$SETTINGS" > "$SETTINGS.tmp"

if ! jq empty "$SETTINGS.tmp" 2>/dev/null; then
    echo "❌ 生成的 settings.json 无效，已保留原文件" >&2
    rm -f "$SETTINGS.tmp"
    exit 1
fi

mv "$SETTINGS.tmp" "$SETTINGS"
echo "✅ hooks 已从 settings.json 移除"

# 删除 slash command symlinks（只删 symlink，不删用户自建的同名文件）
# 注：当前版本已不再创建 slash command symlink，保留清理旧残留以防万一
for cmd in handoff resume fresh; do
    link="$HOME/.claude/commands/$cmd.md"
    [ -L "$link" ] && rm -f "$link"
done
echo "✅ slash commands symlinks 已清理"

# 删除 skill symlinks（含旧版遗留的 fresh）
for skill in handoff resume fresh; do
    link="$HOME/.claude/skills/cc-handoff-$skill"
    [ -L "$link" ] && rm -f "$link"
done
echo "✅ skills symlinks 已清理"

echo
echo "🧹 cc-handoff 已卸载"
echo "   数据保留在 ~/.claude/projects/*/handoffs/"
echo "   如需清空：rm -rf ~/.claude/projects/*/handoffs"
echo "   代码保留在 ~/.claude/cc-handoff/（可 rm -rf 删除）"
