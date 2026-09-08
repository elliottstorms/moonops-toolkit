#!/bin/sh
# restore_drill.sh: clone the cloud mirror and prove it matches live sources.
# Read-only with respect to everything except its own temp dir.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REPO="your-username/your-backup-repo"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

echo "cloning $REPO (fresh from GitHub, not the local stage)..."
gh repo clone "$REPO" "$T/mirror" -- -q --depth 1

# The mirror commit's own timestamp is the reference clock for every drift
# verdict below. A file edited AFTER this moment is expected to differ; a file
# last touched BEFORE it that still differs means the mirror is missing content.
# Added 2026-08-26 on your ask, after a drill run 18 minutes past a backup
# printed the DRIFT FOUND headline for four files that were all pure post-backup
# churn (gmail-mirror and bnc-sales-watch both write state on a 15-minute poll,
# so the old headline fired on essentially every non-immediate run and the
# operator had to hand-check four mtimes to learn nothing was wrong).
MIRROR_EPOCH=$(git -C "$T/mirror" log -1 --format=%ct 2>/dev/null || echo 0)
MIRROR_WHEN=$(git -C "$T/mirror" log -1 --format=%ad --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || echo unknown)

drift_benign=0
drift_real=0

# classify_out <live-root> <mirror-sub> <diff-output>
# Annotates each diff line with a verdict and counts it. Prints nothing when the
# output is empty. Sets nothing global except the two counters.
classify_out() {
  _root="$1"; _sub="$2"; _out="$3"
  printf '%s\n' "$_out" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    _path=""; _kind=""
    case "$line" in
      "Files "*" and "*" differ")
        _rest="${line#Files }"; _path="${_rest%% and *}"; _kind="differs" ;;
      "Only in "*)
        _d="${line#Only in }"; _dir="${_d%%:*}"; _name="${_d#*: }"
        _path="$_dir/$_name"
        case "$_dir" in
          "$T"*) _kind="mirror-only" ;;   # in the backup, gone from live
          *)     _kind="live-only"   ;;   # on the machine, absent from the backup
        esac ;;
      *) printf '    %s\n' "$line"; continue ;;
    esac

    # A file the mirror has and live does not is never a restore risk: restoring
    # would bring it back. Name it, do not fail on it.
    if [ "$_kind" = "mirror-only" ]; then
      printf '    [benign: deleted locally since the backup] %s\n' "$line"
      echo "B" >> "$T/.tally"; continue
    fi

    _mt=$(stat -f %m "$_path" 2>/dev/null || echo 0)
    if [ "$_mt" -gt "$MIRROR_EPOCH" ] 2>/dev/null; then
      _when=$(stat -f '%Sm' -t '%H:%M:%S' "$_path" 2>/dev/null || echo '?')
      printf '    [benign: edited %s, after the backup] %s\n' "$_when" "$line"
      echo "B" >> "$T/.tally"
    else
      _when=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$_path" 2>/dev/null || echo '?')
      if [ "$_kind" = "live-only" ]; then
        printf '    [REAL: last touched %s and NOT IN THE MIRROR AT ALL] %s\n' "$_when" "$line"
      else
        printf '    [REAL: last touched %s, before the backup, and still differs] %s\n' "$_when" "$line"
      fi
      echo "R" >> "$T/.tally"
    fi
  done
}

# Content the mirror could actually carry: every file except the runtime noise
# that backup.sh's rsync excludes (backup.sh:55) and this drill's own diff
# filter both drop already. Prints the first such file, or nothing.
#
# Why this is not just `ls -A` (2026-09-08): scheduled-tasks/bnc-demand-counter
# is a retired task whose only remaining files are launchd.err.log and
# launchd.out.log. rsync drops both, so the directory reaches the mirror empty,
# and git cannot track an empty directory. The old literal-emptiness test saw
# two files, called the folder restorable, and reported REAL DRIFT on a mirror
# that was missing nothing. Verified before changing anything: the path has
# never existed in the mirror's history, so nothing was ever lost.
#
# That mattered because it would have fired on EVERY run from then on, and a
# drill that is permanently red is a drill nobody reads. Deliberately narrow:
# a directory holding any file that is not on this noise list still reports
# drift, which is the case tests/ below actually exercises.
_restorable_content() {
  find "$1" -type f \
    ! -name '.DS_Store' ! -name '*.pyc' ! -name '*.log' ! -name '*.tmp' \
    ! -name '.backup-needed' ! -path '*/__pycache__/*' 2>/dev/null | head -1
}

# git cannot represent empty directories, so a live empty dir is never in the
# mirror clone, so "Only in" lines pointing at empty dirs are not restorable
# content and get dropped here.
filter_empty_dirs() {
  while IFS= read -r line; do
    case "$line" in
      "Only in "*)
        d="${line#Only in }"
        dir="${d%%:*}"; name="${d#*: }"
        if [ -d "$dir/$name" ] && [ -z "$(_restorable_content "$dir/$name")" ]; then
          continue
        fi
        ;;
    esac
    [ -n "$line" ] && printf '%s\n' "$line"
  done
}

check() {  # check <live-path> <mirror-subpath> [extra diff excludes...]
  live="$1"; sub="$2"; shift 2
  [ -e "$live" ] || { echo "skip (no live source): $live"; return 0; }
  # Same empty-dir rule as filter_empty_dirs, but for a whole scope. When the
  # live dir is empty the mirror has no such path at all, so `diff -rq` fails
  # with "No such file or directory" instead of emitting "Only in" lines, and
  # the filter below never sees it. Absence is the faithful representation of an
  # empty dir, not data loss. Without this the scope reports drift on every run
  # forever and the drill can never go green, which is how a check stops being
  # read. Still reports drift when the live dir HAS content and the mirror does
  # not: that is a real gap in backup.sh's include list.
  if [ -d "$live" ] && [ -z "$(ls -A "$live" 2>/dev/null)" ] && [ ! -e "$T/mirror/$sub" ]; then
    echo "match: $sub (live dir empty; git cannot track empty dirs)"
    return 0
  fi
  if [ -d "$live" ]; then
    out=$(diff -rq "$@" "$live" "$T/mirror/$sub" 2>&1 \
          | grep -v -E '\.DS_Store|__pycache__|\.pyc|\.log|\.tmp|\.backup-needed' \
          | filter_empty_dirs || true)
  else
    out=$(diff -q "$live" "$T/mirror/$sub" 2>&1 || true)
  fi
  if [ -n "$out" ]; then
    echo "drift: $live <-> mirror/$sub"
    classify_out "$live" "$sub" "$out"
  else
    echo "match: $sub"
  fi
}

check "$HOME/Claude/TASKS.md"                 "workspace/TASKS.md"
check "$HOME/Claude/README.md"                "workspace/README.md"
check "$HOME/Claude/Toolkit"                  "toolkit"
check "$HOME/Claude/Scheduled"                "scheduled"
check "$HOME/.claude/CLAUDE.md"               "claude-config/CLAUDE.md"
check "$HOME/.claude/settings.json"           "claude-config/settings.json"
check "$HOME/.claude/settings.local.json"     "claude-config/settings.local.json"
check "$HOME/.claude/skills"                  "claude-config/skills"
check "$HOME/.claude/agents"                  "claude-config/agents"
check "$HOME/.claude/bin"                     "claude-config/bin"
check "$HOME/.claude/scheduled-tasks"         "claude-config/scheduled-tasks"
check "$HOME/.claude/projects/-Users-you/memory" "memory"
# active memory: private-contact.md is EXCLUDED by design, so diff around it
if [ -d "$HOME/.claude/projects/-Users-you-Claude/memory" ]; then
  out=$(diff -rq "$HOME/.claude/projects/-Users-you-Claude/memory" "$T/mirror/memory-active" 2>&1 \
        | grep -v 'private-contact.md' || true)
  if [ -n "$out" ]; then
    echo "drift: active memory"
    classify_out "$HOME/.claude/projects/-Users-you-Claude/memory" "memory-active" "$out"
  else echo "match: memory-active (PII exclusion intact)"; fi
fi

echo "last mirror commit: $(git -C "$T/mirror" log -1 --format='%h %ad %s' --date=format:'%Y-%m-%d %H:%M')"

# The tally is a file rather than a variable because classify_out runs inside a
# `while read` pipeline, which /bin/sh executes in a subshell: counters
# incremented in there never reach the parent. This bit me on the first cut.
# NOTE: `grep -c` prints 0 AND exits 1 when nothing matches, so the obvious
# `$(grep -c ... || echo 0)` yields a two-line "0\n0" that makes the -gt test
# below die with "integer expression expected". Assign, then correct on failure.
drift_benign=$(grep -c '^B' "$T/.tally" 2>/dev/null) || drift_benign=0
drift_real=$(grep -c '^R' "$T/.tally" 2>/dev/null) || drift_real=0

if [ "$drift_real" -gt 0 ]; then
  echo "RESTORE DRILL: REAL DRIFT: $drift_real file(s) predate the $MIRROR_WHEN backup and still differ."
  echo "  The mirror is missing content. Check backup.sh's include list and its rsync excludes."
  [ "$drift_benign" -gt 0 ] && echo "  ($drift_benign further difference(s) are post-backup churn and are not the problem.)"
  exit 1
elif [ "$drift_benign" -gt 0 ]; then
  echo "RESTORE DRILL: PASS. Every live source restores; $drift_benign file(s) differ purely as post-backup churn (edited since $MIRROR_WHEN)."
else
  echo "RESTORE DRILL: PASS. Cloud mirror matches every live source"
fi
