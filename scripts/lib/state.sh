# ============================================================
#  lib/state.sh — 备份选中状态文件管理
# ============================================================

STATE_DIR="${ROOT}/.cache/backup-tool"
state_file() { echo "${STATE_DIR}/${1}"; }

init_state() {
    rm -rf "$STATE_DIR"
    mkdir -p "$STATE_DIR"

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        touch "$(state_file "${name}")"
    done < <(discover_apps)
}

select_all_recommended() {
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        local sf="$(state_file "${name}")"
        while IFS='|' read -r src is_cache; do
            [[ -n "$src" ]] || continue
            if [[ "$is_cache" == "0" ]]; then
                echo "$src" >> "$sf"
            fi
        done < <(get_backup_dirs "$name")
    done < <(discover_apps)
}

toggle_app() {
    local name="$1"
    local sel_count=0
    while IFS='|' read -r src _; do
        [[ -n "$src" ]] || continue
        is_selected "$name" "$src" && sel_count=$((sel_count + 1)) || true
    done < <(get_backup_dirs "$name")

    if [[ $sel_count -gt 0 ]]; then
        :> "$(state_file "${name}")"
    else
        local sf
        sf="$(state_file "${name}")"
        :> "$sf"
        while IFS='|' read -r src is_cache; do
            [[ -n "$src" ]] || continue
            [[ "$is_cache" == "0" ]] && echo "$src" >> "$sf"
        done < <(get_backup_dirs "$name") || true
    fi
}

get_selected_dirs() {
    local name="$1"
    local sf="$(state_file "${name}")"
    if [[ -f "$sf" ]]; then
        cat "$sf"
    fi
}

is_selected() {
    local name="$1" dir="$2"
    local sf="$(state_file "${name}")"
    [[ -f "$sf" ]] && grep -qxF "$dir" "$sf" 2>/dev/null
}

toggle_dir() {
    local name="$1" dir="$2"
    local sf="$(state_file "${name}")"
    if grep -qxF "$dir" "$sf" 2>/dev/null; then
        grep -vxF "$dir" "$sf" > "${sf}.tmp" 2>/dev/null || true
        mv "${sf}.tmp" "$sf"
    else
        echo "$dir" >> "$sf"
    fi
}

has_any_selected() {
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        local sf="$(state_file "${name}")"
        if [[ -f "$sf" ]] && [[ -s "$sf" ]]; then
            return 0
        fi
    done < <(discover_apps)
    return 1
}

app_has_selection() {
    local name="$1"
    local sf="$(state_file "${name}")"
    [[ -f "$sf" ]] && [[ -s "$sf" ]]
}

count_selected_apps() {
    local count=0
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        app_has_selection "$name" && ((count++)) || true
    done < <(discover_apps)
    echo "$count"
}
