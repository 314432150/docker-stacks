#!/usr/bin/env bash
# ============================================================
#  test_cli.sh — 入口参数验证 + 路径解析
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

echo "[3] 入口参数验证"
_cleanup
_assert_exit "无参数返回 1" 1 "$ENGINE"
_assert_exit "未知子命令返回 1" 1 "$ENGINE" "unknown_cmd"
_assert_exit "--help 返回 0" 0 "$ENGINE" "--help"
echo

echo "[4] 路径解析（任意目录调用）"
pushd /tmp &>/dev/null
out=$("$ENGINE" discover 2>/dev/null || true)
popd &>/dev/null
_assert_contains "从 /tmp 调用 discover 成功" "$out" '"type":"apps"'
echo
