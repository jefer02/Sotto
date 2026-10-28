# Changelog

All notable changes to Sotto are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

The release workflow copies the section whose heading matches the tag (`v1.0.0` → `## [1.0.0]`)
into the GitHub release notes.

## [Unreleased]

## [1.1.0] - 2026-10-27

### Added

- **App lock** (Settings → Privacy, off by default). A password encrypts your scripts, collections,
  sessions, Q&A history, chats and forms instructions on this computer (AES-256, key derived with
  Argon2id). Still no account: nothing leaves your computer.
  - An unlock screen in your theme and language, with show/hide, a Caps Lock hint and a countdown
    after repeated wrong passwords.
  - A **recovery key**, shown once and again on request, to set a new password if you forget it.
    You can also make a new one, which retires the old one.
  - **Lock now** from the sidebar, Settings or Ctrl+Alt+K / ⌃⌥K (rebindable), and **auto-lock**
    after 5–60 minutes without input. It never locks during a talk, rehearsal, agent run or fill.
  - Optional **Windows Hello / Touch ID** unlock.
  - **Reset Sotto** for when both the password and the recovery key are lost. The data can't be
    recovered without one of them.
- Development: `--dart-define=SOTTO_DATA_ROOT=<folder>` (and the "Sotto (test data)" launch
  configuration) runs debug and profile builds on separate data.

### Changed

- The forms instructions are now kept with your data rather than with the settings. A copy stays in
  the settings while the lock is off, so older versions still find them.

## [1.0.0] - 2026-10-10

First public release.

### Added

- **Teleprompter overlay** that keeps your script under the camera: text-only or panel style,
  automatic text color over light and dark slides, hidden from screen sharing on Windows and macOS.
- **Voice following** on this computer (sherpa-onnx): the overlay follows you line by line, holds
  still while you ad-lib and gives your hotkeys priority. English streaming model; Spanish and
  other languages through Whisper.
- **Script library**: import `.docx`, `.pdf`, `.md` and `.txt`, or paste text. Scripts are
  organized into sections, sentences and stage cues in seconds, and refined by DeepSeek without
  changing your words.
- **Live answers**: press a shortcut when the audience asks a question and DeepSeek drafts an
  answer from your script and prep documents.
- **Rehearsals and sessions** with per-section timing, so your pace estimate gets better.
- **Chat**, **screen awareness**, **form filling** and **agent mode** (all opt-in).
- **Sotto Bridge** browser extension for Chrome, Edge and Firefox, so form filling can read web
  forms precisely.
- English and Spanish interface.
- A DeepSeek key built into release builds, so AI features work out of the box. You can add your
  own key in Settings → Integrations; it takes priority.

### Platforms

- **Windows 10/11** and **macOS 12+**: full feature set. Builds are not code-signed yet (see the
  README for the SmartScreen and Gatekeeper steps).
- **Linux (experimental)**: library, editor, voice following, the overlay, DeepSeek answers, chat
  and sessions. Screen reading, form filling, agent mode, the browser extension, reading answers
  aloud and hiding the overlay from screen sharing are not available yet. Global shortcuts need an
  X11 session.
