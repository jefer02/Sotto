import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../l10n/l10n.dart';

enum ModelRole { streaming, transcription }

/// On-device speech models (sherpa-onnx). Fetched once, before the first
/// live session; everything after that works offline.
class SpeechModel {
  const SpeechModel({
    required this.id,
    required this.role,
    required this.sizeMb,
    required this.languages,
  });

  final String id;
  final ModelRole role;
  final int sizeMb;

  String get name {
    final l = L10n.current;
    return switch (id) {
      'sherpa-onnx-streaming-zipformer-en-2023-06-26' => l.modelStreamingEn,
      'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17' => l.modelStreamingEnLight,
      'sherpa-onnx-whisper-base' => l.modelWhisperBase,
      _ => l.modelWhisperTurbo,
    };
  }

  String get description {
    final l = L10n.current;
    return switch (id) {
      'sherpa-onnx-streaming-zipformer-en-2023-06-26' => l.modelStreamingEnDesc,
      'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17' => l.modelStreamingEnLightDesc,
      'sherpa-onnx-whisper-base' => l.modelWhisperBaseDesc,
      _ => l.modelWhisperTurboDesc,
    };
  }

  /// BCP-47 prefixes; `*` means multilingual.
  final List<String> languages;

  String get url => 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$id.tar.bz2';

  bool supports(String language) =>
      languages.contains('*') || languages.any((l) => language.toLowerCase().startsWith(l));
}

abstract final class ModelCatalog {
  static const streamingEn = SpeechModel(
    id: 'sherpa-onnx-streaming-zipformer-en-2023-06-26',
    role: ModelRole.streaming,
    sizeMb: 296,
    languages: ['en'],
  );
  static const streamingEnLight = SpeechModel(
    id: 'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17',
    role: ModelRole.streaming,
    sizeMb: 122,
    languages: ['en'],
  );
  static const whisperBase = SpeechModel(
    id: 'sherpa-onnx-whisper-base',
    role: ModelRole.transcription,
    sizeMb: 198,
    languages: ['*'],
  );
  static const whisperTurbo = SpeechModel(
    id: 'sherpa-onnx-whisper-turbo',
    role: ModelRole.transcription,
    sizeMb: 538,
    languages: ['*'],
  );

  static const all = [streamingEn, streamingEnLight, whisperBase, whisperTurbo];

  static SpeechModel byId(String id) => all.firstWhere((m) => m.id == id);
}

/// Paths to the ONNX files inside an extracted model folder.
class ModelFiles {
  const ModelFiles({required this.dir, required this.tokens, this.encoder, this.decoder, this.joiner});

  final String dir;
  final String tokens;
  final String? encoder;
  final String? decoder;
  final String? joiner;
}

sealed class ModelStatus {
  const ModelStatus();
}

class ModelMissing extends ModelStatus {
  const ModelMissing();
}

class ModelDownloading extends ModelStatus {
  const ModelDownloading(this.progress, {this.extracting = false});
  final double progress;
  final bool extracting;
}

class ModelReady extends ModelStatus {
  const ModelReady(this.files);
  final ModelFiles files;
}

class ModelFailed extends ModelStatus {
  const ModelFailed(this.error);
  final String error;
}

class ModelManager {
  Directory? _root;

  Future<Directory> root() async {
    if (_root != null) return _root!;
    final support = await getApplicationSupportDirectory();
    _root = Directory(p.join(support.path, 'models'));
    await _root!.create(recursive: true);
    return _root!;
  }

  Future<ModelFiles?> locate(SpeechModel model) async {
    final dir = Directory(p.join((await root()).path, model.id));
    if (!await dir.exists()) return null;
    return findFiles(dir.path);
  }

  /// Finds model files by pattern (archives differ in naming), preferring
  /// int8 weights, which are smaller and faster on CPU.
  static Future<ModelFiles?> findFiles(String dirPath) async {
    final files = await Directory(dirPath).list(recursive: true).where((e) => e is File).map((e) => e.path).toList();
    String? pick(String role) {
      final matches = files.where((f) {
        final name = p.basename(f).toLowerCase();
        return name.contains(role) && name.endsWith('.onnx');
      }).toList();
      if (matches.isEmpty) return null;
      return matches.firstWhere((f) => f.contains('int8'), orElse: () => matches.first);
    }

    final tokens = files.where((f) => p.basename(f).endsWith('tokens.txt')).firstOrNull;
    if (tokens == null) return null;
    final enc = pick('encoder');
    final dec = pick('decoder');
    if (enc == null || dec == null) return null;
    return ModelFiles(dir: dirPath, tokens: tokens, encoder: enc, decoder: dec, joiner: pick('joiner'));
  }

  Stream<ModelStatus> download(SpeechModel model) async* {
    final dir = await root();
    final archive = File(p.join(dir.path, '${model.id}.tar.bz2.part'));
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(model.url)));
      if (res.statusCode != 200) {
        yield ModelFailed(L10n.current.modelDownloadFailed(res.statusCode));
        return;
      }
      final total = res.contentLength ?? model.sizeMb * 1024 * 1024;
      final sink = archive.openWrite();
      var received = 0;
      var lastYield = DateTime.now();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (DateTime.now().difference(lastYield).inMilliseconds > 150) {
          lastYield = DateTime.now();
          yield ModelDownloading((received / total).clamp(0, 1).toDouble());
        }
      }
      await sink.close();

      yield const ModelDownloading(1, extracting: true);
      final archivePath = archive.path;
      final out = dir.path;
      await Isolate.run(() async {
        final renamed = archivePath.replaceFirst('.part', '');
        await File(archivePath).rename(renamed);
        await extractFileToDisk(renamed, out);
        await File(renamed).delete();
      });

      final files = await locate(model);
      yield files == null ? ModelFailed(L10n.current.modelIncomplete) : ModelReady(files);
    } on SocketException {
      yield ModelFailed(L10n.current.modelOffline);
    } catch (e) {
      yield ModelFailed('$e');
    } finally {
      client.close();
      if (await archive.exists()) await archive.delete();
    }
  }

  Future<void> remove(SpeechModel model) async {
    final dir = Directory(p.join((await root()).path, model.id));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

final modelManagerProvider = Provider<ModelManager>((ref) => ModelManager());

/// Live status of each catalog model, with download control.
class ModelStatusNotifier extends Notifier<Map<String, ModelStatus>> {
  final _subs = <String, StreamSubscription<ModelStatus>>{};

  @override
  Map<String, ModelStatus> build() {
    ref.onDispose(() {
      for (final s in _subs.values) {
        s.cancel();
      }
    });
    // `refresh` reads `state`, which only exists once build has returned.
    Future.microtask(refresh);
    return {for (final m in ModelCatalog.all) m.id: const ModelMissing()};
  }

  Future<void> refresh() async {
    final mgr = ref.read(modelManagerProvider);
    final next = {...state};
    for (final m in ModelCatalog.all) {
      if (next[m.id] is ModelDownloading) continue;
      final files = await mgr.locate(m);
      next[m.id] = files == null ? const ModelMissing() : ModelReady(files);
    }
    state = next;
  }

  void download(SpeechModel model) {
    if (state[model.id] is ModelDownloading) return;
    state = {...state, model.id: const ModelDownloading(0)};
    _subs[model.id] = ref
        .read(modelManagerProvider)
        .download(model)
        .listen((s) => state = {...state, model.id: s}, onDone: () => _subs.remove(model.id));
  }

  Future<void> remove(SpeechModel model) async {
    await ref.read(modelManagerProvider).remove(model);
    state = {...state, model.id: const ModelMissing()};
  }

  ModelFiles? ready(SpeechModel model) => switch (state[model.id]) {
    ModelReady(:final files) => files,
    _ => null,
  };
}

final modelStatusProvider = NotifierProvider<ModelStatusNotifier, Map<String, ModelStatus>>(ModelStatusNotifier.new);
