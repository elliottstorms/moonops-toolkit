---
name: audiocast
description: Turn ANY script or text into a clean, shareable audio file (mp3), fully offline on macOS via the built-in `say` engine. Use when the user says "make this a shareable audio file", "turn this into audio / an mp3 / a voiceover / a podcast", "read this aloud", or "voice this script", or hands over text and wants to hear it or send it to someone.
---

# Audiocast - any script to a shareable audio file

Takes any text and produces a clean spoken-word audio file the user can play or send to anyone. The default path is 100% offline on a Mac (macOS `say` plus `ffmpeg`) - no accounts, no network, no installs. Output is an **mp3** by default because it plays everywhere.

This skill changes the **format**, never the **content**. Keep the words as written.

## Step 1 - Get the script

In order of preference:
1. Text or a file the user provides now (pasted text, or a path to a `.txt` / `.md` / `.docx`).
2. A specific earlier message they point to.
3. If it is genuinely ambiguous which text is meant, ask - never guess between two candidates.

For `.md`, `.docx`, or rich text, pull out the plain prose first.

## Step 2 - Clean it into TTS-ready text

TTS reads **literally**, so strip anything the ear cannot parse and make symbols speakable. Save the result as plain UTF-8 `.txt`.

- Remove markdown (`#`, `*`, backticks, link brackets), emoji, and any icons or glyphs. A header becomes a spoken lead-in or just a paragraph break.
- Turn tables and bullet lists into spoken sentences, or "first... second... third...".
- Make numbers and symbols speakable: "$40K" becomes "forty thousand dollars"; "25 deg" becomes "twenty-five degrees"; a domain like "example.com" becomes "example dot com". Expand acronyms that mangle in TTS.
- Spell out or drop URLs and emails ("link in the description").
- Keep sentences a touch shorter than written prose; the ear prefers it. Do not add or drop meaning.
- Do NOT leave stage directions, section labels, or "[pause]" in the body - they get read aloud. Use paragraph breaks for pacing.

## Step 3 - Render (pick voice and format first)

Defaults: voice = best installed (falls back to **Samantha**), format = **mp3**, loudness-normalized so it sounds consistent wherever it plays. Override only on request ("British voice", "faster", "make it an m4a").

```bash
~/.claude/skills/audiocast/render_audio.sh -i "path/to/script.txt" -t "Title For Sharing"
```

Flags:
- `-i` input `.txt` (required) · `-o` output path · `-t` title (ID3 tag plus filename)
- `-v` voice · `-f mp3|m4a` · `-r` rate in words/min (e.g. `-r 170`) · `--raw` (skip loudness normalize)
- Output defaults to `~/Claude/Audio/<slug>_<date>.mp3`. Override the directory with the `AUDIOCAST_OUTDIR` env var.

Better voices are **free**: **System Settings > Accessibility > Spoken Content > System Voice > Manage Voices** and download an *Enhanced* or *Premium* English voice. The renderer auto-prefers them once installed; or pass the exact name with `-v`.

## Step 4 - Polish (optional, only if asked)

With `ffmpeg`: a soft music/ambience bed under the voice (duck it well below the speech), an intro/outro, or a different loudness target. Keep it subtle unless a produced feel is wanted.

## Step 5 - Deliver

Give the **file path, its duration and size**, and one line on what it is. Offer to re-render in another voice, speed, or format. Everything stays local; nothing is uploaded.

## Fallbacks (if `say` is not available)

The renderer tries `say`, then `edge-tts` (a neural voice, needs network), then `piper` (offline neural, needs a local `.onnx` model), then hands off. If no engine works, deliver the clean `.txt` and suggest a notebook-style reader, a hosted TTS service, or a phone's read-aloud - the script is already clean enough to paste anywhere.

## House rules

- **Format-only.** Never change the meaning of the words to make them "flow." If a line reads awkwardly aloud, rephrase the *sentence*, not the *point*.
- **mp3 by default** (universally shareable); m4a only on request (smaller, still plays broadly).
- **One voice** unless a two-host feel is requested.
- **Local and offline by default** - nothing leaves the machine.

## Requirements

macOS (for the built-in `say` voices) and `ffmpeg` on the PATH for encoding and loudness
normalization (`brew install ffmpeg`). Without `ffmpeg` the script falls back to `afconvert`
or `lame` if present, or leaves a `.aiff`.
