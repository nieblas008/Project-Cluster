# ADR 0006 — Go-karts: arcade kinematics, host-owned claims, authoritative laps

**Date:** 2026-07-02 · **Status:** accepted · **Phase:** 6

## Context

Karts are the project's founding must-have (PLAN §9). They need: momentum-based
driving that feels different from walking, exclusive kart ownership, wall
collisions that are satisfying rather than sticky, and a lap timer trustworthy
enough to hang a team tournament on.

## Decision

1. **Pure arcade kinematics in `ClusterProtocol` (`KartSim`).** Velocity always
   points along the heading (no lateral slip simulation): throttle integrates
   speed against `KartTuning`'s acceleration/braking/coast-drag; steering rate
   scales with speed (no turning at standstill) and reverses with reverse gear;
   the handbrake ("drift") multiplies turn rate and drag instead of modeling
   grip — long slides, simple math, fully unit-tested. Wall hits scrub speed to
   ~30% (satisfying thunk, no wall-riding exploit). Same function runs as
   client prediction and host validation, like walking.
2. **Karts are world furniture with a claim lock.** Map objects (`type:
   "kart"`) define pads; the host tracks assignments — mount requires the kart
   free, the player kart-less and within reach; dismount (or disconnect) parks
   the kart where the driver stood. Full `raceState` (assignments + parked
   poses + leaderboard) broadcasts on change, desk-style.
3. **Laps are host-clocked.** Checkpoint zones (`cp-0…cp-3`, `cp-0` =
   start/finish) feed a pure `LapTracker` (in order, no shortcuts, no
   re-triggers); the host runs one per karted player on *validated* positions
   and its own clock, so lap times can't be forged by a fast client. Times
   persist via a `LapStore` (SQLite migration v3) keyed by identity; the
   leaderboard is best-per-player.
4. **Wire v5**: snapshots gain `mode` (kart/drift bits) + `heading`; inputs
   gain a drift flag; new `raceCommand` / `raceState` / `lapCompleted` /
   `raceEvent` (horn) messages.
5. **Feel:** one top-down kart sprite per avatar color rotated to the live
   heading, skid dots while drifting, generated engine/horn/skid audio, camera
   zooms out in a kart. `E` mounts/dismounts, `Space` drifts, `H` honks.

## Consequences

- "The kart feels wrong" stays a constants PR against `KartTuning.standard`.
- Client-authoritative positions remain (PLAN §7) — but lap *times* are host
  truth, which is what the tournament needs; full server physics stays parked.
- Parked-kart positions are session state, not persisted: a fresh session
  lines karts back up at their pads (tournament-friendly reset).
