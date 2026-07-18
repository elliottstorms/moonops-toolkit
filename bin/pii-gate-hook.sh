#!/bin/sh
# pii-gate-hook.sh - Claude Code PreToolUse hook: block tool calls whose text
# payload contains PII. Wire it to outbound-shaped tools (Write|Edit, WebFetch)
# in settings.json. Hook contract: exit 2 blocks the call and the stderr line
# is shown to the model, which then knows exactly why it was stopped.
#
# If the scanner itself is missing this warns and allows (a misconfigured gate
# that bricks every tool call teaches people to delete the gate; a loud warning
# teaches them to fix the path).
set -eu

SCANNER="${PII_SCANNER:-$HOME/.claude/skills/pii-scan/pii_scan.py}"
if [ ! -f "$SCANNER" ]; then
  echo "pii-gate: scanner not found at $SCANNER (set PII_SCANNER); allowing" >&2
  exit 0
fi

# Pull every string value out of tool_input and scan the lot as one stream.
python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

def strings(x):
    if isinstance(x, str):
        yield x
    elif isinstance(x, dict):
        for v in x.values():
            yield from strings(v)
    elif isinstance(x, list):
        for v in x:
            yield from strings(v)

print("\n".join(strings(d.get("tool_input", {}))))
' | python3 "$SCANNER" --mode gate --stdin
