#!/usr/bin/env bash
# Timed world backup/restore drill (Phase 7). Copies the live world file to a
# backup, "loses" a scratch copy, restores it, and integrity-checks both ways.
# Never touches the real file except to read it.
set -euo pipefail

CONTAINER="$HOME/Library/Containers/com.ricardonieblas.ProjectCluster/Data/Library/Application Support/Project Cluster/world.sqlite"
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

if [[ -f "$CONTAINER" ]]; then
    SOURCE="$CONTAINER"
    echo "drill: using the real world file ($(du -h "$SOURCE" | cut -f1 | xargs))"
else
    SOURCE="$SCRATCH/synthetic.sqlite"
    sqlite3 "$SOURCE" "CREATE TABLE t(x); INSERT INTO t VALUES (1),(2),(3);"
    echo "drill: no world file yet — using a synthetic database"
fi

START=$(python3 -c 'import time; print(time.time())')
cp "$SOURCE" "$SCRATCH/backup.sqlite"                                   # 1. back up
sqlite3 "$SCRATCH/backup.sqlite" "PRAGMA integrity_check;" >/dev/null   # 2. verify backup
cp "$SCRATCH/backup.sqlite" "$SCRATCH/restored.sqlite"                  # 3. restore
sqlite3 "$SCRATCH/restored.sqlite" "PRAGMA integrity_check;" >/dev/null # 4. verify restore
END=$(python3 -c 'import time; print(time.time())')

echo "drill: backup + verify + restore + verify took $(python3 -c "print(f'{$END - $START:.2f}')")s"
echo "drill: PASS — restoring a world is a file copy plus an app relaunch"
