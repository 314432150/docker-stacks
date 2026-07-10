#!/usr/bin/env bash
# ============================================================
#  test_engine.sh — Engine 集成测试主编排器
# ============================================================
# 运行:   bash scripts/tests/test_engine.sh
# 要求:   在项目根目录执行
# 结构:
#   主入口 (当前文件) → 初始化 PASS/FAIL，按序加载各子测试模块
#   _helpers.sh       → 公共断言/清理函数
#   test_syntax.sh    → 语法检查 + 可执行权限
#   test_cli.sh       → 入口参数 + 路径解析
#   test_discover.sh  → 应用发现
#   test_backup.sh    → 备份 (--keep/--upload)
#   test_restore.sh   → 还原
#   test_deploy.sh    → 部署
#   test_lock.sh      → 任务锁互斥
#   test_lib.sh       → lib 函数完整性
#   test_webdav.sh    → WebDAV 集成
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

# 初始化全局计数器（子模块通过 _assert_* 系列函数共享）
PASS=0
FAIL=0

echo "============================================================"
echo "  Engine 集成测试"
echo "============================================================"
echo

# 按依赖顺序加载测试模块
source "${SCRIPT_DIR}/test_syntax.sh"
source "${SCRIPT_DIR}/test_cli.sh"
source "${SCRIPT_DIR}/test_discover.sh"
source "${SCRIPT_DIR}/test_backup.sh"
source "${SCRIPT_DIR}/test_restore.sh"
source "${SCRIPT_DIR}/test_deploy.sh"
source "${SCRIPT_DIR}/test_lock.sh"
source "${SCRIPT_DIR}/test_lib.sh"
source "${SCRIPT_DIR}/test_webdav.sh"

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
