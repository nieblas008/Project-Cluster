# Changelog

## 0.3.0 — Phase 2: The walkable mansion (2026-06-11)

- The mansion exists: 44×30 generated map (great hall, library, lounge, four
  offices with 16 desk zones, gardens, pond, and the kart-track loop reserved
  for Phase 6), rendered in SpriteKit with generated tile + avatar art
  (original, license-free — see assets/LICENSES.md).
- Walking: WASD/arrows, client-side prediction with the shared sim, host-side
  validation (speed clamp, wall clips refused), remote avatars interpolated
  120 ms in the past, camera follow, nameplates.
- 15 Hz authoritative world tick on the host, fanned out per member.
- UDP datagram plane through the relay (ADR 0002): per-pair flows with token
  binding, ChaChaPoly-sealed datagrams keyed from the tunnel handshake,
  replay/reorder protection, idle flow sweep.
- TCP fallback as a first-class road: same world payloads over the encrypted
  tunnel, negotiated per player; Settings → Connection gains the
  Automatic / TCP-only toggle; the join HUD shows which road you're on.
- Wire version 2 (welcome carries map version + transport policy; map-hash
  mismatch is refused with a clear message).
- The CI smoke now walks: host + joiner converge rosters, the joiner moves
  ~2 tiles, and the run executes twice — once over UDP, once forced to TCP.

## 0.2.0 — Phase 1: Relay, host & join (2026-06-11)

- Real relay: TLS control plane (register → 6-character code → join → attach)
  and per-pair connection splicing; still stateless, still blind (ADR 0001).
- End-to-end encrypted tunnel between host and joiner: NK-pattern handshake
  (X25519 → ChaChaPoly), host key pinned via the relay, identity signature
  bound to the tunnel transcript.
- Host lobby: live session code with copy button, knock/approve for first-time
  identities (persisted to the world database), roster broadcast, stop session.
- Join lobby: code entry, progress states, knock waiting, roster, leave.
- Connectivity Doctor in Settings: control-plane reachability + certificate
  pin + protocol ping + UDP probe, with plain-language remedies.
- Relay deploy kit: VPS provision script (Docker, firewall, cert), compose
  with TLS mounts, manual deploy workflow, relay runbook.
- CI now runs a true end-to-end smoke: real relay process, host + joiner
  sessions, both rosters must converge.

## 0.1.0 — Phase 0: Foundation (2026-06-11)

- One unified macOS app (SwiftUI) with Host & Play / Join screens stubbed.
- Device identity: Curve25519 keypair generated on first launch, stored in the Keychain —
  no accounts, no passwords.
- Host world storage: SQLite (GRDB) under Application Support with migration v1
  (players, space + invite secret).
- Shared `ClusterProtocol` package: wire codec, geometry/interpolation math,
  proximity-audio rules, kart tuning constants — all unit-tested.
- Relay skeleton (`cluster-relayd`, SwiftNIO): TCP PING/PONG control plane and UDP echo
  data plane, with Dockerfile and compose file for the future VPS.
- CI: macOS job (lint, package tests, app build) and Linux job (relay tests + release build).
- Release tooling: `scripts/release.sh` (archive → upload to TestFlight) + runbook.
