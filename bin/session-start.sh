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
# Count OPEN proposals, not just a non-empty file: pending-review.md always carries
# its header/instructions, so `-s` fired forever once written (stale-banner bug,
# 2026-07-18). A proposal is open if its `## Proposal N` block has no decided marker.
# The status word lives in the header (`## Proposal 12 — APPLIED …`), so inspect
# that line too — the old version ran `next` before it could, and every closed
# proposal read as open forever (2026-07-23, proposal 13). Body text only counts
# when it starts with `**Status:`, so a proposal that merely quotes another's
# status no longer marks itself closed; header match is case-sensitive on the
# file's uppercase convention so an ordinary "undecided" cannot collide.
if [ -f "$SH/pending-review.md" ]; then
  open=$(awk '
    /^## Proposal / { if (inblk && !dec) open++; inblk=1;
                      dec=($0 ~ /(APPLIED|REJECTED|DECIDED|RESOLVED|WITHDRAWN|SUPERSEDED)/); next }
    /^## /          { if (inblk && !dec) open++; inblk=0 }
    inblk && /^\*\*Status:/ &&
      tolower($0) ~ /(applied|rejected|resolved|withdrawn|superseded|closed)/ { dec=1 }
    END             { if (inblk && !dec) open++; print open+0 }
  ' "$SH/pending-review.md")
  if [ "$open" -gt 0 ]; then
    echo
    echo "== self-heal: $open proposal(s) awaiting you — say 'review the pending self-heal proposals' =="
  fi
fi
exit 0
