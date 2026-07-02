# Runbook — The "bad wifi Friday" checklist

The Phase 7 exit criterion: a session should survive a normal day of real-world
failure. Everything here is either automated (✓ CI) or a 2-minute manual check.

## Pre-flight (host, ~2 minutes, before the team arrives)

1. **Relay up?** Settings → Run Connectivity Doctor → all green.
   (From the office: the UDP row may be ⓘ — that's fine, TCP fallback covers it.)
2. **World backed up?** Settings → Export World… (or `scripts/drill-restore.sh`
   verifies the file; last drill: 4.6 s end-to-end).
3. **Host & Play → code** → paste the code in the team chat.
4. Optional: close the window — the menu-bar house icon keeps hosting, and the
   Mac won't idle-sleep while the session is up.

## What failure looks like when it's working (all ✓ CI chaos drills)

| Event | Expected behavior |
|---|---|
| A member's wifi drops | They vanish from the world within seconds; their kart parks itself; roster updates. They rejoin with the same code. |
| The host app crashes / force-quits | Everyone gets a clean "session ended" — no hang. Relaunch, Host & Play, share the **new** code. Desks, laps, and approvals are all still there. |
| Someone's network blocks UDP | They silently ride the TCP fallback (orange badge). Nothing to do. |
| Someone needs removing | Roster sidebar → right-click → Kick (or Block to refuse them permanently). |
| The relay VPS dies | Everyone drops. Redeploy per docs/runbooks/relay.md (~10 min, no data on it to lose), update Settings if the cert changed. |

## Long-session health (manual, once)

Host a session for a workday with the window closed. In Activity Monitor,
Project Cluster should sit at low single-digit CPU while idle (15 Hz tick +
voice when someone talks) with flat memory. If memory climbs steadily over
hours, file a bug with the Activity Monitor screenshot.

## If someone can't join — in order

1. Their Settings → relay address + fingerprint match yours? (Doctor tells them.)
2. Is your session up? (Menu-bar icon present, code correct — codes change per session.)
3. Their app version = your version? (Wire-version mismatch is refused with a clear message.)
4. Blocked? Your roster context menu can't unblock yet — see docs/runbooks/incident.md.
