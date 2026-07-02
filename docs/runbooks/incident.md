# Runbook — Incidents

Quick references for the three things that can actually break, plus the sharp
edges that don't have UI yet.

## "Nobody can join"
1. Host: menu-bar icon present? If not, you aren't hosting — Host & Play again
   (codes are per-session; share the new one).
2. Host: Settings → Doctor. Control-plane row red → the relay is down (below).
3. One person only → their problem: Doctor on their side, check app version.

## Relay down / unreachable
- SSH to the VPS: `docker ps`, `docker logs cluster-relayd`, `docker restart cluster-relayd`.
- Box gone? Reprovision from scratch (docs/runbooks/relay.md, ~10 min).
  The relay holds **no data**; only Settings (address/fingerprint) may change.
- Cert rotated → every member updates the fingerprint in Settings (the Doctor
  shows expected-vs-got on mismatch).

## Host Mac died mid-Friday
- Session is gone; world data is not (it's on that Mac's disk, in Time Machine,
  and in any Settings export).
- Fastest recovery on another Mac: import an identity + world backup
  (docs/runbooks/restore.md), Host & Play, share the new code.

## Sharp edges without UI (fine for the alpha, backlog for the product)
- **Unblock**: no button yet. On the host Mac, while the app is closed:
  `sqlite3 <world.sqlite path> "UPDATE players SET isBlocked = 0 WHERE displayName = 'NAME';"`
- **Desk reassignment for an absent player**: release their claim the same way
  (`DELETE FROM deskClaims WHERE zone = 'desk-NN';`).
