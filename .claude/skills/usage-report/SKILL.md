---
name: usage-report
description: On-Demand blitzbot-Nutzungs-Report aus ~/.blitzbot/logs/blitzbot.log. Zeigt Diktate pro Modus, P50/P95-Latenz (REC-stop → PASTE), Sprach-Verteilung, unvollständige Sessions. Nutze diesen Skill wenn der User fragt "wie war meine blitzbot-Woche", "blitzbot stats", "usage report", "nutzungs-report", "welchen modus nutze ich am meisten", oder ähnliches.
---

# blitzbot Usage Report

Lies den Log und fass zusammen: wie viele Diktate pro Modus, wie schnell war die Pipeline, wo gibt's Error-Muster. On-demand — nicht cron. Der Nutzen ist Entscheidungs-Hilfe („welche Modi brauche ich wirklich?", „wurde eine Regression in der Latenz sichtbar?").

## Aufruf

Aus dem Projekt-Root:

```bash
python3 tools/usage-report.py --days 7
```

Default-Fenster 7 Tage. Überschreiben via `--days N` (0 = alles). `--json` für maschinenlesbar.

## Output-Interpretation für den User

Nach dem Lauf dem User zeigen + kurz einordnen. Wichtige Blickrichtungen:

1. **Modus-Verteilung**: wenn ein Modus unter 1 % der Calls liegt, ist er Kandidat fürs Rauswerfen (CLAUDE.md: „Don't add features … beyond what the task requires"). Das ist eine *Beobachtung* — nie automatisch vorschlagen, Modi zu streichen.
2. **P95-Latenz**: erwarteter Bereich ist 2–10 s (Whisper-Transkription + LLM-Call). P95 > 15 s → möglicher Latenz-Regress, User sollte rausfinden welcher Modus langsam ist. P50 > 5 s ist auch ungewöhnlich — dann meistens Business/Plus/Rage (LLM-Cloud-Call).
3. **Unvollständige Sessions**: REC-stop ohne PASTE kann heißen (a) User hat bewusst gecancelt (ESC im HUD), (b) Paste fehlgeschlagen (Accessibility weg), (c) Transcription-Error. Wenn >10 % → hinweisen, Log-Tail ansehen.
4. **Sprach-Verteilung**: verschiebt sich die EN/DE-Ratio? Relevant für den Sprach-Router-Test.

## Wenn der Log leer oder sehr klein ist

Unter ~10 Sessions ist P50/P95 nicht aussagekräftig — erwähne das. Auch: Log wird beim App-Reset nicht gedreht; bei **sehr** altem Log (> 1 Jahr) könnte `--days 30` weniger Sessions zeigen als erwartet. `ls -lh ~/.blitzbot/logs/blitzbot.log` vorher für Kontext.

## Was der Report **nicht** kann

- **Content nicht loggen** (CLAUDE.md Privacy-Regel): der Log enthält nur `len=<n>` und `<n> chars`, nie den tatsächlichen Text. Kein „was hast du am meisten diktiert" — nur „wie viele Zeichen / welche Modi".
- **Kein LLM-Token-Verbrauch**: das loggt blitzbot aktuell nicht. Für Kosten-Abschätzung müsste man beim Provider nachsehen.
- **Keine Geräte-Trennung**: wenn dasselbe Log auf mehreren Macs benutzt wird (was aktuell nicht der Fall ist), werden die Zahlen gemischt.

## Log-Format-Risiko

Der Report parst auf die Marker `REC start`, `REC stop`, `TRANSCRIPT lang=`, `PASTE len=`. Wenn in `Log.swift` / `ModeProcessor.swift` die Format-Strings geändert werden, bricht der Parser still. Falls der Report plötzlich 0 Diktate zeigt obwohl der User weiß dass welche stattgefunden haben → erst `grep -c "REC start" ~/.blitzbot/logs/blitzbot.log` prüfen, dann die Regex in `tools/usage-report.py` nachziehen.
