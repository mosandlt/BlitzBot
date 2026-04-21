#!/usr/bin/env python3
"""
blitzbot — Nutzungs-Report.

Parst ~/.blitzbot/logs/blitzbot.log und liefert eine Zusammenfassung:
  * Diktate pro Modus im gewählten Zeitfenster
  * P50 / P95 End-to-End-Latenz (REC-stop → PASTE)
  * Unvollständige Sessions (REC-stop ohne PASTE)
  * Sprach-Verteilung (de/en) aus TRANSCRIPT-Zeilen

Aufruf:
    python3 tools/usage-report.py                 # Default: letzte 7 Tage
    python3 tools/usage-report.py --days 30
    python3 tools/usage-report.py --days 0        # alles
    python3 tools/usage-report.py --json          # maschinenlesbar

Das Log-Format ist Free-Text (Log.write produziert beliebige Strings). Dieses
Skript matcht auf die vier stabilen Event-Marker (REC start/stop, TRANSCRIPT,
PASTE). Unbekannte Zeilen werden ignoriert, nicht als Fehler behandelt.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path


LOG_PATH = Path.home() / ".blitzbot" / "logs" / "blitzbot.log"

TS_RE = re.compile(r"^\[(?P<ts>[^\]]+)\] (?P<body>.*)$")
REC_START_RE = re.compile(r"REC start mode=(?P<mode>\S+) file=(?P<file>\S+)")
REC_STOP_RE = re.compile(r"REC stop mode=(?P<mode>\S+) wav=(?P<wav>\S+) bytes=(?P<bytes>\d+)")
TRANSCRIPT_RE = re.compile(r"TRANSCRIPT lang=(?P<lang>\S+)")
PASTE_RE = re.compile(r"PASTE len=(?P<len>\d+)")


def parse_ts(s: str):
    try:
        if s.endswith("Z"):
            return datetime.fromisoformat(s[:-1]).replace(tzinfo=timezone.utc)
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def parse_log(path: Path, since):
    """Returns a list of dicts, one per completed dictation session."""
    sessions: list[dict] = []
    current: dict | None = None
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            match = TS_RE.match(line.rstrip())
            if not match:
                continue
            ts = parse_ts(match.group("ts"))
            if ts is None:
                continue
            if since is not None and ts < since:
                continue
            body = match.group("body")

            sm = REC_START_RE.search(body)
            if sm:
                if current is not None:
                    sessions.append(current)
                current = {
                    "mode": sm.group("mode"),
                    "file": sm.group("file"),
                    "start": ts,
                    "stop": None,
                    "transcript": None,
                    "paste": None,
                    "lang": None,
                    "paste_len": None,
                }
                continue

            sm = REC_STOP_RE.search(body)
            if sm and current is not None and current["mode"] == sm.group("mode"):
                current["stop"] = ts
                continue

            sm = TRANSCRIPT_RE.search(body)
            if sm and current is not None:
                current["transcript"] = ts
                current["lang"] = sm.group("lang")
                continue

            sm = PASTE_RE.search(body)
            if sm and current is not None:
                current["paste"] = ts
                current["paste_len"] = int(sm.group("len"))
                sessions.append(current)
                current = None
                continue
    if current is not None:
        sessions.append(current)
    return sessions


def percentile(sorted_values, p):
    if not sorted_values:
        return None
    k = (len(sorted_values) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(sorted_values) - 1)
    if lo == hi:
        return sorted_values[lo]
    return sorted_values[lo] + (sorted_values[hi] - sorted_values[lo]) * (k - lo)


def build_summary(sessions, window_days):
    by_mode = Counter(s["mode"] for s in sessions)
    by_lang = Counter(s["lang"] for s in sessions if s["lang"])
    latencies_ms = [
        (s["paste"] - s["stop"]).total_seconds() * 1000
        for s in sessions
        if s["stop"] and s["paste"]
    ]
    incomplete = sum(1 for s in sessions if s["stop"] and not s["paste"])
    sorted_lat = sorted(latencies_ms)
    total_chars = sum(s["paste_len"] for s in sessions if s["paste_len"])

    return {
        "window_days": window_days,
        "total": len(sessions),
        "incomplete": incomplete,
        "by_mode": dict(by_mode),
        "by_lang": dict(by_lang),
        "chars_pasted": total_chars,
        "latency_ms": {
            "p50": percentile(sorted_lat, 0.5),
            "p95": percentile(sorted_lat, 0.95),
            "count": len(latencies_ms),
        },
    }


def render_text(summary: dict) -> str:
    lines: list[str] = []
    days = summary["window_days"]
    header = "alle Zeiten" if days == 0 else f"letzte {days} Tage"
    lines.append(f"blitzbot — Nutzungs-Report ({header})")
    lines.append("=" * 50)
    lines.append(f"Diktate gesamt:              {summary['total']}")
    lines.append(f"Unvollständig (kein Paste):  {summary['incomplete']}")
    lines.append(f"Zeichen gepastet:            {summary['chars_pasted']:,}".replace(",", "."))
    lines.append("")

    if summary["by_mode"]:
        lines.append("Modus-Verteilung:")
        max_count = max(summary["by_mode"].values())
        for mode, count in sorted(summary["by_mode"].items(), key=lambda x: -x[1]):
            bar_width = int((count / max_count) * 28) if max_count else 0
            bar = "█" * bar_width
            lines.append(f"  {mode:<14} {count:>4}  {bar}")
        lines.append("")

    if summary["by_lang"]:
        lines.append("Sprache:")
        for lang, count in sorted(summary["by_lang"].items(), key=lambda x: -x[1]):
            lines.append(f"  {lang:<6} {count}")
        lines.append("")

    lat = summary["latency_ms"]
    if lat["count"] > 0:
        lines.append(f"Latenz REC-stop → PASTE ({lat['count']} Samples):")
        lines.append(f"  P50: {lat['p50']/1000:.2f}s")
        lines.append(f"  P95: {lat['p95']/1000:.2f}s")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=7,
                    help="Zeitfenster in Tagen (0 = alles, Default: 7)")
    ap.add_argument("--log", type=Path, default=LOG_PATH)
    ap.add_argument("--json", action="store_true",
                    help="JSON statt Text ausgeben")
    args = ap.parse_args()

    if not args.log.exists():
        print(f"Log nicht gefunden: {args.log}", file=sys.stderr)
        sys.exit(1)

    since = None
    if args.days > 0:
        since = datetime.now(timezone.utc) - timedelta(days=args.days)

    sessions = parse_log(args.log, since)
    summary = build_summary(sessions, args.days)

    if args.json:
        print(json.dumps(summary, indent=2, default=str))
    else:
        print(render_text(summary))


if __name__ == "__main__":
    main()
