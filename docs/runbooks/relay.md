# Runbook — The relay (`cluster-relayd`)

A stateless rendezvous + splice relay on a tiny VPS. It holds **no data**: if
it dies, redeploy and everyone reconnects. World data never leaves the host Mac.

## Provision (one-time, ~10 minutes)

1. Create the VPS: Hetzner Cloud → **CX22** (or CAX11/ARM), **Ubuntu 24.04**,
   region nearest the team (Ashburn `ash` / Hillsboro `hil`), add your SSH key.
2. SSH in and run the provision script:
   ```sh
   ssh root@<vps-ip>
   curl -fsSL https://raw.githubusercontent.com/nieblas008/Project-Cluster/main/deploy/provision-relay.sh | bash
   ```
   (Or copy `deploy/provision-relay.sh` over and run it — read it first; it
   installs Docker, opens 7600/tcp + 7601/udp, generates the self-signed cert,
   and starts the container.)
3. The script ends by printing the **Address** and **Fingerprint** — paste both
   into the app: gear icon → Settings → Relay.
4. In the app, run the **Connectivity Doctor** (Settings). All green → done.
   **Run it once from the host's work WiFi specifically** — that's the network
   that matters (PLAN §14 Phase 1).

## Update to a new relay version

- GitHub → Actions → **Deploy relay** → Run workflow
  (needs `RELAY_SSH_HOST` + `RELAY_SSH_KEY` repo secrets), or manually:
  ```sh
  ssh root@<vps-ip> 'cd /opt/cluster/repo && git pull && docker compose -f deploy/compose.yml up -d --build'
  ```
- Mid-session impact: active sessions drop and apps reconnect/rehost; pick a
  quiet moment.

## Operations

| Task | Command (on the VPS) |
|---|---|
| Status | `docker ps`, `docker logs -f cluster-relayd` |
| Restart | `docker restart cluster-relayd` |
| Cert rotation | delete `/opt/cluster/tls/*`, rerun provision script, give everyone the **new fingerprint** |
| Rebuild from scratch | new VPS + provision script (~10 min); nothing to back up |

## Troubleshooting (mirror of the in-app Doctor)

- **Control plane unreachable** — container down (`docker ps`), wrong IP in
  Settings, or the network blocks 7600/tcp (compare against a phone hotspot).
- **Certificate mismatch** — fingerprint in Settings doesn't match the cert on
  the box (rotated cert? typo?). If neither: treat as hostile and investigate.
- **UDP blocked (info)** — expected on some corporate networks. Lobby works
  over TCP; movement/voice (Phase 2+) fall back to TCP from that network.
