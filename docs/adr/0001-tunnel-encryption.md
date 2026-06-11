# ADR 0001 — Tunnel encryption: Noise-style handshake over a TCP splice (not QUIC-through-relay)

**Date:** 2026-06-11 · **Status:** accepted · **Phase:** 1

## Context

The plan (§2) called for QUIC end-to-end between host and joiner through a dumb UDP relay.
Network.framework only runs QUIC/TLS in the *client* role on outbound connections; a host behind NAT
cannot run a QUIC listener that is reachable "through" a remote relay. Terminating QUIC at the relay
would let the relay read traffic — unacceptable.

## Decision

- **Reliable plane:** the relay *splices* two inbound TCP connections (joiner's connection + a
  host-side `ATTACH` connection) into one byte pipe per pair. Host and joiner run an end-to-end
  encrypted session over it: an NK-pattern handshake (CryptoKit X25519 → HKDF → ChaChaPoly frames),
  where the host's static session key's SHA-256 fingerprint reaches the joiner via the control plane.
- **Control plane:** ordinary TLS, terminated at the relay (NIOSSL server certificate; the app pins
  its SHA-256 fingerprint alongside the relay IP).
- **Datagram plane (Phase 2+):** UDP flow forwarding with app-layer ChaChaPoly sealing, keys exported
  from the tunnel handshake. Falls back onto the reliable plane where UDP is blocked.

## Consequences

- The relay remains blind: it sees TLS it terminates only on the *control* plane (codes,
  fingerprints — no game or voice content) and opaque ciphertext on the session planes.
- Trust chain: app pins relay cert → relay relays the host fingerprint verbatim → joiner pins host.
  The relay is trusted for introductions only, as §2 always stated.
- We own a small, textbook handshake implementation (NK pattern, transcript-hashed) with unit tests
  on both ends, instead of depending on an impossible API arrangement.
- UDP flow forwarding moves from Phase 1 to Phase 2, where movement traffic can actually exercise it;
  Phase 1's Connectivity Doctor still probes UDP reachability via the relay's echo port.
