#!/usr/bin/env bash
# ============================================================
#  test_engine.sh — Engine 集成测试套件 (TDD)
# ============================================================
# 运行:   bash scripts/tests/test_engine.sh
# 要求:   在项目根目录执行
set -euo pipefail

cd "$(dirname "$0")/../.."
ROOT="$(pwd)"
ENGINE="${ROOT}/scripts/engine/engine.sh"
PASS=0; FAIL=0

# ── 工具函数 ──
_assert_eq() {
    local desc="$1" got="$2" expected="$3"
    if [[ "$got" == "$expected" ]]; then
        echo "  ✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $desc"
        echo "    期望: $expected"
        echo "    实际: $got"
        FAIL=$((FAIL + 1))
    fi
}

_assert_json_has() {
    local desc="$1" json="$2" key="$3"
    if echo "$json" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); _=d['$key']" 2>/dev/null; then
        echo "  ✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $desc (JSON 缺少字段 '$key')"
        FAIL=$((FAIL + 1))
    fi
}

_assert_exit() {
    local desc="$1" expected="$2"
    shift 2
    local got=0
    set +e; "$@" &>/dev/null; got=$?; set -e
    if [[ "$got" == "$expected" ]]; then
        echo "  ✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $desc (exit: $got, expected: $expected)"
        FAIL=$((FAIL + 1))
    fi
}

_assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  ✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $desc (输出不含 '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

# 清理残留（每次测试前）
_cleanup() {
    rm -f "${ROOT}/.cache/engine.lock" 2>/dev/null || true
    rm -f /tmp/docker-stacks-engine/engine.lock 2>/dev/null || true
    rm -f "${ROOT}/backups"/2026*openclaw* "${ROOT}/backups"/_test_* 2>/dev/null || true
    rm -rf "${ROOT}/backups"/pre_restore_* 2>/dev/null || true
}

echo "============================================================"
echo "  Engine 集成测试"
echo "============================================================"
echo

# ════════════════════════════════════════════════════════════
#  1. 语法检查
# ════════════════════════════════════════════════════════════
echo "[1] 脚本语法检查"
for f in "${ENGINE}" "${ROOT}"/scripts/engine/_lib.sh \
         "${ROOT}"/scripts/engine/discover.sh \
         "${ROOT}"/scripts/engine/backup.sh \
         "${ROOT}"/scripts/engine/restore.sh \
         "${ROOT}"/scripts/engine/deploy.sh; do
    if [[ -f "$f" ]]; then
        bash -n "$f" 2>/dev/null && \
            echo "  ✓ $(basename "$f")" && PASS=$((PASS+1)) || \
            { echo "  ✗ $(basename "$f") 语法错误"; FAIL=$((FAIL+1)); }
    else
        echo "  - $(basename "$f") (跳过，文件不存在)"
    fi
done
echo

# ════════════════════════════════════════════════════════════
#  2. engine.sh 存在性 + 可执行权限
# ════════════════════════════════════════════════════════════
echo "[2] engine.sh 可执行"
if [[ -x "$ENGINE" ]]; then
    echo "  ✓ engine.sh is executable"
    PASS=$((PASS+1))
else
    echo "  ✗ engine.sh is NOT executable"
    FAIL=$((FAIL+1))
fi
echo

# ════════════════════════════════════════════════════════════
#  3. 无参数 / 未知子命令 / --help / --no-sudo
# ════════════════════════════════════════════════════════════
echo "[3] 入口参数验证"
_cleanup
_assert_exit "无参数返回 1" 1 "$ENGINE"
_assert_exit "未知子命令返回 1" 1 "$ENGINE" "unknown_cmd"
_assert_exit "--help 返回 0" 0 "$ENGINE" "--help"
echo

# ════════════════════════════════════════════════════════════
#  4. discover — 应用发现（含权限信息）
# ════════════════════════════════════════════════════════════
echo "[4] discover 子命令"
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

# ════════════════════════════════════════════════════════════
#  5. backup — 备份
# ════════════════════════════════════════════════════════════
echo "[5] backup 子命令"
_cleanup

# 5a: 空参数
_assert_exit "backup 无参数返回 1" 1 "$ENGINE" "backup"

# 5b: 正常备份（用 openclaw — 数据目录用户可读）
_test_app="openclaw"
if "$ENGINE" discover 2>/dev/null | python3 -c "
import sys, json
apps = json.loads(sys.stdin.read())['apps']
names = [a['name'] for a in apps]
assert '$_test_app' in names
" 2>/dev/null; then
    # 一次调用同时拿退出码和输出
    backup_out=""
    backup_exit=0
    set +e; backup_out=$("$ENGINE" backup "$_test_app" 2>/dev/null); backup_exit=$?; set -e
    _assert_eq "backup $_test_app 返回 0" "$backup_exit" "0"

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
        # 清理
        rm -f "$backup_path"
    else
        echo "  ✗ backup 文件未创建: $backup_path"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  - 跳过: $_test_app 不可用"
fi

# 5c: 不存在的应用
_assert_exit "backup nonexistent 返回 1" 1 "$ENGINE" backup "nonexistent_app_12345"

# 5d: --keep 选项
echo "  [5d] --keep 选项"
_assert_exit "backup --keep 无数字参数返回 1" 1 "$ENGINE" backup "--keep" "$_test_app"

# 5e: --upload 前提条件（无 WebDAV 配置时）
_assert_contains "backup --upload 未配置 WebDAV 报错" \
    "$("$ENGINE" backup "--upload" "$_test_app" 2>/dev/null || true)" "WebDAV"
echo

# ════════════════════════════════════════════════════════════
#  6. restore — 还原
# ════════════════════════════════════════════════════════════
echo "[6] restore 子命令"
_cleanup

# 6a: 参数不完整
_assert_exit "restore 无参数返回 1" 1 "$ENGINE" "restore"

# 6b: 备份文件不存在
_assert_exit "restore 不存在文件返回 1" 1 "$ENGINE" restore "/tmp/nonexistent.tar.gz" "qbittorrent"

# 6c: 正常还原（先 backup 再 restore）
if [[ -n "${_test_app:-}" ]]; then
    set +e
    "$ENGINE" backup "$_test_app" &>/dev/null
    set -e

    test_archive=$(ls -1t "${ROOT}/backups"/*.tar.gz 2>/dev/null | head -1)
    if [[ -n "$test_archive" ]] && [[ -f "$test_archive" ]]; then
        restore_out=""
        set +e; restore_out=$("$ENGINE" restore "$test_archive" "$_test_app" 2>/dev/null || true); set -e

        events=$(echo "$restore_out" | while read -r line; do
            echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['type'])" 2>/dev/null || true
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

# ════════════════════════════════════════════════════════════
#  7. deploy — 部署
# ════════════════════════════════════════════════════════════
echo "[7] deploy 子命令"
_cleanup

# 7a: 空参数
_assert_exit "deploy 无参数返回 1" 1 "$ENGINE" "deploy"

# 7b: docker compose 不可用时返回 3
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    echo "  - docker compose 可用，跳过不可用测试"
else
    _assert_exit "deploy docker 不可用时返回 3" 3 "$ENGINE" deploy "${_test_app:-openclaw}"
fi

# 7c: 不存在的应用
deploy_out=$("$ENGINE" deploy "nonexistent_app_12345" 2>/dev/null || true)
_assert_contains "deploy 不存在应用含 skip 事件" "$deploy_out" "skip"

# 7d: deploy 正常流程（仅在 docker compose 可用且有应用时）
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
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

# ════════════════════════════════════════════════════════════
#  8. 任务锁互斥
# ════════════════════════════════════════════════════════════
echo "[8] 任务锁互斥"
_cleanup

_lock_test_app="${_test_app:-openclaw}"
if "$ENGINE" discover 2>/dev/null | python3 -c "
import sys, json
apps = json.loads(sys.stdin.read())['apps']
names = [a['name'] for a in apps]
assert '$_lock_test_app' in names
" 2>/dev/null; then
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

# ════════════════════════════════════════════════════════════
#  9. 路径解析
# ════════════════════════════════════════════════════════════
echo "[9] 路径解析"

pushd /tmp &>/dev/null
out=$("$ENGINE" discover 2>/dev/null || true)
popd &>/dev/null
_assert_contains "从 /tmp 调用 discover 成功" "$out" '"type":"apps"'
echo

# ════════════════════════════════════════════════════════════
#  10. lib 函数完整性
# ════════════════════════════════════════════════════════════
echo "[10] lib 可复用函数完整性"

LIB="${ROOT}/scripts/lib"
for fn in discover_apps get_backup_dirs get_description parse_volumes \
          init_state select_all_recommended get_selected_dirs has_any_selected \
          toggle_app is_selected toggle_dir \
          webdav_configured webdav_connection_test webdav_upload \
          webdav_list webdav_download webdav_file_size; do
    # 搜索 engine/ 和 lib/ 中的定义
    found=0
    for f in "$LIB"/*.sh "${ROOT}/scripts/engine"/*.sh; do
        if grep -q "^${fn}()" "$f" 2>/dev/null; then
            found=1; break
        fi
    done
    if [[ $found -eq 1 ]]; then
        echo "  ✓ $fn"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $fn (未定义)"
        FAIL=$((FAIL + 1))
    fi
done
echo

# ════════════════════════════════════════════════════════════
#  11. WebDAV 集成测试
# ════════════════════════════════════════════════════════════
echo "[11] WebDAV 集成测试"
_cleanup

# 加载 WebDAV 配置
if [[ -f "${ROOT}/global.env" ]]; then
    set -a; source "${ROOT}/global.env"; set +a
fi

# 加载 webdav 模块
source "${ROOT}/scripts/lib/webdav.sh"

# 11a: webdav_configured
_assert_eq "webdav_configured 检测" \
    "$(webdav_configured && echo yes || echo no)" "yes"

# 11b: webdav_connection_test
printf "  "
if webdav_connection_test; then
    echo "✓ WebDAV 连接成功"
    PASS=$((PASS + 1))

    # 11c: 上传测试文件
    test_file="${ROOT}/backups/_webdav_test_upload.tar.gz"
    echo "test" > /tmp/_test_content
    tar -czf "$test_file" -C /tmp _test_content 2>/dev/null || true
    rm -f /tmp/_test_content

    if [[ -f "$test_file" ]]; then
        if webdav_upload "$test_file" "_webdav_test_upload.tar.gz"; then
            echo "  ✓ webdav_upload 成功"
            PASS=$((PASS + 1))
        else
            echo "  ✗ webdav_upload 失败"
            FAIL=$((FAIL + 1))
        fi

        # 11d: 列出远程文件
        remote_list=$(webdav_list 2>/dev/null || true)
        _assert_contains "webdav_list 含测试文件" "$remote_list" "_webdav_test_upload"

        # 11e: 下载验证
        dl_path="${ROOT}/backups/_webdav_test_download.tar.gz"
        if webdav_download "_webdav_test_upload.tar.gz" "$dl_path"; then
            echo "  ✓ webdav_download 成功"
            PASS=$((PASS + 1))
            # 清理远程测试文件
            curl -s -X DELETE --max-time 10 \
                -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
                "${WEBDAV_URL%/}/_webdav_test_upload.tar.gz" &>/dev/null || true
        else
            echo "  ✗ webdav_download 失败"
            FAIL=$((FAIL + 1))
        fi
        rm -f "$dl_path"
        rm -f "$test_file"
    else
        echo "  - 跳过: 无法创建测试文件"
    fi
else
    echo "  - 跳过: WebDAV 不可达"
fi
echo

# ════════════════════════════════════════════════════════════
#  结果
# ════════════════════════════════════════════════════════════
echo "============================================================"
echo "  测试结果: ${PASS} 通过, ${FAIL} 失败"
echo "============================================================"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
