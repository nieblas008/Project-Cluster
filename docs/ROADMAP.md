# Project Cluster — Roadmap

**Updated:** 2026-07-02 · **Current version:** v0.1.0-alpha

The plan ([docs/PLAN.md](PLAN.md)) describes the *design*. This describes
**what to do next**, in order. Start at the top and work down.

---

## Where you are right now

The whole core product is **built and machine-verified**: identity, host & join
by code through an encrypted relay, the walkable mansion, proximity voice,
status & presence, personal desks, and go-karts with a lap leaderboard.
131 unit tests, a full-product end-to-end smoke on both transports, and five
chaos drills run on every commit.

**But it has never been used by a human other than you, on one Mac.**

That's the single most important fact on this page. Everything below is ordered
around it.

```
        BUILT ✅                    UNVALIDATED ⚠️              NOT BUILT ⬜
   ┌──────────────────┐      ┌──────────────────────┐    ┌─────────────────┐
   │ 7 phases of      │      │ Real relay on a VPS  │    │ Emotes, minimap │
   │ features         │ ───▶ │ Two real Macs        │──▶ │ chat, meeting   │
   │ 131 tests, CI    │      │ Voice in human ears  │    │ rooms, …        │
   │ chaos drills     │      │ TestFlight delivery  │    │                 │
   └──────────────────┘      └──────────────────────┘    └─────────────────┘
                              ↑ YOU ARE HERE
```

---

## Track A — Get it into your team's hands

**Do this before building anything new.** Every feature you add before this is
built on assumptions no human has tested. The riskiest unknown in the entire
project — *does the voice actually sound good between two real Macs?* — can
only be answered here.

| # | Step | Size | Needs from you | Unblocks |
|---|---|---|---|---|
| **A1** | **Deploy the relay VPS** — [docs/runbooks/relay.md](runbooks/relay.md) | ~15 min | Hetzner account (~$5/mo) | Everything below |
| **A2** | **Run the Connectivity Doctor from your work WiFi** — Settings → Doctor | ~2 min | A1 | Answers the outbound-UDP question the architecture was designed around |
| **A3** | **Draw an app icon** — any 1024×1024 PNG into the asset catalog | ~30 min | Taste | A4 (App Store Connect rejects builds without one) |
| **A4** | **App Store Connect + first TestFlight upload** — [docs/runbooks/release.md](runbooks/release.md) | ~1 hr first time | Apple Developer enrollment ($99/yr), A3 | Teammates can install |
| **A5** | **First two-Mac session with one coworker** | ~30 min | A1 + A4 | **The real test**: echo cancellation, latency, whether it feels good |
| **A6** | **First team Friday + kart tournament** 🏁 | one Friday | A5 | The reason this project exists |

### What to watch for in A5 (the one that matters)

Sit with a coworker and check, in this order:

1. **Can they join at all?** (Doctor is green on both ends, code pasted, knock approved)
2. **Echo** — both on laptop speakers, no headphones. This is the thing no test can fake. If there's echo, that's a real bug and worth a session to fix.
3. **Latency** — does conversation feel natural or walkie-talkie?
4. **Proximity** — walk away mid-sentence; does the fade feel right, or too abrupt/too slow?
5. **The gate** — does it clip the start of your words? (Tunable: `VoiceFormat.gateThreshold`)

Whatever you find here becomes the next work item, ahead of any feature below.

---

## Track B — Features, in recommended order

All of these are one focused session each unless noted. **Pick based on what
your team actually asks for after Track A** — this order is my recommendation,
not a commitment.

| # | Feature | Size | Why here | State |
|---|---|---|---|---|
| **B1** | **Emotes** 👋🎉 — wave/dance/party/raise-hand/heart with a key press | 1 session | Cheapest joy-per-line in the backlog; pure Friday fuel. Reuses the horn's transient-broadcast path. | **Designed** — [ADR 0007](adr/0007-emotes-and-minimap.md) |
| **B2** | **Minimap** — toggle a corner map with a dot per person | ½ session | Zero protocol risk (data already arrives in every snapshot); makes a 44×30 world navigable | **Designed** — [ADR 0007](adr/0007-emotes-and-minimap.md) |
| **B3** | **Private audio zones** — meeting rooms where only the room hears you | 1 session | The single highest-value feature for *actual work*. Gather's killer feature. Makes a real workday viable, not just Fridays. | Planned |
| **B4** | **Text chat** — nearby + space-wide, persisted | 1 session | The most-requested thing in every virtual office; also the natural home for links | Planned |
| **B5** | **Avatar customization** — body/hair/outfit layers | 1–2 sessions | Identity and delight; needs an art pass more than engineering | Planned |
| **B6** | **Interactive objects** — shared whiteboard link, jukebox | 1 session | High delight, low mechanism (a zone + an overlay) | Planned |
| **B7** | **Short 6-char codes via CloudKit** — no more 30-char pastes | 1 session | Only matters when non-technical people join often | Planned |
| **B8** | **Kart extras** — skins, boost pads, ghost replays | 1 session | Pure fun; do it when the tournament gets competitive | Planned |
| **B9** | **iOS join-only client** | 2–3 sessions | The shared packages already compile for iOS; it's mostly UI | Planned |

**If you want one recommendation:** do **B1 + B2 together** in one session
(they're both small and both designed already), *then* **B3** — because private
audio zones are what turn this from "a fun Friday thing" into "where we work."

---

## Track C — Only if this becomes a product

Not needed for your team. Listed so you know it's thought about.

- Multi-space per account, space templates, in-app map editor
- Billing (Stripe), ToS/privacy, moderation at scale, rate limiting
- Video tiles, screen share (explicitly cut from v1 scope)
- Host migration / world handoff between Macs

---

## Known rough edges (documented, not blocking)

These are honest gaps in v0.1.0-alpha. None break a Friday; all have workarounds.

| Edge | Workaround | Fix size |
|---|---|---|
| No **unblock** UI | SQL one-liner in [incident runbook](runbooks/incident.md) | ~20 min |
| No **desk reassignment** for absent players | Same runbook | ~20 min |
| Clients must **rejoin manually** after a host restart (no auto-reconnect) | Share the new code | ~1 session |
| **Placeholder art** — clean but flat | Regenerate via `scripts/generate-assets.swift`, or buy a tileset (see [LICENSES](../assets/LICENSES.md)) | art pass |
| **Identity import** needs an app relaunch to fully apply | Relaunch | ~30 min |

---

## How to work on this

The rhythm that's worked so far, unchanged:

1. Say **"do B1"** (or whatever's next) — one item per session.
2. I read the relevant ADR/plan section, build it, and verify with the real
   suite (lint → 131+ tests → app build → smoke on both transports → chaos).
3. It ships to `main` green, with a changelog entry.

Before any session, if you've been away: **"review where we are"** and I'll
re-verify everything and re-read this file.

### The commands you actually need

```sh
# Terminal 1 — relay (leave running)
scripts/dev-relay.sh

# Terminal 2 — two app instances for solo testing
scripts/dev-playtest.sh

# Verify everything
scripts/itest-phase1.sh     # full product, both transports
scripts/itest-chaos.sh      # five failure drills
scripts/drill-restore.sh    # timed backup/restore
```
