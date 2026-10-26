#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Archiving and TestFlight upload require macOS with Xcode." >&2
  exit 1
fi
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer Team ID.}"
: "${APP_BUNDLE_ID:?Set APP_BUNDLE_ID to your registered app Bundle ID.}"
if [[ "$APP_BUNDLE_ID" == com.example.* ]]; then
  echo "Replace the example Bundle ID with your own registered identifier." >&2
  exit 1
fi
mode="${1:---archive}"
if [[ "$mode" != --archive && "$mode" != --upload ]]; then
  echo "Usage: APPLE_TEAM_ID=... APP_BUNDLE_ID=... BUILD_NUMBER=... ./Scripts/release.sh [--archive|--upload]" >&2
  exit 1
fi
mkdir -p build
xcodebuild -project Afterglow.xcodeproj -scheme Afterglow -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Afterglow.xcarchive \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" archive
if [[ "$mode" == --upload ]]; then
  python3 - <<'PY'
import os, plistlib
with open('build/ExportOptions.plist', 'wb') as f:
    plistlib.dump({'method':'app-store-connect','destination':'upload',
                  'teamID':os.environ['APPLE_TEAM_ID'],'signingStyle':'automatic',
                  'uploadSymbols':True,'manageAppVersionAndBuildNumber':False}, f)
PY
  xcodebuild -exportArchive -archivePath build/Afterglow.xcarchive \
    -exportPath build/export -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates
  echo "Upload command finished. Check App Store Connect processing and TestFlight status."
else
  echo "Archive created. Open build/Afterglow.xcarchive in Xcode Organizer."
fi
