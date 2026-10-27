import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
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
    required this.bytes,
    required this.sha256,
    required this.languages,
    this.attribution,
    this.chunkSeconds = 0.32,
  });

  final String id;
  final ModelRole role;

  /// The archive's exact size and SHA-256 (hex) as published on the
  /// sherpa-onnx `asr-models` release. A download that doesn't match both is
  /// discarded before anything is extracted.
  final int bytes;
  final String sha256;

  /// The model's own license notice, for models that need one shown
  /// (CC BY-SA asks for attribution). Null: the Apache-2.0 sherpa models.
  final String? attribution;

  int get sizeMb => (bytes / (1024 * 1024)).round();

  /// A streaming model decodes audio in chunks this long (its encoder's
  /// fixed input, `decode_chunk_len` in the ONNX metadata): how often one
  /// decoder can emit words.
  final double chunkSeconds;

  String get name {
    final l = L10n.current;
    return switch (id) {
      'sherpa-onnx-streaming-zipformer-en-2023-06-26' => l.modelStreamingEn,
      'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17' => l.modelStreamingEnLight,
      'sherpa-onnx-streaming-zipformer-es-kroko-2025-08-06' => l.modelStreamingEs,
      'sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06' => l.modelStreamingFr,
      'sherpa-onnx-streaming-zipformer-de-kroko-2025-08-06' => l.modelStreamingDe,
      'sherpa-onnx-whisper-base' => l.modelWhisperBase,
      _ => l.modelWhisperTurbo,
    };
  }

  String get description {
    final l = L10n.current;
    return switch (id) {
      'sherpa-onnx-streaming-zipformer-en-2023-06-26' => l.modelStreamingEnDesc,
      'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17' => l.modelStreamingEnLightDesc,
      'sherpa-onnx-streaming-zipformer-es-kroko-2025-08-06' ||
      'sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06' ||
      'sherpa-onnx-streaming-zipformer-de-kroko-2025-08-06' => l.modelStreamingKrokoDesc,
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
    bytes: 310414022,
    sha256: '639e25b578e9e997131402199419c13a941f8e4e198e2da1ce57dbf5cf401282',
    languages: ['en'],
  );
  static const streamingEnLight = SpeechModel(
    id: 'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17',
    role: ModelRole.streaming,
    bytes: 127887156,
    sha256: '9c559283e8498d3fe95913c79ca1cb454bb26281ac2b102b41306c7d752765d9',
    languages: ['en'],
  );

  /// Banafo's Kroko community models, converted by sherpa-onnx. They decode
  /// in ~1.3 s chunks: words come 0.5–1.3 s after they're said, a few at a
  /// time, against Whisper's whole phrases after each pause. Measured on the
  /// same 15-beat talk (TTS, see docs/ARCHITECTURE.md): 0–2 % word errors.
  static const _kroko = 'Kroko ASR community model by Banafo (huggingface.co/Banafo/Kroko-ASR), CC BY-SA.';
  static const streamingEs = SpeechModel(
    id: 'sherpa-onnx-streaming-zipformer-es-kroko-2025-08-06',
    role: ModelRole.streaming,
    chunkSeconds: 1.28,
    bytes: 124394665,
    sha256: '31b2230a95d23290b308b393da930015a4b2105cb3abb9367aed35f7fcf29cf1',
    languages: ['es'],
    attribution: _kroko,
  );
  static const streamingFr = SpeechModel(
    id: 'sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06',
    role: ModelRole.streaming,
    chunkSeconds: 1.28,
    bytes: 57220361,
    sha256: 'e6ffd3dc43725cd6c8137b05c739f15607d0df946b9b90eb141e10059efca024',
    languages: ['fr'],
    attribution: _kroko,
  );
  static const streamingDe = SpeechModel(
    id: 'sherpa-onnx-streaming-zipformer-de-kroko-2025-08-06',
    role: ModelRole.streaming,
    chunkSeconds: 1.28,
    bytes: 57565698,
    sha256: '9e27b783c20e67b0d0f13a258c1861fce199917c969d9176a438bee38df64962',
    languages: ['de'],
    attribution: _kroko,
  );
  static const whisperBase = SpeechModel(
    id: 'sherpa-onnx-whisper-base',
    role: ModelRole.transcription,
    bytes: 207557382,
    sha256: '911b2083efd7c0dca2ac3b358b75222660dc09fb716d64fbfc417ba6c99ff3de',
    languages: ['*'],
  );
  static const whisperTurbo = SpeechModel(
    id: 'sherpa-onnx-whisper-turbo',
    role: ModelRole.transcription,
    bytes: 563790207,
    sha256: 'b11acbbcd660b44a8e0df33724feb5aaa709cf65668f2823d59f656312544f22',
    languages: ['*'],
  );

  static const all = [streamingEn, streamingEnLight, streamingEs, streamingFr, streamingDe, whisperBase, whisperTurbo];

  static SpeechModel byId(String id) => all.firstWhere((m) => m.id == id);

  /// Streaming models that can follow [language], best first. Empty: the
  /// language has none, and following falls back to segmented Whisper.
  static List<SpeechModel> streamingFor(String language) => [
    for (final m in all)
      if (m.role == ModelRole.streaming && m.supports(language)) m,
  ];
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

  /// Whether the archive [received] bytes long with SHA-256 [digest] is the
  /// one [model] pins.
  static bool verified(SpeechModel model, int received, Digest digest) =>
      received == model.bytes && digest.toString() == model.sha256;

  Stream<ModelStatus> download(SpeechModel model, {http.Client? client}) async* {
    final dir = await root();
    final archive = File(p.join(dir.path, '${model.id}.tar.bz2.part'));
    final http_ = client ?? http.Client();
    try {
      final res = await http_.send(http.Request('GET', Uri.parse(model.url)));
      if (res.statusCode != 200) {
        yield ModelFailed(L10n.current.modelDownloadFailed(res.statusCode));
        return;
      }
      final total = res.contentLength ?? model.bytes;
      final sink = archive.openWrite();
      // Hashed as it streams in: no second pass over hundreds of MB.
      final digests = _DigestSink();
      final hasher = sha256.startChunkedConversion(digests);
      var received = 0;
      var lastYield = DateTime.now();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (DateTime.now().difference(lastYield).inMilliseconds > 150) {
          lastYield = DateTime.now();
          yield ModelDownloading((received / total).clamp(0, 1).toDouble());
        }
      }
      await sink.close();
      hasher.close();
      // A truncated, corrupted or swapped archive is never extracted.
      if (!verified(model, received, digests.value)) {
        yield ModelFailed(L10n.current.modelChecksumFailed);
        return;
      }

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
      if (client == null) http_.close();
      if (await archive.exists()) await archive.delete();
    }
  }

  Future<void> remove(SpeechModel model) async {
    final dir = Directory(p.join((await root()).path, model.id));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Collects the one digest a chunked SHA-256 conversion produces.
class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
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
      // Disposed while looking (a settings rebuild, the app closing).
      if (!ref.mounted) return;
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
