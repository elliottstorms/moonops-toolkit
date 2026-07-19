#!/bin/sh
# backup.sh: mirror your durable Claude Code assets into a PRIVATE GitHub repo.
# Idempotent: commits and pushes only when something actually changed.
#
# Included:  ~/.claude/CLAUDE.md, ~/.claude/settings.json, ~/.claude/skills/,
#            ~/.claude/agents/, ~/.claude/bin/, and whatever else you add below.
# EXCLUDED, permanently:  anything with PII (job-search, finance, personal notes)
#            and anything matching the secrets tripwire below.
#
# Setup:     set REPO to your own PRIVATE repo (create it private; this is a backup,
#            not a publication). Requires the `gh` CLI, authenticated (`gh auth login`).
# Run:       sh backup.sh
# Schedule:  add a launchd job (macOS) or cron entry to run it daily.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# --- configure these two lines ---
REPO="your-username/your-private-backup-repo"     # PRIVATE repo
STAGE="$HOME/.claude-backup/stage"                # local staging mirror
# ---------------------------------

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
