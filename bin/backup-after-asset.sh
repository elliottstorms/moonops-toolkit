#!/bin/bash
# backup-after-asset.sh — PostToolUse(Edit|Write) hook. When a DURABLE asset changes
# (a skill, agent, hook script, CLAUDE.md, settings, a Toolkit file, or a scheduled task),
# record the path and print a one-line nudge — so "back up after building any durable
# asset" is not a thing you have to remember.
#
# Non-blocking by design: it only RECORDS and REMINDS (exit 0). It never runs git or pushes
# on its own — the daily 17:30 launchd backup does the actual mirror, and `/backup` runs it
# on demand. The recorded list lives at ~/.claude/.backup-needed and is informational.

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
[ -n "$f" ] || exit 0

case "$f" in
  "$HOME/.claude/skills/"*|"$HOME/.claude/agents/"*|"$HOME/.claude/bin/"*| \
  "$HOME/.claude/CLAUDE.md"|"$HOME/.claude/settings.json"| \
  "$HOME/Claude/Toolkit/"*|"$HOME/Claude/Scheduled/"*|"$HOME/Claude/Handoffs/"*) ;;
  *) exit 0 ;;                        # not a durable asset — ignore
esac

flag="$HOME/.claude/.backup-needed"
grep -qxF "$f" "$flag" 2>/dev/null || echo "$f" >> "$flag"
echo "ℹ️  durable asset changed ($(basename "$f")) — recorded; run /backup when ready (auto-backup runs daily 17:30)." >&2
exit 0
