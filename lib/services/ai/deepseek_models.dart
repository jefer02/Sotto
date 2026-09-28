import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/settings.dart';
import '../../data/repositories.dart';
import 'llm_client.dart';

/// Model ids this key may use, from DeepSeek's `GET /models`. Fetched at
/// startup and re-fetched (by invalidating) whenever the key changes.
final deepSeekModelsProvider = FutureProvider<List<String>>((ref) async {
  final key = await resolveDeepSeekKey(ref.watch(secretStoreProvider));
  if (key == null) return const [];
  final client = DeepSeekClient(apiKey: key, model: defaultAiModel);
  try {
    return await client.listModels();
  } finally {
    client.close();
  }
});
