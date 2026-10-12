import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../agent/agent_controller.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/utils/ids.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/controls.dart';
import '../../data/import/script_importer.dart';
import '../../data/models/script.dart';
import '../../data/repositories.dart';
import '../../services/ai/llm_client.dart';
import 'editor_controller.dart';

/// Likely questions with pre-drafted answers (shown instantly when matched
/// live) and prep documents the answer drafter may ground in.
class PrepTab extends ConsumerStatefulWidget {
  const PrepTab({super.key, required this.scriptId});
  final String scriptId;

  @override
  ConsumerState<PrepTab> createState() => _PrepTabState();
}

class _PrepTabState extends ConsumerState<PrepTab> {
  bool _suggesting = false;
  String? _error;

  EditorController get _c => ref.read(editorProvider(widget.scriptId).notifier);

  Future<void> _importDoc() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: context.l10n.addPrepDocument,
      type: FileType.custom,
      allowedExtensions: ScriptImporter.supportedExtensions,
    );
    for (final f in picked) {
      final path = f.path;
      if (path == null) continue;
      try {
        final r = await ScriptImporter.fromFile(path);
        _c.update(
          (s) => s.copyWith(
            prepDocs: [
              ...s.prepDocs,
              PrepDoc(id: newId(), name: r.sourceName, text: r.text),
            ],
          ),
        );
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    }
  }

  Future<void> _pasteDoc() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text == null || text.isEmpty) return;
    _c.update(
      (s) => s.copyWith(
        prepDocs: [
          ...s.prepDocs,
          PrepDoc(id: newId(), name: L10n.current.pastedNotes(s.prepDocs.length + 1), text: text),
        ],
      ),
    );
  }

  /// Asks the model for the questions this audience is most likely to ask,
  /// answered from the script.
  Future<void> _suggest(Script script) async {
    final s = ref.read(settingsProvider);
    final client = await LlmClient.forSettings(s, ref.read(secretStoreProvider));
    if (!mounted) return;
    if (client == null) {
      setState(() => _error = context.l10n.suggestNeedsKey);
      return;
    }
    setState(() {
      _suggesting = true;
      _error = null;
    });
    try {
      final text = [
        for (final sec in script.sections) ...['## ${sec.title}', for (final b in sec.beats) b.plainText],
        for (final d in script.prepDocs) '## Prep: ${d.name}\n${d.text}',
      ].join('\n');
      final out = await client.complete(
        system:
            'You prepare a presenter for audience Q&A. From their talk, write the 5 questions the audience is '
            'most likely to ask, each with a short spoken answer grounded only in the material (2–3 sentences). '
            'Output plain lines only, alternating:\nQ: <question>\nA: <answer>',
        user: text,
        maxTokens: 4096,
      );
      final pairs = <PrepQuestion>[];
      String? q;
      for (final line in out.split('\n').map((l) => l.trim())) {
        if (line.startsWith('Q:')) {
          q = line.substring(2).trim();
        } else if (line.startsWith('A:') && q != null) {
          pairs.add(PrepQuestion(id: newId(), question: q, answer: line.substring(2).trim()));
          q = null;
        }
      }
      if (pairs.isEmpty) throw LlmException(L10n.current.noQuestionsReturned);
      _c.update((s) => s.copyWith(prepQuestions: [...s.prepQuestions, ...pairs]));
    } catch (e) {
      if (mounted) setState(() => _error = e is LlmException ? e.message : '$e');
    } finally {
      client.close();
      if (mounted) setState(() => _suggesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final script = ref.watch(editorProvider(widget.scriptId)).script!;

    final questions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(context.l10n.likelyQuestions, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
            ),
            if (_suggesting)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))
            else
              SottoButton.ghost(
                label: context.l10n.suggestWithAi,
                icon: SottoIcons.ask,
                onPressed: () => unawaited(_suggest(script)),
              ),
            const SizedBox(width: 6),
            SottoButton(
              label: context.l10n.addQuestion,
              icon: SottoIcons.plus,
              onPressed: () => _c.update(
                (s) => s.copyWith(
                  prepQuestions: [
                    ...s.prepQuestions,
                    PrepQuestion(id: newId(), question: '', answer: ''),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(context.l10n.likelyQuestionsNote, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
        const SizedBox(height: 16),
        if (script.prepQuestions.isEmpty)
          _Empty(icon: SottoIcons.ask, text: context.l10n.noPreparedQuestions)
        else
          for (final q in script.prepQuestions)
            _QuestionCard(
              key: ValueKey(q.id),
              question: q,
              onChanged: (next) => _c.update(
                (s) => s.copyWith(prepQuestions: [for (final x in s.prepQuestions) x.id == q.id ? next : x]),
              ),
              onDelete: () =>
                  _c.update((s) => s.copyWith(prepQuestions: s.prepQuestions.where((x) => x.id != q.id).toList())),
            ),
      ],
    );

    final agent = ref.watch(settingsProvider.select((s) => s.agentEnabled)) ? _AgentCard(script: script) : null;

    final docs = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(context.l10n.prepDocuments, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
            ),
            SottoButton.ghost(label: context.l10n.paste, onPressed: () => unawaited(_pasteDoc())),
            const SizedBox(width: 6),
            SottoButton(label: context.l10n.addFile, icon: SottoIcons.import, onPressed: () => unawaited(_importDoc())),
          ],
        ),
        const SizedBox(height: 6),
        Text(context.l10n.prepDocumentsNote, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
        const SizedBox(height: 16),
        if (script.prepDocs.isEmpty)
          _Empty(icon: SottoIcons.doc, text: context.l10n.noPrepDocuments)
        else
          for (final d in script.prepDocs)
            _DocCard(
              key: ValueKey(d.id),
              doc: d,
              onDelete: () => _c.update((s) => s.copyWith(prepDocs: s.prepDocs.where((x) => x.id != d.id).toList())),
            ),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 1000;
        return ListView(
          padding: const EdgeInsets.fromLTRB(40, 32, 40, 48),
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.cueFill.withValues(alpha: 0.1), borderRadius: Radii.rM),
                child: Row(
                  children: [
                    SottoIcon(SottoIcons.alert, size: 14, color: p.cueText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!, style: TypeScale.body.copyWith(color: p.inkPrimary)),
                    ),
                    SottoIconButton(
                      icon: SottoIcons.close,
                      tooltip: context.l10n.dismiss,
                      onPressed: () => setState(() => _error = null),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (agent != null) ...[agent, const SizedBox(height: 28)],
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: questions),
                  const SizedBox(width: 40),
                  Expanded(child: docs),
                ],
              )
            else ...[
              questions,
              const SizedBox(height: 36),
              docs,
            ],
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final SottoIcons icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: Radii.rL,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SottoIcon(icon, size: 16, color: p.inkTertiary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TypeScale.body.copyWith(color: p.inkTertiary)),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({super.key, required this.question, required this.onChanged, required this.onDelete});
  final PrepQuestion question;
  final ValueChanged<PrepQuestion> onChanged;
  final VoidCallback onDelete;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  late final _q = TextEditingController(text: widget.question.question);
  late final _a = TextEditingController(text: widget.question.answer);

  @override
  void dispose() {
    _q.dispose();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rL,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 10),
                child: SottoIcon(SottoIcons.ask, size: 14, color: p.inkTertiary),
              ),
              Expanded(
                child: TextField(
                  controller: _q,
                  maxLines: null,
                  style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: context.l10n.questionHint,
                    hintStyle: TypeScale.bodyStrong.copyWith(color: p.inkDisabled),
                  ),
                  onChanged: (t) => widget.onChanged(widget.question.copyWith(question: t)),
                ),
              ),
              SottoIconButton(
                icon: SottoIcons.close,
                tooltip: context.l10n.deleteQuestion,
                size: 24,
                iconSize: 12,
                onPressed: widget.onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 8),
            child: TextField(
              controller: _a,
              maxLines: null,
              style: ReadingType.editor.copyWith(fontSize: 15, height: 1.55, color: p.inkSecondary),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: context.l10n.answerHint,
                hintStyle: TypeScale.body.copyWith(color: p.inkDisabled),
              ),
              onChanged: (t) => widget.onChanged(widget.question.copyWith(answer: t)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocCard extends StatefulWidget {
  const _DocCard({super.key, required this.doc, required this.onDelete});
  final PrepDoc doc;
  final VoidCallback onDelete;

  @override
  State<_DocCard> createState() => _DocCardState();
}

class _DocCardState extends State<_DocCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final words = widget.doc.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rL,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: Radii.rL,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  SottoIcon(SottoIcons.doc, size: 14, color: p.inkTertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.doc.name,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
                    ),
                  ),
                  Text(context.l10n.wordsCount(words), style: TypeScale.monoSmall.copyWith(color: p.inkTertiary)),
                  const SizedBox(width: 6),
                  SottoIconButton(
                    icon: SottoIcons.close,
                    tooltip: context.l10n.removeDocument,
                    size: 24,
                    iconSize: 12,
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 16, 14),
              child: Text(
                widget.doc.text.length > 2400 ? '${widget.doc.text.substring(0, 2400)}…' : widget.doc.text,
                style: TypeScale.caption.copyWith(color: p.inkSecondary, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Let the agent do it": a task in words, run on screen with confirmation.
class _AgentCard extends ConsumerStatefulWidget {
  const _AgentCard({required this.script});
  final Script script;

  @override
  ConsumerState<_AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends ConsumerState<_AgentCard> {
  final _task = TextEditingController();

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  void _run() {
    final task = _task.text.trim();
    if (task.isEmpty) return;
    unawaited(ref.read(agentControllerProvider.notifier).start(task, script: widget.script));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final running = ref.watch(agentControllerProvider.select((a) => a.inControl));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rL,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SottoIcon(SottoIcons.cursor, size: 14, color: p.cueText),
              const SizedBox(width: 8),
              Text(l.agentCardTitle, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(l.agentCardBody, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SottoTextField(
                  controller: _task,
                  placeholder: l.agentTaskPlaceholder,
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 8),
              SottoButton.primary(label: l.agentRunTask, icon: SottoIcons.play, onPressed: running ? null : _run),
            ],
          ),
        ],
      ),
    );
  }
}
