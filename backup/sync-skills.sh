#!/bin/sh
# sync-skills.sh — copies user-level skills + agents into each Cowork project's
# .claude/ so project-scoped sessions (sandboxed to the project folder) can find them.
# Canonical source stays ~/.claude/{skills,agents}; these are read-only mirrors.
# Runs standalone or as the first step of backup.sh (daily 17:30).
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

PROJECTS="/Users/you/Claude/Projects/moonops
/Users/you/Claude/Projects/project-b"

echo "$PROJECTS" | while IFS= read -r P; do
  [ -d "$P" ] || continue
  mkdir -p "$P/.claude"
  rsync -a --delete --exclude .DS_Store "$HOME/.claude/skills/" "$P/.claude/skills/"
  rsync -a --delete --exclude .DS_Store "$HOME/.claude/agents/" "$P/.claude/agents/"
  echo "synced skills+agents -> $P/.claude/"
done

# Toolkit persona copies are GENERATED MIRRORS of the canonical ~/.claude skills
# (canon decision 2026-07-10 — the pair had silently forked). Never hand-edit
# Toolkit/selene or Toolkit/council; edit ~/.claude/skills/* and rerun this.
for s in selene council; do
  [ -d "$HOME/.claude/skills/$s" ] || continue
  mkdir -p "$HOME/Claude/Toolkit/$s"
  rsync -a --delete --exclude .DS_Store "$HOME/.claude/skills/$s/" "$HOME/Claude/Toolkit/$s/"
done
echo "mirrored selene+council -> Toolkit/ (one-way, canon: ~/.claude/skills)"
