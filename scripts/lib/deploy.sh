# ============================================================
#  lib/deploy.sh — 交互式部署（直接从 compose.yml 启动应用）
# ============================================================

interactive_deploy() {
    local auto_yes="${1:-0}"

    local app_names=()
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        app_names+=("$name")
    done < <(discover_apps)

    if [[ ${#app_names[@]} -eq 0 ]]; then
        echo -e "${YELLOW}没有发现可部署的应用${NC}"
        return
    fi

    local deploy_selected=("${app_names[@]}")

    if [[ "$auto_yes" != "1" ]]; then

    _rline() {
        local name="$2" is_cursor="$3"
        local desc; desc="$(get_description "$name")"
        [[ -n "$desc" ]] && desc=" — ${desc}"

        local checked=false
        for s in "${deploy_selected[@]}"; do
            [[ "$s" == "$name" ]] && checked=true && break
        done
        local marker
        if $checked; then marker="${GREEN}✔${NC}"
        else marker="${DIM}·${NC}"; fi

        if [[ $is_cursor -eq 1 ]]; then
            printf "  ${YELLOW}▸${NC} %b ${BOLD}${WHITE}%-16s${NC}%s\n" \
                "$marker" "$name" "$desc"
        else
            printf "    %b ${BOLD}%-16s${NC}%s\n" \
                "$marker" "$name" "$desc"
        fi
    }
    _toggle_app() {
        local name="$1"
        local new_selected=()
        local found=false
        for s in "${deploy_selected[@]}"; do
            if [[ "$s" == "$name" ]]; then found=true
            else new_selected+=("$s"); fi
        done
        if ! $found; then new_selected+=("$name"); fi
        deploy_selected=("${new_selected[@]}")
    }

    _upd_line() {
        local i="$1"
        local name="${app_names[$i]}"
        local is_cur=0
        [[ $i -eq $cursor ]] && is_cur=1
        printf '\033[%d;0H\033[K' $((5 + i))
        _rline "$i" "$name" "$is_cur"
    }
    _upd_summary() {
        local n=${#app_names[@]}
        printf '\033[%d;0H\033[J' $((5 + n))
        echo
        echo -e "  已选 ${GREEN}${#deploy_selected[@]}${NC}/${n} 个应用"
        echo
        echo -e "  ${DIM}[↑↓/jk] 移动  [空格] 勾选/取消  [a] 全选/取消全选${NC}"
        echo -e "  ${DIM}[d/Enter] 开始部署  [q] 退出${NC}"
        printf '\033[?25l'
    }

    # 首次全量绘制
    local cursor=0
    printf '\033[H\033[2J'; printf '\033[?25l'
    header "🚀 部署 — 选择要启动的应用"
    for i in "${!app_names[@]}"; do
        local is_first=0
        [[ $i -eq 0 ]] && is_first=1
        _rline "$i" "${app_names[$i]}" "$is_first"
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
                local n=${#app_names[@]}
                printf '\033[%d;0H\033[J' $((5 + n + 5))
                echo -e "${YELLOW}  已取消${NC}"
                return ;;
            $'\033[A'|k|K)
                if [[ $cursor -gt 0 ]]; then
                    local prev=$cursor; cursor=$((cursor - 1))
                    _upd_line "$prev"; _upd_line "$cursor"
                    printf '\033[%d;0H\033[?25l' $((5 + cursor))
                fi ;;
            $'\033[B'|j|J)
                local max=$(( ${#app_names[@]} - 1 ))
                if [[ $cursor -lt $max ]]; then
                    local prev=$cursor; cursor=$((cursor + 1))
                    _upd_line "$prev"; _upd_line "$cursor"
                    printf '\033[%d;0H\033[?25l' $((5 + cursor))
                fi ;;
            ' ')
                _toggle_app "${app_names[$cursor]}"
                _upd_line "$cursor"; _upd_summary
                printf '\033[%d;0H\033[?25l' $((5 + cursor)) ;;
            a|A)
                if [[ ${#deploy_selected[@]} -eq ${#app_names[@]} ]]; then
                    deploy_selected=()
                else
                    deploy_selected=("${app_names[@]}")
                fi
                for i in "${!app_names[@]}"; do _upd_line "$i"; done
                _upd_summary ;;
            ''|$'\r'|$'\n'|d|D)
                printf '\033[?25h'
                printf '\033[%d;0H\033[J' $((5 + ${#app_names[@]} + 5))
                break ;;
            *)  ;;
        esac
    done

    if [[ ${#deploy_selected[@]} -eq 0 ]]; then
        echo -e "${YELLOW}  没有选择任何应用，已取消${NC}"
        return
    fi
    fi  # end TUI

    # 确认界面
    clear
    header "🚀 部署确认"
    for name in "${deploy_selected[@]}"; do
        echo -e "  ${CYAN}${name}${NC}"
    done
    echo
    echo -e "  共 ${BOLD}${#deploy_selected[@]}${NC} 个应用"
    echo

    if [[ "$auto_yes" != "1" ]]; then
        confirm "确认开始部署?" "Y" || { echo -e "\n${YELLOW}  已取消${NC}"; return; }
    fi

    if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null 2>&1; then
        echo -e "\n  ${RED}✗ docker compose 不可用，无法部署${NC}"
        return
    fi

    # ── 确保 .env 符号链接 ──
    local global_env="${ROOT}/global.env"
    if [[ -f "$global_env" ]]; then
        echo
        section "检查环境配置"
        for name in "${deploy_selected[@]}"; do
            local compose_dir
            if [[ "$name" == "dockge" ]]; then compose_dir="${ROOT}/dockge"
            else compose_dir="${ROOT}/stacks/${name}"; fi

            local env_link="${compose_dir}/.env"
            if [[ ! -L "$env_link" ]] || [[ "$(readlink -f "$env_link" 2>/dev/null)" != "$global_env" ]]; then
                rm -f "$env_link"
                ln -sf "../../global.env" "$env_link" 2>/dev/null
                echo -e "  ${GREEN}✓${NC} ${name} .env → global.env"
            else
                echo -e "  ${DIM}·${NC} ${name} ${DIM}(env 已就绪)${NC}"
            fi
        done
    else
        echo -e "  ${YELLOW}⚠ global.env 不存在，将使用各应用本地 .env${NC}"
    fi

    # ── 检测并停止已运行的容器 ──
    echo
    section "检查运行中容器"
    local stopped=0
    for name in "${deploy_selected[@]}"; do
        local compose_dir
        if [[ "$name" == "dockge" ]]; then compose_dir="${ROOT}/dockge"
        else compose_dir="${ROOT}/stacks/${name}"; fi

        if [[ ! -f "${compose_dir}/compose.yml" ]]; then
            continue
        fi

        local running
        running=$(cd "$compose_dir" && docker compose ps --services --filter "status=running" 2>/dev/null | head -1)
        if [[ -n "$running" ]]; then
            printf "  ${BLUE}↓${NC} 停止 ${BOLD}${name}${NC} ... "
            if (cd "$compose_dir" && docker compose down 2>/dev/null); then
                echo -e "${GREEN}✓${NC}"
                ((stopped++)) || true
            else
                echo -e "${RED}✗${NC}"
            fi
        else
            echo -e "  ${DIM}·${NC} ${name} ${DIM}(未运行)${NC}"
        fi
    done

    # 执行部署
    echo
    section "启动容器"
    local success=0 fail=0

    for name in "${deploy_selected[@]}"; do
        local compose_dir
        if [[ "$name" == "dockge" ]]; then compose_dir="${ROOT}/dockge"
        else compose_dir="${ROOT}/stacks/${name}"; fi

        if [[ ! -f "${compose_dir}/compose.yml" ]]; then
            echo -e "  ${DIM}·${NC} ${name} ${DIM}(无 compose.yml，跳过)${NC}"
            continue
        fi

        printf "  ${BLUE}↑${NC} 部署 ${BOLD}${name}${NC} ... "
        if (cd "$compose_dir" && docker compose up -d 2>/dev/null); then
            echo -e "${GREEN}✓${NC}"
            ((success++)) || true
        else
            echo -e "${RED}✗${NC}"
            ((fail++)) || true
        fi
    done

    echo
    echo -e "  ${BOLD}部署完成${NC}: 成功 ${GREEN}${success}${NC}, 失败 ${RED}${fail}${NC}"
}
