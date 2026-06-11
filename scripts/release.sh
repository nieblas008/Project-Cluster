#!/usr/bin/env bash
# Archive, sign, and upload Project Cluster to App Store Connect (TestFlight).
#
# Prerequisites (one-time): docs/runbooks/release.md
# Usage: scripts/release.sh
#
# Signing uses the Apple ID logged into Xcode (automatic signing +
# -allowProvisioningUpdates). CI/keyless use can pass an App Store Connect API
# key via ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH instead.

set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="Project Cluster"
ARCHIVE_PATH="build/ProjectCluster.xcarchive"
EXPORT_PLIST="deploy/ExportOptions.plist"

echo "==> Archiving ${SCHEME} (Release)"
xcodebuild archive \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "${ARCHIVE_PATH}" \
    -allowProvisioningUpdates

AUTH_ARGS=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
    AUTH_ARGS+=(
        -authenticationKeyID "${ASC_KEY_ID}"
        -authenticationKeyIssuerID "${ASC_ISSUER_ID}"
        -authenticationKeyPath "${ASC_KEY_PATH}"
    )
fi

echo "==> Uploading to App Store Connect (TestFlight)"
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportOptionsPlist "${EXPORT_PLIST}" \
    -allowProvisioningUpdates \
    "${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}"

echo "==> Uploaded. Processing takes a few minutes in App Store Connect;"
echo "    testers get the update from TestFlight automatically."
