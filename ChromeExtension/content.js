(() => {
if (globalThis.__yukiContentInstalled) return;
globalThis.__yukiContentInstalled = true;
function composer() {
  const candidates = [...document.querySelectorAll('textarea, [contenteditable="true"], [role="textbox"]')];
  const visible = e => { const style = getComputedStyle(e); const rect = e.getBoundingClientRect(); return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0; };
  const visibleEditor = candidates.find(e => visible(e) && e.isContentEditable && !e.closest("nav"));
  if (visibleEditor) return visibleEditor;
  return candidates.find(e => { const label = `${e.getAttribute("aria-label") || ""} ${e.getAttribute("placeholder") || ""}`.toLowerCase(); return visible(e) && !e.closest("nav") && (label.includes("message") || label.includes("ask") || label.includes("chat")); });
}
function composerText(element) { return element?.tagName === "TEXTAREA" ? element.value : (element?.innerText || element?.textContent || ""); }
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
async function waitForComposerClear(element, timeout = 2200) {
  const started = Date.now();
  while (Date.now() - started < timeout) {
    if (!composerText(element).trim()) return true;
    await delay(100);
  }
  return false;
}
function activateButton(button) {
  if (!button || button.disabled) return false;
  button.focus();
  // ChatGPT normally handles a click, but dispatching the complete pointer
  // sequence also covers builds that attach the handler on pointerup.
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup"]) {
    button.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
  }
  button.click();
  return true;
}
async function submitComposer(element, hasImage = false) {
  const button = sendButton(element);
  if (button && !button.disabled) {
    // ChatGPT's composer is asynchronous. In particular, current builds can
    // keep the submitted text/attachment mounted while the request is being
    // accepted, even though the click has already created the user turn. The
    // response watcher below is the reliable completion signal; requiring the
    // composer to clear here creates a false "kept the draft" error and can
    // cause a duplicate submission through the fallback paths.
    if (activateButton(button)) {
      // The click itself is the submission signal. Waiting for ChatGPT to
      // clear the composer makes Yuki feel slow and can block on tabs that
      // stream or render in the background.
      await delay(hasImage ? 180 : 80);
      return "button";
    }
  }
  const form = element?.closest("form");
  if (form?.requestSubmit) {
    form.requestSubmit();
    await delay(120);
    return "form";
  }
  // This is a DOM event delivered to the verified ChatGPT composer, not a
  // global macOS keystroke and cannot reach WoW.
  element.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
  element.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter", code: "Enter", bubbles: true, cancelable: true }));
  await delay(120);
  return "enter";
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
function emit(event, token) { chrome.runtime.sendMessage({ type: "bridge_event", event }).catch(() => {}); }
function waitForResponse(id, baseline, commandToken) {
  const baselineLast = baseline.at(-1) || "";
  let last = "", announced = false, settledTimer = null, finished = false;
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
    if (current && current !== last) last = current;
    // ChatGPT may stream into a reused AX/DOM message node instead of adding
    // a new node. Text changing after the pre-send baseline is still a new
    // assistant turn and must be returned to Yuki.
    const isNewTurn = turns.length > baseline.length || (current && current !== baselineLast);
    if (current && isNewTurn) {
      if (!announced) { announced = true; emit({ type: "response_update", id }, commandToken); }
      clearTimeout(settledTimer);
      settledTimer = setTimeout(() => {
        const latest = assistantTurns().at(-1) || "";
        if (latest && latest === last && !isGenerationPlaceholder(latest)) {
          finished = true;
          observer.disconnect();
          clearInterval(fallback);
          emit({ type: "response_complete", id, text: latest }, commandToken);
        } else scan();
      }, 500);
    }
  };
  const observer = new MutationObserver(scan);
  observer.observe(document.body, { subtree: true, childList: true, characterData: true });
  const fallback = setInterval(scan, 250);
  scan();
}
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type !== "send_message") return;
  const baseline = assistantTurns();
  (async () => {
    if (!(await attachContextImage(message.contextID, message.token))) { sendResponse({ type: "error", message: "Yuki captured the selected app, but ChatGPT wouldn’t accept the image attachment." }); return; }
    const target = composer();
    if (!target || !setExactText(target, message.text)) { sendResponse({ type: "error", message: "I couldn’t find ChatGPT’s message box." }); return; }
    return submitComposer(target, Boolean(message.contextID));
  })().then(submissionMethod => {
    if (!submissionMethod) { sendResponse({ type: "error", message: "ChatGPT kept the draft instead of submitting it." }); return; }
    sendResponse({ type: "status", state: "submitted" });
    waitForResponse(message.id, baseline, message.token);
  }).catch(() => sendResponse({ type: "error", message: "Yuki couldn’t prepare the ChatGPT message." }));
  return true;
});
})();
