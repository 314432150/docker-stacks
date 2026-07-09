# ============================================================
#  lib/backup.sh — 自定义目录选择 + 交互式备份
# ============================================================

customize_app() {
    local name="$1"
    local dirs=()
    local cached=()
    while IFS='|' read -r src is_cache; do
        [[ -n "$src" ]] || continue
        dirs+=("$src")
        cached+=("$is_cache")
    done < <(get_backup_dirs "$name")

    if [[ ${#dirs[@]} -eq 0 ]]; then
        echo -e "${DIM}  ${name} 无可备份目录${NC}"
        press_enter
        return
    fi

    while true; do
        printf '\033[H\033[J'
        header "🔧 自定义 ${name} 备份目录"

        for i in "${!dirs[@]}"; do
            local d="${dirs[$i]}"
            local rec="${cached[$i]}"
            local checked
            if is_selected "$name" "$d"; then checked="1"; else checked="0"; fi
            local marker
            marker="$(check_mark "$checked")"

            local tag=""
            [[ "$rec" == "0" ]] && tag=" ${DIM}(推荐)${NC}"

            local exists
            if [[ -d "${ROOT}/${d}" ]]; then
                exists="${GREEN}✓${NC}"
            else
                exists="${RED}✗${NC}"
            fi

            printf "  [%d] %b ${CYAN}%-40s${NC} %b%b\n" \
                "$((i+1))" "$marker" "$d" "$exists" "$tag"
        done

        echo
        echo -e "  ${DIM}命令: [数字]切换  [a]全选  [n]全不选  [回车]确认返回${NC}"
        read -r -p "  > " cmd

        if [[ -z "$cmd" ]]; then
            break
        elif [[ "$cmd" == "a" ]]; then
            local sf
            sf="$(state_file "${name}")"
            :> "$sf"
            for d in "${dirs[@]}"; do
                echo "$d" >> "$sf"
            done
        elif [[ "$cmd" == "n" ]]; then
            :> "$(state_file "${name}")"
        elif [[ "$cmd" =~ ^[0-9]+$ ]]; then
            local idx=$((cmd - 1))
            if [[ $idx -ge 0 ]] && [[ $idx -lt ${#dirs[@]} ]]; then
                toggle_dir "$name" "${dirs[$idx]}"
            fi
        fi
    done
}

interactive_backup() {
    local auto_yes="${1:-0}"

    init_state

    # 构建应用名列表
    local app_names=()
    local app_names_with_dirs=()
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        app_names+=("$name")
        local has_dirs=false
        while IFS='|' read -r src _; do
            [[ -n "$src" ]] && has_dirs=true && break
        done < <(get_backup_dirs "$name")
        if $has_dirs; then
            app_names_with_dirs+=("$name")
        fi
    done < <(discover_apps)

    if [[ ${#app_names_with_dirs[@]} -eq 0 ]]; then
        echo -e "${YELLOW}没有发现可备份的应用${NC}"
        return
    fi

    # auto_yes: 全选推荐项，跳过 TUI
    if [[ "$auto_yes" == "1" ]]; then
        select_all_recommended
        if ! has_any_selected; then
            echo -e "${YELLOW}  没有推荐的可备份内容${NC}"
            return
        fi
    else

    # ── TUI 渲染辅助 ──
    _rline() {
        local i="$1" name="$2" is_cursor="$3"
        local desc
        desc="$(get_description "$name")"
        [[ -n "$desc" ]] && desc=" — ${desc}"

        local checkbox
        if app_has_selection "$name"; then checkbox="${GREEN}[✓]${NC}"
        else checkbox="${DIM}[ ]${NC}"; fi

        local check_str=""
        while IFS='|' read -r src is_cache; do
            [[ -n "$src" ]] || continue
            local sel=0
            is_selected "$name" "$src" && sel=1 || true
            local marker; marker="$(check_mark "$sel")"
            local tag=""
            [[ "$is_cache" == "0" ]] && [[ "$sel" == "0" ]] && tag=" ${DIM}(推荐)${NC}"
            check_str+="${marker} ${CYAN}${src}${NC}${tag}  "
        done < <(get_backup_dirs "$name")

        if [[ $is_cursor -eq 1 ]]; then
            printf "  ${YELLOW}▸${NC} ${checkbox} ${BOLD}${WHITE}%-16s${NC}  %b%b\n" \
                "$name" "$check_str" "$desc"
        else
            printf "    ${checkbox} ${BOLD}%-16s${NC}  %b%b\n" \
                "$name" "$check_str" "$desc"
        fi
    }

    _upd_line() {
        local i="$1"
        local name="${app_names_with_dirs[$i]}"
        local is_cur=0
        [[ $i -eq $cursor ]] && is_cur=1
        printf '\033[%d;0H\033[K' $((5 + i))
        _rline "$i" "$name" "$is_cur"
    }

    _upd_summary() {
        local count; count="$(count_selected_apps)"
        local n=${#app_names_with_dirs[@]}
        printf '\033[%d;0H\033[J' $((5 + n))
        echo
        echo -e "  选中 ${GREEN}${count}${NC} 个应用"
        echo
        echo -e "  ${DIM}[↑↓/jk] 移动  [空格] 勾选/取消  [a] 全选/取消全选  [c] 自定义目录${NC}"
        echo -e "  ${DIM}[b/Enter] 开始备份  [q] 退出${NC}"
        printf '\033[?25l'
    }

    # 首次全量绘制
    local cursor=0
    printf '\033[H\033[J'
    printf '\033[?25l'
    header "📦 备份 — 选择要备份的内容"
    for i in "${!app_names_with_dirs[@]}"; do
        local is_first=0
        [[ $i -eq 0 ]] && is_first=1
        _rline "$i" "${app_names_with_dirs[$i]}" "$is_first"
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
                local n=${#app_names_with_dirs[@]}
                printf '\033[%d;0H\033[J' $((5 + n + 5))
                echo -e "${YELLOW}  已取消${NC}"
                return ;;
            $'\033[A'|k|K)
                if [[ $cursor -gt 0 ]]; then
                    local prev=$cursor
                    cursor=$((cursor - 1))
                    _upd_line "$prev"; _upd_line "$cursor"
                    printf '\033[%d;0H\033[?25l' $((5 + cursor))
                fi ;;
            $'\033[B'|j|J)
                local max=$(( ${#app_names_with_dirs[@]} - 1 ))
                if [[ $cursor -lt $max ]]; then
                    local prev=$cursor
                    cursor=$((cursor + 1))
                    _upd_line "$prev"; _upd_line "$cursor"
                    printf '\033[%d;0H\033[?25l' $((5 + cursor))
                fi ;;
            ' ')
                toggle_app "${app_names_with_dirs[$cursor]}"
                _upd_line "$cursor"; _upd_summary
                printf '\033[%d;0H\033[?25l' $((5 + cursor)) ;;
            a|A)
                if has_any_selected; then
                    rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
                    while IFS= read -r n; do
                        [[ -n "$n" ]] || continue
                        touch "$(state_file "${n}")"
                    done < <(discover_apps)
                else
                    rm -rf "$STATE_DIR"; mkdir -p "$STATE_DIR"
                    select_all_recommended
                fi
                for i in "${!app_names_with_dirs[@]}"; do _upd_line "$i"; done
                _upd_summary ;;
            c|C)
                printf '\033[?25h'
                customize_app "${app_names_with_dirs[$cursor]}"
                printf '\033[H\033[J'; printf '\033[?25l'
                header "📦 备份 — 选择要备份的内容"
                for i in "${!app_names_with_dirs[@]}"; do
                    local is_cur=0
                    [[ $i -eq $cursor ]] && is_cur=1
                    _rline "$i" "${app_names_with_dirs[$i]}" "$is_cur"
                done
                _upd_summary ;;
            ''|$'\r'|$'\n'|b|B)
                printf '\033[?25h'
                printf '\033[%d;0H\033[J' $((5 + ${#app_names_with_dirs[@]} + 5))
                break ;;
            *)  ;;
        esac
    done

    if ! has_any_selected; then
        echo -e "${YELLOW}  没有选中任何内容，已取消${NC}"
        return
    fi
    fi  # end TUI vs auto_yes

    # ── 确认界面 + 备份执行 ──
    clear
    header "📦 备份确认"

    local total_dirs=0
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        while IFS= read -r d; do
            [[ -n "$d" ]] || continue
            local src_dir
            if [[ "$name" == "dockge" ]]; then
                src_dir="${ROOT}/dockge/${d}"
            else
                src_dir="${ROOT}/stacks/${name}/${d}"
            fi
            local exists
            if [[ -d "$src_dir" ]]; then exists="${GREEN}✓ 存在${NC}"
            else exists="${RED}✗ 不存在${NC}"; fi
            printf "  ${CYAN}%-16s${NC} %-45s %b\n" "$name" "$d" "$exists"
            ((total_dirs++)) || true
        done < <(get_selected_dirs "$name")
    done < <(discover_apps)

    echo
    echo -e "  共 ${BOLD}${total_dirs}${NC} 个目录"
    echo

    # 收集选中的应用名（用于文件名）
    local selected_apps=()
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        local sf="$(state_file "${name}")"
        if [[ -f "$sf" ]] && [[ -s "$sf" ]]; then
            selected_apps+=("$name")
        fi
    done < <(discover_apps)

    local app_suffix=""
    if [[ ${#selected_apps[@]} -gt 0 ]]; then
        if [[ ${#selected_apps[@]} -le 6 ]]; then
            app_suffix="_$(printf '%s_' "${selected_apps[@]}" | sed 's/_$//')"
        else
            app_suffix="_$(printf '%s_' "${selected_apps[@]:0:6}" | sed 's/_$//')_$(( ${#selected_apps[@]} - 6 ))more"
        fi
    fi

    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    local default_dest="${BACKUP_ROOT}/${stamp}${app_suffix}"

    local label=""
    if [[ "$auto_yes" != "1" ]]; then
        echo
        echo -e "  ${DIM}可选: 为本次备份添加标签，方便还原时识别 (回车跳过)${NC}"
        echo -e "  ${DIM}示例: 升级jellyfin前 / 系统迁移 / 周常备份${NC}"
        read -r -p "  备份标签: " label
        if [[ -n "$label" ]]; then
            label="$(echo "$label" | sed 's/[\/\\[:space:][:cntrl:]]\+/-/g; s/--*/-/g; s/^-//;s/-$//' | head -c 60)"
        fi
    fi

    if [[ -n "$label" ]]; then
        default_dest="${BACKUP_ROOT}/${stamp}_${label}${app_suffix}"
    fi

    local dest
    if [[ "$auto_yes" == "1" ]]; then
        dest="${default_dest}"
    else
        echo -en "  备份文件名 [${DIM}${default_dest}.tar.gz${NC}]: "
        read -r dest_input
        dest="${dest_input:-${default_dest}}"
    fi
    dest="${dest%.tar.gz}"

    if [[ "$auto_yes" != "1" ]]; then
        confirm "确认开始备份?" "Y" || { echo -e "\n${YELLOW}  已取消${NC}"; return; }
    fi

    local archive="${dest}.tar.gz"
    echo -e "\n  正在备份到 ${CYAN}${archive}${NC} ...\n"

    local backup_paths=()
    local skip_count=0
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        while IFS= read -r drel; do
            [[ -n "$drel" ]] || continue

            local app_rel
            if [[ "$name" == "dockge" ]]; then app_rel="dockge"
            else app_rel="stacks/${name}"; fi
            local src="${ROOT}/${app_rel}/${drel}"
            if [[ ! -d "$src" ]]; then
                echo -e "  ${RED}✗${NC} [${name}] ${drel} — 目录不存在，跳过"
                ((skip_count++)) || true
                continue
            fi
            backup_paths+=("${app_rel}/${drel}")
            printf "  ${GREEN}✓${NC} ${CYAN}%-16s${NC} %s\n" "$name" "$drel"
        done < <(get_selected_dirs "$name")
    done < <(discover_apps)

    if [[ ${#backup_paths[@]} -eq 0 ]]; then
        echo
        echo -e "  ${YELLOW}没有可备份的目录${NC}"
        return
    fi

    echo
    printf "  ${BLUE}⏳${NC} 正在打包 ${BOLD}%d${NC} 个目录 ... " "${#backup_paths[@]}"
    if tar -czf "$archive" -C "$ROOT" "${backup_paths[@]}" 2>/dev/null; then
        local size; size=$(du -h "$archive" 2>/dev/null | cut -f1)
        echo -e "${GREEN}✓${NC} ${size}"
        local success=${#backup_paths[@]} fail=$skip_count
    else
        echo -e "${RED}✗${NC} 打包失败"
        local success=0 fail=${#backup_paths[@]}
    fi

    echo
    echo -e "  ${BOLD}完成${NC}: 成功 ${GREEN}${success}${NC}, 跳过 ${YELLOW}${fail}${NC}"
    echo -e "  备份位置: ${CYAN}${archive}${NC}"
}
