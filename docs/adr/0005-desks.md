# ADR 0005 — Desks: host-authoritative claims + placements, static catalog

**Date:** 2026-06-13 · **Status:** accepted · **Phase:** 5

## Context

PLAN §10 / Phase 5: claim a desk (a map zone), decorate it from an item
catalog, persist it, and broadcast changes live. The mansion map already
defines 16 `desk` zones (each with tile bounds).

## Decisions

1. **The item catalog is static content, not a DB table.** ~20 items live in
   `ItemCatalog` (ClusterProtocol) — id, name, category, sprite index, size.
   Sprites ship in `items.png` (generated, like tiles/avatars). Simpler than a
   seeded table and versioned with the app; a user-content catalog is a
   productization concern, not now.
2. **The host is authoritative over desks**, same stance as movement/voice.
   Joiners send `DeskCommand` (claim / release / place / remove / move); the
   host validates (one desk per player; placements clamped inside the claimed
   desk's map-zone bounds; you may only edit your own desk), persists to SQLite,
   then broadcasts the full `DeskState`. Pure `DeskRules` does the geometry so
   it's unit-tested.
3. **Full-state broadcast, not deltas.** 16 desks × a handful of items is tiny;
   sending the whole `DeskState` on every change is simplest and self-healing
   (no delta drift). Initial state rides `welcome`.
4. **Persistence.** Two tables: `desk_claims` (zone → owner) and `desk_items`
   (id, zone, catalog id, x, y, rotation). Survive restarts; an unclaimed desk
   keeps its items until reclaimed/cleared (a released desk's items are removed,
   matching "your desk").
5. **Wire version → 4.** `deskState` + `deskCommand` messages added; `welcome`
   carries the initial desk state.

## Consequences

- Item ids are host-assigned (monotonic, persisted) so remove/move reference a
  stable handle.
- The editor is client-side convenience; all authority and validation are on
  the host, so a misbehaving client can't place outside its desk or edit
  someone else's.
