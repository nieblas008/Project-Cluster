# Changelog

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
