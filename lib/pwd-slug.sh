#!/usr/bin/env bash
# pwd-slug.sh —— 将 pwd 转为 Claude Code 约定的 slug，定位存储目录
# 与 ~/.claude/projects/<slug>/ 的命名规则一致：/ 替换为 -，前缀补 -

cc_pwd_slug() {
    local pwd_path="${1:-$(pwd)}"
    # /Users/lx/IdeaProjects/xxx → -Users-lx-IdeaProjects-xxx
    echo "${pwd_path//\//-}"
}

cc_storage_dir() {
    local pwd_path="${1:-$(pwd)}"
    local slug
    slug="$(cc_pwd_slug "$pwd_path")"
    echo "$HOME/.claude/projects/$slug/handoffs"
}

cc_ensure_storage() {
    local dir
    dir="$(cc_storage_dir "${1:-$(pwd)}")"
    mkdir -p "$dir/active" "$dir/archive"
    echo "$dir"
}

# sha1 跨平台封装：Linux 一般 sha1sum / macOS 一般 shasum / 回退 openssl
# 输入走 stdin，输出仅 40 字符十六进制（无空格/文件名）
_cc_sha1_hex() {
    if command -v sha1sum >/dev/null 2>&1; then
        sha1sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 1 | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha1 | awk '{print $NF}'
    else
        # 最终兜底：用 cksum（非 sha1，但跨平台存在），仅保持唯一性
        cksum | awk '{printf "%08x%08x\n", $1, $2}'
    fi
}

# worktree-hash: sha1 前8位 + basename，保证全局唯一且可读
cc_worktree_hash() {
    local pwd_path="${1:-$(pwd)}"
    local hash
    hash="$(printf '%s' "$pwd_path" | _cc_sha1_hex | cut -c1-8)"
    local base
    base="$(basename "$pwd_path")"
    echo "${hash}-${base}"
}
