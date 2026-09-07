#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch_path="${1:-$repo_root/.build-package}"
output_path="${2:-$repo_root/dist/YukiCompanion.app}"

swift build --configuration release -Xswiftc -swift-version -Xswiftc 5 -Xswiftc -Xfrontend -Xswiftc -strict-concurrency=minimal -Xswiftc -Xfrontend -Xswiftc -disable-actor-data-race-checks --scratch-path "$scratch_path"
build_path="$scratch_path/arm64-apple-macosx/release"

rm -rf "$output_path"
mkdir -p "$output_path/Contents/MacOS" "$output_path/Contents/Resources"
cp "$build_path/EffyWoWCompanion" "$output_path/Contents/MacOS/EffyWoWCompanion"
cp "$repo_root/Packaging/macos/Info.plist" "$output_path/Contents/Info.plist"

# Use a real Yuki animation still as the application icon. Generate all macOS
# icon sizes at package time so the source art and the Dock icon stay aligned.
iconset_path="$scratch_path/YukiIcon.iconset"
mkdir -p "$iconset_path"
icon_source="$repo_root/PetAssets/Production/Idle/idle_000.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$icon_source" --out "$iconset_path/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$icon_source" --out "$iconset_path/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_path" -o "$output_path/Contents/Resources/YukiIcon.icns"

resource_bundle="$build_path/EffyWoWCompanion_EffyWoWCompanion.bundle"
if [[ -d "$resource_bundle" ]]; then cp -R "$resource_bundle" "$output_path/Contents/Resources/"; fi

chmod 755 "$output_path/Contents/MacOS/EffyWoWCompanion"
# Swift's linker may leave an ad-hoc signature on the executable. Re-sign the
# completed bundle so its Info.plist and resource bundle are sealed together.
codesign --force --deep --sign - "$output_path"
codesign --verify --deep --strict "$output_path"
echo "Packaged $output_path"
