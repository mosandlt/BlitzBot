# blitzbot — Release-Historie

Für die aktuelle Version siehe `CLAUDE.md` → *Aktueller Stand*. GitHub-Releases mit bilingual Notes: https://github.com/mosandlt/BlitzBot/releases.

| Version | Datum | Kernänderung |
|---|---|---|
| v1.5.1 | 2026-05-04 | **VPIO-Fixes**: Live-Transkription funktioniert jetzt mit Voice Isolation (Float32→Int16-Konvertierung für SpeechAnalyzer) + Waveform-Stutter bei VPIO behoben (Buffer-Size 4096→1024 für 64ms-Kadenz statt 256ms). |
| v1.5.0 | 2026-04-23 | **STT-Korrektur** (optionaler LLM-Pass nach Whisper für Dialekte/Bairisch + Sprachmischungen) + **Bairisch-Fix** (Whisper-Spracherzwingung auf DE bei Auto+Korrektur) + **Live-Spracherkennung im HUD** (DE/EN-Badge aktualisiert sich in Echtzeit) + **HUD-Controls**: Sprach-Pill + Cloud-Toggle direkt in der HUD klickbar. |
| v1.4.1 | 2026-04-22 | **Live-Transkription** im HUD während der Aufnahme (Apple SpeechTranscriber, macOS 26+ / 16-core ANE): Text erscheint Wort für Wort, scrollt automatisch, Toggle in Settings → Allgemein. HUD-Transcript-Box sofort sichtbar + Panel-Höhe 300→380pt (Modi-Pills nicht mehr abgeschnitten). |
| v1.4.0 | 2026-04-22 | Neuer **Translate-Modus** (#7, ⌘⌥7, DE↔EN Auto-Flip), **Hold-to-Talk** als Hotkey-Trigger-Alternative, **Whisper-Modell-Picker** in Settings (kuratierte Liste mit Auto-Download + Auto-Cleanup alter Modelle), **Multi-Mic-Selector** (Core Audio Enumeration), **HUD-Progress** mit Spinner + Live-Timer + Provider-Name während LLM-Call, **Whisper-Decoding-Stabilität** (`--no-fallback` etc. — stoppt kreatives Re-Decoding), **Recovery-Fix** (WAV-Header-Repair für mid-recording Kills), **Startup-Timing-Log-Marker**. |
| v1.3.5 | 2026-04-21 | Launch-at-Login-Toggle (SMAppService) + In-App Whisper-Modell-Download (Progress + Cancel + GGUF-Verify) + Smoke-Test-Script + `release`- und `usage-report`-Skills. |
| v1.3.4 | 2026-04-20 | Prompt-caching für Anthropic-direkte Calls (`cache_control: ephemeral`), Effort-Fix Prompt-Mode (`xhigh` statt `high`), Anti-Inflation-Hint für Business-Modus, CLAUDE.md-Prune (-48%), Shape-Fixture-Tests für alle LLM-Modi, Skills extrahiert. |
| v1.3.3 | 2026-04-19 | Settings-Crash-Fix + resilient Profile-Decode |
| v1.3.2 | 2026-04-18 | **Apple Intelligence wieder raus**. v1.3.0/v1.3.1-Integration entfernt nach Live-Tests: 3B-Modell halluziniert / ignoriert System-Prompt in allen LLM-Modi. Privacy-Skip für Ollama bleibt (nützlich, unabhängig). Für lokale größere Modelle → Ollama + Qwen/Llama 14B+. |
| v1.3.1 | 2026-04-17 | Privacy-Skip bei lokalen Providern (Ollama, Apple Intelligence) — Rohtext geht direkt zum on-device Modell. **Superseded durch v1.3.2**: Ollama-Skip bleibt, Apple-Intelligence-Teil obsolet. |
| v1.3.0 | 2026-04-16 | **Apple Intelligence als 4. Provider** (on-device via `FoundationModels`, macOS 26+, kein Key/URL). **Superseded durch v1.3.2**: Integration entfernt, 3B-Modell empirisch unbrauchbar. |
| v1.2.4 | 2026-04-14 | Opus-4.7 per-Mode Effort-Hints (`output_config.effort`, nur bei `claude-opus-4-7`) + CLAUDE.md-Cleanup + Build-Cache-Hygiene. |
| v1.2.3 | 2026-04-12 | Privacy-Coverage erweitert: Postadressen, IBAN, Kreditkarten mit Luhn, MAC, IPv6 — alle lokal detektiert. |
| v1.2.2 | 2026-04-10 | Privacy-Mode default ON, „Immer anonymisieren"-Term-Liste, Session-Mapping in Settings, Menu-Bar-Shield. |
| v1.2.1 | 2026-04-08 | Privacy-Mode (initial): `NLTagger` + `NSDataDetector` + Regex, Menu-Bar/HUD/Office-Shields. Office-Modell-Dropdown live. Office-Hotkey opt-in. |
| v1.2.0 | 2026-04-05 | **Office Mode** (7. Modus, interaktiver Selection-Rewriter). Inline-Recovery nach LLM-Fehlern (Profile-Switch-Retry, Clipboard-Safety-Net). Strukturierte `LLMError`. Voice-Mode-Filter trennt Voice- von Non-Voice-Pfaden. |
| v1.1.0 | 2026-03-28 | Connection Profiles, Model-Picker, resizable Settings, Keychain open-access ACL (kein Prompt mehr). |
| v1.0.10 | 2026-03-20 | Services raus (Gatekeeper blockt self-signed Apps) + neuer Hotkey `⌘⌥0`: liest Selection via AX/⌘C, schreibt im Default-Modus um. |
| v1.0.9 | 2026-03-18 | macOS Services (in v1.0.10 wieder entfernt wegen Gatekeeper-Inkompatibilität mit non-notarized Apps). |
| v1.0.8 | 2026-03-15 | Wellenform-Amplitude deutlich erhöht (4.5× Gain, geclampt auf ±1). |
| v1.0.7 | 2026-03-12 | Multi-LLM: Anthropic/OpenAI/Ollama, Provider-Picker, dynamische Ollama-Modelliste, stale-Error-Fix. |
| v1.0.6 | 2026-03-09 | Echte Wellenform (Canvas/PCM), Pause/Resume, Auto-Stop-Uhr, Stille-Verzögerung 5s, 60s Default, Cancel-Button, Auto-Execute, Security-Fixes. |
| v1.0.5 | 2026-03-05 | Ad-hoc Release-Pipeline, Gatekeeper-Workaround-Docs, bilingual Release Notes. |
| v1.0.4 | 2026-03-02 | Fix: englischer Input → englischer Output (customPrompts sauber getrennt von Defaults). |
| v1.0.3 | 2026-02-28 | Mode 6 repurposed: „AI Command" → „Prompt" (Prompt-Optimizer); Content-Sprach-Erkennung als Whisper-Override. |
| v1.0.2 | 2026-02-25 | 6. Modus (AI Command), automatische Sprach-Erkennung (DE/EN), manueller Override. |
| v1.0.1 | 2026-02-22 | HUD Mode-Switcher + Stop-Button, Cmd+Q-Fix, Settings-UI mit Icon-Toolbar, Hotkey-Migration. |
| v1.0.0 | 2026-02-20 | Initiales Release: 5 Modi (Normal/Business/Plus/Rage/Emoji), Floating-HUD, Vokabular, Auto-Updater. |
