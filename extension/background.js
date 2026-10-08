// Sotto Bridge — background (a service worker in Chrome and Edge, an event
// page in Firefox). Relays Sotto's requests, which arrive through the native
// messaging host, to the active tab, and the answers back.
//
// It acts only when Sotto asks, only on the active tab, and only while Sotto
// has armed it (auto-fill on, or a fill you started). It never reads pages
// on its own.

const HOST = 'app.sotto.bridge';
const OPS = new Set(['hello', 'arm', 'cancel', 'read', 'act', 'indicator']);
const ACTIONS = new Set(['value', 'select', 'toggle', 'choose', 'invoke']);
const MAX_TEXT = 10000;

/** A request from Sotto, checked before anything is done with it. */
function validRequest(m) {
  if (!m || typeof m !== 'object' || Array.isArray(m)) return false;
  if (m.v !== 1 || !Number.isInteger(m.id) || m.id < 0 || !OPS.has(m.op)) return false;
  if (m.op === 'arm' || m.op === 'indicator') return typeof m.on === 'boolean';
  if (m.op !== 'act') return true;
  if (typeof m.target !== 'string' || !/^ext:\d{1,6}$/.test(m.target) || !ACTIONS.has(m.action)) return false;
  if (m.action === 'value' || m.action === 'choose') return typeof m.arg === 'string' && m.arg.length <= MAX_TEXT;
  if (m.action === 'toggle') return typeof m.arg === 'boolean';
  return m.arg === undefined || m.arg === null;
}

/** A note from the native host itself: whether Sotto is at the other end. */
function hostEvent(m) {
  return !!m && m.v === 1 && m.event === 'sotto' && typeof m.connected === 'boolean';
}

/** The badge text, in the browser's language. */
function fillingLabel(language) {
  return (language || '').toLowerCase().startsWith('es') ? 'Sotto está rellenando' : 'Sotto is filling';
}

const ICON_SIZES = [16, 32, 48, 128];
function iconPaths(connected) {
  const name = connected ? 'icon-connected' : 'icon';
  return Object.fromEntries(ICON_SIZES.map((s) => [s, `icons/${name}-${s}.png`]));
}

function browserName(nav, api) {
  if (api && api.runtime && typeof api.runtime.getBrowserInfo === 'function') return 'firefox';
  const brands = (nav.userAgentData && nav.userAgentData.brands) || [];
  if (brands.some((b) => /edge/i.test(b.brand)) || /\bEdg\//.test(nav.userAgent || '')) return 'edge';
  return 'chrome';
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { validRequest, browserName, hostEvent, fillingLabel, iconPaths };
} else {
  const api = globalThis.browser ?? globalThis.chrome;
  let port = null;
  let armed = false;
  // Whether Sotto itself is at the other end of the host (not just the host).
  let sotto = false;
  // The tab showing the "Sotto is filling" badge.
  let badgeTab = null;

  const setSotto = (connected) => {
    sotto = connected;
    void api.action.setIcon({ path: iconPaths(connected) }).catch(() => {});
    if (!connected) void hideBadge();
  };

  const hideBadge = async () => {
    const tabId = badgeTab;
    badgeTab = null;
    if (tabId === null) return;
    try {
      await api.scripting.executeScript({
        target: { tabId },
        func: () => globalThis.__sottoBridge && globalThis.__sottoBridge.indicator(false),
      });
    } catch (_) {
      // The tab is gone or navigated: the badge went with it.
    }
  };
  // Bumped by cancel and disarm: a request already under way stops before
  // touching the page.
  let generation = 0;

  const connect = () => {
    if (port) return;
    try {
      port = api.runtime.connectNative(HOST);
    } catch (_) {
      port = null;
      return;
    }
    port.onMessage.addListener((m) => (hostEvent(m) ? setSotto(m.connected) : void handle(m)));
    port.onDisconnect.addListener(() => {
      // Sotto isn't installed, or the browser closed the host. Reading
      // lastError keeps Chrome from logging it as unchecked.
      void api.runtime.lastError;
      port = null;
      armed = false;
      generation++;
      setSotto(false);
    });
  };

  const send = (m) => {
    try {
      port?.postMessage(m);
    } catch (_) {
      // Disconnected meanwhile.
    }
  };

  const activeTab = async () => {
    const [tab] = await api.tabs.query({ active: true, lastFocusedWindow: true });
    return tab && tab.id !== undefined ? tab : null;
  };

  const inPage = async (tabId, op, args) => {
    const target = { tabId };
    await api.scripting.executeScript({ target, files: ['content.js'] });
    const [res] = await api.scripting.executeScript({
      target,
      func: (o, a) => globalThis.__sottoBridge.handle(o, a),
      args: [op, args ?? null],
    });
    return res ? res.result : null;
  };

  async function handle(m) {
    if (!validRequest(m)) return;
    const reply = (body) => send({ v: 1, id: m.id, ...body });
    switch (m.op) {
      case 'hello':
        // Only Sotto asks this: it is there.
        if (!sotto) setSotto(true);
        return reply({ ok: true, result: { browser: browserName(navigator, api), version: api.runtime.getManifest().version } });
      case 'arm':
        armed = m.on;
        if (!armed) {
          generation++;
          await hideBadge();
        }
        return reply({ ok: true, result: {} });
      case 'cancel':
        generation++;
        await hideBadge();
        return reply({ ok: true, result: {} });
      case 'indicator':
        if (!m.on) {
          await hideBadge();
          return reply({ ok: true, result: { done: true } });
        }
    }
    if (!armed) return reply({ ok: false, error: 'not_armed' });
    const gen = generation;
    try {
      const tab = await activeTab();
      if (!tab) return reply({ ok: false, error: 'no_tab' });
      if (gen !== generation) return reply({ ok: false, error: 'cancelled' });
      if (m.op === 'indicator') {
        if (badgeTab !== null && badgeTab !== tab.id) await hideBadge();
        await inPage(tab.id, 'indicator', { on: true, label: fillingLabel(navigator.language) });
        badgeTab = tab.id;
        // Cancelled while it was going up: take it straight down.
        if (gen !== generation) {
          await hideBadge();
          return reply({ ok: false, error: 'cancelled' });
        }
        return reply({ ok: true, result: { done: true } });
      }
      const args = m.op === 'act' ? { target: m.target, action: m.action, arg: m.arg ?? null } : null;
      const result = await inPage(tab.id, m.op, args);
      if (m.op === 'read') return reply(result ? { ok: true, result } : { ok: false, error: 'no_result' });
      return reply({ ok: true, result: { done: result === true } });
    } catch (_) {
      // Not allowed on this page (browser pages, the store, or a site the
      // extension hasn't been granted): Sotto falls back to accessibility.
      return reply({ ok: false, error: 'no_access' });
    }
  }

  // The popup asks whether Sotto is connected, and can reconnect.
  api.runtime.onMessage.addListener((m, _sender, respond) => {
    if (m && m.type === 'status') respond({ connected: port !== null && sotto, armed });
    if (m && m.type === 'reconnect') {
      connect();
      respond({ connected: port !== null });
    }
  });

  api.runtime.onStartup.addListener(connect);
  api.runtime.onInstalled.addListener(connect);
  connect();
}
