# Windows Yuki Companion

This is the Windows desktop client for Yuki App Companion. It uses the same localhost bridge and the same shared Chrome extension as macOS; ChatGPT DOM logic is not duplicated in the native app.

## Run the handoff package

1. Extract `YukiCompanion-Windows.zip` to a permanent folder.
2. Start `YukiCompanion.exe`. The first-run guide opens automatically.
3. In the guide, choose an application and one of its currently visible windows.
4. Open `ChromeExtension` from the extracted folder and load it at `chrome://extensions` with Developer mode enabled.
5. Open ChatGPT, sign in, open the **Yuki — App Companion** conversation, and use the extension menu to **Bind this tab to Yuki**.
6. Return to Yuki and send a message. Use the eye button to attach the selected window, or enable Automatic Look in Settings.

## What is captured

Yuki discovers visible top-level windows and stores both the application process name and selected window title. Look captures only that window, never the desktop. Normal visible windows are captured with `PrintWindow`; when a GPU-rendered app declines that request, Yuki falls back to copying the selected window's screen bounds. Minimized or closed windows are rejected and the app explains how to recover.

Settings are stored per user under `%APPDATA%\YukiCompanion\config.json`. The settings window can refresh the list of currently open applications and their windows, change the companion name/theme, choose the Chrome conversation label, and control Automatic Look and startup behavior.

Yuki checks the latest published release on GitHub when it opens if **Check for updates automatically** is enabled. Use **Check now** in Settings to check immediately. When an update is found, Yuki opens the matching Windows ZIP download; close Yuki, replace the extracted app folder, and start the new copy.

The Windows build targets .NET 8 WPF on Windows 10 version 1903 or later. The handoff ZIP is self-contained for `win-x64`, so testers do not need to install .NET separately. The GitHub Actions Windows job restores, builds, tests, and publishes this package on `windows-2022`.
