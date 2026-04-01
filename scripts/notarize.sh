#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="CCMissionControl"
SCHEME="CCMissionControl"
ARCHIVE_PATH="$PROJECT_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$PROJECT_DIR/export"
EXPORT_OPTIONS="$PROJECT_DIR/exportOptions.plist"
ZIP_PATH="$PROJECT_DIR/$APP_NAME.zip"

API_KEY="${NOTARIZE_API_KEY:?Set NOTARIZE_API_KEY}"
API_ISSUER="${NOTARIZE_API_ISSUER:?Set NOTARIZE_API_ISSUER}"

echo "==> Archiving..."
xcodebuild archive \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  | tail -1

echo "==> Exporting..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  | tail -1

echo "==> Creating zip..."
ditto -c -k --keepParent "$EXPORT_PATH/$APP_NAME.app" "$ZIP_PATH"

echo "==> Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --key "${NOTARIZE_API_KEY_PATH:?Set NOTARIZE_API_KEY_PATH}" \
  --key-id "$API_KEY" \
  --issuer "$API_ISSUER" \
  --wait

echo "==> Stapling..."
xcrun stapler staple "$EXPORT_PATH/$APP_NAME.app"

echo "==> Done! Notarized app is at: $EXPORT_PATH/$APP_NAME.app"
