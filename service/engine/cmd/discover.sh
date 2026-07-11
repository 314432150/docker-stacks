# ============================================================
#  cmd/discover.sh — 应用发现（JSON 输出）
# ============================================================
# 依赖: lib/discover.sh (discover_apps, get_backup_dirs, get_description)
# 输出包含权限级别信息（engine.privilege: root|user）

cmd_discover() {
    # 权限级别
    local priv="user"
    [[ ${EUID:-0} -eq 0 ]] && priv="root"

    echo -n "{\"type\":\"apps\",\"engine\":{\"privilege\":\"${priv}\"},\"apps\":["
    local first=true

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue

        local desc; desc="$(_escape_json "$(get_description "$name")")"
        local esc_name; esc_name="$(_escape_json "$name")"

        $first || echo -n ','
        first=false

        echo -n "{\"name\":\"${esc_name}\",\"description\":\"${desc}\",\"dirs\":["

        local dir_first=true
        while IFS='|' read -r src is_cache; do
            [[ -n "$src" ]] || continue
            $dir_first || echo -n ','
            dir_first=false

            local check_path="${ROOT}/instance/stacks/${esc_name}/${src}"
            local esc_src; esc_src="$(_escape_json "$src")"

            local exists=false
            [[ -d "$check_path" ]] && exists=true

            local recommended
            if [[ "$is_cache" == "0" ]]; then recommended=true
            else recommended=false; fi

            echo -n "{\"path\":\"${esc_src}\",\"recommended\":${recommended},\"exists\":${exists}}"
        done < <(get_backup_dirs "$name")

        echo -n ']}'
    done < <(discover_apps)

    echo ']}'
}
