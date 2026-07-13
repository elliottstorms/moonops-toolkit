#!/bin/sh
# sync-skills.sh — copies user-level skills + agents into each project's .claude/
# so project-scoped sessions (sandboxed to the project folder) can find them.
# Canonical source stays ~/.claude/{skills,agents}; these are read-only mirrors.
# Runs standalone, or as the first step of backup.sh.
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# List the project folders that should receive a local skills/agents mirror.
PROJECTS="/Users/you/Claude/Projects/project-a
/Users/you/Claude/Projects/project-b"

echo "$PROJECTS" | while IFS= read -r P; do
  [ -d "$P" ] || continue
  mkdir -p "$P/.claude"
  rsync -a --delete --exclude .DS_Store "$HOME/.claude/skills/" "$P/.claude/skills/"
  rsync -a --delete --exclude .DS_Store "$HOME/.claude/agents/" "$P/.claude/agents/"
  echo "synced skills+agents -> $P/.claude/"
done
