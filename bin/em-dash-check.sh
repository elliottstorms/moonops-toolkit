#!/bin/bash
# em-dash-check.sh: PostToolUse(Edit|Write) hook. Public copy under your name uses NO
# em or en dashes, typed (U+2014, U+2013) or as HTML entities (&mdash; &ndash; &#8212; &#8211;),
# since an entity renders as the same dash on the page. If an edited PUBLIC-COPY file contains
# one, print the offending lines to stderr and exit 2 so Claude fixes it before it ships.
# Every other file exits 0 silently.
#
# Safe by design: any wiring problem (no jq, file gone) exits 0, so a normal edit is never
# blocked by the hook itself. Scoped narrowly to genuinely public surfaces; internal docs,
# notes, skills, and code may use dashes freely (her ruling 2026-09-23: public copy only).
# Widened 2026-09-23 to en dashes, entities, and the Belief and Company site pages; the
# pre-change script is at ~/Claude/Archive/bin/em-dash-check-2026-09-23-pre-en-dash-and-entities.sh.

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
[ -n "$f" ] || exit 0
[ -f "$f" ] || exit 0

case "$f" in
  */moonops/site/*.html)                         ;;   # live moonops.org pages
  */linkedin/POST-*.md)                          ;;   # LinkedIn posts (public)
  */moonops-rain/metadata/*)                     ;;   # video titles / descriptions
  */moonops-rain/briefings/*)                    ;;   # public-facing briefs
  */holiday-hotline/web/src/app/*.tsx)           ;;   # beliefandcompany.com pages
  */holiday-hotline/web/src/lib/landing-html.ts) ;;   # beliefandcompany.com landing page
  *) exit 0 ;;                                         # everything else: dashes are fine
esac

hits=$(grep -nE '—|–|&mdash;|&ndash;|&#8212;|&#8211;' "$f" 2>/dev/null)
if [ -n "$hits" ]; then
  {
    echo "em-dash-check: public copy uses no em or en dashes (typed or as HTML entities). Rewrite with a comma, colon, parentheses, or a new sentence. In $(basename "$f"):"
    echo "$hits" | head -20
  } >&2
  exit 2
fi
exit 0
