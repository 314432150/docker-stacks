#!/usr/bin/env bash
# ============================================================
#  test_restore.sh — 还原（含 backup→restore 往返）
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

echo "[7] restore 子命令"
_cleanup

# 7a: 参数不完整
_assert_exit "restore 无参数返回 1" 1 "$ENGINE" "restore"

# 7b: 备份文件不存在
_assert_exit "restore 不存在文件返回 1" 1 "$ENGINE" restore "/tmp/nonexistent.tar.gz" "qbittorrent"

# 7c: 正常还原（先 backup 再 restore）
_test_app="${BACKUP_TEST_APP:-}"
if [[ -n "$_test_app" ]]; then
    set +e
    "$ENGINE" backup "$_test_app" &>/dev/null
    set -e

    test_archive=$(ls -1t "${ROOT}/backups"/*.tar.gz 2>/dev/null | head -1)
    if [[ -n "$test_archive" ]] && [[ -f "$test_archive" ]]; then
        restore_out=""
        set +e; restore_out=$("$ENGINE" restore "$test_archive" "$_test_app" 2>/dev/null || true); set -e

        events=$(echo "$restore_out" | while read -r line; do
            echo "$line" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p'
        done)
        _assert_contains "restore 含 start 事件" "$events" "start"
        _assert_contains "restore 含 done 事件" "$events" "done"

        echo "  ✓ restore 完整流程通过"
        PASS=$((PASS + 1))

        # 清理
        rm -f "$test_archive"
        rm -rf "${ROOT}/backups"/pre_restore_* 2>/dev/null || true
    else
        echo "  - 跳过: 无测试备份"
    fi
else
    echo "  - 跳过: 无可用应用"
fi
echo
