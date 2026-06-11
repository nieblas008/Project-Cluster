# Changelog

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
