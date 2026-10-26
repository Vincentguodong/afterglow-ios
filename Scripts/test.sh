#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This test requires a Mac with Xcode and an iOS simulator." >&2
  exit 1
fi
destination="${SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro Max}"
xcodebuild -project Afterglow.xcodeproj -scheme Afterglow \
  -destination "$destination" -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
