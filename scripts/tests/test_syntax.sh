#!/usr/bin/env bash
# ============================================================
#  test_syntax.sh — 脚本语法检查 + 可执行权限
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

echo "[1] 脚本语法检查"
for f in "${ENGINE}" \
         "${ROOT}/scripts/engine/_lib.sh" \
         "${ROOT}/scripts/engine/discover.sh" \
         "${ROOT}/scripts/engine/backup.sh" \
         "${ROOT}/scripts/engine/restore.sh" \
         "${ROOT}/scripts/engine/deploy.sh"; do
    if [[ -f "$f" ]]; then
        if bash -n "$f" 2>/dev/null; then
            echo "  ✓ $(basename "$f")"
            PASS=$((PASS + 1))
        else
            echo "  ✗ $(basename "$f") 语法错误"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  - $(basename "$f") (跳过，文件不存在)"
    fi
done
echo

echo "[2] engine.sh 可执行"
if [[ -x "$ENGINE" ]]; then
    echo "  ✓ engine.sh is executable"
    PASS=$((PASS + 1))
else
    echo "  ✗ engine.sh is NOT executable"
    FAIL=$((FAIL + 1))
fi
echo
