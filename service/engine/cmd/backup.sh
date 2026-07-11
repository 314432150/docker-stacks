# ============================================================
#  cmd/backup.sh — 备份指定应用
# ============================================================
# 依赖: lib/discover.sh, cmd/_lib.sh
#
# 权限: 以 root 运行时 tar 可读取任何属主的文件，保留原始权限
#       以普通用户运行时，root 属主文件将 Permission denied

# ── 内部：构建 tar 打包路径列表（纯数据，不 emit） ──
# 参数: app_name [dir1,dir2,...]
# 第 2 个参数为可选逗号分隔目录列表，指定时仅备份这些目录
# 输出到 stdout: 每行  {rel_path}|{status}
#   status: "ok"=正常, "skip"=目录不存在
# 注意: 本函数不调用 _emit，避免 JSON 行混入 tar 路径
_build_backup_paths() {
    local name="$1"
    local only_dirs="$2"

    local dirs=()
    if [[ -n "$only_dirs" ]]; then
        IFS=',' read -ra dirs <<< "$only_dirs"
    else
        while IFS='|' read -r src _; do
            [[ -n "$src" ]] && dirs+=("$src")
        done < <(get_backup_dirs "$name")
    fi

    for d in "${dirs[@]}"; do
        local app_rel="stacks/${name}"

        local full_path="${ROOT}/instance/${app_rel}/${d}"
        [[ -d "$full_path" ]] && echo "${app_rel}/${d}|ok" || echo "${d}|skip"
    done
}

# ── 备份清理：保留最近 N 个备份文件 ──
_cleanup_old_backups() {
    local keep="$1"
    local current="$2"  # 当前刚生成的备份文件，不参与清理
    [[ "$keep" -le 0 ]] && return 0

    local files=()
    local f
    while IFS= read -r f; do
        [[ "$f" == "$current" ]] && continue  # 防御：排除当前备份
        files+=("$f")
    done < <(ls -1t "${BACKUP_ROOT}"/*.tar.gz 2>/dev/null || true)

    if [[ ${#files[@]} -le $keep ]]; then
        return 0
    fi

    for (( i = keep; i < ${#files[@]}; i++ )); do
        local old="${files[$i]}"
        local name; name="$(basename "$old")"
        rm -f "$old" 2>/dev/null || true
        rm -f "${old}.json" 2>/dev/null || true
        _emit "{\"type\":\"progress\",\"step\":\"清理旧备份: ${name}\"}"
    done
}

# ── 子命令入口 ──
cmd_backup() {
    local do_upload=false
    local keep_count=0
    local apps=()

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --upload) do_upload=true; shift ;;
            --keep)
                keep_count="${2:-0}"
                if [[ ! "$keep_count" =~ ^[0-9]+$ ]] || [[ "$keep_count" -lt 0 ]]; then
                    _emit '{"type":"error","msg":"--keep 后必须是非负整数"}'
                    return 1
                fi
                shift 2 ;;
            --*)
                _emit "{\"type\":\"error\",\"msg\":\"未知选项: $1\"}"
                return 1 ;;
            *)
                apps+=("$1"); shift ;;
        esac
    done

    if [[ ${#apps[@]} -eq 0 ]]; then
        _emit '{"type":"error","msg":"未指定要备份的应用"}'
        return 1
    fi

    # 验证 --upload 前提条件
    if [[ "$do_upload" == "true" ]]; then
        if ! webdav_configured; then
            _emit '{"type":"error","msg":"--upload 需要配置 WebDAV（WEBDAV_URL/USER/PASS）"}'
            return 1
        fi
        if ! webdav_connection_test; then
            _emit '{"type":"error","msg":"--upload 失败: WebDAV 连接不可达"}'
            return 1
        fi
    fi

    # 任务锁
    _acquire_lock "backup" || return 2
    trap _release_lock EXIT

    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"

    # 从 app_entry (可能为 "name:dir1,dir2" 格式) 中提取纯 app 名
    _extract_app_name() {
        local entry="$1"
        if [[ "$entry" == *:* ]]; then
            echo "${entry%%:*}"
        else
            echo "$entry"
        fi
    }

    # 构建纯 app 名列表（用于文件名、JSON 输出）
    local pure_apps=()
    for entry in "${apps[@]}"; do
        pure_apps+=("$(_extract_app_name "$entry")")
    done

    # 构建备份文件名（Linux 文件名最长 255 字节，留 15 字节余量）
    local max_fn=240
    local app_suffix
    app_suffix="$(printf '_%s' "${pure_apps[@]}")"
    local candidate="${stamp}${app_suffix}.tar.gz"

    local archive_name
    if [[ ${#candidate} -le $max_fn ]]; then
        archive_name="$candidate"
    else
        # 超限：截断 app 列表，附加 sha256 前 8 位保证唯一
        local hash
        hash="$(printf '%s' "${app_suffix}" | sha256sum | cut -c1-8)"
        local short_suffix=""
        for a in "${pure_apps[@]}"; do
            local trial="${stamp}${short_suffix}_${a}_...+${hash}.tar.gz"
            if [[ ${#trial} -le $max_fn ]]; then
                short_suffix="${short_suffix}_${a}"
            else
                break
            fi
        done
        archive_name="${stamp}${short_suffix}_...+${hash}.tar.gz"
    fi
    local archive="${BACKUP_ROOT}/${archive_name}"

    # 构建 JSON 数组字符串（仅纯 app 名）
    local apps_json="["
    for i in "${!pure_apps[@]}"; do
        [[ $i -gt 0 ]] && apps_json+=","
        apps_json+="\"${pure_apps[$i]}\""
    done
    apps_json+="]"

    _emit "{\"type\":\"start\",\"op\":\"backup\",\"file\":\"${archive_name}\",\"apps\":${apps_json}}"

    # 收集所有要打包的路径（解析 {rel_path}|{status} 格式）
    local paths=()
    for entry in "${apps[@]}"; do
        local app dirs_str
        if [[ "$entry" == *:* ]]; then
            app="${entry%%:*}"
            dirs_str="${entry#*:}"
        else
            app="$entry"
            dirs_str=""
        fi

        while IFS='|' read -r rel_path status; do
            [[ -z "$rel_path" ]] && continue
            if [[ "$status" == "skip" ]]; then
                _emit "{\"type\":\"skip\",\"app\":\"${app}\",\"dir\":\"${rel_path}\",\"reason\":\"目录不存在\"}"
                continue
            fi
            _emit "{\"type\":\"progress\",\"step\":\"收集 ${app}/${rel_path##*/}\"}"
            paths+=("$rel_path")
        done < <(_build_backup_paths "$app" "$dirs_str")
    done

    if [[ ${#paths[@]} -eq 0 ]]; then
        _emit '{"type":"error","msg":"没有可备份的目录"}'
        return 1
    fi

    mkdir -p "$BACKUP_ROOT"

    _emit "{\"type\":\"progress\",\"step\":\"打包 ${#paths[@]} 个目录\",\"current\":1,\"total\":1}"

    local error_file; error_file="$(mktemp)"
    if tar -czf "$archive" -C "${ROOT}/instance" "${paths[@]}" 2>"$error_file"; then
        local size; size="$(du -h "$archive" 2>/dev/null | cut -f1)"
        _emit "{\"type\":\"ok\",\"app\":\"${archive_name}\"}"

        # ── 写入索引文件（供 API 快速查询，避免每次 tar -tzf） ──
        local idx_file="${archive}.json"
        local byte_size
        byte_size="$(stat -c%s "$archive" 2>/dev/null || echo 0)"
        printf '{"name":"%s","size":%d,"mtime":"%s","apps":%s}\n' \
            "$archive_name" "$byte_size" "$(date -Iseconds)" "$apps_json" > "$idx_file"

        # ── 上传到 WebDAV ──
        local upload_ok=true
        if [[ "$do_upload" == "true" ]]; then
            _emit "{\"type\":\"progress\",\"step\":\"上传 ${archive_name} 到 WebDAV\"}"
            if webdav_upload "$archive" "$archive_name"; then
                _emit "{\"type\":\"progress\",\"step\":\"WebDAV 上传成功\"}"
            else
                _emit "{\"type\":\"error\",\"msg\":\"WebDAV 上传失败\"}"
                upload_ok=false
            fi
        fi

        # ── 清理旧备份 ──
        if [[ "$keep_count" -gt 0 ]]; then
            _cleanup_old_backups "$keep_count" "$archive"
        fi

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
