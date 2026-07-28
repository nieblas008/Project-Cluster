# ADR 0007 — Emotes (transient broadcast) and the minimap (pure client)

**Date:** 2026-07-02 · **Status:** **proposed — designed, not yet built** ·
**Backlog items:** #3 (emotes), #8 (minimap)

> This ADR records the design so the work can start cold. No code exists yet;
> see docs/ROADMAP.md for where it sits in the queue.

## Emotes

Five kinds — 👋 wave, 🕺 dance, 🎉 party, ✋ raise hand, ❤️ heart — as
**transient events**, the horn's pattern: a client asks, the host stamps the
*verified* sender identity (no spoofing, same rule as voice), rate-limits
(≥0.4 s apart per player, silently dropped — no punishment for enthusiasm,
just no spam), and relays to everyone. Nothing persists; a raised hand is a
moment, not a state (a sticky hand-raise can layer on later via PlayerStatus
if wanted). Rendered as an emoji popping above the avatar's nameplate;
🎉 additionally bursts confetti particles. Sent with keys **1–5** or the HUD
emote bar. Wire version → 6.

## Minimap

Entirely client-side — the data already arrives in every snapshot. A small
HUD canvas (toggle **M**) draws the collision map scaled down, with a dot per
online player colored by avatar preset and a ring on yourself. No wire
changes, no host involvement, ~5 Hz redraw from the latest snapshot.

## Consequences

- Emotes reuse the sealed-tunnel relay path end to end; the relay still sees
  nothing.
- The minimap sets the pattern for future pure-view features: if the snapshot
  already carries it, the host never needs to know the UI exists.
