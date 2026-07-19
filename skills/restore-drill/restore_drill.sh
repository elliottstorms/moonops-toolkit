#!/bin/sh
# restore_drill.sh — clone the cloud mirror and prove it matches live sources.
# Read-only with respect to everything except its own temp dir.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REPO="your-username/your-backup-repo"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

echo "cloning $REPO (fresh from GitHub, not the local stage)..."
gh repo clone "$REPO" "$T/mirror" -- -q --depth 1

drift=0

# git cannot represent empty directories, so a live empty dir is never in the
# mirror clone — "Only in" lines pointing at empty dirs are not restorable
# content and get dropped here.
filter_empty_dirs() {
  while IFS= read -r line; do
    case "$line" in
      "Only in "*)
        d="${line#Only in }"
        dir="${d%%:*}"; name="${d#*: }"
        if [ -d "$dir/$name" ] && [ -z "$(ls -A "$dir/$name" 2>/dev/null)" ]; then
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
  if [ -d "$live" ]; then
    out=$(diff -rq "$@" "$live" "$T/mirror/$sub" 2>&1 \
          | grep -v -E '\.DS_Store|__pycache__|\.pyc|\.log|\.tmp|\.backup-needed' \
          | filter_empty_dirs || true)
  else
    out=$(diff -q "$live" "$T/mirror/$sub" 2>&1 || true)
  fi
  if [ -n "$out" ]; then
    echo "drift: $live <-> mirror/$sub"
    echo "$out" | sed 's/^/    /' | head -10
    drift=1
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
# active memory: private-contact.md is EXCLUDED by design — diff around it
if [ -d "$HOME/.claude/projects/-Users-you-Claude/memory" ]; then
  out=$(diff -rq "$HOME/.claude/projects/-Users-you-Claude/memory" "$T/mirror/memory-active" 2>&1 \
        | grep -v 'private-contact.md' || true)
  if [ -n "$out" ]; then echo "drift: active memory"; echo "$out" | sed 's/^/    /'; drift=1
  else echo "match: memory-active (PII exclusion intact)"; fi
fi

echo "last mirror commit: $(git -C "$T/mirror" log -1 --format='%h %ad %s' --date=format:'%Y-%m-%d %H:%M')"
if [ "$drift" -eq 0 ]; then
  echo "RESTORE DRILL: PASS — cloud mirror matches every live source"
else
  echo "RESTORE DRILL: DRIFT FOUND — see lines above (normal for post-backup edits; verify timestamps)"
  exit 1
fi
