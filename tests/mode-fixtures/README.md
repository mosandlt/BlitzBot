# Mode Fixtures — Verification Harness

Leichtgewichtige Tests für die 6 LLM-Modi (Business/Plus/Rage/Emoji/Prompt/Office). Kein exakter String-Match — nur **Shape-Kriterien** (z.B. „enthält keine Anrede", „max 2 Emojis", „kein Markdown-Heading").

## Struktur

```
tests/mode-fixtures/
  fixtures/
    business-01-de.txt        # Input (echtes Diktat-Transkript)
    business-01-de.expected   # Shape-Kriterien als Zeilenliste
    business-01-en.txt
    …
    plus-01-de.txt / .expected
    rage-01-de.txt / .expected
    …
  run-fixtures.sh             # Shell-Runner, ruft echten LLM gegen jede Fixture
```

## Format `.expected`

Jede Zeile ist ein einzelnes Kriterium:

- `contains: <substring>` — Output muss den Substring enthalten (case-insensitive)
- `not-contains: <substring>` — Output darf den Substring NICHT enthalten
- `max-length: <N>` — Output ≤ N Zeichen
- `min-length: <N>` — Output ≥ N Zeichen
- `max-emojis: <N>` — Output hat maximal N Emoji-Zeichen
- `no-markdown-headings` — keine `#` / `##` Zeilen
- `no-preamble` — Output beginnt nicht mit `"Hier ist"`, `"Here is"`, `"Sure"`, `"Klar"`, o.ä.

## Ausführen

```bash
cd tests/mode-fixtures
./run-fixtures.sh                         # alle Modi, aktives Profile
./run-fixtures.sh --mode business         # nur Business
./run-fixtures.sh --mode plus --lang en   # Plus auf Englisch
```

Der Runner ruft `blitzbot-cli` (falls vorhanden) oder direkt den aktiven Profile-Endpoint. Output pro Fixture: `✓ name` (alle Kriterien erfüllt) oder `✗ name` (inkl. welches Kriterium).

## Neue Fixture hinzufügen

1. Echtes Diktat als `.txt` in `fixtures/`.
2. `.expected` mit 2–5 Shape-Kriterien (keine Romane).
3. Runner läuft automatisch gegen alle `*.txt`.

**Wichtig:** Fixtures dürfen **keine PII** enthalten (Namen, Adressen, interne Hostnames). Generische Platzhalter (`Person A`, `Firma X`) verwenden oder Privacy-Engine vor-testen.
