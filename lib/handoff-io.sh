#!/usr/bin/env bash
# handoff-io.sh —— handoff 文件的读写
# 文件布局：<storage>/active/<worktree-hash>.md
# 注意：调用方需先 source pwd-slug.sh

cc_handoff_path() {
    local pwd_path="${1:-$(pwd)}"
    local storage
    storage="$(cc_storage_dir "$pwd_path")"
    local hash
    hash="$(cc_worktree_hash "$pwd_path")"
    echo "$storage/active/${hash}.md"
}

# 基于业务 id 生成 handoff 路径：active/<hash>__<id>.md
# id 是业务标识（如 story-888-impl），同 id 覆盖，不同 id 共存
cc_handoff_path_for_id() {
    local id="$1"
    local pwd_path="${2:-$(pwd)}"
    local storage
    storage="$(cc_storage_dir "$pwd_path")"
    local hash
    hash="$(cc_worktree_hash "$pwd_path")"
    # sanitize id：只保留字母数字连字符下划线
    local safe_id
    safe_id="$(echo "$id" | tr -c 'A-Za-z0-9._-' '-' | sed 's/--*/-/g; s/^-//; s/-$//')"
    [ -z "$safe_id" ] && safe_id="task-$(date +%Y%m%d-%H%M)"
    echo "$storage/active/${hash}__${safe_id}.md"
}

# 列当前 worktree 的所有 active handoff，按修改时间降序（最新在前）
# 只识别新格式 <hash>__<id>.md（老格式 <hash>.md 已于 2026-04-24 全部迁移）
# 跨平台实现：用 POSIX `ls -t`（BSD/GNU/MSYS 都支持按 mtime 排序），避免 `stat -f`/`stat -c` 的平台分歧
cc_list_active_for_hash() {
    local pwd_path="${1:-$(pwd)}"
    local storage
    storage="$(cc_storage_dir "$pwd_path")"
    local hash
    hash="$(cc_worktree_hash "$pwd_path")"
    local dir="$storage/active"
    [ -d "$dir" ] || return 0
    # 子 shell cd 避免污染调用方 PWD；ls 出错（无匹配）静默
    ( cd "$dir" 2>/dev/null && ls -t "${hash}__"*.md 2>/dev/null ) \
        | while IFS= read -r name; do
            [ -n "$name" ] && echo "$dir/$name"
          done
    return 0
}

# 数当前 worktree 的 handoff 数量
cc_count_active_for_hash() {
    cc_list_active_for_hash "${1:-$(pwd)}" | grep -c . || echo 0
}

# 找到当前 worktree 对应的 handoff（存在返回路径，不存在返回空）
# 多 handoff 时返回最新那个（按 mtime）。调用方若需判多选，应用 cc_count_active_for_hash
# 显式 return 0 避免 ERR trap 在复合语句失败时误触发
cc_find_handoff() {
    local latest
    latest="$(cc_list_active_for_hash "${1:-$(pwd)}" | head -1)"
    if [ -n "$latest" ] && [ -f "$latest" ]; then
        echo "$latest"
    fi
    return 0
}

# 状态文件路径
cc_state_file() {
    local pwd_path="${1:-$(pwd)}"
    local session_id="$2"
    local kind="$3"   # injected | fresh | warned | usage
    local storage
    storage="$(cc_storage_dir "$pwd_path")"
    mkdir -p "$storage"
    echo "$storage/.${kind}-${session_id}"
}

# 清理超过 N 天的状态文件（避免累积）
cc_cleanup_stale_state() {
    local pwd_path="${1:-$(pwd)}"
    local days="${2:-7}"
    local storage
    storage="$(cc_storage_dir "$pwd_path")"
    [ -d "$storage" ] || return 0
    # 不用 `-delete`（MSYS find 不一定支持）；改 `-exec rm`，跨 BSD/GNU/MSYS 都可
    find "$storage" -maxdepth 1 -name ".injected-*" -mtime "+$days" -exec rm -f {} \; 2>/dev/null
    find "$storage" -maxdepth 1 -name ".fresh-*" -mtime "+$days" -exec rm -f {} \; 2>/dev/null
    find "$storage" -maxdepth 1 -name ".warned-*" -mtime "+$days" -exec rm -f {} \; 2>/dev/null
    find "$storage" -maxdepth 1 -name ".usage-*" -mtime "+$days" -exec rm -f {} \; 2>/dev/null
}
