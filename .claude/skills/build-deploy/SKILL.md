---
name: build-deploy
description: Baue blitzbot und deploye die Dev-App nach /Applications. Nutze diesen Skill nach Code-Änderungen, um die aktuelle Version im Daily-Driver-Install zu testen. Beinhaltet automatisches Kill-Start, Codesigning mit `blitzbot-dev` und Log-Verifikation.
---

# Build & Deploy Dev-App

Standard-Workflow nach jedem Code-Change, damit der User sofort die Änderung im echten System sieht — nicht nur im Downloads-Build.

## Reihenfolge (nie abweichen)

```bash
pkill -f "/Applications/blitzbot.app" 2>/dev/null
./build-app.sh --sign blitzbot-dev
ditto ~/Downloads/blitzbot-build/blitzbot.app /Applications/blitzbot.app
codesign --force --deep --sign blitzbot-dev /Applications/blitzbot.app
touch /Applications/blitzbot.app    # LaunchServices-Refresh
open /Applications/blitzbot.app
./tools/smoke-test.sh               # verifiziert Start-Marker im Log
```

## Warum so

- **Build-Artefakte gehören nach `~/Downloads/blitzbot-build/`, NIE ins Projekt.** Projekt liegt in Nextcloud — `.build/` würde mehrere 100 MB in Sync schieben. `build-app.sh` ruft intern `swift build --scratch-path "$HOME/Downloads/blitzbot-build/swift"` auf.
- **Niemals `swift build` ohne `--scratch-path` aus dem Projekt.** Sonst landet `.build/` im Nextcloud-Ordner.
- **Immer `--sign blitzbot-dev`, nie ad-hoc (`--sign -`).** Ad-hoc-Signing invalidiert bei jedem Re-Sign TCC-Permissions (Accessibility, Input Monitoring) und Keychain-ACL. Mit dem stabilen Dev-Cert überleben Permissions alle Rebuilds.
- **`ditto` statt `cp -r`**, damit Extended Attributes + Resource-Forks erhalten bleiben.
- **`codesign --force --deep`**, weil `ditto` die Signatur mitzieht, aber nach `--force --sign` ersetzt wird — für saubere Verifikation.
- **`touch`** triggert LaunchServices, Finder und Dock den Icon-Cache neu zu laden.

## Verifikation

`./tools/smoke-test.sh` macht die Prüfung automatisch: wartet 5 s nach dem Start und sucht in den letzten Log-Zeilen:

```
Delegate init
applicationDidFinishLaunching
CGEventTap installed (Accessibility-based, no Input Monitoring needed)
SelectionRewriter ready
```

Exit-Codes: `0` = alle Marker da + keine Panics, `1` = Marker fehlt (Hang/Crash beim Start), `2` = Panic-Pattern (`fatal error`, `EXC_BAD_ACCESS`, `Thread … Crashed`, `assertionFailure`, `precondition failed`) im Tail-Fenster.

Warum kein End-to-End-Hotkey-Test: AppleScript für Keystroke-Simulation bräuchte Accessibility für `osascript`, was bei Erstinstallation nicht erteilt ist → False-Negatives. Log-Verifikation fängt die wichtigen Regressions (Crash im `AppDelegate`, fehlende EventTap-Installation) zuverlässig.

Bei Exit ≠ 0: Log-Tail checken (`tail -60 ~/.blitzbot/logs/blitzbot.log`), letzten Stack-Trace oder Error finden.

## Wenn das Cert fehlt

`security find-identity -p codesigning -v | grep blitzbot-dev` zeigt 0 Treffer → Cert neu erstellen via Skill `dev-cert-regen`.

## Release-Build (Ad-hoc, für GitHub)

```bash
./build-app.sh --release
# Ergebnis: ~/Downloads/blitzbot-build/blitzbot-v<X.Y.Z>.zip
```

End-User müssen beim ersten Start Rechtsklick → Öffnen (Gatekeeper), weil nicht notarisiert. Release-Notes immer bilingual (DE + EN, siehe CLAUDE.md § Release-Notes).
