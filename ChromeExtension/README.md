# Yuki App Companion — shared browser extension

This folder is the shared extension for macOS and Windows. It works in Google Chrome and Microsoft Edge. Keep it in a permanent location; load it unpacked from this folder in your chosen browser.

## Install
1. Extract the downloaded ZIP. If you downloaded the repository, locate its `ChromeExtension` folder.
2. Open your browser's extension page: `chrome://extensions` in Chrome or `edge://extensions` in Edge.
3. Turn on **Developer mode** at the top right.
4. Choose **Load unpacked**, then select the folder containing `manifest.json` (this folder).
5. Use the browser's puzzle-piece toolbar button to pin Yuki.
6. Start the Yuki native app. Keep only one copy running.
7. Open ChatGPT in your browser, sign in, and open or create your **Yuki — App Companion** conversation. In Yuki's Settings, you can paste a pinned chat/GPT URL and choose Chrome, Edge, or your default browser; the app will open that destination in the background when it sends a message.
8. While that tab is active, click the Yuki extension and choose **Bind this tab to Yuki**. Wait for confirmation.
9. Send `hello yuki` from Yuki's chat. Keep the bound Chrome tab open.

## Enable visual context
Choose a running app in Yuki Settings. On Mac, allow the installed Yuki app under System Settings → Privacy & Security → Screen Recording, then restart Yuki if requested. Keep the selected app's window visible. Click Yuki's eye button before sending a visual question. Selecting an app alone does not continuously capture it; Automatic Look is optional.

## Update or reconnect
Replace this folder with the new version, click Reload on Yuki's card at `chrome://extensions`, refresh your ChatGPT tab, and bind it again. Close older copies of Yuki before starting an updated app. The extension automatically renews its bridge token after Yuki restarts.

If binding fails, confirm you clicked the extension from a ChatGPT tab in Chrome, not from a preview of popup.html. If Chrome restarts or the bound tab closes, bind the desired tab again. No API key is required.
