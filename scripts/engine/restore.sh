# ============================================================
#  engine/restore.sh — 从备份还原指定应用
# ============================================================
# 依赖: lib/discover.sh, engine/_lib.sh

# ── 内部：列出备份中的应用名 ──
_list_apps_in_backup() {
    local archive="$1"
    tar -tzf "$archive" 2>/dev/null | \
        grep -oP '(?:stacks|dockge)/[^/]+' | \
        sed 's|^stacks/||' | sort -u || true
}

# ── 内部：列出某应用在备份中的所有归档路径 ──
_app_archive_paths() {
    local archive="$1" app="$2"
    local prefix="stacks/${app}/"
    [[ "$app" == "dockge" ]] && prefix="dockge/"

    tar -tzf "$archive" 2>/dev/null | \
        grep "^${prefix}" | \
        grep -o "${prefix}[^/]\+" | sort -u || true
}

# ── 内部：安全备份现有目录 ──
_pre_restore_backup() {
    local archive="$1" app="$2"

    local app_path="stacks/${app}"
    [[ "$app" == "dockge" ]] && app_path="dockge"

    local target="${ROOT}/${app_path}"
    if [[ ! -d "$target" ]] || [[ -z "$(ls -A "$target" 2>/dev/null)" ]]; then
        return 0  # 无内容，不需备份
    fi

    local pre_dir="${BACKUP_ROOT}/pre_restore_$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$pre_dir"

    while IFS= read -r dir_path; do
        [[ -n "$dir_path" ]] || continue
        local safe_fn; safe_fn="$(echo "$dir_path" | tr '/' '_')"
        local pre_archive="${pre_dir}/${safe_fn}.tar.gz"

        if [[ -d "${ROOT}/${dir_path}" ]]; then
            _emit "{\"type\":\"progress\",\"step\":\"安全备份 ${dir_path}\"}"
            if tar -czf "$pre_archive" -C "$ROOT" "${dir_path}" 2>/dev/null; then
                _emit "{\"type\":\"progress\",\"step\":\"安全备份完成: ${pre_archive##*${BACKUP_ROOT}/}\"}"
            fi
        fi
    done < <(_app_archive_paths "$archive" "$app")
}

# ── 内部：容器管理 ──
_docker_stop() {
    local app="$1"
    local compose_dir="${ROOT}/stacks/${app}"
    [[ "$app" == "dockge" ]] && compose_dir="${ROOT}/dockge"

    if [[ ! -f "${compose_dir}/compose.yml" ]]; then return 0; fi
    if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null 2>&1; then
        return 0
    fi

    local running
    running=$(cd "$compose_dir" && docker compose ps --status=running -q 2>/dev/null)
    if [[ -n "$running" ]]; then
        if (cd "$compose_dir" && docker compose down 2>/dev/null); then
            _emit "{\"type\":\"progress\",\"step\":\"停止 ${app}\"}"
        fi
    fi
}

_docker_start() {
    local app="$1"
    local compose_dir="${ROOT}/stacks/${app}"
    [[ "$app" == "dockge" ]] && compose_dir="${ROOT}/dockge"

    if [[ ! -f "${compose_dir}/compose.yml" ]]; then return 0; fi
    if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null 2>&1; then
        return 0
    fi

    if timeout 60 docker compose -f "${compose_dir}/compose.yml" up -d 2>/dev/null; then
        _emit "{\"type\":\"progress\",\"step\":\"启动 ${app}\"}"
    else
        _emit "{\"type\":\"error\",\"app\":\"${app}\",\"msg\":\"容器启动失败\"}"
    fi
}

# ── 子命令入口 ──
cmd_restore() {
    local archive="$1"; shift
    local apps=("$@")

    if [[ -z "$archive" ]] || [[ ${#apps[@]} -eq 0 ]]; then
        _emit '{"type":"error","msg":"用法: engine.sh restore <archive> <app...>"}'
        return 1
    fi

    if [[ ! -f "$archive" ]]; then
        _emit "{\"type\":\"error\",\"msg\":\"备份文件不存在: ${archive}\"}"
        return 1
    fi

    _acquire_lock "restore" || return 2
    trap _release_lock EXIT

    local base; base="$(basename "$archive")"
    local apps_json="["
    for i in "${!apps[@]}"; do
        [[ $i -gt 0 ]] && apps_json+=","
        apps_json+="\"${apps[$i]}\""
    done
    apps_json+="]"

    _emit "{\"type\":\"start\",\"op\":\"restore\",\"file\":\"${base}\",\"apps\":${apps_json}}"

    local success=0 fail=0
    for app in "${apps[@]}"; do
        # 1. 停止容器
        _docker_stop "$app"

        # 2. 安全备份
        _pre_restore_backup "$archive" "$app"

        # 3. 解压
        local app_path="stacks/${app}"
        [[ "$app" == "dockge" ]] && app_path="dockge"

        _emit "{\"type\":\"progress\",\"step\":\"解压 ${app}\",\"current\":$((success + fail + 1)),\"total\":${#apps[@]}}"

        if tar -xzf "$archive" -C "$ROOT" "$app_path" 2>/dev/null; then
            _emit "{\"type\":\"ok\",\"app\":\"${app}\"}"
            ((success++)) || true
        else
            _emit "{\"type\":\"error\",\"app\":\"${app}\",\"msg\":\"解压失败\"}"
            ((fail++)) || true
        fi

        # 4. 启动容器
        _docker_start "$app"
    done

    _emit "{\"type\":\"done\",\"success\":${success},\"fail\":${fail}}"
    return 0
}
