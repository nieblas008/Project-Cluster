# Project Cluster

My own little version of Gather so I can use it with my cool coworkers — a native macOS app,
written in Swift: a 2D mansion where the team walks around as avatars, talks over proximity voice
chat, personalizes desks, and races go-karts. One member **hosts** the session on their own Mac —
the world's data lives there — and everyone else **joins with a short code** through a tiny
stateless relay.

**Status: v0.1.0-alpha — the full core scope is built and CI-verified**: identity,
host & join by code, the walkable mansion, proximity voice, status & presence,
personal desks, and go-karts with a lap leaderboard. The design, roadmap, and
backlog live in [docs/PLAN.md](docs/PLAN.md).

## Controls

| Key | Action |
|---|---|
| WASD / arrows | Walk (steer + throttle in a kart) |
| E | Mount / dismount a kart |
| Space | Handbrake — drift |
| H | Horn 📯 |
| ⌥ Option (hold) | Push-to-talk (when enabled in Settings) |
| ⌃1 / ⌃2 / ⌃3 | Status: Available / Focus / Do Not Disturb |
| Click (decorate mode) | Place / remove desk items |
| Right-click a roster row | Kick / Block (host only) |

## Layout

| Path | What |
|---|---|
| `Project Cluster/` + `Project Cluster.xcodeproj` | The app (SwiftUI shell, later SpriteKit world) |
| `Packages/ClusterProtocol` | Shared core: wire codec, sim math, tuning — platform-free |
| `Packages/ClusterNet` | Identity (Keychain), later relay client + QUIC transport |
| `Packages/ClusterServer` | Host role: world database (GRDB), later the 15 Hz sim |
| `Packages/ClusterVoice` | Voice format, later capture/Opus/jitter/playback |
| `Relay/` | `cluster-relayd` — stateless rendezvous + UDP relay (SwiftNIO, runs on Linux) |
| `deploy/` | Relay compose file, TestFlight export options |
| `docs/` | Plan, runbooks, ADRs |

## Development

```sh
# App: open in Xcode and run, or:
xcodebuild -scheme "Project Cluster" -destination "platform=macOS" build

# Package tests:
swift test --package-path Packages/ClusterProtocol   # (likewise ClusterNet/Server/Voice, Relay)

# Local relay (prints the fingerprint to paste into the app's Settings,
# address 127.0.0.1) — then run two app instances and host/join for real:
scripts/dev-relay.sh

# Full end-to-end check (relay + host + joiner + walking, both transports):
scripts/itest-phase1.sh

# Chaos drills (wifi drop, host crash, rehost, kick):
scripts/itest-chaos.sh

# Timed world backup/restore drill:
scripts/drill-restore.sh

# Regenerate art / the mansion map (outputs land in "Project Cluster/Resources"):
swift scripts/generate-assets.swift
swift scripts/generate-mansion.swift

# Lint:
swift format lint --strict --recursive Packages Relay "Project Cluster"
```

Relay VPS setup + operations: [docs/runbooks/relay.md](docs/runbooks/relay.md).
Releases go to the team via TestFlight: see [docs/runbooks/release.md](docs/runbooks/release.md).
