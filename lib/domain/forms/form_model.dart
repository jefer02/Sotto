import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../agent/safety.dart';

/// One accessible control of the foreground window, as the native side
/// reports it (Windows UI Automation, macOS AX). Bounds are physical screen
/// pixels, like `ScreenCapture.screen`.
class UiElement {
  const UiElement({
    required this.id,
    required this.type,
    this.name = '',
    this.value,
    this.bounds = Rect.zero,
    this.password = false,
    this.enabled = true,
    this.offscreen = false,
    this.readOnly = false,
    this.checked,
    this.parent,
    this.options = const [],
    this.patterns = const {},
    this.multiline = false,
    this.sensitive = false,
    this.labeledBy = '',
    this.help = '',
    this.range,
  });

  /// Opaque, stable while the page stays: the UIA runtime id, an AX handle,
  /// or `ext:N` from the browser extension.
  final String id;

  /// edit, document, radio, checkbox, combo, list, listitem, button, group,
  /// menuitem, slider, spinner — normalized by the native side — and text:
  /// plain text on the page, read only to find the question a control
  /// belongs to.
  final String type;
  final String name;
  final String? value;
  final Rect bounds;
  final bool password;
  final bool enabled;
  final bool offscreen;
  final bool readOnly;

  /// Toggle state (checkbox) or selection (radio, list item).
  final bool? checked;

  /// The nearest collected ancestor's [id].
  final String? parent;

  /// A combo box's option labels.
  final List<String> options;

  /// value, toggle, select, expand, invoke, scroll, focus.
  final Set<String> patterns;

  /// A text area (Enter makes a new line rather than submitting).
  final bool multiline;

  /// Flagged by the browser extension as a password, one-time-code or
  /// payment field: it arrives without its value and is never filled.
  final bool sensitive;

  /// The name of the element that labels it (aria-labelledby, <label for>),
  /// when that differs from [name].
  final String labeledBy;

  /// Help text or description (aria-describedby, a hint under the field).
  final String help;

  /// A slider's or spinner's range (RangeValue pattern).
  final RangeSpec? range;

  bool has(String pattern) => patterns.contains(pattern);

  factory UiElement.fromMap(Map<Object?, Object?> m) {
    double n(Object? v) => (v as num?)?.toDouble() ?? 0;
    final b = m['bounds'];
    return UiElement(
      id: '${m['id']}',
      type: '${m['type'] ?? ''}',
      name: (m['name'] as String? ?? '').trim(),
      value: m['value'] as String?,
      bounds: b is List && b.length == 4 ? Rect.fromLTWH(n(b[0]), n(b[1]), n(b[2]), n(b[3])) : Rect.zero,
      password: m['password'] as bool? ?? false,
      enabled: m['enabled'] as bool? ?? true,
      offscreen: m['offscreen'] as bool? ?? false,
      readOnly: m['readOnly'] as bool? ?? false,
      checked: m['checked'] as bool?,
      parent: m['parent'] as String?,
      options: [for (final o in (m['options'] as List? ?? const [])) '$o'.trim()],
      patterns: {for (final p in (m['patterns'] as List? ?? const [])) '$p'},
      multiline: m['multiline'] as bool? ?? m['type'] == 'document',
      sensitive: m['sensitive'] as bool? ?? false,
      labeledBy: (m['labeledBy'] as String? ?? '').trim(),
      help: [
        for (final k in ['help', 'description'])
          if ((m[k] as String? ?? '').trim().isNotEmpty) (m[k]! as String).trim(),
      ].join(' — '),
      range: RangeSpec.fromList(m['range']),
    );
  }
}

/// A slider's or spinner's range and current value.
class RangeSpec {
  const RangeSpec({required this.min, required this.max, required this.value, this.step = 0});

  final double min;
  final double max;
  final double value;

  /// The smallest change; 0 when the control doesn't say.
  final double step;

  static RangeSpec? fromList(Object? v) {
    if (v is! List || v.length < 3 || v.any((x) => x is! num)) return null;
    final n = [for (final x in v) (x as num).toDouble()];
    if (n[1] <= n[0]) return null;
    return RangeSpec(min: n[0], max: n[1], value: n[2], step: n.length > 3 && n[3] > 0 ? n[3] : 0);
  }

  /// [v] within the range, on a step.
  double snap(double v) {
    var x = v.clamp(min, max).toDouble();
    if (step > 0) x = min + ((x - min) / step).round() * step;
    return x.clamp(min, max).toDouble();
  }

  /// The step the keyboard moves it by (arrow keys): [step], else 1.
  double get keyStep => step > 0 ? step : 1;

  static String format(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();
}

enum FieldRole {
  /// One line or more of text.
  text,

  /// Pick one (radio buttons).
  radio,

  /// Pick any (a group of checkboxes).
  checkboxes,

  /// A single yes/no checkbox.
  checkbox,

  /// Pick one from a drop-down (or list box).
  combo,

  /// A number on a slider or a spinner (a 1–10 scale, a number of years).
  range,
}

/// How Sotto can reach a field.
enum FieldAccess {
  /// It has a working accessibility action (UIA pattern / AX action): the
  /// preferred, precise path.
  nativeAx,

  /// No accessible action — often the case for browser content on macOS.
  /// Only its place on screen is known: click it and type.
  visualOnly,
}

class FormOption {
  const FormOption(this.label, {this.elementId, this.selected = false, this.bounds = Rect.zero});

  final String label;

  /// The element to select / toggle for this option (radio, checkbox).
  final String? elementId;
  final bool selected;
  final Rect bounds;
}

/// A question's input, grouped from [UiElement]s.
class FormField {
  const FormField({
    required this.key,
    required this.role,
    required this.label,
    required this.bounds,
    this.elementId,
    this.options = const [],
    this.value = '',
    this.sensitive = false,
    this.patterns = const {},
    this.multiline = false,
    this.offscreen = false,
    this.help = '',
    this.range,
    this.signature = '',
  });

  /// Stable across re-reads of the same page (element or group id).
  final String key;
  final FieldRole role;

  /// The accessible label ("Email", "How often do you…").
  final String label;
  final Rect bounds;

  /// The element to set (text, combo, single checkbox).
  final String? elementId;
  final List<FormOption> options;

  /// Current text, or the selected option labels joined by ", ".
  final String value;

  /// Password, security-code or payment field: never sent, never filled.
  final bool sensitive;
  final Set<String> patterns;
  final bool multiline;

  /// Scrolled out of view (or on another display): the page knows where it
  /// is, the screenshot doesn't show it.
  final bool offscreen;

  /// Help text under the field ("We only use it to send you the results").
  final String help;

  /// [FieldRole.range]: its range.
  final RangeSpec? range;

  /// The question as the page asks it — label, kind and options — numbered
  /// when the same question appears twice. The same on every read of the
  /// page, even when the browser hands out new element ids (scrolling), so
  /// a question is never asked twice.
  final String signature;

  /// Whether an accessibility action can set this field's value.
  FieldAccess get access {
    bool has(String p) => patterns.contains(p);
    final native = switch (role) {
      FieldRole.text => has('value'),
      FieldRole.radio => has('select') || has('invoke'),
      FieldRole.checkboxes || FieldRole.checkbox => has('toggle') || has('invoke'),
      FieldRole.combo => has('expand') || has('value'),
      FieldRole.range => has('range') || has('value') || has('focus'),
    };
    return native ? FieldAccess.nativeAx : FieldAccess.visualOnly;
  }

  /// Every element id this field is made of.
  Iterable<String> get elementIds => [?elementId, for (final o in options) ?o.elementId];

  List<String> get selected => [
    for (final o in options)
      if (o.selected) o.label,
  ];

  /// Nothing entered or chosen yet. A slider always shows some value, so
  /// it counts as empty until it has been answered.
  bool get empty => switch (role) {
    FieldRole.text || FieldRole.combo => value.trim().isEmpty,
    FieldRole.radio || FieldRole.checkboxes => selected.isEmpty,
    FieldRole.checkbox => !(options.firstOrNull?.selected ?? false),
    FieldRole.range => true,
  };

  FormField copyWith({String? label, String? signature}) => FormField(
    key: key,
    role: role,
    label: label ?? this.label,
    bounds: bounds,
    elementId: elementId,
    options: options,
    value: value,
    sensitive: sensitive,
    patterns: patterns,
    multiline: multiline,
    offscreen: offscreen,
    help: help,
    range: range,
    signature: signature ?? this.signature,
  );
}

/// A button the pager cares about.
class FormButton {
  const FormButton(this.elementId, this.label, this.bounds, {this.invokable = true});
  final String elementId;
  final String label;
  final Rect bounds;
  final bool invokable;
}

/// Everything a read of the foreground window found.
class FormSnapshot {
  const FormSnapshot({required this.fields, this.next, this.submit, this.elements = const {}, this.page});

  /// In reading order (top to bottom, then left to right).
  final List<FormField> fields;
  final FormButton? next;
  final FormButton? submit;
  final Map<String, UiElement> elements;

  /// The area that was read — a browser's page, without its toolbar and
  /// tabs — in physical pixels; null when the platform doesn't say.
  final Rect? page;

  FormField? field(String key) => fields.where((f) => f.key == key).firstOrNull;

  static final _next = RegExp(
    r'^\s*(?:next|continue|siguiente|continuar|pr[oó]xim[oa]|seguir|avanzar|next page|p[aá]gina siguiente)\b|^\s*[›»→>]+\s*$',
    caseSensitive: false,
  );
  static final _submit = RegExp(
    r'\b(?:submit|send|finish|done|complete|enviar|env[ií]a|finalizar|terminar|completar|entregar)\b',
    caseSensitive: false,
  );

  static bool isNextLabel(String s) => _next.hasMatch(s);
  static bool isSubmitLabel(String s) => !isNextLabel(s) && _submit.hasMatch(s);

  /// Groups raw elements into fields: radios and checkboxes by their
  /// parent, combo boxes with their options, text inputs, sliders and
  /// spinners on their own. List items inside a combo box are its options,
  /// not fields. A control without a name of its own takes the text that
  /// labels it — its labelling element, else the question written just
  /// above or beside it ([QuestionText]).
  static FormSnapshot fromElements(List<UiElement> raw) {
    final byId = {for (final e in raw) e.id: e};
    final usable = raw.where((e) => e.enabled && !e.bounds.isEmpty && e.type != 'text').toList();
    final texts = QuestionText(raw);

    bool inside(UiElement e, String type) {
      var p = e.parent;
      for (var depth = 0; p != null && depth < 6; depth++) {
        final parent = byId[p];
        if (parent == null) return false;
        if (parent.type == type) return true;
        p = parent.parent;
      }
      return false;
    }

    // The group an option belongs to. Firefox wraps each option in its
    // <label> as a group of its own: that's the option, not its question —
    // the group above it is.
    String? groupOf(UiElement e) {
      var p = e.parent;
      for (var depth = 0; p != null && depth < 3; depth++) {
        final g = byId[p];
        if (g == null || g.type != 'group') return p;
        final wrapsOnlyThis = g.name.isEmpty || g.name == e.name;
        final small = g.bounds.height <= e.bounds.height * 2.5 + 16;
        if (!(wrapsOnlyThis && small)) return p;
        p = g.parent;
      }
      return p;
    }

    String labelOf(UiElement e) {
      if (e.name.isNotEmpty) return e.name;
      if (e.labeledBy.isNotEmpty) return e.labeledBy;
      return texts.near(e.bounds) ?? '';
    }

    Rect union(List<UiElement> members) => members.map((m) => m.bounds).reduce((a, b) => a.expandToInclude(b));

    String groupLabel(String? parentId, List<UiElement> members) {
      final parent = parentId == null ? null : byId[parentId];
      final around = union(members);
      // A labelled group that is about these options (a fieldset, a
      // radiogroup) — not the whole form they sit in.
      if (parent != null && parent.bounds.height <= around.height + 160) {
        final own = parent.name.isNotEmpty ? parent.name : parent.labeledBy;
        if (own.isNotEmpty) return own;
      }
      final written = texts.near(around);
      if (written != null) return written;
      // Nothing labels it: the options themselves describe it.
      return members.map((m) => m.name).join(' / ');
    }

    bool sensitive(UiElement e, String label) =>
        e.password || e.sensitive || SafetyGate.isSecretLabel(label) || SafetyGate.isPaymentLabel(label);
    bool offscreen(List<UiElement> members) => members.every((m) => m.offscreen);

    final fields = <FormField>[];

    // Radio buttons and checkboxes: one field per parent — split where a
    // question's text stands between two of them (two radio sets with no
    // fieldset of their own share the form as parent).
    List<List<UiElement>> runs(Iterable<UiElement> members) {
      final sorted = members.toList()..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
      final out = <List<UiElement>>[];
      for (final m in sorted) {
        final last = out.lastOrNull?.last;
        if (last != null && !texts.between(last.bounds, m.bounds)) {
          out.last.add(m);
        } else {
          out.add([m]);
        }
      }
      return out;
    }

    final radios = <String, List<UiElement>>{};
    for (final e in usable.where((e) => e.type == 'radio')) {
      radios.putIfAbsent(groupOf(e) ?? 'radio:${e.id}', () => []).add(e);
    }
    for (final MapEntry(key: parent, value: all) in radios.entries) {
      final split = runs(all);
      for (var r = 0; r < split.length; r++) {
        final members = split[r];
        final label = groupLabel(parent.startsWith('radio:') ? null : parent, members);
        fields.add(
          FormField(
            key: r == 0 ? 'group:$parent' : 'group:$parent#$r',
            role: FieldRole.radio,
            label: label,
            bounds: union(members),
            options: [
              for (final m in members)
                FormOption(m.name, elementId: m.id, selected: m.checked ?? false, bounds: m.bounds),
            ],
            sensitive: sensitive(members.first, label),
            patterns: members.first.patterns,
            offscreen: offscreen(members),
          ),
        );
      }
    }

    final boxes = <String, List<UiElement>>{};
    for (final e in usable.where((e) => e.type == 'checkbox')) {
      boxes.putIfAbsent(groupOf(e) ?? 'box:${e.id}', () => []).add(e);
    }
    for (final MapEntry(key: parent, value: all) in boxes.entries) {
      for (final (r, members) in runs(all).indexed) {
        // A labelled run of two or more is one "select all that apply".
        if (members.length >= 2 && !parent.startsWith('box:')) {
          final label = groupLabel(parent, members);
          fields.add(
            FormField(
              key: r == 0 ? 'group:$parent' : 'group:$parent#$r',
              role: FieldRole.checkboxes,
              label: label,
              bounds: union(members),
              options: [
                for (final m in members)
                  FormOption(m.name, elementId: m.id, selected: m.checked ?? false, bounds: m.bounds),
              ],
              sensitive: sensitive(members.first, label),
              patterns: members.first.patterns,
              offscreen: offscreen(members),
            ),
          );
        } else {
          for (final m in members) {
            final label = labelOf(m);
            fields.add(
              FormField(
                key: m.id,
                role: FieldRole.checkbox,
                label: label,
                bounds: m.bounds,
                elementId: m.id,
                options: [FormOption(label, elementId: m.id, selected: m.checked ?? false, bounds: m.bounds)],
                sensitive: sensitive(m, label),
                patterns: m.patterns,
                offscreen: m.offscreen,
              ),
            );
          }
        }
      }
    }

    for (final e in usable) {
      switch (e.type) {
        case 'edit' || 'document' when !e.readOnly && (e.type == 'edit' || e.has('value')):
          if (inside(e, 'combo')) continue; // an editable combo's own text box
          final label = labelOf(e);
          fields.add(
            FormField(
              key: e.id,
              role: FieldRole.text,
              label: label,
              bounds: e.bounds,
              elementId: e.id,
              value: e.value ?? '',
              sensitive: sensitive(e, label),
              patterns: e.patterns,
              multiline: e.multiline,
              offscreen: e.offscreen,
              help: e.help,
            ),
          );
        case 'slider' || 'spinner' when !e.readOnly && (e.range != null || e.has('value')):
          final label = labelOf(e);
          fields.add(
            FormField(
              // No range: a number box that only takes text.
              key: e.id,
              role: e.range != null ? FieldRole.range : FieldRole.text,
              label: label,
              bounds: e.bounds,
              elementId: e.id,
              value: e.range != null ? '' : e.value ?? '',
              sensitive: sensitive(e, label),
              patterns: e.patterns,
              offscreen: e.offscreen,
              help: e.help,
              range: e.range,
            ),
          );
        case 'combo':
          final label = labelOf(e);
          // "Choose…", "Select a country ▾": a prompt, not a choice — even
          // when it is the list's first option.
          final placeholder = texts.isPlaceholder(e);
          fields.add(
            FormField(
              key: e.id,
              role: FieldRole.combo,
              label: label,
              bounds: e.bounds,
              elementId: e.id,
              options: [
                for (final o in e.options)
                  if (o.isNotEmpty) FormOption(o, selected: !placeholder && o == (e.value ?? '').trim()),
              ],
              value: placeholder ? '' : e.value ?? '',
              sensitive: sensitive(e, label),
              patterns: e.patterns,
              offscreen: e.offscreen,
              help: e.help,
            ),
          );
        case 'list' when e.has('select') && !inside(e, 'combo'):
          final items = usable.where((i) => i.type == 'listitem' && i.parent == e.id).toList();
          if (items.isEmpty) continue;
          final label = labelOf(e);
          fields.add(
            FormField(
              key: e.id,
              role: FieldRole.radio,
              label: label,
              bounds: e.bounds,
              elementId: e.id,
              options: [
                for (final i in items)
                  FormOption(i.name, elementId: i.id, selected: i.checked ?? false, bounds: i.bounds),
              ],
              sensitive: sensitive(e, label),
              patterns: items.first.patterns,
              offscreen: e.offscreen,
            ),
          );
      }
    }

    fields.sort((a, b) {
      final dy = a.bounds.top - b.bounds.top;
      return dy.abs() > 6 ? dy.sign.toInt() : (a.bounds.left - b.bounds.left).sign.toInt();
    });

    FormButton? pick(bool Function(String) test) {
      final hits = usable.where((e) => e.type == 'button' && test(e.name)).toList()
        // The bottom-most matching button is the form's own, not a header link.
        ..sort((a, b) => b.bounds.top.compareTo(a.bounds.top));
      final e = hits.firstOrNull;
      return e == null ? null : FormButton(e.id, e.name, e.bounds, invokable: e.has('invoke'));
    }

    final page = raw.where((e) => e.type == 'page' && !e.bounds.isEmpty).firstOrNull?.bounds;
    return FormSnapshot(
      fields: signed(fields),
      next: pick(isNextLabel),
      submit: pick(isSubmitLabel),
      elements: byId,
      page: page,
    );
  }

  /// [fields] with their [FormField.signature]s.
  static List<FormField> signed(List<FormField> fields) {
    final seen = <String, int>{};
    return [
      for (final f in fields)
        () {
          final base = [
            f.role.name,
            _fold(f.label),
            for (final o in f.options) _fold(o.label),
            if (f.range != null) '${f.range!.min}-${f.range!.max}',
          ].join('|');
          final n = seen[base] = (seen[base] ?? 0) + 1;
          return f.copyWith(signature: n == 1 ? base : '$base#$n');
        }(),
    ];
  }

  static String _fold(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The page's plain text, as labels: the question written right above a
/// control (or just left of it, on the same line) — what a sighted user
/// reads as its label when the page didn't connect the two.
class QuestionText {
  QuestionText(List<UiElement> raw)
    : _texts = [
        for (final e in raw)
          if (e.type == 'text' && e.name.trim().isNotEmpty && !e.bounds.isEmpty) e,
      ],
      _controls = [
        for (final e in raw)
          if (e.type != 'text' && e.type != 'group' && e.type != 'document' && e.type != 'page' && !e.bounds.isEmpty)
            e.bounds,
      ];

  final List<UiElement> _texts;
  final List<Rect> _controls;

  /// How far above a control its question may sit.
  static const above = 96.0;

  /// How far left of a control its label may sit, on the same line.
  static const beside = 280.0;

  /// Text drawn inside a control (a combo's placeholder, a button's
  /// caption) labels nothing.
  bool _inControl(Rect t) =>
      _controls.any((c) => c.inflate(1).contains(t.topLeft) && c.inflate(1).contains(t.bottomRight));

  /// The text that labels [r], or null.
  String? near(Rect r) {
    UiElement? best;
    var bestDistance = double.infinity;
    for (final t in _texts) {
      final b = t.bounds;
      if (_inControl(b)) continue;
      double? d;
      final overlapsX = b.left < r.right && b.right > r.left;
      if (overlapsX && b.bottom <= r.top + 4 && r.top - b.bottom <= above) {
        d = math.max(0, r.top - b.bottom);
      } else if (b.right <= r.left + 4 &&
          r.left - b.right <= beside &&
          b.center.dy >= r.top &&
          b.center.dy <= r.bottom) {
        d = math.max(0, r.left - b.right) + 1;
      }
      if (d != null && d < bestDistance) {
        bestDistance = d;
        best = t;
      }
    }
    return best?.name.trim();
  }

  /// Whether a question's text stands between [a] (above) and [b] (below).
  bool between(Rect a, Rect b) => _texts.any((t) {
    final r = t.bounds;
    return !_inControl(r) &&
        r.top >= a.bottom - 2 &&
        r.bottom <= b.top + 2 &&
        r.left < math.max(a.right, b.right) + beside;
  });

  /// Whether [combo]'s value is a prompt — "Choose…", "Select a country ▾",
  /// "-- Elige --" — not a choice.
  bool isPlaceholder(UiElement combo) {
    final v = (combo.value ?? '').trim().toLowerCase().replaceFirst(RegExp(r'^[-–—\s]+'), '');
    if (v.isEmpty) return true;
    return RegExp(r'^(select|choose|pick|please select|elige|elija|selecciona|seleccione|escoge|escoja)\b').hasMatch(v);
  }
}
