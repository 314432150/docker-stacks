#!/usr/bin/env bash
# 从 backup.sh 生成的 tar.gz 恢复应用数据
# 这是 resti.sh 的 CLI 精简版，交互恢复请用: bash scripts/backup.sh restore
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "Usage: $0 <backup-dir> <app> [app ...]"
  echo "  Example: $0 backup/20250625-120000 jellyfin vaultwarden"
  echo ""
  echo "For interactive restore: bash scripts/backup.sh restore"
  exit 1
}

[[ $# -ge 2 ]] || usage

BACKUP_DIR="$1"
shift

if [[ ! -d "${BACKUP_DIR}" ]]; then
  echo "Backup dir not found: ${BACKUP_DIR}" >&2
  exit 1
fi

for name in "$@"; do
  # 支持新格式 {name}_{subdir}.tar.gz 和旧格式 {name}.tar.gz
  shopt -s nullglob
  archives=("${BACKUP_DIR}/${name}"*.tar.gz)
  shopt -u nullglob

  if [[ ${#archives[@]} -eq 0 ]]; then
    echo "No archives found for: ${name}" >&2
    continue
  fi

  for archive in "${archives[@]}"; do
    echo "Restoring from $(basename "$archive") ..."
    tar -xzf "${archive}" -C "${ROOT}"
  done
done

echo "Restore complete. Run docker compose up -d for the restored apps."
