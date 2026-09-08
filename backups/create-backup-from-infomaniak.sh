#!/usr/bin/env bash
set -euo pipefail
umask 077

if [ $# -eq 0 ]; then
  echo "Usage: $0 <local-backup-destination-path>"
  echo "Example: $0 /home/sandro/backups/vaultwarden"
  exit 1
fi

LOCAL_TARGET_DIR="$1"
REMOTE_HOST="deploy@84.234.19.192"
CONTAINER_NAME="vaultwarden-raess"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILENAME="vaultwarden_backup_$TIMESTAMP.tar.gz"

mkdir -p "$LOCAL_TARGET_DIR"

REMOTE_TEMP_FILE=""
cleanup_remote() {
  if [ -n "$REMOTE_TEMP_FILE" ]; then
    ssh "$REMOTE_HOST" "rm -rf \"\$(dirname '$REMOTE_TEMP_FILE')\"" 2>/dev/null || true
  fi
}
trap cleanup_remote EXIT

echo "Connecting to $REMOTE_HOST and executing Docker backup..."
REMOTE_OUTPUT=$(ssh "$REMOTE_HOST" bash -s << EOF
  set -euo pipefail
  TEMP_WORKSPACE=\$(mktemp -d)
  DATA_DIR="\$TEMP_WORKSPACE/vw-data"
  REMOTE_ARCHIVE="\$TEMP_WORKSPACE/$BACKUP_FILENAME"
  mkdir -p "\$DATA_DIR"

  # 1. Trigger Vaultwarden's built-in native SQLite backup engine
  # (this creates a timestamped file like db_20250727_005001.sqlite3 in /data,
  #  the exact name is not predictable, so we look it up afterwards)
  docker exec $CONTAINER_NAME /vaultwarden backup
  GENERATED_DB=\$(docker exec $CONTAINER_NAME sh -c 'ls -t /data/db_*.sqlite3 2>/dev/null | head -n 1')
  if [ -z "\$GENERATED_DB" ]; then
    echo "Error: could not find generated db_*.sqlite3 backup file in container" >&2
    exit 1
  fi

  # 2. Copy the generated backup out and rename it, then remove temp copy inside container
  docker cp $CONTAINER_NAME:"\$GENERATED_DB" "\$DATA_DIR/db_$TIMESTAMP.sqlite3"
  docker exec $CONTAINER_NAME rm "\$GENERATED_DB"

  # 3. Copy attachments, sends, and config if present
  docker cp $CONTAINER_NAME:/data/attachments "\$DATA_DIR/attachments" 2>/dev/null || true
  docker cp $CONTAINER_NAME:/data/sends "\$DATA_DIR/sends" 2>/dev/null || true
  docker cp $CONTAINER_NAME:/data/config.json "\$DATA_DIR/config.json" 2>/dev/null || true
  docker cp $CONTAINER_NAME:/data/rsa_key.pem "\$DATA_DIR/rsa_key.pem" 2>/dev/null || true

  # 4. Compress the files
  tar -czf "\$REMOTE_ARCHIVE" -C "\$DATA_DIR" .
  echo "REMOTE_FILE:\$REMOTE_ARCHIVE"
EOF
)

REMOTE_TEMP_FILE=$(echo "$REMOTE_OUTPUT" | grep '^REMOTE_FILE:' | cut -d: -f2-)

if [ -z "$REMOTE_TEMP_FILE" ]; then
  echo "Error: Remote backup failed."
  echo "$REMOTE_OUTPUT"
  exit 1
fi

echo "Downloading backup to $LOCAL_TARGET_DIR/$BACKUP_FILENAME..."
scp "$REMOTE_HOST:$REMOTE_TEMP_FILE" "$LOCAL_TARGET_DIR/$BACKUP_FILENAME"
chmod 600 "$LOCAL_TARGET_DIR/$BACKUP_FILENAME"

# Verify the downloaded archive is a valid, non-empty tarball
if ! tar -tzf "$LOCAL_TARGET_DIR/$BACKUP_FILENAME" >/dev/null 2>&1; then
  echo "Error: Downloaded archive is corrupt or empty."
  exit 1
fi

# Local Retention Policy: Keep backups from the last 14 days
find "$LOCAL_TARGET_DIR" -type f -name "vaultwarden_backup_*.tar.gz" -mtime +14 -delete

echo "Backup successfully completed and stored at: $LOCAL_TARGET_DIR/$BACKUP_FILENAME"
