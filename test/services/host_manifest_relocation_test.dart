import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/services/screen/host_manifest.dart';

/// Sotto rewrites its native-messaging manifests on every start when their
/// contents differ (HostManifests.install), so the extension keeps finding
/// it wherever the portable folder is unzipped, moved, or installed.
void main() {
  List<HostManifestTarget> at(String exe) =>
      HostManifests.forPlatform(windows: true, executable: exe, dataDir: r'C:\Users\ana\AppData\Local\Sotto');

  const unzipped = r'C:\Users\ana\Downloads\Sotto-1.0.0-windows-x64\Sotto\sotto.exe';
  const moved = r'D:\Tools\Sotto Portable\sotto.exe';
  const installed = r'C:\Users\ana\AppData\Local\Programs\Sotto\sotto.exe';

  test('each manifest points at the executable that is running', () {
    for (final exe in [unzipped, moved, installed]) {
      for (final t in at(exe)) {
        expect(jsonDecode(t.contents)['path'], exe);
      }
    }
  });

  test('moving the folder changes the contents, so the next start rewrites them', () {
    final before = [for (final t in at(unzipped)) t.contents];
    final after = [for (final t in at(moved)) t.contents];
    for (var i = 0; i < before.length; i++) {
      expect(after[i], isNot(before[i]));
    }
  });

  test('the files and registry keys stay in the same per-user places wherever Sotto runs', () {
    final a = at(unzipped), b = at(installed);
    expect([for (final t in a) t.path], [for (final t in b) t.path]);
    expect([for (final t in a) ...t.registryKeys], [for (final t in b) ...t.registryKeys]);
    for (final key in [for (final t in a) ...t.registryKeys]) {
      expect(key, startsWith(r'Software\'));
    }
  });
}
