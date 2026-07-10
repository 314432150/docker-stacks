#!/usr/bin/env bash
# ============================================================
#  test_lib.sh — lib 可复用函数完整性
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_helpers.sh"

echo "[10] lib 可复用函数完整性"

LIB="${ROOT}/scripts/lib"
for fn in discover_apps get_backup_dirs get_description parse_volumes \
          init_state select_all_recommended get_selected_dirs has_any_selected \
          toggle_app is_selected toggle_dir \
          webdav_configured webdav_connection_test webdav_upload \
          webdav_list webdav_download webdav_file_size; do
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
