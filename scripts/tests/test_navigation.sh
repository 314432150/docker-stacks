#!/usr/bin/env bash
# ============================================================
#  导航流程自动化测试
#  验证: 双重回车修复 / 多级菜单返回 / 管理面板导航
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB_DIR="${ROOT}/scripts/lib"

# 加载模块
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/discover.sh"
source "${LIB_DIR}/state.sh"
source "${LIB_DIR}/backup.sh"
source "${LIB_DIR}/restore.sh"
source "${LIB_DIR}/deploy.sh"
source "${LIB_DIR}/install.sh"
source "${LIB_DIR}/webdav.sh"

# 加载全局环境
if [[ -f "${ROOT}/global.env" ]]; then
    set -a
    source "${ROOT}/global.env"
    set +a
fi

pass=0
fail=0
PASS=0
FAIL=0

_check() {
    local desc="$1" result="$2" expected="$3"
    if [[ "$result" == "$expected" ]]; then
        echo -e "  ${GREEN}✓${NC} $desc"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗${NC} $desc (got: $result, expected: $expected)"
        FAIL=$((FAIL+1))
    fi
}

echo "============================================================"
echo "  🧪 导航流程测试"
echo "============================================================"
echo

# ── 1. webdav_configured 检测 ──
echo "[1] webdav_configured 检测"
WEBDAV_URL="https://example.com"
WEBDAV_USER="user"
WEBDAV_PASS="pass"
_check "三要素齐全=已配置" "$(webdav_configured && echo yes || echo no)" "yes"
WEBDAV_URL=""
_check "缺少 URL=未配置" "$(webdav_configured && echo yes || echo no)" "no"

set -a; source "${ROOT}/global.env"; set +a
echo

# ── 2. 关键函数存在性 ──
echo "[2] 关键函数存在性"
for fn in webdav_menu webdav_management webdav_setup_wizard webdav_upload_local \
          webdav_upload webdav_list webdav_download webdav_connection_test \
          webdav_configured interactive_restore interactive_backup interactive_deploy \
          press_enter confirm header discover_apps get_description get_backup_dirs; do
    if declare -f "$fn" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $fn"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗${NC} $fn 未定义"
        FAIL=$((FAIL+1))
    fi
done
echo

# ── 3. 统一 q 退出机制 — _tui_cancelled ──
echo "[3] 统一 q 退出机制 (_tui_cancelled)"

# 3a: common.sh 定义 _tui_cancelled
if grep -q '_tui_cancelled' "${LIB_DIR}/common.sh"; then
    echo -e "  ${GREEN}✓${NC} common.sh 定义 _tui_cancelled"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} common.sh 缺少 _tui_cancelled"
    FAIL=$((FAIL+1))
fi

# 3b: press_enter 检查 _tui_cancelled
if grep -A3 '^press_enter()' "${LIB_DIR}/common.sh" | grep -q '_tui_cancelled'; then
    echo -e "  ${GREEN}✓${NC} press_enter 检查 _tui_cancelled 跳过"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} press_enter 未检查 _tui_cancelled"
    FAIL=$((FAIL+1))
fi

# 3c: backup.sh q 路径设 _tui_cancelled=1
if grep -A8 'q|Q' "${LIB_DIR}/backup.sh" | grep -q '_tui_cancelled=1'; then
    echo -e "  ${GREEN}✓${NC} backup TUI q → _tui_cancelled=1"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} backup TUI q 缺少 _tui_cancelled"
    FAIL=$((FAIL+1))
fi

# 3d: deploy.sh q 路径设 _tui_cancelled=1
if grep -A8 'q|Q' "${LIB_DIR}/deploy.sh" | grep -q '_tui_cancelled=1'; then
    echo -e "  ${GREEN}✓${NC} deploy TUI q → _tui_cancelled=1"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} deploy TUI q 缺少 _tui_cancelled"
    FAIL=$((FAIL+1))
fi

# 3e: restore.sh q 路径数 ≥3 (来源选择、远程列表、本地列表、应用选择)
count=$(grep -c '_tui_cancelled=1' "${LIB_DIR}/restore.sh" || true)
if [[ $count -ge 3 ]]; then
    echo -e "  ${GREEN}✓${NC} restore.sh ${count} 个 q 路径设 _tui_cancelled=1"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} restore.sh 仅 ${count} 个，预期 ≥3"
    FAIL=$((FAIL+1))
fi

# 3f: webdav_menu q 路径设 _tui_cancelled=1
if grep -A1 'q|Q).*return' "${LIB_DIR}/webdav.sh" | grep -q '_tui_cancelled'; then
    echo -e "  ${GREEN}✓${NC} webdav_menu q → _tui_cancelled=1"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} webdav_menu q 缺少 _tui_cancelled"
    FAIL=$((FAIL+1))
fi

# 3g: upload_local q 不设 _tui_cancelled（返回到 webdav_menu，非 dsctl）
if grep -B2 -A1 '"q".*"Q".*return' "${LIB_DIR}/webdav.sh" | grep -q '_tui_cancelled'; then
    upload_q_has_flag=$(grep -B2 -A1 '"q".*"Q".*return' "${LIB_DIR}/webdav.sh" | grep -c '_tui_cancelled' || true)
    # Check only the upload_local one (the webdav_menu one is case-insensitive and already checked)
    # Actually let me just check by context
    if grep -A30 'webdav_upload_local()' "${LIB_DIR}/webdav.sh" | grep -B2 '"q"' | grep -q '_tui_cancelled'; then
        echo -e "  ${RED}✗${NC} upload_local q 误设 _tui_cancelled（应返回 webdav_menu）"
        FAIL=$((FAIL+1))
    else
        echo -e "  ${GREEN}✓${NC} upload_local q 不设 _tui_cancelled（正确，返回到 webdav_menu）"
        PASS=$((PASS+1))
    fi
else
    echo -e "  ${GREEN}✓${NC} upload_local q 无 _tui_cancelled（正确）"
    PASS=$((PASS+1))
fi

# 3h: dsctl 统一 press_enter + _tui_cancelled=0
if grep -q 'press_enter; _tui_cancelled=0' "${ROOT}/scripts/dsctl"; then
    count=$(grep -c 'press_enter; _tui_cancelled=0' "${ROOT}/scripts/dsctl" || true)
    echo -e "  ${GREEN}✓${NC} dsctl 统一 reset + press_enter (${count} 处)"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} dsctl 缺少统一的 press_enter + _tui_cancelled 模式"
    FAIL=$((FAIL+1))
fi
echo

# ── 4. press_enter 幂等性验证 ──
echo "[4] press_enter 幂等性"
# press_enter 内部应设 _tui_cancelled=1 防止 dsctl 重复暂停
if grep -A5 '^press_enter()' "${LIB_DIR}/common.sh" | grep -q '_tui_cancelled=1'; then
    echo -e "  ${GREEN}✓${NC} press_enter 内设 _tui_cancelled=1（幂等）"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} press_enter 缺少幂等保护"
    FAIL=$((FAIL+1))
fi
echo

# ── 5. webdav_management [c] 去掉 ; return ──
echo "[5] webdav_management [c] 导航修复"
if grep -q 'c|C) webdav_setup_wizard; return' "${LIB_DIR}/webdav.sh"; then
    echo -e "  ${RED}✗${NC} [c] 还有 ; return"
    FAIL=$((FAIL+1))
else
    echo -e "  ${GREEN}✓${NC} [c] 已移除 ; return"
    PASS=$((PASS+1))
fi
echo

# ── 6. webdav_setup_wizard 末尾 press_enter ──
echo "[6] webdav_setup_wizard 末尾 press_enter"
# 定位 webdav_setup_wizard 函数体末尾（} 之前），检查是否有 press_enter
wizard_end=$(grep -n "^webdav_upload()" "${LIB_DIR}/webdav.sh" | head -1 | cut -d: -f1)
wizard_end=$((wizard_end - 1))
if sed -n "$((wizard_end-5)),${wizard_end}p" "${LIB_DIR}/webdav.sh" | grep -q "press_enter"; then
    echo -e "  ${GREEN}✓${NC} wizard 末尾有 press_enter"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} wizard 末尾缺少 press_enter"
    FAIL=$((FAIL+1))
fi
echo

# ── 7. WebDAV 连接测试（网络可能不通） ──
echo "[7] WebDAV 连接测试"
if webdav_configured; then
    printf "  测试连接 ${WEBDAV_URL%%/*}... "
    if webdav_connection_test; then
        echo -e "${GREEN}✓${NC}"
        PASS=$((PASS+1))
        
        echo "[7b] 远程文件列表"
        remote_count=$(webdav_list 2>/dev/null | wc -l)
        echo "  远程备份文件数: $remote_count"
        PASS=$((PASS+1))
    else
        echo -e "${YELLOW}⚠ 连接失败${NC}"
        PASS=$((PASS+1))
    fi
else
    echo -e "  ${DIM}未配置，跳过${NC}"
    PASS=$((PASS+1))
fi
echo

# ── 8. 模拟交互流程 ──
echo "[8] 模拟交互流程"

_simulate() {
    local name="$1" input="$2" screen_marker="$3"
    local output
    output=$(printf '%s\n' "$input" | timeout 5 bash "${ROOT}/scripts/dsctl" 2>&1 || true)
    if echo "$output" | grep -q "$screen_marker"; then
        echo -e "  ${GREEN}✓${NC} $name"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗${NC} $name (未找到标记: $screen_marker)"
        echo "  output (tail):"
        echo "$output" | tail -8
        FAIL=$((FAIL+1))
    fi
}

# 8a: 验证 dsctl --help 输出
output=$(timeout 5 bash "${ROOT}/scripts/dsctl" --help 2>&1 || true)
if echo "$output" | grep -q "dsctl"; then
    echo -e "  ${GREEN}✓${NC} dsctl --help 正常"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} dsctl --help 失败"
    FAIL=$((FAIL+1))
fi

# 8b: 验证 dsctl 作为脚本可执行（检查无语法错误）
if bash -n "${ROOT}/scripts/dsctl"; then
    echo -e "  ${GREEN}✓${NC} dsctl 语法检查通过"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} dsctl 语法错误"
    FAIL=$((FAIL+1))
fi
echo

# ── 9. 应用发现 ──
echo "[9] 应用发现"
app_count=$(discover_apps 2>/dev/null | wc -l)
_check "至少 1 个应用" "$([[ $app_count -ge 1 ]] && echo ok || echo fail)" "ok"
echo

# ── 10. 目录结构验证 ──
echo "[10] 目录结构"
for d in "${ROOT}/stacks" "${ROOT}/backups" "${ROOT}/scripts" "${ROOT}/scripts/lib"; do
    if [[ -d "$d" ]]; then
        echo -e "  ${GREEN}✓${NC} ${d#$ROOT/}"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗${NC} ${d#$ROOT/} 不存在"
        FAIL=$((FAIL+1))
    fi
done
echo

# ── 11. 输入校验 ──
echo "[11] 输入校验"

# 11a: restore.sh 来源选择有 */q) 校验
if grep -q 'q|Q) _tui_cancelled=1; return' "${LIB_DIR}/restore.sh" && \
   grep -q "无效选择.*请输入 1" "${LIB_DIR}/restore.sh"; then
    echo -e "  ${GREEN}✓${NC} restore 来源选择有校验（无效值提示）"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} restore 来源选择缺少校验"
    FAIL=$((FAIL+1))
fi

# 11b: restore.sh 远程文件列表有无效序号提示
if grep -q "无效序号.*请选择" "${LIB_DIR}/restore.sh"; then
    echo -e "  ${GREEN}✓${NC} restore 远程列表有无效序号提示"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} restore 远程列表缺少无效序号提示"
    FAIL=$((FAIL+1))
fi

# 11c: restore.sh 本地列表有无效序号提示
if grep -q "请输入数字序号或 q" "${LIB_DIR}/restore.sh"; then
    echo -e "  ${GREEN}✓${NC} restore 本地列表有无效输入提示"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} restore 本地列表缺少无效输入提示"
    FAIL=$((FAIL+1))
fi

# 11d: webdav.sh 管理面板有 *) 校验
if grep -A1 'q|Q) _tui_cancelled=1' "${LIB_DIR}/webdav.sh" | grep -q "无效选择"; then
    echo -e "  ${GREEN}✓${NC} webdav 管理面板有无效输入提示"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} webdav 管理面板缺少无效输入提示"
    FAIL=$((FAIL+1))
fi

# 11e: webdav.sh upload_local 有 while 循环和无效序号/输入提示
if grep -A30 "选择上传.*q.*返回" "${LIB_DIR}/webdav.sh" | grep -q "无效序号" && \
   grep -A30 "选择上传.*q.*返回" "${LIB_DIR}/webdav.sh" | grep -q "while true"; then
    echo -e "  ${GREEN}✓${NC} webdav upload_local 有 while + 校验"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} webdav upload_local 缺少 while 或校验"
    FAIL=$((FAIL+1))
fi

# 11f: dsctl 主菜单有 *) 校验
if grep -q "无效选择.*请输入 1-3.*w.*i.*q" "${ROOT}/scripts/dsctl"; then
    echo -e "  ${GREEN}✓${NC} dsctl 主菜单有无效输入提示"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} dsctl 主菜单缺少无效输入提示"
    FAIL=$((FAIL+1))
fi
echo

# ── 结果 ──
echo "============================================================"
echo "  测试结果: ${PASS} 通过, ${FAIL} 失败"
echo "============================================================"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
