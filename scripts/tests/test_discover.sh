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

# 验证 apps 是数组+数据结构完整
apps_check=$(echo "$out" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert d['type'] == 'apps'
assert 'engine' in d, 'missing engine block'
assert 'privilege' in d['engine'], 'missing privilege'
assert isinstance(d['apps'], list)
for app in d['apps']:
    assert 'name' in app
    assert 'description' in app
    assert 'dirs' in app
    assert isinstance(app['dirs'], list)
    for dr in app['dirs']:
        assert 'path' in dr
        assert 'recommended' in dr
        assert 'exists' in dr
print('OK')
" 2>/dev/null || echo "FAIL")
_assert_eq "discover 数据结构完整" "$apps_check" "OK"

# 至少有 1 个应用
app_count=$(echo "$out" | python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())['apps']))" 2>/dev/null || echo 0)
_assert_eq "discover 发现至少 1 个应用" "$([[ $app_count -ge 1 ]] && echo ok || echo fail)" "ok"

# 权限级别在 {root,user} 中
priv=$(echo "$out" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['engine']['privilege'])" 2>/dev/null)
_assert_eq "discover privilege 在合法集合" "$([[ $priv =~ ^(root|user)$ ]] && echo ok || echo fail)" "ok"
echo
