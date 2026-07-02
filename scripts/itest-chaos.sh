#!/usr/bin/env bash
# Phase 7 chaos drills against a real relay: wifi drop, host crash, rehost
# persistence, kick. Exits 0 only if every drill degrades cleanly.
set -euo pipefail
cd "$(dirname "$0")/.."
FP=$(scripts/relay-dev-cert.sh .dev/relay)
swift build --package-path Relay --product cluster-relayd
swift build --package-path Packages/ClusterNet --product cluster-smoke
Relay/.build/debug/cluster-relayd \
    --tls-cert .dev/relay/cert.pem --tls-key .dev/relay/key.pem \
    --control-port "${RELAY_CONTROL_PORT:-7600}" --udp-port "${RELAY_UDP_PORT:-7601}" &
RELAY_PID=$!
trap 'kill $RELAY_PID 2>/dev/null || true' EXIT
sleep 1.5
RELAY_HOST=127.0.0.1 RELAY_FINGERPRINT="$FP" \
RELAY_CONTROL_PORT="${RELAY_CONTROL_PORT:-7600}" RELAY_UDP_PORT="${RELAY_UDP_PORT:-7601}" \
CLUSTER_CHAOS=1 Packages/ClusterNet/.build/debug/cluster-smoke
