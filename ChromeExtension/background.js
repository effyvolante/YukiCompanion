const BRIDGE = "http://127.0.0.1:39173";
let boundTabId = null;
let sessionToken = null;
const bindingReady = chrome.storage.local.get(["boundTabId"]).then(value => { boundTabId = value.boundTabId ?? null; });
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
      if (!/^https:\/\/(chatgpt\.com|chat\.openai\.com)\//.test(tab.url || "")) throw new Error("Choose a ChatGPT tab in Chrome first.");
      await bindTab(tab);
      sendResponse({ ok: true });
    })().catch(error => sendResponse({ ok: false, message: error.message }));
  }
  if (message.type === "binding_status") bindingReady.then(() => sendResponse({ boundTabId }));
  return true;
});
async function bindTab(tab) {
  if (!tab?.id || !/^https:\/\/(chatgpt\.com|chat\.openai\.com)\//.test(tab.url || "")) throw new Error("Choose a ChatGPT tab first.");
  await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] });
  boundTabId = tab.id;
  await chrome.storage.local.set({ boundTabId, boundUrl: tab.url });
}
async function bindConfiguredChat(chatURL) {
  if (!chatURL) return false;
  const target = new URL(chatURL);
  const tabs = await chrome.tabs.query({});
  const tab = tabs.find(candidate => {
    if (!candidate.url || candidate.url.startsWith("chrome://") || candidate.url.startsWith("edge://")) return false;
    if (candidate.url === chatURL) return true;
    return target.pathname === "/" && candidate.url.startsWith(target.origin + "/");
  });
  if (!tab) return false;
  await bindTab(tab);
  return true;
}
let polling = false;
let waitingCommand = null;
async function poll() {
  if (polling) return;
  polling = true;
  try {
    await bindingReady;
    let command = waitingCommand;
    if (!command) {
      const response = await bridgeFetch("/commands", { cache: "no-store" });
      if (!response.ok) throw new Error("Bridge unavailable");
      command = await response.json();
    }
    if (command.type !== "send_message") { waitingCommand = null; return; }
    if (boundTabId == null && command.chatURL) {
      try {
        if (await bindConfiguredChat(command.chatURL)) waitingCommand = null;
        else { waitingCommand = command; return; }
      } catch (_) {
        waitingCommand = command;
        return;
      }
    }
    if (boundTabId == null) {
      waitingCommand = null;
      await postEvent({ type: "error", id: command.id, message: "No ChatGPT tab is bound. Open your conversation in Chrome, click the Yuki extension, and choose Bind this tab to Yuki." });
      return;
    }
    waitingCommand = null;
    await deliver(command);
  } catch (_) { sessionToken = null; }
  finally { polling = false; }
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
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === "yukiPoll") poll(); });
setInterval(poll, 450);
poll();
