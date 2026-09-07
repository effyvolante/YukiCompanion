#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch_path="${1:-$repo_root/.build-gladys-package}"
output_path="${2:-$repo_root/dist/YukiCompanion-Gladys-macos}"
app_path="$scratch_path/Yuki Companion.app"
payload_path="$scratch_path/pkg-payload"
pkg_path="$output_path/YukiCompanion-Gladys-macos.pkg"
readme_path="$output_path/README-Gladys.md"
dmg_path="$output_path/YukiCompanion-Gladys-macos.dmg"

rm -rf "$scratch_path" "$output_path"
mkdir -p "$scratch_path" "$output_path"

bash "$repo_root/scripts/package-macos-app.sh" "$scratch_path/swift" "$app_path"

# Keep the shared extension beside the app as a self-contained reference, and
# also install it at a stable path that Chrome can load unpacked.
mkdir -p "$app_path/Contents/Resources/ChromeExtension"
cp -R "$repo_root/ChromeExtension/." "$app_path/Contents/Resources/ChromeExtension/"
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"

mkdir -p "$payload_path/Applications"
cp -R "$app_path" "$payload_path/Applications/Yuki Companion.app"
mkdir -p "$payload_path/Library/Application Support/Yuki Companion/ChromeExtension"
cp -R "$repo_root/ChromeExtension/." "$payload_path/Library/Application Support/Yuki Companion/ChromeExtension/"
cp "$repo_root/Packaging/macos/README-Gladys.md" "$payload_path/Library/Application Support/Yuki Companion/README-Gladys.md"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
pkgbuild \
  --root "$payload_path" \
  --scripts "$repo_root/Packaging/macos/GladysInstaller" \
  --identifier "com.effyvolante.yukicompanion.gladys-installer" \
  --version "$version" \
  --install-location / \
  "$pkg_path"

cp "$repo_root/Packaging/macos/README-Gladys.md" "$readme_path"
ditto -c -k --sequesterRsrc --keepParent "$output_path" "$output_path/../YukiCompanion-Gladys-macos.zip"

if command -v hdiutil >/dev/null 2>&1; then
  hdiutil create \
    -volname "Yuki Companion Gladys" \
    -srcfolder "$output_path" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null
fi

pkgutil --payload-files "$pkg_path" | grep -Fq "Applications/Yuki Companion.app/Contents/MacOS/EffyWoWCompanion"
pkgutil --payload-files "$pkg_path" | grep -Fq "Library/Application Support/Yuki Companion/ChromeExtension/manifest.json"

echo "Packaged Gladys handoff: $pkg_path"
echo "Zip: $output_path/../YukiCompanion-Gladys-macos.zip"
[[ -f "$dmg_path" ]] && echo "DMG: $dmg_path"
