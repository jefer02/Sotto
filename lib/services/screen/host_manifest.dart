import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'bridge_protocol.dart';
import 'bridge_transport.dart';

/// The Sotto Bridge extension's identity (its store pages are in
/// features/forms/browser_extension_rows.dart).
abstract final class BridgeExtension {
  /// The native messaging host's name — the same in every browser.
  static const hostName = 'app.sotto.bridge';

  /// Chrome and Edge: the ID that `key` in extension/manifest.json pins.
  /// When the stores assign their own IDs, add them here: only the IDs in
  /// this list can talk to the host.
  static const chromiumIds = ['oaompapbahpnpllcdpidhojbdoblcpil'];

  /// Firefox: `browser_specific_settings.gecko.id` in extension/manifest.json.
  static const firefoxId = 'bridge@sotto.app';
}

/// One manifest file to write, and on Windows the registry key that points
/// each browser at it.
class HostManifestTarget {
  const HostManifestTarget({
    required this.browsers,
    required this.path,
    required this.json,
    this.registryKeys = const [],
  });

  final List<BrowserKind> browsers;
  final String path;
  final Map<String, Object?> json;

  /// Under HKEY_CURRENT_USER; empty on macOS.
  final List<String> registryKeys;

  String get contents => '${const JsonEncoder.withIndent('  ').convert(json)}\n';
}

/// The native messaging host manifests, per OS — per user, so no admin
/// rights are needed. `allowed_origins` / `allowed_extensions` name the
/// extension's own IDs only.
abstract final class HostManifests {
  static Map<String, Object?> chromium(String executable) => {
    'name': BridgeExtension.hostName,
    'description': 'Sotto Bridge',
    'path': executable,
    'type': 'stdio',
    'allowed_origins': [for (final id in BridgeExtension.chromiumIds) 'chrome-extension://$id/'],
  };

  static Map<String, Object?> firefox(String executable) => {
    'name': BridgeExtension.hostName,
    'description': 'Sotto Bridge',
    'path': executable,
    'type': 'stdio',
    'allowed_extensions': [BridgeExtension.firefoxId],
  };

  /// [executable] is the Sotto binary (it becomes the host when a browser
  /// starts it). Windows: [dataDir] holds the files (%LOCALAPPDATA%\Sotto)
  /// and the registry points at them. macOS: [home] is the user's home and
  /// the files go in each browser's own NativeMessagingHosts folder.
  static List<HostManifestTarget> forPlatform({
    required bool windows,
    required String executable,
    String home = '',
    String dataDir = '',
  }) {
    const file = '${BridgeExtension.hostName}.json';
    if (windows) {
      final ctx = p.Context(style: p.Style.windows);
      final dir = ctx.join(dataDir, 'NativeMessagingHosts');
      const key = r'Software\{0}\NativeMessagingHosts\' + BridgeExtension.hostName;
      return [
        HostManifestTarget(
          browsers: const [BrowserKind.chrome, BrowserKind.edge],
          path: ctx.join(dir, file),
          json: chromium(executable),
          registryKeys: [key.replaceFirst('{0}', r'Google\Chrome'), key.replaceFirst('{0}', r'Microsoft\Edge')],
        ),
        HostManifestTarget(
          browsers: const [BrowserKind.firefox],
          path: ctx.join(dir, '${BridgeExtension.hostName}.firefox.json'),
          json: firefox(executable),
          registryKeys: [key.replaceFirst('{0}', 'Mozilla')],
        ),
      ];
    }
    final ctx = p.Context(style: p.Style.posix);
    final support = ctx.join(home, 'Library', 'Application Support');
    return [
      HostManifestTarget(
        browsers: const [BrowserKind.chrome],
        path: ctx.join(support, 'Google', 'Chrome', 'NativeMessagingHosts', file),
        json: chromium(executable),
      ),
      HostManifestTarget(
        browsers: const [BrowserKind.edge],
        path: ctx.join(support, 'Microsoft Edge', 'NativeMessagingHosts', file),
        json: chromium(executable),
      ),
      HostManifestTarget(
        browsers: const [BrowserKind.firefox],
        path: ctx.join(support, 'Mozilla', 'NativeMessagingHosts', file),
        json: firefox(executable),
      ),
    ];
  }

  /// Writes the manifests (and on Windows the registry keys) for this user.
  /// macOS: only for browsers whose support folder exists. Never throws.
  static Future<void> install() async {
    final windows = Platform.isWindows;
    if (!windows && !Platform.isMacOS) return;
    final env = Platform.environment;
    final targets = forPlatform(
      windows: windows,
      executable: Platform.resolvedExecutable,
      home: env['HOME'] ?? '',
      dataDir: p.join(env['LOCALAPPDATA'] ?? env['APPDATA'] ?? '', 'Sotto'),
    );
    for (final t in targets) {
      try {
        final file = File(t.path);
        if (!windows && !await file.parent.parent.exists()) continue; // browser not installed
        if (!await file.exists() || await file.readAsString() != t.contents) {
          await file.parent.create(recursive: true);
          await file.writeAsString(t.contents, flush: true);
        }
        for (final key in t.registryKeys) {
          await PipeTransport.registerHost(key, t.path);
        }
      } catch (_) {
        // A browser folder we can't write: that browser stays "Not installed".
      }
    }
  }
}
