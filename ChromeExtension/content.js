(() => {
if (globalThis.__yukiContentInstalled) return;
globalThis.__yukiContentInstalled = true;
const activeMessages = globalThis.__yukiActiveMessages ||= new Map();
function composer() {
  const candidates = [...document.querySelectorAll('textarea, [contenteditable="true"], [role="textbox"]')];
  const visible = e => { const style = getComputedStyle(e); const rect = e.getBoundingClientRect(); return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0; };
  const visibleEditor = candidates.find(e => visible(e) && e.isContentEditable && !e.closest("nav"));
  if (visibleEditor) return visibleEditor;
  return candidates.find(e => { const label = `${e.getAttribute("aria-label") || ""} ${e.getAttribute("placeholder") || ""}`.toLowerCase(); return visible(e) && !e.closest("nav") && (label.includes("message") || label.includes("ask") || label.includes("chat")); });
}
function composerText(element) { return element?.tagName === "TEXTAREA" ? element.value : (element?.innerText || element?.textContent || ""); }
function normalizedText(text) { return (text || "").replace(/\s+/g, " ").trim(); }
function setExactText(element, text) {
  if (!element) return false;
  if (element.tagName === "TEXTAREA") Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set?.call(element, text);
  else {
    element.focus();
    document.execCommand("selectAll", false);
    document.execCommand("insertText", false, text);
    if (composerText(element).trim() !== text.trim()) { const paragraph = document.createElement("p"); paragraph.textContent = text; element.replaceChildren(paragraph); }
  }
  element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
  element.dispatchEvent(new Event("change", { bubbles: true }));
  return composerText(element).trim() === text.trim();
}
async function attachContextImage(contextID, commandToken) {
  if (!contextID) return true;
  const context = await chrome.runtime.sendMessage({ type: "bridge_context", contextID });
  if (!context?.dataURL) return false;
  const response = await fetch(context.dataURL);
  const blob = await response.blob();
  let input = [...document.querySelectorAll('input[type="file"]')].find(e => !e.disabled);
  if (!input) {
    const buttons = [...document.querySelectorAll("button")];
    const attach = buttons.find(button => {
      const label = `${button.getAttribute("aria-label") || ""} ${button.getAttribute("title") || ""} ${button.getAttribute("data-testid") || ""}`.toLowerCase();
      return /attach|upload|photo|image|file/.test(label);
    });
    if (attach) { attach.click(); await delay(250); }
    input = [...document.querySelectorAll('input[type="file"]')].find(e => !e.disabled);
  }
  if (!input) return false;
  const file = new File([blob], "yuki-wow-view.png", { type: blob.type || "image/png" });
  const transfer = new DataTransfer();
  transfer.items.add(file);
  input.files = transfer.files;
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("change", { bubbles: true }));
  await delay(450);
  return true;
}
function sendButton(element) {
  const exact = document.querySelector('#composer-submit-button, [data-testid="composer-submit-button"]');
  if (exact && !exact.disabled) return exact;
  const scope = element?.closest("form") || element?.parentElement?.parentElement || document;
  const buttons = [...scope.querySelectorAll("button"), ...document.querySelectorAll("button")];
  return buttons.find(button => {
    const label = `${button.getAttribute("aria-label") || ""} ${button.getAttribute("title") || ""} ${button.getAttribute("data-testid") || ""} ${button.getAttribute("name") || ""} ${button.innerText || ""}`.toLowerCase();
    return !button.disabled && (label.includes("send") || label.includes("submit"));
  }) || scope.querySelector('button[type="submit"], [data-testid*="send"], [data-testid*="submit"]');
}
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function activateButton(button) {
  if (!button || button.disabled) return false;
  button.focus();
  // One click must represent one Yuki command. A synthetic pointer sequence
  // followed by click can invoke multiple handlers in some ChatGPT builds.
  button.click();
  return true;
}
function userTurns() {
  return [...document.querySelectorAll('[data-message-author-role="user"]')]
    .map(node => normalizedText(node.innerText || node.textContent || ""))
    .filter(Boolean);
}
async function waitForReadySendButton(element, timeout = 2500) {
  const started = Date.now();
  while (Date.now() - started < timeout) {
    const button = sendButton(composer() || element);
    if (button && !button.disabled) return button;
    await delay(50);
  }
  return null;
}
function submissionObserved(element, message, beforeUserTurns) {
  const currentComposer = composer() || element;
  const currentText = normalizedText(composerText(currentComposer));
  if (!currentText || currentText !== normalizedText(message)) return true;
  const turns = userTurns();
  return turns.length > beforeUserTurns.length && turns.at(-1) === normalizedText(message);
}
async function waitForSubmission(element, message, beforeUserTurns, timeout) {
  const started = Date.now();
  while (Date.now() - started < timeout) {
    if (submissionObserved(element, message, beforeUserTurns)) return true;
    await delay(75);
  }
  return false;
}
async function submitComposer(element, message, beforeUserTurns, hasImage = false) {
  const button = await waitForReadySendButton(element, hasImage ? 4500 : 2500);
  if (activateButton(button)) {
    return await waitForSubmission(element, message, beforeUserTurns, hasImage ? 5000 : 3500) ? "button" : null;
  }
  const form = element?.closest("form");
  if (form?.requestSubmit) {
    form.requestSubmit();
    return await waitForSubmission(element, message, beforeUserTurns, 3500) ? "form" : null;
  }
  // This is a DOM event delivered to the verified ChatGPT composer, not a
  // global macOS keystroke and cannot reach WoW.
  element.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
  element.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
  return await waitForSubmission(element, message, beforeUserTurns, 3500) ? "enter" : null;
}
function assistantTurns() {
  const explicit = [...document.querySelectorAll('[data-message-author-role="assistant"]')];
  if (explicit.length) return explicit.map(node => (node.innerText || node.textContent || "").trim()).filter(Boolean);
  return [...document.querySelectorAll("article")].map(node => (node.innerText || "").trim()).filter(Boolean);
}
function isGenerationPlaceholder(text) {
  const normalized = text.replace(/\u2026/g, "...").replace(/\s+/g, " ").trim().toLowerCase();
  return /^(thinking|thinking\.\.\.|generating|generating\.\.\.|working|working\.\.\.|searching|searching\.\.\.|analyzing image|analyzing image\.\.\.|analyzing|analyzing\.\.\.)$/.test(normalized);
}
function isGenerating() {
  return [...document.querySelectorAll('button')].some(button => {
    const label = `${button.getAttribute("aria-label") || ""} ${button.getAttribute("title") || ""} ${button.getAttribute("data-testid") || ""} ${button.innerText || ""}`.toLowerCase();
    return !button.disabled && /stop generating|stop response|stop streaming/.test(label);
  });
}
function emit(event, token) { chrome.runtime.sendMessage({ type: "bridge_event", event }).catch(() => {}); }
function waitForResponse(id, baseline, commandToken) {
  const baselineLast = baseline.at(-1) || "";
  let last = "", lastEmitted = "", announced = false, settledTimer = null, updateTimer = null, finished = false;
  const scheduleUpdate = text => {
    last = text;
    if (updateTimer) return;
    updateTimer = setTimeout(() => {
      updateTimer = null;
      if (last && last !== lastEmitted) {
        lastEmitted = last;
        emit({ type: "response_update", id, text: last }, commandToken);
      }
    }, 80);
  };
  const scan = () => {
    if (finished) return;
    const turns = assistantTurns();
    const current = turns.at(-1) || "";
    // ChatGPT exposes a temporary assistant node while generating. It is not
    // a reply and must never be mirrored as Yuki's answer.
    if (isGenerationPlaceholder(current)) {
      last = "";
      return;
    }
    // ChatGPT may stream into a reused AX/DOM message node instead of adding
    // a new node. Text changing after the pre-send baseline is still a new
    // assistant turn and must be returned to Yuki.
    const isNewTurn = turns.length > baseline.length || (current && current !== baselineLast);
    // Never emit the pre-send last assistant turn. On a follow-up message it
    // is still the last DOM node while the new response is being created; the
    // old implementation mirrored it as the new reply and could keep
    // resubmitting stale text as the DOM changed.
    if (!isNewTurn) return;
    if (current && current !== last) scheduleUpdate(current);
    if (current) {
      if (!announced) announced = true;
      clearTimeout(settledTimer);
      if (isGenerating()) return;
      settledTimer = setTimeout(() => {
        const latest = assistantTurns().at(-1) || "";
        if (latest && latest === last && !isGenerationPlaceholder(latest) && !isGenerating()) {
          finished = true;
          observer.disconnect();
          clearInterval(fallback);
          clearTimeout(updateTimer);
          if (latest !== lastEmitted) emit({ type: "response_update", id, text: latest }, commandToken);
          emit({ type: "response_complete", id, text: latest }, commandToken);
          activeMessages.delete(id);
        } else scan();
      }, 900);
    }
  };
  const observer = new MutationObserver(scan);
  observer.observe(document.body, { subtree: true, childList: true, characterData: true });
  const fallback = setInterval(scan, 250);
  scan();
}
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type !== "send_message") return;
  if (activeMessages.has(message.id)) {
    const state = activeMessages.get(message.id) === "processing" ? "delivered" : "submitted";
    sendResponse({ type: "status", state });
    return true;
  }
  activeMessages.set(message.id, "processing");
  const baseline = assistantTurns();
  const beforeUserTurns = userTurns();
  (async () => {
    if (!(await attachContextImage(message.contextID, message.token))) throw new Error("context_attachment");
    const target = composer();
    if (!target || !setExactText(target, message.text)) { sendResponse({ type: "error", message: "I couldn’t find ChatGPT’s message box." }); return; }
    return submitComposer(target, message.text, beforeUserTurns, Boolean(message.contextID));
  })().then(submissionMethod => {
    if (!submissionMethod) { activeMessages.delete(message.id); sendResponse({ type: "error", message: "ChatGPT kept the draft instead of submitting it." }); return; }
    activeMessages.set(message.id, "submitted");
    sendResponse({ type: "status", state: "submitted" });
    waitForResponse(message.id, baseline, message.token);
  }).catch(error => {
    activeMessages.delete(message.id);
    const detail = error?.message === "context_attachment" ? "Yuki captured the selected app, but ChatGPT wouldn’t accept the image attachment." : "Yuki couldn’t prepare the ChatGPT message.";
    sendResponse({ type: "error", message: detail });
  });
  return true;
});
})();
