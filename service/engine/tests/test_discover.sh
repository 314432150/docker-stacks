#!/usr/bin/env bash
# ============================================================
#  test_discover.sh — 应用发现（含权限信息）
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

echo "[5] discover 子命令"
_cleanup

out=$("$ENGINE" discover 2>/dev/null || true)
_assert_exit "discover 返回 0" 0 "$ENGINE" "discover"
_assert_json_has "discover 输出含 type" "$out" "type"
_assert_json_has "discover 输出含 apps" "$out" "apps"
_assert_json_has "discover 输出含 engine" "$out" "engine"

# 验证数据结构完整（用 grep/sed 逐项校验，不依赖 python3）
apps_check="OK"
echo "$out" | grep -q '"type":"apps"'         || apps_check="FAIL"
echo "$out" | grep -q '"engine":'             || apps_check="FAIL"
echo "$out" | grep -q '"privilege":"\(root\|user\)"' || apps_check="FAIL"
echo "$out" | grep -q '"apps":\['             || apps_check="FAIL"
echo "$out" | grep -q '"name":"'              || apps_check="FAIL"
echo "$out" | grep -q '"description":"'       || apps_check="FAIL"
echo "$out" | grep -q '"dirs":\['             || apps_check="FAIL"
echo "$out" | grep -q '"path":"'              || apps_check="FAIL"
echo "$out" | grep -q '"recommended":'        || apps_check="FAIL"
echo "$out" | grep -q '"exists":'             || apps_check="FAIL"
_assert_eq "discover 数据结构完整" "$apps_check" "OK"

# 至少有 1 个应用
app_count=$(echo "$out" | grep -o '"name":"' | wc -l)
_assert_eq "discover 发现至少 1 个应用" "$([[ $app_count -ge 1 ]] && echo ok || echo fail)" "ok"

# 权限级别在 {root,user} 中
priv=$(echo "$out" | sed -n 's/.*"privilege":"\([^"]*\)".*/\1/p')
_assert_eq "discover privilege 在合法集合" "$([[ $priv =~ ^(root|user)$ ]] && echo ok || echo fail)" "ok"
echo
