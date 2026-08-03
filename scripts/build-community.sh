#!/usr/bin/env bash
#
# Build, sign, notarize and package RDSM Community for direct download.
#
# This is the Community (free) pipeline — Developer ID + notarization, NOT the
# Mac App Store. Produces a notarized, stapled .zip ready to upload alongside a
# Sparkle appcast.
#
# Prerequisites (one-time):
#   1. A "Developer ID Application: <name> (<TEAMID>)" certificate in your keychain.
#   2. A notarytool keychain profile:
#        xcrun notarytool store-credentials "RDSM_NOTARY" \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "<app-specific-password>"
#   3. brew install xcodegen
#
# Usage:
#   scripts/build-community.sh [version]
#
set -euo pipefail

VERSION="${1:-}"
TEAM_ID="${TEAM_ID:-MZUPC2WYBN}"
NOTARY_PROFILE="${NOTARY_PROFILE:-RDSM_NOTARY}"
SCHEME="RDSMCommunity"
APP_NAME="RDSM Community"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/$SCHEME.app"
ZIP="$BUILD_DIR/RDSM-Community${VERSION:+-$VERSION}.zip"

echo "==> Generating Xcode project"
cd "$ROOT/app"
xcodegen generate --spec project.yml

echo "==> Archiving (Release)"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -project "$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  DEVELOPMENT_TEAM="$TEAM_ID"

echo "==> Exporting with Developer ID"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

echo "==> Zipping for notarization"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to notary service (this can take a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Re-zipping the stapled app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Verifying Gatekeeper acceptance"
spctl --assess --type execute --verbose=2 "$APP" || {
  echo "WARNING: spctl assessment failed — check signing/notarization." >&2
}

echo
echo "Done: $ZIP"
echo
echo "Next: generate/refresh the Sparkle appcast, e.g."
echo "  ./bin/generate_appcast \"$BUILD_DIR\"     # from the Sparkle distribution"
echo "then upload the .zip + appcast.xml to the download host."
