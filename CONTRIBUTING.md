# Contributing to Sotto

Thanks for helping. Sotto is a Flutter desktop app (Windows, macOS and experimental Linux) with no
backend: keep it that way. Everything runs on the user's computer except DeepSeek requests and the
one-time download of speech models.

## Setup

```sh
flutter --version          # 3.47.5 (stable)
flutter pub get
flutter run -d windows     # or -d macos / -d linux
```

You don't need a DeepSeek key to work on Sotto. Without one, voice following, the overlay, the
library and the editor all work; AI features ask for a key. To build with one, see
[Building with a DeepSeek key](README.md#build-from-source).

## Before you open a pull request

```sh
flutter analyze --no-pub          # must report no issues
flutter test --no-pub             # must pass
cd extension && npm test          # if you touched the browser extension
```

The render test boots the whole app and catches startup crashes that unit tests miss. It also
checks for overflows at the minimum window size (960 × 600) in both languages:

```sh
SOTTO_RENDER=1 SOTTO_RENDER_SIZE=960x600 SOTTO_RENDER_LANG=es flutter test test/visual
```

## Conventions

- **Lints and format.** `analysis_options.yaml` (flutter_lints, single quotes, `unawaited_futures`)
  with a 120-column page width. Format only the files you changed (`dart format -l 120 <files>`),
  not the whole tree, so diffs stay readable.
- **Naming.** Dart conventions: `UpperCamelCase` types, `lowerCamelCase` members, `snake_case` files.
  Widgets are named for what they show (`ScriptCard`, `SettingRow`), controllers for what they drive
  (`LiveController`), and providers end in `Provider`.
- **Design system.** Use the tokens in `lib/core/design/tokens.dart` (`SottoPalette`, `Space`,
  `Radii`, `Motion`, `Layout`) and the components in `lib/core/widgets/`. No magic numbers for colors,
  durations or spacing. Text must reach WCAG AA contrast in the light and dark themes.
- **Motion.** Durations come from `Motion` (120–200 ms for micro-interactions, 250–400 ms for panels and
  pages). Every animation must stop under reduce motion: check
  `MediaQuery.maybeDisableAnimationsOf(context)`, which already includes Sotto's own setting.
- **Strings.** Every user-facing string goes in **both** `lib/l10n/app_en.arb` and
  `lib/l10n/app_es.arb`, then run `flutter gen-l10n`. Spanish runs longer: check that nothing overflows.
  Widgets use `context.l10n`; code without a `BuildContext` uses `L10n.current`.
- **Platforms.** Features that need native code ask `platformFeaturesProvider`
  (`lib/core/platform/platform_features.dart`) rather than checking the OS. A feature a platform can't
  do must be hidden or explained, and must never crash or fail silently.
- **Tests.** Add tests with every change: pure logic in `test/domain`, services in `test/services`, and
  widgets in `test/widgets`. Tests must not need a DeepSeek key or a network connection.
- **Commits.** Small and focused, with an imperative subject ("Add pace stepper to Voice settings").

## Secrets

**Never commit a key.** The built-in DeepSeek key is passed at build time with
`--dart-define=DEEPSEEK_API_KEY=…` or `--dart-define-from-file=secrets.json`. `secrets.json` and the
legacy `lib/core/secrets.dart` are git-ignored. Don't print or log keys, and don't put them in test
fixtures. Use obvious fakes like `sk-test`. If you think a key was committed, don't push. Open a private
security advisory on GitHub instead.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
