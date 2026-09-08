#!/usr/bin/env bash
# run-daily-backup-captiva.sh
#
# Wrapper for sandro-captiva-linux: runs the Vaultwarden backup once per day.
# Since this machine isn't always on, this script is meant to be triggered
# frequently (e.g. every hour, and at boot) via cron — it exits immediately
# if a backup for today already exists, and only does actual work once.
set -euo pipefail

# --- Configuration ---
BACKUP_SCRIPT="/home/sandro/workspace/vaultwarden-raess/backups/create-backup-from-infomaniak.sh"
TARGET_DIR="/home/sandro/backups/vaultwarden"
LOG_FILE="$TARGET_DIR/backup.log"

TODAY=$(date +"%Y%m%d")

mkdir -p "$TARGET_DIR"

# Skip if a backup with today's date already exists
if ls "$TARGET_DIR"/vaultwarden_backup_"$TODAY"_*.tar.gz >/dev/null 2>&1; then
  exit 0
fi

{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S') - No backup found for today, running backup ====="
  "$BACKUP_SCRIPT" "$TARGET_DIR"
} >> "$LOG_FILE" 2>&1
