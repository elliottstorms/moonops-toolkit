#!/bin/bash
# session-end-capture.sh — SessionEnd hook. The capture half of the self-heal
# loop: when any session ends, distill its transcript (your own messages
# only, via skills/self-heal/distill.py) into ~/.claude/self-heal/queue/<sid>.md,
# where the daily self-heal pass (scheduled task, or /self-heal on demand)
# picks it up and folds what it learned back into the skill library.
#
# Zero tokens: pure shell + python, no model calls. Non-blocking by design:
# capture failures are logged, never raised — a broken hook must never get in
# the way of ending a session (always exits 0).
#
# Skips, all logged: self-heal's own runs (loop guard — the loop must not
# study itself), sessions with no typed user message (pure automation runs
# have nothing to teach about how you work), already-healed sessions.

ROOT="$HOME/.claude/self-heal"
LOG="$ROOT/logs/capture.log"
mkdir -p "$ROOT/queue" "$ROOT/done" "$ROOT/logs" "$ROOT/snapshots"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

IN=$(cat)
SID=$(echo "$IN" | jq -r '.session_id // empty' 2>/dev/null)
TP=$(echo "$IN" | jq -r '.transcript_path // empty' 2>/dev/null)
REASON=$(echo "$IN" | jq -r '.reason // "unknown"' 2>/dev/null)

if [ -z "$SID" ] || [ ! -f "$TP" ]; then
  echo "$(ts) skip: missing session id or transcript (sid=$SID)" >> "$LOG"
  exit 0
fi
if [ -f "$ROOT/done/$SID.md" ]; then
  echo "$(ts) skip: already healed $SID" >> "$LOG"
  exit 0
fi

TMP=$(mktemp "${TMPDIR:-/tmp}/selfheal.XXXXXX")
python3 "$HOME/.claude/skills/self-heal/distill.py" "$TP" \
  --min-user-msgs 1 --skip-if-first-cmd self-heal \
  > "$TMP" 2>>"$LOG"
RC=$?

if [ $RC -eq 0 ] && [ -s "$TMP" ]; then
  mv "$TMP" "$ROOT/queue/$SID.md"
  echo "$(ts) queued $SID (reason=$REASON, $(wc -c < "$ROOT/queue/$SID.md" | tr -d ' ') bytes)" >> "$LOG"
elif [ $RC -eq 3 ]; then
  rm -f "$TMP"
  echo "$(ts) skip: gated $SID (heal run or no typed user messages)" >> "$LOG"
else
  rm -f "$TMP"
  echo "$(ts) ERROR: distill rc=$RC for $SID ($TP)" >> "$LOG"
fi
exit 0
