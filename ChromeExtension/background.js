const BRIDGE = "http://127.0.0.1:39173";
let boundTabId = null;
let boundUrl = null;
let sessionToken = null;
const isChatGPTURL = url => /^https:\/\/(chatgpt\.com|chat\.openai\.com)\//.test(url || "");
const bindingReady = chrome.storage.local.get(["boundTabId", "boundUrl"]).then(async value => {
  boundTabId = value.boundTabId ?? null;
  boundUrl = value.boundUrl ?? null;
  if (boundTabId != null) {
    try {
      const tab = await chrome.tabs.get(boundTabId);
      if (!isChatGPTURL(tab.url)) await clearBinding();
    } catch (_) { await clearBinding(); }
  }
  await reportBindingState();
});
async function setBinding(tab) {
  if (!tab?.id || !isChatGPTURL(tab.url)) throw new Error("Choose a ChatGPT tab first.");
  await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] });
  boundTabId = tab.id;
  boundUrl = tab.url;
  await chrome.storage.local.set({ boundTabId, boundUrl });
  await reportBindingState();
}
async function clearBinding() {
  boundTabId = null;
  await chrome.storage.local.remove(["boundTabId"]);
  await reportBindingState();
}
async function reconnectStoredBinding() {
  if (boundTabId != null) {
    try { const tab = await chrome.tabs.get(boundTabId); await setBinding(tab); return true; } catch (_) { /* Try the saved URL. */ }
  }
  if (boundUrl) {
    const tabs = await chrome.tabs.query({});
    const tab = tabs.find(candidate => candidate.url === boundUrl || (isChatGPTURL(candidate.url) && new URL(candidate.url).origin === new URL(boundUrl).origin));
    if (tab) { await setBinding(tab); return true; }
  }
  await clearBinding();
  return false;
}
function reportBindingState() {
  return postEvent({ type: "bridge_status", state: boundTabId == null ? "needs_binding" : "ready" });
}
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "bridge_event" || message.type === "bridge_context") {
    (async () => {
      await bindingReady;
      if (sender.tab?.id !== boundTabId) throw new Error("Tab is not bound to Yuki.");
      if (message.type === "bridge_event") {
        await postEvent(message.event);
        sendResponse({ ok: true });
      } else {
        const response = await bridgeFetch(`/context/${encodeURIComponent(message.contextID)}`, { cache: "no-store" });
        if (!response.ok) throw new Error("Captured image is unavailable.");
        const bytes = new Uint8Array(await response.arrayBuffer());
        let binary = "";
        for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
        sendResponse({ dataURL: `data:image/png;base64,${btoa(binary)}` });
      }
    })().catch(error => sendResponse({ error: error.message }));
    return true;
  }
  if (message.type === "bind_tab") {
    (async () => {
      await bindingReady;
      const tab = await chrome.tabs.get(sender.tab?.id ?? message.tabId);
      if (!isChatGPTURL(tab.url)) throw new Error("Choose a ChatGPT tab in Chrome first.");
      await setBinding(tab);
      sendResponse({ ok: true });
    })().catch(error => sendResponse({ ok: false, message: error.message }));
  }
  if (message.type === "binding_status") bindingReady.then(() => sendResponse({ boundTabId }));
  return true;
});
let polling = false;
async function poll() {
  if (polling) return;
  polling = true;
  try {
    await bindingReady;
    const response = await bridgeFetch("/commands", { cache: "no-store" });
    if (!response.ok) throw new Error("Bridge unavailable");
    const command = await response.json();
    if (command.type === "reconnect") { await reconnectStoredBinding(); return; }
    if (command.type !== "send_message") return;
    if (boundTabId == null) {
      await postEvent({ type: "error", id: command.id, message: "No ChatGPT tab is bound. Open your conversation in Chrome, click the Yuki extension, and choose Bind this tab to Yuki." });
      return;
    }
    await deliver(command);
  } catch (_) { sessionToken = null; }
  finally { polling = false; }
}
async function deliver(command) {
  try {
    await chrome.tabs.get(boundTabId);
    await postEvent({ type: "status", state: "delivered", id: command.id, token: command.token });
    const result = await chrome.tabs.sendMessage(boundTabId, command);
    if (result?.type) postEvent({ ...result, id: command.id, token: command.token });
  } catch (_) {
    try {
      await chrome.scripting.executeScript({ target: { tabId: boundTabId }, files: ["content.js"] });
      await postEvent({ type: "status", state: "delivered", id: command.id, token: command.token });
      const result = await chrome.tabs.sendMessage(boundTabId, command);
      if (result?.type) postEvent({ ...result, id: command.id, token: command.token });
    } catch (_) {
      postEvent({ type: "error", id: command.id, token: command.token, message: "Yuki’s ChatGPT tab is no longer available. Refresh the tab and bind it again." });
    }
  }
}
chrome.tabs.onRemoved.addListener(tabId => { if (tabId === boundTabId) clearBinding(); });
chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
  if (tabId !== boundTabId) return;
  if (change.url && !isChatGPTURL(change.url)) { clearBinding(); return; }
  if (change.status === "complete" && isChatGPTURL(tab.url)) setBinding(tab).catch(() => clearBinding());
});
function bridgeHeaders() { return sessionToken ? { "X-Yuki-Bridge-Token": sessionToken } : {}; }
async function bridgeFetch(path, options = {}) {
  for (let attempt = 0; attempt < 2; attempt++) {
    if (!sessionToken) {
      const session = await fetch(`${BRIDGE}/session`, { cache: "no-store" });
      if (!session.ok) throw new Error("Start the Yuki app first.");
      sessionToken = (await session.json()).token;
    }
    const response = await fetch(`${BRIDGE}${path}`, { ...options, headers: { ...options.headers, ...bridgeHeaders() } });
    if (response.status !== 401) return response;
    sessionToken = null;
  }
  throw new Error("Bridge session expired.");
}
function postEvent(event) { return bridgeFetch("/events", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(event) }).catch(() => {}); }
chrome.alarms.create("yukiPoll", { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === "yukiPoll") { reportBindingState(); poll(); } });
setInterval(poll, 150);
setInterval(reportBindingState, 5000);
poll();
