#!/usr/bin/env bash
# End-to-end check: real relay + host & joiner sessions. Runs the scenario
# twice — once auto-negotiating UDP, once forced to the TCP fallback
# (ADR 0002) — and both must walk.
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

export RELAY_HOST=127.0.0.1 RELAY_FINGERPRINT="$FP"
export RELAY_CONTROL_PORT="${RELAY_CONTROL_PORT:-7600}" RELAY_UDP_PORT="${RELAY_UDP_PORT:-7601}"

echo "=== smoke 1/2: automatic transport (expects UDP) ==="
Packages/ClusterNet/.build/debug/cluster-smoke

echo "=== smoke 2/2: forced TCP fallback ==="
CLUSTER_FORCE_TCP=1 Packages/ClusterNet/.build/debug/cluster-smoke
