#!/bin/bash
# session-start.sh — SessionStart hook. Fast, read-only orientation printed into context
# when a Claude Code session opens: the pinned top of TASKS.md and any handoffs waiting in
# the inbox (so a staged dispatch is never missed). Never blocks; always exits 0.

T="$HOME/Claude/TASKS.md"
IN="$HOME/Claude/Handoffs/inbox"

if [ -f "$T" ]; then
  echo "== TASKS.md (top) =="
  sed -n '1,18p' "$T"
fi

if [ -d "$IN" ]; then
  pending=$(ls -1 "$IN"/*.md 2>/dev/null)
  if [ -n "$pending" ]; then
    echo
    echo "== Handoffs waiting in inbox — run /run-handoff =="
    echo "$pending" | sed 's#.*/##'
  fi
fi

# Self-heal tripwires — quiet unless something needs you. A queued digest
# older than 36h means the daily self-heal-daily pass hasn't fired (scheduled
# tasks can fail silently — the 2026-07-10 frontmatter bug class); a non-empty
# pending-review.md means proposals are waiting on her decision.
SH="$HOME/.claude/self-heal"
if [ -d "$SH/queue" ]; then
  stale=$(find "$SH/queue" -name '*.md' -mmin +2160 2>/dev/null | wc -l | tr -d ' ')
  if [ "$stale" -gt 0 ]; then
    echo
    echo "== self-heal: $stale session digest(s) waiting >36h — daily heal may be stalled; run /self-heal =="
  fi
fi
if [ -s "$SH/pending-review.md" ]; then
  echo
  echo "== self-heal: proposals awaiting you — say 'review the pending self-heal proposals' =="
fi
exit 0
