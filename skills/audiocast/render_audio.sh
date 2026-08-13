#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  audiocast · render_audio.sh
#  Any clean .txt script → a shareable audio file.
#
#  Engine order (first one that works wins):
#    1) edge-tts  en-US-AvaNeural   neural, needs network; long scripts are
#                                   chunked and concatenated
#    2) macOS `say` with an installed Premium/Enhanced voice   (offline)
#    3) macOS `say` Samantha        (offline, explicit last resort)
#    4) piper                       (offline neural, needs a local .onnx)
#
#  Default output: mp3, loudness-normalized, with an ID3 title, in ~/Claude/Audio.
#
#  Usage:
#    render_audio.sh -i script.txt [-o out] [-v Voice] [-f mp3|m4a]
#                    [-r rate] [-t "Title"] [--raw] [--offline]
#
#  -v routing: a locale-style neural id (en-US-AvaNeural, en-GB-SoniaNeural)
#  forces edge-tts with that voice. Any other name (Daniel, Karen, "Ava
#  (Premium)") forces the local `say` engine with that voice.
#
#  PRIVACY: engine 1 posts the script text to Microsoft's TTS endpoint. For a
#  sensitive script, pass --offline (or -v "<local voice>") to keep every word
#  on this machine. Engines 2-4 never touch the network.
#
#  Env: AUDIOCAST_VOICE, AUDIOCAST_OUTDIR, EDGE_VOICE, AUDIOCAST_CHUNK_CHARS,
#       PIPER_VOICE
# ─────────────────────────────────────────────────────────────
set -euo pipefail

INPUT=""; OUT=""; VOICE="${AUDIOCAST_VOICE:-}"; FMT="mp3"; RATE=""; TITLE=""; NORMALIZE=1
OUTDIR="${AUDIOCAST_OUTDIR:-$HOME/Claude/Audio}"
EDGE_VOICE="${EDGE_VOICE:-en-US-AvaNeural}"
MAX_CHUNK="${AUDIOCAST_CHUNK_CHARS:-1400}"
GAP_SECONDS="0.35"
ENGINE=""
OFFLINE=0

while [ $# -gt 0 ]; do
  case "$1" in
    -i) INPUT="${2:-}"; shift 2;;
    -o) OUT="${2:-}"; shift 2;;
    -v) VOICE="${2:-}"; shift 2;;
    -f) FMT="${2:-}"; shift 2;;
    -r) RATE="${2:-}"; shift 2;;
    -t) TITLE="${2:-}"; shift 2;;
    --raw) NORMALIZE=0; shift;;
    --offline) OFFLINE=1; shift;;
    -h|--help) echo "usage: $0 -i script.txt [-o out] [-v Voice] [-f mp3|m4a] [-r rate] [-t Title] [--raw] [--offline]"; exit 0;;
    *) if [ -z "$INPUT" ]; then INPUT="$1"; shift; else echo "unknown arg: $1" >&2; exit 2; fi;;
  esac
done

[ -z "$INPUT" ] && { echo "error: -i script.txt required" >&2; exit 2; }
[ -f "$INPUT" ] || { echo "error: input not found: $INPUT" >&2; exit 2; }
[ -s "$INPUT" ] || { echo "error: input is empty: $INPUT" >&2; exit 2; }
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

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/audiocast.XXXXXX")"
cleanup() { if [ -n "${WORKDIR:-}" ] && [ -d "$WORKDIR" ]; then rm -rf "$WORKDIR"; fi; }
trap cleanup EXIT

report() {
  local f="$1" dur size mmss=""
  size="$(ls -lh "$f" 2>/dev/null | awk '{print $5}')"
  if command -v ffprobe >/dev/null 2>&1; then
    dur="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$f" 2>/dev/null || echo "")"
    case "${dur:-}" in ''|*[!0-9.]*) dur="";; esac
    [ -n "${dur:-}" ] && mmss="$(awk -v s="$dur" 'BEGIN{printf "%d:%02d", int(s/60), int(s%60)}')"
  fi
  echo ""
  echo "✅ audio ready"
  echo "   file:     $f"
  echo "   length:   ${mmss:-?}"
  echo "   size:     ${size:-?}"
  echo "   voice:    ${VOICE:-auto}   format: $FMT   engine: ${ENGINE:-?}"
  echo "AUDIOCAST_OK|file=$f|length=${mmss:-?}|size=${size:-?}|voice=${VOICE:-auto}|format=$FMT|engine=${ENGINE:-?}"
}

# ── voice routing ────────────────────────────────────────────
# A locale-style neural id (xx-XX-NameNeural) means edge-tts; anything else
# is a local `say` voice name.
is_edge_voice() {
  case "$1" in
    [a-z][a-z]-[A-Z][A-Z]*Neural|[a-z][a-z][a-z]-[A-Z][A-Z]*Neural) return 0;;
    *) return 1;;
  esac
}

WANT_ENGINE="auto"
if [ -n "$VOICE" ]; then
  if is_edge_voice "$VOICE"; then
    WANT_ENGINE="edge"; EDGE_VOICE="$VOICE"
  else
    WANT_ENGINE="say"
  fi
fi
if [ "$OFFLINE" -eq 1 ]; then
  if [ "$WANT_ENGINE" = "edge" ]; then
    echo "error: --offline and the neural voice '$VOICE' contradict each other." >&2
    echo "       Drop one: --offline keeps the text on this machine, the neural voice does not." >&2
    exit 2
  fi
  [ "$WANT_ENGINE" = "auto" ] && WANT_ENGINE="offline"
fi

# `say` takes words-per-minute; edge-tts takes a percentage delta. Translate
# a bare wpm number against the ~175 wpm baseline `say` reads at.
EDGE_RATE=""
if [ -n "$RATE" ]; then
  case "$RATE" in
    [+-][0-9]*%) EDGE_RATE="$RATE";;
    [0-9]*)      EDGE_RATE="$(awk -v r="$RATE" 'BEGIN{p=int((r-175)*100/175+(r>=175?0.5:-0.5)); printf "%s%d%%", (p<0?"":"+"), p}')";;
    *)           echo "[warn] unrecognized -r '$RATE', ignoring it for edge-tts." >&2;;
  esac
fi

# ── shared finalize: concat list → normalized, tagged output ─
# $1 = ffmpeg concat list file, $2 = 1 if sources are already mp3 (stream-copyable)
finalize() {
  local list="$1" copyable="$2" codec="libmp3lame"
  [ "$FMT" = "m4a" ] && codec="aac"
  local args
  args=(-y -loglevel error -f concat -safe 0 -i "$list")
  if [ "$NORMALIZE" -eq 1 ]; then
    args+=(-af "loudnorm=I=-16:TP=-1.5:LRA=11" -codec:a "$codec" -b:a 128k)
  elif [ "$copyable" -eq 1 ] && [ "$FMT" = "mp3" ]; then
    args+=(-c:a copy)
  else
    args+=(-codec:a "$codec" -b:a 128k)
  fi
  args+=(-metadata title="$TITLE" "$OUT")
  ffmpeg "${args[@]}"
}

# ── 1) edge-tts (neural, preferred: this is the Ava path) ────
edge_chunk_script() {
  cat <<'PY'
import os, re, sys
src, outdir, maxlen = sys.argv[1], sys.argv[2], int(sys.argv[3])
text = open(src, encoding="utf-8", errors="replace").read()
text = text.replace("\r\n", "\n").replace("\r", "\n")

paras = [re.sub(r"\s*\n\s*", " ", p).strip()
         for p in re.split(r"\n\s*\n+", text) if p.strip()]

def split_long(s):
    """Break an oversized paragraph on sentence ends, never mid-sentence."""
    if len(s) <= maxlen:
        return [s]
    parts, cur = [], ""
    for sent in re.split(r"(?<=[.!?…])\s+", s):
        while len(sent) > maxlen:            # one pathological sentence
            cut = sent.rfind(" ", 0, maxlen)
            if cut <= 0:
                cut = maxlen
            parts.append(sent[:cut].strip())
            sent = sent[cut:].strip()
        if not cur:
            cur = sent
        elif len(cur) + 1 + len(sent) <= maxlen:
            cur += " " + sent
        else:
            parts.append(cur)
            cur = sent
    if cur:
        parts.append(cur)
    return [p for p in parts if p]

units = []
for p in paras:
    units.extend(split_long(p))

chunks, cur = [], ""
for u in units:
    if not cur:
        cur = u
    elif len(cur) + 2 + len(u) <= maxlen:
        cur += "\n\n" + u
    else:
        chunks.append(cur)
        cur = u
if cur:
    chunks.append(cur)

if not chunks:
    sys.stderr.write("no speakable text in input\n")
    sys.exit(1)

for i, c in enumerate(chunks, 1):
    with open(os.path.join(outdir, "chunk_%04d.txt" % i), "w", encoding="utf-8") as fh:
        fh.write(c + "\n")
print(len(chunks))
PY
}

edge_render_chunk() {
  local src="$1" dst="$2" attempt=1
  while [ "$attempt" -le 3 ]; do
    if [ -n "$EDGE_RATE" ]; then
      python3 -m edge_tts --voice "$EDGE_VOICE" --rate "$EDGE_RATE" \
        -f "$src" --write-media "$dst" >/dev/null 2>&1 || true
    else
      python3 -m edge_tts --voice "$EDGE_VOICE" \
        -f "$src" --write-media "$dst" >/dev/null 2>&1 || true
    fi
    if [ -s "$dst" ]; then return 0; fi
    rm -f "$dst"
    attempt=$((attempt + 1))
    if [ "$attempt" -le 3 ]; then sleep "$attempt"; fi
  done
  return 1
}

try_edge() {
  python3 -c "import edge_tts" >/dev/null 2>&1 || return 1

  local nchunks
  nchunks="$(edge_chunk_script | python3 - "$INPUT" "$WORKDIR" "$MAX_CHUNK" 2>/dev/null || echo "")"
  case "${nchunks:-}" in ''|*[!0-9]*) echo "[edge-tts] could not chunk input, skipping." >&2; return 1;; esac
  [ "$nchunks" -ge 1 ] || return 1

  echo "[edge-tts] rendering with neural voice: $EDGE_VOICE (${nchunks} chunk$([ "$nchunks" -eq 1 ] || echo s))"

  local i n part
  i=0
  for part in "$WORKDIR"/chunk_*.txt; do
    i=$((i + 1))
    n="$(printf '%04d' "$i")"
    if ! edge_render_chunk "$part" "$WORKDIR/part_$n.mp3"; then
      echo "[edge-tts] chunk $i of $nchunks failed after 3 attempts (no network route to provider?), falling back." >&2
      rm -f "$WORKDIR"/part_*.mp3
      return 1
    fi
    if [ "$nchunks" -gt 1 ]; then echo "   chunk $i/$nchunks ok"; fi
  done

  # No ffmpeg: only a single unnormalized mp3 can still be delivered.
  if ! command -v ffmpeg >/dev/null 2>&1; then
    if [ "$nchunks" -eq 1 ] && [ "$FMT" = "mp3" ]; then
      mv "$WORKDIR/part_0001.mp3" "$OUT"
      if [ "$NORMALIZE" -eq 1 ]; then
        echo "[warn] ffmpeg missing, skipped loudness normalization and ID3 title." >&2
      fi
      VOICE="$EDGE_VOICE"; ENGINE="edge-tts"; report "$OUT"; return 0
    fi
    echo "[edge-tts] ffmpeg required to join ${nchunks} chunks, falling back." >&2
    return 1
  fi

  # A short breath between chunks so the joins read as pauses, not splices.
  local gap=""
  if [ "$nchunks" -gt 1 ]; then
    gap="$WORKDIR/gap.mp3"
    ffmpeg -y -loglevel error -f lavfi -i anullsrc=r=24000:cl=mono \
      -t "$GAP_SECONDS" -codec:a libmp3lame -b:a 48k "$gap"
  fi

  local list="$WORKDIR/concat.txt"
  : > "$list"
  i=0
  for part in "$WORKDIR"/part_*.mp3; do
    i=$((i + 1))
    if [ "$i" -gt 1 ] && [ -n "$gap" ]; then printf "file '%s'\n" "$gap" >> "$list"; fi
    printf "file '%s'\n" "$part" >> "$list"
  done

  finalize "$list" 1
  VOICE="$EDGE_VOICE"; FMT="${OUT##*.}"; ENGINE="edge-tts"
  report "$OUT"; return 0
}

# ── 2/3) macOS say: Premium/Enhanced first, Samantha last ────
pick_voice() {
  [ -n "$VOICE" ] && { echo "$VOICE"; return; }
  local list; list="$(say -v '?' 2>/dev/null || true)"
  # Installed Premium/Enhanced voices only. Samantha is the explicit last
  # resort and must never win by default: it is the one voice this skill
  # exists to avoid handing over by accident.
  local prefs=("Ava (Premium)" "Zoe (Premium)" "Allison (Premium)" "Evan (Premium)" \
               "Samantha (Premium)" "Tom (Premium)" \
               "Ava (Enhanced)" "Zoe (Enhanced)" "Allison (Enhanced)" "Evan (Enhanced)" \
               "Samantha (Enhanced)" "Tom (Enhanced)")
  local v
  for v in "${prefs[@]}"; do
    printf '%s\n' "$list" | grep -qF "$v" && { echo "$v"; return; }
  done
  # Nothing better is installed.
  echo "Samantha"
}

try_say() {
  command -v say >/dev/null 2>&1 || return 1
  VOICE="$(pick_voice)"
  if [ "$VOICE" = "Samantha" ]; then
    ENGINE="say (last resort)"
    echo "[say] LAST RESORT: no neural route and no Premium/Enhanced voice installed, rendering with Samantha." >&2
    echo "[say]   Fix: System Settings ▸ Accessibility ▸ Spoken Content ▸ System Voice ▸ Manage Voices → download Ava (Premium)." >&2
  else
    ENGINE="say"
    echo "[say] rendering with local voice: $VOICE"
  fi

  # Render into the work dir so a failed run leaves nothing beside the deliverable.
  local aiff="$WORKDIR/say.aiff"
  if [ -n "$RATE" ]; then
    say -r "$RATE" -v "$VOICE" -f "$INPUT" -o "$aiff"
  else
    say -v "$VOICE" -f "$INPUT" -o "$aiff"
  fi

  # ffmpeg is primary (loudnorm + ID3 + any codec). lame/afconvert are
  # fallbacks only if ffmpeg is missing.
  if command -v ffmpeg >/dev/null 2>&1; then
    local list="$WORKDIR/concat.txt"
    printf "file '%s'\n" "$aiff" > "$list"
    finalize "$list" 0
  elif [ "$FMT" = "mp3" ] && command -v lame >/dev/null 2>&1 && command -v afconvert >/dev/null 2>&1; then
    afconvert "$aiff" "$WORKDIR/say.wav" -f WAVE -d LEI16
    lame -h -b 128 --quiet "$WORKDIR/say.wav" "$OUT"
  elif [ "$FMT" = "m4a" ] && command -v afconvert >/dev/null 2>&1; then
    # afconvert AAC fallback: omit explicit -b (pinning it triggers a '!dat' error on some inputs)
    afconvert -f m4af -d aac "$aiff" "$OUT"
  else
    OUT="$OUTBASE.aiff"
    cp "$aiff" "$OUT"
    echo "[warn] no encoder for $FMT found, left AIFF (install ffmpeg)." >&2
  fi
  report "$OUT"; return 0
}

# ── 4) piper (offline neural, needs a local model) ───────────
try_piper() {
  command -v piper >/dev/null 2>&1 || return 1
  [ -n "${PIPER_VOICE:-}" ] && [ -f "${PIPER_VOICE}" ] || return 1
  echo "[piper] rendering with model: $PIPER_VOICE"
  piper -m "$PIPER_VOICE" -f "$OUTBASE.wav" < "$INPUT"
  OUT="$OUTBASE.wav"; VOICE="$(basename "$PIPER_VOICE")"; FMT="wav"; ENGINE="piper"
  report "$OUT"; return 0
}

# ── engine chain ─────────────────────────────────────────────
case "$WANT_ENGINE" in
  edge)
    try_edge && exit 0
    echo "error: -v '$VOICE' is a neural voice but edge-tts could not render it." >&2
    exit 1
    ;;
  say)
    try_say && exit 0
    echo "error: -v '$VOICE' requested but macOS 'say' is unavailable." >&2
    exit 1
    ;;
  offline)
    # --offline: local engines only, the text never leaves this machine.
    try_say && exit 0
    try_piper && exit 0
    echo "error: --offline requested but no local TTS engine is available." >&2
    exit 1
    ;;
  *)
    try_edge && exit 0
    try_say && exit 0
    try_piper && exit 0
    ;;
esac

echo "No TTS engine available here." >&2
echo "→ Hand off $INPUT to NotebookLM / ElevenLabs / phone read-aloud, or run on a Mac (macOS 'say')." >&2
exit 1
