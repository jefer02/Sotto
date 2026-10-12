import 'dart:async';

import 'package:sotto/core/platform/platform_features.dart';

/// Runs before every test file. Tests describe Sotto's full feature set
/// whatever OS the runner is on (CI tests on Windows and Linux); the Linux
/// gating tests override platformFeaturesProvider themselves.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PlatformFeatures.current = PlatformFeatures.forOs('windows');
  await testMain();
}
