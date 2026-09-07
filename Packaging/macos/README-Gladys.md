# Yuki Companion — Gladys macOS installer

This package installs the current Yuki Companion app and the checked-in shared
Chrome extension. Yuki uses your normal signed-in ChatGPT session; no API key
is required.

## Install

1. Open `YukiCompanion-Gladys-macos.pkg` and complete the installer.
2. The installer places `Yuki Companion.app` in `/Applications`, opens Chrome
   at `chrome://extensions`, and opens the exact extension folder in Finder.
3. In Chrome, turn on **Developer mode**, choose **Load unpacked**, and select
   the folder Finder opened:

   `/Library/Application Support/Yuki Companion/ChromeExtension`

4. Pin Yuki from Chrome's puzzle-piece menu.
5. Open ChatGPT in Chrome, sign in, and open or create the conversation named
   **Yuki — App Companion**. Click the Yuki extension in that tab and choose
   **Bind this tab to Yuki**.
6. Open Yuki from Applications and choose **Get started** from her menu.

Chrome requires the single **Load unpacked** confirmation for an extension
that is not distributed through the Chrome Web Store or an enterprise policy;
the installer automates everything that macOS and Chrome allow for a normal
personal installation and puts the exact folder in front of you.

## Permissions for visual context

When Yuki asks to look at the selected app window, allow **Yuki Companion** in
**System Settings → Privacy & Security → Screen Recording**, then restart Yuki
if macOS requests it. Accessibility is only needed for legacy keyboard-assisted
controls; the Chrome extension connection itself does not require it.

Yuki captures only the selected application's visible window. It does not
continuously capture the desktop.

## Keep Yuki easy to open

After installation, open `/Applications` in Finder and drag **Yuki Companion**
to the Dock. The app can also be opened from Spotlight.

## Updating

Use **Check for updates** in Yuki's menu. Updates are published from the
YukiCompanion GitHub releases; replace the installed app with the new package
when one is available, and click **Reload** on the Yuki extension card if the
extension files changed.
