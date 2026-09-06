# Yuki + Chrome setup

This bridge uses your normal logged-in ChatGPT session in Chrome. No OpenAI API key is required.

1. Build and launch Yuki:

   `python3 Tools/build_yuki_app.py`

   Then open `Desktop/Effy WoW Companion.app`.

2. In Chrome, open `chrome://extensions` and turn on **Developer mode**.

3. Choose **Load unpacked** and select this project’s `ChromeExtension` folder.

4. Open ChatGPT in Chrome and navigate to the existing **Yuki — WoW Companion** Work conversation.

5. Click the Yuki extension icon and choose **Bind this tab to Yuki**.

6. Leave Chrome open and unminimized on another Desktop/Space. Return to WoW and use Yuki’s bubble.

The first text test should be `hello yuki`. If Yuki says the Chrome bridge is unavailable, confirm Yuki is running and that the extension is loaded on the ChatGPT tab.
