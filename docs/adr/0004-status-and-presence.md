# ADR 0004 — Status & presence: host-derived, roster carries everyone

**Date:** 2026-06-13 · **Status:** accepted · **Phase:** 4

## Context

PLAN §9 / Phase 4: a roster sidebar of *all known players* (online first, with
status + last-seen), user-set status (available / focus / DND), auto-away, and
DND that mutes voice both ways.

## Decisions

1. **Status is user-set, presence is derived.** Three user statuses
   (`available` / `focus` / `dnd`) persist per player in the world DB. Presence
   (online / away / offline) is computed, never set: *online* = connected,
   *away* = no input or voice for `PresenceRules.autoAwaySeconds` (300 s),
   *offline* = not connected (shown from the DB with last-seen).
2. **The host owns presence.** It already tracks `lastInputAt`; Phase 4 widens
   that to `lastActivityAt` (movement **or** voice **or** a status change). The
   tick recomputes away flags and rebroadcasts the roster on any change. One
   authority, no client clock-skew games — same stance as movement (PLAN §7).
3. **The roster carries the whole team.** Online members (live status/away)
   are merged with offline known players pulled from the DB (stored status,
   last-seen). Pure `RosterBuilder.build` does the merge+sort (online first,
   then away, then offline by recency) so it's unit-tested.
4. **DND mutes voice at both layers.** Client: DND force-mutes the mic and
   silences playback. Host (defense in depth): `fanOutVoice` drops a DND sender
   and skips a DND receiver, so a misbehaving client can't leak audio.
5. **Wire version → 3.** `RosterEntry` gained status/away/last-seen and a new
   `setStatus` session message exists. Host and joiners update together.

## Consequences

- The roster grows with everyone who has ever joined — fine at team scale; a
  retention/affordance question for the productization phase, not now.
- `HostDirectory` grows `allKnownPlayers()` and `saveStatus()`; the in-memory
  test double and the GRDB adapter both implement them.
