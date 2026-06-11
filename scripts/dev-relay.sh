#!/usr/bin/env bash
# Runs the relay locally with a dev certificate; prints the fingerprint to
# paste into the app's Settings (host: 127.0.0.1).
set -euo pipefail
cd "$(dirname "$0")/.."
FP=$(scripts/relay-dev-cert.sh .dev/relay)
echo "Relay fingerprint: $FP"
swift build --package-path Relay --product cluster-relayd
exec Relay/.build/debug/cluster-relayd \
    --tls-cert .dev/relay/cert.pem --tls-key .dev/relay/key.pem "$@"
