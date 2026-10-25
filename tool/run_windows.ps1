# flutter run for Windows that always starts the new build: closes any open
# Sotto first (the app, or the browser extension's bridge — the same
# sotto.exe), which would otherwise keep the build from linking or starting.
# Passes secrets.json, the DeepSeek key for dev runs, when there is one.
#   .\tool\run_windows.ps1            (extra arguments go to flutter run)
Get-Process sotto -ErrorAction SilentlyContinue | Stop-Process -Force
$root = Split-Path $PSScriptRoot -Parent
$defines = if (Test-Path "$root\secrets.json") { @("--dart-define-from-file=$root\secrets.json") } else { @() }
flutter run -d windows @defines @args
