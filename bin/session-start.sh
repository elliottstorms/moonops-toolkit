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

# Daily brief (com.moonops.dailysync, 07:20). The brief is written to a local file
# rather than emailed, so something has to surface it or it may as well not exist.
# Fresh brief: show the alert lines and Today's one thing. Stale brief: say so,
# because a missing morning sync is itself the alert — that is the exact failure
# class (a launchd job dying quietly) the sync was built to catch, and nothing
# else watches the watcher.
BRIEF="$HOME/Claude/DailyBrief.md"
if [ -f "$BRIEF" ]; then
  if [ -n "$(find "$BRIEF" -mtime -1 2>/dev/null)" ]; then
    echo
    echo "== 🌙 Daily brief ($(date -r "$BRIEF" '+%a %-I:%M %p')) — ~/Claude/DailyBrief.html =="
    grep -E '^> ⚠️|^\*\*Top priority' "$BRIEF" 2>/dev/null | head -4
    awk '/^## 👉/{getline; print "👉 " $0; exit}' "$BRIEF" 2>/dev/null
  elif [ -z "$(find "$BRIEF" -mtime -2 2>/dev/null)" ]; then
    echo
    echo "== ⚠️ daily-sync: brief is $(( ( $(date +%s) - $(date -r "$BRIEF" +%s) ) / 86400 ))d stale — the 07:20 sync may be dead; check ~/Claude/daily-sync/logs/run.log =="
  fi
fi

# CLAUDE.md edits cannot be applied by the headless 07:20 sync (harness-level
# sensitive-file gate, verified 2026-07-27), so it leaves proposals here instead.
# An interactive session CAN apply them, which is exactly what this line is for.
PROPS="$HOME/Claude/daily-sync/claude-md-proposals.md"
# Count the `## ` proposal blocks, not just a non-empty file: this file always
# carries its own header and instructions, so `-s` alone would nag forever. That
# is the same stale-banner bug the self-heal check hit on 2026-07-18.
if [ -f "$PROPS" ]; then
  n=$(grep -c '^## ' "$PROPS" 2>/dev/null)
  [ -n "$n" ] || n=0
  if [ "$n" -gt 0 ]; then
    echo
    echo "== daily-sync: $n CLAUDE.md proposal(s) pending — say 'apply the CLAUDE.md proposals' =="
  fi
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
# LAST status marker wins (2026-07-28): the previous version latched dec once set,
# so a proposal closed and later reopened (a real event — Proposal 17 was applied
# then downgraded-open on 2026-07-27) would read closed forever, the quiet inverse
# of the 2026-07-23 bug. Each `**Status:` line now overwrites dec, header included,
# so the newest marker is authoritative. selftest.sh check 27 enforces the matching
# file convention: at most one `**Status:` line per proposal block.
if [ -f "$SH/pending-review.md" ]; then
  open=$(awk '
    /^## Proposal / { if (inblk && !dec) open++; inblk=1;
                      dec=($0 ~ /(APPLIED|REJECTED|DECIDED|RESOLVED|WITHDRAWN|SUPERSEDED)/); next }
    /^## /          { if (inblk && !dec) open++; inblk=0 }
    inblk && /^\*\*Status:/ {
      dec=(tolower($0) ~ /(applied|rejected|resolved|withdrawn|superseded|closed)/) }
    END             { if (inblk && !dec) open++; print open+0 }
  ' "$SH/pending-review.md")
  if [ "$open" -gt 0 ]; then
    echo
    echo "== self-heal: $open proposal(s) awaiting you — say 'review the pending self-heal proposals' =="
  fi
fi
exit 0
