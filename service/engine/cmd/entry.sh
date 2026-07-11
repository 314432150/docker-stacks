#!/usr/bin/env bash
# ============================================================
#  cmd/entry.sh — 引擎入口
# ============================================================
# 职责: 路径解析 → 加载配置/lib → 路由分发 → 调用 cmd_*
# 输出: 子命令 stdout 输出 JSONL 事件流，日志走 stderr
# 用法: ./entry.sh {discover|backup|restore|deploy} [...]
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
ROOT="$(cd "$(dirname "$SELF")/../../.." && pwd)"    # /srv/docker-stacks
ENGINE_DIR="$(dirname "$SELF")"                       # .../service/engine/cmd
LIB_DIR="$(cd "$(dirname "$SELF")/../lib" && pwd)"    # .../service/engine/lib
BACKUP_ROOT="${BACKUP_ROOT:-${ROOT}/instance/backups}"

# WebDAV 配置：优先使用环境变量（server spawn 时已传入），否则从 settings.json 读取
if [[ -z "${WEBDAV_URL:-}" ]]; then
    _json="${ROOT}/service/web/server/data/settings.json"
    if [[ -f "$_json" ]] && command -v python3 &>/dev/null; then
        eval "$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1])).get("webdav",{})
for k in ["url","user","pass"]:
    v = d.get(k,"")
    if v:
        print(f"export WEBDAV_{k.upper()}=\"{v}\"")
' "$_json")"
    fi
fi

# ── 加载 lib 纯工具库 ──
source "$LIB_DIR/common.sh"
source "$LIB_DIR/discover.sh"
source "$LIB_DIR/webdav.sh"

# ── 加载 cmd 模块（按依赖顺序） ──
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
            _emit '{"type":"error","msg":"未指定子命令，用法: entry.sh {discover|backup|restore|deploy} [...]"}'
            return 1 ;;
        --help)
            echo "用法: entry.sh {discover|backup|restore|deploy} [参数...]" >&2
            echo "" >&2
            echo "子命令:" >&2
            echo "  discover              扫描所有应用，输出 JSON 列表（含权限级别）" >&2
            echo "  backup [选项] <app...> 备份指定应用 → JSONL 事件流" >&2
            echo "    选项:" >&2
            echo "      --upload           备份后自动上传到 WebDAV（需配置 WEBDAV_*）" >&2
            echo "      --keep N           保留最近 N 个本地备份，删除更旧的" >&2
            echo "  restore <archive> <app...>  从备份还原指定应用" >&2
            echo "  deploy <app...>       部署指定应用（docker compose up）" >&2
            echo "" >&2
            echo "所有命令输出 JSONL 事件流到 stdout，日志到 stderr" >&2
            echo "退出码: 0=成功, 1=参数错误, 2=锁冲突, 3=前置条件不满足" >&2
            ;;
        *)  _emit "{\"type\":\"error\",\"msg\":\"未知子命令: ${cmd}\"}"; return 1 ;;
    esac
}

_main "$@"
