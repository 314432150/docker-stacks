# ============================================================
#  engine/backup.sh — 备份指定应用
# ============================================================
# 依赖: lib/discover.sh, lib/state.sh, engine/_lib.sh

# ── 内部：构建 tar 打包路径列表（纯数据，不 emit） ──
# 参数: app_name
# 输出到 stdout: 每行一个路径  {rel_path}|{skip_code}
#   skip_code: 0=正常,1=目录不存在(跳过)
# 注意: 本函数不调用 _emit，避免 JSON 行混入 tar 路径
_build_backup_paths() {
    local name="$1"

    local dirs=()
    while IFS='|' read -r src _; do
        [[ -n "$src" ]] && dirs+=("$src")
    done < <(get_backup_dirs "$name")

    for d in "${dirs[@]}"; do
        local app_rel
        if [[ "$name" == "dockge" ]]; then app_rel="dockge"
        else app_rel="stacks/${name}"; fi

        local full_path="${ROOT}/${app_rel}/${d}"
        if [[ ! -d "$full_path" ]]; then
            echo "${d}|skip"
        else
            echo "${app_rel}/${d}|ok"
        fi
    done
}

# ── 子命令入口 ──
cmd_backup() {
    local apps=("$@")

    if [[ ${#apps[@]} -eq 0 ]]; then
        _emit '{"type":"error","msg":"未指定要备份的应用"}'
        return 1
    fi

    # 任务锁
    _acquire_lock "backup" || return 2
    trap _release_lock EXIT

    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    local app_suffix
    app_suffix="$(printf '_%s' "${apps[@]}")"
    local archive_name="${stamp}${app_suffix}.tar.gz"
    local archive="${BACKUP_ROOT}/${archive_name}"

    # 构建 JSON 数组字符串
    local apps_json="["
    for i in "${!apps[@]}"; do
        [[ $i -gt 0 ]] && apps_json+=","
        apps_json+="\"${apps[$i]}\""
    done
    apps_json+="]"

    _emit "{\"type\":\"start\",\"op\":\"backup\",\"file\":\"${archive_name}\",\"apps\":${apps_json}}"

    # 收集所有要打包的路径（解析 {rel_path}|{status} 格式）
    local paths=()
    for app in "${apps[@]}"; do
        while IFS='|' read -r rel_path status; do
            [[ -z "$rel_path" ]] && continue
            if [[ "$status" == "skip" ]]; then
                _emit "{\"type\":\"skip\",\"app\":\"${app}\",\"dir\":\"${rel_path}\",\"reason\":\"目录不存在\"}"
                continue
            fi
            _emit "{\"type\":\"progress\",\"step\":\"收集 ${app}/${rel_path##*/}\"}"
            paths+=("$rel_path")
        done < <(_build_backup_paths "$app")
    done

    if [[ ${#paths[@]} -eq 0 ]]; then
        _emit '{"type":"error","msg":"没有可备份的目录"}'
        return 1
    fi

    mkdir -p "$BACKUP_ROOT"

    _emit "{\"type\":\"progress\",\"step\":\"打包 ${#paths[@]} 个目录\",\"current\":1,\"total\":1}"

    local error_file; error_file="$(mktemp)"
    if tar -czf "$archive" -C "$ROOT" "${paths[@]}" 2>"$error_file"; then
        local size; size="$(du -h "$archive" 2>/dev/null | cut -f1)"
        _emit "{\"type\":\"done\",\"file\":\"${archive_name}\",\"size\":\"${size}\",\"path\":\"${archive}\"}"
        rm -f "$error_file"
        return 0
    else
        local err_msg; err_msg="$(cat "$error_file" 2>/dev/null | tr '\n' ' ' | head -c 200)"
        _emit "{\"type\":\"error\",\"msg\":\"打包失败: ${err_msg}\"}"
        rm -f "$error_file" "$archive" 2>/dev/null
        return 1
    fi
}
