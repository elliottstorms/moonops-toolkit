#!/bin/bash
# selftest.sh — prove the self-heal loop actually works, end to end, on demand.
#
# The loop is a chain: SessionEnd hook -> distill.py gates -> queue -> heal pass
# -> ledger + state.json. Every link has failed at least once (the 7/18 gate leak
# in the sweep, the 7/19 same leak in the hook, a classifier-blocked edit that
# stalled a run). A chain nobody tests is a chain that is quietly broken, so this
# script exercises each link against a real fixture and prints PASS/FAIL.
#
# Read-only against real state: it snapshots state.json, runs every test in a
# scratch dir with synthetic transcripts, cleans its own artifacts out of queue/,
# and restores state.json byte-for-byte before exiting (including on error, via
# the EXIT trap). Safe to run any time.
#
# Usage:  bash ~/.claude/skills/self-heal/selftest.sh
# Exit:   0 = all pass, 1 = one or more failures.

ROOT="$HOME/.claude/self-heal"
SKILLS="$HOME/.claude/skills/self-heal"
HOOK="$HOME/.claude/bin/session-end-capture.sh"
Q="$ROOT/queue"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/selfheal-test.XXXXXX")
STATE_BAK="$WORK/state.json.bak"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

cleanup() {
  rm -f "$Q"/SELFTEST-*.md
  [ -f "$STATE_BAK" ] && cp "$STATE_BAK" "$ROOT/state.json"
  rm -rf "$WORK"
}
trap cleanup EXIT

[ -f "$ROOT/state.json" ] && cp "$ROOT/state.json" "$STATE_BAK"

# A transcript whose content is NOW (passes the age gate) and whose user text
# carries a real preference signal.
mk_fresh() {
  local sid="$1" out="$2" now
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  cat > "$out" <<EOF
{"type":"user","timestamp":"$now","sessionId":"$sid","cwd":"/Users/you/Claude","version":"selftest","message":{"content":"$3"}}
{"type":"assistant","timestamp":"$now","message":{"content":"assistant text that must never appear in a digest"}}
EOF
}

fire_hook() {  # sid, transcript path
  printf '{"session_id":"%s","transcript_path":"%s","reason":"selftest"}' "$1" "$2" | bash "$HOOK" >/dev/null 2>&1
}

echo "self-heal selftest — $(date '+%Y-%m-%d %H:%M')"

head_ "1. Files and syntax"
for f in "$HOOK" "$SKILLS/distill.py" "$SKILLS/state_update.py" "$SKILLS/SKILL.md"; do
  [ -f "$f" ] && ok "exists: ${f##*/}" || bad "MISSING: $f"
done
bash -n "$HOOK" 2>/dev/null && ok "hook parses (bash -n)" || bad "hook has a syntax error"
python3 -m py_compile "$SKILLS/distill.py" 2>/dev/null && ok "distill.py compiles" || bad "distill.py does not compile"
python3 -m py_compile "$SKILLS/state_update.py" 2>/dev/null && ok "state_update.py compiles" || bad "state_update.py does not compile"
python3 -c "import json;json.load(open('$ROOT/state.json'))" 2>/dev/null \
  && ok "state.json is valid JSON" || bad "state.json is corrupt — every age gate reads this"

head_ "2. Capture path (a real session ending gets queued)"
mk_fresh SELFTEST-FRESH "$WORK/fresh.jsonl" "always snapshot before editing an infra script"
fire_hook SELFTEST-FRESH "$WORK/fresh.jsonl"
if [ -f "$Q/SELFTEST-FRESH.md" ]; then
  ok "fresh session queued"
  grep -q "always snapshot" "$Q/SELFTEST-FRESH.md" && ok "her typed words survive into the digest" \
    || bad "typed user text missing from digest"
  grep -q "assistant text that must never appear" "$Q/SELFTEST-FRESH.md" \
    && bad "TRUST BOUNDARY BREACH: assistant text leaked into digest" \
    || ok "assistant text excluded (trust boundary holds)"
else
  bad "fresh session was NOT queued — capture is broken"
fi
rm -f "$Q/SELFTEST-FRESH.md"

# Compact-continuation summaries are assistant prose wearing a user label: on
# compaction the harness injects a type:"user" line flagged isCompactSummary.
# The 2026-08-28 trust-boundary audit caught distill.py counting them as her
# typed words (proposal 63). Put-the-bug-back proof: drop isCompactSummary from
# distill.py's user-line skip and this check fails.
NOWC=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
cat > "$WORK/compact.jsonl" <<EOF
{"type":"user","timestamp":"$NOWC","sessionId":"SELFTEST-COMPACT","cwd":"/Users/you/Claude","message":{"content":"a genuine typed line that should survive"}}
{"type":"user","timestamp":"$NOWC","isCompactSummary":true,"sessionId":"SELFTEST-COMPACT","message":{"content":"COMPACT-MARKER: this session is being continued from a previous conversation"}}
EOF
fire_hook SELFTEST-COMPACT "$WORK/compact.jsonl"
if [ -f "$Q/SELFTEST-COMPACT.md" ]; then
  grep -q "COMPACT-MARKER" "$Q/SELFTEST-COMPACT.md" \
    && bad "compact-continuation summary leaked into digest as typed text" \
    || ok "compact-continuation summary excluded (isCompactSummary gate)"
else
  bad "compact fixture session was NOT queued — cannot prove the isCompactSummary gate"
fi
rm -f "$Q/SELFTEST-COMPACT.md"

head_ "3. Content-age gate (hook side — the 2026-07-19 fix)"
grep -q 'skip-if-content-before' "$HOOK" && ok "hook passes --skip-if-content-before" \
  || bad "hook is missing the content-age gate (stale sessions will re-enter the queue)"
OLD="$WORK/old.jsonl"
cat > "$OLD" <<'EOF'
{"type":"user","timestamp":"2026-06-23T20:53:00.000Z","sessionId":"SELFTEST-OLD","cwd":"/Users/you","message":{"content":"pre-loop history that /insights already mined"}}
EOF
fire_hook SELFTEST-OLD "$OLD"
[ -f "$Q/SELFTEST-OLD.md" ] && { bad "stale session leaked into queue"; rm -f "$Q/SELFTEST-OLD.md"; } \
  || ok "stale session gated at capture time"

head_ "4. Never-block contract (a broken state.json must not stop capture)"
mv "$ROOT/state.json" "$WORK/state.hidden"
mk_fresh SELFTEST-NOSTATE "$WORK/nostate.jsonl" "capture must survive a missing state file"
fire_hook SELFTEST-NOSTATE "$WORK/nostate.jsonl"
[ -f "$Q/SELFTEST-NOSTATE.md" ] && ok "captures with state.json absent (fails open)" \
  || bad "missing state.json blocked capture — hook must never block a session exit"
rm -f "$Q/SELFTEST-NOSTATE.md"
echo 'not json {{{' > "$ROOT/state.json"
mk_fresh SELFTEST-BADSTATE "$WORK/badstate.jsonl" "capture must survive a corrupt state file"
fire_hook SELFTEST-BADSTATE "$WORK/badstate.jsonl"
[ -f "$Q/SELFTEST-BADSTATE.md" ] && ok "captures with state.json corrupt (fails open)" \
  || bad "corrupt state.json blocked capture"
rm -f "$Q/SELFTEST-BADSTATE.md"
mv "$WORK/state.hidden" "$ROOT/state.json"

head_ "5. Loop guard (the loop must not study itself)"
NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
cat > "$WORK/heal.jsonl" <<EOF
{"type":"user","timestamp":"$NOW","sessionId":"SELFTEST-HEAL","message":{"content":"<scheduled-task name=\"self-heal-daily\">run the full heal pass</scheduled-task>"}}
EOF
fire_hook SELFTEST-HEAL "$WORK/heal.jsonl"
[ -f "$Q/SELFTEST-HEAL.md" ] && { bad "a heal run was queued for learning"; rm -f "$Q/SELFTEST-HEAL.md"; } \
  || ok "self-heal's own run gated"

head_ "6. Atomic state writes"
python3 "$SKILLS/state_update.py" selftest_marker='"x"' >/dev/null 2>&1 \
  && ok "state_update.py writes" || bad "state_update.py failed to write"
python3 -c "import json;json.load(open('$ROOT/state.json'))" 2>/dev/null \
  && ok "state.json still valid after write" || bad "state_update.py corrupted state.json"
python3 "$SKILLS/state_update.py" bogus >/dev/null 2>&1
[ $? -eq 2 ] && ok "rejects malformed args with exit 2" || bad "bad args not rejected"
python3 -c "import json;json.load(open('$ROOT/state.json'))" 2>/dev/null \
  && ok "state.json intact after a rejected write" || bad "failed write damaged state.json"

head_ "7. Bookkeeping surfaces"
[ -f "$ROOT/ledger.md" ] && ok "ledger.md present ($(wc -l < "$ROOT/ledger.md" | tr -d ' ') lines)" || bad "ledger.md missing"
[ -f "$ROOT/pending-review.md" ] && ok "pending-review.md present" || bad "pending-review.md missing"
[ -d "$ROOT/snapshots" ] && ok "snapshots/ present ($(ls "$ROOT/snapshots" | wc -l | tr -d ' ') runs)" || bad "snapshots/ missing"
# grep -c prints 0 AND exits 1 when there are no matches, so a `|| echo 0`
# fallback would emit "0\n0" and break the integer test. Swallow the status
# with `|| true` instead and default only when the file is absent.
CAPERR=$(grep -c 'ERROR:' "$ROOT/logs/capture.log" 2>/dev/null || true)
CAPERR=${CAPERR:-0}
[ "$CAPERR" -eq 0 ] && ok "no ERROR lines in capture.log" || bad "$CAPERR ERROR line(s) in capture.log — investigate"
LOGLEN=$(wc -l < "$ROOT/logs/capture.log" 2>/dev/null | tr -d ' ' || true)
LOGLEN=${LOGLEN:-0}
[ "$LOGLEN" -le 2000 ] && ok "capture.log within rotation cap ($LOGLEN lines)" || bad "capture.log not rotating ($LOGLEN lines)"
# One `**Status:` line per proposal block, or the banner counter cannot be
# trusted: dual status lines that drift apart is how the 2026-07-28 incident's
# repair left 16 and 18 self-contradictory, and the counter's last-wins rule
# (session-start.sh, 2026-07-28) assumes the newest marker is THE marker.
DUPSTAT=$(awk '
  /^## Proposal / { if (blk!="" && n>1) print blk; blk=$0; n=0; next }
  /^## /          { if (blk!="" && n>1) print blk; blk="" }
  blk!="" && /^\*\*Status:/ { n++ }
  END             { if (blk!="" && n>1) print blk }
' "$ROOT/pending-review.md" 2>/dev/null)
[ -z "$DUPSTAT" ] && ok "one Status line per proposal block" || bad "dual Status lines in: $(echo "$DUPSTAT" | tr '\n' ';')"
# One `## Proposal N` heading per proposal number. Closing a proposal used to add
# an APPLIED heading and leave the original under a second `## Proposal N`, and the
# banner counter reads `## ` headings, so the preserved copy read open forever: the
# count grew by one per proposal applied and hit 6 against a true 0 on 2026-08-09.
# A preserved original belongs at `### Proposal N, original finding` (SKILL.md §6).
DUPHEAD=$(awk '
  /^## Proposal / { id=$3; gsub(/[^0-9A-Za-z]/,"",id); cnt[id]++ }
  END            { for (i in cnt) if (cnt[i]>1) printf "%s ", i }
' "$ROOT/pending-review.md" 2>/dev/null)
[ -z "$DUPHEAD" ] && ok "one '## Proposal N' heading per proposal number" \
                  || bad "duplicate '## Proposal N' headings for: $DUPHEAD(preserved originals belong at '### ')"
# The proposal counter itself, against fixtures covering both stale-banner
# directions: closed-reads-open (the 2026-07-23 bug) and reopened-reads-closed
# (the sticky-dec inverse, fixed 2026-07-28). Since 2026-08-29 (proposal 64
# option 2) there is ONE implementation, state_update.py --count-only, called by
# both session-start.sh and the state writer, so this exercises the live code
# directly instead of extracting an awk out of the hook.
COUNTER="$SKILLS/state_update.py"
if [ -f "$COUNTER" ]; then
  cat > "$WORK/fix1.md" <<'FIX'
## Proposal 90 — something still open
**Status: open**
## Proposal 91 — APPLIED 2026-01-01 — closed in header
body text
## Proposal 92 — closed in body only
**Status: applied 2026-01-01, closed.**
## Proposal 93 — applied then reopened
**Status: applied 2026-01-01.**
**Status: open — downgraded, the edit never landed**
## Proposal 94 — discusses another proposal
This block quotes `## Proposal 91 — APPLIED` and the word applied in prose.
**Status: open**
FIX
  GOT=$(python3 -B "$COUNTER" --count-only "$WORK/fix1.md" 2>/dev/null)
  [ "$GOT" = "3" ] && ok "proposal counter fixtures (open/header-closed/body-closed/reopened/quoting) -> 3" \
                   || bad "proposal counter fixtures expected 3, got $GOT"
  # DECLINED is the word this loop writes when you declines a proposal, and it
  # was in NEITHER of the old awk's two decided-word lists. Proposal 60 counted
  # correctly on 2026-08-28 only because its status sentence happened to end in
  # "closed"; a bare DECLINED would have read open forever, which is the
  # 2026-07-23 bug class under a different word (proposal 64, 2026-08-29).
  cat > "$WORK/fix2.md" <<'FIX'
## Proposal 95 — declined with no other decided word in the line
**Status: DECLINED 2026-08-29.**
FIX
  GOT=$(python3 -B "$COUNTER" --count-only "$WORK/fix2.md" 2>/dev/null)
  [ "$GOT" = "0" ] && ok "a bare '**Status: DECLINED' reads as closed" \
                   || bad "bare DECLINED not recognised as decided (got $GOT open)"
  # The hook must never go silent on a counter failure: a hidden count reads as
  # "no proposals waiting", the silent-instrument failure. Point the hook's own
  # logic at a missing file and require the loud UNAVAILABLE line.
  GOT=$(python3 -B "$COUNTER" --count-only "$WORK/nonexistent.md" 2>/dev/null)
  case "$GOT" in
    ''|*[!0-9]*) ok "counter failure yields non-numeric, so the banner falls through to UNAVAILABLE" ;;
    *)           bad "counter returned '$GOT' for a missing file instead of failing loudly" ;;
  esac
else
  bad "state_update.py missing — the proposal counter cannot be tested"
fi
# The hook must call the shared counter, not carry a second copy of the rules.
if grep -q 'count-only' "$HOME/.claude/bin/session-start.sh" 2>/dev/null &&
   ! grep -q 'inblk && !dec' "$HOME/.claude/bin/session-start.sh" 2>/dev/null; then
  ok "session-start.sh delegates counting (no second implementation)"
else
  bad "session-start.sh is not delegating to --count-only (drift: two counters again)"
fi

head_ "8. Managed-block integrity across the skill library"
BADBLOCK=0
for f in "$HOME"/.claude/skills/*/SKILL.md "$HOME"/.claude/agents/*.md; do
  [ -f "$f" ] || continue
  read -r s e <<<"$(awk '/self-heal:start/{s++} /self-heal:end/{e++} END{print s+0, e+0}' "$f")"
  if [ "$s" != "$e" ] || [ "$s" -gt 1 ]; then
    bad "marker imbalance in ${f#$HOME/.claude/}: $s start / $e end"; BADBLOCK=1
  fi
done
[ $BADBLOCK -eq 0 ] && ok "all managed blocks have balanced 1/1 markers"

printf '\n\033[1mRESULT: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
