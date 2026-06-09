#!/bin/bash

set -euxo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <output_path> <team_id> <app_profile_uuid>"
  exit 1
fi

OUTPUT_PATH="$1"
TEAM_ID="$2"
APP_PROFILE_UUID="$3"

PROJECT="DiscogsPicker.xcodeproj"
SCHEME="DiscogsPicker"
BUNDLE_ID="com.dancrosby.discogspicker"
ARCHIVE_PATH="$OUTPUT_PATH/DiscogsPicker.xcarchive"
EXPORT_PATH="$OUTPUT_PATH/export"
EXPORT_OPTIONS_PATH="$OUTPUT_PATH/ExportOptions.plist"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
SIGN_IDENTITY="${IOS_SIGN_IDENTITY:-Apple Distribution: Daniel Crosby (UWJ88DX8WQ)}"

mkdir -p "$OUTPUT_PATH" "$EXPORT_PATH"

xcodebuild -resolvePackageDependencies \
  -project "$PROJECT" \
  -scheme "$SCHEME"

WWDR_CERT="$OUTPUT_PATH/AppleWWDRCAG3.cer"
curl -L "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer" -o "$WWDR_CERT"
sudo security import "$WWDR_CERT" -k /Library/Keychains/System.keychain -T /usr/bin/codesign || true
security list-keychains -d user -s $(security list-keychains -d user | sed s/\"//g) /Library/Keychains/System.keychain

xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PROVISIONING_PROFILE_SPECIFIER="$APP_PROFILE_UUID"

cat > "$EXPORT_OPTIONS_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>uploadSymbols</key>
  <true/>
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

AUTH_ARGS=()
if [ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]; then
  AUTH_ARGS=(
    -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH"
    -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID"
    -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"
  )
fi

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
  "${AUTH_ARGS[@]}"

IPA_PATH=$(find "$EXPORT_PATH" -type f -name "*.ipa" -print -quit)
if [ -z "$IPA_PATH" ]; then
  echo "No IPA was exported."
  exit 1
fi

echo "Exported IPA: $IPA_PATH"
