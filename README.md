# Sotto

*The voice in the wings.* A live presentation assistant for macOS and Windows: it keeps your script
under the camera, follows your voice line by line, and drafts an answer when the room asks a question.

Built with Flutter 3.47 / Dart 3.13. Fully local: no backend and no account. Everything is stored on
this computer. The only network calls are DeepSeek (organizing scripts, answers, chat and, if you opt
in, screenshots for screen awareness, questionnaires and agent mode) and a one-time download of the
on-device speech models from GitHub. Speech recognition never leaves the computer.

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
capture and UI Automation for questionnaires). No permissions are needed.

**macOS permissions** (System Settings → Privacy & Security):

| Permission | Needed for | When it's asked |
|---|---|---|
| Microphone | Following your voice, capturing questions, chat dictation (push-to-talk) | First live session or first dictation |
| Screen Recording | Screen awareness, "Attach screen" in chat, questionnaires on screen | When you first use one; pre-flight checks it |
| Accessibility | Questionnaires on screen (reading and filling forms through the AX API) and agent mode | When you turn questionnaires on in Settings → Answers, or first press the shortcut |

**No App Sandbox on macOS.** Sotto is a personal-use app, not distributed through the App Store, so
`macos/Runner/Release.entitlements` and `DebugProfile.entitlements` don't enable
`com.apple.security.app-sandbox`. The sandbox would block exactly what questionnaire filling and agent
mode need: reading other apps' accessibility trees (AX API) and posting mouse and keyboard events
(CGEvent). Nothing is open by default — macOS still gates each capability behind the privacy
permissions above, and every feature that uses them is opt-in.

**Granting the permissions (once):**

1. `flutter run -d macos` (or open the built `Sotto.app`). The first live session asks for the
   **Microphone** — choose *Allow*.
2. **Screen Recording:** turn on Settings → Privacy → *Screen awareness* (or Settings → Answers →
   *Questionnaires on screen*). macOS shows its prompt; choose *Open System Settings*, switch **Sotto**
   on under Privacy & Security → Screen Recording, then quit and reopen Sotto (macOS applies Screen
   Recording only after a relaunch).
3. **Accessibility:** turn on *Questionnaires on screen* (or Settings → Privacy → *Agent mode*). macOS
   shows its prompt; choose *Open System Settings* and switch **Sotto** on under Privacy & Security →
   Accessibility. If Sotto isn't listed, press **+** and pick the app
   (`build/macos/Build/Products/Debug/Sotto.app` for a debug build).
4. Both settings pages show a warning row with *Open System Settings* while a permission is missing,
   and pre-flight checks them before going live.

Debug builds are signed ad hoc, so each rebuild looks like a new app to macOS: if a permission is
switched on but stops working after a rebuild, remove Sotto from the list (**−**) and add it again, or
reset it with `tccutil reset Accessibility app.sotto.sotto` and
`tccutil reset ScreenCapture app.sotto.sotto`.

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
| G | Agent task by voice (opt-in) | Esc | **Emergency stop** — agent and questionnaire filling |
| F | Fill the questionnaire on screen (opt-in) | C | Chat panel in the overlay |
| V (hold) | Push-to-talk: dictate a chat message | | |

All shortcuts are global, so they work while Zoom or your slides have focus. You can rebind them, or
change the shared chord, in Settings → Shortcuts. The recorder flags conflicts with system shortcuts
and other apps. F, C and V also work outside a live session: F turns the main window into the
questionnaire panel, C opens the Chat page, V opens it and starts dictating.

## Importing and organizing scripts

A script is usable within a second or two of importing, even at 10,000+ words:

1. **Instant first pass.** Files are parsed off the UI thread (`.txt` / `.md` / `.docx` on
   `Isolate.run`, PDFs on pdfrx's PDFium worker isolate) and the offline rule-based organizer runs on
   a background isolate too. The script opens right away as *Refining…* — you can read and edit it.
2. **AI refinement that never rewrites.** The text is split locally into numbered sentences (English
   and Spanish aware: abbreviations, initials, "3.5" / "48,2"). DeepSeek gets `[1] … [2] …` and
   returns only boundaries as JSON — `{"sections":[{"title":"…","beats":[[1,2],[3]],"cues":[{"after":3,"type":"slide","label":"4"}]}]}` —
   and the sections are rebuilt locally from the original sentences, so the wording is guaranteed
   unchanged and output tokens drop by ~90 %. Replies are validated (every sentence once, in order)
   and repaired locally; an unusable reply keeps the rule-based result for that part.
3. **Fast requests.** Thinking is off for organizing (`DeepSeekTaskProfile`), long scripts are cut
   into ~1,500-word chunks at headings (with one paragraph of context), sent 4 at a time with retry
   and exponential backoff on 429 / 5xx, and the identical system prompt comes first so DeepSeek's
   prefix cache applies.
4. **Progressive.** The library card and the editor show a real progress bar (chunks done / total).
   Each chunk lands in the open editor as it arrives — never in a part you edited or where your cursor
   is ("Kept your edits in 1 part"). Results are cached by a hash of the text, so importing the same
   file again is instant.

`DeepSeekTaskProfile` (`lib/services/ai/task_profile.dart`) is the one place that decides DeepSeek's
thinking per task: organize, answers and chat off (chat has a per-conversation *Think deeper*),
questionnaires and agent mode at low effort. Multi-turn requests with thinking on send each
`reasoning_content` back, as the API requires.

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
    forms/        Questionnaires: fields from accessibility trees, option matching, answer →
                  action mapping, verification, paging (pure, tested)
    chat/         Chat history trimming, request building, streaming-safe Markdown
    following/    Text normalizer ("$48.2" → "forty eight point two"), Smith–Waterman aligner,
                  FollowEngine (the rules from the "Following your voice" board)
    structuring/  Rule-based organizer, sentence splitter, ID-based AI plan: chunking,
                  validation / repair, local rebuild, progressive merge
  services/
    speech/       Mic capture (record), sherpa-onnx worker isolate, Whisper, VAD, models, dictation
    ai/           DeepSeek client (SSE, tool calls, task profiles), organizer, answers, chat,
                  questionnaires, agent model
    screen/       On-demand screenshots (Windows.Graphics.Capture / ScreenCaptureKit) and form
                  access (UI Automation / AX)
    agent/        Native input (SendInput + UI Automation) and the real agent executor
    tts/          Read aloud (flutter_tts)
  features/
    library/      Home, script lists, sessions, import (drop / paste / browse), readiness
    editor/       Script workspace: Write, Q&A prep, Rehearsals, live overlay preview
    preflight/    Go-live checks
    settings/     Shortcuts, Appearance, Voice & following, Answers, General, Integrations, Privacy
    live/         LiveController (the session state machine) and the overlay UI
    agent/        AgentController (confirmations, emergency stop, logging) and the agent panel
    questionnaire/  Questionnaire filling controller and overlay panel
    chat/         Chat page, overlay chat panel, composer, Markdown rendering
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

**Agent mode (opt-in).** Off by default; turn it on in Settings → Privacy. Describe a task
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

**Questionnaires on screen (opt-in).** Off by default; turn it on in Settings → Answers →
*Questionnaires on screen* (mode, answer language, short / detailed open answers, extra instructions).
`Ctrl+Alt+F` (or the overlay button) captures the display of the window in front, reads its form
through accessibility — Windows UI Automation (`windows/runner/native/forms.cpp`: text fields, radio
groups, checkboxes, combo boxes with labels and options), the AX API on macOS — and asks DeepSeek to
answer **from its own knowledge, not your script**, with the screenshot, the field list and your
extra instructions (name, role, preferences). Then it fills the form:

- Every field is marked **native_ax** (it has a working accessibility action) or **visual_only** (it
  doesn't — or isn't in the tree at all, as with much browser content on macOS). native_ax fields use
  the accessibility action (`ValuePattern.SetValue`, `SelectionItemPattern.Select`, `TogglePattern`,
  `ExpandCollapsePattern` + select; `AXValue` / `AXPress`). On macOS, Sotto also asks Chrome, Edge and
  Electron apps to build their web accessibility tree (`AXManualAccessibility`), so more fields take
  that path.
- visual_only fields are filled where the screenshot shows them — DeepSeek reads each question's kind
  and box off the screenshot, and the box is mapped to real screen coordinates (DPI and
  multi-monitor aware). Text: click the field, wait 80 ms, select what's there, then type the answer as
  one Unicode key event per character (SendInput on Windows, CGEvent on macOS — never a clipboard
  paste, so web inputs register real typing); line breaks only in multi-line fields. Drop-downs: click
  to open, find the option on a fresh screenshot and click it (or type its label + Enter if it can't be
  seen). Radios and checkboxes: click the centre. 100–300 ms between fields.
- It then re-reads the tree and takes a new screenshot to verify every value. A field that didn't take
  is retried once, typing at half speed (40 ms between keys instead of 20 ms); if it still fails, the
  overlay marks it **could not fill** so you can fill it yourself. It presses *Next* on multi-page forms
  (up to 10 pages; buttons found in the tree or on the screenshot) and scrolls for more — and **stops
  before Submit**: "Done — review and submit", and only Enter clicks it.
- The loop is `lib/domain/forms/form_runner.dart` — pure, driven in tests by a fake browser window that
  exposes no accessibility content (`test/integration/form_fill_fake_browser_test.dart`: single- and
  multi-line text, a native select, a radio group, a checkbox group, a Next button to a second page).
- *Show me the answers first* lists every answer in the overlay (editable) and fills on Enter.
- Password and payment fields are never sent or filled, card numbers are never typed, `Ctrl+Alt+Esc`
  stops at once, an amber "Sotto is filling" frame shows while it works, and every filled field is
  logged in the session (Sessions shows it) unless Privacy → *Keep history* is *Don't keep*.
  Screenshots are never saved.

**Chat.** A general assistant chat with DeepSeek: the *Chat* page in the main window (conversations
you can rename and delete) and, while live, a compact panel in the overlay (`Ctrl+Alt+C`) that never
takes the keyboard from Zoom or PowerPoint until you click its input. Enter sends, Shift+Enter is a
new line; hold `Ctrl+Alt+V` to dictate with the on-device Whisper model (the transcript lands in the
input, or is sent at once — Settings → Answers → Chat). *Attach screen* sends a screenshot with the
next message, *Use my script* adds your script as context (off by default), and replies stream as
Markdown with copy, read-aloud and stop. Thinking is off unless you turn on *Think deeper* for a
conversation. The last 20 messages go as context (10 / 20 / 40 in Settings). Chats are stored in
the `chats` Hive box and follow Privacy → *Keep history* and *Delete all local data*.

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
  section skips), including Spanish numbers and a Spanish script read aloud; the sentence splitter,
  ID-based organizing (validation, repair, rebuild, chunking, merge) and a 15,000-word benchmark
  (`flutter test test/domain/organize_test.dart` prints the timings); questionnaire fields, option
  matching, answer mapping and verification over fake UI Automation trees; chat history, dictation
  insertion and streaming Markdown.
- `test/services` — DeepSeek request shapes (task profiles, JSON mode, vision, tool calls) and a guard
  that speech stays on-device (no cloud STT endpoint, no host but DeepSeek and GitHub).
- `test/integration` — real speech: a sample WAV streamed through the sherpa-onnx worker, driving the
  follow engine. It runs once the light English model is installed (or with `SOTTO_MODEL_DIR`); on
  Linux, point `LD_LIBRARY_PATH` at `build/linux/x64/debug/bundle/lib`.
- `test/widgets` — renders the live answer card with the bundled fonts to `build/answer_card.png`, and
  the questionnaire panel, overlay chat and Chat page at their real sizes.
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
- **Questionnaires on macOS** use the AX API where the page exposes it and fall back to clicking and
  typing (CGEvent, `SyntheticInput` in `MainFlutterWindow.swift`) where it doesn't — this covers
  Chrome, Edge and Firefox pages that don't expose their content to AX. The same CGEvent input now
  backs agent mode on macOS. Both need Accessibility permission.
- **Visual-only fields depend on the model's eyes.** Where a page exposes nothing, DeepSeek finds the
  questions, their boxes and the drop-down options on screenshots; small or crowded controls can be
  missed. Anything that doesn't verify is marked *could not fill* rather than guessed.
- The macOS ScreenCaptureKit, AX and CGEvent code is written but has not been compiled or run on a
  Mac yet (this branch was built on Windows).
- Linux builds and runs for development (used for verification), but it is not a target. Global
  arrow-key hotkeys and read-aloud aren't available there.

Typefaces: Geist, Geist Mono and Atkinson Hyperlegible Next, bundled under the SIL Open Font License
(see `assets/fonts/`).
