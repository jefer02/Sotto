import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/display.dart';
import '../../core/widgets/interactive.dart';
import '../../core/widgets/stage_transitions.dart';
import '../../data/import/material_reader.dart';
import '../../data/import/script_importer.dart';
import '../../data/import/source_material.dart';
import '../../data/models/script.dart';
import '../../data/repositories.dart';
import '../../domain/structuring/check_markers.dart';
import '../../l10n/l10n.dart';
import '../../services/ai/script_generator.dart';
import '../settings/pages/voice_page.dart' show languages;
import 'generate_controller.dart';
import 'library_actions.dart';
import 'organize_jobs.dart';

/// How the presenter chose to start.
sealed class NewScriptChoice {
  const NewScriptChoice();
}

class WriteFromScratch extends NewScriptChoice {
  const WriteFromScratch();
}

/// Import files: [paths], or null to pick them.
class ImportFiles extends NewScriptChoice {
  const ImportFiles([this.paths]);
  final List<String>? paths;
}

class ImportPasted extends NewScriptChoice {
  const ImportPasted(this.text);
  final String text;
}

class Generated extends NewScriptChoice {
  const Generated(this.script, {this.checks = 0});
  final Script script;

  /// Markers left in it for the presenter to check.
  final int checks;
}

class OpenIntegrations extends NewScriptChoice {
  const OpenIntegrations();
}

/// "New script": write from scratch, import text (kept word for word), or
/// generate one with AI from a presentation, PDF or document. [ref] must
/// outlive the dialog (the library's), since the choice runs after it
/// closes.
Future<void> showNewScriptDialog(WidgetRef ref, {BuildContext? context, String? collectionId}) async {
  final at = context ?? rootNavigatorKey.currentContext;
  // ⌘N again while it is open does nothing.
  if (at == null || _dialogOpen) return;
  _dialogOpen = true;
  final NewScriptChoice? choice;
  try {
    choice = await showSottoDialog<NewScriptChoice>(
      context: at,
      builder: (_) => NewScriptDialog(collectionId: collectionId),
    );
  } finally {
    _dialogOpen = false;
  }
  final router = ref.read(routerProvider);
  switch (choice) {
    case WriteFromScratch():
      await createScriptAndOpen(ref, collectionId: collectionId);
    case ImportFiles(:final paths):
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) await importFiles(ref, ctx, paths: paths, collectionId: collectionId);
    case ImportPasted(:final text):
      final script = await importText(ref, ScriptImporter.fromPaste(text), collectionId: collectionId);
      router.go('/script/${script.id}');
    case Generated(:final script, :final checks):
      router.go('/script/${script.id}');
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        final l = L10n.current;
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
          SnackBar(content: Text(checks == 0 ? l.genDraftReady : '${l.genDraftReady} ${l.genChecks(checks)}')),
        );
      }
    case OpenIntegrations():
      router.go('/settings/integrations');
    case null:
      break;
  }
}

bool _dialogOpen = false;

enum _View { choose, import, generate }

class NewScriptDialog extends ConsumerStatefulWidget {
  const NewScriptDialog({super.key, this.collectionId, this.initialView, this.initialFiles = const []});
  final String? collectionId;

  /// For tests: open straight on a path ("import", "generate")…
  @visibleForTesting
  final String? initialView;

  /// …with these files already added as material.
  @visibleForTesting
  final List<String> initialFiles;

  @override
  ConsumerState<NewScriptDialog> createState() => _NewScriptDialogState();
}

class _NewScriptDialogState extends ConsumerState<NewScriptDialog> {
  late _View _view = _View.values.asNameMap()[widget.initialView] ?? _View.choose;
  late final GenerateScriptController _gen = generateControllerFor(ref)..addListener(_changed);
  final _paste = TextEditingController();
  final _minutes = TextEditingController(text: '10');
  final _audience = TextEditingController();
  final _tone = TextEditingController();
  late String _language = ref.read(settingsProvider).language;
  bool _useNotes = true;
  bool _perSlide = true;
  bool _questions = true;
  bool _dragging = false;

  /// Null while checking.
  bool? _hasKey;

  @override
  void initState() {
    super.initState();
    unawaited(_checkKey());
    if (widget.initialFiles.isNotEmpty) unawaited(_gen.addFiles(widget.initialFiles));
    _paste.addListener(_changed);
    _minutes.addListener(_changed);
  }

  Future<void> _checkKey() async {
    final client = await ref.read(organizerLlmProvider)();
    client?.close();
    if (mounted) setState(() => _hasKey = client != null);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gen
      ..removeListener(_changed)
      ..dispose();
    _paste.dispose();
    _minutes.dispose();
    _audience.dispose();
    _tone.dispose();
    super.dispose();
  }

  void _close([NewScriptChoice? choice]) {
    if (_gen.phase == GeneratePhase.generating) _gen.cancel();
    Navigator.of(context).pop(choice);
  }

  int get _minutesValue => (int.tryParse(_minutes.text.trim()) ?? 0).clamp(0, 180);

  GenerationOptions _options() {
    final s = ref.read(settingsProvider);
    final l = context.l10n;
    final language = languages.where((o) => o.value == _language).firstOrNull?.label ?? _language;
    return GenerationOptions(
      minutes: _minutesValue,
      wordsPerMinute: paceFor(s).wpm,
      language: language,
      audience: _audience.text,
      tone: _tone.text,
      useNotes: _useNotes,
      sectionPerSlide: _perSlide,
      prepQuestions: _questions,
      checkMarker: l.genCheckMarker,
    );
  }

  Future<void> _generate() async {
    final script = await _gen.generate(_options(), collectionId: widget.collectionId);
    if (script != null && mounted) {
      Navigator.of(context).pop(Generated(script, checks: CheckMarkers.countIn(script.sections)));
    }
  }

  Future<void> _pickMaterial() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: context.l10n.genMaterial,
      type: FileType.custom,
      allowedExtensions: MaterialReader.extensions,
    );
    final paths = [
      for (final f in picked)
        if (f.path != null) f.path!,
    ];
    if (paths.isNotEmpty) await _gen.addFiles(paths);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final generating = _gen.phase == GeneratePhase.generating;
    final title = switch (_view) {
      _View.choose => l.newScript,
      _View.import => l.pathImportTitle,
      _View.generate => l.pathGenerateTitle,
    };
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: p.raised,
          insetPadding: const EdgeInsets.all(Space.s10),
          shape: RoundedRectangleBorder(
            borderRadius: Radii.rXl,
            side: BorderSide(color: p.control),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 760, maxHeight: MediaQuery.sizeOf(context).height * 0.88),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: TypeScale.title2.copyWith(color: p.inkPrimary)),
                      ),
                      SottoIconButton(icon: SottoIcons.close, tooltip: l.closeEsc, onPressed: _close),
                    ],
                  ),
                  const SizedBox(height: Space.s3),
                  Flexible(
                    child: SingleChildScrollView(
                      child: AnimatedSwitcher(
                        duration: context.motion(Motion.snappy),
                        child: KeyedSubtree(
                          key: ValueKey((_view, _gen.phase)),
                          child: switch (_view) {
                            _View.choose => _choose(context),
                            _View.import => _import(context),
                            _View.generate when _gen.phase == GeneratePhase.form => _generateForm(context),
                            _View.generate => _progress(context),
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_view != _View.choose) ...[
                    const SizedBox(height: Space.s4),
                    Divider(height: 1, color: p.hairline),
                    const SizedBox(height: Space.s4),
                    _footer(context, generating),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────── Choose ───────────────────────────────

  Widget _choose(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.newScriptSubtitle, style: TypeScale.body.copyWith(color: p.inkSecondary)),
        const SizedBox(height: Space.s4),
        _PathCard(
          key: const ValueKey('path-write'),
          icon: SottoIcons.plus,
          title: l.pathWriteTitle,
          body: l.pathWriteBody,
          keepsWords: true,
          onTap: () => _close(const WriteFromScratch()),
        ),
        const SizedBox(height: Space.s2),
        _PathCard(
          key: const ValueKey('path-import'),
          icon: SottoIcons.import,
          title: l.pathImportTitle,
          body: l.pathImportBody,
          keepsWords: true,
          onTap: () => setState(() => _view = _View.import),
        ),
        const SizedBox(height: Space.s2),
        _PathCard(
          key: const ValueKey('path-generate'),
          icon: SottoIcons.slide,
          title: l.pathGenerateTitle,
          body: l.pathGenerateBody,
          keepsWords: false,
          onTap: () => setState(() => _view = _View.generate),
        ),
        const SizedBox(height: Space.s4),
        Text(l.newScriptWordsNote, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
      ],
    );
  }

  // ─────────────────────────────── Import ───────────────────────────────

  Widget _import(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WordsBadge(keepsWords: true, detail: l.pathImportBody),
        const SizedBox(height: Space.s4),
        _DropZone(
          dragging: _dragging,
          onDragging: (v) => setState(() => _dragging = v),
          onDropped: (paths) => _close(ImportFiles(paths)),
          hint: l.importDropHint,
          action: SottoButton(
            label: l.importChooseFile,
            icon: SottoIcons.import,
            size: ButtonSize.small,
            onPressed: () => _close(const ImportFiles()),
          ),
        ),
        const SizedBox(height: Space.s5),
        Text(l.importPasteLabel, style: TypeScale.bodyStrong.copyWith(color: p.inkSecondary)),
        const SizedBox(height: Space.s2),
        SottoTextField(
          key: const ValueKey('import-paste'),
          controller: _paste,
          placeholder: l.importPastePlaceholder,
          minLines: 5,
          maxLines: 9,
        ),
      ],
    );
  }

  // ─────────────────────────────── Generate ───────────────────────────────

  Widget _generateForm(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final pace = paceFor(s);
    final words = _minutesValue * pace.wpm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WordsBadge(keepsWords: false, detail: l.pathGenerateBody),
        const SizedBox(height: Space.s5),
        SectionHeading(l.genMaterial),
        const SizedBox(height: Space.s2),
        _DropZone(
          dragging: _dragging,
          onDragging: (v) => setState(() => _dragging = v),
          onDropped: (paths) => unawaited(_gen.addFiles(paths)),
          hint: l.genMaterialHint,
          action: SottoButton(
            label: l.genChooseFiles,
            icon: SottoIcons.import,
            size: ButtonSize.small,
            onPressed: () => unawaited(_pickMaterial()),
          ),
        ),
        for (final m in _gen.materials) ...[
          const SizedBox(height: Space.s2),
          _MaterialRow(entry: m, onRemove: () => _gen.remove(m.id)),
        ],
        const SizedBox(height: Space.s5),
        SettingsGroup(
          children: [
            SettingRow(
              title: l.genDuration,
              subtitle: pace.measured ? l.genBudget(words, pace.wpm) : l.genBudgetDefault(words, pace.wpm),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SottoTextField(key: const ValueKey('gen-minutes'), controller: _minutes, width: 64, mono: true),
                  const SizedBox(width: Space.s2),
                  Text(l.genMinutes, style: TypeScale.body.copyWith(color: p.inkSecondary)),
                ],
              ),
            ),
            SettingRow(
              title: l.genAudience,
              below: _FreeTextWithChips(
                controller: _audience,
                placeholder: l.genAudiencePlaceholder,
                chips: [l.genChipExecutives, l.genChipTeam, l.genChipCustomers, l.genChipStudents, l.genChipGeneral],
              ),
            ),
            SettingRow(
              title: l.genTone,
              below: _FreeTextWithChips(
                controller: _tone,
                placeholder: l.genTonePlaceholder,
                chips: [
                  l.genChipConfident,
                  l.genChipConversational,
                  l.genChipFormal,
                  l.genChipInspiring,
                  l.genChipConcise,
                ],
              ),
            ),
            SettingRow(
              title: l.genLanguage,
              trailing: SottoSelect<String>(
                width: 230,
                value: _language,
                options: [
                  for (final o in languages)
                    SelectOption(o.value, o.value == s.language ? l.genLanguageSpeech(o.label) : o.label),
                ],
                onChanged: (v) => setState(() => _language = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s4),
        SettingsGroup(
          children: [
            SettingRow(
              title: l.genUseNotes,
              subtitle: l.genUseNotesSub,
              trailing: SottoToggle(value: _useNotes, onChanged: (v) => setState(() => _useNotes = v)),
            ),
            SettingRow(
              title: l.genSectionPerSlide,
              subtitle: l.genSectionPerSlideSub,
              trailing: SottoToggle(value: _perSlide, onChanged: (v) => setState(() => _perSlide = v)),
            ),
            SettingRow(
              title: l.genQuestions,
              subtitle: l.genQuestionsSub,
              trailing: SottoToggle(value: _questions, onChanged: (v) => setState(() => _questions = v)),
            ),
          ],
        ),
        const SizedBox(height: Space.s4),
        if (_hasKey == false) _NeedsKey(onOpen: () => _close(const OpenIntegrations())) else const _PrivacyNotice(),
      ],
    );
  }

  Widget _progress(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final failed = _gen.phase == GeneratePhase.failed;
    final stage = _gen.progress?.stage;
    final steps = [
      (
        GenerationStage.understanding,
        _gen.progress?.stage == GenerationStage.understanding
            ? l.genStageUnderstanding(_gen.progress!.done, _gen.progress!.total)
            : l.genStageUnderstandingDone,
      ),
      (GenerationStage.writing, l.genStageWriting),
      (GenerationStage.checking, l.genStageChecking),
      if (_questions) (GenerationStage.questions, l.genStageQuestions),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StageRow(label: l.genStageReading, state: _StepState.done),
        for (final (st, label) in steps)
          _StageRow(
            label: label,
            state: stage == null
                ? (st == GenerationStage.understanding ? _StepState.active : _StepState.waiting)
                : st.index < stage.index
                ? _StepState.done
                : st == stage
                ? (failed ? _StepState.failed : _StepState.active)
                : _StepState.waiting,
          ),
        if (failed) ...[
          const SizedBox(height: Space.s3),
          Text(l.genFailed, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
          const SizedBox(height: Space.s1),
          Text(
            _gen.error ?? '',
            key: const ValueKey('gen-error'),
            style: TypeScale.body.copyWith(color: p.inkSecondary),
          ),
          const SizedBox(height: Space.s1),
          Text(l.genFailedNothingSaved, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
        ],
        const SizedBox(height: Space.s4),
        SectionHeading(l.preview),
        const SizedBox(height: Space.s2),
        Container(
          key: const ValueKey('gen-preview'),
          height: 220,
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: Radii.rL,
            border: Border.all(color: p.hairline),
          ),
          child: _gen.preview.isEmpty
              ? Center(
                  child: Text(
                    l.genPreviewWaiting,
                    textAlign: TextAlign.center,
                    style: TypeScale.body.copyWith(color: p.inkTertiary),
                  ),
                )
              : SingleChildScrollView(
                  reverse: true,
                  child: Text(_gen.preview, style: TypeScale.body.copyWith(color: p.inkSecondary, height: 1.5)),
                ),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context, bool generating) {
    final l = context.l10n;
    void back() => setState(() {
      _view = _View.choose;
      _gen.back();
    });
    return Row(
      children: [
        if (!generating) SottoButton.ghost(label: l.welcomeBack, onPressed: back),
        const Spacer(),
        ...switch (_view) {
          _View.choose => const <Widget>[],
          _View.import => [
            SottoButton.primary(
              key: const ValueKey('import-paste-go'),
              label: l.importPasteAction,
              onPressed: _paste.text.trim().isEmpty ? null : () => _close(ImportPasted(_paste.text)),
            ),
          ],
          _View.generate when generating => [
            SottoButton(key: const ValueKey('gen-cancel'), label: l.genCancel, onPressed: _gen.cancel),
          ],
          _View.generate when _gen.phase == GeneratePhase.failed => [
            SottoButton.primary(label: l.genTryAgain, onPressed: () => unawaited(_generate())),
          ],
          _View.generate => [
            SottoButton.primary(
              key: const ValueKey('gen-go'),
              label: l.genGenerate,
              icon: SottoIcons.slide,
              onPressed: _hasKey == true && _gen.canGenerate && _minutesValue > 0 ? () => unawaited(_generate()) : null,
            ),
          ],
        },
      ],
    );
  }
}

/// One way to start, and whether it keeps the presenter's words.
class _PathCard extends StatelessWidget {
  const _PathCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.keepsWords,
    required this.onTap,
  });

  final SottoIcons icon;
  final String title;
  final String body;
  final bool keepsWords;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Interactive(
      onTap: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: context.motion(Motion.quick),
        padding: const EdgeInsets.all(Space.s4),
        decoration: BoxDecoration(
          color: s.hovered ? p.float : p.panel,
          borderRadius: Radii.rL,
          border: Border.all(color: s.hovered ? p.emphasis : p.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SottoIcon(icon, size: 16, color: s.hovered ? p.cueText : p.inkSecondary),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                  const SizedBox(height: Space.s1),
                  Text(body, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
            _WordsChip(keepsWords: keepsWords),
          ],
        ),
      ),
    );
  }
}

class _WordsChip extends StatelessWidget {
  const _WordsChip({required this.keepsWords});
  final bool keepsWords;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return keepsWords
        ? StatusChip(l.badgeKeepsWords, tone: ChipTone.confirmed, icon: SottoIcons.check)
        : StatusChip(l.badgeWritesNew, tone: ChipTone.cue, icon: SottoIcons.alert);
  }
}

/// The path's promise about wording, at the top of its form.
class _WordsBadge extends StatelessWidget {
  const _WordsBadge({required this.keepsWords, required this.detail});
  final bool keepsWords;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WordsChip(keepsWords: keepsWords),
        const SizedBox(width: Space.s3),
        Expanded(
          child: Text(detail, style: TypeScale.body.copyWith(color: p.inkSecondary)),
        ),
      ],
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.dragging,
    required this.onDragging,
    required this.onDropped,
    required this.hint,
    required this.action,
  });

  final bool dragging;
  final ValueChanged<bool> onDragging;
  final ValueChanged<List<String>> onDropped;
  final String hint;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DropTarget(
      onDragEntered: (_) => onDragging(true),
      onDragExited: (_) => onDragging(false),
      onDragDone: (d) {
        onDragging(false);
        final paths = [for (final f in d.files) f.path];
        if (paths.isNotEmpty) onDropped(paths);
      },
      child: AnimatedContainer(
        duration: context.motion(Motion.quick),
        padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s5),
        decoration: BoxDecoration(
          color: dragging ? p.float : p.panel,
          borderRadius: Radii.rL,
          border: Border.all(color: dragging ? p.cueFill : p.hairline),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.s3,
          runSpacing: Space.s2,
          children: [
            SottoIcon(SottoIcons.import, size: 15, color: p.inkTertiary),
            Text(hint, style: TypeScale.body.copyWith(color: p.inkSecondary)),
            action,
          ],
        ),
      ),
    );
  }
}

/// A material file and what was read from it.
class _MaterialRow extends StatelessWidget {
  const _MaterialRow({required this.entry, required this.onRemove});
  final MaterialEntry entry;
  final VoidCallback onRemove;

  static String summary(SourceMaterial m) {
    final l = L10n.current;
    final units = m.units.length;
    return [
      switch (m.kind) {
        SourceKind.pptx || SourceKind.odp => l.genSlides(units),
        SourceKind.pdf => l.genPages(units),
        SourceKind.image => l.genPicture,
        _ => l.genParts(units),
      },
      if (m.hidden.isNotEmpty) l.genHiddenSkipped(m.hidden.length),
      if (m.isSlides) m.unitsWithNotes == 0 ? l.genNoNotes : l.genNotesFound(m.unitsWithNotes),
      l.genWords(m.wordCount + m.notesWords),
      if (m.ocrUnits > 0 && m.kind == SourceKind.pdf) l.genOcrUsed(m.ocrUnits),
      if (m.kind == SourceKind.image) l.genOcrPicture,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final m = entry.material;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rM,
        border: Border.all(color: entry.error != null ? p.cueFill : p.hairline),
      ),
      child: Row(
        children: [
          SottoIcon(m?.isSlides ?? false ? SottoIcons.slide : SottoIcons.doc, size: 14, color: p.inkTertiary),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.error ?? (m == null ? l.genReading : summary(m)),
                  style: TypeScale.caption.copyWith(color: entry.error != null ? p.cueText : p.inkTertiary),
                ),
              ],
            ),
          ),
          if (entry.reading)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
          else
            SottoIconButton(icon: SottoIcons.close, tooltip: l.genRemove, onPressed: onRemove),
        ],
      ),
    );
  }
}

/// A text field with quick choices under it; a chip fills the field.
class _FreeTextWithChips extends StatelessWidget {
  const _FreeTextWithChips({required this.controller, required this.placeholder, required this.chips});
  final TextEditingController controller;
  final String placeholder;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SottoTextField(controller: controller, placeholder: placeholder),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s1_5,
          runSpacing: Space.s1_5,
          children: [
            for (final c in chips)
              Interactive(
                onTap: () => controller.text = c,
                builder: (context, s) => AnimatedContainer(
                  duration: context.motion(Motion.quick),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: controller.text == c ? p.float : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: controller.text == c || s.hovered ? p.emphasis : p.control),
                  ),
                  child: Text(c, style: TypeScale.caption.copyWith(color: p.inkSecondary)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Shown before generating: what goes to DeepSeek.
class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SurfaceCard(
      key: const ValueKey('gen-privacy'),
      padding: const EdgeInsets.all(Space.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SottoIcon(SottoIcons.shield, size: 14, color: p.inkSecondary),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Text(context.l10n.genPrivacy, style: TypeScale.body.copyWith(color: p.inkSecondary)),
          ),
        ],
      ),
    );
  }
}

class _NeedsKey extends StatelessWidget {
  const _NeedsKey({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    return SurfaceCard(
      key: const ValueKey('gen-needs-key'),
      padding: const EdgeInsets.all(Space.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SottoIcon(SottoIcons.plug, size: 14, color: p.cueText),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.genNeedsKey, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                const SizedBox(height: Space.s1),
                Text(l.genNeedsKeySub, style: TypeScale.body.copyWith(color: p.inkSecondary)),
                const SizedBox(height: Space.s2),
                TextLink('${l.genOpenIntegrations}  ›', onTap: onOpen),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _StepState { waiting, active, done, failed }

class _StageRow extends StatelessWidget {
  const _StageRow({required this.label, required this.state});
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: switch (state) {
              _StepState.done => SottoIcon(SottoIcons.check, size: 14, color: p.confirmed),
              _StepState.active => const Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
              _StepState.failed => SottoIcon(SottoIcons.alert, size: 14, color: p.cueText),
              _StepState.waiting => Center(
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.inkTertiary),
                ),
              ),
            },
          ),
          const SizedBox(width: Space.s3),
          Text(
            label,
            style: TypeScale.body.copyWith(color: state == _StepState.waiting ? p.inkTertiary : p.inkPrimary),
          ),
        ],
      ),
    );
  }
}
