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

# Log rotation: this hook fires on every session end, forever. Cap the log so
# it can never grow unbounded; 500 lines of history is plenty for debugging.
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" | tr -d ' ')" -gt 2000 ]; then
  tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

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
# Content-age gate (same as the sweep's): a re-opened old session fires
# SessionEnd with a transcript whose real content pre-dates the loop's
# watermark. Without this, the hook re-admits history the sweep was fixed
# (2026-07-18) to exclude — proven by b4cb1a74, hook-captured on 2026-07-18
# with content ending 2026-07-06. Cutoff comes from state.json.last_sweep;
# if state.json is missing or unreadable, CUTOFF is empty and the flag is
# omitted entirely, preserving the hook's never-block-a-session contract.
# distill.py additionally fails open on an unparseable cutoff (gated twice).
CUTOFF=$(python3 -c "import json,sys;print(json.load(open('$ROOT/state.json'))['last_sweep'])" 2>/dev/null)
python3 "$HOME/.claude/skills/self-heal/distill.py" "$TP" \
  --min-user-msgs 1 --skip-if-first-cmd self-heal \
  ${CUTOFF:+--skip-if-content-before "$CUTOFF"} \
  > "$TMP" 2>>"$LOG"
RC=$?

if [ $RC -eq 0 ] && [ -s "$TMP" ]; then
  mv "$TMP" "$ROOT/queue/$SID.md"
  echo "$(ts) queued $SID (reason=$REASON, $(wc -c < "$ROOT/queue/$SID.md" | tr -d ' ') bytes)" >> "$LOG"
elif [ $RC -eq 3 ]; then
  rm -f "$TMP"
  echo "$(ts) skip: gated $SID (heal run, no typed user messages, or content pre-dates ${CUTOFF:-<no cutoff>})" >> "$LOG"
else
  rm -f "$TMP"
  echo "$(ts) ERROR: distill rc=$RC for $SID ($TP)" >> "$LOG"
fi
exit 0
