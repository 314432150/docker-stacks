#!/usr/bin/env bash
# ============================================================
#  docker-stacks 交互式备份 / 还原工具 (纯 Bash，零依赖)
# ============================================================
#
# 用法:
#   bash scripts/backup.sh                  # 交互式主菜单（备份 / 还原）
#   bash scripts/backup.sh backup           # 进入交互式备份
#   bash scripts/backup.sh backup -y        # 非交互一键备份全部推荐项
#   bash scripts/backup.sh restore          # 进入交互式还原
#   bash scripts/backup.sh --install        # 注册为全局命令 ds-backup（安装到 /usr/local/bin）
#
# 注册为全局命令后可在任意目录直接调用:
#   ds-backup
#   ds-backup backup -y
#   ds-backup restore
#
# ⚠️ 推荐用 sudo 执行，确保备份还原时保留文件原始权限:
#   sudo ds-backup backup -y
#   sudo ds-backup restore
#
# 环境变量:
#   BACKUP_ROOT   备份输出目录（默认: <仓库>/backups）
#   AUTO_YES      非交互模式，跳过确认（=1）
#
set -euo pipefail

# ── 解析脚本真实路径（支持软链接） ──
_resolve_script() {
    local src="${BASH_SOURCE[0]}"
    if command -v realpath &>/dev/null; then
        realpath "$src"
    elif command -v readlink &>/dev/null && readlink -f "$src" &>/dev/null 2>&1; then
        readlink -f "$src"
    else
        # 手动跟随符号链接
        local dir
        dir="$(cd "$(dirname "$src")" && pwd)"
        while [[ -L "$src" ]]; do
            src="$(readlink "$src")"
            [[ "$src" != /* ]] && src="$dir/$src"
            dir="$(cd "$(dirname "$src")" && pwd)"
        done
        cd "$dir" && pwd
        echo "$(cd "$dir" && pwd)/$(basename "$src")"
    fi
}
SCRIPT_PATH="$(_resolve_script)"
ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-${ROOT}/backups}"

# ──────────────────────────────────────────────
# 终端颜色（检测 tty）
# ──────────────────────────────────────────────
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    BOLD='\033[1m';    DIM='\033[2m'
    RED='\033[91m';    GREEN='\033[92m'
    YELLOW='\033[93m'; BLUE='\033[94m'
    CYAN='\033[96m';   WHITE='\033[97m'
    NC='\033[0m'
else
    BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; WHITE=''; NC=''
fi

# ──────────────────────────────────────────────
# 缓存目录关键词（匹配到则不推荐默认勾选）
# ──────────────────────────────────────────────
CACHE_PATTERNS='cache|tmp|temp|transcodes|metadata'

# 外部挂载前缀（不参与备份）
SYSTEM_PREFIXES='^\$|^/etc/|^/dev/|^/proc/|^/sys/|^/run/|^/var/run/|^~|^\.\.'

# ──────────────────────────────────────────────
# 工具函数
# ──────────────────────────────────────────────
header() {
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo
}

section() { echo -e "\n${BOLD}${CYAN}$1${NC}"; }

success() { echo -e "  ${GREEN}✓${NC} $1"; }
fail()    { echo -e "  ${RED}✗${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
info()    { echo -e "  ${BLUE}→${NC} $1"; }

confirm() {
    local prompt="$1"
    local default="${2:-N}"
    local yn
    while true; do
        if [[ "$default" == "Y" ]]; then
            echo -en "  ${YELLOW}${prompt} [Y/n]: ${NC}"
            read -r yn
            if [[ -z "$yn" ]] || [[ "$yn" =~ ^[Yy] ]]; then
                return 0
            elif [[ "$yn" =~ ^[Nn] ]]; then
                return 1
            fi
        else
            echo -en "  ${YELLOW}${prompt} [y/N]: ${NC}"
            read -r yn
            if [[ "$yn" =~ ^[Yy] ]]; then
                return 0
            elif [[ -z "$yn" ]] || [[ "$yn" =~ ^[Nn] ]]; then
                return 1
            fi
        fi
        # 非法输入，重新提示
    done
}

press_enter() {
    echo -en "  ${DIM}按回车继续...${NC}"
    read -r
}

# ──────────────────────────────────────────────
# 应用发现
# ──────────────────────────────────────────────
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

# ──────────────────────────────────────────────
# 卷解析：从 compose.yml 提取可备份目录
# 输出格式: "src|is_cache"
#   src       = 仓库相对路径（去掉 ./ 前缀）
#   is_cache  = 1=缓存(不推荐), 0=数据(推荐)
# ──────────────────────────────────────────────
parse_volumes() {
    local file="$1"
    local in_volumes=false
    local indent_marker=""

    while IFS= read -r line; do
        # 检测 volumes: 段开始
        if [[ "$line" =~ ^[[:space:]]*volumes:[[:space:]]*$ ]]; then
            in_volumes=true
            # 记录缩进，用于检测段结束
            indent_marker="$(echo "$line" | sed 's/volumes:.*//')"
            continue
        fi

        $in_volumes || continue

        # 检测段结束：非空行且缩进不深于 volumes: 且不是注释
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ -n "$trimmed" ]] && [[ ! "$trimmed" =~ ^# ]]; then
            local current_indent="${line%%[![:space:]]*}"
            if [[ "${#current_indent}" -le "${#indent_marker}" ]]; then
                in_volumes=false
                continue
            fi
        fi

        # 匹配:   - ./path:/container/path
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(\./[^:]+):.+$ ]]; then
            local source
            source="$(echo "$line" | sed -E 's/^[[:space:]]*-[[:space:]]+(\.\/[^:]+):.+$/\1/')"

            # 跳过外部挂载
            if echo "$source" | grep -qE "$SYSTEM_PREFIXES"; then
                continue
            fi

            # 判断是否为缓存
            local src_clean="${source#./}"
            local is_cache=0
            if echo "$src_clean" | grep -qiE "$CACHE_PATTERNS"; then
                is_cache=1
            fi

            echo "${src_clean}|${is_cache}"
        fi
    done < "$file"
}

# 获取应用的备份目录选项
# 输出: "src|is_cache" 每行一个
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

# ──────────────────────────────────────────────
# 应用描述（从 compose 注释提取）
# ──────────────────────────────────────────────
get_description() {
    local name="$1"
    local compose_file
    if [[ "$name" == "dockge" ]]; then
        compose_file="${ROOT}/dockge/compose.yml"
    else
        compose_file="${ROOT}/stacks/${name}/compose.yml"
    fi

    if [[ -f "$compose_file" ]]; then
        # 提取第一个 ===== 包裹的注释标题
        grep -m1 -E '^[[:space:]]*#[[:space:]]*=+' "$compose_file" 2>/dev/null | \
            sed -E 's/^[[:space:]]*#[[:space:]]*=+[[:space:]]*//; s/[[:space:]]*=+[[:space:]]*$//' || true
    fi
}

# ──────────────────────────────────────────────
# 状态文件管理（保存选中状态，跨函数传递）
# ──────────────────────────────────────────────
STATE_DIR="${ROOT}/.cache/backup-tool"
state_file() { echo "${STATE_DIR}/${1}"; }

init_state() {
    rm -rf "$STATE_DIR"
    mkdir -p "$STATE_DIR"

    # 默认不选中任何目录，用户按 [a] 全选推荐 或按数字逐个选择
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
    # 切换：如果当前全部推荐都选中 -> 取消全部
    #        如果全部未选中 -> 全选推荐项
    #        否则 -> 全选推荐项
    local sel_count=0
    while IFS='|' read -r src _; do
        [[ -n "$src" ]] || continue
        is_selected "$name" "$src" && sel_count=$((sel_count + 1)) || true
    done < <(get_backup_dirs "$name")

    if [[ $sel_count -gt 0 ]]; then
        # 有选中 -> 取消全部
        :> "$(state_file "${name}")"
    else
        # 无选中 -> 全选推荐项
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

# ──────────────────────────────────────────────
# 显示复选框标记
# ──────────────────────────────────────────────
check_mark() {
    if [[ "$1" == "1" ]]; then
        echo -e "${GREEN}✔${NC}"
    else
        echo -e "${DIM}·${NC}"
    fi
}

# ──────────────────────────────────────────────
# 自定义某应用的目录选择
# ──────────────────────────────────────────────
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
            if is_selected "$name" "$d"; then
                checked="1"
            else
                checked="0"
            fi
            local marker
            marker="$(check_mark "$checked")"

            local tag=""
            [[ "$rec" == "0" ]] && tag=" ${DIM}(推荐)${NC}"

            # 检查路径是否存在
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

# ──────────────────────────────────────────────
# 交互式备份
# ──────────────────────────────────────────────
interactive_backup() {
    local auto_yes="${1:-0}"

    init_state

    # 构建应用名列表
    local app_names=()
    local app_names_with_dirs=()
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        app_names+=("$name")
        # 检查是否有备份目录
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

    # auto_yes: 全选推荐项，跳过 TUI，直接进入确认/备份流程
    if [[ "$auto_yes" == "1" ]]; then
        select_all_recommended
        if ! has_any_selected; then
            echo -e "${YELLOW}  没有推荐的可备份内容${NC}"
            return
        fi
    else

    # ── 辅助：渲染单个应用行（在光标当前位置输出，不移动光标） ──
    _rline() {
        local i="$1" name="$2" is_cursor="$3"
        local desc
        desc="$(get_description "$name")"
        [[ -n "$desc" ]] && desc=" — ${desc}"

        local checkbox
        if app_has_selection "$name"; then
            checkbox="${GREEN}[✓]${NC}"
        else
            checkbox="${DIM}[ ]${NC}"
        fi

        local check_str=""
        while IFS='|' read -r src is_cache; do
            [[ -n "$src" ]] || continue
            local sel=0
            is_selected "$name" "$src" && sel=1 || true
            local marker
            marker="$(check_mark "$sel")"
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

    # ── 辅助：跳到指定行，擦除该行，重绘 ──
    # header 占 4 行（第 1-4 行），第 1 个 app 在第 5 行
    _upd_line() {
        local i="$1"
        local name="${app_names_with_dirs[$i]}"
        local is_cur=0
        [[ $i -eq $cursor ]] && is_cur=1
        printf '\033[%d;0H\033[K' $((5 + i))
        _rline "$i" "$name" "$is_cur"
    }

    # ── 辅助：从指定行起擦除到底，重绘底部摘要 ──
    _upd_summary() {
        local count
        count="$(count_selected_apps)"
        local n=${#app_names_with_dirs[@]}
        printf '\033[%d;0H\033[J' $((5 + n))
        echo
        echo -e "  选中 ${GREEN}${count}${NC} 个应用"
        echo
        echo -e "  ${DIM}[↑↓/jk] 移动  [空格] 勾选/取消  [a] 全选/取消全选  [c] 自定义目录${NC}"
        echo -e "  ${DIM}[b/Enter] 开始备份  [q] 退出${NC}"
        printf '\033[?25l'  # 确保光标隐藏
    }

    # ── 首次全量绘制（隐藏终端光标） ──
    local cursor=0
    printf '\033[H\033[J'
    printf '\033[?25l'  # 清屏后立即隐藏光标（部分终端清屏会重置光标可见性）
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
                printf '\033[?25h'  # 恢复光标
                local n=${#app_names_with_dirs[@]}
                printf '\033[%d;0H\033[J' $((5 + n + 5))
                echo -e "${YELLOW}  已取消${NC}"
                return
                ;;
            $'\033[A'|k|K)  # 上箭头 / k
                if [[ $cursor -gt 0 ]]; then
                    local prev=$cursor
                    cursor=$((cursor - 1))
                    _upd_line "$prev"
                    _upd_line "$cursor"
                    printf '\033[%d;0H\033[?25l' $((5 + cursor))
                fi
                ;;
            $'\033[B'|j|J)  # 下箭头 / j
                local max=$(( ${#app_names_with_dirs[@]} - 1 ))
                if [[ $cursor -lt $max ]]; then
                    local prev=$cursor
                    cursor=$((cursor + 1))
                    _upd_line "$prev"
                    _upd_line "$cursor"
                    printf '\033[%d;0H\033[?25l' $((5 + cursor))
                fi
                ;;
            ' ')  # 空格切换
                toggle_app "${app_names_with_dirs[$cursor]}"
                _upd_line "$cursor"
                _upd_summary
                printf '\033[%d;0H\033[?25l' $((5 + cursor))
                ;;
            a|A)
                if has_any_selected; then
                    # 当前有选中 -> 取消全选
                    rm -rf "$STATE_DIR"
                    mkdir -p "$STATE_DIR"
                    while IFS= read -r name; do
                        [[ -n "$name" ]] || continue
                        touch "$(state_file "${name}")"
                    done < <(discover_apps)
                else
                    # 当前无选中 -> 全选推荐
                    rm -rf "$STATE_DIR"
                    mkdir -p "$STATE_DIR"
                    select_all_recommended
                fi
                for i in "${!app_names_with_dirs[@]}"; do
                    _upd_line "$i"
                done
                _upd_summary
                ;;
            c|C)
                printf '\033[?25h'  # 进入子菜单前恢复光标
                customize_app "${app_names_with_dirs[$cursor]}"
                # customize 内部会清屏，返回后全量重绘并重新隐藏光标
                printf '\033[H\033[J'
                printf '\033[?25l'
                header "📦 备份 — 选择要备份的内容"
                for i in "${!app_names_with_dirs[@]}"; do
                    local is_cur=0
                    [[ $i -eq $cursor ]] && is_cur=1
                    _rline "$i" "${app_names_with_dirs[$i]}" "$is_cur"
                done
                _upd_summary
                ;;
            ''|$'\r'|$'\n'|b|B)
                printf '\033[?25h'  # 恢复光标
                printf '\033[%d;0H\033[J' $((5 + ${#app_names_with_dirs[@]} + 5))
                break
                ;;
            *)  ;;  # 忽略未知按键（终端空闲时可能收到焦点/缩放等转义序列）
        esac
    done

    # 收集选中的备份项
    if ! has_any_selected; then
        echo -e "${YELLOW}  没有选中任何内容，已取消${NC}"
        return
    fi
fi  # 结束 else（auto_yes 模式 vs TUI）

# ── 共享：确认界面 + 备份执行 ──

    # 确认界面
    clear
    header "📦 备份确认"

    local total_dirs=0
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        while IFS= read -r d; do
            [[ -n "$d" ]] || continue
            local exists
            local src_dir
            if [[ "$name" == "dockge" ]]; then
                src_dir="${ROOT}/dockge/${d}"
            else
                src_dir="${ROOT}/stacks/${name}/${d}"
            fi
            if [[ -d "$src_dir" ]]; then
                exists="${GREEN}✓ 存在${NC}"
            else
                exists="${RED}✗ 不存在${NC}"
            fi
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
        # 最多取前 6 个应用名，超出用 _Nmore 表示
        if [[ ${#selected_apps[@]} -le 6 ]]; then
            app_suffix="_$(printf '%s_' "${selected_apps[@]}" | sed 's/_$//')"
        else
            app_suffix="_$(printf '%s_' "${selected_apps[@]:0:6}" | sed 's/_$//')_$(( ${#selected_apps[@]} - 6 ))more"
        fi
    fi

    # 备份目标
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    local default_dest="${BACKUP_ROOT}/${stamp}${app_suffix}"

    # 可选标签
    local label=""
    if [[ "$auto_yes" != "1" ]]; then
        echo
        echo -e "  ${DIM}可选: 为本次备份添加标签，方便还原时识别 (回车跳过)${NC}"
        echo -e "  ${DIM}示例: 升级jellyfin前 / 系统迁移 / 周常备份${NC}"
        read -r -p "  备份标签: " label
        if [[ -n "$label" ]]; then
            # 清理标签：替换文件名危险字符为 -，去首尾 -
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
    # 去掉用户可能输入的 .tar.gz 后缀，后面统一添加
    dest="${dest%.tar.gz}"

    if [[ "$auto_yes" != "1" ]]; then
        confirm "确认开始备份?" "Y" || { echo -e "\n${YELLOW}  已取消${NC}"; return; }
    fi

    # 执行备份 — 创建单个 tar.gz 归档
    local archive="${dest}.tar.gz"
    echo -e "\n  正在备份到 ${CYAN}${archive}${NC} ...\n"

    local backup_paths=()
    local skip_count=0
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        while IFS= read -r drel; do
            [[ -n "$drel" ]] || continue

            local app_rel
            if [[ "$name" == "dockge" ]]; then
                app_rel="dockge"
            else
                app_rel="stacks/${name}"
            fi
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
        local size
        size=$(du -h "$archive" 2>/dev/null | cut -f1)
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

# ──────────────────────────────────────────────
# 备份内容解析
# ──────────────────────────────────────────────

# 从备份中列出应用名（去重）
list_apps_in_backup() {
    local bp="$1"
    if [[ -n "${_TAR_CACHE:-}" ]]; then
        echo "$_TAR_CACHE" | grep -oP '(?:stacks|dockge)/[^/]+' | sed 's|^stacks/||' | sort -u || true
    else
        tar -tzf "$bp" 2>/dev/null | grep -oP '(?:stacks|dockge)/[^/]+' | sed 's|^stacks/||' | sort -u || true
    fi
}

# 获取备份大小（MB）
backup_size_mb() {
    local bp="$1"
    local total_size
    total_size=$(stat -c%s "$bp" 2>/dev/null || stat -f%z "$bp" 2>/dev/null || echo 0)
    echo "scale=1; $total_size / 1048576" | bc 2>/dev/null || echo "?"
}

# 从归档中获取某应用的路径列表
# 输出: "stacks/app/data" 每行一个（相对于 ROOT）
app_archive_paths() {
    local bp="$1" app="$2"
    if [[ -n "${_TAR_CACHE:-}" ]]; then
        echo "$_TAR_CACHE" | grep "^stacks/${app}/" | grep -o "stacks/${app}/[^/]\+" | sort -u || true
    else
        tar -tzf "$bp" 2>/dev/null | grep "^stacks/${app}/" | grep -o "stacks/${app}/[^/]\+" | sort -u || true
    fi
}

# ──────────────────────────────────────────────
# 交互式还原
# ──────────────────────────────────────────────
interactive_restore() {
    # 列出所有备份
    local backups=()
    if [[ -d "$BACKUP_ROOT" ]]; then
        while IFS= read -r -d '' f; do
            local bname
            bname="$(basename "$f")"
            # 跳过 migration 安全备份
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
        echo -e "  ${DIM}完成后重新运行: sudo ds-backup restore${NC}"
        echo
        press_enter
        return
    fi

    local selected_backup=""

    # 选择备份
    while true; do
        printf '\033[H\033[J'
        header "📥 还原 — 选择备份"

        for i in "${!backups[@]}"; do
            local b="${backups[$i]}"
            local bpath="${BACKUP_ROOT}/${b}"

            # 计算大小
            local size_mb
            size_mb="$(backup_size_mb "$bpath")"

            # 解析内容
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

    # 缓存 tar 列表，避免 TUI 渲染时反复读取大文件
    _TAR_CACHE=$(tar -tzf "$selected_backup" 2>/dev/null || true)

    # 解析备份中的应用
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

    # 选择要还原的应用（TUI：方向键+空格，与备份交互一致）
    local app_archive_counts=()
    for name in "${backup_apps[@]}"; do
        local ac
        ac=$(echo "$_TAR_CACHE" | grep "^stacks/${name}/" | grep -o "stacks/${name}/[^/]\+" | sort -u | wc -l)
        app_archive_counts+=("$ac")
    done
    local restore_selected=("${backup_apps[@]}")
    while true; do
        # ── TUI 渲染辅助 ──
        _rline() {
            local i="$1" name="$2" is_cursor="$3"
            local checked=false
            for s in "${restore_selected[@]}"; do
                [[ "$s" == "$name" ]] && checked=true && break
            done
            local marker
            if $checked; then
                marker="${GREEN}✔${NC}"
            else
                marker="${DIM}·${NC}"
            fi
            local ac="${app_archive_counts[$i]}"
            if [[ $is_cursor -eq 1 ]]; then
                printf "  ${YELLOW}▸${NC} %b ${BOLD}${WHITE}%-16s${NC} ${DIM}%d 个归档${NC}\n" \
                    "$marker" "$name" "$ac"
            else
                printf "    %b ${BOLD}%-16s${NC} ${DIM}%d 个归档${NC}\n" \
                    "$marker" "$name" "$ac"
            fi
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
        _toggle_app() {
            local name="$1"
            local new_selected=()
            local found=false
            for s in "${restore_selected[@]}"; do
                if [[ "$s" == "$name" ]]; then
                    found=true
                else
                    new_selected+=("$s")
                fi
            done
            if ! $found; then
                new_selected+=("$name")
            fi
            restore_selected=("${new_selected[@]}")
        }

        local cursor=0

        # 首次全量绘制
        printf '\033[H\033[J'
        printf '\033[?25l'
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
                    return
                    ;;
                $'\033[A'|k|K)
                    if [[ $cursor -gt 0 ]]; then
                        local prev=$cursor
                        cursor=$((cursor - 1))
                        _upd_line "$prev"
                        _upd_line "$cursor"
                        printf '\033[%d;0H\033[?25l' $((5 + cursor))
                    fi
                    ;;
                $'\033[B'|j|J)
                    local max=$(( ${#backup_apps[@]} - 1 ))
                    if [[ $cursor -lt $max ]]; then
                        local prev=$cursor
                        cursor=$((cursor + 1))
                        _upd_line "$prev"
                        _upd_line "$cursor"
                        printf '\033[%d;0H\033[?25l' $((5 + cursor))
                    fi
                    ;;
                ' ')
                    _toggle_app "${backup_apps[$cursor]}"
                    _upd_line "$cursor"
                    _upd_summary
                    printf '\033[%d;0H\033[?25l' $((5 + cursor))
                    ;;
                a|A)
                    if [[ ${#restore_selected[@]} -eq 0 ]]; then
                        restore_selected=("${backup_apps[@]}")
                    else
                        restore_selected=()
                    fi
                    for i in "${!backup_apps[@]}"; do
                        _upd_line "$i"
                    done
                    _upd_summary
                    ;;
                ''|$'\r'|$'\n'|r|R)
                    printf '\033[?25h'
                    printf '\033[%d;0H\033[J' $((5 + ${#backup_apps[@]} + 5))
                    break
                    ;;
                *)  ;;
            esac
        done

        # 未选择时重新进入 TUI
        if [[ ${#restore_selected[@]} -eq 0 ]]; then
            echo -e "${YELLOW}  未选择任何应用${NC}"
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

    # ── 还原前：迁移安全备份（目标目录已有内容时先备份，防止还原失败无法回滚）──
    local migration_backup_dir=""
    local has_existing=0

    for name in "${restore_selected[@]}"; do
        # 检查目标目录是否存在内容
        local target_dir="${ROOT}/stacks/${name}"
        [[ "$name" == "dockge" ]] && target_dir="${ROOT}/dockge"
        if [[ -d "$target_dir" ]] && [[ -n "$(ls -A "$target_dir" 2>/dev/null)" ]]; then
            has_existing=1
            break
        fi
    done

    if [[ $has_existing -eq 1 ]]; then
        echo
        section "迁移前安全备份"
        echo -e "  ${YELLOW}⚠${NC} 检测到目标目录已有内容"
        echo -e "  ${DIM}还原将覆盖现有文件，建议先创建安全备份以防万一${NC}"
        echo
        if confirm "创建迁移前安全备份?" "N"; then
            local pre_stamp
            pre_stamp="$(date +%Y%m%d-%H%M%S)"
            migration_backup_dir="${BACKUP_ROOT}/pre_restore_${pre_stamp}"
            mkdir -p "$migration_backup_dir"

            local pre_ok=0 pre_fail=0
            for name in "${restore_selected[@]}"; do
                while IFS= read -r dir_path; do
                        [[ -n "$dir_path" ]] || continue
                        if [[ -d "${ROOT}/${dir_path}" ]] && \
                           [[ -n "$(ls -A "${ROOT}/${dir_path}" 2>/dev/null)" ]]; then
                            local safe_fn
                            safe_fn="$(echo "$dir_path" | tr '/' '_')"
                            local pre_archive="${migration_backup_dir}/${safe_fn}.tar.gz"
                            printf "  ${BLUE}⏳${NC} 备份现有 ${CYAN}${dir_path}${NC} ... "
                            if tar -czf "$pre_archive" -C "$ROOT" "${dir_path}" 2>/dev/null; then
                                local pre_size
                                pre_size=$(du -h "$pre_archive" 2>/dev/null | cut -f1)
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

    # ── 还原前：停止受影响的容器 ──
    local has_compose=false
    command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1 && has_compose=true

    local stopped_apps=()
    if $has_compose; then
        echo
        section "停止容器"
        for name in "${restore_selected[@]}"; do
            local compose_dir
            if [[ "$name" == "dockge" ]]; then
                compose_dir="${ROOT}/dockge"
            else
                compose_dir="${ROOT}/stacks/${name}"
            fi
            if [[ -f "${compose_dir}/compose.yml" ]]; then
                # 检查是否有容器在运行
                local running
                running=$(cd "$compose_dir" && docker compose ps --status=running -q 2>/dev/null)
                if [[ -n "$running" ]]; then
                    printf "  ${BLUE}→${NC} 停止 ${BOLD}${name}${NC} ... "
                    if (cd "$compose_dir" && docker compose down 2>/dev/null); then
                        echo -e "${GREEN}✓${NC}"
                        stopped_apps+=("$name")
                    else
                        echo -e "${RED}✗${NC}"
                    fi
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
            echo -e "${GREEN}✓${NC}"
            ((success++)) || true
        else
            echo -e "${RED}✗${NC}"
            ((fail++)) || true
        fi
    done

    echo
    echo -e "  ${BOLD}解压完成${NC}: 成功 ${GREEN}${success}${NC}, 失败 ${RED}${fail}${NC}"

    # ── 还原后：重新启动容器 ──
    if $has_compose; then
        echo
        section "启动容器"
        for name in "${restore_selected[@]}"; do
            local compose_dir
            if [[ "$name" == "dockge" ]]; then
                compose_dir="${ROOT}/dockge"
            else
                compose_dir="${ROOT}/stacks/${name}"
            fi
            if [[ ! -f "${compose_dir}/compose.yml" ]]; then
                echo -e "  ${DIM}·${NC} ${name} ${DIM}(无 compose.yml，跳过)${NC}"
                continue
            fi
            printf "  ${BLUE}→${NC} 启动 ${BOLD}${name}${NC} ... "
            if timeout 60 docker compose -f "${compose_dir}/compose.yml" up -d 2>/dev/null; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
            fi
        done
    else
        echo -e "  ${DIM}compose 不可用，请手动启动服务${NC}"
    fi

    # 迁移安全备份提示
    if [[ -n "$migration_backup_dir" ]] && [[ -d "$migration_backup_dir" ]]; then
        echo
        echo -e "  ${DIM}💡 迁移前安全备份已保存到: ${CYAN}${migration_backup_dir}${NC}"
        echo -e "  ${DIM}   确认还原无误后可手动删除: rm -rf ${migration_backup_dir}${NC}"
    fi
}

# ──────────────────────────────────────────────
# 清理状态
# ──────────────────────────────────────────────
cleanup() {
    rm -rf "${ROOT}/.cache/backup-tool"
}
trap cleanup EXIT

# ──────────────────────────────────────────────
# 注册为全局命令
# ──────────────────────────────────────────────
CMD_NAME="ds-backup"

install_command() {
    local target="${SCRIPT_PATH}"
    local link_path=""

    echo
    echo -e "${BOLD}  安装 ${CMD_NAME} 全局命令${NC}"
    echo

    # 统一安装到 /usr/local/bin（sudo 也能找到）
    if [[ -d "/usr/local/bin" ]]; then
        if command -v sudo &>/dev/null; then
            echo -e "  ${DIM}使用 sudo 安装到 /usr/local/bin/${CMD_NAME} ...${NC}"
            if sudo ln -sf "$target" "/usr/local/bin/${CMD_NAME}" 2>/dev/null && \
               sudo chmod +x "/usr/local/bin/${CMD_NAME}" 2>/dev/null; then
                echo
                echo -e "  ${GREEN}✓${NC} 已安装: ${BOLD}/usr/local/bin/${CMD_NAME}${NC}"
                echo
                echo -e "  备份/还原请用: ${BOLD}sudo ${CMD_NAME} backup|restore${NC}"
                return 0
            else
                echo -e "  ${RED}sudo 执行失败，请手动运行:${NC}"
                echo -e "    ${BOLD}sudo ln -sf \"$target\" /usr/local/bin/${CMD_NAME}${NC}"
            fi
        else
            echo -e "  ${YELLOW}未找到 sudo，请手动执行:${NC}"
            echo -e "    ${BOLD}ln -sf \"$target\" /usr/local/bin/${CMD_NAME}${NC}"
        fi
    else
        echo -e "  ${RED}/usr/local/bin 目录不存在${NC}"
    fi

    # 兜底
    echo -e "  ${RED}无法自动安装，请手动执行:${NC}"
    echo
    echo -e "    ${BOLD}sudo ln -sf \"$target\" /usr/local/bin/${CMD_NAME}${NC}"
    return 1
}

uninstall_command() {
    echo
    echo -e "${BOLD}  卸载 ${CMD_NAME} 全局命令${NC}"
    echo

    local removed=0
    for dir in "/usr/local/bin" "${HOME}/.local/bin"; do
        local link="${dir}/${CMD_NAME}"
        if [[ -L "$link" ]]; then
            echo -e "  ${BLUE}→${NC} 删除 ${link}"
            rm -f "$link" 2>/dev/null || sudo rm -f "$link" 2>/dev/null || true
            ((removed++)) || true
        fi
    done

    if [[ $removed -eq 0 ]]; then
        echo -e "  ${YELLOW}未找到已安装的 ${CMD_NAME}${NC}"
    else
        echo
        echo -e "  ${GREEN}✓${NC} 已卸载"
    fi
    echo
    echo -e "  ${DIM}本地使用方式: bash ${SCRIPT_PATH}${NC}"
}

# ──────────────────────────────────────────────
# 主入口
# ──────────────────────────────────────────────
main() {
    # ── 权限检查：备份/还原需要 root，不然部分文件读不了 ──
    local _arg1="${1:-}"
    local _all_args="${*:-}"
    if [[ $EUID -ne 0 ]] && [[ "$_arg1" != "--install" ]] && [[ "$_arg1" != "-i" ]] && \
       [[ "$_arg1" != "--uninstall" ]] && [[ "$_arg1" != "--help" ]] && [[ "$_arg1" != "-h" ]]; then
        echo -e "\n${RED}✗${NC} 备份/还原需 root 权限（部分文件属主非当前用户）"
        echo -e "  ${BOLD}请用: sudo $(basename "$0") ${_all_args}${NC}\n"
        exit 1
    fi

    if [[ $# -eq 0 ]]; then
        # 无参数：交互式主菜单
        while true; do
            printf '\033[H\033[J'
            header "docker-stacks 备份 / 还原工具"

            # 检查是否已安装为全局命令
            local installed=""
            if command -v "$CMD_NAME" &>/dev/null; then
                installed="  ${DIM}(已注册全局命令: ${CMD_NAME})${NC}"
            fi

            local apps=()
            while IFS= read -r name; do
                [[ -n "$name" ]] || continue
                apps+=("$name")
            done < <(discover_apps)

            echo -e "  发现 ${BOLD}${#apps[@]}${NC} 个应用:"
            for name in "${apps[@]}"; do
                local desc
                desc="$(get_description "$name")"
                [[ -n "$desc" ]] && desc=" — ${desc}"
                local ndirs=0
                while IFS='|' read -r _ _; do
                    ((ndirs++)) || true
                done < <(get_backup_dirs "$name")
                printf "    ${CYAN}%-16s${NC} ${DIM}%d 个可备份目录${NC}%s\n" "$name" "$ndirs" "$desc"
            done

            echo
            echo -e "  [${BOLD}1${NC}] 📦 备份"
            echo -e "  [${BOLD}2${NC}] 📥 还原"
            echo -e "  [${BOLD}i${NC}] 📌 安装为全局命令 (${CMD_NAME})"
            echo -e "  [${BOLD}q${NC}] 退出$installed"
            echo
            read -r -p "  > " cmd

            case "$cmd" in
                q|Q)
                    echo -e "\n${DIM}  再见!${NC}"
                    break
                    ;;
                1) interactive_backup; press_enter ;;
                2) interactive_restore; press_enter ;;
                i|I) install_command; press_enter ;;
            esac
        done

    elif [[ "$1" == "--install" ]] || [[ "$1" == "-i" ]]; then
        install_command

    elif [[ "$1" == "--uninstall" ]]; then
        uninstall_command

    elif [[ "$1" == "backup" ]]; then
        shift
        local auto_yes=0
        if [[ "${1:-}" == "-y" ]] || [[ "${1:-}" == "--yes" ]]; then
            auto_yes=1
            shift
        fi
        interactive_backup "$auto_yes"

    elif [[ "$1" == "restore" ]]; then
        interactive_restore

    elif [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        sed -n '/^# 用法:/,/^# 环境变量:/p' "$0" | sed '$d'
        echo
        echo "可备份的应用:"
        discover_apps | while read -r name; do echo "  $name"; done

    else
        echo -e "${YELLOW}未知参数: $*${NC}" >&2
        echo "用法: $(basename "$0") [backup|restore|--install|--help]" >&2
        exit 1
    fi
}

main "$@"
