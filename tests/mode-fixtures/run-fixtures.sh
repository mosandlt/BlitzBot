#!/usr/bin/env bash
# Minimal Mode-Fixture Runner.
#
# Läuft durch tests/mode-fixtures/fixtures/*.txt, ruft einen LLM-Endpoint via curl
# mit dem Default-System-Prompt des jeweiligen Modus und prüft die Shape-Kriterien
# in der zugehörigen *.expected Datei.
#
# Usage: ./run-fixtures.sh [--mode <business|plus|rage|emoji>] [--lang <de|en>]
#
# Endpoint: liest API-Key aus Keychain (Service=de.blitzbot.mac Account=anthropic-api-key)
# oder aus $ANTHROPIC_API_KEY.

set -euo pipefail

FIXTURES_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
MODE_FILTER=""
LANG_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) MODE_FILTER="$2"; shift 2 ;;
        --lang) LANG_FILTER="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# API-Key holen
API_KEY="${ANTHROPIC_API_KEY:-}"
if [[ -z "$API_KEY" ]]; then
    API_KEY=$(security find-generic-password -s "de.blitzbot.mac" -a "anthropic-api-key" -w 2>/dev/null || true)
fi
if [[ -z "$API_KEY" ]]; then
    echo "No API key found (ANTHROPIC_API_KEY env or blitzbot Keychain)"
    exit 1
fi

MODEL="${BLITZBOT_FIXTURE_MODEL:-claude-sonnet-4-5}"

PASS=0
FAIL=0

for fixture in "$FIXTURES_DIR"/*.txt; do
    name=$(basename "$fixture" .txt)
    mode="${name%%-*}"
    lang="${name##*-}"

    [[ -n "$MODE_FILTER" && "$mode" != "$MODE_FILTER" ]] && continue
    [[ -n "$LANG_FILTER" && "$lang" != "$LANG_FILTER" ]] && continue

    expected="${fixture%.txt}.expected"
    if [[ ! -f "$expected" ]]; then
        echo "⚠  $name: no .expected file, skipping"
        continue
    fi

    # System-Prompt pro Modus (kurzgefasst — in echter App via Mode.swift)
    case "$mode" in
        business) system='Rewrite this dictated text for business communication: clear, polite, active voice. Reply with final text only, no preamble.' ;;
        plus)     system='Minimal cleanup of dictated text: remove filler words, fix grammar, keep voice and style. Reply with smoothed text only, no preamble.' ;;
        rage)       system='De-escalate this angry note: remove insults, keep substantive criticism. Reply with rewritten text only, no preamble.' ;;
        emoji)      system='Keep wording 1:1, add tasteful emojis. Target 1 emoji per 1-2 sentences. Reply with emojified text only.' ;;
        aicommand)  system='Du bekommst einen diktierten Text in dem der User beschreibt, was er von einer KI haben möchte. Wandle die lose Beschreibung in einen sauberen Prompt um. Erkenne ob Update an Bestehendem oder neues Projekt. Kein Meta-Satz, kein Preamble, löse die Aufgabe nicht selbst, generiere keinen Code. Antworte ausschließlich mit dem finalen Prompt-Text.' ;;
        *) continue ;;
    esac

    input=$(cat "$fixture")

    response=$(curl -s https://api.anthropic.com/v1/messages \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$(jq -n --arg model "$MODEL" --arg sys "$system" --arg input "$input" \
              '{model: $model, max_tokens: 1024, system: $sys, messages: [{role:"user", content: $input}]}')" \
        | jq -r '.content[0].text // empty')

    if [[ -z "$response" ]]; then
        echo "✗ $name: no response"
        FAIL=$((FAIL+1))
        continue
    fi

    # Criteria-Check
    all_ok=1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue

        key="${line%%:*}"
        val="${line#*: }"

        case "$key" in
            contains)
                grep -qi -- "$val" <<< "$response" || { echo "  ✗ $name: missing '$val'"; all_ok=0; }
                ;;
            not-contains)
                grep -qi -- "$val" <<< "$response" && { echo "  ✗ $name: contains forbidden '$val'"; all_ok=0; }
                ;;
            max-length)
                (( ${#response} <= val )) || { echo "  ✗ $name: length ${#response} > $val"; all_ok=0; }
                ;;
            min-length)
                (( ${#response} >= val )) || { echo "  ✗ $name: length ${#response} < $val"; all_ok=0; }
                ;;
            no-preamble)
                [[ "$response" =~ ^(Hier\ ist|Here\ is|Sure|Klar|Natürlich|Of\ course) ]] && { echo "  ✗ $name: has preamble"; all_ok=0; }
                ;;
            no-markdown-headings)
                grep -q -E '^#{1,3} ' <<< "$response" && { echo "  ✗ $name: has markdown heading"; all_ok=0; }
                ;;
            max-emojis)
                # Grobe Emoji-Count-Approximation via Byte-Länge-Differenz nach ASCII-Strip
                emoji_count=$(python3 -c "import sys,re; t=sys.stdin.read(); print(len(re.findall(r'[\U0001F300-\U0001FAFF\U00002600-\U000027BF]', t)))" <<< "$response")
                (( emoji_count <= val )) || { echo "  ✗ $name: $emoji_count emojis > $val"; all_ok=0; }
                ;;
        esac
    done < "$expected"

    if (( all_ok )); then
        echo "✓ $name"
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "Result: $PASS passed, $FAIL failed"
exit $FAIL
