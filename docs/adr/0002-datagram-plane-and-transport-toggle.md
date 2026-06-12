# ADR 0002 — Datagram plane: relay UDP flows, sealed datagrams, user-selectable TCP fallback

**Date:** 2026-06-11 · **Status:** accepted · **Phase:** 2

## Context

Movement snapshots (15 Hz) and later voice want unreliable, latest-wins delivery — UDP. Phase 1
deferred the relay's UDP data plane (ADR 0001). Some networks block outbound UDP entirely; the owner
explicitly wants the fallback to be a *user-facing option*, not only auto-detection, because future
teams will run unknown network configurations.

## Decision

1. **Relay UDP flows.** At attach time the relay allocates a `flowID` + per-side 8-byte tokens and
   tells each leg via the control plane (`dataPlane`). Each app sends a `CBND` bind datagram
   (magic + flowID + token) from its UDP socket; the relay records the observed address per side and
   thereafter forwards datagrams between the two addresses by `flowID` prefix, contents untouched.
   Flows expire after 120 s idle (sweep task) — the relay stays stateless-ish and self-cleaning.
   Unbound small datagrams that aren't binds are still echoed (Connectivity Doctor probe unchanged).
2. **Datagram encryption.** The Phase 1 tunnel handshake now also derives directional datagram keys
   (HKDF labels `udp-i2r`/`udp-r2i`). Each datagram is `flowID ‖ seq ‖ ChaChaPoly(payload,
   nonce = seq, aad = flowID)`. Receivers accept only `seq` greater than the highest seen —
   replays and reordering drop, which is correct for latest-wins movement. The relay can read
   exactly nothing.
3. **One payload codec, two transports.** World traffic (`WorldPayload`: inputs, snapshots) encodes
   identically everywhere; it rides either sealed datagrams (UDP) or `worldFrame` messages inside
   the existing encrypted TCP tunnel (fallback). A `GameTransport` interface hides the choice from
   the sim.
4. **Per-player negotiation + toggle.** Each joiner probes its UDP path after `welcome` and tells
   the host (`transportSelected`). Settings gains a **Connection** section: *Automatic
   (recommended)* / *TCP only (compatibility)*. The host's own setting acts as a session-wide
   policy (advertised in `welcome`): a host on a UDP-blocked network forces TCP for all. Mixed
   sessions are normal — one player on TCP doesn't affect the others.
5. Wire version bumps to 2 (`welcome` gained fields; datagram space is new). Host and joiners must
   update together — fine in alpha, TestFlight auto-updates later.

## Consequences

- Movement works on hostile networks at slightly higher latency, by design rather than by accident.
- The settings panel starts its life as the home for future "advanced options" (per the owner's
  product direction).
- The relay gains its first UDP state (flow table) but no persistence and no key material.
