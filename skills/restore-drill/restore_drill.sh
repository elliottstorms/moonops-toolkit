#!/bin/sh
# restore_drill.sh: clone the cloud mirror and prove it matches live sources.
# Read-only with respect to everything except its own temp dir.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REPO="your-username/your-backup-repo"
# Two test hooks (added 2026-09-23), the same convention as build-public-toolkit.sh's
# SRC and OUT overrides. A real drill sets neither, and the first line of output says
# so whenever MIRROR_CLONE is set.
#   BACKUP_SH     read the copy rules from this file instead of the live backup.sh, so
#                 a deliberately broken copy can prove the drill follows the rules it
#                 reads rather than rules of its own.
#   MIRROR_CLONE  compare against this existing clone instead of cloning fresh, so a
#                 deliberately damaged clone can prove a missing or altered file is caught.
BACKUP_SH="${BACKUP_SH:-$HOME/Claude/Toolkit/backup/backup.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
: > "$T/.checked"   # every mirror path some check below covers, for the coverage check
: > "$T/.tally"

# ---- the copy rules, read out of backup.sh itself (added 2026-09-23) ----
# Everything this drill checked before that date is a plain copy of a folder or a
# file, so `diff` against the clone was enough. The rest of the mirror is not: the
# projects, the workspace extras and the LinkedIn carve-out are copied with rsync
# exclusions, a 5 MB cap, and per-file holdbacks for privacy terms and for pages that
# embed media as base64 text. None of that may read as drift, and a second copy of
# those rules kept in here would quietly go stale the first time backup.sh changed.
# So the drill reads them out of backup.sh at run time: the R() rsync wrapper, each
# scope's own rsync call, the privacy patterns and the canary lines that prove them,
# and the lists. It runs those rsync calls in dry-run mode to learn exactly which
# files backup.sh would copy right now, and compares that set with the clone.
#
# Two things are code rather than data and are restated here: which scopes run the
# privacy and embedded-media holdbacks (and with which case rules), and where each
# workspace extra lands. Every restatement is paired with a SHAPE CHECK, a fixed line
# it expects to find in backup.sh, so a change there stops the drill with CANNOT RUN
# instead of letting it compare against rules that no longer apply.
#
# A scope group that backup.sh does not configure at all is skipped, not failed: the
# public edition of backup.sh has only the plain copies, and the drill still has to
# work against it.
[ -r "$BACKUP_SH" ] || { echo "RESTORE DRILL: CANNOT RUN: no readable backup.sh at $BACKUP_SH"; exit 2; }

bk_problems=""
bk_problem() { bk_problems="$bk_problems
    - $1"; }
bk_count() { grep -cF -- "$1" "$BACKUP_SH" || true; }   # lines holding a fixed string

# NAME='...' on one line at column 0; the value is taken verbatim
bk_sq() {
  BK_VAL=""
  [ "$(grep -c "^$1='" "$BACKUP_SH" || true)" = 1 ] || return 1
  BK_VAL=$(sed -n "s/^$1='\(.*\)'\$/\1/p" "$BACKUP_SH")
  [ -n "$BK_VAL" ]
}
# NAME="..." on one line at column 0; $HOME is expanded and anything else refused
bk_dq() {
  BK_VAL=""
  [ "$(grep -c "^$1=\"" "$BACKUP_SH" || true)" = 1 ] || return 1
  BK_VAL=$(sed -n "s/^$1=\"\(.*\)\"\$/\1/p" "$BACKUP_SH")
  case "$BK_VAL" in *'`'*|*'$('*) return 1 ;; esac
  BK_VAL=$(printf '%s' "$BK_VAL" | sed "s|\\\$HOME|$HOME|g")
  case "$BK_VAL" in *'$'*) return 1 ;; esac
  [ -n "$BK_VAL" ]
}
# The whole command that starts on the one line holding ANCHOR, following backslash
# continuations. Accepted only as a single `R ...` call with no chaining, pipes,
# substitutions or redirects, so evaluating it can do nothing but call R, and R below
# is a dry run.
bk_cmd() {
  BK_VAL=""
  [ "$(bk_count "$1")" = 1 ] || return 1
  BK_VAL=$(awk -v a="$1" '
    !on && index($0, a) { on = 1 }
    on { l = $0; c = (l ~ /\\$/); sub(/\\$/, "", l); sub(/^[ \t]+/, "", l); printf "%s ", l; if (!c) exit }
  ' "$BACKUP_SH")
  case "$BK_VAL" in 'R '*) ;; *) return 1 ;; esac
  case "$BK_VAL" in *';'*|*'|'*|*'&'*|*'$('*|*'`'*|*'>'*|*'<'*) return 1 ;; esac
}
# The body of backup.sh's R() wrapper: one rsync call ending in "$@"
bk_rbase() {
  BK_VAL=$(awk '/^R\(\) \{$/ { on = 1; next } on && /^\}$/ { exit }
    on { l = $0; sub(/\\$/, "", l); sub(/^[ \t]+/, "", l); printf "%s ", l }' "$BACKUP_SH")
  case "$BK_VAL" in 'rsync '*'"$@" ') ;; *) return 1 ;; esac
  case "$BK_VAL" in *';'*|*'|'*|*'&'*|*'$('*|*'`'*|*'>'*|*'<'*) return 1 ;; esac
}
bk_shape() {  # bk_shape N FIXED WHAT: backup.sh must hold FIXED on exactly N lines
  if [ "$(bk_count "$2")" != "$1" ]; then bk_problem "$3 (expected $1 line(s) holding: $2)"; fi
  return 0
}
one_line() { [ -n "$1" ] && [ "$(printf '%s\n' "$1" | wc -l | tr -d ' ')" = 1 ]; }

HAVE_PROJ=0; HAVE_LI=0; HAVE_WS=0; HAVE_LAUNCHD=0
if grep -q '^PROJ_ALLOW="' "$BACKUP_SH"; then HAVE_PROJ=1; fi
if grep -q '^LI_SRC="' "$BACKUP_SH"; then HAVE_LI=1; fi
if grep -q '^WS_EXTRA="' "$BACKUP_SH"; then HAVE_WS=1; fi
if [ "$(bk_count "--include='com.moonops.*.plist'")" != 0 ]; then HAVE_LAUNCHD=1; fi
PII_RE_PROJ=""; PII_RE_LI=""; EMB_RE=""; PROJ_SRC=""; PROJ_ALLOW=""; WS_EXTRA=""; LI_SRC=""
CMD_PROJ=""; CMD_LI=""; CMD_LAUNCHD=""; CMD_WS=""; CMD_WS_AUDIO=""; PLD_DEFAULT=""; PLD_CASE=""

if [ $((HAVE_PROJ + HAVE_LI + HAVE_WS + HAVE_LAUNCHD)) -gt 0 ]; then
  if bk_rbase; then eval "_bk_R() { $BK_VAL; }"; else bk_problem "the R() rsync wrapper that every scope copies with"; fi
fi
if [ $((HAVE_PROJ + HAVE_LI + HAVE_WS)) -gt 0 ]; then
  # backup.sh proves its privacy patterns against two fixed lines before every run:
  # one that must be held back and one innocent line that must not. The drill reuses
  # both, so a pattern that reads back empty (which would match everything, hold back
  # every file, and leave nothing to compare) cannot slip through as a clean pass.
  CANARY_HIT=$(grep -F "if ! printf '" "$BACKUP_SH" | cut -d"'" -f2 | sed 's/\\n$//')
  CANARY_MISS=$(grep -F "if printf '" "$BACKUP_SH" | cut -d"'" -f2 | sed 's/\\n$//')
  one_line "$CANARY_HIT" && one_line "$CANARY_MISS" || bk_problem "the two canary lines that prove the privacy patterns"
  EMB_RE=$(sed -n "s/.*grep -rlE '\(data:[^']*\)'.*/\1/p" "$BACKUP_SH" | sort -u)
  one_line "$EMB_RE" || bk_problem "the embedded-media pattern (one grep -rlE 'data:...' pattern, the same everywhere)"
  if ! printf 'x data:image/png;base64,AAAA\n' | grep -qE -- "${EMB_RE:-.}"; then
    bk_problem "the embedded-media pattern read from backup.sh misses a base64 image"
  fi
  bk_shape 2 "grep -rlE 'data:" "the embedded-media holdback runs in two scopes"
  bk_shape 2 "--include='*.html' --include='*.md'" "the embedded-media holdback reads only .html and .md files"
fi
canary_ok() {  # canary_ok PATTERN: backup.sh's own canary must hit, its innocent line must not
  printf '%s\n' "$CANARY_HIT" | grep -qiE -- "$1" || return 1
  if printf '%s\n' "$CANARY_MISS" | grep -qiE -- "$1"; then return 1; fi
  return 0
}
if [ "$HAVE_PROJ" = 1 ] || [ "$HAVE_WS" = 1 ]; then
  if bk_sq PII_RE_PROJ && canary_ok "$BK_VAL"; then PII_RE_PROJ="$BK_VAL"; else bk_problem "PII_RE_PROJ, or it fails backup.sh's own canary"; fi
fi
if [ "$HAVE_PROJ" = 1 ]; then
  if bk_dq PROJ_SRC; then PROJ_SRC="$BK_VAL"; else bk_problem "PROJ_SRC"; fi
  if bk_dq PROJ_ALLOW; then PROJ_ALLOW="$BK_VAL"; else bk_problem "PROJ_ALLOW"; fi
  if bk_cmd 'R --delete-excluded --exclude-from="$PROJ_DENY"'; then CMD_PROJ="$BK_VAL"; else bk_problem "the projects rsync call"; fi
  # the one per-project subtree that stays local: a default plus a case line
  PLD_DEFAULT=$(sed -n 's/^ *PROJ_LOCAL_DIR="\([^"$`]*\)" *$/\1/p' "$BACKUP_SH")
  PLD_CASE=$(grep -E '^ *case "\$p" in ' "$BACKUP_SH" || true)
  one_line "$PLD_DEFAULT" || bk_problem "the PROJ_LOCAL_DIR default"
  if ! one_line "$PLD_CASE" || ! printf '%s\n' "$PLD_CASE" \
       | grep -qE '^ *case "\$p" in( [A-Za-z0-9._-]+\) PROJ_LOCAL_DIR="[^"$`]*" ;;)+ esac *$'; then
    bk_problem "the PROJ_LOCAL_DIR case line (only project) PROJ_LOCAL_DIR=\"dir\" ;; entries)"
  fi
  bk_shape 1 '( cd "$PROJ_SRC/$p" && grep -rilE \' "the projects privacy holdback (case-insensitive, every file)"
fi
if [ "$HAVE_LI" = 1 ]; then
  if bk_sq PII_RE_LI && canary_ok "$BK_VAL"; then PII_RE_LI="$BK_VAL"; else bk_problem "PII_RE_LI, or it fails backup.sh's own canary"; fi
  if bk_dq LI_SRC; then LI_SRC="$BK_VAL"; else bk_problem "LI_SRC"; fi
  if bk_cmd 'R --delete-excluded --exclude-from="$LI_DENY"'; then CMD_LI="$BK_VAL"; else bk_problem "the LinkedIn rsync call"; fi
  bk_shape 1 '( cd "$LI_SRC" && grep -rilE \' "the LinkedIn privacy holdback (case-insensitive, every file, no embedded-media holdback)"
fi
if [ "$HAVE_WS" = 1 ]; then
  if bk_dq WS_EXTRA; then WS_EXTRA="$BK_VAL"; else bk_problem "WS_EXTRA"; fi
  if bk_cmd 'R -m --delete-excluded --exclude-from="$WS_DENY"'; then CMD_WS_AUDIO="$BK_VAL"; else bk_problem "the Audio rsync call"; fi
  if bk_cmd 'R --delete-excluded --exclude-from="$WS_DENY"'; then CMD_WS="$BK_VAL"; else bk_problem "the workspace extras rsync call"; fi
  bk_shape 1 '( cd "$HOME/Claude/$w" && grep -rilE "$PII_RE_PROJ" .' "the workspace privacy holdback (case-insensitive, every file)"
  bk_shape 1 'if [ "$w" = "Audio" ]; then' "Audio is the one workspace extra with its own destination"
  bk_shape 1 'dest="$STAGE/workspace/audio-scripts"' "the Audio destination"
  bk_shape 1 'dest="$STAGE/workspace/$lw"' "the destination of every other workspace extra"
  bk_shape 1 "| tr '[:upper:]' '[:lower:]')" "workspace extras land under a lower-cased name"
fi
if [ "$HAVE_LAUNCHD" = 1 ]; then
  if bk_cmd "--include='com.moonops.*.plist' --exclude='*'"; then CMD_LAUNCHD="$BK_VAL"; else bk_problem "the launchd rsync call"; fi
fi
# Every single file backup.sh copies with a plain cp, loop lists expanded, so a file it
# starts copying is checked from that day on without anyone editing this drill.
: > "$T/.cpfiles"
grep -E 'cp "\$HOME/[^"]*" +"\$STAGE/[^"]*"' "$BACKUP_SH" \
  | sed -E 's/.*cp "\$HOME\/([^"]*)" +"\$STAGE\/([^"]*)".*/\1|\2/' | LC_ALL=C sort -u > "$T/.cps" || true
while IFS='|' read -r s d; do
  v=$(printf '%s' "$s" | sed -n 's/.*\$\([a-z_][a-z_]*\).*/\1/p')
  if [ -z "$v" ]; then printf '%s|%s\n' "$s" "$d" >> "$T/.cpfiles"; continue; fi
  lst=$(sed -n "s/^ *for $v in \\([^;\$\`]*\\); do *\$/\\1/p" "$BACKUP_SH")
  if ! one_line "$lst"; then bk_problem "the loop list behind cp \"\$HOME/$s\""; continue; fi
  for item in $lst; do
    printf '%s|%s\n' "$(printf '%s' "$s" | sed "s/\\\$$v/$item/")" "$(printf '%s' "$d" | sed "s/\\\$$v/$item/")" >> "$T/.cpfiles"
  done
done < "$T/.cps"

if [ -n "$bk_problems" ]; then
  echo "RESTORE DRILL: CANNOT RUN: this drill reads its copy rules out of $BACKUP_SH, and these parts no longer have the shape it expects:$bk_problems"
  echo "  Update restore_drill.sh to match backup.sh before trusting any verdict. Nothing was compared."
  exit 2
fi

if [ -n "${MIRROR_CLONE:-}" ]; then
  echo "TEST MODE: comparing against the existing clone $MIRROR_CLONE, not a fresh one from GitHub"
  ln -s "$MIRROR_CLONE" "$T/mirror"
else
  echo "cloning $REPO (fresh from GitHub, not the local stage)..."
  gh repo clone "$REPO" "$T/mirror" -- -q --depth 1
fi

# The mirror commit's own timestamp is the reference clock for every drift
# verdict below. A file edited AFTER this moment is expected to differ; a file
# last touched BEFORE it that still differs means the mirror is missing content.
# Added 2026-08-26 on the owner's ask, after a drill run 18 minutes past a backup
# printed the DRIFT FOUND headline for four files that were all pure post-backup
# churn (gmail-mirror and bnc-sales-watch both write state on a 15-minute poll,
# so the old headline fired on essentially every non-immediate run and the
# operator had to hand-check four mtimes to learn nothing was wrong).
MIRROR_EPOCH=$(git -C "$T/mirror" log -1 --format=%ct 2>/dev/null || echo 0)
MIRROR_WHEN=$(git -C "$T/mirror" log -1 --format=%ad --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || echo unknown)
# Two refinements to that clock (2026-09-23), both found by the first full-coverage run:
#  1. It reads a file's CHANGE time (ctime), not its modification time. cp -p, rsync -a
#     and git checkouts stamp a fresh copy with an old mtime, so a file written today can
#     look months old: that run called a file archived with cp -p, minutes after the
#     backup, "last touched 2026-08-26 and NOT IN THE MIRROR AT ALL". Nothing can set
#     ctime back; any write, copy or rename moves it forward.
#  2. The backup takes minutes and copies each scope at a different moment before the
#     commit that sets MIRROR_EPOCH, so a file changed shortly before the commit may
#     simply have missed its scope's copy (four files created mid-run did exactly that).
#     A change inside BACKUP_RUN_WINDOW seconds before the commit is named, not failed.
#     If the backup truly cannot carry the file, the next drill after the next backup
#     sees it again, older than the commit, and fails then.
BACKUP_RUN_WINDOW=900

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
      # 2026-09-23: a line of any other shape used to be printed and never counted,
      # so a drill could show it and still say PASS. A line the drill cannot read is
      # a file it did not verify, which is never a pass.
      *) printf '    [REAL: the drill could not compare this] %s\n' "$line"
         echo "R" >> "$T/.tally"; continue ;;
    esac

    # A file the mirror has and live does not is never a restore risk: restoring
    # would bring it back. Name it, do not fail on it.
    if [ "$_kind" = "mirror-only" ]; then
      printf '    [benign: deleted locally since the backup] %s\n' "$line"
      echo "B" >> "$T/.tally"; continue
    fi

    _mt=$(stat -f %c "$_path" 2>/dev/null || echo 0)
    if [ "$_mt" -gt "$MIRROR_EPOCH" ] 2>/dev/null; then
      _when=$(stat -f '%Sc' -t '%H:%M:%S' "$_path" 2>/dev/null || echo '?')
      printf '    [benign: changed %s, after the backup] %s\n' "$_when" "$line"
      echo "B" >> "$T/.tally"
    elif [ "$_mt" -gt $((MIRROR_EPOCH - BACKUP_RUN_WINDOW)) ] 2>/dev/null; then
      _when=$(stat -f '%Sc' -t '%H:%M:%S' "$_path" 2>/dev/null || echo '?')
      printf '    [benign: changed %s, while the backup was running; the next backup settles it] %s\n' "$_when" "$line"
      echo "B" >> "$T/.tally"
    else
      _when=$(stat -f '%Sc' -t '%Y-%m-%d %H:%M:%S' "$_path" 2>/dev/null || echo '?')
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
  echo "$sub" >> "$T/.checked"
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
  if [ ! -e "$T/mirror/$sub" ]; then
    # 2026-09-23: when the mirror lacked the path entirely, diff printed "No such
    # file or directory", a line classify_out did not recognize, so it was shown and
    # never counted: a single mirrored file could vanish from the cloud copy and the
    # drill still said PASS. It is now reported as live content with no copy in the
    # mirror, and classified like any other.
    out=$(printf 'Only in %s: %s\n' "$(dirname "$live")" "$(basename "$live")" | filter_empty_dirs || true)
  elif [ -d "$live" ]; then
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
echo "memory-active" >> "$T/.checked"
if [ -d "$HOME/.claude/projects/-Users-you-Claude/memory" ]; then
  out=$(diff -rq "$HOME/.claude/projects/-Users-you-Claude/memory" "$T/mirror/memory-active" 2>&1 \
        | grep -v 'private-contact.md' || true)
  if [ -n "$out" ]; then
    echo "drift: active memory"
    classify_out "$HOME/.claude/projects/-Users-you-Claude/memory" "memory-active" "$out"
  else echo "match: memory-active (PII exclusion intact)"; fi
fi

# ---- every other single file backup.sh copies with cp (added 2026-09-23) ----
while IFS='|' read -r s d; do
  if grep -qxF -- "$d" "$T/.checked"; then continue; fi
  check "$HOME/$s" "$d" < /dev/null
done < "$T/.cpfiles"

# ---- the rule-driven scopes (added 2026-09-23) ----
# R is backup.sh's own wrapper plus a dry run: `-n -i` lists what would be copied
# and copies nothing. Its destination is STAGE, the drill's own empty temp dir.
R() { _bk_R -n -i "$@"; }
STAGE="$T/inv"; mkdir -p "$STAGE"
: > "$T/.empty"
TOT_PII=0; TOT_EMB=0; TOT_OVER=0; TOT_CMP=0

cap() {  # print at most 15 detail lines per scope, then a count of the rest
  awk 'NR <= 15 { print } END { if (NR > 15) printf "    ... and %d more like these\n", NR - 15 }'
}
scope_args() {  # scope_args CMD: SRC and DST = its last two arguments, expanded as the shell would
  set -f
  eval "set -- ${1#R }"
  set +f
  SRC=""; DST=""
  for _a in "$@"; do SRC="$DST"; DST="$_a"; done
  return 0
}
inventory() {  # inventory CMD OUT: the files that rsync call would copy right now
  scope_args "$1"
  case "$DST" in "$STAGE"/*) ;; *) echo "destination outside the drill's temp dir: $DST" > "$T/.inv.err"; return 1 ;; esac
  rm -rf "$DST"; mkdir -p "$DST"
  set -f
  if eval "$1" > "$T/.inv.raw" 2> "$T/.inv.err"; then set +f; else set +f; return 1; fi
  awk '/^>f/ { print substr($0, index($0, " ") + 1) }' "$T/.inv.raw" | LC_ALL=C sort > "$2.files"
  awk '/^cL/ { p = substr($0, index($0, " ") + 1); sub(/ -> .*$/, "", p); print p }' "$T/.inv.raw" \
    | LC_ALL=C sort > "$2.links"
  return 0
}

# rules_scope CMD PRIVACY_PATTERN EMBEDDED(yes|no)
# Expected set = what backup.sh's rsync call would copy, minus its holdbacks. Then:
#   in the clone and identical      nothing to say
#   in the clone but different      churn or REAL, by the same clock as classify_out
#   expected but not in the clone   REAL, unless it changed after the backup; and when
#                                   the reason is a project's own .gitignore applying
#                                   inside the mirror, grouped by rule, because git will
#                                   never commit that file however often backup.sh runs
#   in the clone but not expected   benign: restoring would bring it back
# Plus a privacy check on the cloud copy itself: a file in the clone that carries a
# term this scope's filter holds back means the filter failed at some point.
rules_scope() {
  rs_cmd="$1"; rs_re="$2"; rs_emb="$3"
  scope_args "$rs_cmd"
  rs_live="${SRC%/}"; rs_sub="${DST#"$STAGE"/}"; rs_sub="${rs_sub%/}"
  echo "$rs_sub" >> "$T/.checked"
  if [ ! -d "$rs_live" ]; then echo "skip (no live source): $rs_live"; return 0; fi
  if ! inventory "$rs_cmd" "$T/.in"; then
    echo "drift: $rs_live <-> mirror/$rs_sub"
    echo "    [REAL: the dry run of backup.sh's own rsync call failed: $(head -1 "$T/.inv.err")]"
    echo "R" >> "$T/.tally"; return 0
  fi
  # The same call without its size cap: the files backup.sh's holdback scan sees (it
  # also holds back an oversized page), and the difference is what the cap alone keeps out.
  cp "$T/.in.files" "$T/.nc.files"
  case "$rs_cmd" in *--max-size=*)
    if ! inventory "$(printf '%s' "$rs_cmd" | sed 's/ --max-size=[^ ]*//')" "$T/.nc"; then
      cp "$T/.in.files" "$T/.nc.files"
    fi ;;
  esac
  # holdbacks, recomputed file by file with backup.sh's own patterns
  : > "$T/.held.pii"; : > "$T/.held.emb"
  if [ -n "$rs_re" ]; then
    ( cd "$rs_live" && tr '\n' '\0' < "$T/.nc.files" | xargs -0 grep -liE -- "$rs_re" 2>/dev/null ) \
      | LC_ALL=C sort -u > "$T/.held.pii" || true
  fi
  if [ "$rs_emb" = yes ]; then
    ( cd "$rs_live" && grep -E '\.(html|md)$' "$T/.nc.files" | tr '\n' '\0' \
        | xargs -0 grep -lE -- "$EMB_RE" 2>/dev/null ) | LC_ALL=C sort -u > "$T/.held.emb" || true
  fi
  LC_ALL=C sort -u "$T/.held.pii" "$T/.held.emb" > "$T/.held"
  LC_ALL=C comm -23 "$T/.nc.files" "$T/.in.files" | LC_ALL=C comm -23 - "$T/.held" > "$T/.over"
  LC_ALL=C sort -u "$T/.in.files" "$T/.in.links" | LC_ALL=C comm -23 - "$T/.held" > "$T/.expect"
  if [ -d "$T/mirror/$rs_sub" ]; then
    ( cd "$T/mirror/$rs_sub" && find . \( -type f -o -type l \) | sed 's|^\./||' ) | LC_ALL=C sort > "$T/.clone"
  else
    : > "$T/.clone"
  fi
  LC_ALL=C comm -23 "$T/.expect" "$T/.clone" > "$T/.liveonly"
  LC_ALL=C comm -13 "$T/.expect" "$T/.clone" > "$T/.mirroronly"
  LC_ALL=C comm -12 "$T/.expect" "$T/.clone" > "$T/.both"
  while IFS= read -r f; do
    if [ -L "$rs_live/$f" ] || [ -L "$T/mirror/$rs_sub/$f" ]; then
      if [ "$(readlink "$rs_live/$f" 2>/dev/null || true)" != "$(readlink "$T/mirror/$rs_sub/$f" 2>/dev/null || true)" ]; then
        printf '%s\n' "$f"
      fi
    elif ! cmp -s "$rs_live/$f" "$T/mirror/$rs_sub/$f"; then
      printf '%s\n' "$f"
    fi
  done < "$T/.both" > "$T/.differs"
  # which missing files will never be committed, and the .gitignore rule that stops them
  : > "$T/.ign"
  if [ -s "$T/.liveonly" ]; then
    sed "s|^|$rs_sub/|" "$T/.liveonly" \
      | git -c core.quotePath=false -C "$T/mirror" check-ignore -v --no-index --stdin > "$T/.ign" 2>/dev/null || true
  fi
  awk -F '\t' -v n="$((${#rs_sub} + 2))" '{ print substr($2, n) }' "$T/.ign" | LC_ALL=C sort -u > "$T/.ign.paths"
  LC_ALL=C comm -23 "$T/.liveonly" "$T/.ign.paths" > "$T/.liveonly.plain"
  # privacy check on the cloud copy itself
  : > "$T/.leak"
  if [ -n "$rs_re" ] && [ -s "$T/.clone" ]; then
    ( cd "$T/mirror/$rs_sub" && tr '\n' '\0' < "$T/.clone" | xargs -0 grep -liE -- "$rs_re" 2>/dev/null ) >> "$T/.leak" || true
  fi
  if [ "$rs_emb" = yes ] && [ -s "$T/.clone" ]; then
    ( cd "$T/mirror/$rs_sub" && grep -E '\.(html|md)$' "$T/.clone" | tr '\n' '\0' \
        | xargs -0 grep -lE -- "$EMB_RE" 2>/dev/null ) >> "$T/.leak" || true
  fi
  LC_ALL=C sort -u -o "$T/.leak" "$T/.leak"

  n_exp=$(wc -l < "$T/.expect" | tr -d ' ');     TOT_CMP=$((TOT_CMP + n_exp))
  n_pii=$(wc -l < "$T/.held.pii" | tr -d ' ');   TOT_PII=$((TOT_PII + n_pii))
  n_emb=$(wc -l < "$T/.held.emb" | tr -d ' ');   TOT_EMB=$((TOT_EMB + n_emb))
  n_over=$(wc -l < "$T/.over" | tr -d ' ');      TOT_OVER=$((TOT_OVER + n_over))
  info="$n_exp file(s) compared"
  if [ "$n_pii" -gt 0 ]; then info="$info; $n_pii held back by the privacy filter"; fi
  if [ "$n_emb" -gt 0 ]; then info="$info; $n_emb embedded-media page(s) held back"; fi
  if [ "$n_over" -gt 0 ]; then info="$info; $n_over over the size cap"; fi
  if [ -s "$T/.ign" ] || [ -s "$T/.liveonly.plain" ] || [ -s "$T/.differs" ] \
     || [ -s "$T/.mirroronly" ] || [ -s "$T/.leak" ]; then
    echo "drift: $rs_live <-> mirror/$rs_sub ($info)"
  else
    echo "match: $rs_sub ($info)"
    return 0
  fi

  while IFS= read -r f; do
    printf '    [REAL: this copy ON GITHUB holds a term the privacy or embedded-media filter keeps off it] %s\n' "$rs_sub/$f"
    echo "RP" >> "$T/.tally"
  done < "$T/.leak" | cap
  if [ -s "$T/.ign" ]; then
    awk -F '\t' -v n="$((${#rs_sub} + 2))" '
      { r = $1; i = index(r, ":"); src = substr(r, 1, i - 1); rest = substr(r, i + 1)
        j = index(rest, ":"); pat = substr(rest, j + 1); k = src "\t" pat; c[k]++
        if (!(k in ex)) ex[k] = substr($2, n) }
      END { for (k in c) { split(k, a, "\t")
        printf "    [REAL: never reaches GitHub] %d file(s) the backup copies but git never commits, because %s ignores \"%s\" (e.g. %s)\n", c[k], a[1], a[2], ex[k] } }
    ' "$T/.ign" | LC_ALL=C sort
    sed 's/.*/RI/' "$T/.ign" >> "$T/.tally"
  fi
  { awk -v L="$rs_live" '{ n = split($0, p, "/"); nm = p[n]
        d = (n > 1) ? substr($0, 1, length($0) - length(nm) - 1) : ""
        printf "Only in %s%s: %s\n", L, (d == "" ? "" : "/" d), nm }' "$T/.liveonly.plain"
    awk -v L="$rs_live" -v M="$T/mirror/$rs_sub" '{ printf "Files %s/%s and %s/%s differ\n", L, $0, M, $0 }' "$T/.differs"
  } > "$T/.lines"
  if [ -s "$T/.lines" ]; then classify_out "$rs_live" "$rs_sub" "$(cat "$T/.lines")" | cap; fi
  if [ -s "$T/.mirroronly" ]; then
    { LC_ALL=C comm -12 "$T/.mirroronly" "$T/.held" | sed 's/^/held	/'
      LC_ALL=C comm -23 "$T/.mirroronly" "$T/.held" | LC_ALL=C comm -12 - "$T/.over" | sed 's/^/over	/'
      LC_ALL=C comm -23 "$T/.mirroronly" "$T/.held" | LC_ALL=C comm -23 - "$T/.over" | sed 's/^/rest	/'
    } > "$T/.mo"
    while IFS="$(printf '\t')" read -r why f; do
      case "$why" in
        held) why="held back by a filter now; the next backup removes this older copy" ;;
        over) why="now over the size cap; the mirror keeps its last copy" ;;
        *) if [ -e "$rs_live/$f" ] || [ -L "$rs_live/$f" ]; then why="now outside backup.sh's copy rules"
           else why="deleted locally since the backup"; fi ;;
      esac
      printf '    [benign: %s] %s\n' "$why" "$rs_sub/$f"
      echo "B" >> "$T/.tally"
    done < "$T/.mo" | cap
  fi
  return 0
}

if [ "$HAVE_LAUNCHD" = 1 ]; then rules_scope "$CMD_LAUNCHD" "" no; fi
if [ "$HAVE_LI" = 1 ]; then LI_DENY="$T/.empty"; rules_scope "$CMD_LI" "$PII_RE_LI" no; fi
if [ "$HAVE_PROJ" = 1 ]; then
  PROJ_DENY="$T/.empty"
  for p in $PROJ_ALLOW; do
    PROJ_LOCAL_DIR="$PLD_DEFAULT"; eval "$PLD_CASE"
    rules_scope "$CMD_PROJ" "$PII_RE_PROJ" yes
  done
  # A project folder still in the mirror after leaving the allow-list is refreshed by
  # nothing: backup.sh syncs each listed project on its own and never prunes the rest.
  for d in "$T/mirror/projects"/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    case " $PROJ_ALLOW " in
      *" $n "*) ;;
      *) echo "note: projects/$n is in the mirror but on no allow-list, so nothing refreshes it; restoring brings back its last copy"
         echo "projects/$n" >> "$T/.checked" ;;
    esac
  done
fi
if [ "$HAVE_WS" = 1 ]; then
  WS_DENY="$T/.empty"
  for w in $WS_EXTRA; do
    lw=$(printf '%s' "$w" | tr '[:upper:]' '[:lower:]')
    if [ "$w" = "Audio" ]; then
      dest="$STAGE/workspace/audio-scripts"; rules_scope "$CMD_WS_AUDIO" "$PII_RE_PROJ" yes
    else
      dest="$STAGE/workspace/$lw"; rules_scope "$CMD_WS" "$PII_RE_PROJ" yes
    fi
  done
fi

# ---- coverage: every file in the mirror falls under some check above (2026-09-23) ----
# The mirror's own configuration (.github/, .gitignore, .gitleaks.toml) is no copy of
# anything live. Anything else outside every check is a scope backup.sh copies that
# this drill does not know yet, and a pass would say nothing about it.
( cd "$T/mirror" && find . -path ./.git -prune -o \( -type f -o -type l \) -print | sed 's|^\./||' ) \
  | LC_ALL=C sort > "$T/.all"
awk 'NR == FNR { pre[++n] = $0; next }
     { for (i = 1; i <= n; i++) if ($0 == pre[i] || index($0, pre[i] "/") == 1) next; print }' \
  "$T/.checked" "$T/.all" | grep -vE '^(\.github/|\.gitignore$|\.gitleaks\.toml$)' > "$T/.unchecked" || true
n_unchecked=$(wc -l < "$T/.unchecked" | tr -d ' ')
if [ "$n_unchecked" -gt 0 ]; then
  echo "unchecked: $n_unchecked file(s) in the mirror sit outside every check above, so this run proves nothing about them:"
  awk -F/ '{ k = ($2 == "") ? $1 : $1 "/" $2; c[k]++ } END { for (k in c) printf "    %d  %s\n", c[k], k }' "$T/.unchecked" | LC_ALL=C sort -k2
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
real_ign=$(grep -c '^RI' "$T/.tally" 2>/dev/null) || real_ign=0
real_leak=$(grep -c '^RP' "$T/.tally" 2>/dev/null) || real_leak=0

RC=0
if [ "$drift_real" -gt 0 ]; then
  echo "RESTORE DRILL: REAL DRIFT: $drift_real file(s) would not come back as they are from the $MIRROR_WHEN backup."
  real_other=$((drift_real - real_ign - real_leak))
  if [ "$real_other" -gt 0 ]; then
    echo "  $real_other predate the backup and are missing from it or still differ. Check backup.sh's include list and its rsync excludes."
  fi
  if [ "$real_ign" -gt 0 ]; then
    echo "  $real_ign are copied by the backup but never committed, because a project's own .gitignore applies inside the mirror (grouped by rule above)."
  fi
  if [ "$real_leak" -gt 0 ]; then
    echo "  $real_leak cop(ies) ON GITHUB hold a term the privacy or embedded-media filter should have kept off them. Treat this as a privacy incident first."
  fi
  if [ "$drift_benign" -gt 0 ]; then echo "  ($drift_benign further difference(s) are post-backup churn and are not the problem.)"; fi
  if [ "$n_unchecked" -gt 0 ]; then echo "  ($n_unchecked file(s) in the mirror also sit outside every check.)"; fi
  RC=1
elif [ "$n_unchecked" -gt 0 ]; then
  echo "RESTORE DRILL: INCOMPLETE: every checked file restores, but $n_unchecked file(s) in the mirror sit outside every check. Teach restore_drill.sh the scope they come from."
  RC=2
elif [ "$drift_benign" -gt 0 ]; then
  echo "RESTORE DRILL: PASS. Every live source restores; $drift_benign file(s) differ purely as post-backup churn (edited since $MIRROR_WHEN)."
else
  echo "RESTORE DRILL: PASS. Cloud mirror matches every live source"
fi
if [ "$TOT_CMP" -gt 0 ]; then
  echo "  Rule-checked scopes: $TOT_CMP file(s) compared against backup.sh's own copy rules."
fi
if [ $((TOT_PII + TOT_EMB + TOT_OVER)) -gt 0 ]; then
  echo "  Kept out of the cloud copy on purpose: $TOT_PII file(s) held back by the privacy filter, $TOT_EMB embedded-media page(s), $TOT_OVER file(s) over the size cap. Those come back only from a local backup such as Time Machine, never from this mirror."
fi
exit $RC
