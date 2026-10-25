import 'package:flutter/material.dart';

import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/platform/external_links.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/stage_transitions.dart';
import '../../../l10n/l10n.dart';
import '../../../services/speech/model_manager.dart';

/// Where a model's license and attribution live, by model. Opened in the
/// browser only — the app downloads every model from GitHub.
const modelSources = {
  'sherpa-onnx-streaming-zipformer-es-kroko-2025-08-06': 'https://huggingface.co/Banafo/Kroko-ASR',
  'sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06': 'https://huggingface.co/Banafo/Kroko-ASR',
  'sherpa-onnx-streaming-zipformer-de-kroko-2025-08-06': 'https://huggingface.co/Banafo/Kroko-ASR',
};

/// Before a model that asks for attribution downloads: its license, who
/// made it and where it comes from. True when the presenter accepts.
Future<bool> confirmModelLicense(BuildContext context, SpeechModel model) async {
  if (model.attribution == null) return true;
  final ok = await showSottoDialog<bool>(
    context: context,
    builder: (_) => ModelLicenseDialog(model: model),
  );
  return ok ?? false;
}

class ModelLicenseDialog extends StatelessWidget {
  const ModelLicenseDialog({super.key, required this.model});
  final SpeechModel model;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final source = modelSources[model.id];
    return AlertDialog(
      backgroundColor: p.float,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.rL,
        side: BorderSide(color: p.control),
      ),
      title: Text(l.modelLicenseTitle(model.name), style: TypeScale.title2.copyWith(color: p.inkPrimary)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.modelLicenseBody, style: TypeScale.body.copyWith(color: p.inkSecondary)),
            const SizedBox(height: Space.s3),
            Text(l.modelLicenseAttribution, style: TypeScale.captionStrong.copyWith(color: p.inkTertiary)),
            const SizedBox(height: Space.s1),
            SelectableText(model.attribution!, style: TypeScale.body.copyWith(color: p.inkPrimary)),
            if (source != null) ...[
              const SizedBox(height: Space.s3),
              TextLink(l.modelLicenseSource(source), onTap: () => openExternal(source)),
            ],
          ],
        ),
      ),
      actions: [
        SottoButton.ghost(label: l.cancel, onPressed: () => Navigator.pop(context, false)),
        SottoButton.primary(label: l.modelLicenseAccept, onPressed: () => Navigator.pop(context, true)),
      ],
    );
  }
}
