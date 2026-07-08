#!/bin/bash
# em-dash-check.sh — PostToolUse(Edit|Write) hook. MoonOps public copy uses NO em dashes
# (brand rule: "no em dashes in public copy"). If an edited PUBLIC-COPY file contains an
# em dash (—, U+2014), print the offending lines to stderr and exit 2 so Claude fixes it
# before it ships. Every other file exits 0 silently.
#
# Safe by design: any wiring problem (no jq, file gone) exits 0 — a normal edit is never
# blocked by the hook itself. Scoped narrowly to genuinely public surfaces; internal docs,
# notes, and code may use em dashes freely.

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
[ -n "$f" ] || exit 0
[ -f "$f" ] || exit 0

case "$f" in
  */moonops/site/*.html)        ;;   # live moonops.org pages
  */linkedin/POST-*.md)         ;;   # LinkedIn posts (public)
  */moonops-rain/metadata/*)    ;;   # video titles / descriptions
  */moonops-rain/briefings/*)   ;;   # public-facing briefs
  *) exit 0 ;;                        # everything else: em dashes are fine
esac

hits=$(grep -nF "—" "$f" 2>/dev/null)
if [ -n "$hits" ]; then
  {
    echo "em-dash-check: MoonOps public copy uses no em dashes — replace with a hyphen, comma, or rewrite. In $(basename "$f"):"
    echo "$hits" | head -20
  } >&2
  exit 2
fi
exit 0
