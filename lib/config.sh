#!/usr/bin/env bash
# config.sh —— 层级配置合并：内置默认 < 用户全局 < 项目级
# 首选 JSON（零依赖），YAML 需要 yq 作为可选
# 查找顺序：.claude/handoff.json > .claude/handoff.yaml（需 yq）

_cc_load_file_as_json() {
    local file="$1"
    [ -f "$file" ] || return 1
    case "$file" in
        *.json)
            cat "$file"
            ;;
        *.yaml|*.yml)
            if command -v yq >/dev/null 2>&1; then
                yq -o=json '.' "$file" 2>/dev/null
            else
                return 1
            fi
            ;;
    esac
}

_cc_first_existing() {
    for f in "$@"; do
        [ -f "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}

cc_load_config() {
    local pwd_path="${1:-$(pwd)}"

    # 内置默认
    local result='{
        "enabled": true,
        "threshold": 0.35,
        "model_limits": {
            "default": 200000,
            "claude-opus-4-7": 200000,
            "claude-sonnet-4-6": 200000,
            "claude-haiku-4-5": 200000
        }
    }'

    # 用户全局
    local user_cfg
    user_cfg="$(_cc_first_existing \
        "$HOME/.claude/cc-handoff/config.json" \
        "$HOME/.claude/cc-handoff/config.yaml" 2>/dev/null)"
    if [ -n "$user_cfg" ]; then
        local user_json
        user_json="$(_cc_load_file_as_json "$user_cfg")"
        if [ -n "$user_json" ]; then
            result="$(jq -s '.[0] * .[1]' <(echo "$result") <(echo "$user_json") 2>/dev/null || echo "$result")"
        fi
    fi

    # 项目级（最高优先级）
    local project_cfg
    project_cfg="$(_cc_first_existing \
        "$pwd_path/.claude/handoff.json" \
        "$pwd_path/.claude/handoff.yaml" 2>/dev/null)"
    if [ -n "$project_cfg" ]; then
        local project_json
        project_json="$(_cc_load_file_as_json "$project_cfg")"
        if [ -n "$project_json" ]; then
            result="$(jq -s '.[0] * .[1]' <(echo "$result") <(echo "$project_json") 2>/dev/null || echo "$result")"
        fi
    fi

    echo "$result"
}

cc_config_enabled() {
    local cfg="$1"
    [[ "$(echo "$cfg" | jq -r '.enabled // true')" != "false" ]]
}

cc_config_threshold() {
    local cfg="$1"
    echo "$cfg" | jq -r '.threshold // 0.35'
}
