const BRIDGE = "http://127.0.0.1:39173";
let boundTabId = null;
let sessionToken = null;
chrome.storage.local.get(["boundTabId"], value => { boundTabId = value.boundTabId ?? null; });
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "bind_tab" && (sender.tab || message.tabId)) { boundTabId = sender.tab?.id ?? message.tabId; chrome.storage.local.set({ boundTabId, boundUrl: message.url || sender.tab?.url }); sendResponse({ ok: true }); }
  if (message.type === "binding_status") sendResponse({ boundTabId });
  return true;
});
async function poll() {
  try {
    if (!sessionToken) { const session = await fetch(`${BRIDGE}/session`, { cache: "no-store" }); if (session.ok) sessionToken = (await session.json()).token; }
    const command = await (await fetch(`${BRIDGE}/commands`, { cache: "no-store", headers: bridgeHeaders() })).json();
    if (command.type !== "send_message" || boundTabId == null) return;
    deliver(command);
  } catch (_) {}
}
async function deliver(command) {
  try {
    await chrome.tabs.get(boundTabId);
    const result = await chrome.tabs.sendMessage(boundTabId, command);
    if (result?.type) postEvent({ ...result, id: command.id, token: command.token });
  } catch (_) {
    try {
      await chrome.scripting.executeScript({ target: { tabId: boundTabId }, files: ["content.js"] });
      const result = await chrome.tabs.sendMessage(boundTabId, command);
      if (result?.type) postEvent({ ...result, id: command.id, token: command.token });
    } catch (_) {
      postEvent({ type: "error", id: command.id, token: command.token, message: "Yuki’s ChatGPT tab is no longer available. Refresh the tab and bind it again." });
    }
  }
}
chrome.tabs.onRemoved.addListener(tabId => { if (tabId === boundTabId) { boundTabId = null; chrome.storage.local.remove(["boundTabId", "boundUrl"]); } });
function bridgeHeaders() { return sessionToken ? { "X-Yuki-Bridge-Token": sessionToken } : {}; }
function postEvent(event) { fetch(`${BRIDGE}/events`, { method: "POST", headers: { "Content-Type": "application/json", ...bridgeHeaders() }, body: JSON.stringify(event) }).catch(() => {}); }
chrome.alarms.create("yukiPoll", { periodInMinutes: 0.01 });
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === "yukiPoll") poll(); });
setInterval(poll, 450);
poll();
