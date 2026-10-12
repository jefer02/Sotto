// The built-in DeepSeek key is no longer read from a Dart file, so the app
// compiles in a fresh clone and in CI. Pass it as a compile-time define:
//
//   cp secrets.example.json secrets.json      # git-ignored; paste your key
//   flutter run --dart-define-from-file=secrets.json
//   flutter build windows --release --dart-define-from-file=secrets.json
//
// or directly: --dart-define=DEEPSEEK_API_KEY=sk-…
//
// See lib/core/embedded_key.dart. Without it, Sotto asks each user for their
// own key in Settings › Integrations (voice following and the overlay work
// without any key).
