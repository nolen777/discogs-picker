#!/bin/bash

set -euxo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <xcarchive_path> <team_id> <app_profile_uuid>"
  exit 1
fi

ARCHIVE_PATH="$1"
TEAM_ID="$2"
APP_PROFILE_UUID="$3"

BUNDLE_ID="com.dancrosby.discogspicker"
EXPORT_PATH="$(dirname "$ARCHIVE_PATH")/upload"
EXPORT_OPTIONS_PATH="$(dirname "$ARCHIVE_PATH")/UploadExportOptions.plist"
SIGN_IDENTITY="${IOS_SIGN_IDENTITY:-Apple Distribution: Daniel Crosby (UWJ88DX8WQ)}"

if [ -z "${APP_STORE_CONNECT_API_KEY_PATH:-}" ] || [ -z "${APP_STORE_CONNECT_API_KEY_ID:-}" ] || [ -z "${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]; then
  echo "App Store Connect API key environment variables are required."
  exit 1
fi

mkdir -p "$EXPORT_PATH"

cat > "$EXPORT_OPTIONS_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>upload</string>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>$SIGN_IDENTITY</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>$BUNDLE_ID</key>
    <string>$APP_PROFILE_UUID</string>
  </dict>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
  -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"
