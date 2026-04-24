#!/usr/bin/env bash
# smoke.sh —— CI 用最小端到端冒烟：lib 函数能跑 + 跨 sha1 工具一致
# 设计为可独立跑：tests/smoke.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

pass=0
fail=0
_assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ok   · $label"
        pass=$((pass+1))
    else
        echo "  FAIL · $label"
        echo "         expected: $expected"
        echo "         actual:   $actual"
        fail=$((fail+1))
    fi
}
_assert_nonempty() {
    local v="$1" label="$2"
    if [ -n "$v" ]; then
        echo "  ok   · $label ($v)"
        pass=$((pass+1))
    else
        echo "  FAIL · $label (empty)"
        fail=$((fail+1))
    fi
}

echo "== env =="
echo "bash: $BASH_VERSION"
uname -s

echo
echo "== load lib =="
# shellcheck disable=SC1091
source lib/pwd-slug.sh
# shellcheck disable=SC1091
source lib/handoff-io.sh

echo
echo "== sha1 dispatch 一致性 =="
# 所有可用工具输出应一致（相同输入 → 相同 sha1）
INPUT="hello-cc-handoff"
EXPECT="$(printf '%s' "$INPUT" | _cc_sha1_hex)"
_assert_nonempty "$EXPECT" "_cc_sha1_hex 产出"
if command -v sha1sum >/dev/null 2>&1; then
    S="$(printf '%s' "$INPUT" | sha1sum | awk '{print $1}')"
    _assert_eq "$S" "$EXPECT" "_cc_sha1_hex == sha1sum"
fi
if command -v openssl >/dev/null 2>&1; then
    S="$(printf '%s' "$INPUT" | openssl dgst -sha1 | awk '{print $NF}')"
    _assert_eq "$S" "$EXPECT" "_cc_sha1_hex == openssl"
fi

echo
echo "== cc_worktree_hash 确定性 =="
H1="$(cc_worktree_hash "/tmp/fake/repo")"
H2="$(cc_worktree_hash "/tmp/fake/repo")"
_assert_eq "$H1" "$H2" "同路径两次调用输出一致"
_assert_eq "repo" "${H1##*-}" "hash 以 basename 结尾"

echo
echo "== cc_list_active_for_hash 空目录 =="
TMP="$(mktemp -d)"
mkdir -p "$TMP/storage/active"
# 模拟 cc_storage_dir：临时覆盖 HOME + 伪造 project slug
export HOME_BACKUP="$HOME"
export HOME="$TMP"
SLUG="$(cc_pwd_slug "/tmp/fake/repo")"
mkdir -p "$HOME/.claude/projects/$SLUG/handoffs/active"
OUT="$(cc_list_active_for_hash "/tmp/fake/repo")"
_assert_eq "" "$OUT" "空目录返回空"

echo
echo "== cc_list_active_for_hash 排序 =="
HASH="$(cc_worktree_hash "/tmp/fake/repo")"
ACT="$HOME/.claude/projects/$SLUG/handoffs/active"
# 造两个文件，B 比 A 新
touch -t 202601010000 "$ACT/${HASH}__task-a.md"
touch -t 202602010000 "$ACT/${HASH}__task-b.md"
OUT="$(cc_list_active_for_hash "/tmp/fake/repo")"
FIRST="$(echo "$OUT" | head -1)"
SECOND="$(echo "$OUT" | sed -n '2p')"
_assert_eq "${HASH}__task-b.md" "$(basename "$FIRST")"  "最新文件排第一"
_assert_eq "${HASH}__task-a.md" "$(basename "$SECOND")" "次新文件排第二"

echo
echo "== cc_handoff_path_for_id sanitize =="
P1="$(cc_handoff_path_for_id "story/123 impl" "/tmp/fake/repo")"
_assert_eq "${HASH}__story-123-impl.md" "$(basename "$P1")" "id 非法字符→连字符"

# 还原
export HOME="$HOME_BACKUP"
rm -rf "$TMP"

echo
echo "== 结果 =="
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
