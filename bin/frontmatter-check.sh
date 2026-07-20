#!/bin/bash
# frontmatter-check.sh - PostToolUse(Edit|Write) hook. Validates YAML frontmatter
# whenever a skill, agent, or scheduled-task definition is written. Invalid YAML
# in these files fails silently at load time (a scheduled alert can simply never
# fire: this class of bug hit three scheduled tasks on 2026-07-10), so catch it
# at write time: exit 2 with the parse error so Claude fixes it immediately.
#
# Safe by design: any wiring problem (no jq, no ruby, file gone, no frontmatter
# fence) exits 0, so a normal edit is never blocked by the hook itself.

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
[ -n "$f" ] || exit 0
[ -f "$f" ] || exit 0

case "$f" in
  */skills/*/SKILL.md|*/scheduled-tasks/*/SKILL.md|*/.claude/agents/*.md) ;;
  *) exit 0 ;;
esac

command -v ruby >/dev/null 2>&1 || exit 0
head -1 "$f" | grep -q '^---$' || exit 0   # no frontmatter fence: not ours to judge

err=$(awk '/^---$/{n++; next} n==1' "$f" | ruby -E UTF-8 -ryaml -e 'YAML.safe_load(STDIN.read)' 2>&1)
if [ $? -ne 0 ]; then
  {
    echo "frontmatter-check: invalid YAML frontmatter in $(basename "$f"), fix before this definition silently fails to load:"
    echo "$err" | head -3
    echo "hint: values containing a colon+space must be quoted (description: \"Daily alert: check the queue\")"
  } >&2
  exit 2
fi
exit 0
