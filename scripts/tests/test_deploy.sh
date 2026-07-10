#!/usr/bin/env bash
# ============================================================
#  test_deploy.sh — 部署
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

echo "[8] deploy 子命令"
_cleanup

# 8a: 空参数
_assert_exit "deploy 无参数返回 1" 1 "$ENGINE" "deploy"

# 8b: docker compose 不可用时返回 3
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    echo "  - docker compose 可用，跳过不可用测试"
else
    _assert_exit "deploy docker 不可用时返回 3" 3 "$ENGINE" deploy "${BACKUP_TEST_APP:-openclaw}"
fi

# 8c: 不存在的应用
deploy_out=$("$ENGINE" deploy "nonexistent_app_12345" 2>/dev/null || true)
_assert_contains "deploy 不存在应用含 skip 事件" "$deploy_out" "skip"

# 8d: deploy 正常流程（仅在 docker compose 可用且有应用时）
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    _test_app="${BACKUP_TEST_APP:-openclaw}"
    deploy_out=""
    set +e; deploy_out=$("$ENGINE" deploy "$_test_app" 2>/dev/null); set -e
    deploy_events=$(echo "$deploy_out" | while read -r line; do
        echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['type'])" 2>/dev/null || true
    done)
    _assert_contains "deploy 含 start 事件" "$deploy_events" "start"
    _assert_contains "deploy 含 done 事件" "$deploy_events" "done"
else
    echo "  - 跳过 deploy 集成测试（无 docker compose）"
fi
echo
