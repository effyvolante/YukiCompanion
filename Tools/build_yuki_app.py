#!/usr/bin/env python3
"""Build and package Yuki with a stable macOS application identity."""
import pathlib, plistlib, shutil, subprocess
root = pathlib.Path(__file__).resolve().parents[1]
subprocess.run(['swift', 'build'], cwd=root, check=True)
binary_dir = pathlib.Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip())
app = root / 'outputs' / 'Yuki Companion.app'
contents = app / 'Contents'
(contents / 'MacOS').mkdir(parents=True, exist_ok=True)
(contents / 'Resources').mkdir(exist_ok=True)
shutil.copy2(binary_dir / 'EffyWoWCompanion', contents / 'MacOS' / 'EffyWoWCompanion')
# SwiftPM's generated accessor resolves this bundle relative to Bundle.main.
shutil.copytree(binary_dir / 'EffyWoWCompanion_EffyWoWCompanion.bundle', contents / 'Resources' / 'EffyWoWCompanion_EffyWoWCompanion.bundle', dirs_exist_ok=True)
iconset = root / 'outputs' / '.YukiIcon.iconset'
if iconset.exists():
    shutil.rmtree(iconset)
iconset.mkdir(parents=True)
icon_source = root / 'PetAssets' / 'Production' / 'Idle' / 'idle_000.png'
for size in (16, 32, 128, 256, 512):
    subprocess.run(['sips', '-z', str(size), str(size), str(icon_source), '--out', str(iconset / f'icon_{size}x{size}.png')], check=True, stdout=subprocess.DEVNULL)
    retina_size = size * 2
    subprocess.run(['sips', '-z', str(retina_size), str(retina_size), str(icon_source), '--out', str(iconset / f'icon_{size}x{size}@2x.png')], check=True, stdout=subprocess.DEVNULL)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(contents / 'Resources' / 'YukiIcon.icns')], check=True)
with (contents / 'Info.plist').open('wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='com.effy.wowcompanion', CFBundleName='Yuki Companion', CFBundleDisplayName='Yuki — App Companion', CFBundleExecutable='EffyWoWCompanion', CFBundleIconFile='YukiIcon.icns', CFBundlePackageType='APPL', CFBundleVersion='10', CFBundleShortVersionString='1.0.0', LSMinimumSystemVersion='13.0', NSHighResolutionCapable=True), f)
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
# Keep the launch location used during local testing in sync with the packaged
# build. This prevents accidentally launching an older binary with stale bridge
# behavior.
desktop_app = pathlib.Path.home() / 'Desktop' / 'Yuki Companion.app'
shutil.copytree(app, desktop_app, dirs_exist_ok=True)
print(app)
