import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/settings.dart';

/// What this platform can do. Windows and macOS have everything; Linux is
/// experimental: the library, editor, voice following, the overlay, DeepSeek
/// answers, chat and sessions work, while the features that need native
/// code Sotto only has for Windows and macOS are hidden or explained.
///
/// The UI asks here instead of checking the OS, and [clamp] keeps settings
/// that can't work switched off, so no controller tries them and fails
/// silently. Tests override [platformFeaturesProvider] with [forOs].
class PlatformFeatures {
  const PlatformFeatures({
    required this.os,
    required this.screenCapture,
    required this.formFilling,
    required this.agent,
    required this.browserBridge,
    required this.captureExclusion,
    required this.readAloud,
    required this.biometrics,
    this.wayland = false,
  });

  factory PlatformFeatures.forOs(String os, {bool wayland = false}) {
    final full = os == 'windows' || os == 'macos';
    return PlatformFeatures(
      os: os,
      // Screenshots for "ask about the screen" (app.sotto/screen).
      screenCapture: full,
      // Reading and filling forms on screen (app.sotto/forms).
      formFilling: full,
      // Mouse and keyboard control (app.sotto/input).
      agent: full,
      // The Sotto Bridge native-messaging host (named pipe / Unix socket).
      browserBridge: full,
      // The overlay hidden from screen sharing (WDA_EXCLUDEFROMCAPTURE /
      // NSWindow.sharingType).
      captureExclusion: full,
      // flutter_tts has no Linux implementation.
      readAloud: full,
      // App Lock: Windows Hello / Touch ID (local_auth has no Linux one).
      biometrics: full,
      wayland: os == 'linux' && wayland,
    );
  }

  /// This machine's features. Tests pin it (test/flutter_test_config.dart) so
  /// they behave the same on every CI runner.
  static PlatformFeatures current = PlatformFeatures.forOs(
    Platform.operatingSystem,
    wayland: Platform.environment['XDG_SESSION_TYPE'] == 'wayland' || Platform.environment['WAYLAND_DISPLAY'] != null,
  );

  final String os;
  final bool screenCapture;
  final bool formFilling;
  final bool agent;
  final bool browserBridge;
  final bool captureExclusion;
  final bool readAloud;
  final bool biometrics;

  /// A Wayland session on Linux: global shortcuts (keybinder) and
  /// always-on-top only work through XWayland, if at all.
  final bool wayland;

  bool get isLinux => os == 'linux';

  /// Settings with what this platform can't do switched off.
  AppSettings clamp(AppSettings s) {
    if (screenCapture && formFilling && agent) return s;
    return s.copyWith(
      screenAwareness: screenCapture ? null : false,
      attachSlideToAnswers: screenCapture ? null : false,
      formsEnabled: formFilling ? null : false,
      formsAutoFill: formFilling ? null : false,
      showFormsNav: formFilling ? null : false,
      agentEnabled: agent ? null : false,
    );
  }
}

final platformFeaturesProvider = Provider<PlatformFeatures>((ref) => PlatformFeatures.current);
