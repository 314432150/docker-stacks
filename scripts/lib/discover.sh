# ============================================================
#  lib/discover.sh — 应用发现、卷解析、描述提取
# ============================================================

discover_apps() {
    for compose_file in "${ROOT}"/stacks/*/compose.yml; do
        [[ -f "${compose_file}" ]] || continue
        local name
        name="$(basename "$(dirname "${compose_file}")")"
        # 跳过空壳
        if grep -q 'services:\s*{\s*}\s*$' "${compose_file}" 2>/dev/null; then
            continue
        fi
        echo "${name}"
    done
    # dockge
    if [[ -f "${ROOT}/dockge/compose.yml" ]]; then
        echo "dockge"
    fi
}

# 从 compose.yml 提取可备份目录
# 输出格式: "src|is_cache"
#   src       = 仓库相对路径（去掉 ./ 前缀）
#   is_cache  = 1=缓存(不推荐), 0=数据(推荐)
parse_volumes() {
    local file="$1"
    local in_volumes=false
    local indent_marker=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*volumes:[[:space:]]*$ ]]; then
            in_volumes=true
            indent_marker="$(echo "$line" | sed 's/volumes:.*//')"
            continue
        fi

        $in_volumes || continue

        local trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ -n "$trimmed" ]] && [[ ! "$trimmed" =~ ^# ]]; then
            local current_indent="${line%%[![:space:]]*}"
            if [[ "${#current_indent}" -le "${#indent_marker}" ]]; then
                in_volumes=false
                continue
            fi
        fi

        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(\./[^:]+):.+$ ]]; then
            local source
            source="$(echo "$line" | sed -E 's/^[[:space:]]*-[[:space:]]+(\.\/[^:]+):.+$/\1/')"

            if echo "$source" | grep -qE "$SYSTEM_PREFIXES"; then
                continue
            fi

            local src_clean="${source#./}"
            local is_cache=0
            if echo "$src_clean" | grep -qiE "$CACHE_PATTERNS"; then
                is_cache=1
            fi

            echo "${src_clean}|${is_cache}"
        fi
    done < "$file"
}

get_backup_dirs() {
    local name="$1"
    local compose_file
    if [[ "$name" == "dockge" ]]; then
        compose_file="${ROOT}/dockge/compose.yml"
    else
        compose_file="${ROOT}/stacks/${name}/compose.yml"
    fi

    if [[ -f "$compose_file" ]]; then
        parse_volumes "$compose_file"
    fi
}

get_description() {
    local name="$1"
    local compose_file
    if [[ "$name" == "dockge" ]]; then
        compose_file="${ROOT}/dockge/compose.yml"
    else
        compose_file="${ROOT}/stacks/${name}/compose.yml"
    fi

    if [[ -f "$compose_file" ]]; then
        grep -m1 -E '^[[:space:]]*#[[:space:]]*=+' "$compose_file" 2>/dev/null | \
            sed -E 's/^[[:space:]]*#[[:space:]]*=+[[:space:]]*//; s/[[:space:]]*=+[[:space:]]*$//' || true
    fi
}
