#!/bin/bash
# session-start.sh: SessionStart hook. Fast, read-only orientation printed into context
# when a Claude Code session opens: the pinned top of TASKS.md and any handoffs waiting in
# the inbox (so a staged dispatch is never missed). Never blocks; always exits 0.

T="$HOME/Claude/TASKS.md"
IN="$HOME/Claude/Handoffs/inbox"

if [ -f "$T" ]; then
  echo "== TASKS.md (top) =="
  sed -n '1,18p' "$T"
fi

# Live alerts. Until 2026-10-28 this spot echoed the alert lines of the 07:20 daily
# brief; that sync was retired with the dashboard and the other pushed status pages,
# because the pages went unread and a daily model run to produce a few alert lines
# cost more than it caught. The two checks behind those alerts are cheap enough to
# run right here, fresh at every session start, with no scheduled job that can
# itself die quietly (the old "nothing watches the watcher" problem goes away):
#   1. a scheduled job (com.moonops.* or com.yourname.*) whose last exit was a positive
#      code and that is not running now. Negative codes are signals, such as the -15 a
#      KeepAlive job reports after a restart, and are normal, so they are skipped.
#   2. any job-failure line STATUS.md recorded in the last 24 hours.
#   3. the open asks on the MoonOps morning card (moonops-rain/out/card_asks.md, which the
#      07:00 run rewrites): a stream recording left public, or nothing scheduled to air.
#      The 07:20 sync was that file's only reader, so retiring it left these alarms
#      reaching nobody, the same silence that hid an empty premiere runway for eight days
#      in October 2026. A card the 07:00 run has not rewritten in 30 hours says so, so a
#      run that never happened cannot pass for a clean card.
#   4. the asks other routines park in files for her (the gitscore loop's proposals, the
#      MoonOps council's OPEN_ASKS.md, the Belief and Company weekly council's unanswered
#      decisions), read through ~/.claude/skills/daily-sync/collect_asks.py. Her rule is that an
#      ask reaches her in chat, never parked in a file, and the 07:20 sync was these files' only
#      reader too. The collector's card, self-heal and CLAUDE.md sources are skipped because
#      this file already prints them, and a collector that fails says so instead of going quiet.
#      Its support-inbox rows are left out too, because item 5 sums them into one line, but
#      that source's unknown-not-zero warning prints here.
#   5. customer email to the Belief and Company support inbox that has no reply yet, from
#      ~/.local/state/gmail-mirror/support.json, which the Gmail mirror's support alarm
#      (~/Claude/Toolkit/gmail-mirror/support_alarm.py) rewrites every 15 minutes, 7 AM to 11 PM.
#      It replaced the daily support-desk model run on 2026-10-29. Since 2026-11-01 this is
#      one count line (how many, the oldest's wait, the Spam and unsent-draft notes) and never
#      a sender or a subject: anyone can write to hello@, so those are outside text, and this
#      line reaches every session, unattended ones included. support_alarm.py --status shows
#      them when she says "check support". The same emails are rows in collect_asks.py (item
#      4), the portable reader behind "my tasks" and the weekly review, and the stale-alarm
#      rule lives there: "unknown" is triggered by the age of the last good check, not one
#      failed run, so a network blip stays quiet and a dead alarm cannot pass for an empty inbox.
#   6. the venture queue's morning release (her 2026-09-14 rule: tasks released every morning,
#      get ahead freely), one line from ~/.claude/skills/daily-sync/today.py --line, her pick
#      2A of 2026-10-29. The retired 07:20 sync had been the queue's only reader. "My tasks",
#      "todo list" and "fresh stats" print the full list from the same script.
# Quiet when all six are clean, so a printed line always means something.
ST="$HOME/Claude/STATUS.md"
CARD="$HOME/Claude/Projects/moonops/moonops-rain/out/card_asks.md"
alerts=$(
  launchctl list 2>/dev/null | awk -F'\t' '$3 ~ /^com\.(moonops|yourname)\./ && $1 == "-" && $2+0 > 0 {print "launchd: " $3 " last exited " $2 " and is not running"}'
  if [ -f "$ST" ]; then
    cutoff=$(date -v-24H '+%Y-%m-%d %H:%M' 2>/dev/null)
    [ -n "$cutoff" ] && tail -n 400 "$ST" 2>/dev/null \
      | awk -F' [|] ' -v c="$cutoff" '$3 == "job-failure" && $1 >= c {print "job-failure " $1 ": " substr($4, 1, 220)}' | tail -n 4
  fi
  if [ -f "$CARD" ]; then
    asof=$(sed -n '1s/.*as of \([0-9-]*\).*/\1/p' "$CARD")
    awk -v d="$asof" '/^## / {sub(/^## /, ""); print "MoonOps card " d ": " substr($0, 1, 220)}' "$CARD" | head -n 4
    age=$(( ( $(date +%s) - $(stat -f %m "$CARD" 2>/dev/null || date +%s) ) / 3600 ))
    [ "$age" -ge 30 ] && echo "MoonOps card: not rewritten for $age hours, so the 07:00 run has not been checking and the lines above may be stale"
  fi
  python3 -B "$HOME/.claude/skills/daily-sync/collect_asks.py" --json 2>/dev/null | python3 -c '
import json, sys
skip = {"moonops-card", "self-heal", "claude-md"}
try:
    d = json.load(sys.stdin)
except Exception:
    print("Waiting on you: the ask collector (collect_asks.py) failed, so parked asks are unknown, not zero")
    sys.exit(0)
# Support rows are summed into the one count line below; the support warning still prints here.
asks = [a for a in d.get("open", []) if a.get("source") not in skip and a.get("source") != "bnc-support"]
for a in asks[:5]:
    print("Waiting on you: " + a.get("line", "")[:220])
if len(asks) > 5:
    print("Waiting on you: %d more; collect_asks.py lists them all" % (len(asks) - 5))
for s in d.get("sources", []):
    why = s.get("error") or s.get("warning")
    if why and s.get("key") not in skip:
        print("Waiting on you: %s is unknown today, not zero (%s)" % (s.get("label"), why[:150]))
' 2>/dev/null
  python3 - "$HOME/.local/state/gmail-mirror/support.json" <<'PYSUP' 2>/dev/null
# One count line, never a sender or a subject (item 5 above says why). A missing, unreadable
# or stale record is reported as unknown by collect_asks.py, above, so this stays quiet then.
import json, sys, time
from datetime import datetime
try:
    waiting = [o for o in (json.load(open(sys.argv[1])).get("open") or []) if isinstance(o, dict)]
except Exception:
    sys.exit(0)
if not waiting:
    sys.exit(0)
def epoch(s):
    try:
        return datetime.fromisoformat(s).timestamp()
    except Exception:
        return 0
now = time.time()
ages = [max(0, now - e) for e in (epoch(o.get("since")) for o in waiting) if e]
def waited(sec):
    h = sec / 3600
    return "%d minutes" % (h * 60) if h < 1 else ("%d hours" % h if h < 48 else "%d days" % (h / 24))
n = len(waiting)
head = "%d email%s" % (n, "" if n == 1 else "s")
if ages:
    head += (", waiting " if n == 1 else ", the oldest waiting ") + waited(max(ages))
notes = []
for folder in ("Spam", "Trash"):
    k = sum(1 for o in waiting if o.get("folder") == folder)
    if k:
        notes.append("Gmail put %s in %s" % ("it" if n == 1 else k, folder))
k = sum(1 for o in waiting if o.get("draft_waiting"))
if k:
    notes.append("a reply is drafted in Gmail, not sent" if n == 1
                 else "%d %s a reply drafted in Gmail, not sent" % (k, "has" if k == 1 else "have"))
print('Belief and Company mail waiting for a reply: %s%s. Say "check support" for a reply, or "no reply needed" to clear it'
      % (head, " (%s)" % "; ".join(notes) if notes else ""))
PYSUP
  python3 -B "$HOME/.claude/skills/daily-sync/today.py" --line 2>/dev/null \
    || echo "Venture queue unknown: today.py failed, so today's venture tasks are unknown, not zero"
)
if [ -n "$alerts" ]; then
  echo
  echo "== ⚠️ Alerts, computed live at session start (mention once, at the end of the first reply) =="
  echo "$alerts"
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

# Self-heal tripwires: quiet unless something needs you. A queued digest
# older than 36h means the daily self-heal-daily pass hasn't fired (scheduled
# tasks can fail silently: the 2026-07-10 frontmatter bug class); a non-empty
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
# The status word lives in the header (`## Proposal 12`, an em dash, `APPLIED …`), so inspect
# that line too: the old version ran `next` before it could, and every closed
# proposal read as open forever (2026-07-23, proposal 13). Body text only counts
# when it starts with `**Status:`, so a proposal that merely quotes another's
# status no longer marks itself closed; header match is case-sensitive on the
# file's uppercase convention so an ordinary "undecided" cannot collide.
# LAST status marker wins (2026-07-28): the previous version latched dec once set,
# so a proposal closed and later reopened (a real event: Proposal 17 was applied
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
