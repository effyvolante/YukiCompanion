# Yuki Companion

Yuki is the default theme for Yuki Companion, a tiny pink companion that uses your normal logged-in ChatGPT account through a ChatGPT tab in Google Chrome. The Chrome tab is the backend; Yuki’s pink bubble remains the visible chat interface.

The current known-good implementation is the macOS app in `Sources/EffyWoWCompanion`. Windows development is isolated under `Windows/`; shared contracts live under `Shared/`. The macOS app remains the compatibility reference and is not rewritten as part of the cross-platform work.

No OpenAI API key, API billing, private endpoint, cookie access, or credential extraction is used.

## Requirements

- macOS 13+
- World of Warcraft Retail
- Google Chrome
- ChatGPT open in Chrome and logged in
- Xcode 15+ or Swift command-line tools

For Windows, use the `YukiCompanion-windows` artifact from a green GitHub Actions run. It is a self-contained `win-x64` WPF package for Windows 10 version 1903 or later and includes the shared `ChromeExtension` folder plus its installation guide.

## Build and launch

```bash
cd /Users/jaybracewell/Documents/Codex/2026-09-05/pr
python3 Tools/build_yuki_app.py
open "$HOME/Desktop/Yuki Companion.app"
```

For a packaged app bundle suitable for testing launch-at-login:

```bash
bash scripts/package-macos-app.sh
open dist/YukiCompanion.app
```

Yuki is a normal Dock application. Open **Yuki Companion → Settings…** or press **⌘,** to personalize it. The app must be running and active for the shortcut to apply.

The package includes the SwiftPM executable, Yuki animation resources, a valid application manifest, and the screen-recording usage description.

## One-time Chrome setup

1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. Click **Load unpacked**.
4. Select this project’s `ChromeExtension` folder.
5. In Chrome, open the existing **Yuki — App Companion** conversation.
6. Click the Yuki extension icon and choose **Bind this tab to Yuki**.
7. Leave Chrome open and unminimized on another Desktop/Space while WoW is fullscreen elsewhere.

Then open Yuki’s bubble and send `hello yuki`.

## Permissions

The normal Chrome bridge does not require Yuki to control ChatGPT through macOS Accessibility. The old desktop Accessibility bridge remains in the source as a legacy fallback only.

Screen Recording is required for the screenshot/Look feature. Yuki captures only the selected application’s visible window and never falls back to capturing the desktop.

## Troubleshooting

- **Chrome bridge unavailable:** confirm Yuki is running, the extension is loaded, and the Yuki App Companion chat tab is still open and bound.
- **Message box not found:** refresh the ChatGPT tab, confirm it is the Yuki App Companion chat, then bind the tab again.
- **ChatGPT changed its layout:** the extension’s DOM selectors may need a small update; no API key or account reset is required.

Yuki does not automate WoW, inspect process memory, inject code, press abilities, or send gameplay input.
