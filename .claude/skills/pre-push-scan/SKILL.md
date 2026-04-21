---
name: pre-push-scan
description: Scanne den aktuellen Git-Diff vor `git push` auf Secrets und PII. Ergänzt den repo-lokalen `.git/hooks/pre-push`. Nutze diesen Skill wenn der User committet / pushen will, als Defense-in-Depth — der Hook blockt mechanisch, aber doppelt hält besser.
---

# Pre-Push Secrets & PII Scan

## Was geprüft wird

- **Credentials:** API-Keys, Tokens, JWT-Prefixes (`eyJ…`), Bearer-Tokens, Private-Key-Header (`-----BEGIN`).
- **PII:** Personen-Klarnamen, Firmen-Email-Adressen, Telefonnummern, Signal-IDs.
- **Infrastruktur:** Interne IP-Bereiche, WiFi-SSIDs, MAC-Adressen, interne Hostnames, Device-IDs.
- **Lokale Pfade:** Absolute User-Pfade (`/Users/…`).
- **Lokale Notes:** Inhalte aus gitignored `*.local.md`-Dateien dürfen nicht im getrackten Diff landen.

Die **exakte Pattern-Liste** lebt in `.git/hooks/pre-push` (repo-lokal, nicht committed — als Regex).

## Ablauf

1. Pattern-Grep auf den Diff:
   ```bash
   git diff origin/main...HEAD | grep -E "<pattern-liste>" && echo "BLOCK" || echo "OK"
   ```
   (Pattern-Liste steht in `.git/hooks/pre-push`.)
2. **Bei Treffer:** Push abbrechen. User informieren, betroffene Datei aus Commit entfernen (`git reset HEAD~1 --mixed`, Datei fixen, neu committen). **Nicht** mit `--no-verify` umgehen.

## Wenn doch etwas durchrutscht

History clean ziehen — der alte Commit bleibt sonst für immer öffentlich sichtbar:

```bash
# Option A: git filter-repo (empfohlen, brew install git-filter-repo)
git filter-repo --path <datei> --invert-paths
git push --force-with-lease

# Option B: BFG Repo-Cleaner
bfg --delete-files <datei>
git reflog expire --expire=now --all && git gc --prune=now --aggressive
git push --force-with-lease
```

**Danach:** Betroffene Keys rotieren (Anthropic-API-Key in Console neu generieren, alter Token in Keychain ersetzen). Niemals „im nächsten Commit löschen" — der alte Commit bleibt in Clones + Forks erhalten.

## Pre-Push Hook nicht deaktivieren

Der Hook in `.git/hooks/pre-push` ist die erste Verteidigungslinie. Nie:

- `git push --no-verify` — umgeht den Hook komplett.
- `chmod -x .git/hooks/pre-push` — deaktiviert ihn stumm.
- Hook löschen und neu klonen — Patterns gehen verloren.

Wenn der Hook fälschlich blockt (False Positive): Pattern im Hook justieren, Commit neu anschauen, bewusst entscheiden. Nicht umgehen.
