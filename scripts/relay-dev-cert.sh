#!/usr/bin/env bash
# Generates (once) a self-signed dev certificate for the local relay and
# prints its fingerprint. Used by dev runs, the smoke test, and CI.
set -euo pipefail
CERT_DIR="${1:-.dev/relay}"
mkdir -p "$CERT_DIR"
if [[ ! -f "$CERT_DIR/cert.pem" ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
        -days 825 -nodes -subj "/CN=cluster-relay-dev" 2>/dev/null
fi
openssl x509 -in "$CERT_DIR/cert.pem" -outform DER | shasum -a 256 | cut -d' ' -f1
