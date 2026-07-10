# ============================================================
#  engine/_lib.sh — 引擎共享基础设施
# ============================================================
# 本模块仅定义引擎内部使用的工具函数，不包含 TUI。
#
# 权限模型：
#   - 以 root 启动（EUID=0）→ 可操作任何文件，tar --same-owner 恢复权限
#   - 以普通用户启动 → 只能操作用户可读写的文件，root 属主文件会失败
#   建议：web 后端以 root 启动（sudo node server.js）保障完整备份能力

# ── JSON 事件输出 ──
# 所有 emit 输出到 stdout，一行一个 JSON 对象
_emit() { echo "$1"; }

# ── 任务锁 ──
# 优先 $ROOT/.cache，不可写则回退 /tmp
_LOCK_DIR="${ROOT}/.cache"
if [[ ! -w "$_LOCK_DIR" ]]; then
    mkdir -p "$_LOCK_DIR" 2>/dev/null || true
    if [[ ! -w "$_LOCK_DIR" ]]; then
        _LOCK_DIR="/tmp/docker-stacks-engine"
        mkdir -p "$_LOCK_DIR" 2>/dev/null || true
    fi
fi
LOCK_FILE="${_LOCK_DIR}/engine.lock"

_acquire_lock() {
    local op="$1"
    mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true

    local holder
    holder="$(cat "$LOCK_FILE" 2>/dev/null || true)"

    if [[ -n "$holder" ]]; then
        _emit "{\"type\":\"busy\",\"msg\":\"已有任务运行中: ${holder}\"}"
        return 1
    fi

    echo "$$ $op" > "$LOCK_FILE" 2>/dev/null || {
        _emit "{\"type\":\"error\",\"msg\":\"无法创建锁文件: ${LOCK_FILE}\"}"
        return 1
    }
    return 0
}

_release_lock() {
    rm -f "$LOCK_FILE"
}

# ── 启动时状态报告（stderr，不影响 JSONL 事件流） ──
_emit_startup_info() {
    local priv
    if [[ ${EUID:-0} -eq 0 ]]; then priv="root"
    else                               priv="user"
    fi
    echo "[engine] 启动 | 用户=$(whoami) | 权限=${priv} | 锁目录=${_LOCK_DIR}" >&2
}
