#!/usr/bin/env bash
# Packages a Linux release build (flutter build linux --release) into dist/:
#   Sotto-<version>-linux-x64.tar.gz   always
#   Sotto-<version>-x86_64.AppImage    best effort (needs network for appimagetool)
# Usage: tool/package_linux.sh <version>
set -euo pipefail

version="${1:?usage: tool/package_linux.sh <version>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/build/linux/x64/release/bundle"
out="$root/dist"
name="Sotto-$version-linux-x64"
[ -x "$bundle/sotto" ] || { echo "No build at $bundle" >&2; exit 1; }
mkdir -p "$out"

# tar.gz: one folder; run ./sotto inside it.
stage="$(mktemp -d)"
cp -a "$bundle" "$stage/$name"
cp "$root/linux/packaging/sotto.desktop" "$stage/$name/"
cp "$root/assets/branding/sotto_icon_256.png" "$stage/$name/sotto.png"
cp "$root/LICENSE" "$stage/$name/"
tar -C "$stage" -czf "$out/$name.tar.gz" "$name"
echo "tar.gz: $out/$name.tar.gz"

# AppImage: the same bundle in an AppDir. Optional — the tar.gz is the supported download.
appdir="$stage/Sotto.AppDir"
mkdir -p "$appdir/usr/bin"
cp -a "$bundle/." "$appdir/usr/bin/"
cp "$root/linux/packaging/sotto.desktop" "$appdir/sotto.desktop"
cp "$root/assets/branding/sotto_icon_256.png" "$appdir/sotto.png"
cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/usr/bin/sotto" "$@"
EOF
chmod +x "$appdir/AppRun"
tool="$stage/appimagetool"
if curl -fsSL -o "$tool" \
  https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage; then
  chmod +x "$tool"
  # No FUSE on CI runners: run the tool from its extracted copy.
  if ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$out/Sotto-$version-x86_64.AppImage"; then
    echo "AppImage: $out/Sotto-$version-x86_64.AppImage"
  else
    echo "::warning::AppImage packaging failed; the tar.gz is still published."
  fi
else
  echo "::warning::Could not download appimagetool; skipped the AppImage."
fi
rm -rf "$stage"
