#!/usr/bin/env bash
# Packages a macOS release build (flutter build macos --release, universal by default) into dist/:
# ad-hoc signed (codesign --sign -), as Sotto-<version>-macos.dmg, or a zip if hdiutil fails.
# Not notarized: users clear the quarantine flag once (see README).
# Usage: tool/package_macos.sh <version>
set -euo pipefail

version="${1:?usage: tool/package_macos.sh <version>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/macos/Build/Products/Release/Sotto.app"
out="$root/dist"
[ -d "$app" ] || { echo "No build at $app" >&2; exit 1; }
mkdir -p "$out"

echo "Architectures: $(lipo -archs "$app/Contents/MacOS/Sotto")"

# Ad-hoc signature over the whole bundle, keeping the entitlements the build signed with. No
# hardened runtime: without a Team ID its library validation would refuse our own frameworks.
entitlements="$root/macos/Runner/Release.entitlements"
codesign --force --deep --sign - --entitlements "$entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

stage="$(mktemp -d)"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
dmg="$out/Sotto-$version-macos.dmg"
if hdiutil create -volname "Sotto $version" -srcfolder "$stage" -ov -format UDZO "$dmg"; then
  echo "dmg: $dmg"
else
  echo "::warning::hdiutil failed; publishing a zip instead."
  ditto -c -k --keepParent "$app" "$out/Sotto-$version-macos.zip"
  echo "zip: $out/Sotto-$version-macos.zip"
fi
rm -rf "$stage"
