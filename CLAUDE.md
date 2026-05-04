# blitzbot

Lokale Speech-to-Text-App für macOS — diktieren statt tippen, systemweit in jede App einfügen.

**Inspiration**: Video *"Nie wieder Tippen! Meine eigene Speech-to-Text App (Claude Code)"* von Christoph Magnussen — https://www.youtube.com/watch?v=vVTl1dqPL0k. **Ziel**: eigene Variante bauen, nicht den Code kopieren.

Release-Historie: `docs/CHANGELOG.md`. Workflow-Details ausgelagert in `.claude/skills/{build-deploy,dev-cert-regen,pre-push-scan,release,usage-report}/SKILL.md`.

---

## Wie wir hier arbeiten

### Zwei-Prompt-Regel — niemals überspringen

Bevor für ein neues Feature Code geschrieben wird, läuft immer erst der **Kritik-Pass**. Wichtigster Punkt in dieser Datei.

**Prompt 1 — Kritische Voranalyse** (erzeugt *keinen* Code, nur Risiko-Map):

> Agiere als Product Engineer für macOS und prüfe dieses Vorhaben kritisch.
>
> **Vorhaben:** [Feature-Beschreibung]
>
> Zerlege das Vorhaben in technische Teilprobleme. Nenne die 10 größten Risiken für einen alltagstauglichen MVP. Erkläre, welche macOS-Berechtigungen und Systemgrenzen relevant sind. Unterscheide klar: (1) sicher machbar im MVP, (2) wahrscheinlich machbar mit Edge Cases, (3) riskant oder app-übergreifend unzuverlässig. Schlage eine konkrete MVP-Architektur vor und empfiehl, welche Teile zuerst prototypen. Schreibe für ein nicht-technisches Gründerteam: klare Entscheidungen statt MVP-Phrasen.

**Prompt 2 — Implementierung**: Feature mit Erkenntnissen aus Prompt 1 präzisieren, dann in Auto Mode umsetzen, Subagents parallel für Architektur-/Backend-Scan + Implementation, nach Deploy Codex als Zweitmeinung.

### Auto Mode + Codex

- Auto Mode aktivieren via `Shift+Tab` oder `claude --mode=auto`. Empfohlenes Setup: **Opus 4.7 (1M context) + high effort**.
- Codex läuft als Plugin. Für Architektur-Entscheidungen und Review als Zweitmeinung nutzen — Claude ist opinionated, Codex bremst.

---

## Workflow-Regeln (gelernte Praxis)

1. **Build-Artefakte gehören nach `~/Downloads/blitzbot-build/`, NIE ins Projekt.** Projekt liegt in Nextcloud — `.build/` im Projekt würde Sync blockieren. Kern: `swift build --scratch-path "$HOME/Downloads/blitzbot-build/swift"`. Niemals `swift build` ohne `--scratch-path`. Kompletter Build+Deploy-Flow im Skill `build-deploy`. **Nach jedem Build** Dev-App nach `/Applications` deployen und starten, Log-Verifikation auf `Delegate init` + `applicationDidFinishLaunching` + `CGEventTap installed` (Hotkey-System up).

2. **Code-Signing: immer `--sign blitzbot-dev`, nie ad-hoc (`--sign -`).** Ad-hoc invalidiert bei jedem Re-Sign TCC-Permissions (Accessibility, Input Monitoring) und Keychain-ACL. Mit dem stabilen Dev-Cert überleben Permissions alle Rebuilds. Falls Cert fehlt (`security find-identity -p codesigning -v` zeigt 0): Skill `dev-cert-regen`.

3. **Logging**: Nie `print()` oder `FileHandle.standardError`. **Immer `Log.write(...)`** aus `Log.swift` → `~/.blitzbot/logs/blitzbot.log` (per `tail -f` beobachtbar, überlebt Neustart).

4. **Lifecycle**: `applicationDidFinishLaunching` im `NSApplicationDelegate` (`@NSApplicationDelegateAdaptor`) ist der einzige verlässliche Startpunkt. `.onAppear` auf `MenuBarExtra`-Label feuert nicht zuverlässig.

5. **SourceKit-Warnungen nach Edits sind oft stale.** Immer `swift build` laufen lassen und darauf vertrauen, nicht blind den SourceKit-Fehlern folgen.

6. **SwiftUI-Fokus-Falle**: Alle floating Panels (HUD, Setup) müssen `NSPanel` mit `.nonactivatingPanel` + `ignoresMouseEvents` sein. Sonst klaut das Panel den Fokus und `Cmd+V` pastet ins falsche Ziel.

7. **KeyboardShortcuts gepinnt auf `<1.15.0`.** Version 2.x nutzt `#Preview`-Macros die einen Xcode-only `PreviewsMacros`-Plugin brauchen → SPM-Build bricht.

8. **Keine weiteren Dependencies ohne Rückfrage.** Jede Dep vergrößert die Bundle-Size und erhöht Supply-Chain-Risiko.

9. **Vor jedem Push: PII/Secrets-Sperre.** Skill `pre-push-scan` + mechanischer `.git/hooks/pre-push`. Als kritisch gilt: API-Keys, Tokens, JWT-Prefixe, Private Keys, Personennamen, Firmen-Emails, lokale Pfade, interne IPs, SSIDs, MACs, interne Hostnames, Device-IDs, Telefonnummern, Inhalte aus lokalen Notiz-Files. Niemals mit `--no-verify` umgehen.

10. **Vor jedem Push: README aktuell halten.** Neue Features → Modi-Tabelle / Usage / Settings. Breaking Changes → README § Changelog als neue Version (Datum + Stichpunkte). Entfernte Funktionen → raus. Neue Dateien/Module → README § Development → Key files. TOC synchron. Keine „TODO: update README"-Commits.

11. **Release Notes bilingual (English zuerst, Deutsch danach).** GitHub schneidet bei schmalen Fenstern oben ab, Englisch ist breitere Leser-Basis. Inhalt identisch, nicht nur übersetzte Überschriften. Bei `gh release edit` beide Blöcke aktualisieren.

12. **UI-Änderungen im echten Build testen.** Nach jedem UI-Change: rebuild, deploy, Hotkey drücken, Verhalten prüfen.

---

## Produkt

### Idee

- **Menubar-App** (Icon oben rechts) — Activation-Policy per Default `.accessory` (kein Dock), wird nur beim Öffnen des Office-Fensters temporär auf `.regular` geschaltet
- Läuft permanent im Hintergrund, systemweit verfügbar
- Globaler Hotkey → Aufnahme → Transkription → Auto-Paste in die aktive App (LinkedIn, Slack, Mail, WhatsApp Web — überall)
- Toggle (drücken/erneut drücken); Modus kann während Aufnahme gewechselt werden

### Modi (Default-Hotkeys — in Settings individuell belegbar)

| Pos | Modus    | Hotkey | Tagline                              | Verhalten |
|-----|----------|--------|--------------------------------------|-----------|
| 1   | Normal   | `⌘⌥1`  | "Sprache rein. Text raus."          | Wort-für-Wort, **kein** LLM-Call |
| 2   | Business | `⌘⌥2`  | "Sprache rein. Businesstauglich raus." | LLM → klar, höflich, strukturiert |
| 3   | Plus     | `⌘⌥3`  | "Geschrieben sprechen."             | LLM → Füllwörter/Grammatik glätten, Stimme bleibt |
| 4   | Rage     | `⌘⌥4`  | "Frust rein. Entspannt raus."       | LLM → Beleidigungen raus, Kritik bleibt |
| 5   | Emoji    | `⌘⌥5`  | "Sprache rein. Text mit Emojis raus." | Original + dezente Emojis |
| 6   | Prompt   | `⌘⌥6`  | "Idee rein. Prompt raus."           | LLM verwandelt gesprochene Idee in tool-agnostischen Prompt (ChatGPT/Claude/Cursor/…). Output ist der Prompt, nicht das Ergebnis. |
| 7   | Translate | `⌘⌥7` | "Sprache rein. Übersetzung raus."   | Whisper + LLM → DE↔EN Auto-Flip (Zielsprache = Gegenpart der erkannten Sprache). |
| 8   | Office   | *(opt-in)* | "Auswahl rein. Review + Paste raus." | Non-Voice: Selection/Clipboard/File-Drop → Preview → Modus-Picker → LLM → ⌘↵ pastet. Siehe `OfficeView.swift`. |

Plus `⌘⌥0`: liest aktuelle Selection via AX/⌘C, schreibt im Default-Modus um, pastet zurück — fire-and-forget.

Jeder Modus hat anpassbaren System-Prompt in Settings (leer = Sprach-abhängiger Default, bei Custom-Text: Toggle „Replace" vs. „Append to default" pro Modus).

**Sprach-Routing (DE / EN)**: Whisper läuft mit `-l auto`, Content-Stopword-Detector entscheidet finale Sprache (Whispers Auto-Detect auf kurzen Clips unzuverlässig). Priorität in `ModeProcessor.resolveLanguage`: user-Override > Content-Detector > Whisper-Metadata. Prompts pro Modus in DE+EN (`defaultSystemPromptGerman` / `defaultSystemPromptEnglish` in `Mode.swift`).

### UI-Copy-Regeln

- Taglines immer „X rein. Y raus." — prägnant, keine Fachsprache
- Menubar-Icon spiegelt Status: `bolt.fill` (bereit), `record.circle.fill` rot (aufnehmend), `waveform` gelb (verarbeitend), `checkmark.circle.fill` grün (fertig), `exclamationmark.triangle.fill` orange (Fehler)
- Menubar-Popover minimal: Header + Modi-Liste + Footer (Quit, API-Key-Warning). Settings-Zahnrad im Popover-Header oben rechts
- **Deutsche UI** ist Default, Englisch via `Localizable.strings`. Deutsche User-Logs (`"Aufnahme läuft"`), englische Identifier (`startRecording`)
- HUD (Floating-Panel während Aufnahme): zentral, Modus-Badge + Timer mm:ss + Waveform + Live-Transkript (Apple SpeechTranscriber, macOS 26+ / 16-core ANE) + Sprach-Pill + Cloud-Toggle

### Settings-UI (Tabs)

1. **Allgemein** — Output-Sprache, Auto-Stop-Silence-Timer, Whisper-Binary + Modell-Pfad, Privacy-Mode + „Immer anonymisieren"-Liste, Default-Modus für ⌘⌥0
2. **Profile** — Connection Profiles CRUD, JSON Import/Export, Quick-Switcher, Mac-Scanner, Modell-Discovery pro Profil
3. **Hotkeys** — pro Modus `KeyboardShortcuts.Recorder`
4. **Prompts** — System-Prompt pro Modus editierbar, Replace/Append-Toggle
5. **Vokabular** — Eigennamen/Fachbegriffe (als `--prompt` an Whisper)
6. **Setup** — Shortcut zu Permissions
7. **Über** — Version, Lizenz, Auto-Update-Check

---

## Technik

### Stack

- **Swift 5.9+, SwiftUI** (macOS 13+), **SPM** (nicht Xcode-Projekt)
- **STT:** whisper.cpp lokal via `whisper-cli` CLI (nicht Whisper API) — offline, privat. Optionaler LLM-Korrektur-Pass (`sttCorrectionEnabled`) für Dialekte/Sprachmischungen.
- **Live-Transkription:** Apple `SpeechAnalyzer` (macOS 26+, 16-core ANE) liefert Wort-für-Wort-Interim-Text im HUD während der Aufnahme. Toggle in Settings → Allgemein.
- **LLM (Business/Plus/Rage/Emoji/Prompt/Translate/Office):** `LLMRouter` → aktives `ConnectionProfile`. Provider: Anthropic / OpenAI / Ollama / custom OpenAI-kompatibel. Auth: `x-api-key` / `Bearer` / keine.
- **Privacy-Layer:** lokaler `PrivacyEngine` — `NLTagger(.nameType)` + `NSDataDetector` + Regex (IBAN/MAC/IPv6/Kreditkarte mit Luhn) ersetzt PII mit `[NAME_n]`/`[UNTERNEHMEN_n]`/…, reverse-mapped beim Response. Standardmäßig an.
- **Hotkeys:** `KeyboardShortcuts` (`<1.15.0`)
- **Auto-Paste:** `NSPasteboard` + `CGEvent` Cmd+V-Simulation (Accessibility)
- **Audio:** `AVAudioEngine` mit Tap (PCM-Samples + RMS für HUD)
- **Floating-UI:** `NSPanel` (`nonactivatingPanel`, `fullScreenAuxiliary`, `canJoinAllSpaces`)
- **Prompt Caching:** aktiv für Anthropic-direkte Calls (`cache_control: ephemeral` am System-Prompt), deaktiviert bei Proxy- oder Custom-baseURL-Profilen.

### Architektur (Flow)

```
Hotkey → ModeProcessor.toggle → AudioRecorder → wav → WhisperTranscriber
       → resolveLanguage → PrivacyEngine.anonymize → LLMRouter.rewrite
       → (on error: HUD bleibt, Clipboard-Safety-Net, Profile-Retry 30s)
       → PrivacyEngine.deanonymize → Paster (NSPasteboard + CGEvent Cmd+V)
```

### Key Files

`Sources/blitzbot/`:

| Datei | Rolle |
|---|---|
| `blitzbotApp.swift` | `@main` + AppDelegate + MenuBarExtra + Settings/Setup/Office-Windows |
| `Mode.swift` | Enum + DE/EN System-Prompts + Opus-4.7-Effort-Map |
| `ModeProcessor.swift` | State-Machine, Whisper-Dispatch, Sprach-Routing, Recovery-Kontext |
| `HotkeyManager.swift` | KeyboardShortcuts-Bindings + `⌘⌥0` Selection-Rewriter + Office-Toggle |
| `AudioRecorder.swift` | AVAudioEngine + PCM-Tap + RMS-Level |
| `WhisperTranscriber.swift` | `whisper-cli` subprocess wrapper, JSON-Parse |
| `LLMRouter.swift` + `LLMError.swift` | Provider-Dispatch + strukturierte Errors mit `isRecoverable` |
| `AnthropicClient.swift` / `OpenAIClient.swift` / `OllamaClient.swift` | API-Clients |
| `ConnectionProfile.swift` + `ProfileStore.swift` + `ProfileScanner.swift` | Multi-LLM Profile-Management |
| `PrivacyEngine.swift` | Pre-Send-Anonymizer, reversibles Placeholder-Mapping |
| `KeychainStore.swift` + `KeychainPreWarmer.swift` | API-Keys mit Open-Access-ACL |
| `LiveTranscriber.swift` | `LiveTranscriberManager` + `AppleLiveTranscriber` (SpeechAnalyzer, macOS 26+), Interim-Text-Stream an HUD |
| `RecordingHUD.swift` + `MenuBarView.swift` + `OfficeView.swift` + `SettingsView.swift` + `ProfilesView.swift` + `PermissionsView.swift` | UI |
| `Paster.swift` | Cmd+V via CGEvent (nonactivating) |
| `Log.swift` | `~/.blitzbot/logs/blitzbot.log` append-only |
| `Updater.swift` | GitHub-Releases-API-Check + In-place-Install |
| `LaunchAtLoginManager.swift` | `SMAppService.mainApp`-Wrapper für den Login-Item-Toggle in Settings → Allgemein |
| `ModelDownloader.swift` | In-App Whisper-Modell-Download von HuggingFace, Progress + Cancel + GGUF-Magic-Verify |

`blitzbot.app/Contents/Info.plist` — Bundle-ID `de.blitzbot.app`, CFBundleLocalizations. Activation-Policy wird programmatisch in `applicationWillFinishLaunching` auf `.accessory` gesetzt.

`blitzbot-ios/` — eigenständiger iOS-MVP (Hold-to-Talk + Share Extension + Siri Shortcut), nicht released.

---

## Sicherheit & Privatsphäre

- **Audio-Dateien:** `/tmp/blitzbot-<uuid>.wav` — nach Transkription **immer** löschen (`defer` in `WhisperTranscriber`). Niemals in `~`, niemals als Backup.
- **API-Keys:** Keychain mit Open-Access-ACL (`de.blitzbot.mac` service, Pro-Profile-Slot). Nie `UserDefaults`, nie loggen, nie ins Repo.
- **Transkripte nicht loggen:** im Release-Build keine `Log.write("TRANSCRIPT: …")`-Calls, nur `len=<n>`.
- **Cloud-Calls:** User weiß via README + Settings, dass Business/Plus/Rage/Emoji/Prompt Text an den aktiven Provider schicken. Normal-Modus macht keine Cloud-Calls. Privacy-Mode default ON seit v1.2.2.
- **Vor jedem Push:** Skill `pre-push-scan` + Hook blockt mechanisch.

---

## Nicht tun

- Kein Source-Code von fremden Tools kopieren — nur inspirieren
- Keine LaunchAgents / Auto-Start ohne User-Zustimmung
- Kein `sudo` ohne Rückfrage
- Keine globalen Installs (`brew install -g`, `npm -g`) ohne Freigabe
- Keine destruktiven Git-Operationen (force-push, reset --hard) automatisch
- Kein Re-Sign der App ohne Grund — jedes Re-Sign kostet User Accessibility-Permissions

---

## Aktueller Stand

- **Aktuelle Version:** v1.5.1 (Stand: 2026-05-04)
- **GitHub:** https://github.com/mosandlt/BlitzBot (MIT, public)
- **Bundle-ID:** `de.blitzbot.app`. Keychain-Service: `de.blitzbot.mac` (Accounts pro Profile-Slot + Legacy `anthropic-api-key` / `openai-api-key` / `ollama-api-key`)
- **Release-Artifakt:** ad-hoc signiert via `./build-app.sh --release` → `.zip` auf GitHub Releases. End-User: Rechtsklick → Öffnen beim ersten Start (nicht notarisiert).
- **Keychain-ACL:** Open-Access (`SecAccessCreate` mit leerem `trustedApps`). Kein Prompt beim ersten Start oder nach Rebuilds. Einmalige Migration via `KeychainPreWarmer` (Flag `keychain.openACL.migrated.v2`).
- **LLM-Architektur:** `LLMRouter` → aktives `ConnectionProfile`. Apple Intelligence war v1.3.0/v1.3.1, in v1.3.2 entfernt (3B empirisch unbrauchbar). Für lokale größere Modelle: Ollama + Qwen/Llama/Mistral 14B+.
- **Privacy:** default an seit v1.2.2. Lokale Anonymisierung vor jedem LLM-Call, Reverse-Mapping im Response.
- **Prompt Caching:** aktiv bei Anthropic-direkten Calls (`cache_control: ephemeral` am System-Prompt, 5-Min-TTL). Bei Proxy-/Custom-baseURL-Profilen deaktiviert.
- **macOS 26:** SPM-Resource-Bundles brauchen `CFBundleIdentifier` — `build-app.sh` patcht automatisch alle Bundles nach dem Kopieren. Ohne diesen Patch crasht `KeyboardShortcuts.RecorderCocoa` beim Start.
- **iOS Sub-Projekt:** `blitzbot-ios/` Scaffold, nicht released. SFSpeechRecognizer funktioniert nur auf echtem iPhone, nicht im Simulator.

Release-Historie komplett: `docs/CHANGELOG.md`.

---

## Offene Punkte

- Apple Developer Program + Notarisierung (wenn User-Basis >0 wird, 99 €/Jahr)
- iOS-App testen + releasen
- Apple Intelligence re-evaluieren, falls Apple größeres on-device Modell liefert
