#!/bin/sh
# Builds a universal (Apple silicon and Intel) Release app, signs it with Flavio's
# Developer ID when that certificate is in the keychain (and notarizes it), or keeps
# the ad-hoc signature from Xcode when it isn't (CI and forks). Writes dist/<Name>-<version>.zip.
# Usage: scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
NAME="Number Pantry"
TARGET="Calculum"
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
BUILD="$ROOT/build/release"
APP="$BUILD/Release/$NAME.app"
ZIP="$ROOT/dist/Number-Pantry-$VERSION.zip"
CHECK=$(mktemp -d)

cleanup() {
  rm -rf "$CHECK"
}
trap cleanup EXIT

rm -rf "$BUILD" "$ZIP"
mkdir -p dist
xcodebuild -project "$TARGET.xcodeproj" -target "$TARGET" -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO SYMROOT="$BUILD" -quiet build

lipo "$APP/Contents/MacOS/$NAME" -verify_arch arm64 x86_64
lipo "$APP/Contents/Helpers/calculum" -verify_arch arm64 x86_64

identity=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: Flavio Copes \(DGFKNTAG99\)"/ { print $2; exit }')
if [ -n "$identity" ]; then
  signature="Developer ID"

  # Re-sign every Mach-O inside-out (no --deep), then the app. Signing without
  # --entitlements drops the get-task-allow entitlement Xcode adds, which notarization rejects.
  find "$APP" -depth -type f | while IFS= read -r file; do
    case $(file -b "$file") in
      *Mach-O*) codesign --force --options runtime --timestamp --sign "$identity" "$file" ;;
    esac
  done
  codesign --force --options runtime --timestamp --sign "$identity" "$APP"
else
  signature="ad-hoc"
fi

codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/$NAME.app"

if [ "$signature" = "Developer ID" ]; then
  rm -rf "$CHECK"
  CHECK=$(mktemp -d)

  result=$(xcrun notarytool submit "$ZIP" --keychain-profile notary --wait --output-format json)
  status=$(printf '%s' "$result" | plutil -extract status raw -o - -)
  if [ "$status" != "Accepted" ]; then
    printf '%s\n' "$result" >&2
    submission_id=$(printf '%s' "$result" | plutil -extract id raw -o - -)
    xcrun notarytool log "$submission_id" --keychain-profile notary >&2
    exit 1
  fi

  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  ditto -x -k "$ZIP" "$CHECK"
  codesign --verify --deep --strict "$CHECK/$NAME.app"
  spctl --assess --type execute --verbose "$APP"
fi

rm -rf "$CHECK"
CHECK=""
trap - EXIT

echo "Built $APP $VERSION for $(lipo -archs "$APP/Contents/MacOS/$NAME"), $signature signed"
echo "$ZIP"
shasum -a 256 "$ZIP"
