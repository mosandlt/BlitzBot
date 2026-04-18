# blitzbot ⚡

**Local speech-to-text menu bar app for macOS.** Dictate anywhere, anytime — the transcribed text pastes directly into whatever app has focus: Mail, Slack, LinkedIn, Notes, WhatsApp Web, your terminal, your IDE.

No always-on cloud listener. No server round-trip for the raw transcription. Press a hotkey, speak, press the hotkey again — text appears.

> **⚠️ Platform support: macOS only (Apple Silicon)**
>
> blitzbot is **not available** for Windows or Linux. The whole app is deeply integrated with macOS-specific APIs: SwiftUI + AppKit UI, Carbon global hotkeys, CGEvent Cmd+V simulation, TCC accessibility permissions, macOS Keychain. Porting isn't a recompile — it would be a rewrite of every OS-touching layer.
>
> The reusable pieces are cross-platform: [whisper.cpp](https://github.com/ggerganov/whisper.cpp) runs on Linux and Windows, and the Claude API is HTTP. If you want to build a Windows or Linux equivalent using those building blocks, go for it — the prompts in `Sources/blitzbot/Mode.swift` are portable. PRs adding a separate cross-platform implementation (Tauri, Electron, native Win/Linux) are welcome as a sibling directory, but will not be maintained by me personally. See the [Contributing](#contributing) section.

> **Inspiration**: Christoph Magnussen's video *"Nie wieder Tippen! Meine eigene Speech-to-Text App (Claude Code)"* — https://www.youtube.com/watch?v=vVTl1dqPL0k
>
> This is my own take on the idea: different architecture, different modes, different name. The point — as Christoph put it — is the shift from *tool tourist* to *application master*.

- **Speech-to-text**: [whisper.cpp](https://github.com/ggerganov/whisper.cpp) running locally. Offline. Private. No audio leaves your machine.
- **Text polishing** (optional, per mode): [Anthropic Claude API](https://www.anthropic.com). Only the transcribed text is sent, never the audio.
- **One API key to set up**: or more, via **Connection Profiles** — each profile holds a provider, base URL, auth scheme, and key. Switch profiles with one click.
- **Open source**: MIT license.

---

## Table of contents

- [The seven modes](#the-seven-modes)
- [Office Mode — interactive selection-rewriter](#office-mode--interactive-selection-rewriter)
- [Privacy Mode — local PII anonymization](#privacy-mode--local-pii-anonymization)
- [Connection recovery — no transcript left behind](#connection-recovery--no-transcript-left-behind)
- [Connection profiles](#connection-profiles)
- [Installation](#installation)
- [First launch on macOS (Gatekeeper workaround)](#first-launch-on-macos-gatekeeper-workaround)
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
- [Changelog](#changelog)
- [License](#license)

---

## The seven modes

Modes 1–6 are voice-driven (mic + Whisper + paste). Mode 7 (**Office**) is the first non-voice mode: a dedicated window that accepts typed text or a dropped file.

| # | Mode          | Default hotkey | Tagline                                 | Behavior |
|---|---------------|----------------|------------------------------------------|----------|
| 1 | **Normal**      | `⌘⌥1`          | Voice in. Text out.                      | Raw Whisper transcript. **No cloud call.** Zero cost. |
| 2 | **Business**    | `⌘⌥2`          | Voice in. Business-ready out.            | Claude rewrites into clear, polite, structured business communication (emails, customer replies, LinkedIn posts). |
| 3 | **Plus**        | `⌘⌥3`          | Speak in writing.                        | Claude removes filler words (*uhm, also, you know*) and fixes grammar — **your voice stays intact**. Not a business makeover. |
| 4 | **Rage**        | `⌘⌥4`          | Frustration in. Calm out.                | Claude strips insults and aggressive tone — the substance of your criticism stays sharp. Good for writing angry emails you won't regret. |
| 5 | **Emoji**       | `⌘⌥5`          | Voice in. Text with emojis out.          | Original wording 1:1, dotted with tasteful emojis (roughly 1 per 1-2 sentences). |
| 6 | **Prompt**      | `⌘⌥6`          | Idea in. Prompt out.                     | Dictate a loose idea — Claude turns it into a clean, precise prompt you can paste into any AI tool (ChatGPT, Claude, Claude Code, Cursor, Aider, Copilot, Gemini, …). Output is the prompt itself, not the result. |
| 7 | **Office**      | *(no default — set in Settings → Hotkeys)* | Selection in. Choice + paste out. | Interactive selection-rewriter. Grabs the currently selected text, shows it in a preview, lets you pick any voice-mode prompt (Business, Plus, Rage, Emoji, Prompt), override profile + model, tweak the text, then pastes the result back into the source app on ⌘↵. File-drop also works as an alternative input. See [Office Mode](#office-mode--interactive-selection-rewriter). |

### Output language (auto-detected or manual)

Settings → General → *Output language*:

- **Auto** (default) — Whisper detects the language of what you spoke; the Claude polish runs in the same language
- **German** — forces DE transcription + polish regardless of what you said
- **English** — forces EN transcription + polish

While recording, the HUD shows a small `DE`/`EN` badge next to the mode name so you see what the app will actually output.

### Switch mode mid-recording

Start a recording with `⌘⌥1` (Normal), change your mind halfway through, press `⌘⌥4` while still speaking — the recording keeps going, but will be processed as Rage when you stop. The floating HUD reflects the current mode live.

Or click directly: the HUD has six **mode pills** at the bottom (Office is excluded from the HUD — it has its own window). Click any pill during recording to switch live. The **Stop** button on the right ends the recording with a mouse click — useful when your keyboard is full of other input and you don't want to hit the hotkey.

### Everything customizable

- **Hotkeys**: Settings → Hotkeys → click the recorder next to each mode, press your desired combo.
- **Prompts**: Settings → Prompts → edit the Claude system prompt per mode. Make Business more formal, Rage softer, Emoji denser.
- **Vocabulary**: Settings → Vocabulary → add proper nouns and jargon. They're fed to Whisper as context so it spells *Anthropic*, *Kubernetes*, your colleagues' names, etc. correctly instead of phonetic nonsense.

---

## Office Mode — interactive selection-rewriter

The seventh mode is different from the voice-driven six: no mic, no Whisper. It's a **preview-and-confirm** version of the ⌘⌥0 selection-rewriter — you see what got captured, you pick which mode to apply, you review the result, then you decide when to paste it back.

### The flow

1. Highlight text in any app (Mail, Safari, Notes, your IDE, any Electron thing, …).
2. Press your configured Office hotkey. **There is no default** — assign one under Settings → Hotkeys. While the window is open blitzbot also appears in the Dock + ⌘-Tab, so you can jump back to it from anywhere; the Dock icon disappears again when the window closes.
3. Blitzbot grabs the selection *before* stealing focus (AX API first, `⌘C` simulation as fallback) and remembers the source app's bundle ID for the paste-back step.
4. The window opens pre-filled with the grabbed text. The source-app name appears as a chip above the editor.
5. **Profile + model switcher** — top of the header. Dropdown lists every connection profile; picking one overrides which endpoint this session uses, without mutating your global active profile. The model field pre-fills with the picked profile's preferred model and is editable, so you can e.g. try Opus for this one request and keep Sonnet as your default.
6. Pick a mode from the picker row — Business / Plus / Rage / Emoji / Prompt. The default is whatever `Settings → Allgemein → Text umschreiben → Default-Modus` is set to (shared with ⌘⌥0).
7. Tweak the text if needed — the editor is fully editable.
8. Hit `⌘↵` or click **Verarbeiten**. LLMRouter sends it through the chosen profile/model with the picked mode's prompt.
9. The result appears below, and is **automatically copied to the clipboard** as a safety net.
10. Hit `⌘↵` again (now labelled **In App einfügen**) or click the button. Blitzbot closes the Office window, re-activates the source app by bundle ID, and simulates ⌘V so the result lands where your selection was.

### Fallbacks

- **No selection** when you press ⌘⌥O? Blitzbot pre-fills from the current clipboard contents (up to the 200 KB text limit). The source-app info is still captured, so paste-back still works.
- **Window opened via MenuBar → Office → Öffnen** (not the hotkey)? There's no AX selection available because blitzbot already stole focus by the time the popover opens. The editor falls back to clipboard contents; paste-back is unavailable (no source app was captured), the result just stays on the clipboard.
- **File drop** — drop a text file (`.txt`, `.md`, `.json`, `.csv`, `.log`, plus common code types) into the small dropzone below the editor to replace the input. Hard limit: **200 KB**. Binary types are intentionally unsupported. File-origin inputs have no source app, so the result goes to the clipboard only.

### Design notes

- **Toggle window**: press your Office hotkey a second time to close.
- **Dock appearance** — while Office is open blitzbot toggles its activation policy to `.regular` so you get a Dock icon + ⌘-Tab entry. Closing the window reverts to the menu-bar-only `.accessory` policy.
- **Auto-copy to clipboard** is always on once processing succeeds, regardless of whether you paste-back. That's the "clipboard by default" safety net — even if paste-back fails or you close the window without confirming, the result is there.
- **Re-process button** appears after a first result so you can try the same input against a different mode/profile/model without re-grabbing.
- **Session override, not global** — the profile/model picker changes only the current Office session; your global active profile stays put.
- **No disk persistence** — everything lives in window state, gone on close.

---

## Privacy Mode — local PII anonymization

blitzbot ships a **pre-send anonymizer for every outbound LLM call**. Names, company mentions, places, emails, IPs, URLs, and phone numbers are detected locally and replaced with neutral tokens *before* any text leaves the app. The LLM's response is then automatically rewritten back into the real terms on the way in, so for the user the flow looks unchanged — but what the provider sees is redacted.

Every path that hits an LLM — all six voice modes, Office Mode, the `⌘⌥0` selection-rewriter, and the recovery retries — goes through the same wrap. One mechanism, consistent guarantee.

> **Default since v1.2.2: ON.** Privacy Mode is active on a fresh install and stays active unless you explicitly turn it off. Your choice is persisted — an explicit off survives app restarts and updates. If you had Privacy Mode explicitly turned off in an earlier version, that setting is preserved.

### How it works

1. **Scan.** When a request is about to go out, the input text is analyzed by several local detectors running in parallel:
   - Apple's `NLTagger(.nameType)` for personal names, organization names, and place names
   - `NSDataDetector` for phone numbers, URLs, and postal addresses (street + number + ZIP + city, any locale Apple's parser knows)
   - regex for email addresses, IPv4 + IPv6 addresses, MAC addresses, IBAN bank account numbers, and credit-card numbers (with a Luhn-checksum filter to rule out random long numbers)
   - plus your own "Immer anonymisieren" list from Settings (case-insensitive, whole-word match) — catches short all-caps abbreviations and internal code names that the NER model misses
2. **Substitute.** Each detected entity is swapped for a bracketed all-caps token. The full set of kinds:

   | Kind | Placeholder shape |
   |---|---|
   | Personal name | `[NAME_1]`, `[NAME_2]`, … |
   | Organization / company | `[UNTERNEHMEN_1]`, … |
   | Place (city, region) | `[ORT_1]`, … |
   | Postal address | `[ADRESSE_1]`, … |
   | Email address | `[EMAIL_1]`, … |
   | IP address (v4 or v6) | `[IP_1]`, … |
   | URL | `[URL_1]`, … |
   | Phone number | `[TELEFON_1]`, … |
   | IBAN | `[IBAN_1]`, … |
   | Credit-card number | `[KREDITKARTE_1]`, … |
   | MAC address | `[MAC_1]`, … |

   The indexer grows per kind as new entities appear. The same original value reuses its existing token, so multi-turn context stays consistent — if you mention the same colleague in two dictations, they get the same placeholder both times.
3. **Send.** The anonymized text goes to the LLM along with a short bilingual instruction appended to the system prompt: "any `[XXXX_N]` tokens in the input are placeholders for real entities — keep them verbatim, do **not** fill them in, do **not** apply your own anonymization to plain-text words". This prevents the model from either "correcting" the placeholders or inventing new ones of its own.
4. **Reverse.** The model's response is scanned for the placeholders you sent out and they're swapped back into the original values before the text reaches your clipboard, your active app, or the Office preview. Longer placeholders are matched first so `[NAME_10]` doesn't get eaten as `[NAME_1]` + `"0]"`.

### Activation and deactivation

Three equivalent ways to flip Privacy Mode — all toggle the same underlying state, all persist.

| Surface | Where |
|--------|-------|
| Menu-bar popover header | Click the ⚡ icon → the shield pill next to the status indicator is the toggle. Shows live entity count when on. |
| Office window header | Shield pill next to the profile/model pickers. Click opens a popover with the full session mapping (`[NAME_1] ↔ Alex Example` etc.) and an inline toggle + reset. |
| Recording HUD header | Shield pill between the language badge and the timer. Single click toggles. Compact — no popover on the HUD (nonactivating panel). |
| Settings → Allgemein → Privacy | Full section with the toggle, live entity count, reset button, and the "Immer anonymisieren" editor. |

On a **fresh install** Privacy Mode starts **on**. On an **existing install** your persisted choice wins — if you had it off before, it stays off.

### "Immer anonymisieren" — custom term list

`NLTagger` is ML-based and sometimes misses short all-caps words or domain-specific code names. The *Immer anonymisieren* field in Settings → Allgemein → Privacy takes a comma-separated list of terms that are always replaced, case-insensitive, whole-word only. Typical entries: your employer's short name, internal project codenames, your own last name, client code names. Persisted in UserDefaults; stays empty by default.

### Privacy guarantees

- **No external service ever sees the originals.** All detectors are macOS system frameworks, running locally. A privacy feature that phoned home would defeat its own point.
- **Mapping stays in memory.** Lives on `AppConfig.privacyEngine`, never written to UserDefaults, Keychain, or disk.
- **Reset on toggle-off and quit.** Turning the feature off wipes the session mapping; app quit disposes of the engine entirely. No PII dictionary sitting around between runs.
- **Log only counts.** `~/.blitzbot/logs/blitzbot.log` records `Privacy: anonymized name=3 organization=1 …` — never the originals themselves.
- **System prompts pass through unchanged** (except for the bilingual instruction added on the fly when Privacy Mode is on). Default prompts contain tool names like `Claude`/`ChatGPT`/`Cursor` that `NLTagger` would flag; placeholdering them would tank output quality. If your *custom* prompt overrides contain PII, anonymize it before saving — the feature treats system prompts as canonical app content.

### What you see when it's running

- Green shield pill in the menu bar, Office header, and HUD, with the session's unique-entity count.
- Settings → Allgemein → Privacy: live counter + a *Zurücksetzen* button.
- Office Mode: click the shield pill to open a popover with the full `placeholder ↔ original` mapping, color-coded by kind (names blue, orgs purple, places teal, emails orange, URLs green, phones indigo, IPs pink).
- Log lines per request so you can verify the mapping is firing.

---

## Connection recovery — no transcript left behind

What happens when you've dictated 20 seconds, the Claude call fails halfway through, and you're on a flaky coffee-shop Wi-Fi? Before: the transcript was lost to an auto-hiding error toast. Now: the HUD stays open and offers you a second chance.

**Recoverable failures**:

- network-level: no internet, timeout, DNS error, TLS failure, host unreachable
- HTTP 401 / 403 (bad / expired key)
- HTTP 5xx (provider outage)

When one of those fires, the HUD switches into **recovery mode**:

- the transcript is **mirrored to the system clipboard immediately** (safety net — even if the app crashes now, your text is safe)
- a profile picker appears inline — every connection profile you have, with the just-failed profile marked **fehlgeschlagen** and disabled
- a 30-second countdown pill starts. If you pick nothing, recovery state is discarded — but the transcript still lives in the clipboard
- click a different profile, hit **Erneut senden** — the retry reuses the same transcript against the alternate endpoint, without re-transcribing. If the retry also fails, the flow re-enters recovery with the new profile flagged

What's *not* recoverable (these still go to the old `.fehler` state): empty transcriptions, "no API key configured", malformed responses, context-length exceeded. Those aren't a profile problem and another endpoint won't fix them.

The retry path is an **override** — your globally-active profile stays put. Use this when your work VPN proxy is flaky but your direct-Anthropic profile works.

---

## Connection profiles

blitzbot can talk to **any OpenAI-compatible or Anthropic-compatible LLM endpoint** — not just the default Anthropic API. You configure endpoints as *profiles*, pick one as active, and all LLM calls flow through it.

### What a profile contains

| Field | Description |
|-------|-------------|
| **Name** | Display name (e.g. "Direct Anthropic", "Work proxy") |
| **Provider** | `Anthropic` / `OpenAI` / `Ollama` — controls the request format |
| **Base URL** | Endpoint root (e.g. `https://api.anthropic.com`, `http://localhost:11434`) |
| **Auth scheme** | `x-api-key` header / `Bearer` token / none |
| **Active model** | Which model to use (picked from a live list or typed manually) |
| **API key / token** | Stored in the macOS Keychain — never in files |

### Managing profiles

Open **Settings → Profile**:

- **Quick-switcher chips** at the top — click any chip to activate that profile immediately
- **New profile** button — opens an inline editor
- **Scan this Mac** — automatically discovers configs in `~/.claude-profiles/`, `~/.claude/settings.json`, and `~/.config/claude/` and offers to import them as profiles (reads `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`)
- **Import / Export** — JSON format (export never includes secrets)
- **Model discovery** — inside the profile editor, click *Abrufen* to fetch the live model list from the endpoint. Click any model row to set it as the active model.

### Keychain and passwords

API keys and tokens are stored in the macOS login keychain with an **open-access ACL** — meaning any application on your Mac can read the item without a per-app confirmation dialog. macOS will **never ask for your login password** to grant blitzbot access, not even after rebuilds or updates.

> **Upgrading from v1.0.x / v1.1.0**: on the first launch blitzbot rewrites existing keychain items with the open-access ACL (one-time, silent). After that, no prompts ever.

---

## Installation

### Requirements

- **macOS 13 (Ventura) or newer** — Windows and Linux are **not supported** (see platform note above)
- Apple Silicon (arm64) — Intel not tested
- [Homebrew](https://brew.sh)
- About 1.5 GB of free disk for the Whisper model
- Anthropic API key (only for Business / Plus / Rage / Emoji — Normal works without)

### Option A: Download the release

1. Grab the latest `.zip` from [Releases](https://github.com/mosandlt/BlitzBot/releases).
2. Unzip. Drag `blitzbot.app` into `/Applications`.
3. **First launch — read this** ⚠️ — see [First launch on macOS](#first-launch-on-macos-gatekeeper-workaround) below.
4. Run the Whisper setup from the repo (see below) — you still need the CLI and model.

### First launch on macOS (Gatekeeper workaround)

blitzbot is **ad-hoc signed**, not notarized by Apple. That means when you double-click `blitzbot.app` the first time, macOS Gatekeeper will block it with one of these messages:

- *"blitzbot.app" can't be opened because the developer cannot be verified.*
- *"blitzbot.app" can't be opened because Apple cannot check it for malicious software.*
- *"blitzbot.app" is damaged and can't be opened.* (macOS 15+ Sequoia, if downloaded via browser)

**Why**: shipping a Gatekeeper-clean macOS app requires enrolling in the Apple Developer Program (99 €/year) and notarizing every release through Apple's service. This project is open source and hobbyist — that cost isn't justified yet. The source is on GitHub, you can read and build it yourself.

**How to open it anyway** (one-time per install):

1. Close the Gatekeeper dialog.
2. **Finder → Applications → right-click `blitzbot.app` → Open** (or Control-click → Open).
3. A similar dialog appears but now with an **Open** button. Click **Open**.
4. macOS remembers your decision. From the second launch onward it opens normally.

If the dialog says *"is damaged"* (macOS 15+), run this once in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/blitzbot.app
```

That strips the quarantine attribute Safari/Chrome attach to downloaded files. Then double-click normally.

**Security note**: you're running un-notarized code. That's a real trade-off. Before opening, you can:

- Build from source yourself (`./build-app.sh` — see [Development](#development))
- Inspect the signed binary: `codesign -dv /Applications/blitzbot.app` (should say `Signature=adhoc`)
- Diff the zip against what the repo would produce at the tagged commit

The app's behavior is constrained — it records audio, calls whisper.cpp locally, and optionally calls the Anthropic API. No other network calls, no telemetry, no auto-update writes outside `/Applications/blitzbot.app` itself.

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

### API key / connection profile

Only needed for Business / Plus / Rage / Emoji / Prompt.

**Quick setup (direct Anthropic):**
1. Get a key at https://console.anthropic.com/settings/keys
2. In blitzbot: menu bar ⚡ → ⚙ (gear) → **Profile** → *New profile* → paste key → Save
3. Key is stored in the macOS Keychain. Never in files, never in git.

**Custom endpoint or proxy:** use the Profile tab to set a different base URL and auth scheme. The scanner (*Auf diesem Mac suchen*) can auto-import settings from Claude Code config files.

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

- **Top-left**: X cancel button (aborts recording without pasting) + mode icon + name
- **Top-right**: elapsed time (`mm:ss`, monospaced)
- **Controls row**: Pause / Resume button (left) + Auto-Stop countdown clock with draining ring (right, only visible when auto-stop is running)
- **Middle**: full-width real audio waveform — draws actual PCM samples from the mic, scrolling in real-time. Always yellow during recording; grey when idle. A small **"Stimme erkannt"** badge fades in when voice is detected.
- **Silence banner**: fades in after 5 seconds of continuous silence with countdown to auto-stop (disappears smoothly when you resume speaking, no layout jumps)
- **Status line**: *Recording… → Pausiert → Transkribiere… → Formuliere… → Fertig*
- **Bottom row**: six mode pills (click to switch mode live), Auto-Execute toggle (↵), red **Stop** button

The HUD does **not** steal focus — it's an `NSPanel` with `nonactivatingPanel`, visible on all Spaces including fullscreen apps. Your target app keeps focus, so the Cmd+V actually pastes where you expect. The mode pills, Pause button, and Stop button work via mouse click because the panel accepts events without activating.

### Cancel vs. Stop

- **Stop** (red button or hotkey re-press): ends recording and processes + pastes the text
- **Cancel** (X button, top-left): ends recording and **discards** everything — nothing gets pasted. Good for accidental presses or drafts you change your mind about.

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

Seven tabs under **⚙ Settings**:

| Tab         | What's inside |
|-------------|---------------|
| **General**     | Output language (Auto/DE/EN), auto-stop on silence (toggle + timeout 10s–2min, default 60s), Whisper binary path, Whisper model path. Active profile name shown with a quick link to the Profile tab. |
| **Profile**     | Connection profiles — add, edit, delete, import/export, scan for local configs. Quick-switcher chips. Model list per profile. See [Connection profiles](#connection-profiles). |
| **Hotkeys**     | One recorder field per mode. Click, press keys. Defaults shown. |
| **Prompts**     | Editable system prompt per mode. Leave empty = language-aware default. Add text to either *replace* or *append* to the default (toggle per mode). |
| **Vocabulary**  | Proper nouns, product names, jargon, colleagues. Passed to Whisper as `--prompt`. Improves spelling accuracy dramatically. |
| **Setup**       | Opens the onboarding wizard again. Use when permissions got reset (common after rebuilds). |
| **About**       | Version, update check, GitHub link, license. |

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
mode router (for non-Normal modes, LLM provider is configurable: Claude / OpenAI / Ollama):
    ├─ Normal   → text directly (no cloud call, regardless of provider)
    ├─ Business → LLM call with business prompt
    ├─ Plus     → LLM call with light-touch polish prompt
    ├─ Rage     → LLM call with de-escalation prompt
    ├─ Emoji    → LLM call with emoji-insertion prompt
    ├─ Prompt   → LLM call that turns a loose idea into a tool-agnostic prompt
    └─ Office   → LLM call with structured-summary prompt (bypasses voice path entirely;
                  input is typed text or a dropped file, output lands in a preview window
                  instead of being auto-pasted)
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
- **Business / Plus / Rage / Emoji / Prompt** send exactly one HTTPS request to `api.anthropic.com`, containing just the transcribed text + the mode's system prompt. That's the only thing that ever leaves your machine.
- **The API key lives in the macOS Keychain**, not in UserDefaults, not on disk in plain text.
- **Transcripts aren't persisted.** The dev log at `~/.blitzbot/logs/blitzbot.log` logs transcript *length* only — the content itself is not written to disk.

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

Build artifacts live in `~/Downloads/blitzbot-build/`, **never** inside the project directory — the project may live in a synced folder (Nextcloud, iCloud, Dropbox) and the `.build/` folder gets hundreds of megabytes.

```bash
# Default: sign with local blitzbot-dev cert
# (permissions + keychain stay intact across rebuilds on your own machine)
./build-app.sh

# Explicit identity
./build-app.sh --sign <identity>

# Release build: ad-hoc sign + zip for GitHub release
# (portable, but end users will hit Gatekeeper on first launch)
./build-app.sh --release

# Launch
open ~/Downloads/blitzbot-build/blitzbot.app

# Regenerate the app icon (writes blitzbot.iconset/ + updates the committed AppIcon.icns)
swift tools/make-icon.swift
iconutil -c icns blitzbot.iconset -o blitzbot.app/Contents/Resources/AppIcon.icns

# Follow logs
tail -f ~/.blitzbot/logs/blitzbot.log

# Run Whisper on a file directly (debugging)
whisper-cli -m ~/.blitzbot/models/ggml-large-v3-turbo.bin -f test.wav -l de -nt -otxt -of test
```

### Signing identity

| Scenario | Command | Cert | Who can open the app |
|---|---|---|---|
| **Local dev** (your own Mac) | `./build-app.sh` | `blitzbot-dev` (self-signed, in your login keychain) | Only you — signature tied to the private key on your machine |
| **GitHub Release** | `./build-app.sh --release` | Ad-hoc (no cert) | Anyone, but first launch triggers Gatekeeper (see [First launch](#first-launch-on-macos-gatekeeper-workaround)) |
| **Custom identity** | `./build-app.sh --sign <name>` | whatever you pass | Depends on the cert |

The local `blitzbot-dev` cert is regenerated via the CLI block in [`CLAUDE.md`](CLAUDE.md) if it ever gets lost. No Keychain Access GUI needed. The cert stays on your machine — never bundled into releases.

Shipping a Gatekeeper-clean release requires the Apple Developer Program (99 €/year) and notarization. Not done here. See [First launch](#first-launch-on-macos-gatekeeper-workaround) for what end users see.

### Key files

```
Sources/blitzbot/
  blitzbotApp.swift         @main + AppDelegate + MenuBarExtra + Windows (Settings / Setup / Office)
  AppConfig.swift           UserDefaults, Keychain wrapper, vocabulary, per-mode prompts
  AppInfo.swift             Version constants and repo URL
  Mode.swift                enum (Normal…Prompt…Office) + display names + default prompts
  HotkeyManager.swift       KeyboardShortcuts integration per mode + rewriteSelection + toggleOffice
  ModeProcessor.swift       state machine: toggle → record → transcribe → formulate → paste.
                             Also owns the inline-recovery flow (RecoveryContext, 30 s timer,
                             profile-switch retry) for recoverable LLM errors.
  AudioRecorder.swift       AVAudioEngine setup + rolling PCM sample buffer + RMS level publishing
  WhisperTranscriber.swift  subprocess wrapper around whisper-cli
  LLMRouter.swift           routes LLM calls through the active profile or legacy fallback;
                             also provides a profile-override overload used by recovery retries
  LLMError.swift            structured error type (connectionFailed / authFailed / serverError /
                             other). `isRecoverable` drives the inline-recovery UI.
  AnthropicClient.swift     Claude API request/response (supports custom base URL + auth schemes);
                             throws `LLMError` for recoverable failures
  OpenAIClient.swift        OpenAI-compatible API client (same error contract)
  OllamaClient.swift        Ollama local-LLM client (same error contract)
  Paster.swift              NSPasteboard + CGEvent Cmd+V simulation
  KeychainStore.swift       API key read/write/delete — open-access ACL, no prompts ever
  KeychainPreWarmer.swift   one-time ACL migration at first launch → silent forever after
  ConnectionProfile.swift   profile model (provider, baseURL, authScheme, model, Keychain slot)
  ProfileStore.swift        @ObservedObject store — CRUD, UserDefaults persistence, Keychain I/O
  ProfileScanner.swift      scans ~/.claude-profiles/, ~/.claude/settings.json for importable configs
  ModelDiscovery.swift      fetches live model list from Anthropic /v1/models, OpenAI, Ollama
  Log.swift                 simple append-only log at ~/.blitzbot/logs/blitzbot.log
  Permissions.swift         TCC status checker for mic/accessibility/whisper
  PermissionsView.swift     onboarding wizard UI
  MenuBarView.swift         popover content (header, mode list, footer); Office row opens its window
  SettingsView.swift        TabView (General / Profile / Hotkeys / Prompts / Vocabulary / Setup / About)
  ProfilesView.swift        Profile tab UI — list, editor, scanner, quick-switcher
  RecordingHUD.swift        NSPanel + SwiftUI content for the floating recording HUD.
                             Renders the inline recovery UI (profile picker + countdown) when
                             `ModeProcessor.Status` is `.recovery`.
  OfficeView.swift          Office Mode window — dropzone, text editor, Verarbeiten button,
                             result preview, copy-to-clipboard. Calls LLMRouter directly.
  SelectionRewriter.swift   ⌘⌥0 hotkey — reads AX selection, rewrites via LLM, pastes back
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

### Ports to other platforms

blitzbot itself will stay macOS-only — the tight OS integration is a feature, not a bug, and porting would mean a parallel codebase that drifts over time.

If you want to build a sibling (Windows, Linux, iOS, Android, web) the approach is:

- New repo (or new top-level directory in this repo, e.g. `blitzbot-win/`, `blitzbot-ios/`)
- Share the things that are genuinely portable: the Claude system prompts (`Mode.swift`), the Whisper invocation, the API request shape
- Open an issue first to align on scope so we don't end up with multiple half-finished ports

I personally won't maintain ports — I can't test on OSes I don't use. But I'll happily link to and endorse a well-built sibling project from this README.

#### Windows

- Cross-platform single codebase: [Tauri](https://tauri.app) (Rust + webview) → one binary per OS, small, native-feeling
- Native: C# / WinUI 3 with `RegisterHotKey` + `SendInput` + `SetClipboardData`

#### Linux

- Native: GTK4 / Qt with `xdotool` or Wayland-specific hotkey handling, which is unfortunately still fragmented (per-compositor APIs, no unified global-hotkey story yet)

#### iOS — pre-analyzed, not built

Someone asked. We looked into it. Here's the honest take so the next person doesn't have to start from zero.

**The core blitzbot UX does not port to iOS.** Apple forbids any app from simulating keyboard input into another app. There are also no global hotkeys outside the Shortcuts app. That means "press a key, speak, text lands in whatever app has focus" — the whole point on macOS — is architecturally impossible on iOS. A Windows/Linux port is a rewrite of the OS layer; an iOS "port" is a different app category.

**The realistic iOS product is a standalone dictation app** — not a system-wide paste engine. Call it *blitzbot Notes* or similar. User flow:

1. Open app (or trigger via Shortcuts / Share Extension / Home-Screen widget)
2. Tap mic, speak, tap again
3. Pick a mode (Normal / Business / Plus / Rage / Emoji) — same prompts as macOS
4. Result shows in an editable text view
5. Copy to clipboard, share-sheet into the target app, or save as a local draft

**Suggested MVP architecture**:

```
BlitzbotApp (SwiftUI, iOS 17+)
├── RecordView         big mic button, mode picker, live waveform
├── TranscriptView     editable text, re-process with different mode, copy/share/save
├── DraftsView         local history of the last ~50 transcripts (Core Data)
├── SettingsView       API key, mode prompts, vocabulary, Whisper model size
└── ShortcutsIntents   App Intents for Shortcuts.app integration + Share Extension
```

**Top risks to validate before committing** (do these first, in this order):

1. **Whisper on-device performance.** Use [WhisperKit](https://github.com/argmaxinc/WhisperKit) or [whisper.cpp iOS bindings](https://github.com/ggerganov/whisper.cpp/tree/master/examples/whisper.objc). Measure latency + heat + battery with three model sizes (`tiny` ~75 MB, `base` ~150 MB, `small` ~480 MB). Forget `large-v3-turbo` (1.5 GB) on anything below an iPhone 15 Pro. **If this isn't fast + cool + battery-friendly, stop.**
2. **Background processing.** iOS kills background tasks after ~30 s. Long dictations plus Whisper runtime might get killed mid-transcription. Requires `UIBackgroundModes → audio` and careful state restoration.
3. **Thermal throttling.** Consecutive long transcriptions warm up the device and the OS starts throttling CPU/GPU. Measure under "normal user" conditions (back-to-back dictations, not a single clean bench).
4. **Clipboard tax.** Since iOS 14, `UIPasteboard.general` reads are surfaced to the user with a toast. Writes are fine, but a flow that reads clipboard contents would hurt trust.
5. **Shortcuts-app integration UX.** Technically nice, but onboarding is painful — users have to create a Shortcut, grant permissions, assign an activation method. Most won't bother.
6. **Custom Keyboard Extension.** Theoretical path to "type with your voice everywhere". Blocker: custom keyboards without *Full Access* cannot hit the network → no Claude call. With Full Access, users get a scary permissions dialog that tanks adoption.
7. **App Store review.** LLM-based text apps are getting stricter content-safety review. The Rage mode ("de-escalate angry text") could flag on the wrong reviewer.
8. **Model distribution size.** Bundled Whisper model bloats the `.ipa`. Downloading on first launch is cleaner but needs a resume-capable downloader + integrity check.
9. **API key storage.** iOS Keychain works fine, but sync across macOS/iOS via iCloud Keychain is non-trivial to do cleanly.
10. **Maintenance cost.** Two platforms = doubled prompt-sync effort, doubled UI to keep aligned. Without a clear user-value-add beyond the macOS app, this is scope creep.

**What's safely in scope for an MVP**:

- Dictation with Whisper on-device + mode picker
- Copy-to-clipboard + Share-sheet
- Vocabulary list synced from macOS via iCloud KV store
- TestFlight beta distribution

**What's out of scope for an MVP**:

- Simulating "paste into active app" — not possible
- Custom Keyboard — too much UX friction for v1
- Always-on background dictation — OS will kill it

**Suggested first step: one-day spike.** Before planning the whole app, build a throwaway iOS app that does *only* Whisper on-device with three model sizes and logs latency + temperature + battery delta. If the numbers are bad on realistic hardware, iOS is a bad investment and we should document that instead of shipping a slow app. If the numbers are good, greenlight the MVP planning with actual data.

If you want to take this on: fork or open an issue, propose the spike, and we'll link your repo from here.

---

## Roadmap

- [ ] Apple notarization (removes first-launch Gatekeeper workaround for end users)
- [ ] Universal binary (arm64 + x86_64)
- [ ] Push-to-talk mode
- [ ] Streaming transcription with interim text in the HUD
- [ ] Multi-mic selection in settings
- [ ] Custom "Translate" mode

Got other ideas? Open an issue.

---

## Changelog

### v1.2.4 (2026-04-18)

- **Opus 4.7 per-mode effort hints**. When the active model is `claude-opus-4-7`, each mode now sends a matching `output_config.effort` value (low / medium / high / xhigh) so the model invests reasoning proportionally to the task: Plus/Emoji = low, Rage = medium, Business/Office = high, Prompt = xhigh. Threading goes through `LLMRouter` → `AnthropicClient` without affecting Sonnet/Haiku or other providers. No UI change — the hint is derived automatically from the mode.
- **Docs cleanup**: `CLAUDE.md` refreshed — stale version pin replaced (was still v1.1.0), mode list extended to the 7th (Office), file overview synced with the full current Swift layout (adds `LLMRouter`, `LLMError`, `ConnectionProfile`, `ProfileStore`, `ProfileScanner`, `ModelDiscovery`, `OpenAIClient`, `OllamaClient`, `PrivacyEngine`, `OfficeView`, `ProfilesView`, `KeychainPreWarmer`), architecture diagram now shows the Privacy-wrap + inline-recovery branch, Settings-Tab count corrected (7 not 6), stale `LSUIElement=YES` claim replaced with the correct *activation-policy-set-programmatically* behavior. Release history in `CLAUDE.md` brought up to date with v1.2.0–v1.2.3.
- **Build-cache hygiene**: removed stray `.build/` + old v1.0.0 release zip that had accumulated inside the Nextcloud-synced project folder (rule from `CLAUDE.md` §1).

### v1.2.3 (2026-04-17)

- **Expanded PII coverage.** Privacy Mode now additionally detects and anonymizes:
  - **Postal addresses** — full street + house number + ZIP + city, via `NSDataDetector(.address)`. Replaced with `[ADRESSE_1]`, `[ADRESSE_2]`, …
  - **IBAN bank account numbers** — two-letter country code + two check digits + 11–30 alphanumeric, with or without whitespace blocks. Replaced with `[IBAN_1]`, …
  - **Credit-card numbers** — 13–19 digit sequences that pass a **Luhn checksum** check. The checksum filter rules out random long numbers (order IDs, reference numbers) that happen to match the digit count, so false-positives stay low. Replaced with `[KREDITKARTE_1]`, …
  - **MAC addresses** — colon- or dash-separated six-group hex (`aa:bb:cc:dd:ee:ff`). Replaced with `[MAC_1]`, …
  - **IPv6** — the full eight-group form is now caught alongside IPv4 under the same `[IP_n]` placeholder.

  All detection remains 100% local (Apple system frameworks + regex + a Luhn helper). No new external dependencies. The mapping popover and settings list color-code the new kinds.

### v1.2.2 (2026-04-17)

- **Privacy Mode now defaults to ON.** New installs have the pre-send anonymizer active out of the box; existing installs that previously had Privacy explicitly turned off keep their setting (persisted value wins over the registered default). Switches in Settings → Allgemein → Privacy, the menu-bar popover, the Office window header, or the recording HUD all flip the same state.
- **What the anonymizer does.** Before a request goes to an LLM, the outbound text is scanned locally (no external service) and entities in the following categories are replaced with stable placeholders:

  | Category | Detector | Placeholder shape |
  |---|---|---|
  | Personal names | Apple `NLTagger(.nameType)` | `[NAME_1]`, `[NAME_2]`, … |
  | Organizations / companies | `NLTagger` + user-supplied *Immer anonymisieren* list | `[UNTERNEHMEN_1]`, … |
  | Place names | `NLTagger` | `[ORT_1]`, … |
  | Email addresses | regex | `[EMAIL_1]`, … |
  | IPv4 addresses | regex | `[IP_1]`, … |
  | URLs | `NSDataDetector(.link)` | `[URL_1]`, … |
  | Phone numbers | `NSDataDetector(.phoneNumber)` | `[TELEFON_1]`, … |

  The model's response is rewritten back into the real terms on the way in, so your clipboard / pasted text / Office preview always shows the original values — only what leaves the machine is redacted. The mapping lives only in memory, is wiped on toggle-off and on app quit, and is never written to disk.
- **System-prompt hint rewritten** to stop the LLM from hallucinating placeholders. The previous version listed example placeholder shapes which led some models to re-anonymize plain-text names on their own (producing placeholders that had no reverse mapping). The new instruction is token-shape-based only and explicitly tells the model not to introduce placeholders of its own.
- **"Immer anonymisieren" custom term list** (Settings → Allgemein → Privacy). Terms that are always anonymized, even if `NLTagger` misses them — useful for short all-caps company abbreviations, internal project codenames, or your own last name. Case-insensitive, whole-word match. Persisted separately from the session mapping. List-based UX: each term gets its own row with a minus button; a dedicated input + plus button (Return also adds) for new entries.
- **Session mapping inline in Settings.** The Privacy section now shows the current `placeholder ↔ original` table directly in Settings → Allgemein → Privacy (color-coded by kind), in addition to the existing Office-Mode popover. Makes it easy to audit what the engine has captured without jumping into another window.
- **Menu-bar shield toggle** (small improvement). The privacy shield is now also in the menu-bar popover header next to the status indicator — gives a quick visual confirmation of the active state without having to open Office Mode, a recording HUD, or Settings. Same toggle, same state.

### v1.2.1 (2026-04-17)

- **Privacy Mode**: opt-in local anonymization for every outbound LLM call. Personal names, organizations, places (via `NLTagger`), emails / IPv4 (regex), URLs + phone numbers (`NSDataDetector`) are replaced with stable placeholders like `[NAME_1]` before leaving the app, and the model's response is rewritten back into your real terms before it hits the clipboard or gets pasted. Mapping lives in memory only, wiped on toggle-off and app quit — no persisted PII database. Toggle in Settings → Allgemein *or* via the shield pill in the Office window header and the recording HUD (same state, live entity count).
- **Model dropdown in Office.** The earlier text field is replaced with a live-fetched list of models from the current profile's endpoint (via the existing `ModelDiscovery`). Picking one overrides the model for this session only. Shows a *Profil-Standard* entry to reset.
- **Office hotkey now opt-in.** The earlier ⌘⌥O default collided with other apps; a one-time migration strips it for users still on the default. Set your own combo in Settings → Hotkeys.
- **Per-session profile switcher** in the Office header. Pick any connection profile from a dropdown for this one request, without mutating the globally active profile.
- **Dock visibility** while Office is open — `LSUIElement` removed from Info.plist and `.accessory` set programmatically in `applicationWillFinishLaunching`. Toggle to `.regular` when Office opens (Dock icon + ⌘-Tab); back to `.accessory` on close. Also handles SwiftUI session-restored Office windows via an `onAppear` hook.
- **"Office" removed from the mode picker inside the Office window** — it was the marker for the window path, not a prompt you'd pick there.

### v1.2.0 (2026-04-17)

- **Office Mode — 7th mode**: interactive selection-rewriter. Grab the selection in any app, open a window with the text pre-filled, pick a mode, optionally tweak the input, and paste the result back into the source app on ⌘↵. Clipboard fallback when no selection is active, clipboard auto-copy once processing succeeds, file-drop (txt/md/json/csv/code, 200 KB hard cap) as an alternative input for when you'd rather drop a file than highlight text. Preserves the fire-and-forget `⌘⌥0` flow untouched.
- **Inline connection recovery**: when a voice-mode LLM call fails with a recoverable error (connection, auth, 5xx), the HUD no longer hides and loses the transcript. Instead it stays open and shows a profile picker inline — the failed profile is marked and disabled, a 30 s countdown pill ticks down, pick any other profile and *Erneut senden* retries the same transcript without re-transcribing. The transcript is mirrored to the system pasteboard the instant recovery starts (safety net), and stays there even if the countdown expires.
- **Structured LLM errors** (`LLMError.swift`): every client (Anthropic, OpenAI, Ollama) now throws `.connectionFailed` / `.authFailed` / `.serverError` / `.other` instead of a plain `NSError`. `isRecoverable` decides whether the HUD offers recovery or falls through to the old auto-hiding `.fehler` state.
- **Non-voice modes are filtered out of voice UI paths**: the HUD mode pills and the hotkey dispatcher only iterate `Mode.voiceModes` (modes 1–6). Office Mode appears in the menu-bar popover with an *Öffnen* button instead of *Starte*, and in Settings → Hotkeys as a normal recorder row.

### v1.1.0 (2026-04-15)

- **Connection profiles** — replace the single-provider setup with a full profile system. Each profile holds a provider (Anthropic / OpenAI / Ollama), a base URL, an auth scheme (`x-api-key` / `Bearer` / none), and a model. Any number of profiles, quick-switch with one click.
- **New Settings tab: Profile** — list, inline editor, JSON import/export, quick-switcher chips, per-profile model discovery (live list from the endpoint).
- **Profile scanner** — *Auf diesem Mac suchen* reads `~/.claude-profiles/*.json`, `~/.claude/settings.json`, and `~/.config/claude/*.json` and offers to import them automatically.
- **LLMRouter** — central routing layer that sends every LLM call through the active profile (or falls back to legacy settings for existing installs).
- **Keychain — truly silent**: all keychain items use an open-access ACL (`SecAccessCreate` with empty trusted-apps list). macOS never prompts for a password or "Allow / Always Allow" confirmation — not on first launch, not after rebuilds, not ever. A one-time migration at first launch rewrites any legacy items; subsequent launches skip it entirely.
- **Settings window is now resizable** — drag to any size; minimum is 780 × 580 px.
- General tab simplified — provider picker and per-provider key fields moved to the new Profile tab.

### v1.0.10 (2026-04-15)

- **Text rewriting via hotkey — no voice, no Services menu required**. Select text in any app that supports Accessibility → press the configured hotkey (default `⌘⌥0`) → selection gets rewritten using the configured default mode. Result is pasted back over the selection.
- **Why this replaces v1.0.9's Services approach**: macOS Gatekeeper consistently refuses to surface Services from non-notarized apps (`spctl -a` returns `rejected`, LaunchServices sets the `launch-disabled` flag). The self-signed dev workflow can't overcome that without an Apple Developer account ($99/yr). The hotkey path uses only Accessibility, which is already granted.
- **Uses AX API first, ⌘C fallback**: reads the focused element's `AXSelectedText` attribute directly (works in most native apps). For apps that don't expose AX text (some Electron apps), it simulates ⌘C, reads the clipboard, and restores the previous clipboard contents afterwards — so your clipboard history stays intact.
- **Setting moved**: *Settings → Allgemein → „Text umschreiben (Hotkey, ohne Stimme)"* — hotkey recorder + default-mode picker (Business/Plus/Rage/Emoji/Prompt).
- NSServices entries and `ServiceProvider.swift` fully removed. The Info.plist is clean. No cross-app registration state remains.

### v1.0.9 (2026-04-15)

- **macOS Services integration — rewrite text without voice**. Select text in any app (Mail, Notes, Safari, Pages, most web inputs) → right-click → **Services** submenu → pick a blitzbot mode. The selection is replaced in place with the rewritten text. Works alongside the existing voice flow — no mic needed.
  - Six service entries: **blitzbot: Business / Plus / Rage / Emoji / Prompt** plus **blitzbot: Umschreiben (Default)** which uses a configurable default mode.
  - **New setting** in *Settings → Allgemein → Kontextmenü*: pick the default mode used by the "Umschreiben (Default)" entry + toggle whether to keep the original text in the clipboard on error.
  - Language auto-detection: the selected text is routed to the DE or EN system prompt based on a lightweight stop-word analysis, no manual switching needed.
  - If a service entry doesn't appear after install: *Settings → Allgemein → Kontextmenü → Dienste-Menü neu laden*, or log out / back in once. Apple's `pbs` daemon sometimes needs a kick.
- **Note** on compatibility: works in any app that offers Services on its context menu (TextEdit, Mail, Notes, Pages, Safari text fields, most native apps). Some Electron apps (Slack desktop, Teams) don't surface Services — use the dictation flow there instead.

### v1.0.8 (2026-04-15)

- **More visible waveform amplitude**: the yellow HUD waveform now renders peaks ~4.5× taller than before so speech is visually obvious at a glance. Samples are soft-clamped to ±1 so the wave still stays inside the 72 px HUD slot — no visual breakout.
- Idle (post-stop) grey trace also slightly stronger for better continuity between recording and idle states.

### v1.0.7 (2026-04-14)

- **Multi-LLM provider support**: switch between **Anthropic Claude**, **OpenAI ChatGPT**, and **Ollama** (local LLM). Per-provider model picker and API key. Normal mode remains local regardless of provider.
  - Anthropic: existing flow (Sonnet/Opus/Haiku, `x-api-key`).
  - OpenAI: `gpt-4o-mini` / `gpt-4o` + free-text model field, bearer auth, `/v1/chat/completions`.
  - Ollama: base URL (default `http://localhost:11434`), dynamic model list from `/api/tags` with green/red health indicator + refresh button, optional bearer auth, 300 s chat timeout for local-model latency.
- **Provider-aware error suppression**: the stale "Ollama nicht erreichbar" banner no longer leaks into the menu-bar header when another provider is active. Errors get auto-cleared when the provider changes.
- **Provider-aware key warning**: menu-bar footer warns about missing Anthropic/OpenAI keys only for the currently selected provider. Ollama shows no key warning (local use often needs none).
- **Settings → General** restructured: LLM-Provider picker at top of the tab, provider-specific section below (keys, models, URL, health), rest unchanged.

### v1.0.6 (2026-04-14)

- **Real audio waveform**: HUD waveform now draws actual PCM sample data from the microphone (Canvas-based, scrolling oscilloscope). Was a simulated bar-chart animation before.
- **Waveform always yellow during recording**: the waveform line stays consistently yellow for the entire recording session — no more grey flicker during pauses in speech.
- **"Stimme erkannt" badge**: a small green-dot pill fades in over the waveform as soon as voice input is detected, fades out on silence. Gives immediate confirmation that the mic is picking up audio.
- **Pause / Resume**: new Pause button in the HUD controls row. Audio engine pauses (keeping the WAV file open), resumes seamlessly. Auto-stop timer resets on resume.
- **Auto-Stop countdown clock**: circular draining-ring indicator next to the Pause button shows seconds remaining until auto-stop fires. Appears only when the countdown is active.
- **"Stille erkannt" delay**: the silence banner now waits 5 seconds of continuous silence before appearing (was immediate). Prevents flicker on natural pauses mid-sentence.
- **Auto-stop default: 60 seconds** (was 45 s). Settings picker now starts at 10 s.
- **Cancel button (X)**: HUD top-left now has an X button to abort a recording without pasting. Previous versions had no discard path.
- **No layout jumps**: the silence banner area has a reserved fixed height; it fades in/out via opacity (`.easeInOut 0.35 s`) instead of adding/removing from layout.
- **Auto-Execute toggle (↵)**: per-recording toggle in the HUD bottom row. When on, blitzbot simulates Return after the paste — useful for submitting messages in ChatGPT, Slack, etc. Resets to off on each new recording.
- **Security hardening**: transcript content no longer written to log file (length only). API error messages sanitized — internal error types don't leak to logs or UI. Anthropic API request timeout set to 120 s.
- **Custom prompt append mode**: Prompts tab now offers *"Replace default"* or *"Append to default"* per mode. Append is useful for "use Business style, but also be informal with colleagues".

### v1.0.5 (2026-04-14)

- **Release build pipeline clarified**: `./build-app.sh --release` now explicitly ad-hoc signs and packages a `.zip` for GitHub Releases. The local dev cert (`blitzbot-dev`) never ends up in a release artifact — it stays on the developer's machine for in-place rebuilds.
- **README**: new [First launch on macOS](#first-launch-on-macos-gatekeeper-workaround) section with the Gatekeeper workaround (right-click → Open, or `xattr -dr com.apple.quarantine` for macOS 15+ "damaged" message), and an honest note about why the app isn't notarized.
- **Signing identity table** added to the Development section so it's clear what each build mode ships.
- No code changes — this is a distribution-hygiene release.

### v1.0.4 (2026-04-14)

- **English input now actually gets English output**. Regression fix for the language-routing logic introduced in v1.0.2.
  - Root cause: `AppConfig.init()` used to eagerly populate `prompts[mode]` with the German default (via a back-compat accessor that ignored the language parameter). `prompt(for:language:)` then always took the "custom prompt" branch because the dictionary was non-empty, and the language-aware default on the next line was never reached. The bug was silently re-persisted into UserDefaults on every `save()`.
  - Fix: split custom user overrides (`customPrompts`) from defaults. A missing key now means "use language-appropriate default". One-time migration in `init()` strips any previously auto-persisted German-default strings so existing installs recover automatically. Real user customizations (differ from the German default) are preserved.
- Prompts tab in Settings now shows which language's default is active when no override is set, and offers a "Reset to default" button if you did override.

### v1.0.3 (2026-04-14)

- **Mode 6 repurposed**: was *AI Command* (Claude executes the instruction). Now *Prompt* — Claude turns a loose spoken idea into a clean, tool-agnostic prompt you paste into your AI of choice. Output is the prompt, not the result. Helpful when you know what you want but haven't yet structured it.
- **Language detection hardened**: `whisper-cli -l auto` mislabels short English utterances as German more often than expected. v1.0.3 adds a stop-word-ratio content detector on top: if the transcript clearly looks English or German, that overrides Whisper's metadata. Prompt routing now follows the content, not Whisper's self-assessment.

### v1.0.2 (2026-04-14)

- **AI Command mode (6th mode, `⌘⌥6`)**: dictate an instruction and Claude executes it instead of polishing the wording. Write code, run an analysis, answer a factual question — the result gets pasted directly. Ideal for quick "write me a Python function that…" or "summarize this in three bullets" without opening a chat UI.
- **Automatic language detection**: Whisper now auto-detects the spoken language (previously hardcoded to German). The Claude polish runs in the same language. German and English prompts ship as defaults for all modes.
- **Manual language override**: Settings → General → *Output language* with *Auto / Deutsch / English* — forces transcription and Claude output to a specific language regardless of what was spoken.
- **HUD language badge**: while recording, a small `DE` or `EN` pill shows next to the mode name so you see what will actually be written.
- HUD width grew from 480 → 560 px to fit the 6th mode pill cleanly.

### v1.0.1 (2026-04-14)

- **HUD mode switcher**: five clickable mode pills + a red Stop button inside the floating recording HUD. Switch modes or end the recording without reaching for the keyboard. Panel still doesn't steal focus.
- **Cmd+Q / Quit fixed**: the *Beenden* button in the menu bar popover now properly terminates the app under the accessory activation policy (`keyboardShortcut("q", modifiers: .command)` added).
- **Settings UI refactor**: replaced the stock macOS `TabView` with a custom icon toolbar at the top of the settings window. Six colored tiles (General/Hotkeys/Prompts/Vocabulary/Setup/About), clearer affordance, more native look.
- **Hotkey migration**: when adding Business at position 2, the existing stored bindings for Plus/Rage/Emoji would have collided with the new Business default (⌘⌥2) and left Emoji unbound. v1.0.1 resets all mode shortcuts to the v1.0.1 defaults exactly once on first launch, guarded by a one-time migration flag. Subsequent user customizations persist normally.
- **Build hygiene**: `./build-app.sh` now builds into `~/Downloads/blitzbot-build/` via `swift build --scratch-path` instead of leaving `.build/` inside the (possibly sync'd) project directory. Also updates `/Applications/blitzbot.app` in place.

### v1.0.0 (2026-04-14)

Initial public release.

- 5 modes: Normal (offline), Business, Plus, Rage, Emoji with individual hotkeys (default `⌘⌥1-5`)
- Live mode switch while recording
- Floating HUD with timer + live waveform + mode badge
- Custom hotkeys per mode via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) recorder
- Editable system prompts per mode
- Vocabulary list fed to Whisper as context for proper nouns and jargon
- Auto-updater via GitHub Releases (check from Settings → About)
- Setup wizard for macOS permissions
- DE + EN UI
- Persistent log at `~/.blitzbot/logs/blitzbot.log`
- MIT license

---

## License

MIT — see [LICENSE](LICENSE).

© 2026 blitzbot contributors.
