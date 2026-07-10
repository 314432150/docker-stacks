# ============================================================
#  engine/_lib.sh — 引擎共享基础设施
# ============================================================
# 本模块仅定义引擎内部使用的工具函数，不包含 TUI。

# ── JSON 事件输出 ──
# 所有 emit 输出到 stdout，一行一个 JSON 对象
_emit() { echo "$1"; }

# ── 任务锁 ──
# 优先用 ROOT/.cache，不可写时 fallback 到 /tmp
_LOCK_DIR="${ROOT}/.cache"
if [[ ! -w "$_LOCK_DIR" ]] && [[ ! -d "$_LOCK_DIR" ]]; then
    mkdir -p "$_LOCK_DIR" 2>/dev/null || true
fi
if [[ ! -w "$_LOCK_DIR" ]]; then
    _LOCK_DIR="/tmp/docker-stacks-engine"
    mkdir -p "$_LOCK_DIR" 2>/dev/null || true
fi
LOCK_FILE="${_LOCK_DIR}/engine.lock"

_acquire_lock() {
    local op="$1"
    mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true
    if [[ -f "$LOCK_FILE" ]]; then
        local holder; holder="$(cat "$LOCK_FILE" 2>/dev/null)"
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
    rm -f "$LOCK_FILE" 2>/dev/null || true
}
