# blitzbot ⚡

**Local speech-to-text menu bar app for macOS.** Dictate anywhere, anytime — the transcribed text pastes directly into whatever app has focus: Mail, Slack, LinkedIn, Notes, WhatsApp Web, your terminal, your IDE.

No always-on cloud listener. No server round-trip for the raw transcription. Press a hotkey, speak, press the hotkey again — text appears.

> **Inspiration**: Christoph Magnussen's video *"Nie wieder Tippen! Meine eigene Speech-to-Text App (Claude Code)"* — https://www.youtube.com/watch?v=vVTl1dqPL0k
>
> This is my own take on the idea: different architecture, different modes, different name. The point — as Christoph put it — is the shift from *tool tourist* to *application master*.

- **Speech-to-text**: [whisper.cpp](https://github.com/ggerganov/whisper.cpp) running locally. Offline. Private. No audio leaves your machine.
- **Text polishing** (optional, per mode): [Anthropic Claude API](https://www.anthropic.com). Only the transcribed text is sent, never the audio.
- **One API key to set up**: Anthropic. That's it.
- **Open source**: MIT license.

---

## Table of contents

- [The five modes](#the-five-modes)
- [Installation](#installation)
- [Usage](#usage)
- [Settings](#settings)
- [Data flow & privacy](#data-flow--privacy)
- [Cost](#cost)
- [macOS permissions explained](#macos-permissions-explained)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [Roadmap](#roadmap)
- [License](#license)

---

## The five modes

| # | Mode        | Default hotkey | Tagline                                 | Behavior |
|---|-------------|----------------|------------------------------------------|----------|
| 1 | **Normal**    | `⌘⌥1`          | Voice in. Text out.                      | Raw Whisper transcript. **No cloud call.** Zero cost. |
| 2 | **Business**  | `⌘⌥2`          | Voice in. Business-ready out.            | Claude rewrites into clear, polite, structured business communication (emails, customer replies, LinkedIn posts). |
| 3 | **Plus**      | `⌘⌥3`          | Speak in writing.                        | Claude removes filler words (*uhm, also, you know*) and fixes grammar — **your voice stays intact**. Not a business makeover. |
| 4 | **Rage**      | `⌘⌥4`          | Frustration in. Calm out.                | Claude strips insults and aggressive tone — the substance of your criticism stays sharp. Good for writing angry emails you won't regret. |
| 5 | **Emoji**     | `⌘⌥5`          | Voice in. Text with emojis out.          | Original wording 1:1, dotted with tasteful emojis (roughly 1 per 1-2 sentences). |

### Switch mode mid-recording

Start a recording with `⌘⌥1` (Normal), change your mind halfway through, press `⌘⌥4` while still speaking — the recording keeps going, but will be processed as Rage when you stop. The floating HUD reflects the current mode live.

### Everything customizable

- **Hotkeys**: Settings → Hotkeys → click the recorder next to each mode, press your desired combo.
- **Prompts**: Settings → Prompts → edit the Claude system prompt per mode. Make Business more formal, Rage softer, Emoji denser.
- **Vocabulary**: Settings → Vocabulary → add proper nouns and jargon. They're fed to Whisper as context so it spells *Anthropic*, *Kubernetes*, your colleagues' names, etc. correctly instead of phonetic nonsense.

---

## Installation

### Requirements

- macOS 13 (Ventura) or newer
- Apple Silicon (arm64) — Intel not tested
- [Homebrew](https://brew.sh)
- About 1.5 GB of free disk for the Whisper model
- Anthropic API key (only for Business / Plus / Rage / Emoji — Normal works without)

### Option A: Download the release

1. Grab the latest `.zip` from [Releases](https://github.com/mosandlt/BlitzBot/releases).
2. Unzip. Drag `blitzbot.app` into `/Applications`.
3. Run the Whisper setup from the repo (see below) — you still need the CLI and model.

### Option B: Build from source

```bash
git clone https://github.com/mosandlt/BlitzBot.git
cd BlitzBot
./setup-whisper.sh     # installs whisper-cpp via brew + downloads the model
./build-app.sh         # compiles + bundles blitzbot.app
open blitzbot.app
```

### Whisper setup (both options need this)

`./setup-whisper.sh` does two things:

1. `brew install whisper-cpp` — the local CLI
2. Downloads `ggml-large-v3-turbo.bin` (~1.5 GB) into `~/.blitzbot/models/` — the model used for transcription

The model lives outside the repo so it isn't re-downloaded on every clone.

### First launch

On first launch blitzbot opens a **Setup window** that walks you through four checks:

1. **Microphone** — required
2. **Accessibility** — required (for the Cmd+V paste simulation)
3. **Whisper binary** — must exist
4. **Whisper model** — must exist

Green checkmarks everywhere? Click *Continue*. Something red? Click the button next to it to open the relevant macOS Settings pane. If you close the window prematurely, reopen it via **Settings → Setup**.

### Anthropic API key

Only needed for Business / Plus / Rage / Emoji.

1. Get one at https://console.anthropic.com/settings/keys
2. In blitzbot: menu bar ⚡ icon → ⚙ (gear) → **General** → paste key into *Anthropic API Key* → Save
3. Key is stored in the macOS Keychain. Never in files, never in git.

Normal mode runs entirely offline — no key, no cloud calls, nothing.

---

## Usage

1. Put focus into your target app (Notes, Mail, any text field).
2. Press your mode hotkey (default `⌘⌥1` for Normal).
3. A HUD appears in the center of the screen with a live timer, animated waveform, mode badge, and status line.
4. Speak.
5. Press the same hotkey again to stop.
6. 1-3 seconds later (Whisper + optional Claude call), text pastes into the target app via simulated Cmd+V.

### The HUD

During recording, a floating panel shows up in the middle of your screen:

- Top-left: mode icon + name
- Top-right: elapsed time (`mm:ss`, monospaced)
- Middle: 22-band waveform that reacts to your mic input
- Bottom: status text — *Recording… → Transcribing… → Formulating… → Done*

The HUD does **not** steal focus — it's an `NSPanel` with `nonactivatingPanel` + `ignoresMouseEvents`, visible on all Spaces including fullscreen apps. Your target app keeps focus, so the Cmd+V actually pastes where you expect.

### The menu bar icon

The menu bar icon reflects current state without requiring you to open the popover:

| Icon                              | State |
|-----------------------------------|-------|
| ⚡ (yellow bolt)                   | Idle, ready |
| 🔴 red dot + "REC" label          | Recording |
| 🟡 waveform                       | Transcribing or calling Claude |
| 🟢 green checkmark                | Done — text pasted |
| 🟠 orange warning triangle        | Error (hover/click for detail) |

Click the icon to open the popover with the full mode list, status, and access to Settings.

---

## Settings

Six tabs under **⚙ Settings**:

| Tab        | What's inside |
|------------|---------------|
| **General**    | Anthropic API key, Claude model selection (Sonnet/Opus/Haiku), Whisper binary path, Whisper model path |
| **Hotkeys**    | One recorder field per mode. Click, press keys. Defaults shown. Any conflicts are handled by the OS (you'll see it if a combo is reserved). |
| **Prompts**    | Editable system prompt per mode. The default prompts are deliberately minimal — tweak to match your tone. |
| **Vocabulary** | Proper nouns, product names, jargon, colleagues. Passed to Whisper as `--prompt`. Improves spelling accuracy dramatically. |
| **Setup**      | Opens the onboarding wizard again. Use when permissions got reset (common after rebuilds). |
| **About**      | Version, update check, GitHub link, license. Click *Check now* to see if a new release is available. |

---

## Data flow & privacy

```
microphone
    ↓
AVAudioEngine ──► /tmp/blitzbot-<uuid>.wav   (ephemeral, deleted after transcription)
    ↓
whisper-cli (local, offline, no network)
    ↓
text
    ↓
mode router:
    ├─ Normal   → text directly
    ├─ Business → Claude API call with business prompt
    ├─ Plus     → Claude API call with light-touch polish prompt
    ├─ Rage     → Claude API call with de-escalation prompt
    └─ Emoji    → Claude API call with emoji-insertion prompt
    ↓
NSPasteboard.general (writes the result)
    ↓
CGEvent Cmd+V simulation (120 ms delay, cgAnnotatedSessionEventTap)
    ↓
text lands in whatever app has keyboard focus
```

**Privacy guarantees:**

- **Audio never leaves your machine.** Not in any mode. Transcription is 100% local via whisper.cpp.
- **`.wav` files are temporary.** Created in `/tmp/`, deleted immediately after Whisper finishes (inside a `defer` block in the transcriber).
- **Normal mode makes zero network calls.** No telemetry, no analytics, no phone-home.
- **Business / Plus / Rage / Emoji** send exactly one HTTPS request to `api.anthropic.com`, containing just the transcribed text + the mode's system prompt. That's the only thing that ever leaves your machine.
- **The API key lives in the macOS Keychain**, not in UserDefaults, not on disk in plain text.
- **Transcripts aren't persisted.** The dev log at `~/.blitzbot/logs/blitzbot.log` contains transcripts only for debugging — if you plan to ship this publicly at scale, strip those `Log.write("TRANSCRIPT: …")` calls or reduce them to just `len=<n>`.

---

## Cost

| Mode       | Cost per dictation (rough) |
|------------|-----------------------------|
| Normal     | $0 — fully local |
| Business   | ~$0.0006 — 200 input tokens × Sonnet pricing |
| Plus       | ~$0.0006 |
| Rage       | ~$0.0006 |
| Emoji      | ~$0.0006 |

Pricing source: [Anthropic pricing](https://www.anthropic.com/pricing) — update yourself if rates change. In practice dictating all day long costs a few cents.

---

## macOS permissions explained

blitzbot touches three macOS permission systems:

1. **Microphone** — so it can record you. Granted via the first `AVCaptureDevice.requestAccess` call; macOS remembers per user account.
2. **Accessibility** — so it can simulate the Cmd+V that pastes into the active app. Granted in **System Settings → Privacy & Security → Accessibility**.
3. **Input Monitoring / Post Events** — implicitly covered by Accessibility on recent macOS; on some older versions you may also need to toggle *Input Monitoring*.

### Why do permissions disappear after I rebuild the app?

Short answer: ad-hoc code signing.

Long answer: macOS TCC (the Transparency, Consent, and Control system) binds permissions to a specific *code signature hash* (cdhash). Every time you run `codesign --force --sign -` with an ad-hoc identity, the cdhash changes. TCC then doesn't recognize the app as the same entity that was previously granted permission, and revokes it.

The microphone permission survives rebuilds because it's stored in the **user** TCC database and keyed slightly differently (by bundle ID). Accessibility and Input Monitoring live in the **system** TCC database and are stricter.

### The fix: a stable developer certificate

Create a self-signed certificate once, then always sign with it. Permissions stick.

1. Open **Keychain Access**.
2. Menu: *Certificate Assistant* → *Create a Certificate…*
3. Name: `blitzbot-dev`
4. Identity Type: *Self Signed Root*
5. Certificate Type: *Code Signing*
6. Click *Create*.
7. After creation, double-click the cert in Keychain Access → *Trust* → *When using this certificate*: **Always Trust** (specifically mark *Code Signing* as Always Trust).

Then sign with it:

```bash
./build-app.sh --sign blitzbot-dev
```

Permissions now persist across rebuilds. Until you do this step, you'll need to re-grant Accessibility after every build — the Setup tab makes this a two-click operation, but it's annoying.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Menu bar icon appears, but hotkey does nothing | Accessibility permission revoked | Settings → Setup → *Open in Settings* → re-enable blitzbot |
| Text ends up in clipboard but doesn't paste | Accessibility permission revoked | Same as above |
| "No API key" warning at bottom of popover | No Anthropic key saved | Settings → General → paste key → Save |
| `whisper-cli not found` | Whisper not installed, or path changed | Settings → General → Whisper binary → set correct path, or run `./setup-whisper.sh` again |
| Transcription is garbage or wrong language | Whisper language assumption (default: de) | Edit `WhisperTranscriber.swift:6` — `language: String = "de"` → change to your language code |
| Business / Plus / Rage output is empty | Claude API call failed (e.g. invalid key, rate limit) | Check `~/.blitzbot/logs/blitzbot.log` for an `ERROR:` line |
| Icon is always black / doesn't render | Rebuilt icon with the dev script, ad-hoc sign didn't refresh LaunchServices | Run `touch blitzbot.app` then `open blitzbot.app` — forces LaunchServices refresh |
| HUD doesn't appear | Processor didn't transition to `.aufnahme` state | Log check — either the audio engine failed to start (mic permission?) or the mode toggle didn't fire |

### Reading the log

```bash
tail -f ~/.blitzbot/logs/blitzbot.log
```

Every state transition is logged: hotkey registration, recording start/stop with byte count, transcript preview, paste confirmation, and any errors. This is your first debugging tool.

---

## Development

### Tooling

- **Swift 5.9+** with macOS 13+ as minimum target
- **Swift Package Manager** — no Xcode project file, just `Package.swift`
- **Xcode** or any Swift-aware editor
- External dependency: [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, pinned `<1.15.0` (the 2.x line uses `#Preview` macros that break non-Xcode `swift build`)

### Commands

```bash
# Build release binary
swift build -c release

# Regenerate the app icon (writes blitzbot.iconset/ and AppIcon.icns)
swift tools/make-icon.swift
iconutil -c icns blitzbot.iconset -o blitzbot.app/Contents/Resources/AppIcon.icns

# Full build + bundle + sign + launch
./build-app.sh                       # ad-hoc sign (dev cycle)
./build-app.sh --sign blitzbot-dev   # stable self-signed cert (permissions survive)

# Follow logs
tail -f ~/.blitzbot/logs/blitzbot.log

# Run Whisper on a file directly (debugging)
whisper-cli -m ~/.blitzbot/models/ggml-large-v3-turbo.bin -f test.wav -l de -nt -otxt -of test
```

### Key files

```
Sources/blitzbot/
  blitzbotApp.swift         @main + AppDelegate + MenuBarExtra + Windows
  AppConfig.swift           UserDefaults, Keychain wrapper, vocabulary, per-mode prompts
  AppInfo.swift             Version constants and repo URL
  Mode.swift                enum (Normal, Business, Plus, Rage, Emoji) + display names + default prompts
  HotkeyManager.swift       KeyboardShortcuts integration per mode
  ModeProcessor.swift       state machine: toggle → record → transcribe → formulate → paste
  AudioRecorder.swift       AVAudioEngine setup + RMS level publishing for the HUD waveform
  WhisperTranscriber.swift  subprocess wrapper around whisper-cli
  AnthropicClient.swift     Claude API request/response
  Paster.swift              NSPasteboard + CGEvent Cmd+V simulation
  KeychainStore.swift       API key read/write/delete in Keychain
  Log.swift                 simple append-only log at ~/.blitzbot/logs/blitzbot.log
  Permissions.swift         TCC status checker for mic/accessibility/whisper
  PermissionsView.swift     onboarding wizard UI
  MenuBarView.swift         popover content (header, mode list, footer)
  SettingsView.swift        TabView (General / Hotkeys / Prompts / Vocabulary / Setup / About)
  RecordingHUD.swift        NSPanel + SwiftUI content for the floating recording HUD
  Updater.swift             GitHub Releases API check + download + install
```

### Working conventions

See [`CLAUDE.md`](CLAUDE.md) for the full set of rules this project follows. Highlights:

- **Two-prompt rule**: before any non-trivial feature, run a critical-analysis pass first, then implement. No "just code it up".
- **Log via `Log.write(...)`**, never `print`, never `FileHandle.standardError.write` — the persistent log survives app restarts and is your main debugging tool.
- **Lifecycle via `NSApplicationDelegate`** (wired with `@NSApplicationDelegateAdaptor`). SwiftUI `.onAppear` on `MenuBarExtra` labels is not reliable as a startup hook.
- **Floating panels must not steal focus** — always `NSPanel` with `.nonactivatingPanel` + `ignoresMouseEvents`.
- **No new external dependencies without discussion.** Every package added is supply-chain risk and bundle-size tax.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         user presses ⌘⌥2 (Business)                  │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│ KeyboardShortcuts → HotkeyManager.onTrigger → ModeProcessor.toggle   │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│ ModeProcessor state machine                                          │
│  bereit → aufnahme → transkribiert → formuliert → fertig → bereit    │
│                                                                      │
│  In aufnahme:  AudioRecorder running + @Published elapsed timer      │
│                + RMS level stream into HUD                           │
│  In transkribiert: WhisperTranscriber subprocess                     │
│  In formuliert:    AnthropicClient request                           │
│  In fertig:        Paster.pasteText() + 1.5s cooldown                │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│ observers                                                            │
│  MenuBarLabel (icon + REC badge)                                     │
│  MenuBarView (popover content)                                       │
│  RecordingHUDController (shows NSPanel during active recording)      │
└──────────────────────────────────────────────────────────────────────┘
```

Everything is driven by `@Published` fields on `ModeProcessor` and `AudioRecorder`. SwiftUI views subscribe via `@EnvironmentObject`. No shared mutable state outside these observables.

---

## Contributing

PRs welcome. A few principles:

- **Small, focused commits.** No "wip", no "fix stuff".
- **Keep the tagline pattern.** New mode? Tagline must read *"X in. Y out."* in both English and German.
- **Don't add dependencies lightly.** The current dep list is `KeyboardShortcuts` and that's it. Be prepared to justify additions.
- **German + English for UI strings.** See `blitzbot.app/Contents/Resources/en.lproj/Localizable.strings` and the `String(localized:)` calls in source.
- **Before pushing**: run the secrets scan in `CLAUDE.md` (section *Sicherheit & Privatsphäre*). No `.env`, no API keys, no personal identifiers.

Areas where help is especially welcome:

- Push-to-talk as an alternative to toggle (hold hotkey while speaking)
- Intel x86_64 build + universal binary
- Notarization pipeline for the release workflow
- Additional languages in `Localizable.strings`
- More modes (e.g. *Translate* — dictate in one language, get output in another)

---

## Roadmap

- [ ] Stable-cert code signing in the release build (no more permission resets for end users)
- [ ] Apple notarization
- [ ] Universal binary (arm64 + x86_64)
- [ ] Push-to-talk mode
- [ ] Optional local-only LLM for polishing (Ollama integration) for full offline end-to-end
- [ ] Streaming transcription with interim text in the HUD
- [ ] Multi-mic selection in settings
- [ ] Custom "Translate" mode

Got other ideas? Open an issue.

---

## License

MIT — see [LICENSE](LICENSE).

© 2026 blitzbot contributors.
