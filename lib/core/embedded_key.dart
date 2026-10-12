/// The DeepSeek key built into this copy of Sotto, so answers work out of
/// the box. It never lives in the source: builds pass it with
///   --dart-define=DEEPSEEK_API_KEY=sk-…
/// or, locally, --dart-define-from-file=secrets.json (git-ignored; template
/// in secrets.example.json). Empty in a fresh clone, in CI test jobs and in
/// any build made without it — Sotto then asks for the user's own key.
///
/// A key saved in Settings › Integrations always takes priority. Never
/// print or log this value.
const String kEmbeddedDeepSeekKey = String.fromEnvironment('DEEPSEEK_API_KEY');

/// Where people create their own DeepSeek key.
const deepSeekKeysUrl = 'https://platform.deepseek.com/api_keys';
