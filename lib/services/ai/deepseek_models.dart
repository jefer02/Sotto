import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/settings.dart';
import '../../data/repositories.dart';
import 'llm_client.dart';

/// Model ids this key may use, from DeepSeek's `GET /models`. Fetched at
/// startup and re-fetched (by invalidating) whenever the key changes.
final deepSeekModelsProvider = FutureProvider<List<DeepSeekModel>>((ref) async {
  final cred = await resolveDeepSeekCredential(ref.watch(secretStoreProvider));
  if (cred == null) return const [];
  final client = DeepSeekClient(apiKey: cred.key, model: defaultAiModel, builtInKey: cred.source == KeySource.builtIn);
  try {
    return await client.listModels();
  } finally {
    client.close();
  }
});

/// Whether [model] reads images, per `GET /models`. With no list yet
/// (offline, no key checked) it's assumed to — an image it then refuses
/// switches that fill to text.
bool visionReadsImages(List<DeepSeekModel> models, String model) =>
    models.isEmpty || models.any((m) => m.id == model && m.images);

/// The model to send screenshots to: [selected] if it reads images, else
/// Flash, else the first model that does. Null when none can.
String? pickVisionModel(List<DeepSeekModel> models, String selected) {
  final vision = models.where((m) => m.images).map((m) => m.id).toList();
  if (vision.contains(selected)) return selected;
  if (vision.contains(defaultAiModel)) return defaultAiModel;
  return vision.isEmpty ? null : vision.first;
}
