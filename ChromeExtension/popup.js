const status = document.getElementById("status");
document.getElementById("bind").onclick = async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url?.startsWith("https://chatgpt.com/") && !tab?.url?.startsWith("https://chat.openai.com/")) { status.textContent = "Open the Yuki App Companion chat on chatgpt.com first."; return; }
  chrome.runtime.sendMessage({ type: "bind_tab", tabId: tab.id, url: tab.url }, result => { status.textContent = result?.ok ? "Bound this ChatGPT tab to Yuki." : "Could not bind this tab."; });
};
