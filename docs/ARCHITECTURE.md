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
questionnaires and agent mode at low effort; generating a script off for reading slides (`digest`)
and high for writing the script (`generate`). Multi-turn requests with thinking on send each
`reasoning_content` back, as the API requires.

## New script: write, import or generate

*New script* (the library's button, `Ctrl+N` / `⌘N`) opens one dialog with three paths, each labelled
by what it does with wording — **Keeps your words** or **Writes new text**
(`lib/features/library/new_script_dialog.dart`):

1. **Write from scratch** — a blank script, as before.
2. **Import text** — a file (drop or pick: `.docx`, `.pdf`, `.md`, `.txt`) or pasted text, kept word
   for word and organized as above (`importFiles` / `importText`).
3. **Generate with AI** — from presentations, PDFs, documents or pictures. The form lists every file
   with what was read from it ("12 slides · 1 hidden slide skipped · notes on 9 slides · 1,240 words ·
   OCR on 2 scanned pages", or why it couldn't be read), the duration — the word budget is minutes ×
   the presenter's pace (the mean of their rehearsals in `AppSettings.paceSamples`, else Settings'
   148 wpm) — audience and tone (free text plus quick chips), the language (default: the speech
   language), and *Use speaker notes*, *One section per slide* and *Also prepare likely questions*.
   A notice that the files' text goes to DeepSeek is on screen before *Generate*; without a key the
   path says it needs one and links to Settings › Integrations. While it runs, each stage shows its
   progress and the script streams into a preview; *Cancel* closes the request at once and saves
   nothing. The result opens in the editor as a **draft**, titled from the material (its first
   slide's title, else the file name), with `targetSeconds` set and the likely questions in Q&A prep.

**Extraction** (`lib/data/import/`) — everything on this computer and off the UI thread, into one model,
`SourceMaterial` → `SourceUnit` {number, title, body lines with outline levels, speaker notes, OCR text,
alt text} (`source_material.dart`):

- **.pptx** (`presentation_parser.dart`, on `Isolate.run`): slide order comes from
  `ppt/presentation.xml` (`p:sldIdLst`) resolved through its `.rels` — never from part names, which
  reordering slides doesn't change. Text from `a:t` runs, paragraph by paragraph with `a:pPr@lvl`;
  titles from `title` / `ctrTitle` placeholders; slide number, date, header and footer placeholders
  skipped; table rows as "a | b | c"; pictures' `descr` as alt text; speaker notes from the notes
  slide's body placeholder. Hidden slides (`show="0"`) are skipped and reported; numbers stay the
  deck's (hidden ones count, as in PowerPoint), so cues match the slides on screen.
- **.odp**: `draw:page`s in order; title frames by `presentation:class`, list depth as the level,
  `svg:desc` / `svg:title` of images, the notes page; hidden pages (page or page-style
  `presentation:visibility="hidden"`) skipped and reported.
- **.pdf**: pdfrx's text layer per page (PDFium on its worker isolate); a page with fewer than 24
  letters is treated as scanned — rendered to 2,000 px and read by the system OCR
  (Windows.Media.Ocr / macOS Vision) through a new `ocrImage` call on `app.sotto/screen`
  (`SottoRecognizeBgra` in `windows/runner/native/screen_capture.cpp`, `recognizeImage` in
  `MainFlutterWindow.swift`). Wrapped lines rejoin; a short unpunctuated first line is the title.
- **.docx / .md / .txt**: the importer's text, cut at headings, bullets keeping their indentation.
- **.png / .jpg**: decoded on `Isolate.run` (`image`), then OCR.
- **Unsupported**: `.key`, `.ppt`, `.pps`, `.doc`, `.pages`… say to export as PowerPoint (.pptx) or
  PDF; old binary or password-protected Office files (OLE compound) say to save them again.
- **Limits** (`ReadLimits`): files up to 100 MB and 300 slides or pages; archives up to 10,000
  entries, each XML part up to 16 MB and 96 MB in all, uncompressed — checked against the central
  directory before anything is inflated, and the archive package never inflates an entry past its
  declared size, so a zip bomb stops there; pictures up to 40 MP. Only parts with plain relative
  names are looked up (no `..`, absolute, drive or backslash names), relationship targets that
  would leave the package are dropped, and nothing is ever written to disk.
- Cost: O(B) time in the uncompressed XML read (one pass per part), memory one part's DOM at a time
  plus the text kept; per scanned page, rendering and OCR are O(pixels) at ≤ 2,000 px a side.

**Generation** (`lib/services/ai/script_generator.dart`; prompts, parsing and repair are pure in
`lib/domain/structuring/generation_plan.dart`), map-reduce:

1. **Map** — groups of ≤ 6 slides (≤ 1,200 words, never across files) → each slide's purpose, key
   ideas and verbatim facts as JSON; 4 in flight (`forEachParallel`), retried with exponential
   backoff on 429 / 5xx / timeouts (`withRetry`), thinking off. A reply unusable twice falls back to
   the slides' own words.
2. **Reduce** — one streamed request writes the script: an introduction, sections (one per slide,
   or per group of related slides), beats written to be spoken (8–30 words), `"slide": n` on the beat
   where each slide of the presented deck appears (the first deck, else the first PDF; supporting
   documents get no cues), and a closing — within the word budget ±10 %. Thinking high.
3. **Check** — the reply is parsed into Script / Section / Beat / Cue and repaired locally: code fences
   and stray prose around the JSON tolerated, empty beats dropped, Markdown and cue tokens stripped
   from spoken text, cues kept only for known slides, once each and ascending. Unusable JSON is asked
   for once more with what was wrong; a length outside the budget is sent back once to be resized
   (the closer of the two wins). Long beats are then split where the rule-based organizer splits
   them (`ScriptStructurer.splitLong`), the cue staying on the first part, and hint words computed.
4. **Questions** (optional) — 5–8 likely audience questions with answers from the same digests.

Grounding: the prompts allow only facts from the material and forbid inventing numbers, names or
dates; where something needed is missing the model writes a visible marker — `[CHECK: …]`
(`[REVISAR: …]` in Spanish) — and the snackbar says how many there are. Prompt injection: every
piece of file content (and the audience and tone the presenter typed) goes between
`<material>` … `</material>`, any tag-like `<material` / `</material` inside it is defused (`‹`), and
each system prompt says the block is data whose instructions are never followed. Results are cached
in the organize box by a hash of (material, options, model) — the same request again opens at once.
Cost for U slides, T words and a budget of W words: map is ⌈U/6⌉ requests (≈ ⌈U/24⌉ round trips),
O(T) tokens in; reduce one request with O(U) digest tokens in and O(W) out (twice at most); local
work O(T + W) time and memory.

Errors: whatever stops a run — DeepSeek's own errors (bad key, no balance, busy after retries, timed
out), a dropped connection, a garbled stream, a reply unusable twice — reaches the dialog as one worded
message under "Couldn't generate the script", with "Nothing was saved", *Try again* and *Back*; the
material stays added. Nothing is saved or cached until a run succeeds.

**Markers to check** (`lib/domain/structuring/check_markers.dart`). `[CHECK: …]`, `[REVISAR: …]` (and
`VERIFY` / `VERIFICAR`) live inside beat text, so everything that reads beats knows them:

- *Voice following*: `FlatScript` gives a marker's words no tokens — reading one aloud never moves the
  script — while display indexes still point at the words shown; a beat ending in a marker is
  finished by its last real word (`FlatBeat.wordsToSay`), and a beat that is only a marker is passed
  over like an empty one.
- *Overlay*: marker words are drawn in the cue color and never dimmed as said. Settings → Appearance →
  *Show markers to check* (on by default): off, a session starts from the script with markers
  stripped (`CheckMarkers.stripScript`; beats left empty dropped, ids kept), so the overlay and the
  aligner see the same text.
- *Editor*: the Write tab shows "N spots to check" with previous / next (across sections, wrapping);
  each marker opens selected, so typing replaces it, or *Remove marker* takes it out with its spacing
  tidied. `/script/<id>?marker=<n>` opens on marker n.
- *Pre-flight*: a non-blocking warning, "Spots to check", with how many are left, whether they show
  live, and *Open the first*; shown at once, before the other checks load.

**Debug logs** (debug builds only, `debugPrint`): `material:` per file — kind, units, hidden slides,
words, notes, OCR'd pages and time — and per OCR call (`OCR <file> page n: w x h px, chars recognized,
ms`, after "no text layer, rendered in … ms"); `generate:` the input size and budget, each map group's
time, then per stage (map, write, resize, questions) its time and DeepSeek's token counts (prompt,
prefix-cache hits, completion, thinking — asked for with `stream_options.include_usage` only while
generating), local repairs and fallbacks, and the stage a failure or cancel happened in.

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
  app/            App root, go_router routes, global shortcuts
  core/
    design/       Design tokens (tokens.dart), typography, theme, 48 icons from the design
    widgets/      Component library: buttons, keycaps, controls, chips, settings rows, chrome
    platform/     WindowService (main window ⇄ overlay), HotkeyService, key labels
  data/
    models/       Script → Section → Beat (+Cue), settings, Q&A entries, sessions (hand-written JSON)
    storage/      Hive CE boxes (LocalStore), API keys in the OS keychain (SecretStore)
    import/       .txt / .md / .docx (OOXML) / .pdf (PDFium) → text; presentations, PDFs, documents
                  and pictures → SourceMaterial for generating (.pptx, .odp, OCR, safe archives)
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
                  validation / repair, local rebuild, progressive merge; generation prompts,
                  reply parsing and repair
  services/
    speech/       Mic capture (record), sherpa-onnx worker isolate (offset streaming decoders), Whisper, VAD,
                  pinned models, dictation
    system_fonts  Installed font families, read from font files' name tables
    ai/           DeepSeek client (SSE, tool calls, task profiles), organizer, script generator,
                  answers, chat, questionnaires, agent model
    screen/       On-demand screenshots (Windows.Graphics.Capture / ScreenCaptureKit) and form
                  access (UI Automation / AX)
    agent/        Native input (SendInput + UI Automation) and the real agent executor
    tts/          Read aloud (flutter_tts)
  features/
    library/      Home, script lists, sessions, import (drop / paste / browse), the New script
                  dialog and its generate controller, readiness
    editor/       Script workspace: Write, Q&A prep, Rehearsals, live overlay preview
    preflight/    Go-live checks
    settings/     Shortcuts, Appearance, Voice & following, Answers, General, Integrations, Privacy:
                  one centered column (≤ 720 px); Voice and Appearance keep their live panel
                  (mic test and pace, overlay preview) beside it, in view while the column scrolls
                  (Sessions and Forms center their lists at 880 px, `Layout.readableMax`)
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
brightness above one half gives near-black text; below, near-white text (the text starts light until the
first reading). The outline and shadow are always the opposite color — a light outline and soft glow
around dark text, a dark outline and soft shadow around light text — thin (60 % of *Outline width*) and
slightly soft, so they hold the letters' edges over a chart or a photo and disappear into a plain slide.
*Always light* and *Always dark* use the same contrasting outline; *Custom* uses your own colors. A
change is kept only when a second sample 400 ms later agrees, so slide transitions don't flicker, and it
crossfades over 200 ms (at once with *Reduce motion*). It is pixel math on this computer — nothing is
encoded, saved or sent, and no AI is involved. On macOS it needs Screen Recording; without it the text
keeps its color.

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

**Speech models.** Downloaded once from the sherpa-onnx `asr-models` release on GitHub; each archive's
size and SHA-256 are pinned in `ModelCatalog` and checked while it streams in — a mismatch is discarded
before anything is extracted. Which model follows is one decision, `planFollowing`, shared by a live
session and Settings → Voice & following ("Follows with", and why):

| Spoken language | Follows with | Notes |
|---|---|---|
| English | streaming zipformer (2023-06-26, or the light 20M) | 0.32 s chunks: words ~0.25 s after they end |
| Spanish, French, German | Kroko streaming zipformer (2025-08-06) | 1.28 s chunks; four offset decoders (below) |
| others | Whisper Base, segmented | a phrase at a time, after each pause |

Whisper (Turbo, else Base) still transcribes questions and dictation, where a whole transcript matters
more than latency. If a language's streaming model isn't installed, Whisper follows meanwhile and the
session says which download follows word by word. Kroko models are Banafo's community models
(huggingface.co/Banafo/Kroko-ASR), licensed **CC BY-SA — the publisher does not state which version**;
Settings shows the license, attribution and source link before the download starts. Measured on the
same 15-beat talk (TTS): Kroko 0–2 % word errors (es, fr, de, en); for English, Kroko was more accurate
than the shipped model (2.0 % vs 5.4 %) but ~3× slower to emit a word (0.69 s vs 0.24 s), so English
keeps its model.

**Voice following.** 16 kHz mic audio (Media Foundation delivers ~10 ms chunks) goes straight to
sherpa-onnx in a background isolate — no voice-activity gate on the streaming path — so inference
never touches the 120 Hz UI thread. The Kroko encoder takes exactly 141 feature frames
(`decode_chunk_len` 128 in its ONNX metadata; the input shape is static), so one decoder emits words
every 1.28 s, about 1 s after they end. `OffsetStreams` runs four decoders on the same audio, each a
quarter chunk after the one before, and merges their words on when each began (`MergedWords`): words
come every ~0.3 s. Each decoder costs ≈ 0.1 s of CPU (two threads, int8) per chunk; if decoding takes
more than half of real time, it drops to two streams, then one. Endpoint detection is off (a reset would
put the streams back in step); in long silences they reset one after another, still staggered. A word is
final once the next word has begun, or once 0.35 s of decoded audio follows its last piece (greedy
search only appends; replayed over ~400 words, no word called final ever changed). The open last word is
offered as *tentative* (`HeardUpdate.tentative`).

Latency by stage on long.wav (`test/integration/latency_stages_test.dart`, real time, real worker):

| Stage | One decoder, finals only | Four offset decoders, tentative words |
|---|---|---|
| audio chunk delivered after the word ends | 0.05 s | 0.05 s |
| decoder emits the word | 0.92 s (p90 1.42) | 0.51 s (p90 0.77) |
| emitted → shown | 0.28 s (p90 1.30) | 0.00 s |
| worker: decode + message | 0.02 s | 0.02 s |
| update → FollowEngine moves | 0.14 s | 0.15 s |
| **word ends → following moved past it** | **1.37 s** (p90 2.27) | **0.68 s** (p90 0.98) |
| position update → frame built (profile bench) | — | 4.6 ms (p90 9.3) |

The model's own look-ahead sets a floor near 0.4 s. Segmented Whisper re-reads the open utterance every
0.7 s (`SegmentedRecognizer.followingRefresh`). `FollowEngine` tracks a *word*, not a beat:

- only stable words count — committed ones, the partial words a streaming recognizer calls final, and
  for Whisper the partial words a second update agrees with (matched by longest common subsequence, so a
  word Whisper slips in front doesn't reset the rest); a word that is later rewritten never moves the
  engine
- open words show at once when, in order, they are exactly the script's next words and the presenter is
  reading along; final words confirm them, a revision takes the display back — what shows is always a
  word heard, never ahead of the voice
- only new words count: an update moves the script only when its alignment ends on words not used
  before, so silence, noise, caption hallucinations and ad-libs leave it where it is
- small steps are easy: two matched words in a row, or one exact rare word right next to the
  presenter while reading; the stretch skipped before a matched run is at most the run's own length
- big moves are earned: a far or backward move needs ≥ 5 matched words (weight ≥ 3, more the further
  it goes), a match ~1.4× better than anywhere else in the script, and a second update that carries on
  from it
- the aligner (Smith–Waterman over normalized, phonetically keyed tokens; Spanish b/v, ll/y, silent h,
  al/a, del/de, punto/coma) weights rare words up to 1, repeated ones towards 0.5, stop words 0.3;
  O(n·m) per alignment with n ≤ 16 heard words over a ~50-word band, the whole script only when the
  band finds nothing
- "Move on when said" only decides when the next line shows as current; the position (`saidBeat`,
  `saidWords`) never skips a line's unsaid end
- hold still after 6 s without script words; manual keys win, discard what was heard before them, and
  "previous beat" pauses following for 3 s
- the speaking rate (characters a second) is measured from when each word began, for the overlay

The overlay keeps a continuous reading cursor (`ReadingCursor`, in characters): it walks to the end of
the last word said at the measured pace — faster when behind, always arriving within 0.9 s — and never
passes it; hotkeys and relocks place it at once. The column scrolls by translating one pre-laid-out
column (`ScriptScroll`, a critically damped spring on one ticker) to keep the cursor's letters on the
eye-line, so the text creeps up as you speak. Under reduced motion it glides slower and calmer — the
script's movement is content, so it is never instant. Each shown line sits on its own repaint layer:
text-only glyphs carry a 13-shadow outline, and re-drawing the whole column for one changing line cost
100–200 ms a frame. `test/domain/following_metrics_test.dart` replays recorded output of both paths
(`test/fixtures/speech_es/asr_whisper_base_700ms.json`, `asr_kroko_es.json`, recorded by
`test/integration/record_asr_es_test.dart`; `long.wav` has word-level truth from `generate_long.py`)
beside a frozen copy of the previous rules and prints the numbers; logs per update go to
`build/following_harness/`. On the same audio, Whisper with the previous rules → streaming with the
current ones: latency 1.5–1.8 s → 0.6–0.8 s, words per move 2.5–3.7 → 1.3–2.0, lag p90 4.1–5.6 →
2.4–4.0 words, false advances 0 → 0, relock 4.3–4.7 s → 2.6–3.4 s.

**Highlight effect** (Appearance → Highlight effect: Off / Simple / Glow + sparkles). `KaraokeLine` puts
one `CustomPainter` with its own ticker on its own repaint layer under (dark text) or over (light text,
added with `BlendMode.plus`) the line being said. The glow is the same text — thickened, blurred and
tinted cold blue-white — clipped to the letters at the cursor by a moving gradient mask (opaque at the
head, eased off over ~1.8 letters behind, rolling off ~1 letter ahead), in one `saveLayer` bounded to
those letters; the line keeps its color. Sparkles rise from a fixed pool of 60 (flat arrays, no
allocation per frame). Per frame O(s + p): s ≤ 2 line pieces under the mask, p ≤ 60 sparkles; space is
the pool plus three laid-out copies of the line. Reduced motion: a still glow on the word last said, no
sweep, no sparkles, no ticker. Tokens live in `Karaoke` (`lib/core/design/tokens.dart`). Profile bench
(`tool/karaoke_bench.dart`, recognition running): build p50 0.5 ms, raster p50 5 / p90 8.6 ms, ~1 frame
in 5 s over 16 ms (a line becoming current).

**Script fonts** (Appearance → Script font, overlay and editor apart). Bundled, all SIL OFL 1.1: Atkinson
Hyperlegible Next (default), Geist, Cormorant (the highlight's suggested serif, drawn 14 % larger for
its small x-height), Source Sans 3, Lexend, Geist Mono — or any installed font, found by reading each
font file's `name` table (Windows, macOS) or fontconfig (Linux). A choice is family, source, weight
(clamped to the font's axis) and letter spacing in ems, in `AppSettings` (settings saved before default
to the fonts as they were). It reaches text through `ReadingType.live` / `editorIn`; the line cache keys
on the resolved style. A system font that is no longer installed falls back to the default, and until
the scan is done the default is the drawing fallback.

**Organizing pasted text.** Every way text comes in is organized at once — files (picked or dropped),
the clipboard (Ctrl+V in the library, the welcome dialog), and a paste of several sentences into a
beat in the Write tab (`PastedText.detect`, 250 ms debounce; typing never triggers it). The rule-based
pass runs on a background isolate, then DeepSeek refines in the background with the usual progress
bar; without a key the rule-based pass alone, with no error. A paste into a script with content goes in
at the paste (`PastePlacement`); "Undo" puts the pasted text back as it was, one step.

**Answers.** An offline BM25 ranking picks script sections and prep-document excerpts. Only the
question and those excerpts are sent. Q&A-prep answers that match are shown instantly with no model
call. Responses stream in a line protocol, so the headline appears first and the points follow.
Live answers run with DeepSeek's thinking mode off for latency; `reasoning_content` from thinking
models is ignored.

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

- `test/domain` — normalizer, aligner and follow rules (stable partials, tentative open words,
  off-script speech and noise, repeated phrases, sustained relocks, backward jumps, manual keys), on
  recorded Whisper and streaming output and
  hand-built sequences, including Spanish numbers and a Spanish script read aloud; the sentence splitter,
  ID-based organizing (validation, repair, rebuild, chunking, merge) and a 15,000-word benchmark
  (`flutter test test/domain/organize_test.dart` prints the timings); questionnaire fields, option
  matching, answer mapping and verification over fake UI Automation trees; auto-fill (the watcher only
  starting on real changes, one cycle at a time, the scroll limit, the 1 s hold to stop, A/B/C/D by
  letter and by text, question types, password / payment gates, visual-only options clicked at their
  centre, drags); the overlay's text color (luminance of known pixel grids, the 400 ms debounce, fixed
  colors turn detection off) and geometry; chat history, dictation insertion and streaming Markdown.
- `test/data` — reading material for generation: a .pptx whose slide parts are named out of order,
  speaker notes, a hidden slide, nested bullets, a picture-only slide (alt text), corrupted and old
  binary files, a part over the size limit (a small zip bomb), relationship paths that would leave
  the package; .odp; documents; a PDF with a text page and a scanned page (PDFium and OCR behind
  fakes); pictures; unsupported formats' messages (`material_reader_test.dart`, fixtures built in
  `test/fixtures/materials/pptx_builder.dart`).
- `test/domain/check_markers_test.dart` — markers to check: found in both languages, stripped and
  removed tidily, the overlay's marker words; following skips them, a beat ending in one finishes, a
  marker-only beat is passed over, in English and Spanish.
- `test/services` — generating a script with a fake DeepSeek (`script_generator_test.dart`): the
  word budget, every slide cued once and in order (hidden slides never), an off-budget script resized,
  unusable JSON asked for again and a usable one repaired, backoff on 5xx but not on a bad key, every
  kind of failure (no balance, bad key, dropped connection, offline, garbled stream) worded,
  cancelling mid-stream saving and caching nothing, the cache, and instructions inside slide text
  staying inside the data block; the browser bridge (native messaging framing with partial reads, message schema,
  the extension → accessibility → vision order, host manifests per OS); DeepSeek request shapes (task profiles, JSON mode, vision, tool calls) and a guard
  that speech stays on-device (no cloud STT endpoint, no host but DeepSeek and GitHub); pinned model
  checksums (a tampered or truncated archive is never extracted), which model follows each language,
  streaming words' finality and the merge of offset decoders.
- `test/integration` — real speech: sample WAVs streamed through the sherpa-onnx worker in real time,
  driving the follow engine (English, and Spanish with the streaming model and with Whisper). Each runs
  once its model is installed (`SOTTO_MODELS_ROOT` adds folders); on Linux, point `LD_LIBRARY_PATH` at
  `build/linux/x64/debug/bundle/lib`. Opt-in: `SOTTO_RECORD_ASR=1` records both Spanish paths for the
  metrics, `SOTTO_LATENCY=1` measures latency by stage. They hold on a loaded machine without hiding
  slowness (`native_speech.dart`): after playback they wait until the recognizer has gone quiet — a
  window of 1.5 s or twice the 90th-percentile gap between its updates, scaled by how far playback
  fell behind real time — instead of a fixed sleep; the presenter's position is judged at the audio the
  recognizer had processed (`HeardUpdate.clock`, or the audio fed), not the wall clock; and speed is
  checked on its own: the work left after the audio ends must stay under a quarter of the audio's
  length (half for Whisper) plus 2 s. `drain_test.dart` checks with fake decoders that one keeping up
  passes and one at half real-time speed fails. Each run prints the wall/audio ratio, feeder lateness,
  update gaps and backlog.
- `test/widgets` — renders the live answer card with the bundled fonts to `build/answer_card.png`, and
  the questionnaire panel, overlay chat and Chat page at their real sizes; the Forms page in each state
  (recent fills and the history setting), Settings → Forms / Answers, the chat opt-in and auto-close,
  the Stop hold, and the overlay's height following its text; the hover controls never covering the
  current or next line in any layout (960×600 and small overlays, controls above or below); the library
  at 960×600 in both languages; the karaoke highlight (never ahead of what was said, no ticker under
  reduced motion, the sparkle cap); a model's license shown before its download; the line cache
  following a script font change; every Settings page at 960×600, 1280×800, 1600×1000 and 1920×1080
  in both languages — one centered column at most 720 px, or a side panel that stays in view (at
  least 40 % of the view, or all of itself) at every scroll position (`settings_columns_test.dart`);
  the New script dialog: its three paths and their labels, pasted text kept as is, the missing-key
  explanation, the privacy notice before anything is sent, and a generated draft saved
  (`new_script_dialog_test.dart`), and a DeepSeek error worded in the dialog with nothing saved; markers
  in the editor — counted, walked through across sections selected, removed or typed over, opened by
  number — and pre-flight's non-blocking warning and *Open the first* (`check_markers_ui_test.dart`).
- `test/core` — a live session started from a maximised window opens the overlay at its saved
  geometry, not the size of the screen.
- `test/visual` — opt-in: `SOTTO_RENDER=1 flutter test test/visual` renders every screen (welcome, pre-flight
  and the live overlay included) to PNG. `SOTTO_RENDER_LANG=en|es`, `SOTTO_RENDER_THEME=dark|light`,
  `SOTTO_RENDER_SIZE=1920x1080` and `SOTTO_RENDER_OUT=<folder>`; at 960x600 it doubles as an overflow check.
  `test/visual/karaoke_render_test.dart` renders the highlight mid-sweep over a sky, a dark scene and a
  light slide. `test/visual/settings_render_test.dart` renders every Settings page at the top and
  scrolled to the end, in both languages, at 960×600, 1280×800, 1600×1000 and 1920×1080
  (`build/settings`).

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
- **Live following** uses streaming models for English, Spanish, French and German. Spanish (Kroko)
  shows a word ~0.7 s after it ends — its fixed 1.28 s chunk sets a floor near 0.4 s even with four
  offset decoders. Other languages follow via Whisper, a phrase at a time.
- **Text-only outline cost.** Text-only glyphs carry a 13-shadow outline; with Highlight off, each word's
  dimming re-rasterizes the current line through it, so frames run over budget while words dim on slower
  GPUs.
- **The Kroko license version is unstated** by its publisher (CC BY-SA, version not given).
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

Typefaces: Geist, Geist Mono, Atkinson Hyperlegible Next, Cormorant, Source Sans 3 and Lexend, bundled under the SIL Open Font License
(see `assets/fonts/`).
