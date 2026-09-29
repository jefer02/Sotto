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
  });

  /// Opaque, stable while the page stays: the UIA runtime id, an AX handle.
  final String id;

  /// edit, document, radio, checkbox, combo, list, listitem, button, group,
  /// menuitem — normalized by the native side.
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
    );
  }
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

  List<String> get selected => [
    for (final o in options)
      if (o.selected) o.label,
  ];

  /// Nothing entered or chosen yet.
  bool get empty => switch (role) {
    FieldRole.text || FieldRole.combo => value.trim().isEmpty,
    FieldRole.radio || FieldRole.checkboxes => selected.isEmpty,
    FieldRole.checkbox => !(options.firstOrNull?.selected ?? false),
  };
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
  const FormSnapshot({required this.fields, this.next, this.submit, this.elements = const {}});

  /// In reading order (top to bottom, then left to right).
  final List<FormField> fields;
  final FormButton? next;
  final FormButton? submit;
  final Map<String, UiElement> elements;

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
  /// parent, combo boxes with their options, text inputs on their own.
  /// List items inside a combo box are its options, not fields.
  static FormSnapshot fromElements(List<UiElement> raw) {
    final byId = {for (final e in raw) e.id: e};
    final usable = raw.where((e) => e.enabled && !e.bounds.isEmpty).toList();

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

    String groupLabel(String? parentId, List<UiElement> members) {
      final parent = parentId == null ? null : byId[parentId];
      if (parent != null && parent.name.isNotEmpty) return parent.name;
      // No labelled group: the options themselves describe it.
      return members.map((m) => m.name).join(' / ');
    }

    bool sensitive(UiElement e, String label) =>
        e.password || SafetyGate.isSecretLabel(label) || SafetyGate.isPaymentLabel(label);

    final fields = <FormField>[];

    // Radio buttons: one field per parent.
    final radios = <String, List<UiElement>>{};
    for (final e in usable.where((e) => e.type == 'radio')) {
      radios.putIfAbsent(e.parent ?? 'radio:${e.id}', () => []).add(e);
    }
    for (final MapEntry(key: parent, value: members) in radios.entries) {
      final label = groupLabel(parent.startsWith('radio:') ? null : parent, members);
      fields.add(
        FormField(
          key: 'group:$parent',
          role: FieldRole.radio,
          label: label,
          bounds: members.map((m) => m.bounds).reduce((a, b) => a.expandToInclude(b)),
          options: [
            for (final m in members)
              FormOption(m.name, elementId: m.id, selected: m.checked ?? false, bounds: m.bounds),
          ],
          sensitive: sensitive(members.first, label),
          patterns: members.first.patterns,
        ),
      );
    }

    // Checkboxes: a labelled parent with two or more is one question.
    final boxes = <String, List<UiElement>>{};
    for (final e in usable.where((e) => e.type == 'checkbox')) {
      boxes.putIfAbsent(e.parent ?? 'box:${e.id}', () => []).add(e);
    }
    for (final MapEntry(key: parent, value: members) in boxes.entries) {
      if (members.length >= 2 && !parent.startsWith('box:')) {
        final label = groupLabel(parent, members);
        fields.add(
          FormField(
            key: 'group:$parent',
            role: FieldRole.checkboxes,
            label: label,
            bounds: members.map((m) => m.bounds).reduce((a, b) => a.expandToInclude(b)),
            options: [
              for (final m in members)
                FormOption(m.name, elementId: m.id, selected: m.checked ?? false, bounds: m.bounds),
            ],
            sensitive: sensitive(members.first, label),
            patterns: members.first.patterns,
          ),
        );
      } else {
        for (final m in members) {
          fields.add(
            FormField(
              key: m.id,
              role: FieldRole.checkbox,
              label: m.name,
              bounds: m.bounds,
              elementId: m.id,
              options: [FormOption(m.name, elementId: m.id, selected: m.checked ?? false, bounds: m.bounds)],
              sensitive: sensitive(m, m.name),
              patterns: m.patterns,
            ),
          );
        }
      }
    }

    for (final e in usable) {
      switch (e.type) {
        case 'edit' || 'document' when !e.readOnly && (e.type == 'edit' || e.has('value')):
          if (inside(e, 'combo')) continue; // an editable combo's own text box
          fields.add(
            FormField(
              key: e.id,
              role: FieldRole.text,
              label: e.name,
              bounds: e.bounds,
              elementId: e.id,
              value: e.value ?? '',
              sensitive: sensitive(e, e.name),
              patterns: e.patterns,
            ),
          );
        case 'combo':
          fields.add(
            FormField(
              key: e.id,
              role: FieldRole.combo,
              label: e.name,
              bounds: e.bounds,
              elementId: e.id,
              options: [
                for (final o in e.options)
                  if (o.isNotEmpty) FormOption(o, selected: o == (e.value ?? '').trim()),
              ],
              value: e.value ?? '',
              sensitive: sensitive(e, e.name),
              patterns: e.patterns,
            ),
          );
        case 'list' when e.has('select') && !inside(e, 'combo'):
          final items = usable.where((i) => i.type == 'listitem' && i.parent == e.id).toList();
          if (items.isEmpty) continue;
          fields.add(
            FormField(
              key: e.id,
              role: FieldRole.radio,
              label: e.name,
              bounds: e.bounds,
              elementId: e.id,
              options: [
                for (final i in items)
                  FormOption(i.name, elementId: i.id, selected: i.checked ?? false, bounds: i.bounds),
              ],
              sensitive: sensitive(e, e.name),
              patterns: items.first.patterns,
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

    return FormSnapshot(fields: fields, next: pick(isNextLabel), submit: pick(isSubmitLabel), elements: byId);
  }
}
