# Changelog

## Unreleased

- **Desk items can now be rotated.** The wire protocol, host validation, and
  SQLite persistence for moving/rotating a placed item all existed and were
  tested, but no UI ever sent the command — every item was stuck at rotation 0.
  In decorate mode: click an item to turn it a quarter turn, ⌥-click to remove.
  The end-to-end smoke now covers the rotate path on both transports.
- Removed dead `VoiceEngine.removeSpeaker` (superseded by `retainSpeakers` in
  the Phase 3 audit; zero call sites since).
- ADR 0007 (emotes + minimap) corrected to **proposed** — it described designs
  that aren't built yet while claiming "accepted".
- Added [docs/ROADMAP.md](docs/ROADMAP.md): where the project stands and what
  to do next, in order.

## v0.1.0-alpha — First assembled alpha (2026-07-02)

The first tagged build: all seven phases of the core scope (the 0.1–0.9
development milestones below), plus the pre-alpha audit:

- **Fixed:** blocking an offline player silently did nothing — the blocklist
  now persists regardless of connection state, and chaos drill 5 proves a
  blocked identity is refused on rejoin.
- **Fixed:** the menu bar's "Open Window" couldn't reopen a closed window.
- Voice concealment stats now surface in the connection-quality tooltip.
- Version alignment (app 0.1.0, relay banner), asset license manifest
  completed (items/karts sprites + audio), README gained the controls table,
  plan status updated.

Known alpha edges (documented in docs/runbooks/incident.md): no unblock UI,
no desk reassignment UI, identity import applies to new sessions only.

## 0.9.0 — Phase 7: The rock-solid pass (2026-07-02)

- Chaos drills, automated and in CI: a member's wifi drop removes them cleanly
  and auto-parks their kart; a host crash ends every joiner without a hang;
  rehosting with the same world brings desks/laps/approvals back; kick delivers
  its reason. All four run against a real relay on every push.
- Menu-bar hosting: close the window and the world stays up — code and roster
  one click away, Stop Hosting included. The Mac won't idle-sleep while hosting.
- Moderation: right-click a roster row to Kick or Block (blocklist persists;
  blocked identities are refused at the door).
- World & Identity in Settings: export the world file (one SQLite file is the
  whole world), export/import your identity key to move Macs. Restore drill
  executed against the real world file: 4.6 s + an app relaunch
  (docs/runbooks/restore.md).
- Runbooks: the "bad wifi Friday" checklist, incident quick-reference, and
  backup/restore — plus scripts/drill-restore.sh and scripts/itest-chaos.sh.

With this, all seven phases of the plan's core scope are complete.

## 0.8.0 — Phase 6: Go-karts 🏎️ (2026-07-02)

- Four karts wait on the gravel loop's south straight. Walk up, press E, and
  the avatar becomes a kart: momentum, braking, reverse, speed-scaled steering,
  and a Space handbrake that trades grip for slide (ADR 0006). Walls scrub
  speed with a satisfying thunk instead of sticking.
- Every handling number lives in KartTuning.standard, pinned by tests —
  "the kart feels wrong" is a constants PR.
- The track: checkpoints around the loop with a host-clocked lap timer that
  refuses shortcuts and can't be forged by a fast client. cross the start line
  to arm, lap in order, and your time lands in the world database.
- Leaderboard (trophy button): each player's personal best, fastest first,
  persisted across sessions. lapCompleted tells you your time and whether it's
  a new PB. The Phase 5 trophies finally mean something.
- Feel: color-matched kart sprites rotating to live headings (remote karts
  turn smoothly via angle interpolation), skid marks while drifting, generated
  engine loop / horn (H) / skid audio, camera zooms out at speed.
- Claim locks: one driver per kart, mount requires standing next to it,
  dismount (or disconnect) parks it where you stood; a fresh session lines
  karts back at their pads.
- Wire version 5 (snapshot mode/heading, input flags, race messages). The
  smoke now MOUNTS, drives at kart speed past the host's kart-aware
  validation, and dismounts — on UDP and forced TCP.

## 0.7.0 — Phase 5: Desks & personalization (2026-07-02)

- Claim a desk: stand in any of the mansion's 16 desk zones and the desk panel
  offers Claim (one desk per person), Decorate, or Release — a released desk
  surrenders its decorations (ADR 0005).
- Item catalog: 20 items across plants, tech, comfort, fun, and trophies —
  original generated sprites (items.png), zero license risk. The trophy shelf
  awaits Phase 6's kart winners.
- Decorate mode: the desk highlights in the world; click inside to place the
  selected item (snapped to half-tiles), click an item to remove it, 8 items
  max per desk.
- Host-authoritative and persistent: every edit is validated on the host (your
  desk only, inside its bounds, valid item), stored in SQLite (migration v2),
  and the full desk state broadcasts live to everyone — placements survive
  restarts and appear the moment someone joins.
- Wire version 4 (deskState/deskCommand messages).
- The end-to-end smoke now also claims a desk, places a lava lamp, and asserts
  both sides converge — on UDP and forced TCP.

## 0.6.0 — Phase 4: Status & presence (2026-06-13)

- User-set status — Available / Focus / Do Not Disturb — set from an in-world
  picker or hotkeys (⌃1/⌃2/⌃3), persisted across sessions, shown as a badge on
  your avatar and in the roster.
- Derived presence: online / away / offline. The host turns idle time (no
  movement or voice for 5 min) into an "away" flag and dims the avatar; offline
  players appear from the database with "last seen" (ADR 0004).
- Roster sidebar: everyone the world has ever met — online (active before away)
  before offline-by-recency — with status, away, and last-seen. Toggle in the HUD.
- DND mutes voice both ways: the client force-mutes the mic and the host drops a
  DND speaker and skips a DND listener in the fan-out (defense in depth).
- Status persists in the world database and rides the roster on the wire
  (wire version → 3); a new setStatus message carries changes host-ward.
- The end-to-end smoke now also flips the joiner to DND and asserts the host's
  roster reflects it, on both transports.

## 0.5.0 — Phase 3 (part 2): Voice finishing pass (2026-06-13)

- Push-to-talk: hold ⌥ Option to transmit (a modifier never collides with
  movement or the future kart handbrake); toggle in Settings → Voice, open
  mic stays the default. HUD shows "Hold ⌥" / "ON AIR".
- Output-device selection in the in-world toolbar (route playback to
  headphones to break an echo loop); mic picker moved alongside it.
- Adaptive jitter buffer: depth grows after a concealed burst and eases back
  after clean ones, only ever changing at talk-burst boundaries so within-burst
  playout stays deterministic. Receive-side VoiceStats (played / concealed /
  late-dropped) exposed.
- Connection-quality indicator (joiner): a 3-bar read derived from the host's
  snapshot cadence — good / fair / poor / lost — in the HUD.
- Settings → Voice section for the push-to-talk preference (persisted).

## 0.4.0 — Phase 3 (part 1): Proximity voice (2026-06-12)

- Voice with zero third-party dependencies: Apple's native Opus codec via
  AVAudioConverter, probed empirically before committing (ADR 0003).
- Capture: voice-processed input (Apple echo cancellation / noise suppression
  / gain control), 48 kHz mono, 20 ms frames, RMS mic gate with hangover —
  silence is never sent.
- Playback: per-speaker pipelines (jitter buffer with reorder/conceal/burst
  logic → Opus decode → player node), one 20 ms playout timer.
- The host is a micro-SFU (PLAN §8): voice frames fan out only to members
  within earshot, speaker identity stamped from the verified pair (no
  spoofing), payloads re-sealed per pair but never decoded.
- Proximity volume: each snapshot drives per-speaker gain (full ≤5 tiles,
  fade to silent at 10).
- Voice rides the same two roads as movement: UDP datagrams or the TCP
  tunnel (ADR 0002) — per player, automatically.
- In-world HUD: mute toggle, live mic level, input-device picker, permission
  errors with a fix path; speaking rings on avatars.
- Microphone entitlement + usage description; the smoke test now TALKS:
  synthetic Opus both directions through the relay, decoded and
  energy-verified, on both transports.

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
