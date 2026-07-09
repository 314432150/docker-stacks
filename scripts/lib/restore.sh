# ============================================================
#  lib/restore.sh — 备份解析 + 交互式还原
# ============================================================

# 从备份中列出应用名（去重）
list_apps_in_backup() {
    local bp="$1"
    if [[ -n "${_TAR_CACHE:-}" ]]; then
        echo "$_TAR_CACHE" | grep -oP '(?:stacks|dockge)/[^/]+' | sed 's|^stacks/||' | sort -u || true
    else
        tar -tzf "$bp" 2>/dev/null | grep -oP '(?:stacks|dockge)/[^/]+' | sed 's|^stacks/||' | sort -u || true
    fi
}

backup_size_mb() {
    local bp="$1"
    local total_size
    total_size=$(stat -c%s "$bp" 2>/dev/null || stat -f%z "$bp" 2>/dev/null || echo 0)
    awk "BEGIN {printf \"%.0f\", $total_size / 1048576}"
}

app_archive_paths() {
    local bp="$1" app="$2"
    if [[ -n "${_TAR_CACHE:-}" ]]; then
        echo "$_TAR_CACHE" | grep "^stacks/${app}/" | grep -o "stacks/${app}/[^/]\+" | sort -u || true
    else
        tar -tzf "$bp" 2>/dev/null | grep "^stacks/${app}/" | grep -o "stacks/${app}/[^/]\+" | sort -u || true
    fi
}

interactive_restore() {
    local backups=()
    if [[ -d "$BACKUP_ROOT" ]]; then
        while IFS= read -r -d '' f; do
            local bname; bname="$(basename "$f")"
            [[ "$bname" == pre_restore_* ]] && continue
            backups+=("$bname")
        done < <(find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -name '*.tar.gz' -print0 2>/dev/null | sort -rz)
    fi

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "\n${YELLOW}  备份目录为空${NC}"
        echo -e "  路径: ${CYAN}${BACKUP_ROOT}${NC}"
        echo
        echo -e "  ${BOLD}📋 NAS 迁移 — 导入备份文件${NC}"
        echo
        echo -e "  请先将旧 NAS 上的备份文件复制到当前服务器:"
        echo
        echo -e "  ${DIM}方式1 — rsync 直接拉取 (推荐):${NC}"
        echo -e "    ${BOLD}rsync -avP 旧NAS用户名@旧NAS_IP:${ROOT}/backups/ ${BACKUP_ROOT}/${NC}"
        echo
        echo -e "  ${DIM}方式2 — scp 手动复制:${NC}"
        echo -e "    ${BOLD}scp -r 旧NAS用户名@旧NAS_IP:${ROOT}/backups/* ${BACKUP_ROOT}/${NC}"
        echo
        echo -e "  ${DIM}方式3 — 外接存储 / SMB 挂载:${NC}"
        echo -e "    ${BOLD}cp -r /mnt/usb/backups/* ${BACKUP_ROOT}/${NC}"
        echo
        echo -e "  ${DIM}完成后重新运行: sudo ${CMD_NAME} restore${NC}"
        echo
        press_enter
        return
    fi

    local selected_backup=""

    # 选择备份
    while true; do
        printf '\033[H\033[2J'
        header "📥 还原 — 选择备份"

        for i in "${!backups[@]}"; do
            local b="${backups[$i]}"
            local bpath="${BACKUP_ROOT}/${b}"
            local size_mb; size_mb="$(backup_size_mb "$bpath")"
            local apps
            apps="$(list_apps_in_backup "$bpath" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
            [[ -z "$apps" ]] && apps="${DIM}(空)${NC}"

            printf "  [%d] ${BOLD}%s${NC}  ${DIM}%s MB${NC}\n" "$((i+1))" "$b" "$size_mb"
            echo -e "      应用: ${apps}"
        done

        echo
        echo -e "  ${DIM}命令: [数字]选择备份  [q]退出${NC}"
        read -r -p "  > " cmd

        if [[ "$cmd" == "q" || "$cmd" == "Q" ]]; then
            return
        elif [[ "$cmd" =~ ^[0-9]+$ ]]; then
            local idx=$((cmd - 1))
            if [[ $idx -ge 0 ]] && [[ $idx -lt ${#backups[@]} ]]; then
                selected_backup="${BACKUP_ROOT}/${backups[$idx]}"
                break
            fi
        fi
    done

    # 缓存 tar 列表
    _TAR_CACHE=$(tar -tzf "$selected_backup" 2>/dev/null || true)

    local backup_apps=()
    while IFS= read -r aname; do
        [[ -n "$aname" ]] || continue
        if [[ -d "${ROOT}/stacks/${aname}" ]] || [[ "$aname" == "dockge" ]]; then
            backup_apps+=("$aname")
        fi
    done < <(list_apps_in_backup "$selected_backup")

    if [[ ${#backup_apps[@]} -eq 0 ]]; then
        echo -e "\n${YELLOW}  备份中没有可还原的应用${NC}"
        press_enter
        return
    fi

    # 选择要还原的应用（TUI）
    local app_archive_counts=()
    for name in "${backup_apps[@]}"; do
        local ac
        ac=$(echo "$_TAR_CACHE" | grep "^stacks/${name}/" | grep -o "stacks/${name}/[^/]\+" | sort -u | wc -l)
        app_archive_counts+=("$ac")
    done
    local restore_selected=("${backup_apps[@]}")

    while true; do
        _rline() {
            local name="$2" is_cursor="$3"
            local desc; desc="$(get_description "$name")"
            [[ -n "$desc" ]] && desc=" — ${desc}"
            local checked=false
            for s in "${restore_selected[@]}"; do
                [[ "$s" == "$name" ]] && checked=true && break
            done
            local marker
            if $checked; then marker="${GREEN}✔${NC}"
            else marker="${DIM}·${NC}"; fi
            local ac="${app_archive_counts[$1]}"
            if [[ $is_cursor -eq 1 ]]; then
                printf "  ${YELLOW}▸${NC} %b ${BOLD}${WHITE}%-16s${NC} ${DIM}%d个归档${NC}%s\n" \
                    "$marker" "$name" "$ac" "$desc"
            else
                printf "    %b ${BOLD}%-16s${NC} ${DIM}%d个归档${NC}%s\n" \
                    "$marker" "$name" "$ac" "$desc"
            fi
        }
        _toggle_app() {
            local name="$1"
            local new_selected=()
            local found=false
            for s in "${restore_selected[@]}"; do
                if [[ "$s" == "$name" ]]; then found=true
                else new_selected+=("$s"); fi
            done
            if ! $found; then new_selected+=("$name"); fi
            restore_selected=("${new_selected[@]}")
        }

        _upd_line() {
            local i="$1"
            local name="${backup_apps[$i]}"
            local is_cur=0
            [[ $i -eq $cursor ]] && is_cur=1
            printf '\033[%d;0H\033[K' $((5 + i))
            _rline "$i" "$name" "$is_cur"
        }
        _upd_summary() {
            local n=${#backup_apps[@]}
            printf '\033[%d;0H\033[J' $((5 + n))
            echo
            echo -e "  已选 ${GREEN}${#restore_selected[@]}${NC} 个应用"
            echo
            echo -e "  ${DIM}[↑↓/jk] 移动  [空格] 勾选/取消  [a] 全选/取消全选${NC}"
            echo -e "  ${DIM}[r/Enter] 开始还原  [q] 退出${NC}"
            printf '\033[?25l'
        }

        # 首次全量绘制
        local cursor=0
        printf '\033[H\033[2J'; printf '\033[?25l'
        header "📥 还原 — $(basename "$selected_backup")"
        for i in "${!backup_apps[@]}"; do
            local is_first=0
            [[ $i -eq 0 ]] && is_first=1
            _rline "$i" "${backup_apps[$i]}" "$is_first"
        done
        _upd_summary

        while true; do
            local key
            IFS= read -rsn1 key
            if [[ $key == $'\033' ]]; then
                local extra
                read -rsn2 -t 0.01 extra 2>/dev/null || true
                key+="$extra"
            fi

            case "$key" in
                q|Q)
                    printf '\033[?25h'
                    local n=${#backup_apps[@]}
                    printf '\033[%d;0H\033[J' $((5 + n + 5))
                    return ;;
                $'\033[A'|k|K)
                    if [[ $cursor -gt 0 ]]; then
                        local prev=$cursor; cursor=$((cursor - 1))
                        _upd_line "$prev"; _upd_line "$cursor"
                        printf '\033[%d;0H\033[?25l' $((5 + cursor))
                    fi ;;
                $'\033[B'|j|J)
                    local max=$(( ${#backup_apps[@]} - 1 ))
                    if [[ $cursor -lt $max ]]; then
                        local prev=$cursor; cursor=$((cursor + 1))
                        _upd_line "$prev"; _upd_line "$cursor"
                        printf '\033[%d;0H\033[?25l' $((5 + cursor))
                    fi ;;
                ' ')
                    _toggle_app "${backup_apps[$cursor]}"
                    _upd_line "$cursor"; _upd_summary
                    printf '\033[%d;0H\033[?25l' $((5 + cursor)) ;;
                a|A)
                    if [[ ${#restore_selected[@]} -eq 0 ]]; then
                        restore_selected=("${backup_apps[@]}")
                    else
                        restore_selected=()
                    fi
                    for i in "${!backup_apps[@]}"; do _upd_line "$i"; done
                    _upd_summary ;;
                ''|$'\r'|$'\n'|r|R)
                    printf '\033[?25h'
                    printf '\033[%d;0H\033[J' $((5 + ${#backup_apps[@]} + 5))
                    break ;;
                *)  ;;
            esac
        done

        if [[ ${#restore_selected[@]} -eq 0 ]]; then
            echo -e "${YELLOW}  没有选择任何应用${NC}"
            press_enter
            continue
        fi
        break
    done

    # 确认还原
    clear
    header "📥 还原确认"
    for name in "${restore_selected[@]}"; do
        echo -e "  ${CYAN}${name}${NC}"
        while IFS= read -r p; do
            [[ -n "$p" ]] && echo -e "    ${DIM}${p}${NC}"
        done < <(app_archive_paths "$selected_backup" "$name")
    done
    echo
    if ! confirm "确认还原? 这将覆盖现有文件!" "Y"; then
        echo -e "\n${YELLOW}  已取消${NC}"
        return
    fi

    # ── 迁移前安全备份 ──
    local migration_backup_dir=""
    local has_existing=0
    for name in "${restore_selected[@]}"; do
        local target_dir="${ROOT}/stacks/${name}"
        [[ "$name" == "dockge" ]] && target_dir="${ROOT}/dockge"
        if [[ -d "$target_dir" ]] && [[ -n "$(ls -A "$target_dir" 2>/dev/null)" ]]; then
            has_existing=1; break
        fi
    done

    if [[ $has_existing -eq 1 ]]; then
        echo
        section "迁移前安全备份"
        echo -e "  ${YELLOW}⚠${NC} 检测到目标目录已有内容"
        echo -e "  ${DIM}还原将覆盖现有文件，建议先创建安全备份以防万一${NC}"
        echo
        if confirm "创建迁移前安全备份?" "N"; then
            local pre_stamp; pre_stamp="$(date +%Y%m%d-%H%M%S)"
            migration_backup_dir="${BACKUP_ROOT}/pre_restore_${pre_stamp}"
            mkdir -p "$migration_backup_dir"

            local pre_ok=0 pre_fail=0
            for name in "${restore_selected[@]}"; do
                while IFS= read -r dir_path; do
                    [[ -n "$dir_path" ]] || continue
                    if [[ -d "${ROOT}/${dir_path}" ]] && \
                       [[ -n "$(ls -A "${ROOT}/${dir_path}" 2>/dev/null)" ]]; then
                        local safe_fn; safe_fn="$(echo "$dir_path" | tr '/' '_')"
                        local pre_archive="${migration_backup_dir}/${safe_fn}.tar.gz"
                        printf "  ${BLUE}⏳${NC} 备份现有 ${CYAN}${dir_path}${NC} ... "
                        if tar -czf "$pre_archive" -C "$ROOT" "${dir_path}" 2>/dev/null; then
                            local pre_size; pre_size=$(du -h "$pre_archive" 2>/dev/null | cut -f1)
                            echo -e "${GREEN}✓${NC} ${pre_size}"
                            ((pre_ok++)) || true
                        else
                            echo -e "${RED}✗${NC}"
                            ((pre_fail++)) || true
                        fi
                    fi
                done < <(app_archive_paths "$selected_backup" "$name")
            done
            echo
            echo -e "  安全备份: 成功 ${GREEN}${pre_ok}${NC}, 失败 ${RED}${pre_fail}${NC}"
            echo -e "  位置: ${CYAN}${migration_backup_dir}${NC}"
        else
            echo -e "  ${DIM}已跳过安全备份${NC}"
        fi
    fi

    # ── 停止受影响的容器 ──
    local has_compose=false
    command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1 && has_compose=true

    local stopped_apps=()
    if $has_compose; then
        echo
        section "停止容器"
        for name in "${restore_selected[@]}"; do
            local compose_dir
            if [[ "$name" == "dockge" ]]; then compose_dir="${ROOT}/dockge"
            else compose_dir="${ROOT}/stacks/${name}"; fi
            if [[ -f "${compose_dir}/compose.yml" ]]; then
                local running
                running=$(cd "$compose_dir" && docker compose ps --status=running -q 2>/dev/null)
                if [[ -n "$running" ]]; then
                    printf "  ${BLUE}→${NC} 停止 ${BOLD}${name}${NC} ... "
                    if (cd "$compose_dir" && docker compose down 2>/dev/null); then
                        echo -e "${GREEN}✓${NC}"; stopped_apps+=("$name")
                    else echo -e "${RED}✗${NC}"; fi
                else
                    echo -e "  ${DIM}·${NC} ${name} ${DIM}(未运行，跳过)${NC}"
                fi
            fi
        done
        if [[ ${#stopped_apps[@]} -eq 0 ]]; then
            echo -e "  ${DIM}没有运行中的容器需要停止${NC}"
        fi
    else
        echo -e "\n  ${YELLOW}⚠ docker compose 不可用，跳过容器管理${NC}"
    fi

    # 执行还原
    echo
    section "解压备份"
    local success=0 fail=0
    for name in "${restore_selected[@]}"; do
        local app_path="stacks/${name}"
        [[ "$name" == "dockge" ]] && app_path="dockge"
        printf "  ${BLUE}⏳${NC} 解压 ${BOLD}${name}${NC} ... "
        if tar -xzf "$selected_backup" -C "$ROOT" "$app_path" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"; ((success++)) || true
        else
            echo -e "${RED}✗${NC}"; ((fail++)) || true
        fi
    done

    echo
    echo -e "  ${BOLD}解压完成${NC}: 成功 ${GREEN}${success}${NC}, 失败 ${RED}${fail}${NC}"

    # ── 重新启动容器 ──
    if $has_compose; then
        echo
        section "启动容器"
        for name in "${restore_selected[@]}"; do
            local compose_dir
            if [[ "$name" == "dockge" ]]; then compose_dir="${ROOT}/dockge"
            else compose_dir="${ROOT}/stacks/${name}"; fi
            if [[ ! -f "${compose_dir}/compose.yml" ]]; then
                echo -e "  ${DIM}·${NC} ${name} ${DIM}(无 compose.yml，跳过)${NC}"
                continue
            fi
            printf "  ${BLUE}→${NC} 启动 ${BOLD}${name}${NC} ... "
            if timeout 60 docker compose -f "${compose_dir}/compose.yml" up -d 2>/dev/null; then
                echo -e "${GREEN}✓${NC}"
            else echo -e "${RED}✗${NC}"; fi
        done
    else
        echo -e "  ${DIM}compose 不可用，请手动启动服务${NC}"
    fi

    if [[ -n "$migration_backup_dir" ]] && [[ -d "$migration_backup_dir" ]]; then
        echo
        echo -e "  ${DIM}💡 迁移前安全备份已保存到: ${CYAN}${migration_backup_dir}${NC}"
        echo -e "  ${DIM}   确认还原无误后可手动删除: rm -rf ${migration_backup_dir}${NC}"
    fi
}
