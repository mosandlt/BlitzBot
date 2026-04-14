# blitzbot ⚡

Lokale Speech-to-Text-Menubar-App für macOS. Diktieren → Transkribieren → Auto-Paste in jede App.

**Inspiriert** von: *"Nie wieder Tippen! Meine eigene Speech-to-Text App (Claude Code)"* von Christoph Magnussen → https://www.youtube.com/watch?v=vVTl1dqPL0k

- **STT**: whisper.cpp lokal (offline, privat, keine Cloud für Normal-Modus)
- **LLM-Glättung** (Business/Plus/Rage/Emoji): Anthropic Claude API
- **Ein einziger Key**: Anthropic — mehr nicht
- **Open Source**: MIT

---

## 5 Modi

| Pos | Modus      | Default-Hotkey | Tagline                                | Was passiert |
|-----|------------|----------------|-----------------------------------------|--------------|
| 1   | **Normal**   | `⌘⌥1`          | Sprache rein. Text raus.                | Whisper-Transkript roh, **keine Cloud**, null Kosten |
| 2   | **Business** | `⌘⌥2`          | Sprache rein. Businesstauglich raus.    | Claude → klar, höflich, strukturiert (Mails, Kunden, LinkedIn) |
| 3   | **Plus**     | `⌘⌥3`          | Geschrieben sprechen.                   | Claude → Füllwörter raus, Grammatik glatt, **deine Stimme bleibt** |
| 4   | **Rage**     | `⌘⌥4`          | Frust rein. Entspannt raus.             | Claude → Beleidigungen weg, Kritik bleibt scharf |
| 5   | **Emoji**    | `⌘⌥5`          | Sprache rein. Text mit Emojis raus.     | Original + dezente Emojis |

Alle Hotkeys in den Einstellungen individuell belegbar.
**Modus-Switch während Aufnahme**: anderen Hotkey drücken → Aufnahme läuft weiter, Verarbeitung im neuen Modus.

---

## Installation

### 1. Whisper + Modell

```bash
./setup-whisper.sh
```

Installiert `whisper-cpp` via Homebrew und lädt `ggml-large-v3-turbo.bin` nach `~/.blitzbot/models/` (~1.5 GB, außerhalb des Projekts).

### 2. Bauen & starten

Aus dem Source:

```bash
swift build -c release
cp .build/release/blitzbot blitzbot.app/Contents/MacOS/blitzbot
codesign --force --deep --sign - blitzbot.app
open blitzbot.app
```

Oder fertiges Release holen: https://github.com/mosandlt/BlitzBot/releases

### 3. Berechtigungen

Beim ersten Start öffnet sich das Setup-Fenster. Freigabe:
- **Mikrofon** (für die Aufnahme)
- **Bedienungshilfen** (damit Cmd+V automatisch pastet)

Wenn das Setup-Fenster weg ist: Einstellungen → **Setup**-Tab → öffnen.

### 4. API-Key

Einstellungen → **Allgemein** → Anthropic API Key → https://console.anthropic.com/settings/keys → einfügen → Speichern. Liegt in macOS Keychain, nie im Repo.

Normal-Modus braucht **keinen** Key.

---

## Bedienung

1. Fokus in Ziel-App setzen (Notes, Mail, Slack, LinkedIn, …)
2. Hotkey drücken → HUD erscheint zentral (Timer, Waveform, Modus)
3. Reden
4. Gleichen Hotkey nochmal → Text landet per Cmd+V in der Ziel-App

Während der Aufnahme kannst du einen anderen Modus-Hotkey drücken — der Modus wechselt live.

---

## Datenfluss

```
Mikrofon → AVAudioEngine → /tmp/*.wav (nur Sekunden)
        → whisper-cli (lokal, offline)
        → Text
        → ggf. Claude API (Business/Plus/Rage/Emoji)
        → NSPasteboard + Cmd+V-Simulation
        → Text in aktiver App
```

- Normal-Modus: **null** API-Calls, null Kosten, voll offline
- Andere Modi: einmaliger Claude-Call pro Diktat (Sonnet ~$3/Mio Input-Tokens → praktisch kostenlos)

---

## Features

- **Floating-HUD** in Bildmitte während Aufnahme: Timer, 22-Band Live-Waveform, Modus-Badge, Status — klaut keinen Fokus
- **Vokabular-Liste** in Einstellungen: Eigennamen/Fachbegriffe (z.B. Firmennamen, Marken, Personennamen) → Whisper schreibt sie korrekt
- **Individuelle Hotkeys** pro Modus
- **Editierbare System-Prompts** pro Modus
- **Deutsch + Englisch** UI (nach System-Sprache)
- **Auto-Updater**: Settings → Über → "Jetzt prüfen" (via GitHub Releases)
- **Setup-Wizard** bei fehlenden Permissions, immer erreichbar unter Einstellungen → Setup

---

## Sicherheit & Privatsphäre

- Audio landet als `.wav` in `/tmp/blitzbot-<uuid>.wav` und wird **sofort nach Transkription gelöscht**
- API-Key in macOS Keychain, nicht in Files
- Transkripte werden **nicht** dauerhaft gespeichert
- Normal-Modus: **keine** Daten verlassen dein Gerät
- Andere Modi: genau ein Request an Anthropic mit dem transkribierten Text, sonst nichts

---

## Troubleshooting

- **Icon da, aber Hotkey tut nichts** → Einstellungen → Setup → Bedienungshilfen prüfen. Jeder Rebuild der App invalidiert die Berechtigung (ad-hoc Codesigning).
- **Text im Clipboard, aber kein Auto-Paste** → Bedienungshilfen-Permission fehlt.
- **"Kein API-Key"-Warnung unten in Popover** → Einstellungen → Allgemein → Key eintragen.
- **`whisper-cli` nicht gefunden** → Pfad in Einstellungen → Allgemein → Whisper anpassen, oder `./setup-whisper.sh` nochmal.
- **Log prüfen**: `tail -f ~/.blitzbot/logs/blitzbot.log`

---

## Entwicklung

Siehe [`CLAUDE.md`](CLAUDE.md) für Projekt-Regeln (Zwei-Prompt-Workflow, Build-Zyklus, Permissions-Fallstricke, Architektur).

```bash
# Build
swift build -c release

# Icon regenerieren
swift tools/make-icon.swift && iconutil -c icns blitzbot.iconset -o blitzbot.app/Contents/Resources/AppIcon.icns

# Deploy
cp .build/release/blitzbot blitzbot.app/Contents/MacOS/blitzbot && codesign --force --deep --sign - blitzbot.app && open blitzbot.app
```

Logs: `~/.blitzbot/logs/blitzbot.log`

---

## Lizenz

MIT — siehe [LICENSE](LICENSE).
