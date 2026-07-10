# ============================================================
#  lib/webdav.sh — 远程 WebDAV 备份上传 / 下载 / 列表
# ============================================================
#
# 依赖: curl, python3（列表解析）；curl 上传/下载无需 python
# 配置: 在 global.env 中设置 WEBDAV_URL / WEBDAV_USER / WEBDAV_PASS
#

# ── 检查 WebDAV 是否已配置 ──
webdav_configured() {
    [[ -n "${WEBDAV_URL:-}" ]] && [[ -n "${WEBDAV_USER:-}" ]] && [[ -n "${WEBDAV_PASS:-}" ]]
}

# ── WebDAV 连接测试 ──
webdav_connection_test() {
    local url="${WEBDAV_URL%/}"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        -X PROPFIND -H "Depth: 0" "$url/" 2>/dev/null)
    [[ "$http_code" == "207" ]] && return 0
    [[ "$http_code" == "200" ]] && return 0
    return 1
}

# ── WebDAV 管理入口 ──
webdav_menu() {
    if webdav_configured; then
        webdav_management
    else
        webdav_setup_wizard
    fi
}

# ── 已配置时的管理面板 ──
webdav_management() {
    while true; do
        printf '\033[H\033[2J'
        header "🔧 WebDAV 远程备份"

        echo -e "  ${DIM}当前配置:${NC}"
        echo -e "  ${DIM}  地址:   ${CYAN}${WEBDAV_URL}${NC}"
        echo -e "  ${DIM}  用户名: ${CYAN}${WEBDAV_USER}${NC}"
        echo -e "  ${DIM}  密码:   ${CYAN}****${NC}"
        echo

        echo -e "  [${BOLD}c${NC}] 修改配置"
        echo -e "  [${BOLD}u${NC}] 上传本地备份到 WebDAV"
        echo -e "  [${BOLD}q${NC}] 返回"
        echo
        read -r -p "  > " cmd

        case "$cmd" in
            c|C) webdav_setup_wizard ;;
            u|U) webdav_upload_local ;;
            q|Q) _tui_cancelled=1; return ;;
            *) echo -e "\n  ${RED}无效选择，请输入 c、u 或 q${NC}"; sleep 1 ;;
        esac
    done
}

# ── 从本地备份列表中选择文件上传到 WebDAV ──
webdav_upload_local() {
    printf '\033[H\033[2J'
    header "📤 上传本地备份到 WebDAV"

    local files=()
    while IFS= read -r f; do
        files+=("$f")
    done < <(ls -1t "${BACKUP_ROOT}"/*.tar.gz 2>/dev/null || true)

    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}没有找到本地备份文件${NC}"
        echo
        press_enter
        return
    fi

    for i in "${!files[@]}"; do
        local f="${files[$i]}"
        local name size
        name="$(basename "$f")"
        size="$(du -h "$f" 2>/dev/null | cut -f1)"
        printf "  [%d] ${CYAN}%s${NC}  ${DIM}%s${NC}\n" "$((i+1))" "$name" "$size"
    done

    echo
    echo -e "  ${DIM}命令: [数字]选择上传  [q]返回${NC}"
    while true; do
        read -r -p "  > " cmd

        if [[ "$cmd" == "q" || "$cmd" == "Q" ]]; then
            return
        elif [[ "$cmd" =~ ^[0-9]+$ ]]; then
            local idx=$((cmd - 1))
            if [[ $idx -ge 0 ]] && [[ $idx -lt ${#files[@]} ]]; then
                local f="${files[$idx]}"
                local remote_name
                remote_name="$(basename "$f")"
                echo
                printf "  ${BLUE}⏳${NC} 正在上传 ${CYAN}%s${NC} ... " "$remote_name"
                if webdav_upload "$f" "$remote_name"; then
                    echo -e "${GREEN}✓${NC}"
                    echo -e "  远程位置: ${CYAN}${WEBDAV_URL%/}/${remote_name}${NC}"
                else
                    echo -e "${RED}✗ 上传失败${NC}"
                fi
                echo
                press_enter
                return
            else
                echo -e "  ${RED}无效序号，请选择 1-${#files[@]}，或 q 返回${NC}"
            fi
        else
            echo -e "  ${RED}无效输入，请输入数字序号，或 q 返回${NC}"
        fi
    done
}

# ── 交互式 WebDAV 配置向导 ──
webdav_setup_wizard() {
    printf '\033[H\033[2J'
    header "🔧 配置 WebDAV 远程备份"

    local had_config
    had_config="false"
    if webdav_configured; then
        had_config="true"
        echo -e "  ${DIM}当前配置:${NC}"
        echo -e "  ${DIM}  地址:   ${CYAN}${WEBDAV_URL}${NC}"
        echo -e "  ${DIM}  用户名: ${CYAN}${WEBDAV_USER}${NC}"
        echo -e "  ${DIM}  密码:   ${CYAN}****${NC}"
        echo
    fi

    echo -e "  ${DIM}支持任何标准 WebDAV 服务（坚果云、Nextcloud、群晖等）${NC}"
    echo

    echo -e "  ${BOLD}坚果云 配置示例:${NC}"
    echo -e "  ${DIM}    1. 登录坚果云 → 账户信息 → 安全选项 → 第三方应用管理${NC}"
    echo -e "  ${DIM}    2. 添加应用，生成专用密码${NC}"
    echo -e "  ${DIM}    3. 在坚果云中创建目录（如 docker-stacks），填入下方地址${NC}"
    printf  "  ${DIM}%14s: %s${NC}\n" "地址" "https://dav.jianguoyun.com/dav/docker-stacks"
    echo

    echo -e "  ${DIM}留空保留当前值，输入 - 清除${NC}"
    echo

    local new_url new_user new_pass
    if [[ -z "${WEBDAV_URL:-}" ]]; then
        printf "  ${DIM}(留空默认: https://dav.jianguoyun.com/dav/docker-stacks)${NC}\n"
    fi
    printf "  %14s: " "URL";  read -r -e -i "${WEBDAV_URL:-}" new_url
    printf "  %14s: " "User"; read -r -e -i "${WEBDAV_USER:-}" new_user
    if [[ -n "${WEBDAV_PASS:-}" ]]; then
        printf "  %14s: ${DIM}(已设置)${NC} " "Pass"; read -r new_pass
    else
        printf "  %14s: " "Pass"; read -r new_pass
    fi

    [[ "$new_url" == "-" ]] && new_url=""
    [[ "$new_user" == "-" ]] && new_user=""
    [[ "$new_pass" == "-" ]] && new_pass=""

    # 首次配置时，地址留空则使用坚果云示例默认地址
    if [[ -z "$new_url" ]] && ! webdav_configured; then
        new_url="https://dav.jianguoyun.com/dav/docker-stacks"
    fi

    # 密码已设置时，留空保留原密码
    if [[ -z "$new_pass" ]] && [[ "$had_config" == "true" ]]; then
        new_pass="$WEBDAV_PASS"
    fi

    local env_file="${ROOT}/global.env"
    if grep -q "^WEBDAV_URL=" "$env_file" 2>/dev/null; then
        sed -i "s|^WEBDAV_URL=.*|WEBDAV_URL=${new_url}|" "$env_file"
    else
        echo "WEBDAV_URL=${new_url}" >> "$env_file"
    fi
    if grep -q "^WEBDAV_USER=" "$env_file" 2>/dev/null; then
        sed -i "s|^WEBDAV_USER=.*|WEBDAV_USER=${new_user}|" "$env_file"
    else
        echo "WEBDAV_USER=${new_user}" >> "$env_file"
    fi
    if grep -q "^WEBDAV_PASS=" "$env_file" 2>/dev/null; then
        sed -i "s|^WEBDAV_PASS=.*|WEBDAV_PASS=${new_pass}|" "$env_file"
    else
        echo "WEBDAV_PASS=${new_pass}" >> "$env_file"
    fi

    # 重新加载
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a

    echo

    if webdav_configured; then
        printf "  ${BLUE}⏳${NC} 测试 WebDAV 连接 ... "
        if webdav_connection_test; then
            echo -e "${GREEN}✓ 连接成功${NC}"
        else
            echo -e "${YELLOW}⚠ 连接失败${NC}"
            echo -e "  ${DIM}请检查地址、用户名和密码是否正确；稍后可在主菜单重新配置${NC}"
        fi
    else
        echo -e "  ${YELLOW}WebDAV 已禁用（所有配置已清除）${NC}"
    fi
    echo
    press_enter
}

# ── 上传文件到 WebDAV ──
webdav_upload() {
    local local_file="$1"
    local remote_name="${2:-$(basename "$local_file")}"
    local url="${WEBDAV_URL%/}/${remote_name}"

    local http_code
    # -# 进度条输出到 stderr（终端可见），-w 输出 http_code 到 stdout（$() 捕获）
    http_code=$(curl -# -o /dev/null -w "%{http_code}" --max-time 600 \
        -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        -T "$local_file" "$url")

    if [[ "$http_code" == "201" ]] || [[ "$http_code" == "204" ]]; then
        return 0
    else
        echo "  HTTP ${http_code}" >&2
        return 1
    fi
}

# ── 列出 WebDAV 上以 .tar.gz 结尾的备份文件 ──
webdav_list() {
    local url="${WEBDAV_URL%/}"
    local xml

    xml=$(curl -s --max-time 30 \
        -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        -X PROPFIND -H "Depth: 1" "$url/" 2>/dev/null)

    if [[ -z "$xml" ]]; then
        return 1
    fi

    if command -v python3 &>/dev/null; then
        echo "$xml" | python3 -c "
import sys, re
from urllib.parse import unquote
text = sys.stdin.read()
for m in re.finditer(r'<[^>]*href[^>]*>([^<]+)</[^>]*href[^>]*>', text, re.I):
    name = unquote(m.group(1).rstrip('/').split('/')[-1])
    if name and not name.startswith('.') and name.endswith('.tar.gz'):
        print(name)
" 2>/dev/null
    else
        echo "$xml" | grep -oP '<[^>]*href[^>]*>\K[^<]+(?=</[^>]*href[^>]*>)' 2>/dev/null | \
        while read -r href; do
            local name
            name="$(basename "${href%/}")"
            [[ "$name" == *.tar.gz ]] && echo "$name"
        done
    fi
}

# ── 从 WebDAV 下载文件 ──
webdav_download() {
    local remote_file="$1"
    local local_path="$2"
    local url="${WEBDAV_URL%/}/${remote_file}"

    local http_code
    http_code=$(curl -s -o "$local_path" -w "%{http_code}" --max-time 600 \
        -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        "$url" 2>/dev/null)

    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "201" ]]; then
        return 0
    else
        echo "  HTTP ${http_code}" >&2
        return 1
    fi
}

# ── 查询 WebDAV 文件大小（字节） ──
webdav_file_size() {
    local remote_file="$1"
    local url="${WEBDAV_URL%/}/${remote_file}"

    curl -sI --max-time 15 \
        -u "${WEBDAV_USER}:${WEBDAV_PASS}" "$url" 2>/dev/null | \
        grep -i 'content-length' | awk '{print $2}' | tr -d '\r'
}
