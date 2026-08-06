#!/bin/sh
# sync-skills.sh: copies user-level skills + agents into each project's .claude/
# so project-scoped sessions (sandboxed to the project folder) can find them.
# Canonical source stays ~/.claude/{skills,agents}; these are read-only mirrors.
# Runs standalone, or as the first step of backup.sh.
#
# CHECK THAT YOU ACTUALLY NEED THIS BEFORE YOU SCHEDULE IT. It helps only if you run
# sessions sandboxed to a project folder. Claude Code in a terminal already reads
# ~/.claude/skills globally, whatever directory it started in, so on that surface the
# mirror buys nothing and costs something real: every mirrored skill gets listed a
# second time as a directory-scoped copy, against a skill-listing context budget that
# is capped. Overflow it and the least-used skills quietly lose their descriptions and
# stop triggering. If you are not running sandboxed project sessions, delete the loop
# below rather than leaving it to run nightly.
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
