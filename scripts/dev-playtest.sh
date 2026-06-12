#!/usr/bin/env bash
# Solo playtest: builds the app and opens TWO instances — "Player 1" (your
# normal profile) and "Player 2" (its own identity via -ClusterProfile).
# Run scripts/dev-relay.sh in another terminal first.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building (first time takes a minute)…"
xcodebuild -scheme "Project Cluster" -configuration Debug \
    -derivedDataPath .dev/build build | grep -E "BUILD" || true

APP=".dev/build/Build/Products/Debug/Project Cluster.app"
if [[ ! -d "$APP" ]]; then
    echo "Build failed — run the xcodebuild line above without the grep to see why."
    exit 1
fi

open -n "$APP"
sleep 1
open -n "$APP" --args -ClusterProfile two
echo "==> Two instances open. Host in one, join with the code in the other."
