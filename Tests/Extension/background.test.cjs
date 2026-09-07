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
      runtime: { onMessage: { addListener(fn) { listener = fn; } } },
      tabs: { get: async id => ({ id, url: 'https://chatgpt.com/c/example' }),
        sendMessage: async (id, command) => { delivered.push(command); return { type: 'response_complete', text: 'reply' }; },
        onRemoved: { addListener() {} } },
      scripting: { executeScript: async () => {} },
      alarms: { create() {}, onAlarm: { addListener() {} } }
    },
    fetch: async (url, options = {}) => {
      if (url.endsWith('/session')) return { ok: true, json: async () => ({ token }) };
      if (options.headers['X-Yuki-Bridge-Token'] !== token) return { status: 401, ok: false };
      if (url.endsWith('/commands')) return { ok: true, json: async () => queue.shift() || { type: 'idle' } };
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
  assert.deepEqual(h.events.map(x => x.type), ['response_complete', 'response_complete']);
});
test('unbound commands return an actionable error', async () => {
  const h = harness(null); await h.tick(); h.queue.push({ type: 'send_message', id: 'a' }); await h.tick();
  assert.equal(h.events[0].type, 'error'); assert.match(h.events[0].message, /Bind this tab/);
});
test('binding installs receiver and confirms success', async () => {
  const h = harness(null); await h.tick();
  assert.equal((await h.message({ type: 'bind_tab', tabId: 7 })).ok, true);
  assert.equal((await h.message({ type: 'binding_status' })).boundTabId, 7);
});
test('only bound tab can relay images and events', async () => {
  const h = harness(); await h.tick();
  assert.match((await h.message({ type: 'bridge_context', contextID: 'a' }, { tab: { id: 8 } })).error, /not bound/);
  assert.equal((await h.message({ type: 'bridge_context', contextID: 'a' }, { tab: { id: 7 } })).dataURL, 'data:image/png;base64,AQID');
  await h.message({ type: 'bridge_event', event: { type: 'response_complete', id: 'a' } }, { tab: { id: 7 } });
  assert.equal(h.events[0].type, 'response_complete');
});
test('reinjecting content script registers only one receiver', () => {
  let count = 0;
  const context = vm.createContext({ chrome: { runtime: { onMessage: { addListener() { count++; } } } } });
  const content = fs.readFileSync('ChromeExtension/content.js', 'utf8');
  vm.runInContext(content, context); vm.runInContext(content, context);
  assert.equal(count, 1);
});
