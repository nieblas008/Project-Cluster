#!/usr/bin/env bash
# Provision a fresh Ubuntu VPS (Hetzner CX22/CAX11) as the Project Cluster
# relay. Run as root ON the box. Idempotent. See docs/runbooks/relay.md.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/nieblas008/Project-Cluster.git}"

apt-get update
apt-get install -y --no-install-recommends docker.io docker-compose-v2 git openssl ufw curl

# Firewall: SSH + the two relay ports, nothing else.
ufw allow OpenSSH
ufw allow 7600/tcp
ufw allow 7601/udp
ufw --force enable

mkdir -p /opt/cluster/tls
cd /opt/cluster
if [[ ! -d repo ]]; then
    git clone --depth 1 "$REPO_URL" repo
fi

# Self-signed cert: the app pins its fingerprint, no CA involved.
if [[ ! -f /opt/cluster/tls/cert.pem ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout /opt/cluster/tls/key.pem -out /opt/cluster/tls/cert.pem \
        -days 3650 -nodes -subj "/CN=cluster-relay"
fi
# The container runs as 'nobody'.
chown -R 65534:65534 /opt/cluster/tls
chmod 600 /opt/cluster/tls/key.pem

cd /opt/cluster/repo
docker compose -f deploy/compose.yml up -d --build

echo
echo "============================================================"
echo " Relay is up. Enter these in the app's Settings:"
echo "   Address:     $(curl -4 -s ifconfig.me || hostname -I | awk '{print $1}')"
echo "   Fingerprint: $(openssl x509 -in /opt/cluster/tls/cert.pem -outform DER | sha256sum | cut -d' ' -f1)"
echo "============================================================"
