import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/settings.dart';
import '../../data/repositories.dart';
import 'llm_client.dart';

/// Model ids this key may use, from DeepSeek's `GET /models`. Fetched at
/// startup and re-fetched (by invalidating) whenever the key changes.
final deepSeekModelsProvider = FutureProvider<List<DeepSeekModel>>((ref) async {
  final key = await resolveDeepSeekKey(ref.watch(secretStoreProvider));
  if (key == null) return const [];
  final client = DeepSeekClient(apiKey: key, model: defaultAiModel);
  try {
    return await client.listModels();
  } finally {
    client.close();
  }
});

/// The model to send screenshots to: [selected] if it reads images, else
/// Flash, else the first model that does. Null when none can.
String? pickVisionModel(List<DeepSeekModel> models, String selected) {
  final vision = models.where((m) => m.images).map((m) => m.id).toList();
  if (vision.contains(selected)) return selected;
  if (vision.contains(defaultAiModel)) return defaultAiModel;
  return vision.isEmpty ? null : vision.first;
}
