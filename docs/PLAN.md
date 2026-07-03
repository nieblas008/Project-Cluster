# Project Cluster — Master Plan (v4)

> A native macOS app, written in Swift, in the spirit of Gather (gather.town): a 2D mansion where a
> ~15-person remote team walks around as avatars, talks over proximity voice chat, personalizes desks,
> and races go-karts. **One member hosts the session on their own Mac** — the world's data lives there —
> and everyone else joins with a short code, Among Us style, **through a tiny relay server in the
> cloud** so nobody ever needs port forwarding.

**Status:** **v0.1.0-alpha — all seven phases of the core scope are shipped.**
Development continues from the backlog (§15), one item per prompt (§17).
**Last updated:** 2026-06-10 (v4 — relay-based connectivity replaces direct connections)
**Owner:** Ricardo Nieblas

**Changes from v3:** the direct-connection design (router port mapping, IP-encoding codes) is replaced
by a **relay server** — required because the host will often be on work WiFi where port forwarding is
impossible. This is the Among Us architecture: the host's machine runs the session and stores the data;
a small, *stateless* cloud relay only introduces peers and forwards encrypted packets. Side effects:
session codes become short (6 chars) again, and no domain is needed. Everything else from v3 stands.

---

## 1. Vision & guiding constraints

- **The model:** Ricardo opens the app and clicks **Host** — his Mac runs the authoritative session and
  stores the world (SQLite on disk). The app registers with the relay and shows a short code. Coworkers
  open the same app, click **Join**, type the code. When the host app closes, the room closes.
- **The relay exists so hosting works from anywhere** — including work WiFi, hotels, hotspots. Neither
  host nor joiners need router access: everyone connects *outbound* to the relay.
- **The relay stores nothing.** No accounts, no world data, no logs of game content. It maps codes to
  sessions and forwards end-to-end-encrypted packets it cannot read. If it dies, redeploy in minutes —
  zero data loss, because all data lives on the host's Mac.
- **Availability:** the room is up whenever the host app is running (menu-bar host mode keeps it cheap
  to leave up all day). The relay is always-on but holds no world.
- **No domain, no website.** The app pins the relay's static IP and certificate fingerprint directly —
  native apps don't need DNS or CA-issued certs.
- **All Swift, Apple-first** — including the relay (server-side Swift on Linux).
- **Quality bar:** bare-minimum feature set, each feature rock-solid, then chisel the backlog.
- **Mobile later:** shared Swift packages + SwiftUI + SpriteKit keep the iOS door open (§16).

**Core scope (and nothing else):**
1. Identity & profiles (serverless "accounts" — §6)
2. Host & join from anywhere via short code + relay
3. Walkable shared world (the mansion, multiplayer movement)
4. Proximity **voice** chat (no video, no screen share)
5. Status & presence (roster, available/focus/DND, auto-away)
6. Desk personalization
7. **Go-karts** 🏎️

**Confirmed (2026-06-11):** the whole team uses Macs (work machines) — the app is macOS-exclusive
(iOS later; Windows never).

---

## 2. Connectivity architecture: the dumb relay

```
                         ┌─ tiny VPS (~$5/mo, static IP, no domain) ──────────┐
                         │  cluster-relayd (Swift/NIO, stateless)             │
                         │   · TCP/TLS control: register code / look up code  │
                         │   · UDP forwarding: pairs of opaque packet flows   │
                         └────────▲──────────────────────────▲────────────────┘
                                  │ outbound only            │ outbound only
                                  │                          │
                    ┌─────────────┴──────────┐      ┌────────┴──────────┐
                    │ HOST app (Ricardo)     │      │ JOINER apps (×14) │
                    │ · authoritative sim    │      │ · prediction +    │
                    │ · SQLite world store   │      │   interpolation   │
                    │ · voice fan-out (SFU)  │      │ · voice capture/  │
                    │ · knock approval       │      │   playback        │
                    └────────────────────────┘      └───────────────────┘

         Sessions are encrypted END-TO-END between host and each joiner (ADR 0001);
         the relay splices/forwards opaque bytes and cannot decrypt anything.
```

**How a session works:**
1. Host app opens a pinned TLS control connection to the relay, registers a session, and receives a
   **6-character code** (relay maps code → session, exactly why Among Us codes can be short).
2. A joiner sends the code up its own control connection; the relay introduces the two sides: it
   allocates a UDP flow for the pair and gives the joiner the host's session certificate fingerprint
   (captured at registration).
3. Host and joiner then establish an **end-to-end encrypted tunnel with each other** through a relay
   splice (ADR 0001): the relay pipes the two connections together, and an NK-pattern handshake
   (CryptoKit X25519 → ChaChaPoly) runs between the apps — host key pinned via the relayed
   fingerprint, invite secret + knock approval (§6) gating entry. The reliable plane carries events
   (joins, desk edits, status); a sealed UDP datagram plane (Phase 2) carries movement and voice.
4. The relay never holds session keys. Per-leg TLS protects against on-path attackers; the splice
   pipes ciphertext it cannot open. Originally this was specced as QUIC-through-relay — ADR 0001
   records why that's not buildable with Network.framework and what replaced it.

**Why a custom ~small Swift relay is safe to build:** stateless, no database, no disk, one binary on
one box; SwiftNIO's TCP/TLS and UDP channels are mature on Linux; the data plane is a routing table of
`(flow id) → (two observed addresses)`. Off-the-shelf tunnels (e.g. frp) could substitute in a pinch —
documented as the shortcut, not the plan.

**UDP-hostile networks are a product feature, not just a caveat (ADR 0002):** the TCP fallback is
built as a first-class transport with a user-facing toggle (Settings → Connection), negotiated per
player — a future team behind any firewall can always select compatibility mode. Background: some
corporate networks block outbound UDP entirely. Since the
host will be on work WiFi, **Phase 1's first deliverable is a reachability self-test run from that
exact network**. If UDP fails there, the relay grows a TCP-443 fallback mode (tunneling the datagrams
over the existing TLS control connection — worse for voice latency, but functional) in the same phase
rather than waiting in the backlog.

**Performance reality check:** worst realistic load (all 15 in one room, ~3 simultaneous speakers at
~40 kbps + movement snapshots) is roughly 2 Mbps through the relay and ~2 Mbps up from the host —
trivial for any VPS (Hetzner includes 20 TB/mo) and fine for office/home uplinks. Latency adds one hop;
placing the relay near the team's center (Ashburn VA / Hillsboro OR) keeps voice comfortably under
tolerance. A direct peer-to-peer fast path (hole punching, relay as fallback) is a backlog optimization.

**Alternatives considered and rejected:**
| Option | Why not |
|---|---|
| Direct connections + port forwarding (v3) | Impossible from work WiFi — the host doesn't control that router |
| GameKit / Game Center | Small real-time session sizes, Game Center coupling, opaque relay |
| Cloudflare Workers/Durable Objects relay | WebSocket/TCP only — no UDP datagrams; worse voice for no cost win |
| Tailscale/ZeroTier overlay | "Install a VPN" onboarding; free tiers don't cover 15 |
| iroh (hole punching + free public relays) | Attractive, but adds Rust FFI + third-party relay dependency; revisit if we ever want the P2P fast path for free |
| Full web/cloud stack (v1/v2) | Superseded; remains in git history as the documented fallback world |

---

## 3. Tech stack (Apple-first, plus one small Linux deployment)

| Layer | Choice | Notes |
|---|---|---|
| Language | **Swift 6** everywhere (app + relay) | Strict concurrency; actors isolate sim, networking, audio |
| UI | **SwiftUI** (+ AppKit escape hatches) | Host/join, lobby, roster, desk editor, settings, menu-bar host mode. iOS-portable |
| Game rendering | **SpriteKit** via `SpriteView` | Tile maps, sprites, particles (skid marks!). iOS-portable |
| Game simulation | **Pure Swift, shared package** | Deterministic movement/kart math + collision sampling — *not* SpriteKit physics — same code for host validation and client prediction |
| App networking | **Network.framework** (`NWConnection`) + CryptoKit tunnel (ADR 0001) | TLS to the relay (pinned); end-to-end NK handshake between apps; reliable frames = events, sealed datagrams (Phase 2) = movement + voice |
| Relay | **SwiftNIO** on Linux: TLS control plane + UDP forwarding data plane | Stateless single binary in Docker; never parses QUIC; ~small codebase |
| Relay hosting | **Hetzner CX22/CAX11 VPS** (~$4–5/mo, static IP, 20 TB) | No domain: app pins IP + cert fingerprint. (Oracle Cloud's always-free tier is a $0 alternative with reliability caveats) |
| Identity & crypto | **CryptoKit** (Curve25519) + **Keychain** | Device keypair = identity; certs self-signed + pinned |
| Voice capture/playback | **AVAudioEngine** with voice processing | Apple-provided echo cancellation / noise suppression / AGC — what makes DIY voice feasible |
| Voice codec | **Opus** (vendored libopus via SPM) | ~32–48 kbps/speaker, built-in packet-loss concealment |
| Persistence (host Mac) | **GRDB** (SQLite) | One world file in `~/Library/Application Support/ProjectCluster/`; Time Machine covers backups |
| Maps | **Tiled** → JSON + small Swift importer | Tiled JSON is simple; SKTiled as reference |
| Testing | Swift Testing / XCTest | `ClusterProtocol` math + codec and relay routing are the tested cores |
| CI/CD | GitHub Actions: macOS runner (app), Linux runner (relay) | App: build/test/lint + notarized TestFlight releases. Relay: build/test + Docker image + SSH deploy |
| Distribution | **TestFlight for Mac** | Auto-updates, crash reports, feedback for the 15 testers |

Third-party dependencies, total: GRDB, an Opus wrapper, SwiftNIO (Apple-maintained). Minimum target
macOS 14.

---

## 4. App & repository structure

**One unified app.** Everyone — host and coworkers — installs the same Project Cluster app from
TestFlight. Its first screen offers **Host & Play** or **Join**: hosting simply activates the embedded
`ClusterServer` package in-process, and the app then joins its own session like any other player. The
only other executable in the repo, `cluster-relayd`, is headless server infrastructure that runs on the
VPS — no person ever installs or sees it.

```
Project-Cluster/
├─ ProjectCluster.xcodeproj
├─ App/                          # SwiftUI: HostOrJoin, Lobby, GameWindow (SpriteView + overlays),
│  │                             #   Roster sidebar, DeskEditor panel, Settings, MenuBar host mode
│  └─ Game/                      # SpriteKit: WorldScene, AvatarNode, KartNode, camera,
│                                #   Tiled importer, render-side interpolation
├─ Packages/
│  ├─ ClusterProtocol/           # shared core (pure Swift, platform-free): message types + compact
│  │                             #   versioned binary codec, sim math (movement, kart kinematics,
│  │                             #   collision sampling), proximity + interpolation math, kart tuning
│  ├─ ClusterServer/             # host role: authoritative SimActor (15 Hz), room state, knock
│  │                             #   handling, voice fan-out, GRDB persistence
│  ├─ ClusterNet/                # relay client (control + UDP flows), QUIC transport actors,
│  │                             #   session codes, cert generation/pinning, Connectivity Doctor
│  └─ ClusterVoice/              # voice-processed capture, Opus, jitter buffer, per-speaker
│                                #   playback, speaking detection
├─ Relay/                        # cluster-relayd (SwiftNIO executable) + Dockerfile
│                                #   control plane (register/lookup/introduce) + UDP forwarder
├─ maps/                         # Tiled project + exported JSON
├─ assets/                       # tilesets, sprites, audio + LICENSES.md manifest
├─ deploy/                       # relay: compose file, provision script, deploy workflow target
├─ docs/                         # this plan, ADRs, runbooks/ (relay ops, release, restore, incident)
├─ scripts/                      # release.sh (archive → notarize → TestFlight), seed/dev helpers
└─ .github/workflows/            # ci-app.yml, ci-relay.yml, deploy-relay.yml
```

**Concurrency model:** `SimActor` ticks at 15 Hz on the host; `NetActor`s own connections; rendering on
the MainActor; audio on AVAudioEngine's realtime threads with single-producer handoff buffers.

**The iOS door:** `ClusterProtocol`/`ClusterNet`/`ClusterVoice` are platform-portable; SwiftUI +
SpriteKit run on iOS. A join-only iPhone client later reuses everything but window chrome.

---

## 5. What runs where (and what the relay can never see)

| Concern | Lives on | Notes |
|---|---|---|
| Authoritative simulation (movement, karts, validation) | **Host's Mac** | `ClusterServer` in-process |
| World data (profiles, desks, lap times) | **Host's Mac** (SQLite) | The "stored locally" requirement, satisfied fully |
| Voice fan-out (who hears whom) | **Host's Mac** | Host forwards each speaker only to players in earshot |
| Code → session mapping, packet forwarding | Relay VPS | Stateless; in-memory only |
| Game/voice content | Nowhere in the cloud | End-to-end encrypted host ↔ joiner; relay forwards ciphertext |

---

## 6. Identity & "accounts" without account infrastructure

- **Identity = a Curve25519 keypair** per Mac, generated on first launch, stored in the Keychain;
  public key = stable player ID, private key signs the join handshake.
- **Profile** (display name + avatar preset) travels in the handshake; the host's DB caches it by
  public key, so desks, lap times, and last-seen persist across sessions.
- **Joining:** short code finds the session at the relay; an invite secret (embedded in the code) plus
  **knock approval** ("Dana wants to join" → host approves once, key remembered) gates entry. Kicked
  keys go to a blocklist.
- **Caveats, honestly:** identity is per-Mac (export/import in Phase 7 covers laptop migration); no
  passwords exist, so nothing to reset. Right-sized for 15 people who know each other.

---

## 7. Movement & game sync design

- **Tick:** host's `SimActor` integrates the world at **15 Hz** and sends compact, versioned binary
  snapshots over QUIC datagrams (through the relay).
- **Client prediction (self):** clients simulate their own avatar with the *same* `ClusterProtocol`
  math for zero input latency; host validates (speed clamp, bounds, tile collision sampling) and
  corrects only on real divergence.
- **Interpolation (others):** remote players render ~100–150 ms in the past, lerping buffered
  snapshots. Pure math, unit-tested — the "feels like Gather, not teleporting robots" line.
- **Reliability split:** movement/voice = datagrams; joins, desk edits, status, lap results = streams.
- **Reconnection:** auto-retry with backoff, resume by identity key; host restart mid-session reloads
  the world from SQLite and clients rejoin cleanly (positions reset to spawn — acceptable). Host quit
  shows a clean "session ended" screen (Phase 2 exit test).

---

## 8. Voice design (voice only — and the honest hard part)

No LiveKit safety net: voice is built from parts, made feasible because **Apple ships the hard DSP**
(voice-processed I/O = echo cancellation, noise suppression, AGC).

1. **Capture:** AVAudioEngine input, voice processing on → 48 kHz mono, 20 ms frames.
2. **Encode:** Opus ~32–48 kbps, sequence numbers + timestamps; silence not transmitted (mic gating
   doubles as the speaking indicator).
3. **Transport:** QUIC datagrams to the host (via relay).
4. **Fan-out (host as micro-SFU):** the host never decodes or mixes — it forwards each speaker's
   packets only to receivers within earshot (proximity subscription from room state).
5. **Playback:** per-speaker player nodes behind a small adaptive jitter buffer (~60–100 ms); Opus PLC
   fills gaps; per-speaker volume = proximity fade (≤5 tiles full, 5→10 fade, >10 unsubscribed).

**Controls:** mute + push-to-talk option, input device picker, speaking rings, connection-quality
badge. **DND** force-mutes the mic and pauses subscriptions (§9).

**Risk containment:** the voice phase is allowed two prompts; voice is "just datagrams" to the
protocol, so vendoring a WebRTC audio engine behind the same interface is the documented fallback.

---

## 9. Status & presence

- **Presence (ephemeral):** online-in-world / away / offline; `last_seen_at` persisted by the host on
  disconnect ("last seen 2h ago").
- **Status (user-set):** `available` · `focus` · `dnd` — sidebar control + global hotkey, nameplate
  badge + roster dot, persisted per player. *focus* = visual heads-down signal, voice unaffected;
  *dnd* = mic force-muted + incoming audio paused.
- **Auto-away:** 5 minutes without input → away (dimmed avatar); any input returns.
- **Roster sidebar:** all known players (online first) with avatar, status, last seen — the "glance and
  know who's around" feature.

---

## 10. Desk personalization

- **Claiming:** desks are zones in the Tiled map; self-serve claim (one per player) and release; owner
  nameplate on hover.
- **Editor:** SwiftUI palette (catalog with previews) + SpriteKit placement — drag in, snap-to-grid
  ghost clamped to your desk's bounds, move/rotate/remove. Reliable stream to host → SQLite →
  `deskUpdated` broadcast, live for everyone.
- **Parked:** custom image uploads, unlockables, seasonal items.

---

## 11. Go-karts 🏎️

- **Mount/dismount:** spawn pads in the map; press `E`. Movement swaps to kart kinematics —
  acceleration curve, top speed, momentum, drift/handbrake on `Space` — with skid-mark particles,
  engine loop, horn.
- **Tuning is content:** all handling params in one constants file in `ClusterProtocol`, pinned by sim
  tests; "kart feels wrong" is a constants PR.
- **Claim lock:** host-side first-claim-wins per kart, released on dismount/disconnect.
- **Sync:** same predict/validate/interpolate pipeline as walking — karts are fast avatars with
  different math.
- **The track:** loop around the mansion grounds, checkpoints → host-validated lap timer →
  `kart_lap_times` → leaderboard UI. Friday time-trials are the retention feature.
- **Parked:** kart skins, boost pads, ghost replays.

---

## 12. Data on the host (GRDB / SQLite)

| Table | Purpose |
|---|---|
| `players` | public key, display name, avatar preset, status pref, `last_seen_at`, approved/blocked |
| `space` | single row: world name, map version, rotating invite secret, settings |
| `item_catalog` | ~20 seeded desk items (plants, monitors, rugs, posters, desk pets, lava lamp, trophy shelf) |
| `desks` | map zone id, `owner_player_id` (nullable), name |
| `desk_items` | desk, catalog item, x/y, rotation, layer |
| `kart_lap_times` | player, track id, time ms, recorded at |

Ephemeral state (positions, kart claims, who's online) lives in room memory and evaporates. Backups:
Time Machine by default + **Export World** button (Phase 7) with a timed restore drill.

---

## 13. Content prerequisites (folded into Phase 2)

- **Art licensing:** LimeZu *Modern Interiors* (the Gather look) needs its paid license; Kenney is
  CC0. Every asset's source + license in `assets/LICENSES.md` from day one.
- **The mansion map:** Tiled, with named zones — spawn, ≥15 desk zones, hangout areas, and the kart
  loop + checkpoints reserved in the layout so Phase 6 needs no map surgery.

---

## 14. Roadmap — one phase per prompt

Say **"do Phase N"**; this document is the spec.

| Phase | Work order | Definition of done |
|---|---|---|
| **0 — Foundation** | Xcode project + four SPM packages + relay executable skeleton; SwiftUI shell (Host/Join stubbed); identity keypair + Keychain; GRDB + first migration; CI (macOS app job, Linux relay job); release script (sign → notarize → TestFlight) + runbook. *Needs from you: Apple Developer Program ($99/yr); all-Mac confirmation.* | Signed, notarized build installs on a teammate's Mac via TestFlight; both CI jobs green |
| **1 — Relay, host & join** | `cluster-relayd` (control plane: register/lookup/introduce over TLS; data plane: pair splicing — UDP flows land in Phase 2 per ADR 0001); provision VPS + Docker deploy workflow + relay runbook; app pins relay IP + cert; session codes; end-to-end tunnel handshake (secret, identity, profile, knock/approve); lobby roster; clean disconnects; **Connectivity Doctor** (relay reachability, UDP-blocked detection) — **run from your work WiFi on day one**; if UDP is blocked there, build the TCP-443 fallback in this phase. *Needs from you: Hetzner account (~$5/mo); 30 min on work WiFi for the reachability test.* | You host from work WiFi; a coworker on another network joins with a 6-char code; both lobbies show the roster; Doctor explains any failure in plain language |
| **2 — Walkable mansion** | Art + `LICENSES.md`; mansion map (Tiled JSON) + Swift importer; SpriteKit `WorldScene`; 15 Hz sim; prediction + validation + interpolation (§7); nameplates; camera; graceful host-quit and rejoin; **relay UDP flows + sealed datagrams + per-player TCP fallback with a user-facing Automatic/TCP-only toggle in Settings → Connection (ADR 0002)** | Three Macs on different networks walk the mansion smoothly — including one forced to TCP-only; killing the host app gives clients a clean "session ended"; rehosting lets them rejoin |
| **3 — Voice** *(allowed two prompts)* | `ClusterVoice` per §8: voice-processed capture, Opus, datagrams via relay, host proximity fan-out, jitter buffer + PLC, proximity volume, mute/PTT, device picker, speaking rings | Full-team meeting in-app, echo-free on laptop speakers, including one member on bad hotel wifi |
| **4 — Status & presence** | Roster sidebar; presence + `last_seen_at`; available/focus/DND with badges, hotkey, persistence; DND voice behavior; auto-away (§9) | A teammate opens the app and knows in 5 seconds who's around and who's interruptible |
| **5 — Desks** | Claim/release; catalog seed; SwiftUI palette + SpriteKit ghost/snap editor; host persistence + live broadcast (§10) | Every member decorates a desk; decorations survive host restarts and appear live to others |
| **6 — Go-karts** | Spawn pads + claim locks; kart kinematics + tuning constants (sim-tested); mount/dismount; skids/engine/horn; checkpoints + lap timer; leaderboard (§11) | First team time-trial tournament runs, standings on the leaderboard 🏁 |
| **7 — Rock-solid pass** | Chaos drills: host force-quit/relaunch, client wifi drops, host-Mac sleep handling, **relay reboot mid-session** (apps must auto-resume); menu-bar host mode + sleep prevention; Export World + timed restore; identity export/import; kick + blocklist; energy/memory over a 4-hour session; runbooks (relay ops, release, restore, incident) | "Bad wifi Friday" checklist passes; relay reboot doesn't end the party; restore drill has a real timing; the app hosts a workday from the menu bar without waking the fans |

Sequencing: 1→2→3 build on each other; 4, 5, 6 depend only on 2 (karts may jump the queue —
sanctioned). After Phase 7: backlog items (§16), one per prompt, same contract.

---

## 15. Dev workflow

- **Project setup & IDE split:** the app target is created once from Xcode's plain **macOS → App**
  template (SwiftUI lifecycle) — *not* the Game template, whose SpriteKit scaffold fights our
  Tiled-based setup — using synchronized folders, so adding files never churns the project file.
  ~90% of code lives in the local SwiftPM packages (file-based, `swift build`/`swift test` from the
  CLI). Day-to-day code is written via Claude Code against this repo (terminal or VS Code, same
  thing); Xcode stays open as the run/debug surface — SwiftUI previews, SpriteKit debugging,
  Instruments, Network Link Conditioner for the bad-wifi drills, and the one-time signing/TestFlight
  setup that requires the Apple ID GUI.
- **Local dev:** relay + two app instances on one Mac (relay runs natively or in Docker); Xcode
  previews for UI; seed script for catalog + fake players.
- **Branching:** GitHub flow; `main` always shippable; squash merges; conventional commits; tags drive
  TestFlight releases (changelog = patch notes).
- **CI:** app job on macOS runner (10× minute multiplier — keep lean; self-hosted runner on the host
  Mac if minutes pinch); relay job on cheap Linux runners.
- **Deploys:** relay = Docker image + SSH deploy on merge (stateless: deploys are fearless); app =
  `scripts/release.sh` → notarize → TestFlight, testers auto-update.
- **Playtest ritual:** the team is QA; feedback → GitHub issues (`bug`, `feature`, `kart-feels-wrong`).

---

## 16. Backlog (parked, in rough value order)

1. Text chat (nearby + space-wide; persists in host DB)
2. Private audio zones (meeting rooms — zone-scoped voice)
3. Peer-to-peer fast path (hole punching, relay as fallback — lower latency, less relay bandwidth)
4. Emotes & reactions (wave, dance, confetti, raise hand)
5. Interactive objects (shared whiteboard link, jukebox)
6. Avatar customization layers (paper-doll)
7. iOS join-only client (shared packages make this mostly UI)
8. Host migration / second-host world import (Export World exists from Phase 7)
9. Minimap + locate/follow a teammate
10. Custom desk-item uploads
11. Kart skins, boost pads, ghost replays
12. Video tiles (only if ever truly wanted)
13. Productization: sell the app; teams bring their own host Mac; our relay becomes the one shared
    service (cheap to scale — it's stateless packet forwarding), or iroh-style per-team relays

**Cut (not planned):** screen sharing; Windows/Linux clients.

---

## 17. Working agreement (how phases get executed)

- One prompt = one phase (Phase 3 may take two). Implement to the definition of done, verify with local
  instances + real-network checks where the phase demands them, update runbooks + changelog, leave
  `main` shippable.
- Each phase assumes the previous ones merged. When reality diverges mid-phase, the plan gets amended
  in the same PR — this document stays the source of truth.
- Decisions in §2–§13 don't get re-litigated inside a phase; new decisions get a one-line ADR in
  `docs/adr/`.

---

## 18. Risks & mitigations

1. **DIY voice is the hardest part.** → Apple's voice-processed I/O supplies the DSP; Opus PLC +
   jitter buffer are well-trodden; double phase budget; WebRTC-audio-behind-the-same-interface is the
   documented fallback.
2. **UDP blocked on the host's work network.** → Tested in Phase 1, day one, from that exact WiFi;
   TCP-443 fallback gets built immediately if needed instead of waiting in the backlog.
3. **Relay is a single point of failure.** → It's stateless and disposable: Docker redeploy in
   minutes, apps auto-reconnect (Phase 7 chaos drill), worst case is a short outage — never data loss.
4. **Room uptime = host Mac uptime.** → Menu-bar hosting + sleep prevention; host migration is backlog
   item 8; accepted by design otherwise.
5. **All-Mac team assumption.** → Confirm before Phase 0 — the one assumption the plan stands on.
6. **Apple-platform friction** (notarization, TestFlight review). → $99/yr program + scripted release
   path from Phase 0 so distribution never blocks a Friday.
7. **No staging — the host's world is production.** → Export World before risky upgrades; migrations
   tested against a copied DB in CI.
8. **Asset licensing.** → `assets/LICENSES.md`, audited before any commercial use.
9. **Scope creep.** → §16 parked by agreement; core first.
10. **Solo-dev burnout.** → Phases land in one prompt each and end in something the team feels; karts
    may jump the queue, sanctioned.

---

## 19. Costs

| Item | Cost |
|---|---|
| Relay VPS (Hetzner CX22/CAX11, static IP, 20 TB traffic) | **~$4.50–5.50/mo** |
| Apple Developer Program (signing, notarization, TestFlight) | $99/yr (**~$8.25/mo**) |
| Domain | **$0 — none needed** (app pins the relay's static IP + cert fingerprint) |
| Databases, media services, web hosting | $0 — none exist |
| One-time: art licenses (tileset + avatars) | ~$20–60 |
| **Total recurring** | **~$13–14/mo** |

Penny-pinching option: Oracle Cloud's always-free ARM tier can host the relay for $0 (total ≈ $8.25/mo),
at the cost of occasional reclamation/reliability jank — fine to try, easy to move off (the relay is
one stateless container).
