# How Sotto works

Technical notes for contributors: how scripts are organized, how the overlay and voice following work,
what each opt-in feature does on each platform, and how it is tested. For installing and using Sotto,
see the [README](../README.md).

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
| G | Agent task by voice (opt-in) | Esc | **Emergency stop** — agent, form filling, auto-fill (pauses) |
| F | Fill the form on screen (opt-in) | C | Chat panel in the overlay (with *Show chat*) |
| V (hold) | Push-to-talk: dictate a chat message (with *Show chat*) | | |

All shortcuts are global, so they work while Zoom or your slides have focus. You can rebind them, or
change the shared chord, in Settings → Shortcuts. The recorder flags conflicts with system shortcuts
and other apps. F, C, V and Esc also work outside a live session: F fills the form in front (the main
window becomes the forms overlay), C opens the Chat page, V opens it and starts dictating (C and V
only with Settings → General → *Show chat* on), Esc stops whatever Sotto is doing on screen.

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

## Browser extension internals

**How it connects.** Permissions: `activeTab`, `scripting`, `nativeMessaging` (plus the optional site
access above). The browser starts Sotto's own executable as the native messaging host (4-byte
length-prefixed JSON on stdin / stdout), which relays to the running app over a named pipe
(`\\.\pipe\sotto-bridge-<your SID>`: DACL limited to your user, remote clients refused, the client's
process token checked; `windows/runner/native/bridge.cpp`) on Windows, or a Unix socket in a `0700`
folder on macOS (peer user checked; `macos/Runner/AppDelegate.swift`). The host manifest allows only the
extension's own ID (`allowed_origins` for Chrome / Edge, `allowed_extensions` for Firefox). Every
message is validated against a schema (`lib/services/screen/bridge_protocol.dart`), every read and action
is logged in the session record, and `Ctrl+Alt+Esc` cancels whatever the extension was about to do.

**Developing it.** Load `extension/` unpacked (`chrome://extensions` → Developer mode; Firefox:
`about:debugging` → Load Temporary Add-on). The `key` in `manifest.json` pins the Chrome / Edge ID that
`lib/services/screen/host_manifest.dart` allows; add the store-assigned IDs there when publishing. Tests:
`cd extension && npm install && npm test` (DOM tests with jsdom).

## Architecture

```
lib/
  app/            App root, go_router routes, global shortcuts; AppSession (start, lock,
                  unlock), the unlock screen and auto-lock
  core/
    design/       Design tokens (tokens.dart), typography, theme, 48 icons from the design
    widgets/      Component library: buttons, keycaps, controls, chips, settings rows, chrome
    platform/     WindowService (main window ⇄ overlay), HotkeyService, key labels
  data/
    models/       Script → Section → Beat (+Cue), settings, Q&A entries, sessions (hand-written JSON)
    storage/      Hive CE boxes (LocalStore), API keys in the OS keychain (SecretStore),
                  where things live on disk (StoragePaths)
    lock/         App lock: the vault (Argon2id / AES-GCM / HKDF), recovery key, throttle,
                  crash-safe encrypt/decrypt migration
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
    forms/        Auto-fill controller, overlay status bar and log, the Forms page
    chat/         Chat page, overlay chat panel, composer, Markdown rendering
    onboarding/   First-run welcome
```

**Overlay styles.** *Text only* (the default) draws no background at all: the window, DWM backdrop
(Windows) and vibrancy (macOS) are fully transparent and every glyph carries a configurable outline
and soft shadow, so it reads over dark slides, white slides and video grids alike. The status strip
and controls appear on hover or while a shortcut is held and fade out 2 s later. *Panel* keeps the
translucent card. Both keep capture exclusion and never take focus.

**Overlay size.** The overlay is always a small floating window — 480 × 120 px just below the top
centre of the primary display the first time, then wherever you leave it. Drag any edge to resize it
(minimum 320 × 60); position and size are saved 500 ms after you stop, per display. It can't be
maximised, zoomed, tiled or snapped to fill the screen (a maximised or full-screen main window is
restored first when you go live, and put back when the session ends); only your own edge drag makes
it big. Its **height follows the text**: after every beat it becomes just tall enough for the lines
showing (150 ms ease-out), up to Settings → Appearance → *Max overlay height* (20–80 % of the display,
default 40 %); drag the height yourself and that becomes the maximum for the session. The eye-line
stays put while it does.

**Overlay text color.** Settings → Appearance → *Overlay text color*: *Auto* (default), *Always light*,
*Always dark* or *Custom* (your own text and outline colors). *Auto* samples the few pixels behind the
overlay every 800 ms while live (and at once on a slide cue), with Sotto itself excluded: average
brightness above one half gives near-black text, outline and shadow; below, near-white text and a soft
glow. A change is kept only when a second sample 400 ms later agrees, so slide transitions don't
flicker, and it crossfades over 200 ms. It is pixel math on this computer — nothing is encoded, saved or
sent, and no AI is involved. On macOS it needs Screen Recording; without it the text keeps its color.

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

**Forms (opt-in).** Filling forms, quizzes and exams has its own page — *Forms* in the sidebar
(Settings → General → *Show Forms in sidebar*) — and its own settings, Settings → Forms: *Auto-fill
forms and quizzes* (the master switch, mirrored on the page), *Answer questionnaires on screen*
(`Ctrl+Alt+F`), *Fill automatically / Show me the answers first*, *Scroll to find more questions*,
extra instructions (name, role, preferences), answer language (the form's or the app's), short or
detailed open answers, what is sent, and *Clear fill history*. The Forms page shows the switch, a
status card (Off / Watching / Filling… N/M / Paused, with Pause and Stop), *Fill what's on screen now*
(3 s to switch to the form — the same as `Ctrl+Alt+F`) and the recent fills: when, which app or
website, how many fields, how it ended; tap one for every answer with its question type. It follows
Privacy → *Keep history*.

*Auto-fill* watches the window in front every 1.5 s. When a new form appears — its questions, not
their answers, are compared (a hash of the fields' kinds, labels and options, or the window and its
title when a page exposes fewer than two fields) — it runs one fill cycle: read the fields and their
types, send the screenshot and the field list to DeepSeek, fill, verify, scroll for more (up to 10
times a page while new questions keep appearing; UI Automation's ScrollPattern / the AX scroll bar
says when the page ends), press Next, and stop at Submit: "Done — review and submit yourself". It never
presses Submit, Send, Pay, Buy, Confirm or Delete on its own (a "Next" with those words counts as
Submit). One cycle at a time; a page that appears meanwhile is looked at right after. Question types:
short and long text, multiple choice A/B/C/D (DeepSeek returns the letter *and* the option's text and
either can match — Google Forms shows no letters, exam platforms often show only letters), true /
false, checkboxes, drop-downs, scales and ratings (1–5, stars, Likert), matching and ordering (dragged
with a real mouse-down → move → mouse-up), image options, and questions shown only as text (a PDF, a
read-only exam page): their answers appear in the overlay and nothing is touched. Each answer comes
with a one-line reason, shown in the overlay's log. While auto-fill is on, the overlay has a status
bar — "● Auto-fill ON" with Pause and Stop (hold 1 s; a ring counts down), "⏸ Paused" with Resume,
"Filling… 4/9 — question" with Stop now — and a scrollable log; outside a live session the window
becomes this overlay until *Open Sotto*. `Ctrl+Alt+Esc` cancels a cycle and pauses the watcher.

Web forms are read in this order: the **browser extension** (the page's own DOM — see
[Browser extension](#browser-extension)), then UI Automation / AX, then the screenshot alone (DeepSeek finds
the questions and options on it). Fields read through the extension are filled through it too.

**Questionnaires on screen.** `Ctrl+Alt+F` (or the overlay button) captures the display of the window
in front, reads its form
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

**Chat (opt-in).** The chat is off by default so it stays out of the way: turn it on in
Settings → General → *Show chat*. That adds *Chat* to the sidebar and turns on its shortcuts (C and
V); with it off, neither exists. A general assistant chat with DeepSeek: the *Chat* page in the main
window (conversations you can rename and delete) and, while live, a compact panel in the overlay
(`Ctrl+Alt+C`) that opens only when you press it, never takes the keyboard from Zoom or PowerPoint
until you click its input, and closes itself after 60 s without activity (30 s / 1 / 2 / 5 min or
never, in Settings → General; never while a reply is arriving). Enter sends, Shift+Enter is a
new line; hold `Ctrl+Alt+V` to dictate with the on-device Whisper model (the transcript lands in the
input, or is sent at once — Settings → General → Chat). *Attach screen* sends a screenshot with the
next message, *Use my script* adds your script as context (off by default), and replies stream as
Markdown with copy, read-aloud and stop. Thinking is off unless you turn on *Think deeper* for a
conversation. The last 20 messages go as context (10 / 20 / 40 in Settings → General). Chats are stored in
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

## App lock

Opt-in (Settings → Privacy → App lock). Off, Sotto starts exactly as before.

**Key hierarchy.** A random 32-byte data key (DEK, `Random.secure()`) encrypts the data boxes
(`HiveAesCipher`, AES-256-CBC per record). The DEK is never written in plain form; it is wrapped in
`lock_vault.json` twice:

- under a key from the **password**: Argon2id (`cryptography`'s `DartArgon2id`, run in
  `Isolate.run`), 16-byte random salt, **64 MiB, 2 passes, parallelism 1**, 32-byte output. Measured
  on a mid-range Windows laptop, AOT-compiled: 64 MiB × 3 took 870–960 ms (over the 800 ms budget),
  64 MiB × 2 590–630 ms, 48 MiB × 3 650–670 ms, 19 MiB × 2 (OWASP's floor) 170–200 ms.
  `cryptography_flutter` has no native Argon2 on desktop, so this is pure Dart;
- under a key from the **recovery key**: 128 random bits shown as 28 Crockford Base32 characters
  (7 groups of 4; the last 12 bits are a SHA-256 checksum, so a typo is caught before any
  decryption). HKDF-SHA256 is enough to stretch it: it is already high-entropy.

Each wrap is **AES-256-GCM** with a fresh 12-byte nonce. A wrong password is a failed GCM tag. Hive
doesn't check keys, so the boxes are never opened with a key the vault hasn't confirmed. The vault
also keeps the recovery key sealed under the DEK, so it can be shown again after a password check and
so a key read from the keychain can be verified.

**Vault format** (`lock_vault.json`, application-support folder, never in Documents): `format` (1),
`kdf` (`name`, `memoryKiB`, `iterations`, `parallelism`, `length`), `salt`, and three slots —
`password`, `recovery`, `recoveryKey` — each `{nonce, data}` (base64; data is ciphertext + 16-byte
tag), plus `createdAt`. Every slot's GCM associated data is the header (format, KDF name and
parameters, salt) plus the slot's name, so editing a parameter, swapping slots or changing the salt
fails authentication. KDF parameters are bounds-checked on read. The file is written atomically
(temp file + rename). **A valid vault on disk is what "the lock is on" means**; a vault that exists
but can't be read keeps Sotto locked, and only Reset helps.

Changing the password re-wraps the DEK under a new salt; the data and the recovery key stay.
Regenerating the recovery key re-wraps the DEK under the new one, and the old one stops working the
moment the vault is replaced.

**Organize cache keys.** Hive encrypts values, not keys. Record keys are UUIDs (documented, accepted)
except `organize_cache`, keyed by a hash of the text. With the lock on that becomes HMAC-SHA256 under
an HKDF subkey of the DEK (`info = "sotto-organize-cache"`), so a key can't confirm that a guessed
script was organized. The cache starts empty when the lock is turned on or off.

**What is encrypted:** `scripts`, `collections`, `qa_history`, `sessions`, `organize_cache`, `chats`
and `prefs`. `prefs` holds the one setting that is personal text, the forms instructions. While the
lock is off a copy also stays in `settings`, so an older build still finds it. With the lock on that
copy is removed and `settings` is compacted. **`settings` stays plain**: the unlock screen needs the
theme, language and reduced-motion setting first.

**Startup** (`main.dart`):

1. `StoragePaths` (Documents\Sotto for the boxes, application support for the lock files).
2. `LockMigration.recover`, before any box is opened.
3. Only the `settings` box.
4. No vault: the data boxes open and the usual startup runs (seeding, organize reset, pruning, the
   model check, the bridge). Vault: `UnlockApp`, a standalone `MaterialApp` with nothing else
   running.

Unlocking opens the data with the cipher, then runs the same startup steps. A box that won't open
shows `StartupFailure` with Retry on either path.

**Sessions and locking** (`AppSession`). Each unlock is a fresh session: a new `ProviderContainer`
over the opened store (`localStoreProvider`, `appSessionProvider`, `secretStoreProvider`
overridden). Locking:

1. Releases every global hotkey.
2. Shows the unlock screen, so the old widget tree unmounts.
3. Flushes the write buffers.
4. **Disposes the container.** Every StreamProvider, controller and the browser bridge closes through
   its own `onDispose`.
5. Closes the data boxes and zero-fills the DEK (best effort).

No provider needs to know about the lock, and nothing can keep a closed box. While locked there are
no idle hotkeys, no bridge, no auto-fill, no agent, no overlay and no DeepSeek calls, because none of
their providers exist. Unlocking always lands on Home; turning the lock on or off reopens on
Settings → Privacy (`initialLocationProvider`).

**Auto-lock** (`AutoLock`) counts input to Sotto's window: keys, clicks, scrolls and pointer moves.
The count sits above both the main window and the overlay, so going live doesn't restart it. It never
locks while `sessionBusyProvider` is true (a live session or rehearsal, an agent run, a
questionnaire, a fill, an organize job). If the time ran out meanwhile, it locks as soon as that
ends. Choices: Off / 5 / 15 / 30 / 60 min (15 by default).

**Migration** (`LockMigration`), crash-safe:

1. A marker (`lock_migration.json`) says `copy`.
2. Each box is copied into `<name>_migrating` with the new cipher, closed, reopened through that
   cipher and checked: same count, same keys.
3. Turning on: the vault is written as `lock_vault.pending.json`.
4. The marker says `swap`; each original file is deleted and its copy renamed in its place.
5. The pending vault becomes `lock_vault.json` (on), or the vault is deleted (off).
6. The marker goes.

On the next start, a marker at `copy` rolls back (temp boxes and pending vault deleted; the originals
were never touched), and one at `swap` rolls forward (only renames, no key needed). An unreadable
marker stops startup instead of guessing. Turning the lock on twice is refused before anything is
opened.

**Biometrics** (off by default; Windows and macOS through `local_auth`, hidden on Linux and where
Windows Hello / Touch ID isn't set up). `local_auth` only answers yes or no, so turning it on stores
the DEK in the keychain (`SecretKey.appLockKey`, never cached in memory). Anything running as the
user can read it there; the setting says so. Turning it off, turning the lock off and Reset all delete
the entry. A key read from the keychain is verified against the vault before use. The
`local_auth_windows` plugin still builds with `/await`, which MSVC 14.5x rejects:
`windows/CMakeLists.txt` defines `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for that one
target.

**Throttling.** Five wrong attempts are free. Then the next waits 30 s, 1 min, 5 min, 15 min, and 1 h
from then on (`lock_attempts.json`, so quitting doesn't reset it; a clock set back can't stretch the
wait past an hour). Nothing is ever wiped for failing. This is a speed bump for someone at the
keyboard; Argon2id is the real cost of a guess, including for someone who copied the files.

**Reset Sotto** (unlock screen → Forgot password → Reset, with the word typed to confirm) deletes the
data boxes (`prefs` included), the vault, the attempt count, any migration marker and temp boxes, and
the keychain entry. It keeps `settings` and the DeepSeek key.

**Hygiene and limits.** Passwords, keys and the recovery key are never logged and never stored in
`AppSettings`; only the unlock duration is logged, in debug and profile builds. Password fields are
cleared after use. Dart can't guarantee that memory is zeroed: `VaultCrypto.forget` zero-fills the
buffers Sotto owns, but copies made by the crypto library or the garbage collector may survive until
reused. Deleting the plaintext files when turning the lock on isn't a secure erase, and a synced or
backed-up Documents folder may keep old plain versions.

**Test data.** Debug and profile builds take `--dart-define=SOTTO_DATA_ROOT=C:\SottoTest`
(`.vscode/launch.json` → "Sotto (test data)"): the boxes go to `<root>\data`, the lock files to
`<root>\support`, and the lock's keychain entry is named `sotto.dev.appLockKey`. Release builds
ignore it. Speech models stay shared. `--dart-define=SOTTO_AUTOLOCK_SECONDS=20` makes any auto-lock
choice other than Never last 20 seconds instead, for testing (also ignored in release builds).

## macOS notes

**No App Sandbox.** Sotto is distributed outside the App Store, so `macos/Runner/Release.entitlements` and
`DebugProfile.entitlements` don't enable `com.apple.security.app-sandbox`. The sandbox would block exactly
what Forms (manual and auto-fill) and agent mode need: reading other apps' accessibility trees (AX API),
knowing which window is in front, and posting mouse and keyboard events, drags included (CGEvent).
Nothing is open by default — macOS still gates each capability behind the Microphone, Screen Recording
and Accessibility permissions, and every feature that uses them is opt-in.

Debug builds are signed ad hoc, so each rebuild looks like a new app to macOS: if a permission is
switched on but stops working after a rebuild, remove Sotto from the list (**−**) and add it again, or
reset it with `tccutil reset Accessibility app.sotto.sotto` and
`tccutil reset ScreenCapture app.sotto.sotto`.

## Linux notes (experimental)

What a platform can do is described in one place, `lib/core/platform/platform_features.dart`. On Linux
the native channels Sotto has for Windows and macOS (`app.sotto/screen`, `forms`, `input`, `bridge`) don't
exist, so screen reading, form filling, agent mode and the browser bridge are hidden or explained in the
UI, and the matching settings are kept off (`PlatformFeatures.clamp`). Global shortcuts use keybinder
(X11); under Wayland they only work for XWayland windows, and readiness says so. The overlay is
transparent only under a compositing window manager.

## Tests

- `test/domain` — normalizer, aligner and follow rules (advance, hold, relock, backward jumps,
  section skips), including Spanish numbers and a Spanish script read aloud; the sentence splitter,
  ID-based organizing (validation, repair, rebuild, chunking, merge) and a 15,000-word benchmark
  (`flutter test test/domain/organize_test.dart` prints the timings); questionnaire fields, option
  matching, answer mapping and verification over fake UI Automation trees; auto-fill (the watcher only
  starting on real changes, one cycle at a time, the scroll limit, the 1 s hold to stop, A/B/C/D by
  letter and by text, question types, password / payment gates, visual-only options clicked at their
  centre, drags); the overlay's text color (luminance of known pixel grids, the 400 ms debounce, fixed
  colors turn detection off) and geometry; chat history, dictation insertion and streaming Markdown.
- `test/services` — the browser bridge (native messaging framing with partial reads, message schema,
  the extension → accessibility → vision order, host manifests per OS); DeepSeek request shapes (task profiles, JSON mode, vision, tool calls) and a guard
  that speech stays on-device (no cloud STT endpoint, no host but DeepSeek and GitHub).
- `test/integration` — real speech: a sample WAV streamed through the sherpa-onnx worker, driving the
  follow engine. It runs once the light English model is installed (or with `SOTTO_MODEL_DIR`); on
  Linux, point `LD_LIBRARY_PATH` at `build/linux/x64/debug/bundle/lib`.
- `test/widgets` — renders the live answer card with the bundled fonts to `build/answer_card.png`, and
  the questionnaire panel, overlay chat and Chat page at their real sizes; the Forms page in each state
  (recent fills and the history setting), Settings → Forms / Answers, the chat opt-in and auto-close,
  the Stop hold, and the overlay's height following its text. The unlock screen in every state (show /
  hide, Caps Lock, loading, wrong password, shake vs reduced motion, throttled, Windows Hello, forgot
  password, Reset, a damaged vault, Spanish, a small window) and Settings → Privacy → App lock with its
  dialogs.
- `test/core` — a live session started from a maximised window opens the overlay at its saved
  geometry, not the size of the screen. App lock: `AppSession` on a temp folder (turning the lock on
  and off, lock / unlock, restart, throttling across a restart, never locking mid-session, forgot
  password, recovery key shown / regenerated, keychain keys verified, Windows Hello, Reset, a damaged
  vault) and auto-lock with `fake_async`.
- `test/data` — the vault (round trips, wrong password, recovery key, change password, seven kinds of
  tampering, parameters in JSON, the real Argon2 cost once), the recovery key format, throttling with
  `fake_async`, and the migration (plain → encrypted → plain, interrupted in each phase, the forms
  instructions moving between `settings` and `prefs`, HMAC organize-cache keys).
- `test/visual` — opt-in: `SOTTO_RENDER=1 flutter test test/visual` renders every screen (welcome, pre-flight
  and the live overlay included) to PNG. `SOTTO_RENDER_LANG=en|es`, `SOTTO_RENDER_THEME=dark|light`,
  `SOTTO_RENDER_SIZE=1920x1080` and `SOTTO_RENDER_OUT=<folder>`; at 960x600 it doubles as an overflow check.
  `unlock_render_test.dart` and `app_lock_render_test.dart` render the unlock screen and the App lock
  settings in both languages and themes (to `build/unlock` and `build/app_lock`).

## Known limitations

- **Meeting chat.** "Send to chat" copies the answer to the clipboard for you to paste. Posting
  directly to Zoom/Teams needs their OAuth apps, which conflicts with running without a backend.
- **The browser extension is optional.** Without it — or on a page it can't read (browser pages, the
  extension stores, a site you haven't allowed) — web forms are read from accessibility and the screen.
- **Auto-fill sends screenshots.** Each new page it fills sends a screenshot of the window in front to
  DeepSeek (never saved). It only runs while you have it on, and never on Sotto's own windows.
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
- The macOS ScreenCaptureKit, AX and CGEvent code is compiled in CI but has not been run on a Mac by
  the maintainer yet.
- Linux is experimental: see [Linux notes](#linux-notes-experimental).

Typefaces: Geist, Geist Mono and Atkinson Hyperlegible Next, bundled under the SIL Open Font License
(see `assets/fonts/`).
