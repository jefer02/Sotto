// DOM tests for the page side: what is read, what is never sent, and how
// fields are filled. Run with `npm test` in extension/.
const test = require('node:test');
const assert = require('node:assert/strict');
const { JSDOM } = require('jsdom');
const { sottoForms } = require('../content.js');
const { validRequest, browserName } = require('../background.js');

function page(html) {
  const dom = new JSDOM(`<!doctype html><title>Sign-up</title><body>${html}</body>`, { url: 'https://example.org/form' });
  const win = dom.window;
  // jsdom has no layout: every element gets a visible box.
  win.Element.prototype.getBoundingClientRect = () => ({ left: 10, top: 20, width: 100, height: 24 });
  return { win, doc: win.document, bridge: sottoForms(win) };
}

const field = (r, name, type) => r.fields.find((f) => f.name === name && (!type || f.type === type));

test('reads text fields, selects, radio groups and checkboxes with labels', () => {
  const { bridge } = page(`
    <label for="n">Full name</label><input id="n" value="Ada">
    <label>Country <select name="c"><option>Spain</option><option selected>Mexico</option></select></label>
    <fieldset><legend>How often?</legend>
      <label><input type="radio" name="f"> Daily</label>
      <label><input type="radio" name="f" checked> Weekly</label>
    </fieldset>
    <textarea aria-label="Comments">Hi</textarea>
    <button>Next</button>`);
  const r = bridge.read();
  assert.equal(r.title, 'Sign-up');
  assert.equal(r.origin, 'https://example.org');
  assert.equal(field(r, 'Full name').value, 'Ada');
  const country = r.fields.find((f) => f.type === 'combo');
  assert.deepEqual(country.options, ['Spain', 'Mexico']);
  assert.equal(country.value, 'Mexico');
  const group = field(r, 'How often?');
  assert.equal(group.type, 'group');
  const radios = r.fields.filter((f) => f.type === 'radio');
  assert.equal(radios.length, 2);
  assert.ok(radios.every((f) => f.parent === group.id));
  assert.equal(radios[1].checked, true);
  assert.equal(field(r, 'Comments').multiline, true);
  assert.equal(field(r, 'Next').type, 'button');
  assert.ok(r.fields.every((f) => /^ext:\d+$/.test(f.id) && f.bounds.length === 4));
});

test('never sends password, one-time-code or payment values', () => {
  const { bridge } = page(`
    <label for="p">Password</label><input id="p" type="password" value="hunter2">
    <input name="card_number" value="4111 1111 1111 1111">
    <input autocomplete="cc-csc" aria-label="CVC" value="123">
    <input autocomplete="one-time-code" aria-label="Code" value="998877">
    <label for="i">IBAN</label><input id="i" value="ES9121000418450200051332">
    <label>Expiry month <select><option>01</option><option selected>07</option></select></label>
    <label for="e">Email</label><input id="e" value="ada@example.org">`);
  const r = bridge.read();
  const json = JSON.stringify(r);
  for (const secret of ['hunter2', '4111', '123"', '998877', 'ES9121', '"07"']) {
    assert.ok(!json.includes(secret), `leaked ${secret}`);
  }
  const sensitive = r.fields.filter((f) => f.sensitive);
  assert.equal(sensitive.length, 6);
  assert.ok(sensitive.every((f) => f.value === undefined && f.options === undefined && f.patterns.length === 0));
  assert.equal(field(r, 'Email').value, 'ada@example.org');
  assert.equal(field(r, 'Email').sensitive, undefined);
});

test('refuses to fill sensitive fields', () => {
  const { bridge, doc } = page(`
    <label for="p">Password</label><input id="p" type="password">
    <input id="cc" name="cardnumber" aria-label="Number on card">`);
  const r = bridge.read();
  for (const f of r.fields) assert.equal(bridge.act(f.id, 'value', 'x'), false);
  assert.equal(doc.getElementById('p').value, '');
  assert.equal(doc.getElementById('cc').value, '');
});

test('fills text with input and change events', () => {
  const { bridge, doc } = page('<label for="n">Name</label><input id="n">');
  const el = doc.getElementById('n');
  const events = [];
  el.addEventListener('input', () => events.push('input'));
  el.addEventListener('change', () => events.push('change'));
  const id = field(bridge.read(), 'Name').id;
  assert.equal(bridge.act(id, 'value', 'Ada Lovelace'), true);
  assert.equal(el.value, 'Ada Lovelace');
  assert.deepEqual(events, ['input', 'change']);
});

test('radios and checkboxes get a real click sequence', () => {
  const { bridge, doc } = page(`
    <fieldset><legend>Pick</legend><label><input id="a" type="radio" name="x"> One</label></fieldset>
    <label><input id="c" type="checkbox"> I agree</label>`);
  const seen = [];
  for (const t of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click', 'change']) {
    doc.getElementById('a').addEventListener(t, () => seen.push(t));
  }
  const r = bridge.read();
  assert.equal(bridge.act(field(r, 'One', 'radio').id, 'select'), true);
  assert.equal(doc.getElementById('a').checked, true);
  assert.deepEqual(seen, ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click', 'change']);
  const agree = field(r, 'I agree', 'checkbox').id;
  assert.equal(bridge.act(agree, 'toggle', true), true);
  assert.equal(doc.getElementById('c').checked, true);
  // Already on: no second click.
  assert.equal(bridge.act(agree, 'toggle', true), true);
  assert.equal(doc.getElementById('c').checked, true);
});

test('chooses a select option by its text, accents and case aside', () => {
  const { bridge, doc } = page('<label for="s">Level</label><select id="s"><option value="1">Básico</option><option value="2">Avanzado</option></select>');
  const id = field(bridge.read(), 'Level').id;
  assert.equal(bridge.act(id, 'choose', 'avanzado'), true);
  assert.equal(doc.getElementById('s').value, '2');
  assert.equal(bridge.act(id, 'choose', 'Experto'), false);
});

test('lettered options drawn as plain elements are radios of one question', () => {
  const { bridge } = page(`
    <div class="question"><h3>Which colour do you prefer?</h3>
      <div>A. Red</div><div>B. Green</div><div>C) Blue</div><div>D. Yellow</div></div>`);
  const r = bridge.read();
  const opts = r.fields.filter((f) => f.type === 'radio');
  assert.deepEqual(opts.map((o) => o.name), ['A. Red', 'B. Green', 'C) Blue', 'D. Yellow']);
  const parent = r.fields.find((f) => f.id === opts[0].parent);
  assert.equal(parent.name, 'Which colour do you prefer?');
  // A second read finds them again, with the same ids.
  const again = bridge.read().fields.filter((f) => f.type === 'radio');
  assert.deepEqual(again.map((o) => o.id), opts.map((o) => o.id));
});

test('skips hidden and disabled controls', () => {
  const { bridge } = page(`
    <input aria-label="Hidden" style="display:none"><input aria-label="Off" disabled><input aria-label="On">`);
  assert.deepEqual(bridge.read().fields.map((f) => f.name), ['On']);
});

test('unknown ids and ops do nothing', () => {
  const { bridge } = page('<input aria-label="A">');
  bridge.read();
  assert.equal(bridge.act('ext:999', 'value', 'x'), false);
  assert.equal(bridge.handle('eval', {}), null);
});

test('background validates every request from Sotto', () => {
  assert.equal(validRequest({ v: 1, id: 1, op: 'read' }), true);
  assert.equal(validRequest({ v: 1, id: 2, op: 'act', target: 'ext:3', action: 'value', arg: 'hi' }), true);
  assert.equal(validRequest({ v: 1, id: 2, op: 'act', target: 'ext:3', action: 'toggle', arg: true }), true);
  assert.equal(validRequest({ v: 1, id: 2, op: 'arm', on: true }), true);
  assert.equal(validRequest({ v: 2, id: 1, op: 'read' }), false);
  assert.equal(validRequest({ v: 1, id: 1.5, op: 'read' }), false);
  assert.equal(validRequest({ v: 1, id: 1, op: 'eval' }), false);
  assert.equal(validRequest({ v: 1, id: 1, op: 'arm', on: 'yes' }), false);
  assert.equal(validRequest({ v: 1, id: 1, op: 'act', target: '#pw', action: 'value', arg: 'x' }), false);
  assert.equal(validRequest({ v: 1, id: 1, op: 'act', target: 'ext:1', action: 'submit' }), false);
  assert.equal(validRequest({ v: 1, id: 1, op: 'act', target: 'ext:1', action: 'value', arg: 'x'.repeat(10001) }), false);
  assert.equal(validRequest([]), false);
  assert.equal(validRequest(null), false);
});

test('background names the browser', () => {
  assert.equal(browserName({ userAgent: 'Mozilla/5.0 Chrome/140.0' }, {}), 'chrome');
  assert.equal(browserName({ userAgent: 'Mozilla/5.0 Chrome/140.0 Edg/140.0' }, {}), 'edge');
  assert.equal(browserName({ userAgent: '' }, { runtime: { getBrowserInfo() {} } }), 'firefox');
});

test('"Sotto is filling" badge: closed shadow root, corner, no clicks, removed at once', () => {
  const { bridge, doc, win } = page('<label for="n">Name</label><input id="n">');
  // A hostile page style can't move or enable it.
  const style = doc.createElement('style');
  style.textContent = 'sotto-indicator { left: 0 !important; top: 0 !important; pointer-events: auto !important; }';
  doc.head.appendChild(style);

  assert.equal(bridge.handle('indicator', { on: true, label: 'Sotto is filling' }), true);
  const host = doc.querySelector('sotto-indicator');
  assert.ok(host);
  assert.equal(host.shadowRoot, null, 'closed shadow root');
  assert.equal(host.getAttribute('aria-hidden'), 'true');
  for (const [k, v] of [['position', 'fixed'], ['right', '16px'], ['bottom', '16px'], ['pointer-events', 'none']]) {
    assert.equal(host.style.getPropertyValue(k), v);
    assert.equal(host.style.getPropertyPriority(k), 'important');
  }
  assert.equal(win.getComputedStyle(host).pointerEvents, 'none');
  // The page's own form is untouched.
  assert.equal(doc.getElementById('n').parentElement, doc.body);
  // Once only.
  bridge.indicator(true);
  assert.equal(doc.querySelectorAll('sotto-indicator').length, 1);

  bridge.handle('indicator', { on: false });
  assert.equal(doc.querySelector('sotto-indicator'), null);
  assert.equal(bridge.badge, null);
});

test('background: indicator requests, host events, icons and labels', () => {
  const { hostEvent, fillingLabel, iconPaths } = require('../background.js');
  assert.equal(validRequest({ v: 1, id: 4, op: 'indicator', on: true }), true);
  assert.equal(validRequest({ v: 1, id: 4, op: 'indicator' }), false);
  assert.equal(hostEvent({ v: 1, event: 'sotto', connected: true }), true);
  assert.equal(hostEvent({ v: 1, event: 'sotto', connected: 'yes' }), false);
  assert.equal(hostEvent({ v: 1, id: 1, op: 'read' }), false);
  assert.equal(fillingLabel('es-MX'), 'Sotto está rellenando');
  assert.equal(fillingLabel('en-US'), 'Sotto is filling');
  assert.deepEqual(iconPaths(true), {
    16: 'icons/icon-connected-16.png',
    32: 'icons/icon-connected-32.png',
    48: 'icons/icon-connected-48.png',
    128: 'icons/icon-connected-128.png',
  });
  const fs = require('node:fs');
  const path = require('node:path');
  for (const p of [...Object.values(iconPaths(true)), ...Object.values(iconPaths(false))]) {
    assert.ok(fs.existsSync(path.join(__dirname, '..', p)), p);
  }
});

test('manifest asks for no new permissions and lists every icon', () => {
  const m = require('../manifest.json');
  assert.deepEqual(m.permissions, ['activeTab', 'scripting', 'nativeMessaging']);
  assert.deepEqual(Object.keys(m.icons), ['16', '32', '48', '128']);
  assert.deepEqual(m.action.default_icon, m.icons);
});
