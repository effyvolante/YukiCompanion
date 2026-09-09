const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('ChromeExtension/background.js', 'utf8');

function harness(bound = 7) {
  let token = 'first';
  const queue = [], events = [], delivered = [];
  let listener;
  const context = vm.createContext({
    btoa: s => Buffer.from(s, 'binary').toString('base64'), Uint8Array,
    setInterval() {},
    chrome: {
      storage: { local: { get: async () => ({ boundTabId: bound }), set: async () => {}, remove() {} } },
      runtime: { onMessage: { addListener(fn) { listener = fn; } }, onStartup: { addListener() {} }, onInstalled: { addListener() {} } },
      tabs: { get: async id => ({ id, url: 'https://chatgpt.com/c/example' }),
        query: async () => [{ id: 7, url: 'https://chatgpt.com/c/example' }],
        sendMessage: async (id, command) => { delivered.push(command); return { type: 'response_complete', text: 'reply' }; },
        onRemoved: { addListener() {} }, onUpdated: { addListener() {} } },
      scripting: { executeScript: async () => {} },
      alarms: { create() {}, onAlarm: { addListener() {} } }
    },
    fetch: async (url, options = {}) => {
      if (url.endsWith('/session')) return { ok: true, json: async () => ({ token }) };
      if (options.headers['X-Yuki-Bridge-Token'] !== token) return { status: 401, ok: false };
      if (url.includes('/commands')) return { ok: true, json: async () => queue.shift() || { type: 'idle' } };
      if (url.endsWith('/events')) { events.push(JSON.parse(options.body)); return { ok: true }; }
      return { ok: true, arrayBuffer: async () => new Uint8Array([1, 2, 3]).buffer };
    }
  });
  vm.runInContext(source, context);
  return { queue, events, delivered, restart() { token = 'second'; },
    async tick() { await new Promise(setImmediate); await vm.runInContext('poll()', context); await new Promise(setImmediate); },
    message(message, sender = {}) { return new Promise(resolve => listener(message, sender, resolve)); } };
}
test('renews token after native restart and delivers consecutive messages', async () => {
  const h = harness(); await h.tick(); h.restart();
  h.queue.push({ type: 'send_message', id: 'a' }, { type: 'send_message', id: 'b' });
  await h.tick(); await h.tick();
  assert.deepEqual(h.delivered.map(x => x.id), ['a', 'b']);
  assert.deepEqual(h.events.filter(x => x.type === 'response_complete').map(x => x.type), ['response_complete', 'response_complete']);
});
test('unbound commands return an actionable error', async () => {
  const h = harness(null); await h.tick(); h.queue.push({ type: 'send_message', id: 'a' }); await h.tick();
  const error = h.events.find(event => event.type === 'error'); assert.equal(error.type, 'error'); assert.match(error.message, /Bind this tab/);
});
test('binding installs receiver and confirms success', async () => {
  const h = harness(null); await h.tick();
  assert.equal((await h.message({ type: 'bind_tab', tabId: 7 })).ok, true);
  assert.equal((await h.message({ type: 'binding_status' })).boundTabId, 7);
});
test('reconnect command restores the saved binding without activating a tab', async () => {
  const h = harness(); await h.tick();
  h.queue.push({ type: 'reconnect' }); await h.tick();
  assert.equal((await h.message({ type: 'binding_status' })).boundTabId, 7);
  assert.equal(h.delivered.length, 0);
  assert.equal(h.events.filter(event => event.type === 'bridge_status').at(-1).state, 'ready');
});
test('only bound tab can relay images and events', async () => {
  const h = harness(); await h.tick();
  assert.match((await h.message({ type: 'bridge_context', contextID: 'a' }, { tab: { id: 8 } })).error, /not bound/);
  assert.equal((await h.message({ type: 'bridge_context', contextID: 'a' }, { tab: { id: 7 } })).dataURL, 'data:image/png;base64,AQID');
  await h.message({ type: 'bridge_event', event: { type: 'response_complete', id: 'a' } }, { tab: { id: 7 } });
  assert.equal(h.events.find(event => event.type === 'response_complete').type, 'response_complete');
});
test('reinjecting content script registers only one receiver', () => {
  let count = 0;
  const context = vm.createContext({ chrome: { runtime: { onMessage: { addListener() { count++; } } } } });
  const content = fs.readFileSync('ChromeExtension/content.js', 'utf8');
  vm.runInContext(content, context); vm.runInContext(content, context);
  assert.equal(count, 1);
});
test('content receiver never submits the same message id twice', async () => {
  let listener, clicks = 0;
  class FakeTextarea {
    constructor() { this.tagName = 'TEXTAREA'; this._value = ''; this.isContentEditable = false; }
    closest() { return null; }
    getBoundingClientRect() { return { width: 200, height: 40 }; }
    getAttribute(name) { return name === 'placeholder' ? 'Message ChatGPT' : ''; }
    dispatchEvent() {}
  }
  Object.defineProperty(FakeTextarea.prototype, 'value', { get() { return this._value; }, set(value) { this._value = value; } });
  const textarea = new FakeTextarea();
  const button = { disabled: false, focus() {}, dispatchEvent() {}, click() { clicks++; }, getAttribute() { return ''; }, innerText: '' };
  const context = vm.createContext({
    HTMLTextAreaElement: FakeTextarea,
    document: {
      body: {}, execCommand() {}, createElement() { return { textContent: '' }; },
      querySelector(selector) { return selector.includes('composer-submit-button') ? button : null; },
      querySelectorAll(selector) { if (selector.includes('textarea')) return [textarea]; if (selector.includes('button')) return [button]; return []; }
    },
    getComputedStyle: () => ({ display: 'block', visibility: 'visible' }),
    InputEvent: class {}, Event: class {}, MouseEvent: class {}, KeyboardEvent: class {},
    MutationObserver: class { observe() {} disconnect() {} },
    setTimeout, clearTimeout, setInterval: () => 1, clearInterval() {}, window: {},
    chrome: { runtime: { onMessage: { addListener(fn) { listener = fn; } }, sendMessage: async () => ({}) } }
  });
  vm.runInContext(fs.readFileSync('ChromeExtension/content.js', 'utf8'), context);
  const send = message => new Promise(resolve => listener(message, {}, resolve));
  assert.equal((await send({ type: 'send_message', id: 'same', text: 'hello' })).state, 'submitted');
  assert.equal((await send({ type: 'send_message', id: 'same', text: 'hello' })).state, 'submitted');
  assert.equal(clicks, 1);
});
