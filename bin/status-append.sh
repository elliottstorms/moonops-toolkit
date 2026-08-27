#!/bin/sh
# status-append.sh — append one event to ~/Claude/STATUS.md (the Code → Cowork reverse loop).
# The daily Cowork sync reads new lines and auto-closes matching TASKS.md items / raises alerts.
#
# Usage: status-append.sh <surface> <type> <summary> [url_or_commit] [verified]
#   surface: code | cowork
#   type:    video-upload | site-ship | gumroad-sale | backup | job-failure | note
#   verified: yes | no   (default no)
#
# Example: status-append.sh code site-ship "praise nav fix live" "c590db7" yes
#          status-append.sh code video-upload "Campfire rain 8h" "https://youtu.be/XXXX" yes
# Arity guard: STATUS.md is only ever appended via this helper (you Tier 1), so a
# malformed call must fail loudly here instead of writing a garbage row the daily Cowork
# sync cannot match. Require surface, type, summary; url and verified are optional.
if [ "$#" -lt 3 ] || [ "$#" -gt 5 ]; then
  printf 'status-append.sh: refusing to write. Got %s arg(s); need 3 to 5.\n  usage: status-append.sh <surface> <type> <summary> [url_or_commit] [verified]\n' "$#" >&2
  exit 2
fi
STATUS="$HOME/Claude/STATUS.md"
ts=$(date '+%Y-%m-%d %H:%M')
printf '%s | %s | %s | %s | %s | %s\n' \
  "$ts" "${1:-code}" "${2:-note}" "${3:-}" "${4:-}" "${5:-no}" >> "$STATUS"
