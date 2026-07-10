# ============================================================
#  engine/deploy.sh — 部署指定应用
# ============================================================
# 依赖: lib/discover.sh, engine/_lib.sh

# ── 内部：确保 .env 符号链接 ──
_ensure_env_link() {
    local app="$1"
    local compose_dir="${ROOT}/stacks/${app}"
    local global_env="${ROOT}/global.env"

    if [[ ! -f "$global_env" ]]; then return 0; fi
    if [[ ! -d "$compose_dir" ]]; then return 0; fi

    local env_link="${compose_dir}/.env"
    if [[ ! -L "$env_link" ]] || [[ "$(readlink -f "$env_link" 2>/dev/null)" != "$global_env" ]]; then
        rm -f "$env_link"
        ln -sf "../../global.env" "$env_link" 2>/dev/null
        _emit "{\"type\":\"progress\",\"step\":\"${app} .env 已就绪\"}"
    fi
}

# ── 子命令入口 ──
cmd_deploy() {
    local apps=("$@")

    if [[ ${#apps[@]} -eq 0 ]]; then
        _emit '{"type":"error","msg":"未指定要部署的应用"}'
        return 1
    fi

    if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null 2>&1; then
        _emit '{"type":"error","msg":"docker compose 不可用"}'
        return 3
    fi

    _acquire_lock "deploy" || return 2
    trap _release_lock EXIT

    local apps_json="["
    for i in "${!apps[@]}"; do
        [[ $i -gt 0 ]] && apps_json+=","
        apps_json+="\"${apps[$i]}\""
    done
    apps_json+="]"

    _emit "{\"type\":\"start\",\"op\":\"deploy\",\"apps\":${apps_json}}"

    local success=0 fail=0
    for app in "${apps[@]}"; do
        local compose_dir="${ROOT}/stacks/${app}"

        # .env 链接
        _ensure_env_link "$app"

        if [[ ! -f "${compose_dir}/compose.yml" ]]; then
            _emit "{\"type\":\"skip\",\"app\":\"${app}\",\"reason\":\"无 compose.yml\"}"
            continue
        fi

        # 停止已运行的
        local running
        running=$(cd "$compose_dir" && docker compose ps --status=running -q 2>/dev/null)
        if [[ -n "$running" ]]; then
            _emit "{\"type\":\"progress\",\"step\":\"停止 ${app}\"}"
            cd "$compose_dir" && docker compose down 2>/dev/null || true
        fi

        # 启动
        _emit "{\"type\":\"progress\",\"step\":\"部署 ${app}\",\"current\":$((success + fail + 1)),\"total\":${#apps[@]}}"

        if (cd "$compose_dir" && docker compose up -d 2>/dev/null); then
            _emit "{\"type\":\"ok\",\"app\":\"${app}\"}"
            ((success++)) || true
        else
            _emit "{\"type\":\"error\",\"app\":\"${app}\",\"msg\":\"部署失败\"}"
            ((fail++)) || true
        fi
    done

    _emit "{\"type\":\"done\",\"success\":${success},\"fail\":${fail}}"
    return 0
}
