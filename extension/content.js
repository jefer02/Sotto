// Sotto Bridge — the page side. Injected into the active tab by
// background.js only when Sotto asks (never declared as a content script, so
// it never runs on its own). Reads the page's form controls and fills them.
//
// Safety: password, one-time-code and payment fields are reported as
// `sensitive` with no value, and are never filled.
//
// The same file runs under Node for the tests (module.exports below).

/* exported sottoForms */
function sottoForms(win) {
  const doc = win.document;

  // Mirrors SafetyGate in lib/domain/agent/safety.dart.
  const SECRET = /pass(word|code|phrase)|contrase(ñ|n)a|passwort|mot de passe|\bpin\b|\bsecret\b|one[- ]time code|\b2fa\b|\botp\b/i;
  const PAYMENT = new RegExp(
    'card ?number|credit|debit|\\bcvv\\b|\\bcvc\\b|\\bcsc\\b|security code|expir|\\biban\\b|\\bswift\\b|routing|account number|' +
      'billing|tarjeta|caducidad|vencimiento|c[oó]digo de seguridad|n[uú]mero de cuenta|titular|facturaci[oó]n',
    'i',
  );
  const SENSITIVE_AUTOCOMPLETE = new Set(['current-password', 'new-password', 'one-time-code']);
  const MAX_FIELDS = 800;

  // Element ids live here, in the extension's own world: the page's DOM is
  // never marked.
  const byId = new Map();
  const ids = new WeakMap();
  let next = 0;
  const idOf = (el) => {
    let id = ids.get(el);
    if (!id) {
      id = 'ext:' + next++;
      ids.set(el, id);
      byId.set(id, new WeakRef(el));
    }
    return id;
  };
  const find = (id) => {
    const el = byId.get(id)?.deref();
    return el && el.isConnected ? el : null;
  };

  const text = (el) => (el ? el.innerText || el.textContent || '' : '').replace(/\s+/g, ' ').trim();
  const words = (s) => (s || '').replace(/[_\-.[\]]+/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2');

  const visible = (el) => {
    const r = el.getBoundingClientRect();
    const s = win.getComputedStyle(el);
    return r.width > 1 && r.height > 1 && s.visibility !== 'hidden' && s.display !== 'none';
  };

  // Screen bounds in physical pixels. Firefox knows where the viewport is;
  // elsewhere it is estimated from the window frame.
  const box = (el) => {
    const r = el.getBoundingClientRect();
    const dpr = win.devicePixelRatio || 1;
    let left, top;
    if (typeof win.mozInnerScreenX === 'number') {
      left = win.mozInnerScreenX;
      top = win.mozInnerScreenY;
    } else {
      const bx = Math.max(0, (win.outerWidth - win.innerWidth) / 2);
      left = win.screenX + bx;
      top = win.screenY + Math.max(0, win.outerHeight - win.innerHeight - bx);
    }
    return [(left + r.left) * dpr, (top + r.top) * dpr, r.width * dpr, r.height * dpr];
  };

  const escape = (s) => (win.CSS && win.CSS.escape ? win.CSS.escape(s) : String(s).replace(/["\\]/g, '\\$&'));

  const labelOf = (el) => {
    const a = el.getAttribute('aria-label');
    if (a) return a.trim();
    const lb = el.getAttribute('aria-labelledby');
    if (lb) {
      const t = lb.split(/\s+/).map((i) => text(doc.getElementById(i))).join(' ').trim();
      if (t) return t;
    }
    if (el.id) {
      const l = doc.querySelector('label[for="' + escape(el.id) + '"]');
      if (l) return text(l);
    }
    const wrap = el.closest('label');
    if (wrap) return text(wrap);
    return (el.getAttribute('placeholder') || el.getAttribute('title') || el.getAttribute('name') || text(el)).trim();
  };

  /** Password, one-time-code or payment: by type, autocomplete, label, name or id. */
  const sensitive = (el, label) => {
    const type = (el.getAttribute('type') || '').toLowerCase();
    if (type === 'password') return true;
    const ac = (el.getAttribute('autocomplete') || '').toLowerCase().split(/\s+/);
    if (ac.some((t) => t.startsWith('cc-') || SENSITIVE_AUTOCOMPLETE.has(t))) return true;
    const hay = [label, el.getAttribute('name'), el.id, el.getAttribute('placeholder')].map(words).join(' ');
    return SECRET.test(hay) || PAYMENT.test(hay);
  };

  const question = (el) => {
    const g = el.closest('fieldset,[role=radiogroup],[role=group],[role=listitem],.question,[data-question]');
    if (g) {
      const lg = g.querySelector('legend,[role=heading],h1,h2,h3,h4,label');
      const aria = g.getAttribute('aria-label');
      return [g, aria || (lg ? text(lg) : text(g).slice(0, 200))];
    }
    return [el.parentElement, text(el.parentElement).slice(0, 200)];
  };

  function read() {
    const out = [];
    const seen = new Set();
    const groups = new Set();
    const group = (el) => {
      const [g, label] = question(el);
      if (!g) return null;
      if (!groups.has(g)) {
        groups.add(g);
        seen.add(g);
        out.push({ id: idOf(g), type: 'group', name: label, bounds: box(g) });
      }
      return idOf(g);
    };
    const controls = doc.querySelectorAll(
      'input,textarea,select,[role=radio],[role=checkbox],[contenteditable=true],button,[role=button]',
    );
    for (const el of controls) {
      if (out.length >= MAX_FIELDS) break;
      if (el.disabled || !visible(el)) continue;
      const t = (el.getAttribute('type') || '').toLowerCase();
      const role = el.getAttribute('role');
      const name = labelOf(el);
      const e = { id: idOf(el), name, bounds: box(el) };
      if (el.tagName === 'SELECT') {
        e.type = 'combo';
        e.patterns = ['expand', 'value'];
        if (sensitive(el, name)) e.sensitive = true;
        else {
          e.options = [...el.options].map((o) => o.text.trim());
          e.value = el.selectedOptions[0] ? el.selectedOptions[0].text.trim() : '';
        }
      } else if (t === 'radio' || role === 'radio') {
        e.type = 'radio';
        e.checked = el.checked === true || el.getAttribute('aria-checked') === 'true';
        e.patterns = ['select'];
        e.parent = group(el);
      } else if (t === 'checkbox' || role === 'checkbox') {
        e.type = 'checkbox';
        e.checked = el.checked === true || el.getAttribute('aria-checked') === 'true';
        e.patterns = ['toggle'];
        e.parent = group(el);
      } else if (el.tagName === 'BUTTON' || role === 'button' || t === 'submit' || t === 'button') {
        e.type = 'button';
        e.name = name || el.value || '';
        e.patterns = ['invoke'];
      } else if (el.tagName === 'TEXTAREA' || el.isContentEditable || el.getAttribute('contenteditable') === 'true') {
        e.type = 'edit';
        e.multiline = true;
        e.patterns = ['value'];
        if (sensitive(el, name)) e.sensitive = true;
        else e.value = el.tagName === 'TEXTAREA' ? el.value : text(el);
      } else if (el.tagName === 'INPUT' && !['hidden', 'file', 'image', 'reset', 'range', 'color'].includes(t)) {
        e.type = 'edit';
        e.patterns = ['value'];
        if (sensitive(el, name)) e.sensitive = true;
        else e.value = el.value;
      } else continue;
      if (e.sensitive) e.patterns = [];
      seen.add(el);
      out.push(e);
    }
    // Lettered options drawn as plain elements: "A. …", "B) …".
    const lettered = /^\(?[A-Ha-h][.)]\s+\S/;
    for (const el of doc.querySelectorAll('li,label,div,span,p')) {
      if (out.length >= MAX_FIELDS) break;
      if (seen.has(el) || el.children.length > 3 || !visible(el)) continue;
      const s = text(el);
      if (s.length > 300 || !lettered.test(s)) continue;
      if (el.querySelector('input,[role=radio],[role=checkbox]')) continue;
      // Inside a control already collected (a question group doesn't count).
      let anc = el.parentElement;
      while (anc && !seen.has(anc)) anc = anc.parentElement;
      if (anc && !groups.has(anc)) continue;
      seen.add(el);
      out.push({
        id: idOf(el),
        type: 'radio',
        name: s,
        bounds: box(el),
        checked: el.getAttribute('aria-checked') === 'true' || el.classList.contains('selected'),
        patterns: ['select'],
        parent: group(el),
      });
    }
    return { title: doc.title || '', origin: win.location ? win.location.origin : '', fields: out };
  }

  const fold = (s) =>
    (s || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();

  const fire = (el, type) => el.dispatchEvent(new win.Event(type, { bubbles: true }));

  // A real click sequence, so React / Vue / Angular see a user's click.
  const click = (el) => {
    const opts = { bubbles: true, cancelable: true, view: win, button: 0 };
    const P = win.PointerEvent || win.MouseEvent;
    el.dispatchEvent(new P('pointerdown', opts));
    el.dispatchEvent(new win.MouseEvent('mousedown', opts));
    el.dispatchEvent(new P('pointerup', opts));
    el.dispatchEvent(new win.MouseEvent('mouseup', opts));
    el.click();
  };

  const isChecked = (el) => el.checked === true || el.getAttribute('aria-checked') === 'true';

  // Sets the value the way typing would: the prototype's setter (so a
  // framework's value tracker notices), then input and change.
  const setValue = (el, value) => {
    if (el.isContentEditable || el.getAttribute('contenteditable') === 'true') {
      el.textContent = value;
    } else {
      const proto = el.tagName === 'TEXTAREA' ? win.HTMLTextAreaElement.prototype : el.tagName === 'SELECT'
        ? win.HTMLSelectElement.prototype
        : win.HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    }
    fire(el, 'input');
    fire(el, 'change');
  };

  /** One action on a field read before. Returns true when it was done. */
  function act(id, op, arg) {
    const el = find(id);
    if (!el || el.disabled) return false;
    // Never typed into or chosen for: checked again here, whatever was read.
    const valued = op === 'value' || op === 'choose' || (el.getAttribute('type') || '').toLowerCase() === 'password';
    if (valued && sensitive(el, labelOf(el))) return false;
    if (el.scrollIntoView) el.scrollIntoView({ block: 'center' });
    switch (op) {
      case 'value':
        if (typeof arg !== 'string') return false;
        if (el.focus) el.focus();
        setValue(el, arg);
        return true;
      case 'select':
        if (!isChecked(el)) click(el);
        return true;
      case 'invoke':
        click(el);
        return true;
      case 'toggle':
        if (typeof arg !== 'boolean') return false;
        if (isChecked(el) !== arg) click(el);
        return true;
      case 'choose': {
        if (el.tagName !== 'SELECT' || typeof arg !== 'string') return false;
        const want = fold(arg);
        const opts = [...el.options];
        const o = opts.find((o) => fold(o.text) === want) || opts.find((o) => want && fold(o.text).includes(want));
        if (!o) return false;
        setValue(el, o.value);
        return true;
      }
      default:
        return false;
    }
  }

  // ─────────── "Sotto is filling" ───────────
  // A small badge in the bottom-right corner while a fill runs. It lives in
  // a closed shadow root (the page's styles can't reach it, and it can't
  // reach the page's), takes no clicks, and goes the moment the fill ends
  // or is cancelled.
  let badge = null;

  const BADGE_CSS = `
    :host { all: initial; }
    .badge {
      display: inline-flex; align-items: center; gap: 8px;
      padding: 7px 12px 7px 10px; border-radius: 999px;
      font: 600 12px/1.2 system-ui, -apple-system, "Segoe UI", sans-serif; letter-spacing: .01em;
      color: #FFFFFF;
      background: linear-gradient(180deg, #6D5CF0 0%, #4A3BC4 100%);
      box-shadow: 0 0 0 1px rgba(20, 17, 43, .18), 0 6px 18px rgba(91, 75, 219, .38), 0 0 24px rgba(109, 92, 240, .35);
      animation: in 160ms ease-out;
    }
    .dot { width: 7px; height: 7px; border-radius: 50%; background: #C9A45C; box-shadow: 0 0 0 3px rgba(201, 164, 92, .25); animation: breathe 1.6s ease-in-out infinite; }
    @keyframes in { from { opacity: 0; transform: translateY(4px); } to { opacity: 1; transform: none; } }
    @keyframes breathe { 50% { box-shadow: 0 0 0 5px rgba(201, 164, 92, .12); } }
    @media (prefers-reduced-motion: reduce) { .badge, .dot { animation: none; } }
  `;

  function indicator(on, label) {
    if (!on) {
      if (badge) badge.remove();
      badge = null;
      return true;
    }
    if (badge && badge.isConnected) return true;
    const host = doc.createElement('sotto-indicator');
    // Inline !important: page CSS that targets the host can't move it over a
    // field or make it clickable.
    const set = (k, v) => host.style.setProperty(k, v, 'important');
    set('all', 'initial');
    set('position', 'fixed');
    set('right', '16px');
    set('bottom', '16px');
    set('z-index', '2147483647');
    set('pointer-events', 'none');
    set('user-select', 'none');
    host.setAttribute('aria-hidden', 'true');
    const root = host.attachShadow({ mode: 'closed' });
    const style = doc.createElement('style');
    style.textContent = BADGE_CSS;
    const pill = doc.createElement('div');
    pill.className = 'badge';
    const dot = doc.createElement('span');
    dot.className = 'dot';
    const text = doc.createElement('span');
    text.textContent = typeof label === 'string' && label ? label.slice(0, 60) : 'Sotto is filling';
    pill.append(dot, text);
    root.append(style, pill);
    (doc.documentElement || doc.body).appendChild(host);
    badge = host;
    return true;
  }

  return {
    read,
    act,
    sensitive,
    indicator,
    /** The badge element, for tests. */
    get badge() {
      return badge;
    },
    handle(op, args) {
      if (op === 'read') return read();
      if (op === 'act' && args) return act(args.target, args.action, args.arg);
      if (op === 'indicator' && args) return indicator(args.on === true, args.label);
      return null;
    },
  };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { sottoForms };
} else if (!globalThis.__sottoBridge) {
  // Injected again on every request: the first injection's ids stay valid.
  globalThis.__sottoBridge = sottoForms(window);
}
