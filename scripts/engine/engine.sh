#!/usr/bin/env bash
# ============================================================
#  engine/engine.sh — 核心引擎入口
# ============================================================
# 职责: 路径解析 → 加载配置/lib → 路由分发 → 调用 cmd_*
# 输出: 子命令 stdout 输出 JSONL 事件流，日志走 stderr
# 用法: ./engine.sh {discover|backup|restore|deploy} [...]
# ============================================================
set -euo pipefail

# ── 路径解析（支持软链接 + 任意工作目录调用） ──
_resolve_self() {
    local src="${BASH_SOURCE[0]}"
    if command -v realpath &>/dev/null; then
        realpath "$src"
    elif command -v readlink &>/dev/null && readlink -f "$src" &>/dev/null 2>&1; then
        readlink -f "$src"
    else
        local d; d="$(cd "$(dirname "$src")" && pwd)"
        while [[ -L "$src" ]]; do
            src="$(readlink "$src")"
            [[ "$src" != /* ]] && src="$d/$src"
            d="$(cd "$(dirname "$src")" && pwd)"
        done
        echo "$(cd "$d" && pwd)/$(basename "$src")"
    fi
}

SELF="$(_resolve_self)"
ROOT="$(cd "$(dirname "$SELF")/../.." && pwd)"       # /srv/docker-stacks
ENGINE_DIR="$(dirname "$SELF")"                       # .../scripts/engine
LIB_DIR="${ROOT}/scripts/lib"
BACKUP_ROOT="${BACKUP_ROOT:-${ROOT}/backups}"

# ── 加载全局配置 ──
if [[ -f "${ROOT}/global.env" ]]; then
    set -a; source "${ROOT}/global.env"; set +a
fi

# ── 加载 lib 纯工具库 ──
source "$LIB_DIR/common.sh"
source "$LIB_DIR/discover.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/webdav.sh"

# ── 加载 engine 模块（按依赖顺序） ──
source "$ENGINE_DIR/_lib.sh"
source "$ENGINE_DIR/discover.sh"
source "$ENGINE_DIR/backup.sh"
source "$ENGINE_DIR/restore.sh"
source "$ENGINE_DIR/deploy.sh"

# ── 路由 + 主入口 ──
_main() {
    local cmd=""
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cmd="--help"
                break ;;
            *)
                if [[ -z "$cmd" ]]; then
                    cmd="$1"
                else
                    args+=("$1")
                fi
                shift ;;
        esac
    done

    _emit_startup_info

    case "$cmd" in
        discover)  cmd_discover ;;
        backup)    cmd_backup "${args[@]}" ;;
        restore)   cmd_restore "${args[@]}" ;;
        deploy)    cmd_deploy "${args[@]}" ;;
        "")
            _emit '{"type":"error","msg":"未指定子命令，用法: engine.sh {discover|backup|restore|deploy} [...]"}'
            return 1 ;;
        --help)
            echo "用法: engine.sh {discover|backup|restore|deploy} [参数...]"
            echo ""
            echo "子命令:"
            echo "  discover              扫描所有应用，输出 JSON 列表（含权限级别）"
            echo "  backup <app...>       备份指定应用 → JSONL 事件流"
            echo "  restore <archive> <app...>  从备份还原指定应用"
            echo "  deploy <app...>       部署指定应用（docker compose up）"
            echo ""
            echo "所有命令输出 JSONL 事件流到 stdout，日志到 stderr"
            echo "退出码: 0=成功, 1=参数错误, 2=锁冲突, 3=前置条件不满足"
            ;;
        *)  _emit "{\"type\":\"error\",\"msg\":\"未知子命令: ${cmd}\"}"; return 1 ;;
    esac
}

_main "$@"
