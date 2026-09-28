# Sotto

*The voice in the wings.* A live presentation assistant for macOS and Windows: it keeps your script
under the camera, follows your voice line by line, and drafts an answer when the room asks a question.

Built with Flutter 3.47 / Dart 3.13. Fully local: no backend and no account. Everything is stored on
this computer. The only network calls are DeepSeek (answers and, if you opt in, screenshots for screen
awareness and agent mode) and a one-time download of the on-device speech models.

## Run it

```sh
cp lib/core/secrets.example.dart lib/core/secrets.dart   # once; paste your DeepSeek key there
flutter pub get
flutter run -d macos     # or -d windows
flutter test             # unit + widget tests
```

**Built-in DeepSeek key.** `lib/core/secrets.dart` is git-ignored and holds
`const String kDeepSeekApiKey = '…';`. The app uses it unless a key is saved in Settings →
Integrations, which takes priority. The key is never printed or logged. From a fresh clone, copy
`secrets.example.dart` first — the build needs the file to exist (an empty key just means answers
need a key in Integrations).

**Windows** builds need `nuget.exe` on `PATH` (for the `flutter_tts` plugin) and Visual Studio's C++
workload with a Windows 10/11 SDK (the runner's `sotto_native` library uses C++/WinRT for screen
capture). No permissions are needed.

**macOS permissions** (System Settings → Privacy & Security):

| Permission | Needed for | When it's asked |
|---|---|---|
| Microphone | Following your voice, capturing questions | First live session |
| Screen Recording | Screen awareness ("Ask about the screen") | When you turn it on in Settings → Privacy; pre-flight checks it |
| Accessibility | Agent mode (mouse and keyboard) | Not yet — see *Known limitations* |

On first launch the library is seeded with the design's example talk: "Q3 Board Review", or
"Revisión del tercer trimestre" on a Spanish system.

A first-run welcome walks through the two setup steps (voice models, then a first script). You can
redo them any time:

1. **Settings → Voice & following → On-device models.** Download *English · streaming* (follows your
   voice) and *Whisper base* (question transcripts, other languages). They are fetched once from the
   sherpa-onnx releases and used offline after that.
2. **Answers use DeepSeek.** The key is built in from `lib/core/secrets.dart` (git-ignored; copy it
   from `secrets.example.dart`). **Settings → Integrations** can override it with a key stored in
   the Keychain / Credential Manager, pick the model (the list comes from DeepSeek's `GET /models`;
   the default is `deepseek-flash`) and test the connection.
3. Open a script and choose **Go live** (`⌃⌥L` / `Ctrl+Alt+L`).

Without models the overlay still works on hotkeys, with a timed advance. Without a key, everything
works except drafting answers.

## Live shortcuts (default chord ⌃⌥ / Ctrl+Alt)

| Key | Action | Key | Action |
|---|---|---|---|
| L | Go live / end | Q | Ask a question (press again or pause 1.2 s to finish) |
| Space | Pause / resume following | ↩ (hold 0.5 s) | Copy answer for the meeting chat |
| ↓ / ↑ | Next / previous beat | R | Read answer aloud (headphones) |
| → / ← | Next / previous section | X | Dismiss answer / cancel question |
| O | Hide overlay instantly | H | Questions history |
| T | Click-through | = / − | Text size |
| M | Move to next display | S | Ask about the screen (opt-in) |
| G | Agent task by voice (opt-in) | Esc | Emergency stop for the agent |

All shortcuts are global, so they work while Zoom or your slides have focus. You can rebind them, or
change the shared chord, in Settings → Shortcuts. The recorder flags conflicts with system shortcuts
and other apps.

## Languages

The interface is in English and Spanish. **Settings → General → Language** offers *System*, *English* or
*Español*, and the change applies instantly. *System* follows the OS language and falls back to
English. Dates, times, numbers and plurals follow the chosen language ("hace 4 h", "12 sept", "31,4 %").

- **Strings** live in `lib/l10n/app_en.arb` (template) and `app_es.arb`. `flutter pub get` or
  `flutter gen-l10n` regenerates `AppLocalizations`. Widgets use `context.l10n.key`; code without a
  `BuildContext` (models, services, the live controller) uses `L10n.current`.
- **Voice following in Spanish.** The normalizer reads numbers and symbols the way they are spoken in
  Spanish ("48,2" → "cuarenta y ocho coma dos", "%" → "por ciento"). It also folds accents and uses
  Spanish stop words. Cues accept `[DIAPOSITIVA 3]`, `[PAUSA]` and `[NOTA]` as well as the English
  words.
- On a Spanish system, first launch also sets the speech language to *Español (España)* or
  *Español (Latinoamérica)*.
- Answers are drafted in the language of the question by default (Settings → Answers → Language).
- Content you write is never translated. Scripts keep the language they were written in.

## Architecture

```
lib/
  app/            App root, go_router routes, global shortcuts
  core/
    design/       Design tokens (tokens.dart), typography, theme, 48 icons from the design
    widgets/      Component library: buttons, keycaps, controls, chips, settings rows, chrome
    platform/     WindowService (main window ⇄ overlay), HotkeyService, key labels
  data/
    models/       Script → Section → Beat (+Cue), settings, Q&A entries, sessions (hand-written JSON)
    storage/      Hive CE boxes (LocalStore), API keys in the OS keychain (SecretStore)
    import/       .txt / .md / .docx (OOXML) / .pdf (PDFium) → text
    repositories.dart   Riverpod providers over the stores
  l10n/           ARB catalogs (en, es), generated AppLocalizations, L10n helpers
  domain/
    agent/        Agent loop, tool actions, coordinate mapping, safety gate (pure, tested)
    following/    Text normalizer ("$48.2" → "forty eight point two"), Smith–Waterman aligner,
                  FollowEngine (the rules from the "Following your voice" board)
    structuring/  Offline rule-based organizer: sections, one-breath beats, cues, hint words
  services/
    speech/       Mic capture (record), sherpa-onnx worker isolate, Whisper, VAD, models
    ai/           DeepSeek client (SSE streaming, tool calls), model list, answers, agent model
    screen/       On-demand screenshots (Windows.Graphics.Capture / ScreenCaptureKit)
    agent/        Native input (SendInput + UI Automation) and the real agent executor
    tts/          Read aloud (flutter_tts)
  features/
    library/      Home, script lists, sessions, import (drop / paste / browse), readiness
    editor/       Script workspace: Write, Q&A prep, Rehearsals, live overlay preview
    preflight/    Go-live checks
    settings/     Shortcuts, Appearance, Voice & following, Answers, General, Integrations, Privacy
    live/         LiveController (the session state machine) and the overlay UI
    agent/        AgentController (confirmations, emergency stop, logging) and the agent panel
    onboarding/   First-run welcome
```

**Overlay styles.** *Text only* (the default) draws no background at all: the window, DWM backdrop
(Windows) and vibrancy (macOS) are fully transparent and every glyph carries a configurable outline
and soft shadow, so it reads over dark slides, white slides and video grids alike. The status strip
and controls appear on hover or while a shortcut is held and fade out 2 s later. *Panel* keeps the
translucent card. Both keep capture exclusion and never take focus.

**Screen awareness (opt-in).** Off by default; turn it on in Settings → Privacy. Then `⌃⌥S` /
`Ctrl+Alt+S` takes one screenshot of the display with the overlay (or the one under the pointer),
shows a red "Capturing screen" light, listens for an optional spoken question and answers about what
is on screen. Optionally, audience questions can carry a screenshot of the current slide. Capture is
native — Windows.Graphics.Capture with a BitBlt fallback (`windows/runner/native/screen_capture.cpp`),
ScreenCaptureKit on macOS 14+ (`CGDisplayCreateImage` on 12–13) — scaled to 1300 px on the long side,
JPEG-encoded and sent to DeepSeek as an `image_url` part in the user message. Sotto's own window is
always excluded, screenshots are held in memory only and never written to disk, and nothing is ever
captured in the background. On macOS this needs **Screen Recording** permission; pre-flight checks it.

**Agent mode (opt-in, Windows).** Off by default; turn it on in Settings → Privacy. Describe a task
in the Q&A prep tab ("fill this form with my details from the prep docs") or say it with `Ctrl+Alt+G`
while live. The loop — `lib/domain/agent/agent_loop.dart`, pure and tested with a fake executor —
takes a screenshot, asks DeepSeek for one tool call (`click`, `double_click`, `right_click`,
`type_text`, `press_keys`, `scroll`, `move_mouse`, `wait`, `screenshot`, `done`), maps the model's
screenshot pixels back to physical screen pixels (DPI and multi-monitor aware,
`coordinates.dart`), runs the safety gate (`safety.dart`), executes and repeats, for at most 25 steps.
Input is native: `SendInput` with Unicode typing, plus UI Automation to know when the focused field
is a password (`windows/runner/native/input.cpp`). Safety rules, all mandatory:

- Default mode *Confirm each action*: the overlay shows the next action ("Click “Submit” at 812,440")
  and waits for Enter (run) or Esc (stop). *Run automatically* still stops before anything that
  submits, sends, pays, deletes or buys.
- `Ctrl+Alt+Esc` is a global emergency stop: it cancels the loop at once and releases every held key
  and mouse button.
- Typing into password fields, or anything that looks like payment data (card numbers, CVV, IBAN…),
  is blocked outright and the model is told so.
- An amber frame and an "Agent in control" badge are shown whenever the agent has the controls.
- Every action is logged in the session record; Sessions shows it for review.

**One window, two personalities.** Going live morphs the main window into the overlay. It becomes
frameless, always on top, transparent, resizable and draggable, and it snaps under the camera. Ending
the session restores it exactly. The platform extras window_manager doesn't cover live in a small
native channel, `app.sotto/overlay`:

- **macOS** (`macos/Runner/MainFlutterWindow.swift`): the window is an `NSPanel`. In the overlay it is
  non-activating, never takes key focus, sits at `.statusBar` level on every Space and over
  full-screen apps, uses `sharingType = .none`, and has a vibrancy blur.
- **Windows** (`windows/runner/flutter_window.cpp`): `WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`, plus
  `MA_NOACTIVATE` on click, `WDA_EXCLUDEFROMCAPTURE`, and a Windows 11 acrylic backdrop with rounded
  corners.

**Voice following.** 16 kHz mic audio goes to sherpa-onnx in a background isolate, so inference never
touches the 120 Hz UI thread. The rolling transcript is aligned against a band of the script (one beat
back, three ahead) with a local alignment over normalized, phonetically keyed tokens. The follow
engine applies the design's rules:

- dim a word at ≥ 0.7 confidence
- advance at 80 % of a beat
- never scroll back on a guess
- hold still during ad-libs and re-lock on a three-word match
- give manual keys priority

The overlay glides by translating one pre-laid-out, repaint-isolated column, so advancing only
recomposites a layer.

**Answers.** An offline BM25 ranking picks script sections and prep-document excerpts. Only the
question and those excerpts are sent. Q&A-prep answers that match are shown instantly with no model
call. Responses stream in a line protocol, so the headline appears first and the points follow.
Live answers run with DeepSeek's thinking mode off for latency; `reasoning_content` from thinking
models is ignored.

## Tests

- `test/domain` — normalizer, aligner and follow rules (advance, hold, relock, backward jumps,
  section skips), including Spanish numbers and a Spanish script read aloud.
- `test/integration` — real speech: a sample WAV streamed through the sherpa-onnx worker, driving the
  follow engine. It runs once the light English model is installed (or with `SOTTO_MODEL_DIR`); on
  Linux, point `LD_LIBRARY_PATH` at `build/linux/x64/debug/bundle/lib`.
- `test/widgets` — renders the live answer card with the bundled fonts to `build/answer_card.png`.
- `test/visual` — opt-in: `SOTTO_RENDER=1 flutter test test/visual` renders every main-window screen
  (and the welcome dialog) to `build/screens/*.png`; `SOTTO_RENDER_LANG=en` for English.

## Known limitations

- **Meeting chat.** "Send to chat" copies the answer to the clipboard for you to paste. Posting
  directly to Zoom/Teams needs their OAuth apps, which conflicts with running without a backend.
- **Questions in a video call** arrive as system audio. Choose a loopback input (BlackHole on macOS,
  "Stereo Mix" / VB-Cable on Windows) in Settings → Voice & following → *Questions come from*.
- **Screen capture.** On macOS 15+, a full-screen share can still capture the overlay (ScreenCaptureKit).
  Pre-flight says so. Share a window instead.
- **Live following** uses a streaming model for English. Spanish and other languages follow via
  Whisper, re-transcribing about once a second, so they react a little later.
- Not built from the design: the menu-bar item, calendar integration, presentation-clicker following
  and cloud accounts.
- **Agent mode on macOS is not wired up yet.** The Dart side is ready (`services/agent`), but the
  native half — CGEvent posting and the AX API in `MainFlutterWindow.swift`, an Accessibility
  permission check — is not in the repo, and it also requires turning off the App Sandbox in
  `macos/Runner/*.entitlements` (sandboxed apps can't post input events to other apps). That is a
  security trade-off to decide deliberately; until then the agent reports "Windows only" on macOS.
- The macOS ScreenCaptureKit code is written but has not been compiled on a Mac yet.
- Linux builds and runs for development (used for verification), but it is not a target. Global
  arrow-key hotkeys and read-aloud aren't available there.

Typefaces: Geist, Geist Mono and Atkinson Hyperlegible Next, bundled under the SIL Open Font License
(see `assets/fonts/`).
