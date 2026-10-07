import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/forms/form_model.dart';

/// A Chromium page's form controls through the Chrome DevTools Protocol —
/// for pages whose UI Automation tree shows fewer than two fields (custom
/// widgets, lettered options drawn as plain elements).
///
/// Only reachable when the browser runs with `--remote-debugging-port`
/// (default 9222, see the README). Localhost only; nothing leaves the
/// machine. Without it every call returns null and the screenshot does the
/// work.
class CdpDom {
  CdpDom({this.port = 9222});

  final int port;

  /// The page tab whose title the browser window shows, or null.
  Future<CdpPage?> attach(String pageTitle) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 400);
    try {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/json/list'));
      final res = await req.close().timeout(const Duration(milliseconds: 800));
      if (res.statusCode != 200) return null;
      final targets = jsonDecode(await res.transform(utf8.decoder).join());
      if (targets is! List) return null;
      final pages = [
        for (final t in targets.whereType<Map<Object?, Object?>>())
          if (t['type'] == 'page' && t['webSocketDebuggerUrl'] is String) t,
      ];
      final want = pageTitle.trim().toLowerCase();
      final page =
          pages.where((t) => '${t['title']}'.trim().toLowerCase() == want).firstOrNull ??
          pages.where((t) => want.isNotEmpty && want.contains('${t['title']}'.trim().toLowerCase())).firstOrNull;
      if (page == null) return null;
      final socket = await WebSocket.connect(page['webSocketDebuggerUrl']! as String)
          .timeout(const Duration(seconds: 1));
      return CdpPage(socket);
    } catch (e) {
      // No debugging port: the usual case.
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// One attached tab. Element ids are `cdp:N`, stamped on the page as
/// `data-sotto-id` so actions find them again.
class CdpPage {
  CdpPage(this._socket) {
    _sub = _socket.listen(_onMessage, onDone: _failAll, onError: (_) => _failAll());
  }

  final WebSocket _socket;
  late final StreamSubscription<dynamic> _sub;
  var _nextId = 0;
  final _pending = <int, Completer<Object?>>{};

  void _onMessage(dynamic data) {
    final m = jsonDecode('$data');
    if (m is! Map || m['id'] is! int) return;
    final c = _pending.remove(m['id']);
    final result = m['result'];
    c?.complete(result is Map && result['result'] is Map ? (result['result'] as Map)['value'] : null);
  }

  void _failAll() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
  }

  Future<Object?> _eval(String expression) {
    final id = ++_nextId;
    final c = _pending[id] = Completer<Object?>();
    _socket.add(
      jsonEncode({
        'id': id,
        'method': 'Runtime.evaluate',
        'params': {'expression': expression, 'returnByValue': true, 'awaitPromise': false},
      }),
    );
    return c.future.timeout(const Duration(seconds: 3), onTimeout: () => null);
  }

  /// The page's controls in [UiElement] form (bounds in physical pixels).
  Future<List<UiElement>> readFields() async {
    final raw = await _eval(readScript);
    return parseFields(raw);
  }

  /// [raw] is the JSON string the page script returns.
  @visibleForTesting
  static List<UiElement> parseFields(Object? raw) {
    if (raw is! String) return const [];
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [for (final m in list.whereType<Map<Object?, Object?>>()) UiElement.fromMap(m)];
  }

  Future<bool> _act(String id, String op, [Object? arg]) async =>
      await _eval('($actScript)(${jsonEncode(id)}, ${jsonEncode(op)}, ${jsonEncode(arg)})') == true;

  Future<bool> setValue(String id, String text) => _act(id, 'value', text);
  Future<bool> select(String id) => _act(id, 'select');
  Future<bool> toggle(String id, bool on) => _act(id, 'toggle', on);
  Future<bool> choose(String id, String label) => _act(id, 'choose', label);
  Future<bool> invoke(String id) => _act(id, 'invoke');

  Future<void> close() async {
    _failAll();
    await _sub.cancel();
    await _socket.close();
  }

  /// Collects inputs, text areas, selects, ARIA radios / checkboxes and
  /// lettered options ("A. Paris") drawn as plain elements, grouped by
  /// question, with labels and screen bounds.
  static const readScript = r'''
(() => {
  const dpr = window.devicePixelRatio || 1;
  const bx = (window.outerWidth - window.innerWidth) / 2;
  const top = window.outerHeight - window.innerHeight - bx;
  const box = (el) => {
    const r = el.getBoundingClientRect();
    return [(window.screenX + bx + r.left) * dpr, (window.screenY + top + r.top) * dpr, r.width * dpr, r.height * dpr];
  };
  const visible = (el) => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el);
    return r.width > 1 && r.height > 1 && s.visibility !== 'hidden' && s.display !== 'none'; };
  const text = (el) => (el ? (el.innerText || el.textContent || '') : '').replace(/\s+/g, ' ').trim();
  const out = []; let n = 0;
  const id = (el) => { if (!el.dataset.sottoId) el.dataset.sottoId = 'cdp:' + (n++); return el.dataset.sottoId; };
  document.querySelectorAll('[data-sotto-id]').forEach(e => { const k = parseInt((e.dataset.sottoId || '').slice(4)); if (k >= n) n = k + 1; });
  const labelOf = (el) => {
    const a = el.getAttribute('aria-label'); if (a) return a.trim();
    const lb = el.getAttribute('aria-labelledby');
    if (lb) { const t = lb.split(/\s+/).map(i => text(document.getElementById(i))).join(' ').trim(); if (t) return t; }
    if (el.id) { const l = document.querySelector('label[for="' + CSS.escape(el.id) + '"]'); if (l) return text(l); }
    const wrap = el.closest('label'); if (wrap) return text(wrap);
    return (el.getAttribute('placeholder') || el.getAttribute('title') || el.getAttribute('name') || text(el)).trim();
  };
  const question = (el) => {
    const g = el.closest('fieldset,[role=radiogroup],[role=group],[role=listitem],.question,[data-question]');
    if (g) { const lg = g.querySelector('legend,[role=heading],h1,h2,h3,h4,label'); const aria = g.getAttribute('aria-label');
      return [g, aria || (lg ? text(lg) : text(g).slice(0, 200))]; }
    return [el.parentElement, text(el.parentElement).slice(0, 200)];
  };
  const groups = new Map();
  const group = (el) => { const [g, label] = question(el); if (!g) return null;
    if (!groups.has(g)) { groups.set(g, true); out.push({id: id(g), type: 'group', name: label, bounds: box(g)}); }
    return g.dataset.sottoId; };
  for (const el of document.querySelectorAll('input,textarea,select,[role=radio],[role=checkbox],[contenteditable=true],button,[role=button],input[type=submit]')) {
    if (!visible(el) || el.disabled) continue;
    const t = (el.getAttribute('type') || '').toLowerCase();
    const role = el.getAttribute('role');
    let type = null; const e = {id: id(el), name: labelOf(el), bounds: box(el)};
    if (el.tagName === 'SELECT') { type = 'combo'; e.options = [...el.options].map(o => o.text.trim()); e.value = el.selectedOptions[0] ? el.selectedOptions[0].text.trim() : ''; e.patterns = ['expand', 'value']; }
    else if (t === 'radio' || role === 'radio') { type = 'radio'; e.checked = el.checked === true || el.getAttribute('aria-checked') === 'true'; e.patterns = ['select']; e.parent = group(el); }
    else if (t === 'checkbox' || role === 'checkbox') { type = 'checkbox'; e.checked = el.checked === true || el.getAttribute('aria-checked') === 'true'; e.patterns = ['toggle']; e.parent = group(el); }
    else if (el.tagName === 'BUTTON' || role === 'button' || t === 'submit' || t === 'button') { type = 'button'; e.name = labelOf(el) || el.value || ''; e.patterns = ['invoke']; }
    else if (el.tagName === 'TEXTAREA' || el.isContentEditable) { type = 'edit'; e.multiline = true; e.value = el.value !== undefined ? el.value : text(el); e.patterns = ['value']; }
    else if (el.tagName === 'INPUT' && !['hidden', 'file', 'image', 'reset', 'range', 'color'].includes(t)) { type = 'edit'; e.value = el.value; e.password = t === 'password'; e.patterns = ['value']; }
    if (!type) continue;
    e.type = type; out.push(e);
  }
  // Lettered options drawn as plain elements: "A. …", "B) …".
  const lettered = /^\(?[A-Ha-h][.)]\s+\S/;
  for (const el of document.querySelectorAll('li,label,div,span,p,button')) {
    if (el.dataset.sottoId || !visible(el) || el.children.length > 3) continue;
    const s = text(el); if (s.length > 300 || !lettered.test(s)) continue;
    if (el.querySelector('input,[role=radio],[role=checkbox]')) continue;
    // Inside a control already collected (a question group doesn't count).
    const anc = el.parentElement && el.parentElement.closest('[data-sotto-id]');
    if (anc && !groups.has(anc)) continue;
    out.push({id: id(el), type: 'radio', name: s, bounds: box(el), checked: el.getAttribute('aria-checked') === 'true' || el.classList.contains('selected'), patterns: ['select'], parent: group(el)});
  }
  return JSON.stringify(out);
})()
''';

  /// Acts on one stamped element: set a value the way typing would (so
  /// React / Vue see it), click a radio or checkbox, pick a select option.
  static const actScript = r'''
(id, op, arg) => {
  const el = document.querySelector('[data-sotto-id="' + id + '"]'); if (!el) return false;
  const fold = (s) => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  el.scrollIntoView({block: 'center'});
  if (op === 'value') {
    if ((el.getAttribute('type') || '').toLowerCase() === 'password') return false;
    el.focus();
    if (el.isContentEditable) { el.textContent = arg; }
    else { const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, arg); }
    el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true}));
    return true;
  }
  if (op === 'select' || op === 'invoke') { el.click(); return true; }
  if (op === 'toggle') { const on = el.checked === true || el.getAttribute('aria-checked') === 'true'; if (on !== arg) el.click(); return true; }
  if (op === 'choose' && el.tagName === 'SELECT') {
    const want = fold(arg); const o = [...el.options].find(o => fold(o.text) === want) || [...el.options].find(o => fold(o.text).includes(want));
    if (!o) return false; el.value = o.value;
    el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true})); return true;
  }
  return false;
}
''';
}
