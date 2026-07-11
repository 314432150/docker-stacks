#!/usr/bin/env bash
# ============================================================
#  test_lock.sh — 任务锁互斥
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

echo "[9] 任务锁互斥"
_cleanup

_lock_test_app="${BACKUP_TEST_APP:-openclaw}"
if "$ENGINE" discover 2>/dev/null | grep -q "\"name\":\"$_lock_test_app\""; then
    # 使用与 engine 相同的锁路径
    lock_file="${ROOT}/.cache/engine.lock"
    if [[ ! -w "${ROOT}/.cache" ]]; then
        lock_file="/tmp/docker-stacks-engine/engine.lock"
    fi
    mkdir -p "$(dirname "$lock_file")" 2>/dev/null || true
    rm -f "$lock_file"
    echo "99999 test_lock" > "$lock_file"

    lock_out=""
    lock_exit=0
    set +e; lock_out=$("$ENGINE" backup "$_lock_test_app" 2>/dev/null); lock_exit=$?; set -e
    _assert_eq "锁冲突时 backup 返回 2" "$lock_exit" "2"
    _assert_contains "锁冲突输出 busy 事件" "$lock_out" "busy"

    rm -f "$lock_file"
else
    echo "  - 跳过: 无可用应用"
fi
echo
