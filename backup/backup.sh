#!/bin/sh
# backup.sh: mirror your durable Claude Code assets into a PRIVATE GitHub repo.
# Idempotent: commits and pushes only when something actually changed.
#
# Included:  ~/.claude/CLAUDE.md, ~/.claude/settings.json, ~/.claude/skills/,
#            ~/.claude/agents/, ~/.claude/bin/, and whatever else you add below.
# EXCLUDED, permanently:  anything with PII (job-search, finance, personal notes)
#            and anything matching the secrets tripwire below.
#
# KEEP THIS LIST HONEST WHEN FILES SPLIT. The include list names files, so the day you
# split a growing file into an archive or a log, the moved content leaves the mirror
# silently and the backup keeps reporting success over a smaller and smaller surface.
# Whenever a cleanup moves content out of a mirrored file, its destination joins this
# list in the same change, or the cleanup is a data-loss bug wearing a tidiness costume.
#
# Setup:     set REPO to your own PRIVATE repo (create it private; this is a backup,
#            not a publication). Requires the `gh` CLI, authenticated (`gh auth login`).
# Run:       sh backup.sh
# Schedule:  add a launchd job (macOS) or cron entry to run it daily.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# --- configure these ---
REPO="your-username/your-private-backup-repo"     # PRIVATE repo
STAGE="$HOME/.claude-backup/stage"                # local staging mirror
# Name of a history-aware secret-scanning workflow in that repo (the `name:` field
# of the workflow YAML). This kit ships one at .github/workflows/gitleaks.yml, so
# copy that into your backup repo and set this to "gitleaks" to turn the post-push
# verification on. Leave it empty to skip that check entirely.
SCAN_WORKFLOW=""
# -----------------------

LOG="$HOME/.claude-backup/backup.log"
mkdir -p "$STAGE" "$(dirname "$LOG")"
say() { echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" | tee -a "$LOG"; }

# ---- one-time init ----
if [ ! -d "$STAGE/.git" ]; then
  git -C "$STAGE" init -q -b main
  say "initialized staging repo at $STAGE"
fi
if ! git -C "$STAGE" remote get-url origin >/dev/null 2>&1; then
  if ! gh repo view "$REPO" >/dev/null 2>&1; then
    gh repo create "$REPO" --private -d "Claude Code assets backup" >/dev/null
    say "created PRIVATE GitHub repo $REPO"
  fi
  git -C "$STAGE" remote add origin "https://github.com/$REPO.git"
fi

# ---- mirror sources (rsync --delete keeps the mirror exact) ----
R="rsync -a --delete --exclude .DS_Store"
mkdir -p "$STAGE/claude-config"
$R "$HOME/.claude/skills/" "$STAGE/claude-config/skills/"
$R "$HOME/.claude/agents/" "$STAGE/claude-config/agents/"
$R "$HOME/.claude/bin/"    "$STAGE/claude-config/bin/"
cp "$HOME/.claude/CLAUDE.md"      "$STAGE/claude-config/CLAUDE.md"      2>/dev/null || true
cp "$HOME/.claude/settings.json" "$STAGE/claude-config/settings.json" 2>/dev/null || true

# ---- secrets tripwire: refuse to commit anything credential-shaped ----
BAD=$(cd "$STAGE" && find . -type f \( -name "client_secret*" -o -name "*token*.json" -o \
      -name "*.key" -o -name "*.pem" -o -name ".env" -o -name "credentials*.json" \) | head -5)
if [ -n "$BAD" ]; then
  say "ABORT: credential-shaped file(s) in staging, NOT committing: $BAD"
  exit 2
fi
if grep -rlE "gh[pousr]_[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9-]{20,}|AIza[0-9A-Za-z_-]{30,}|AKIA[0-9A-Z]{16}" \
     "$STAGE" --exclude-dir=.git >/dev/null 2>&1; then
  say "ABORT: token-like string found in staged content, NOT committing"
  exit 2
fi

# ---- commit + push only on change ----
cd "$STAGE"
git add -A
if git diff --cached --quiet; then
  say "no changes, nothing to back up"
  exit 0
fi
CHANGED=$(git diff --cached --stat | tail -1)
git commit -q -m "backup: $(date '+%Y-%m-%d %H:%M'), $CHANGED"
git push -q -u origin main
say "backed up + pushed: $CHANGED"

# ---- confirm the history-aware secret scan actually ran and passed ----
# The tripwire above inspects only THIS commit's staged content. A workflow in the
# repo is what scans the FULL history, and it is easy to never notice when that
# workflow stops firing: a provider incident, a renamed action, a revoked token,
# and the only history-aware scan you have is silently off while the backup keeps
# reporting success. A secret scanner that fails quietly is worse than none,
# because it is trusted. NON-FATAL by design: the mirror is already pushed and
# safe on disk, so this only ever reports. It never fails the backup.
if [ -n "$SCAN_WORKFLOW" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    say "warn: scan result unverified (gh CLI not on PATH)"
  elif ! gh auth status >/dev/null 2>&1; then
    say "warn: scan result unverified (gh not authenticated)"
  else
    PUSHED_SHA=$(git rev-parse HEAD)
    SHORT=$(echo "$PUSHED_SHA" | cut -c1-7)
    SCAN=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 12
      SCAN=$(gh run list --repo "$REPO" --limit 20 \
               --json headSha,status,conclusion,workflowName \
               --jq ".[] | select(.headSha==\"$PUSHED_SHA\" and .workflowName==\"$SCAN_WORKFLOW\") | \"\(.status)/\(.conclusion)\"" \
             2>/dev/null | head -1)
      case "$SCAN" in
        completed/*) break ;;
      esac
    done
    case "$SCAN" in
      completed/success)
        say "secret scan: PASS on $SHORT (full history clean)" ;;
      completed/*)
        say "ALERT: secret scan did NOT pass on $SHORT ($SCAN). History-aware scanning is DOWN. Check: gh run list --repo $REPO" ;;
      "")
        say "ALERT: NO scan run exists for $SHORT. The push landed but the workflow never fired, so nothing scanned this history. Re-run: gh workflow run \"$SCAN_WORKFLOW\" --repo $REPO --ref main" ;;
      *)
        say "warn: secret scan still $SCAN on $SHORT after ~2min, not waiting longer" ;;
    esac
  fi
fi
