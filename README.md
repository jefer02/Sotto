# Sotto

*The voice in the wings.* Sotto is a live presentation assistant for your desktop. It keeps your
script in a small overlay just under the camera, follows your voice line by line, and drafts an
answer when the audience asks a question, so you can look at the room, not at your notes.

- **Teleprompter overlay.** A floating, always-on-top window that shows the line you're saying and
  the next ones. Its text stays readable over dark slides, white slides and video calls. On Windows
  and macOS it is hidden from screen sharing.
- **Follows your voice.** Speech recognition runs on your computer (sherpa-onnx): the overlay moves
  as you speak, holds still while you ad-lib, and your shortcuts always win.
- **Answers questions.** Press a shortcut, let the audience member speak, and DeepSeek drafts an
  answer from your script and prep documents.
- **Scripts in seconds.** Drop a `.docx`, `.pdf`, `.md` or `.txt` file, or paste text. Sotto splits it
  into sections, sentences and stage cues without changing your words.
- **Rehearse.** Rehearsals and live sessions keep per-section timing, so your pace estimate gets
  more accurate each time.
- **Optional extras**, off until you turn them on: chat, answers about what's on screen, form
  filling with the Sotto Bridge browser extension, and agent mode.
- English and Spanish interface. No account and no backend: your scripts stay on your computer.

## Platforms

| Platform | Status | Notes |
|---|---|---|
| **Windows 10 / 11** (x64) | Full | Not code-signed yet: SmartScreen warns on first launch. |
| **macOS 12+** (Apple silicon and Intel) | Full | Not notarized yet: see the Gatekeeper steps below. |
| **Linux** (x64) | Experimental | Reduced feature set, X11 recommended. See [Linux](#linux-experimental). |

## Download and install

Get the latest version from the [Releases](../../releases) page. Each file has a SHA-256 checksum
in `SHA256SUMS.txt`.

### Windows

- **Installer:** `Sotto-<version>-windows-x64-setup.exe` adds Sotto to the Start menu and comes with an
  uninstaller. No administrator rights needed.
- **Portable:** `Sotto-<version>-windows-x64.zip`. Unzip it anywhere and run `sotto.exe`. The Visual
  C++ runtime is included.

Because the app isn't code-signed yet, **Windows SmartScreen** may say "Windows protected your PC".
Choose **More info → Run anyway**. You only need to do this once per version.

### macOS

1. Open `Sotto-<version>-macos.dmg` and drag **Sotto** to **Applications**.
2. The app is ad-hoc signed but not notarized, so Gatekeeper blocks the first launch. Either
   right-click Sotto in Applications → **Open** → **Open**, or run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Sotto.app
   ```

3. Grant the permissions Sotto asks for (System Settings → Privacy & Security):

| Permission | Needed for | When it's asked |
|---|---|---|
| **Microphone** | Following your voice, capturing questions, chat dictation | First live session or first dictation |
| **Screen Recording** | Answers about the screen, "Attach screen" in chat, form filling, automatic overlay text color | When you first use one of them |
| **Accessibility** | Form filling and agent mode (reading forms, clicking and typing) | When you turn either on |

macOS applies Screen Recording only after you quit and reopen Sotto. Pre-flight (the check before
going live) shows anything that's still missing.

### Linux (experimental)

- **tar.gz:** extract `Sotto-<version>-linux-x64.tar.gz` and run `./sotto` inside the folder.
- **AppImage** (if attached to the release): `chmod +x Sotto-<version>-x86_64.AppImage` and run it.

System packages (Debian/Ubuntu names):

```sh
sudo apt install libgtk-3-0 libsecret-1-0 gnome-keyring libkeybinder-3.0-0 pulseaudio-utils xdg-desktop-portal
```

`libsecret` and a keyring store your own DeepSeek key. `pulseaudio-utils` (`parecord`, which also
works on PipeWire with `pipewire-pulse`) captures the microphone. `keybinder` registers global
shortcuts, and `xdg-desktop-portal` opens file pickers.

**Works on Linux:** the library and import, the editor, voice following, the teleprompter overlay,
DeepSeek answers, chat, rehearsals and sessions.

**Not available yet:** answers about the screen, form filling, agent mode, the browser extension,
reading answers aloud, and hiding the overlay from screen sharing (share a window, not the whole
screen). The app shows these as "Not available on Linux yet" instead of failing.

**X11 vs Wayland.** Use an X11 session ("Ubuntu on Xorg" on the login screen) for the full
experience. Wayland doesn't let apps register global shortcuts or keep a window above others, so on
Wayland the shortcuts don't fire (the readiness card says so) and the overlay may not stay on top.
The overlay's buttons still work. A transparent overlay needs a compositing window manager.

## First launch

1. **Voice models.** The welcome dialog offers the on-device speech models (Settings → Voice &
   following → On-device models): *English · streaming* to follow your voice and *Whisper base* for
   questions and other languages. They're downloaded once from the sherpa-onnx releases on GitHub
   and work offline afterwards.
2. **A script.** Write one, paste one, or drop a file onto the window.
3. **Go live** with `Ctrl+Alt+L` (`⌃⌥L` on a Mac), or rehearse first. All shortcuts are listed and
   can be changed in Settings → Shortcuts.

Without voice models, the overlay still works with the shortcuts and a timed advance.

## AI features and your DeepSeek key

Organizing scripts, answering questions, chat, form filling and agent mode use
[DeepSeek](https://platform.deepseek.com). **Release builds include a key, so these work out of
the box.**

You can use your **own key** instead. This is optional, but it gives you your own account and
limits:

1. Create a key at [platform.deepseek.com/api_keys](https://platform.deepseek.com/api_keys).
2. Paste it in **Settings → Integrations → API key** and press **Test**.

Your key is stored in the system keychain (Windows Credential Manager, macOS Keychain, or the Secret
Service on Linux) and takes priority over the built-in key. If the built-in key stops working, Sotto
says so and points you to Settings → Integrations. Voice following and the overlay never need a
key.

## Privacy

**Stays on your computer:**

- Your scripts, prep documents, sessions, rehearsals, answers history, chats and settings, in a local
  database.
- Your voice. Speech recognition runs on your computer and audio is never uploaded.
- Your own DeepSeek key, in the system keychain.
- Screenshots. They're held in memory for a single request and never written to disk.
- Sotto has no account, no analytics and no server of its own.

**Sent to DeepSeek**, only when you use a feature that needs it:

- **Answers:** the question and the script and prep excerpts used to answer it.
- **Organizing an imported script:** its numbered sentences. DeepSeek only returns where sections
  begin and end.
- **Chat:** your messages, plus your script or a screenshot only if you attach them.
- **Opt-in features:**
  - Screen awareness: one screenshot when you press the shortcut.
  - Form filling: a screenshot and the list of fields. Password and payment fields are never read
    or sent.
  - Agent mode: screenshots while it works.

**Downloaded:** the speech models, once, from GitHub.

Settings → Privacy controls how long history is kept and can delete all local data. DeepSeek's own
policy applies to what it receives.

### App lock (optional)

Settings → Privacy → **App lock** puts a password on Sotto. It's off by default, and Sotto still has
no account: the password never leaves your computer.

**When it's on, it protects** your scripts, collections, sessions and rehearsals, Q&A history, chats
and forms instructions *at rest*. They're encrypted on disk (AES-256) with a key that only your
password or your recovery key can unlock (Argon2id). Someone who copies the files, or uses your
computer while Sotto is closed or locked, can't read them. Sotto locks when you press **Lock now**
(sidebar, Settings, or Ctrl+Alt+K / ⌃⌥K) and after the inactivity time you choose (never in the
middle of a talk, a rehearsal or a fill).

**It doesn't protect:**

- **Settings** (theme, language, window size, shortcuts). They stay readable so the unlock screen can
  open in your language and theme.
- **Your DeepSeek key.** It was already in the system keychain and stays there.
- **A running, unlocked Sotto.** While it's open and unlocked, your data is too, to you and to any
  program running as you.
- **Copies made before you turned the lock on.** Deleting a file isn't a secure erase. If your
  Documents folder syncs with OneDrive (or a backup tool copies it), older unencrypted versions may
  remain in its version history, recycle bin or backups. Check them after turning the lock on.
- **Windows Hello / Touch ID,** if you turn it on, keeps a copy of the key in the system keychain,
  where programs running as you can read it. It's faster, but weaker than the password alone.

**If you forget the password,** the recovery key (shown once when you turn the lock on, and again
later after entering your password) lets you set a new one. **If you lose both, the data is gone.**
Nobody can recover it, us included. The unlock screen's *Reset Sotto* then deletes the locked data
so you can start over; your settings and your DeepSeek key stay.

## Browser extension

**Sotto Bridge** (`extension/`, for Chrome, Edge and Firefox) lets form filling read web forms from the
page itself instead of from pixels. Install it from Settings → Forms → Browser integration, or unpack
`sotto-bridge-<version>.zip` from the release and load it as an unpacked extension (Chrome/Edge:
`chrome://extensions` → Developer mode; Firefox: `about:debugging` → Load Temporary Add-on). Sotto
registers its native messaging host for your user on every start, with no admin rights needed. It only
reads the active tab, only when Sotto asks, and never reads password or payment fields. Available on
Windows and macOS.

## Build from source

Requirements: [Flutter](https://docs.flutter.dev/get-started/install) **3.47.5** (stable), plus:

- **Windows:** Visual Studio 2022 with the *Desktop development with C++* workload (Windows 10/11
  SDK), and `nuget.exe` on `PATH` for `flutter_tts`.
- **macOS:** Xcode 16 or later.
- **Linux:**

  ```sh
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libkeybinder-3.0-dev
  ```

```sh
flutter pub get
flutter run -d windows        # or -d macos / -d linux
flutter test                  # unit and widget tests (no key or network needed)
```

**Your own built-in key (optional).** The key is never in the source. Pass it at build time:

```sh
cp secrets.example.json secrets.json      # git-ignored; paste your key into it
flutter run --dart-define-from-file=secrets.json
flutter build windows --release --dart-define-from-file=secrets.json
# or: --dart-define=DEEPSEEK_API_KEY=sk-...
```

Without it, the app builds and runs normally, and AI features ask for a key in Settings →
Integrations. A key built into a binary can be extracted from it, so only ship builds with a key you
are willing to share.

Releases are built by GitHub Actions (`.github/workflows/release.yml`) when a `v*` tag is pushed.

## More

- [How Sotto works](docs/ARCHITECTURE.md): architecture, voice following, the overlay, every opt-in
  feature in depth, tests and known limitations.
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## License

[MIT](LICENSE) © 2026 Jeferson Manuel Morillo Vallejo.

Typefaces: Geist, Geist Mono and Atkinson Hyperlegible Next, under the SIL Open Font License (see
`assets/fonts/`).
