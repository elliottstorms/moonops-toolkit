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
    echo "== 🌙 Daily brief ($(date -r "$BRIEF" '+%a %-I:%M %p')), ~/Claude/DailyBrief.html =="
    grep -E '^> ⚠️|^\*\*Top priority' "$BRIEF" 2>/dev/null | head -4
    awk '/^## 👉/{getline; print "👉 " $0; exit}' "$BRIEF" 2>/dev/null
  elif [ -z "$(find "$BRIEF" -mtime -2 2>/dev/null)" ]; then
    echo
    echo "== ⚠️ daily-sync: brief is $(( ( $(date +%s) - $(date -r "$BRIEF" +%s) ) / 86400 ))d stale, the 07:20 sync may be dead; check ~/Claude/daily-sync/logs/run.log =="
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
  # Count only UNDECIDED blocks. Counting every `## ` heading was the same
  # stale-banner bug one layer down: decided proposals are deliberately kept in
  # the file for history and never deleted, so the count froze at 12 and kept
  # nagging after you had cleared every one of them (2026-08-27). A decided
  # block stamps its verdict into its own heading, `## [APPLIED ...]` or
  # `## [CLOSED ...]` or `## [DECIDED ...]`; anything without a bracket is open.
  n=$(grep '^## ' "$PROPS" 2>/dev/null | grep -vc '^## \[')
  [ -n "$n" ] || n=0
  if [ "$n" -gt 0 ]; then
    echo
    echo "== daily-sync: $n CLAUDE.md proposal(s) pending, say 'apply the CLAUDE.md proposals' =="
  fi
fi

if [ -d "$IN" ]; then
  pending=$(ls -1 "$IN"/*.md 2>/dev/null)
  if [ -n "$pending" ]; then
    echo
    # Each dispatch is annotated with its own **Due:** date so an overdue one
    # announces itself instead of waiting to be stumbled on. Added 2026-08-25:
    # DISPATCH_2026-08-19_board-intro-practice.md sat six days past its Due line
    # and nothing here said so; it surfaced only because you happened to ask
    # what the other handoff was. Parsing is BEST EFFORT (first ISO 2026-08-20 or
    # 8/30 style date after the Due marker, stopping at a | or a middot so a
    # later field cannot supply the date). A dispatch whose date cannot be read
    # still prints, just with no age flag, and any failure at all falls back to
    # the plain filename list. Read-only, never blocks, always exits 0.
    block=$(python3 - "$IN" <<'PYDUE' 2>/dev/null
import sys, os, re, glob
from datetime import date
today = date.today()
rows, overdue = [], 0
for p in sorted(glob.glob(os.path.join(sys.argv[1], "*.md"))):
    name = os.path.basename(p)
    try:
        head = open(p, encoding="utf-8", errors="replace").read(4000)
    except OSError:
        head = ""
    due = None
    m = re.search(r"\*\*Due:\*\*\s*([^\n|\u00b7]*)", head)
    if m:
        t = m.group(1)
        iso = re.search(r"(\d{4})-(\d{1,2})-(\d{1,2})", t)
        sl = re.search(r"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b", t)
        try:
            if iso:
                due = date(int(iso.group(1)), int(iso.group(2)), int(iso.group(3)))
            elif sl:
                y = sl.group(3)
                y = today.year if not y else (2000 + int(y) if len(y) == 2 else int(y))
                due = date(y, int(sl.group(1)), int(sl.group(2)))
        except ValueError:
            due = None
    if due is None:
        rows.append("%s  (no readable Due date)" % name)
    else:
        d = (today - due).days
        if d > 0:
            overdue += 1
            rows.append("%s  >> OVERDUE by %d day%s, was due %s <<" % (name, d, "" if d == 1 else "s", due.isoformat()))
        elif d == 0:
            rows.append("%s  >> DUE TODAY <<" % name)
        else:
            rows.append("%s  (due %s, %d day%s out)" % (name, due.isoformat(), -d, "" if d == -1 else "s"))
hdr = "== Handoffs waiting in inbox, run /run-handoff =="
if overdue:
    hdr = "== Handoffs waiting in inbox: %d OVERDUE, run /run-handoff ==" % overdue
print(hdr)
print("\n".join(rows))
PYDUE
)
    if [ -n "$block" ]; then
      echo "$block"
    else
      echo "== Handoffs waiting in inbox, run /run-handoff =="
      echo "$pending" | sed 's#.*/##'
    fi
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
    echo "== self-heal: $stale session digest(s) waiting >36h, daily heal may be stalled; run /self-heal =="
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
  # Counting moved OUT of this file 2026-08-29 (proposal 64 option 2). It used to
  # live here as an awk, and state_update.py grew a second copy of the same rules
  # so it could derive proposals_open; two implementations of one rule in files
  # that could not share code is a drift engine, and the awk's own vocabulary was
  # already wrong (no DECLINED, and two lists that disagreed). One implementation
  # now, in state_update.py --count-only, which selftest.sh exercises directly.
  #
  # Fail-open, three ways, because this is a SessionStart hook and must never
  # block or lie: python3 missing, script missing, or non-numeric output all fall
  # through to a LOUD unavailable line rather than a silent skip. A hidden count
  # would read as "no proposals waiting", which is the silent-instrument failure
  # this loop has been bitten by before.
  open=$(python3 -B "$HOME/.claude/skills/self-heal/state_update.py" \
           --count-only "$SH/pending-review.md" 2>/dev/null)
  case "$open" in
    ''|*[!0-9]*)
      echo
      echo "== self-heal: proposal count UNAVAILABLE (counter failed); check pending-review.md by hand =="
      ;;
    0) : ;;
    *)
      echo
      echo "== self-heal: $open proposal(s) awaiting you, say 'review the pending self-heal proposals' =="
      ;;
  esac
fi
exit 0
