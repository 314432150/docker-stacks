# ============================================================
#  lib/common.sh — 终端颜色、工具函数、常量定义
# ============================================================

# ── 终端颜色（检测 tty） ──
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    BOLD='\033[1m';    DIM='\033[2m'
    RED='\033[91m';    GREEN='\033[92m'
    YELLOW='\033[93m'; BLUE='\033[94m'
    CYAN='\033[96m';   WHITE='\033[97m'
    NC='\033[0m'
else
    BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; WHITE=''; NC=''
fi

# ── 缓存目录关键词（匹配到则不推荐默认勾选） ──
CACHE_PATTERNS='cache|tmp|temp|transcodes|metadata'

# ── 外部挂载前缀（不参与备份） ──
SYSTEM_PREFIXES='^\$|^/etc/|^/dev/|^/proc/|^/sys/|^/run/|^/var/run/|^~|^\.\.'

# ── 输出工具函数 ──
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
            if [[ -z "$yn" ]] || [[ "$yn" =~ ^[Yy] ]]; then return 0
            elif [[ "$yn" =~ ^[Nn] ]]; then return 1; fi
        else
            echo -en "  ${YELLOW}${prompt} [y/N]: ${NC}"
            read -r yn
            if [[ "$yn" =~ ^[Yy] ]]; then return 0
            elif [[ -z "$yn" ]] || [[ "$yn" =~ ^[Nn] ]]; then return 1; fi
        fi
    done
}

press_enter() {
    echo -en "  ${DIM}按回车继续...${NC}"
    read -r
}

check_mark() {
    if [[ "$1" == "1" ]]; then
        echo -e "${GREEN}✔${NC}"
    else
        echo -e "${DIM}·${NC}"
    fi
}
