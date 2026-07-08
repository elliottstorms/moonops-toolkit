#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  audiocast · render_audio.sh
#  Any clean .txt script → a shareable audio file, fully offline on macOS.
#  Engine order:
#    1) macOS `say`  (offline, built-in — default on your Mac)
#    2) edge-tts     (neural, needs network to Microsoft)
#    3) piper        (offline neural, needs a local voice .onnx)
#  Default output: mp3, loudness-normalized, with an ID3 title, in ~/Claude/Audio.
#
#  Usage:
#    render_audio.sh -i script.txt [-o out] [-v Voice] [-f mp3|m4a]
#                    [-r rate] [-t "Title"] [--raw]
# ─────────────────────────────────────────────────────────────
set -euo pipefail

INPUT=""; OUT=""; VOICE="${AUDIOCAST_VOICE:-}"; FMT="mp3"; RATE=""; TITLE=""; NORMALIZE=1
OUTDIR="${AUDIOCAST_OUTDIR:-$HOME/Claude/Audio}"

while [ $# -gt 0 ]; do
  case "$1" in
    -i) INPUT="${2:-}"; shift 2;;
    -o) OUT="${2:-}"; shift 2;;
    -v) VOICE="${2:-}"; shift 2;;
    -f) FMT="${2:-}"; shift 2;;
    -r) RATE="${2:-}"; shift 2;;
    -t) TITLE="${2:-}"; shift 2;;
    --raw) NORMALIZE=0; shift;;
    -h|--help) echo "usage: $0 -i script.txt [-o out] [-v Voice] [-f mp3|m4a] [-r rate] [-t Title] [--raw]"; exit 0;;
    *) if [ -z "$INPUT" ]; then INPUT="$1"; shift; else echo "unknown arg: $1" >&2; exit 2; fi;;
  esac
done

[ -z "$INPUT" ] && { echo "error: -i script.txt required" >&2; exit 2; }
[ -f "$INPUT" ] || { echo "error: input not found: $INPUT" >&2; exit 2; }
case "$FMT" in mp3|m4a) ;; *) echo "error: -f must be mp3 or m4a" >&2; exit 2;; esac

mkdir -p "$OUTDIR"

# Derive title + output path when not given
base_in="$(basename "$INPUT")"; base_in="${base_in%.*}"
[ -z "$TITLE" ] && TITLE="$base_in"
if [ -z "$OUT" ]; then
  slug="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
  [ -z "$slug" ] && slug="audiocast"
  OUT="$OUTDIR/${slug}_$(date +%Y-%m-%d).$FMT"
fi
OUTBASE="${OUT%.*}"

report() {
  local f="$1" dur size mmss=""
  size="$(ls -lh "$f" 2>/dev/null | awk '{print $5}')"
  if command -v ffprobe >/dev/null 2>&1; then
    dur="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$f" 2>/dev/null || echo "")"
    [ -n "${dur:-}" ] && mmss="$(awk -v s="$dur" 'BEGIN{printf "%d:%02d", int(s/60), int(s%60)}')"
  fi
  echo ""
  echo "✅ audio ready"
  echo "   file:     $f"
  echo "   length:   ${mmss:-?}"
  echo "   size:     ${size:-?}"
  echo "   voice:    ${VOICE:-auto}   format: $FMT"
  echo "AUDIOCAST_OK|file=$f|length=${mmss:-?}|size=${size:-?}|voice=${VOICE:-auto}|format=$FMT"
}

pick_voice() {
  [ -n "$VOICE" ] && { echo "$VOICE"; return; }
  local list; list="$(say -v '?' 2>/dev/null || true)"
  # Prefer premium/enhanced neural voices if the user has installed any; else a solid built-in.
  local prefs=("Ava (Premium)" "Zoe (Premium)" "Allison (Enhanced)" "Evan (Enhanced)" \
               "Samantha (Enhanced)" "Tom (Enhanced)" "Samantha" "Alex" "Daniel" "Karen" "Moira")
  local v
  for v in "${prefs[@]}"; do
    printf '%s\n' "$list" | grep -qF "$v" && { echo "$v"; return; }
  done
  echo "Samantha"
}

# ── 1) macOS say (preferred: offline, built-in) ──────────────
if command -v say >/dev/null 2>&1; then
  VOICE="$(pick_voice)"
  echo "[say] rendering with voice: $VOICE"
  if [ -n "$RATE" ]; then
    say -r "$RATE" -v "$VOICE" -f "$INPUT" -o "$OUTBASE.aiff"
  else
    say -v "$VOICE" -f "$INPUT" -o "$OUTBASE.aiff"
  fi

  # Convert AIFF -> target format. ffmpeg is primary (present + reliable: loudnorm,
  # ID3/metadata, and any codec). lame/afconvert are fallbacks only if ffmpeg is missing.
  codec="libmp3lame"; [ "$FMT" = "m4a" ] && codec="aac"
  if command -v ffmpeg >/dev/null 2>&1; then
    if [ "$NORMALIZE" -eq 1 ]; then
      ffmpeg -y -loglevel error -i "$OUTBASE.aiff" -af "loudnorm=I=-16:TP=-1.5:LRA=11" \
        -codec:a "$codec" -b:a 128k -metadata title="$TITLE" "$OUT"
    else
      ffmpeg -y -loglevel error -i "$OUTBASE.aiff" \
        -codec:a "$codec" -b:a 128k -metadata title="$TITLE" "$OUT"
    fi
    rm -f "$OUTBASE.aiff"
  elif [ "$FMT" = "mp3" ] && command -v lame >/dev/null 2>&1 && command -v afconvert >/dev/null 2>&1; then
    afconvert "$OUTBASE.aiff" "$OUTBASE.wav" -f WAVE -d LEI16 && rm -f "$OUTBASE.aiff"
    lame -h -b 128 --quiet "$OUTBASE.wav" "$OUT" && rm -f "$OUTBASE.wav"
  elif [ "$FMT" = "m4a" ] && command -v afconvert >/dev/null 2>&1; then
    # afconvert AAC fallback: omit explicit -b (pinning it triggers a '!dat' error on some inputs)
    afconvert -f m4af -d aac "$OUTBASE.aiff" "$OUT" && rm -f "$OUTBASE.aiff"
  else
    OUT="$OUTBASE.aiff"
    echo "[warn] no encoder for $FMT found — left AIFF (install ffmpeg)." >&2
  fi
  report "$OUT"; exit 0
fi

# ── 2) edge-tts (neural, network-dependent) ──────────────────
if python3 -c "import edge_tts" >/dev/null 2>&1; then
  EVOICE="${EDGE_VOICE:-en-US-AriaNeural}"
  echo "[edge-tts] trying neural voice: $EVOICE"
  if python3 -m edge_tts --voice "$EVOICE" -f "$INPUT" --write-media "$OUTBASE.mp3" 2>/dev/null && [ -s "$OUTBASE.mp3" ]; then
    OUT="$OUTBASE.mp3"; VOICE="$EVOICE"; FMT="mp3"; report "$OUT"; exit 0
  fi
  echo "[edge-tts] no network route to provider — skipping." >&2
fi

# ── 3) piper (offline neural, needs a local model) ───────────
if command -v piper >/dev/null 2>&1 && [ -n "${PIPER_VOICE:-}" ] && [ -f "${PIPER_VOICE}" ]; then
  echo "[piper] rendering with model: $PIPER_VOICE"
  piper -m "$PIPER_VOICE" -f "$OUTBASE.wav" < "$INPUT"
  OUT="$OUTBASE.wav"; VOICE="$(basename "$PIPER_VOICE")"; FMT="wav"; report "$OUT"; exit 0
fi

echo "No TTS engine available here." >&2
echo "→ Hand off $INPUT to NotebookLM / ElevenLabs / phone read-aloud, or run on a Mac (macOS 'say')." >&2
exit 1
