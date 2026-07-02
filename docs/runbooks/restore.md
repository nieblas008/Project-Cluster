# Runbook — World backup & restore

The world (desks, lap records, known players, approvals) is **one SQLite
file** on the host's Mac:

```
~/Library/Containers/com.ricardonieblas.ProjectCluster/Data/Library/Application Support/Project Cluster/world.sqlite
```

Time Machine covers it automatically. Belt-and-suspenders options:

## Backup
- **In-app:** Settings → World & Identity → Export World… (do it while not hosting).
- **Scripted:** `scripts/drill-restore.sh` — also verifies integrity both ways.
  Last executed drill (2026-07-02, real world file): **4.6 s** end-to-end.

## Restore (drilled)
1. Quit Project Cluster.
2. Copy the backup over the path above (create folders if missing).
3. Relaunch → Host & Play. Desks, laps, and approvals are back.
   Total time ≈ file copy + one app relaunch.

## Identity
Settings can also export/import your **identity key**. Treat the exported file
like a password: whoever holds it *is* you in every world that knows you.
Import on a new Mac, relaunch, and your desks/laps/approvals follow you.
