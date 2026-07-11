# ============================================================
#  lib/webdav.sh — 远程 WebDAV 备份上传 / 下载 / 列表
# ============================================================
#
# 依赖: curl, python3（列表解析）；curl 上传/下载无需 python
# 配置: 在 service/web/server/data/settings.json 中设置 WEBDAV_*
#

# ── 检查 WebDAV 是否已配置 ──
webdav_configured() {
    [[ -n "${WEBDAV_URL:-}" ]] && [[ -n "${WEBDAV_USER:-}" ]] && [[ -n "${WEBDAV_PASS:-}" ]]
}

# ── WebDAV 连接测试 ──
webdav_connection_test() {
    local url="${WEBDAV_URL%/}"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        -X PROPFIND -H "Depth: 0" "$url/" 2>/dev/null)
    [[ "$http_code" == "207" ]] && return 0
    [[ "$http_code" == "200" ]] && return 0
    return 1
}

# ── 上传文件到 WebDAV ──
webdav_upload() {
    local local_file="$1"
    local remote_name="${2:-$(basename "$local_file")}"
    local url="${WEBDAV_URL%/}/${remote_name}"

    local http_code
    # -# 进度条输出到 stderr（终端可见），-w 输出 http_code 到 stdout（$() 捕获）
    http_code=$(curl -# -o /dev/null -w "%{http_code}" --max-time 600 \
        -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        -T "$local_file" "$url")

    if [[ "$http_code" == "201" ]] || [[ "$http_code" == "204" ]]; then
        return 0
    else
        echo "  HTTP ${http_code}" >&2
        return 1
    fi
}

# ── 列出 WebDAV 上以 .tar.gz 结尾的备份文件 ──
webdav_list() {
    local url="${WEBDAV_URL%/}"
    local xml

    xml=$(curl -s --max-time 30 \
        -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        -X PROPFIND -H "Depth: 1" "$url/" 2>/dev/null)

    if [[ -z "$xml" ]]; then
        return 1
    fi

    if command -v python3 &>/dev/null; then
        echo "$xml" | python3 -c "
import sys, re
from urllib.parse import unquote
text = sys.stdin.read()
for m in re.finditer(r'<[^>]*href[^>]*>([^<]+)</[^>]*href[^>]*>', text, re.I):
    name = unquote(m.group(1).rstrip('/').split('/')[-1])
    if name and not name.startswith('.') and name.endswith('.tar.gz'):
        print(name)
" 2>/dev/null
    else
        echo "$xml" | grep -oP '<[^>]*href[^>]*>\K[^<]+(?=</[^>]*href[^>]*>)' 2>/dev/null | \
        while read -r href; do
            local name
            name="$(basename "${href%/}")"
            [[ "$name" == *.tar.gz ]] && echo "$name"
        done
    fi
}

# ── 从 WebDAV 下载文件 ──
webdav_download() {
    local remote_file="$1"
    local local_path="$2"
    local url="${WEBDAV_URL%/}/${remote_file}"

    local http_code
    http_code=$(curl -s -o "$local_path" -w "%{http_code}" --max-time 600 \
        -u "${WEBDAV_USER}:${WEBDAV_PASS}" \
        "$url" 2>/dev/null)

    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "201" ]]; then
        return 0
    else
        echo "  HTTP ${http_code}" >&2
        return 1
    fi
}

# ── 查询 WebDAV 文件大小（字节） ──
webdav_file_size() {
    local remote_file="$1"
    local url="${WEBDAV_URL%/}/${remote_file}"

    curl -sI --max-time 15 \
        -u "${WEBDAV_USER}:${WEBDAV_PASS}" "$url" 2>/dev/null | \
        grep -i 'content-length' | awk '{print $2}' | tr -d '\r'
}
