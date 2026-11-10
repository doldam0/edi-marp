#!/usr/bin/env bash
# Build a universal Release EdiMarp.app and package it as dist/EdiMarp.dmg.
#
#   scripts/make-dmg.sh [version]
#
# version sets CFBundleShortVersionString (e.g. 0.1.0); BUILD_NUMBER, if set,
# sets CFBundleVersion. Without them the values in project.yml are used.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-}"
derived=build/release
out=dist

overrides=()
[ -n "$version" ] && overrides+=("MARKETING_VERSION=$version")
[ -n "${BUILD_NUMBER:-}" ] && overrides+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")

xcodebuild -project EdiMarp.xcodeproj -scheme EdiMarp -configuration Release \
  -derivedDataPath "$derived" -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  ${overrides[@]+"${overrides[@]}"} build

app="$derived/Build/Products/Release/EdiMarp.app"

# Stage the app next to an /Applications link so the DMG opens as
# "drag to install".
stage="$(mktemp -d)"
trap 'rm -rf "${stage:?}"' EXIT
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"

mkdir -p "$out"
rm -f "$out/EdiMarp.dmg" "$out/EdiMarp.dmg.sha256"
hdiutil create -volname "edi · marp" -srcfolder "$stage" -ov -format UDZO "$out/EdiMarp.dmg"
(cd "$out" && shasum -a 256 EdiMarp.dmg > EdiMarp.dmg.sha256)

echo "→ $out/EdiMarp.dmg"
