# Runbook — Releasing to TestFlight

## One-time setup

1. **Apple Developer Program** — the team (`L3NSFVB5U9`) must be enrolled ($99/yr).
2. **App record** — in [App Store Connect](https://appstoreconnect.apple.com): My Apps → **+** →
   New App → platform *macOS*, bundle ID `com.ricardonieblas.ProjectCluster`, any SKU.
3. **App icon** — App Store Connect rejects uploads without a filled `AppIcon` asset.
   Add icon images to `Project Cluster/Assets.xcassets/AppIcon.appiconset` before the first upload.
4. **Internal testing group** — App Store Connect → the app → TestFlight → Internal Testing →
   create a group, invite the team by Apple ID email. Testers install the **TestFlight app for Mac**
   (macOS 12+) and accept the email invite.
5. **Xcode account** — Xcode → Settings → Accounts → signed in with the enrolled Apple ID
   (needed for `-allowProvisioningUpdates`).

## Each release

1. Bump `CURRENT_PROJECT_VERSION` (build number — must increase every upload) and, when meaningful,
   `MARKETING_VERSION` in the target's build settings. Update `CHANGELOG.md`.
2. Run:
   ```sh
   scripts/release.sh
   ```
3. Wait for processing (App Store Connect → TestFlight tab, a few minutes). The first build of a new
   version may ask for export-compliance answers (uses standard encryption: yes / exempt).
4. Internal testers update automatically; patch notes = the changelog entry.

## Troubleshooting

- **"No signing certificate"** — Xcode → Settings → Accounts → Manage Certificates → + →
  Apple Distribution.
- **Upload rejected: missing icon** — see one-time setup step 3.
- **Build number already used** — bump `CURRENT_PROJECT_VERSION`.
- **CI / headless upload** — create an App Store Connect API key (Users and Access → Integrations),
  then run with `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` set; the script picks them up.
