#!/usr/bin/env bash
# ============================================================
#  test_webdav.sh — WebDAV 集成测试
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

echo "[11] WebDAV 集成测试"
_cleanup

# 加载 WebDAV 配置（优先 env，否则从 settings.json 读取）
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

# 加载 webdav 模块
source "${ROOT}/service/engine/lib/webdav.sh"

# 11a: webdav_configured
_assert_eq "webdav_configured 检测" \
    "$(webdav_configured && echo yes || echo no)" "yes"

# 11b: webdav_connection_test
printf "  "
if webdav_connection_test; then
    echo "✓ WebDAV 连接成功"
    PASS=$((PASS + 1))

    # 11c: 上传测试文件
    test_file="${ROOT}/instance/backups/_webdav_test_upload.tar.gz"
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
        dl_path="${ROOT}/instance/backups/_webdav_test_download.tar.gz"
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
