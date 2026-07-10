# ============================================================
#  engine/_lib.sh — 引擎共享基础设施
# ============================================================
# 本模块仅定义引擎内部使用的工具函数，不包含 TUI。

# ── JSON 事件输出 ──
# 所有 emit 输出到 stdout，一行一个 JSON 对象
_emit() { echo "$1"; }

# ── 权限提升检测 ──
# 检测顺序: EUID==0 → 尝试 sudo -n → 均不可用则为空
# Web 调用者需确保运行用户有 sudo NOPASSWD 权限（详见 docs/DESIGN.md）
_SUDO=""
if [[ ${EUID:-0} -eq 0 ]]; then
    :  # 已是 root，_SUDO 保持空
elif command -v sudo &>/dev/null; then
    if sudo -n true 2>/dev/null; then
        _SUDO="sudo"
    fi
fi

# ── 特权操作快捷函数 ──
# tar 打包: 保留权限/所有者 → tar 内部直接读取即可保留
_sudo_tar_czf() {
    local archive="$1"; shift
    if [[ -n "$_SUDO" ]]; then
        $_SUDO tar -czf "$archive" "$@"
    else
        tar -czf "$archive" "$@"
    fi
}

# tar 解压: --same-owner 恢复文件原始所有者（需要 root 才能 chown）
_sudo_tar_xzf() {
    local archive="$1"; shift
    if [[ -n "$_SUDO" ]]; then
        $_SUDO tar --same-owner -xzf "$archive" "$@"
    else
        tar --same-owner -xzf "$archive" "$@" 2>/dev/null || tar -xzf "$archive" "$@"
    fi
}

# 列出 tar 内容（不需要特权，但如果归档含 root 文件可能读不到，用 sudo 保障）
_sudo_tar_tzf() {
    local archive="$1"; shift
    if [[ -n "$_SUDO" ]]; then
        $_SUDO tar -tzf "$archive" "$@"
    else
        tar -tzf "$archive" "$@"
    fi
}

# mkdir/rm/chown 等管理操作（锁文件、备份目录）
_sudo_mkdir() {
    if [[ -n "$_SUDO" ]]; then $_SUDO mkdir -p "$@"; else mkdir -p "$@"; fi
}

_sudo_rm() {
    if [[ -n "$_SUDO" ]]; then $_SUDO rm -f "$@"; else rm -f "$@"; fi
}

_sudo_chown() {
    if [[ -n "$_SUDO" ]]; then $_SUDO chown "$@"; else chown "$@" 2>/dev/null || true; fi
}

# ── 任务锁 ──
# 三级策略: .cache (sudo 可用) → .cache (本用户可写) → /tmp
_LOCK_DIR="${ROOT}/.cache"
if [[ -n "$_SUDO" ]]; then
    $_SUDO mkdir -p "$_LOCK_DIR" 2>/dev/null || _LOCK_DIR="/tmp/docker-stacks-engine"
elif [[ ! -w "$_LOCK_DIR" ]]; then
    if [[ ! -d "$_LOCK_DIR" ]]; then mkdir -p "$_LOCK_DIR" 2>/dev/null || true; fi
    if [[ ! -w "$_LOCK_DIR" ]]; then
        _LOCK_DIR="/tmp/docker-stacks-engine"
        mkdir -p "$_LOCK_DIR" 2>/dev/null || true
    fi
fi
LOCK_FILE="${_LOCK_DIR}/engine.lock"

_acquire_lock() {
    local op="$1"
    _sudo_mkdir "$(dirname "$LOCK_FILE")"

    # 检查锁文件是否存在（用 sudo 读，或直接读）
    local holder=""
    if [[ -n "$_SUDO" ]]; then
        holder="$($_SUDO cat "$LOCK_FILE" 2>/dev/null || true)"
    else
        holder="$(cat "$LOCK_FILE" 2>/dev/null || true)"
    fi

    if [[ -n "$holder" ]]; then
        _emit "{\"type\":\"busy\",\"msg\":\"已有任务运行中: ${holder}\"}"
        return 1
    fi

    # 写入 PID + 操作名
    if [[ -n "$_SUDO" ]]; then
        echo "$$ $op" | $_SUDO tee "$LOCK_FILE" >/dev/null 2>&1 || {
            _emit "{\"type\":\"error\",\"msg\":\"无法创建锁文件: ${LOCK_FILE}\"}"
            return 1
        }
    else
        echo "$$ $op" > "$LOCK_FILE" 2>/dev/null || {
            _emit "{\"type\":\"error\",\"msg\":\"无法创建锁文件: ${LOCK_FILE}\"}"
            return 1
        }
    fi
    return 0
}

_release_lock() {
    _sudo_rm "$LOCK_FILE"
}

# ── 启动时状态报告（stderr，不影响 JSONL 事件流） ──
_emit_startup_info() {
    local priv=""
    if [[ ${EUID:-0} -eq 0 ]]; then priv="root"
    elif [[ -n "$_SUDO" ]]; then priv="sudo(免密)"
    else priv="普通用户(无sudo)"
    fi
    echo "[engine] 启动 | 用户=$(whoami) | 权限=${priv} | 锁目录=${_LOCK_DIR}" >&2
}
