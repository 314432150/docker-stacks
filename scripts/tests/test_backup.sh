#!/usr/bin/env bash
# ============================================================
#  test_backup.sh — 备份（含 --keep、--upload）
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

echo "[6] backup 子命令"
_cleanup

# 6a: 空参数
_assert_exit "backup 无参数返回 1" 1 "$ENGINE" "backup"

# 6b: 正常备份
BACKUP_TEST_APP="openclaw"
if "$ENGINE" discover 2>/dev/null | python3 -c "
import sys, json
apps = json.loads(sys.stdin.read())['apps']
names = [a['name'] for a in apps]
assert '$BACKUP_TEST_APP' in names
" 2>/dev/null; then
    backup_out=""
    backup_exit=0
    set +e; backup_out=$("$ENGINE" backup "$BACKUP_TEST_APP" 2>/dev/null); backup_exit=$?; set -e
    _assert_eq "backup $BACKUP_TEST_APP 返回 0" "$backup_exit" "0"

    # 验证 JSONL 事件类型
    events=$(echo "$backup_out" | while read -r line; do
        echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['type'])" 2>/dev/null
    done)
    _assert_contains "backup 含 start 事件" "$events" "start"
    _assert_contains "backup 含 done 事件" "$events" "done"

    # 验证备份文件已创建
    done_line=$(echo "$backup_out" | grep '"type":"done"' | head -1 || true)
    backup_path=$(echo "$done_line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('path',''))" 2>/dev/null || true)
    if [[ -f "$backup_path" ]]; then
        echo "  ✓ backup 文件已创建: $(basename "$backup_path")"
        PASS=$((PASS + 1))
        rm -f "$backup_path"
    else
        echo "  ✗ backup 文件未创建: $backup_path"
        FAIL=$((FAIL + 1))
    fi
else
    BACKUP_TEST_APP=""
    echo "  - 跳过: openclaw 不可用"
fi

# 6c: 不存在的应用
_assert_exit "backup nonexistent 返回 1" 1 "$ENGINE" backup "nonexistent_app_12345"

# 6d: --keep 选项
echo "  [6d] --keep 选项"
_assert_exit "backup --keep 无数字参数返回 1" 1 "$ENGINE" backup "--keep" "${BACKUP_TEST_APP:-openclaw}"

# 6e: --upload 前提条件（无 WebDAV 配置时）
echo "  [6e] --upload 无 WebDAV 配置"
_assert_contains "backup --upload 未配置 WebDAV 报错" \
    "$("$ENGINE" backup "--upload" "${BACKUP_TEST_APP:-openclaw}" 2>/dev/null || true)" "WebDAV"

# 导出测试应用名供其他模块使用（restore 需要）
export BACKUP_TEST_APP
echo
