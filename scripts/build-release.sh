#!/bin/sh
# Builds a universal (Apple silicon and Intel) app with an ad-hoc signature,
# checks the signature survives zipping, and writes dist/<Name>-<version>.zip.
# The name and version come from project.yml.
# Usage: scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
NAME=$(sed -n 's/^name: *//p' project.yml)
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
BUILD="$ROOT/build/release"
APP="$BUILD/Release/$NAME.app"
ZIP="$ROOT/dist/$NAME-$VERSION.zip"
CHECK=$(mktemp -d)

rm -rf "$BUILD" "$ZIP"
mkdir -p dist
xcodebuild -project "$NAME.xcodeproj" -target "$NAME" -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO SYMROOT="$BUILD" -quiet build

lipo "$APP/Contents/MacOS/$NAME" -verify_arch arm64 x86_64
lipo "$APP/Contents/Helpers/calculum" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/$NAME.app"
rm -rf "$CHECK"

echo "$ZIP"
shasum -a 256 "$ZIP"
