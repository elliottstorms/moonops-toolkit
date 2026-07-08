#!/bin/bash
# site-link-check.sh — PostToolUse hook wrapper.
# Reads the Edit/Write hook JSON on stdin. If the edited file is an .html page
# under the moonops site dir, runs the offline site audit (link integrity,
# canonical LinkedIn URL, nav parity, OG tags, forbidden strings). On audit
# FAIL it prints the failing lines to stderr and exits 2 so Claude sees them
# and can fix before the bad edit ships. Otherwise exits 0 silently.
#
# Safe by design: any wiring problem (no jq, script missing, non-site file)
# exits 0 so a normal edit is never blocked by the hook itself.

SITE_DIR="$HOME/Claude/Projects/moonops/site"
REPO="$HOME/Claude/Projects/moonops"
AUDIT="$HOME/.claude/skills/site-check/site_audit.py"

# Pull the edited file path out of the hook payload (Edit and Write both use
# tool_input.file_path; PostToolUse also carries tool_response.filePath).
f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)

case "$f" in
  "$SITE_DIR"/*.html) ;;                # a site page — check it
  *) exit 0 ;;                          # anything else — not our concern
esac

[ -f "$AUDIT" ] || exit 0               # audit engine gone: don't block edits

out=$(python3 "$AUDIT" --repo "$REPO" --offline 2>&1)
if [ $? -eq 2 ]; then                   # 2 = FAIL (0 = pass/warn, 3 = usage err)
  {
    echo "site-check FAILED after editing $(basename "$f") — fix before shipping:"
    echo "$out" | grep -E "FAIL|❌|forbidden|missing|nav|linkedin" || echo "$out"
  } >&2
  exit 2
fi
exit 0
