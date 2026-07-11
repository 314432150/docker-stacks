#!/usr/bin/env bash
# ============================================================
#  _helpers.sh — 测试公共工具函数（供各模块 source）
# 定义: 断言函数、清理函数、ROOT/ENGINE 路径
# 注意: PASS/FAIL 由主入口 test_engine.sh 初始化
# ============================================================

# ── 路径解析 ──
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENGINE="${ROOT}/service/engine/cmd/entry.sh"

# ── 断言函数 ──

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
    if echo "$json" | grep -q "\"${key}\":"; then
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

# ── 清理函数 ──
_cleanup() {
    rm -f "${ROOT}/.cache/engine.lock" 2>/dev/null || true
    rm -f /tmp/docker-stacks-engine/engine.lock 2>/dev/null || true
    rm -f "${ROOT}/backups"/2026*openclaw* "${ROOT}/backups"/_test_* 2>/dev/null || true
    rm -rf "${ROOT}/backups"/pre_restore_* 2>/dev/null || true
}
