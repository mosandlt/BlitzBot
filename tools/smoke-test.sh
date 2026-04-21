#!/usr/bin/env bash
# blitzbot smoke-test — verifies a freshly launched build came up clean.
#
# Usage:
#   ./tools/smoke-test.sh             # default: wait 5s, look at last 60 log lines
#   ./tools/smoke-test.sh 10          # wait 10s before reading log
#
# Exit codes:
#   0 = all expected markers found, no panic patterns
#   1 = expected marker missing (hang or crash during init)
#   2 = panic / fatal pattern detected in tail window
#
# No end-to-end hotkey test — that needs Accessibility on osascript which is
# chicken-and-egg on first install. The markers below prove the launch path
# (delegate init → CGEventTap install → SelectionRewriter ready) actually
# completed, which catches ~80 % of regressions without TCC dependencies.

set -euo pipefail

WAIT_SECONDS="${1:-5}"
LOG="$HOME/.blitzbot/logs/blitzbot.log"

if [[ ! -f "$LOG" ]]; then
    echo "✘ Log file not found at $LOG — is the app installed and launched?"
    exit 1
fi

sleep "$WAIT_SECONDS"

TAIL=$(tail -60 "$LOG")

REQUIRED=(
    "Delegate init"
    "applicationDidFinishLaunching"
    "CGEventTap installed"
    "SelectionRewriter ready"
)

MISSING=()
for marker in "${REQUIRED[@]}"; do
    if ! echo "$TAIL" | grep -q "$marker"; then
        MISSING+=("$marker")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "✘ Smoke test failed — missing markers:"
    for m in "${MISSING[@]}"; do echo "   - $m"; done
    echo ""
    echo "Last 20 log lines:"
    echo "$TAIL" | tail -20
    exit 1
fi

# Panic patterns: things the app itself would log when it's really broken.
# Deliberately narrow to avoid false positives on benign "… failed" lines.
PANICS=$(echo "$TAIL" | grep -Ei "fatal error|EXC_BAD_ACCESS|Thread .* Crashed|assertionFailure|precondition failed" || true)
if [[ -n "$PANICS" ]]; then
    echo "✘ Panic pattern detected:"
    echo "$PANICS"
    exit 2
fi

echo "✔ Smoke test passed — all markers found, no panics."
for m in "${REQUIRED[@]}"; do
    LINE=$(echo "$TAIL" | grep -m1 "$m")
    echo "   $LINE"
done
