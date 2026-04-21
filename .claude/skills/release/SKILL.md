---
name: release
description: Geführter blitzbot-Release-Flow. Bumpt Version in Info.plist + README + docs/CHANGELOG.md atomisch, baut signiertes ad-hoc-ZIP, tagt, pausiert für User-Go, pusht dann Commits + Tags und erstellt GitHub-Release mit bilingualen Notes (EN zuerst, DE darunter). Nutze diesen Skill wenn der User sagt "release bauen", "v1.x.y raus", "release pipeline", oder eine neue Version veröffentlichen will.
---

# blitzbot Release Pipeline

Dieser Skill fährt einen vollständigen Release ohne dass du Schritte vergisst. Jeder Schritt mit Rationale und Fehlerpfad. Nach dem Build wird **gestoppt und auf User-Go gewartet** — Push + GitHub-Release passieren erst wenn der User explizit freigibt.

## Voraussetzungen (immer prüfen vor Schritt 1)

```bash
gh auth status                                  # muss GitHub-CLI authentifiziert sein
security find-identity -p codesigning -v | grep blitzbot-dev  # >=1 Treffer
git -C . status --porcelain                     # muss leer sein (oder nur README/CHANGELOG wenn versehentlich dirty)
```

Wenn `blitzbot-dev` fehlt → erst Skill `dev-cert-regen`. Wenn `gh` nicht auth → `gh auth login`. Wenn Tree dirty → User fragen, committen oder stashen.

## Input vom User erfragen

Frage nach:

1. **Version** (z.B. `1.3.5`) — ohne `v`-Prefix, wird automatisch gesetzt
2. **Kurztitel EN** (z.B. `Launch-at-Login + model auto-download`) — optional, landet im Release-Title
3. **Bullet-Points EN** (3–5 Zeilen) — „what changed" aus User-Sicht
4. **Bullet-Points DE** — inhaltlich identisch zu EN, nicht bloße Übersetzung

Keine automatische Generierung — bilingual Release Notes sind Redaktions-Arbeit (CLAUDE.md Regel 11). Lieber einmal fragen als falsch generieren.

## Schritte (in dieser Reihenfolge)

### 1. Version im Bundle bumpen

Aus dem Projekt-Root:

```bash
VERSION="1.3.5"                                 # aus User-Input
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" blitzbot.app/Contents/Info.plist)
NEW_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" blitzbot.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" blitzbot.app/Contents/Info.plist
```

`CFBundleVersion` (monoton steigender Build-Zähler) nie zurücksetzen — das bricht den Auto-Updater (`Updater.swift` vergleicht Strings lexikografisch).

### 2. `docs/CHANGELOG.md` — neue Zeile prepend

Edit die Datei direkt (mit dem Edit-Tool). Neue Zeile direkt unter der Header-Zeile (`| Version | Datum | Kernänderung |`) und der Trenn-Zeile (`|---|---|---|`), über der bisher jüngsten Version. Format:

```
| v1.3.5 | YYYY-MM-DD | <eine-Zeile Zusammenfassung, Stichpunkte mit + verbunden> |
```

Datum ist das heutige Datum (ISO: `date +%Y-%m-%d`). Die Zusammenfassung ist **kürzer** als die Release-Notes — eine Zeile, Komma-/Pluszeichen-getrennte Kernänderungen.

### 3. README.md — Changelog-Sektion aktualisieren

Lies `README.md`, finde `## Changelog` oder äquivalente Überschrift. Neue Version oben einfügen, identisches Format wie bestehende Einträge. Wenn README keine Changelog-Sektion hat, überspringe diesen Schritt und erwähne es im User-Report.

### 4. README-Konsistenz-Check (CLAUDE.md Regel 10)

Wenn der Release neue Features / Breaking Changes bringt:

- Modi-Tabelle: neue Modi rein, entfernte raus
- Settings-Sektion: neue Tabs oder Toggles dokumentieren
- Key-Files-Liste: neue `Sources/blitzbot/*.swift`-Dateien erwähnen
- TOC synchron zu Überschriften

Lieber einmal zu viel lesen als den User mit veralteter README releasen.

### 5. Commit (noch nicht pushen)

```bash
git add blitzbot.app/Contents/Info.plist docs/CHANGELOG.md README.md
# + ggf. andere Dateien die zum Release gehören
git commit -m "v$VERSION: <Kurztitel>"
```

Commit-Message-Stil (aus bestehenden Commits): `v1.3.4: prompt caching + Prompt-mode effort fix + fixture tests` — Präfix `v<version>:`, dann komma-/pluszeichen-getrennte Kernpunkte.

### 6. Pre-Push-Scan

```bash
./.git/hooks/pre-push < /dev/null
```

Wenn der Hook blockt (Secrets/PII): **stoppen**, User informieren, nicht mit `--no-verify` umgehen (CLAUDE.md Regel 9). Root-Cause fixen, neu committen (neuer Commit, nicht amend).

Falls der Hook fehlt: erst Skill `pre-push-scan` laufen lassen, dann hier zurück.

### 7. Release-Build

```bash
pkill -f "/Applications/blitzbot.app" 2>/dev/null
./build-app.sh --release
```

Output: `~/Downloads/blitzbot-build/blitzbot-${VERSION}-macos-arm64.zip`. Build schlägt fehl wenn Swift-Errors → User zeigen, nicht weitermachen.

### 8. Tag lokal

```bash
git tag "v$VERSION"
```

Nicht `-a` (annotiert) — Historie zeigt Lightweight-Tags, bleibt einheitlich.

### 9. **STOPP — User-Go einholen**

Bevor irgendwas pusht oder public wird, dem User zeigen:

- Neuer Commit: `git log -1 --stat`
- Tag: `v$VERSION`
- ZIP: Pfad + Größe (`ls -lh ~/Downloads/blitzbot-build/blitzbot-${VERSION}-macos-arm64.zip`)
- Release-Title-Vorschau
- Release-Body-Vorschau (beide Sprachen, exakt wie unten formatiert)

Warte auf explizites „ja push" / „go" / „raus damit". Bei „nein" / „stopp": nichts rückgängig — Commits + Tag bleiben lokal, User kann manuell entscheiden.

### 10. Push + GitHub-Release

Bei Go:

```bash
git push origin main
git push origin "v$VERSION"

gh release create "v$VERSION" \
    ~/Downloads/blitzbot-build/blitzbot-${VERSION}-macos-arm64.zip \
    --repo mosandlt/BlitzBot \
    --title "v$VERSION — <Kurztitel>" \
    --notes-file <(cat <<'EOF'
**<Kurztitel EN>**

- <Bullet EN 1>
- <Bullet EN 2>
- <Bullet EN 3>

**Installation:** Download zip → unpack → move to Applications → right-click → Open (Gatekeeper, first launch only).

---

**<Kurztitel DE>**

- <Bullet DE 1>
- <Bullet DE 2>
- <Bullet DE 3>

**Installation:** Zip entpacken → nach Programme ziehen → Rechtsklick → Öffnen (Gatekeeper, nur beim ersten Start).
EOF
)
```

Das Release-Body-Format ist verbindlich (CLAUDE.md Regel 11): **Englisch zuerst**, Trenn-Linie `---`, dann Deutsch. Installation-Hinweis pro Sprache.

### 11. Verifikation

```bash
gh release view "v$VERSION" --repo mosandlt/BlitzBot
open "https://github.com/mosandlt/BlitzBot/releases/tag/v$VERSION"
```

Dem User: Release-URL zeigen + Hinweis dass Auto-Updater bei bestehenden Installationen innerhalb ~24h greift (oder sofort via Settings → Über → Jetzt prüfen).

## Fehlerpfade

- **Build fehlgeschlagen nach Commit**: Commit bleibt, Tag nicht setzen. User entscheidet ob Fix-Commit drauf oder Reset. Nicht eigenmächtig `git reset --hard`.
- **Push rejected** (weil main geupdated wurde): `git pull --rebase` vorschlagen, nicht `--force`.
- **`gh release create` fehlgeschlagen**: Commit + Tag sind schon public. User: Release per `gh release edit "v$VERSION"` manuell ziehen lassen, oder neu anlegen ohne Tag (`--verify-tag`).
- **User sagt „doch nicht"** nach Schritt 8: Commits + Tag bleiben lokal. Zum Rückgängigmachen: `git tag -d "v$VERSION"` und `git reset --soft HEAD~1`. Beide nur mit explizitem User-Go.

## Was dieser Skill **nicht** macht

- Notarisierung via Apple Developer Program (99 €/Jahr, aktuell nicht eingerichtet — CLAUDE.md Offene Punkte)
- Auto-Update-Server (macht `Updater.swift` direkt via GitHub-Releases-API)
- Migration alter User-Defaults (falls ein Release breaking ist → im Code handhaben, nicht hier)
