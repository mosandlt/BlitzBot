# blitzbot

Lokale Speech-to-Text-App für macOS — diktieren statt tippen, systemweit in jede App einfügen.

**Inspiration**: Video *"Nie wieder Tippen! Meine eigene Speech-to-Text App (Claude Code)"* von Christoph Magnussen — https://www.youtube.com/watch?v=vVTl1dqPL0k

**Ziel**: eigene Variante bauen, nicht den Code kopieren.

---

## Wie wir hier arbeiten (Claude, das hier zuerst lesen)

### Zwei-Prompt-Regel — **niemals überspringen**

Bevor du für ein neues Feature Code schreibst, läuft immer erst der **Kritik-Pass**. Das ist der wichtigste Punkt in dieser Datei.

**Prompt 1 — Kritische Voranalyse** (erzeugt *keinen* Code, nur Risiko-Map):

> Bevor du Code erzeugst, agiere als Product Engineer für macOS und prüfe dieses Vorhaben kritisch.
>
> **Vorhaben:** [Feature-Beschreibung]
>
> **Deine Aufgabe:**
> - Zerlege das Vorhaben in technische Teilprobleme
> - Nenne die 10 größten Risiken für einen alltagstauglichen MVP
> - Erkläre insbesondere, welche macOS-Berechtigungen und Systemgrenzen relevant sind
> - Unterscheide klar zwischen:
>   1. sicher machbar im MVP
>   2. wahrscheinlich machbar mit Edge Cases
>   3. riskant oder app-übergreifend unzuverlässig
> - Schlage danach eine konkrete MVP-Architektur vor
> - Empfiehl, welche Teile du zuerst prototypen solltest
>
> **Wichtig:** Schreibe für ein nicht-technisches Gründerteam. Keine unnötige Fachsprache. Klare Entscheidungen statt allgemeiner MVP-Phrasen.

**Prompt 2 — Implementierung** (erst nach Prompt-1-Ergebnis):

1. Feature-Idee mit Erkenntnissen aus Prompt 1 präzisieren
2. In Claude Code Auto Mode einsetzen
3. Subagents parallel launchen (Architektur-Scan, Backend-Scan, Implementation)
4. Nach Deploy: Codex als Code-Review-Zweitmeinung

### Auto Mode

- Bevorzugt gegenüber Plan Mode (der ist laut Video zu träge)
- Aktivieren: `Shift+Tab` bis unten `auto mode on` erscheint, oder Start mit `claude --mode=auto`
- **Empfohlenes Setup: Opus 4.6 (1M context) + high effort**

### Allowlist

`.claude/settings.json` pflegen. Auf die Allowlist dürfen: `swift build`, `xcodebuild`, `git status`, `git diff`, Lese-Commands. **Nicht** auf die Allowlist: `rm`, `git push --force`, `brew install -g`, `sudo`, destruktive Git-Operationen.

### Codex-Zweitmeinung

Codex läuft als Plugin in Claude Code. Claude ist opinionated und legt los; Codex sagt "pass auf, vielleicht drei Schritte zurück". Für Architektur-Entscheidungen und Review nutzen.

---

## Workflow-Regeln (gelernte Praxis)

1. **Build-Zyklus — Build-Artefakte gehören nach `~/Downloads/blitzbot-build/`, NIE ins Projekt**:
   ```
   ./build-app.sh                    # baut komplett nach ~/Downloads/blitzbot-build/blitzbot.app
   open ~/Downloads/blitzbot-build/blitzbot.app
   ```
   **Grund**: Projekt liegt in Nextcloud. `.build/` wird mehrere 100 MB groß → würde die Synchronisation blockieren, Diffs ersticken, Batterie belasten.
   - `swift build --scratch-path "$HOME/Downloads/blitzbot-build/swift"` ist der Kern
   - Die .app wird aus dem committeten Template (`blitzbot.app/Contents/Info.plist` + `Resources/`) neu zusammengebaut, Binary aus dem Scratch-Path
   - Niemals `swift build` ohne `--scratch-path` aus dem Projekt laufen lassen, sonst landet `.build/` wieder im Nextcloud-Ordner
   - Binary ersetzen ohne re-codesign = gebrochene Signatur

   **Nach jedem Build Dev-App in `/Applications` aktualisieren UND starten**, damit der User sofort die Änderung sieht — nicht nur den Downloads-Build:
   ```
   pkill -f "/Applications/blitzbot.app" 2>/dev/null
   ./build-app.sh --sign blitzbot-dev
   ditto ~/Downloads/blitzbot-build/blitzbot.app /Applications/blitzbot.app
   codesign --force --deep --sign blitzbot-dev /Applications/blitzbot.app
   touch /Applications/blitzbot.app    # LaunchServices refresh
   open /Applications/blitzbot.app
   ```
   Dann im Log prüfen (`~/.blitzbot/logs/blitzbot.log`), dass `applicationDidFinishLaunching` + `Hotkeys registered` erscheinen.

   **WICHTIG: immer `--sign blitzbot-dev`, NIE wieder ad-hoc (`--sign -`).** Das selbst-signierte Dev-Cert `blitzbot-dev` liegt in der Login-Keychain (mit Codesign-Trust gesetzt). Ad-hoc Signing invalidiert bei jedem Re-Sign die TCC-Permissions (Accessibility, Input Monitoring) UND die Keychain-ACL (Anthropic-API-Key). Der User muss dann jedes Mal alles neu bestätigen. Mit dem stabilen Cert überleben diese Permissions alle Rebuilds.

   Falls das Cert mal nicht da ist (`security find-identity -p codesigning -v` zeigt 0): neu erstellen via
   ```
   openssl req -x509 -newkey rsa:2048 -keyout /tmp/k.pem -out /tmp/c.pem -days 3650 -nodes \
     -subj "/CN=blitzbot-dev" -addext "extendedKeyUsage=critical,codeSigning"
   openssl pkcs12 -export -inkey /tmp/k.pem -in /tmp/c.pem -out /tmp/c.p12 \
     -passout pass:blitzbot -name "blitzbot-dev" -legacy
   security import /tmp/c.p12 -k ~/Library/Keychains/login.keychain-db -P blitzbot \
     -T /usr/bin/codesign -T /usr/bin/security
   security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s -k "" \
     ~/Library/Keychains/login.keychain-db
   security add-trusted-cert -r trustRoot -p codeSign \
     -k ~/Library/Keychains/login.keychain-db /tmp/c.pem
   rm /tmp/k.pem /tmp/c.pem /tmp/c.p12
   ```

2. **Logging**: Nie `print()` oder `FileHandle.standardError` — **immer `Log.write(...)`** aus `Log.swift`. Schreibt nach `~/.blitzbot/logs/blitzbot.log`, überlebt App-Neustart, ist per `tail` beobachtbar.

3. **Lifecycle**: `applicationDidFinishLaunching` im `NSApplicationDelegate` (via `@NSApplicationDelegateAdaptor`) ist der einzige verlässliche Startpunkt. `.onAppear` auf `MenuBarExtra`-Label feuert **nicht** zuverlässig.

4. **Permissions-Fallstrick** (wichtig!):
   - Jedes `codesign --force --sign -` erzeugt neuen CDHash → macOS TCC invalidiert alle System-Permissions (Accessibility, PostEvent). Mikrofon (user TCC) überlebt.
   - **Dauerhafte Lösung**: stabiles Self-Signed-Cert aus *Keychain Access → Zertifikatsassistent → Zertifikat erstellen* (Name `blitzbot-dev`, Typ Code Signing, Selbstsigniert, "Immer vertrauen"). Dann `codesign -s blitzbot-dev ...` und Permissions bleiben.
   - Bis dahin: User muss nach jedem Rebuild Accessibility re-granten. Setup-Fenster + Settings-Tab "Setup" bietet Shortcut zu Systemeinstellungen.

5. **SourceKit-Warnungen nach Edits sind oft stale.** Immer `swift build` laufen lassen und darauf vertrauen, nicht blind den SourceKit-Fehlern folgen.

6. **SwiftUI-Fokus-Falle**: Alle floating Panels (HUD, Setup) müssen `NSPanel` mit `.nonactivatingPanel` + `ignoresMouseEvents` sein. Sonst klaut das Panel den Fokus und `Cmd+V` pastet ins falsche Ziel.

7. **KeyboardShortcuts-Package**: gepinnt auf `<1.15.0`. Version 2.x nutzt `#Preview`-Macros die einen Xcode-only `PreviewsMacros`-Plugin brauchen → SPM-Build bricht.

8. **Dependencies**: Keine weiteren externen Packages ohne Rückfrage. Jede Dep vergrößert die Bundle-Size und erhöht Supply-Chain-Risiko.

9. **Vor jedem Push: harte PII/Secrets-Sperre — NIEMALS übersprungen**:
   - Bei JEDEM `git push` (ohne Ausnahme) vorher `bosch-secrets-scan` plus Pattern-Grep auf den Diff laufen lassen.
   - Wenn irgendein Treffer: Push abbrechen, User informieren, Datei aus Commit entfernen bevor gepusht wird.
   - Als kritisch gilt alles aus den Kategorien: API-Keys / Tokens / JWT-Prefixe, Private Keys, Personennamen, Firmen-Emails, lokale User-Pfade, interne IP-Bereiche, WiFi-SSIDs, MAC-Adressen, interne Hostnames, Device-IDs, Signal/Telefonnummern, sowie Inhalte aus den lokalen Notiz-Files.
   - Die **exakte Pattern-Liste** steht ausschließlich in `.git/hooks/pre-push` (repo-lokal, nicht committed) — dort als Regex gepflegt, damit diese Datei selbst clean bleibt.
   - Der Hook blockt den Push mechanisch. Nicht löschen, nicht mit `--no-verify` umgehen.
   - **Verantwortung**: Wenn trotzdem etwas durchrutscht → `git filter-repo` oder BFG zum Scrubben der History + Force-Push nach User-Freigabe. Betroffene Keys rotieren. Nie einfach "im nächsten Commit löschen" — der alte Commit bleibt für immer in der History sichtbar.

9a. **Vor jedem Push: README auf den aktuellen Stand bringen.** Ohne Ausnahme. Die README ist die Visitenkarte des Repos und MUSS vor jedem `git push` widerspiegeln was im Code steht:
   - Neue Features → in die passenden Sektionen (Modi-Tabelle, Usage, Settings) einarbeiten
   - Breaking Changes / UI-Änderungen → unter `## Changelog` als neue Version dokumentieren (mit Datum, knappen Stichpunkten)
   - Entfernte oder umbenannte Funktionen → raus aus der README
   - Neue Dateien/Module → in die Datei-Übersicht unter `## Development → Key files`
   - TOC (`## Table of contents`) synchron halten
   - Keine "TODO: update README" Commits. Lieber ein Feature verschieben als die Doku verkommen lassen.

9b. **GitHub Release Notes: immer bilingual (Deutsch + English).** Keine Ausnahme. Muster:
   ```
   > 🇩🇪 Deutsch unten · 🇬🇧 English below

   ---

   ## 🇬🇧 English
   <notes in English>

   ---

   ## 🇩🇪 Deutsch
   <notes in German>
   ```
   Zuerst English, dann Deutsch (GitHub schneidet nach oben ab bei kurzer Fenstergröße — Englisch ist die breitere Leser-Basis). Inhalt muss identisch sein, nicht bloß übersetzte Überschriften. Wenn ein Begriff nur in einer Sprache Sinn ergibt (z.B. UI-Label in Deutsch), in Klammern ergänzen. Bei nachträglichen Edits an Release Notes via `gh release edit`: beide Sprach-Blöcke aktualisieren, nicht nur einen.

10. **UI-Änderungen im echten Build testen** — nicht nur Code lesen. Nach jedem UI-Change: rebuild, deploy, Hotkey drücken, Screenshot/Verhalten prüfen.

11. **Commit-Stil**: Kleine, testbare Commits mit klaren Messages. Kein "wip", kein "fix stuff".

---

## Produkt

### Idee

- **Menubar-App** (Icon oben rechts, kein Dock-Eintrag — `LSUIElement=YES`)
- Läuft permanent im Hintergrund, systemweit verfügbar
- Globaler Hotkey → Aufnahme → Transkription → Auto-Paste in die aktive App
- Funktioniert in LinkedIn, Slack, Mail, WhatsApp Web — überall
- Toggle (drücken/erneut drücken zum Stoppen); Modus kann während Aufnahme gewechselt werden

### Modi (Default-Hotkeys — in Settings individuell belegbar)

| Pos | Modus    | Hotkey | Tagline                              | Verhalten |
|-----|----------|--------|--------------------------------------|-----------|
| 1   | Normal   | `⌘⌥1`  | "Sprache rein. Text raus."          | Wort-für-Wort, unverändert, **kein** LLM-Call |
| 2   | Business | `⌘⌥2`  | "Sprache rein. Businesstauglich raus." | LLM → klar, höflich, strukturiert für Business-Kommunikation |
| 3   | Plus     | `⌘⌥3`  | "Geschrieben sprechen."             | LLM → Füllwörter/Grammatik glätten, Stimme bleibt |
| 4   | Rage     | `⌘⌥4`  | "Frust rein. Entspannt raus."       | LLM → Beleidigungen raus, Kritik bleibt |
| 5   | Emoji    | `⌘⌥5`  | "Sprache rein. Text mit Emojis raus." | Original + dezente Emojis |
| 6   | Prompt   | `⌘⌥6`  | "Idee rein. Prompt raus."           | LLM verwandelt lose gesprochene Idee in einen sauberen, tool-agnostischen Prompt (ChatGPT/Claude/Cursor/Aider/Copilot/Gemini). Output ist der Prompt selbst, nicht das Ergebnis. |

Jeder Modus hat anpassbaren System-Prompt in den Settings (leer = Sprach-abhängiger Default).

**Sprach-Routing (DE / EN)**: Whisper läuft mit `-l auto`, Content-basierter Stopword-Detector entscheidet finale Sprache (weil Whispers eigene Auto-Detect auf kurzen Clips unzuverlässig ist). Priorität in `ModeProcessor.resolveLanguage`: user-Override aus Settings > Content-Detector > Whisper-Metadata. Claude-Prompts gibt es pro Modus in zwei Sprachen (`defaultSystemPromptGerman` / `defaultSystemPromptEnglish` in `Mode.swift`).

### UI-Copy-Regeln

- Taglines immer nach dem Muster **"X rein. Y raus."** — prägnant, keine Fachsprache
- Menubar-Icon reflektiert Status: `bolt.fill` (bereit), `record.circle.fill` rot+REC (aufnehmend), `waveform` gelb (verarbeitend), `checkmark.circle.fill` grün (fertig), `exclamationmark.triangle.fill` orange (Fehler)
- Menubar-Popover minimal: Header + Modi-Liste + Footer (Quit, API-Key-Warning)
- Settings-Zahnrad im Popover-Header oben rechts
- **Deutsche UI** ist Default, **Englisch** via Localizable.strings
- Deutsche User-Logs (`"Aufnahme läuft"`), englische Identifier/Code (`startRecording`)
- HUD (Floating-Panel während Aufnahme): zentral, Modus-Badge + Timer mm:ss + Waveform + Status

### Settings-UI (Tabs)

1. **Allgemein**: Anthropic-API-Key (Keychain), Claude-Modell-Auswahl, Whisper-Binary + Modell-Pfad
2. **Hotkeys**: pro Modus `KeyboardShortcuts.Recorder`
3. **Prompts**: System-Prompt pro Modus editierbar
4. **Vokabular**: Eigennamen/Fachbegriffe-Liste (wird als `--prompt` an Whisper)
5. **Setup**: Shortcut zu Permissions-Fenster
6. **Über**: Version, Lizenz, Auto-Update-Check

---

## Technik

### Stack

- **Sprache**: Swift 5.9+, SwiftUI (macOS 13+)
- **Build**: Swift Package Manager (`swift build`), nicht Xcode-Projekt
- **STT**: whisper.cpp lokal via `whisper-cli` CLI (nicht Whisper API) — offline, privat
- **LLM-Verarbeitung** (Business/Plus/Rage/Emoji/Prompt): Anthropic Claude API
- **Hotkeys**: `KeyboardShortcuts` von Sindre Sorhus (SPM, `<1.15.0`)
- **Auto-Paste**: `NSPasteboard` + `CGEvent` Cmd+V-Simulation (Accessibility-Permission)
- **Audio**: `AVAudioEngine` mit Tap für RMS-Pegel (für HUD-Waveform)
- **Floating-UI**: `NSPanel` (`nonactivatingPanel`, `fullScreenAuxiliary`, `canJoinAllSpaces`)

### Architektur

```
Hotkey-Event (KeyboardShortcuts)
   ↓
ModeProcessor.toggle(mode)          ← Mode-Switch während Aufnahme via gleiche Logik
   ↓
AudioRecorder.start() [AVAudioEngine → /tmp/*.wav, Pegel-Publish an HUD]
   ↓ [User redet, Hotkey nochmal]
Stop-Tap → wav fertig geschrieben
   ↓
WhisperTranscriber.transcribe() [whisper-cli -l de --prompt "<vocab>" …]
   ↓
Mode-Router (Prompt pro Sprache aus Mode.swift):
   ├─ Normal   → Text direkt (kein Cloud-Call)
   ├─ Business → Claude (business prompt, DE oder EN)
   ├─ Plus     → Claude (glätten, Stimme behalten)
   ├─ Rage     → Claude (entschärfen, Kritik bleibt)
   ├─ Emoji    → Claude (Emojis ergänzen)
   └─ Prompt   → Claude (Idee → sauberer Prompt für ein anderes AI-Tool)
   ↓
Paster.pasteText() → NSPasteboard + CGEvent Cmd+V (120ms Delay, cgAnnotatedSessionEventTap)
   ↓
Text erscheint in aktiver App
```

### Dateistruktur

```
Sources/blitzbot/
  blitzbotApp.swift        ← @main + AppDelegate + MenuBarExtra + Windows
  AppInfo.swift            ← Version, Repo-URL, Releases-API-URL (zentrale Konstanten)
  AppConfig.swift          ← UserDefaults, Keychain, Vokabular, outputLanguage, customPrompts
  Mode.swift               ← enum mit displayName, tagline, symbol, defaultSystemPrompt(for:) DE/EN
  HotkeyManager.swift      ← KeyboardShortcuts-Bindings pro Mode + v1.0.1-Migration
  ModeProcessor.swift      ← State-Machine, Timer, Dispatch an Whisper+Claude, resolveLanguage + Content-Detektor
  AudioRecorder.swift      ← AVAudioEngine + RMS-Level-Publishing für HUD-Waveform
  WhisperTranscriber.swift ← subprocess wrapper um whisper-cli, JSON-Parse für erkannte Sprache
  AnthropicClient.swift    ← Claude API call
  Paster.swift             ← NSPasteboard + CGEvent Cmd+V-Simulation (nonactivating)
  KeychainStore.swift      ← API-Key in Keychain (service de.blitzbot.mac, account anthropic-api-key)
  Log.swift                ← ~/.blitzbot/logs/blitzbot.log (append-only, per-line timestamp)
  Permissions.swift        ← TCC-Status-Checker (Mic/Accessibility/Whisper-Binary/Whisper-Model)
  MenuBarView.swift        ← Popover-Content (Header + Mode-List + Footer mit Quit)
  SettingsView.swift       ← Custom Icon-Toolbar (6 Tabs: Allgemein/Hotkeys/Prompts/Vokabular/Setup/Über)
  PermissionsView.swift    ← Onboarding-Wizard (Mic, Accessibility, Whisper-Binary, Whisper-Model)
  RecordingHUD.swift       ← NSPanel Floating-HUD mit Timer + Waveform + Mode-Pills + Stop-Button + Sprach-Badge
  Updater.swift            ← GitHub-Releases-API-Check + Download + Install-in-place

blitzbot.app/Contents/
  Info.plist               ← Bundle-ID de.blitzbot.app, LSUIElement=YES, Version, CFBundleLocalizations
  Resources/
    AppIcon.icns           ← Icon (generiert via tools/make-icon.swift)
    en.lproj/
      Localizable.strings  ← englische Strings (mode names + taglines bisher, rest via defaultValue)

tools/
  make-icon.swift          ← rendert blitzbot.iconset → AppIcon.icns

build-app.sh               ← Default (blitzbot-dev) / --sign <id> / --release (ad-hoc zip)
setup-whisper.sh           ← brew install whisper-cpp + Modell-Download

.git/hooks/pre-push        ← repo-lokal, scannt Diff auf Secrets + PII (regel 9)
.git/info/exclude          ← repo-lokal, git-ignore ohne Push (für private Session-Notizen)
```

---

## Sicherheit & Privatsphäre

- **Audio-Dateien**: `/tmp/blitzbot-<uuid>.wav` — nach Transkription **immer** löschen (`defer` in `WhisperTranscriber.transcribe`). Niemals in `~`, niemals als Backup.
- **API-Keys**: Keychain (`KeychainStore.swift`). Nie `UserDefaults`. Nie ins Repo. Niemals loggen.
- **Transkripte nicht loggen**: im Dev-Log sind Transkripte nur zum Debuggen drin — für Release `Log.write("TRANSCRIPT: …")`-Calls entfernen oder auf `len=<n>` reduzieren.
- **Cloud-Calls** (Claude): User weiß durch README + Settings, dass Business/Plus/Rage/Emoji/Prompt den Text an Anthropic schicken. Normal-Modus macht keine Cloud-Calls.
- **Vor jedem Push**: `bosch-secrets-scan` laufen lassen.

## Nicht tun

- Kein Source-Code von fremden Tools kopieren — nur inspirieren
- Keine LaunchAgents / Auto-Start ohne User-Zustimmung
- Kein `sudo` ohne Rückfrage
- Keine globalen Installs (`brew install -g`, `npm -g`) ohne Freigabe
- Keine destruktiven Git-Operationen (force-push, reset --hard) automatisch
- Kein Re-Sign der App ohne Grund — jedes Re-Sign kostet den User Accessibility-Permissions
- Keine Dependencies adden ohne Rückfrage

---

## Aktueller Stand

- **Aktuelle Version**: v1.0.8 (Stand: 2026-04-15)
- **GitHub**: https://github.com/mosandlt/BlitzBot (MIT, public)
- **Release-Artifakt**: ad-hoc signiert via `./build-app.sh --release` → `.zip` auf GitHub Releases. End-User müssen beim ersten Start Rechtsklick → Öffnen (Gatekeeper), weil nicht notarisiert.
- **Dev-Signing**: `blitzbot-dev` Cert (self-signed, in Login-Keychain, Codesigning-Trust gesetzt). Mit diesem Cert signierte Rebuilds überleben TCC + Keychain-ACL.
- **Bundle-ID**: `de.blitzbot.app`
- **Keychain-Service**: `de.blitzbot.mac` / Accounts `anthropic-api-key`, `openai-api-key`, `ollama-api-key`
- **LLM-Provider**: Anthropic (default), OpenAI, Ollama — umschaltbar in Settings → Allgemein
- **iOS Sub-Projekt**: `blitzbot-ios/` (Scaffold, nicht released; Hold-to-Talk + Share Extension + Siri Shortcut)
  - Simulator: `./run-sim.sh` — baut + startet (SFSpeechRecognizer geht im Sim NICHT, nur auf echtem iPhone)
  - Mac nativ: `./run-mac.sh` — braucht Apple-ID in Xcode (Personal Team, gratis)

## Release-Historie (Kurz)

| Version | Kernänderung |
|---|---|
| v1.0.8 | Wellenform-Amplitude deutlich erhöht (4.5× Gain, geclampt auf ±1) |
| v1.0.7 | Multi-LLM: Anthropic/OpenAI/Ollama, Provider-Picker, dynamische Ollama-Modelliste, stale-Error-Fix |
| v1.0.6 | Echte Wellenform (Canvas/PCM), Pause/Resume, Auto-Stop-Uhr, Stille-Verzögerung 5s, 60s Default, Cancel-Button, Auto-Execute, Security-Fixes |
| v1.0.5 | Ad-hoc Release-Pipeline, Gatekeeper-Workaround-Docs, bilingual Release Notes |
| v1.0.4 | Fix: englischer Input → englischer Output (customPrompts sauber getrennt von Defaults) |
| v1.0.3 | Mode 6 repurposed: "AI Command" → "Prompt" (Prompt-Optimizer); Content-Sprach-Erkennung als Whisper-Override |
| v1.0.2 | 6. Modus (AI Command), automatische Sprach-Erkennung (DE/EN), manueller Override |
| v1.0.1 | HUD Mode-Switcher + Stop-Button, Cmd+Q-Fix, Settings-UI mit Icon-Toolbar, Hotkey-Migration |
| v1.0.0 | Initiales Release: 5 Modi (Normal/Business/Plus/Rage/Emoji), Floating-HUD, Vokabular, Auto-Updater |

## Offene Punkte

- Apple Developer Program + Notarisierung (wenn User-Basis >0 wird, 99 €/Jahr, ersetzt ad-hoc)
- Evtl. Hold-to-Talk als Alternative zu Toggle
- Lokales Whisper-Modell: bereits gesetzt (large-v3-turbo) — evtl. kleineres als Option
- iOS-App testen + releasen (Scaffold existiert, nicht released)
- Hyperspace LLM Proxy Integration (SAP-intern, geparkt)
- Launch-at-Login Toggle via SMAppService
