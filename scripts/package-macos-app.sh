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

resource_bundle="$build_path/EffyWoWCompanion_EffyWoWCompanion.bundle"
if [[ -d "$resource_bundle" ]]; then cp -R "$resource_bundle" "$output_path/Contents/Resources/"; fi

chmod 755 "$output_path/Contents/MacOS/EffyWoWCompanion"
echo "Packaged $output_path"
