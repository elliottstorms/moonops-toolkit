---
name: audiocast
description: 'Turn ANY script or text into a clean, shareable audio file (mp3) in a neural voice, with a fully offline fallback on macOS. Use when the user says "make this a shareable audio file", "turn this into audio / an mp3 / a voiceover / a podcast", "read this aloud", or "voice this script", or hands over text and wants to hear it or send it to someone.'
---

# Audiocast - any script to a shareable audio file

Takes any text and produces a clean spoken-word audio file the user can play or send to anyone. The default voice is a **neural** voice (`en-US-AvaNeural` via edge-tts), with a fully offline macOS `say` path behind it when the network is unreachable. No accounts, no API keys. Output is an **mp3** by default because it plays everywhere.

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

Defaults: voice = **neural `en-US-AvaNeural`**, format = **mp3**, loudness-normalized to -16 LUFS so it sounds consistent wherever it plays. The renderer enforces this order itself, so the defaults need no arguments. Override only on request ("British voice", "faster", "make it an m4a").

```bash
~/.claude/skills/audiocast/render_audio.sh -i "path/to/script.txt" -t "Title For Sharing"
```

Flags:
- `-i` input `.txt` (required) · `-o` output path · `-t` title (ID3 tag plus filename)
- `-v` voice · `-f mp3|m4a` · `-r` rate · `--raw` (skip loudness normalize) · `--offline` (local engines only)
- `-v` routes by the shape of the name: a locale-style neural id (`en-GB-SoniaNeural`) forces edge-tts, any other name (`Daniel`, `Ava (Premium)`) forces the local `say` engine. An explicit override always beats the auto chain.
- `-r` takes words/min for the local voices (`-r 170`) or a percentage for neural (`-r "+10%"`). A bare number is converted for the neural path against a 175 wpm baseline.
- Output defaults to `~/Claude/Audio/<slug>_<date>.mp3`. Override the directory with the `AUDIOCAST_OUTDIR` env var.

**Long scripts are chunked.** A single edge-tts request on a multi-thousand-word script is unreliable, so the renderer splits the text on paragraph and sentence boundaries (about 1400 characters, never mid-sentence), renders each piece with 3 retries, and concatenates them with a 0.35s breath between parts. Tune with `AUDIOCAST_CHUNK_CHARS`. A 4,000-word script lands as roughly 25 requests and one seamless file.

**On voice quality, learned the hard way.** `say`'s stock voices, Samantha above all, sound conspicuously synthetic to anyone who has heard a current neural voice, and audio you intend to *share* is exactly where that shows. That is why the neural voice is the default rather than the upgrade. Pick the default deliberately and write it down, because this is a setting people set once and then never revisit while quietly disliking every file it produces.

**On fallback chains, also learned the hard way.** This renderer previously listed `say` first and neural second. Because `say` exists on every Mac and always succeeds, the neural branch was unreachable code and every file for weeks came out in the fallback voice, while the documentation confidently described the opposite. If your chain's first engine cannot fail, you do not have a chain, you have a hard-coded choice with extra steps. Order a fallback chain best-first, and make the last resort announce itself.

For the **offline tier**, better voices are **free**: **System Settings > Accessibility > Spoken Content > System Voice > Manage Voices** and download an *Enhanced* or *Premium* English voice. The renderer auto-prefers them once installed; or pass the exact name with `-v`. With none installed, the offline tier lands on Samantha and says so loudly.

## Step 4 - Polish (optional, only if asked)

With `ffmpeg`: a soft music/ambience bed under the voice (duck it well below the speech), an intro/outro, or a different loudness target. Keep it subtle unless a produced feel is wanted.

## Step 5 - Deliver

Give the **file path, its duration and size**, and one line on what it is. Offer to re-render in another voice, speed, or format. Read the `engine=` field in the report line first: if it says `say (last resort)`, mention that instead of handing over a fallback-voice file as though it were the intended one.

## Fallbacks

The renderer tries, in this order:

1. **edge-tts `en-US-AvaNeural`** (neural, needs network, chunked for long scripts)
2. **macOS `say` with an installed Premium/Enhanced voice** (offline)
3. **macOS `say` Samantha** (offline, explicit last resort, prints a warning plus the one-line fix)
4. **piper** (offline neural, needs a local `.onnx` model at `$PIPER_VOICE`)

Then it hands off. If no engine works, deliver the clean `.txt` and suggest a notebook-style reader, a hosted TTS service, or a phone's read-aloud - the script is already clean enough to paste anywhere.

Every path produces the same deliverable: target format, loudness normalization, ID3 title, and an `AUDIOCAST_OK|...` report line carrying the file, length, size, voice, format, and which engine actually rendered.

## House rules

- **Format-only.** Never change the meaning of the words to make them "flow." If a line reads awkwardly aloud, rephrase the *sentence*, not the *point*.
- **mp3 by default** (universally shareable); m4a only on request (smaller, still plays broadly).
- **One voice** unless a two-host feel is requested.
- **Neural by default, offline on demand.** The default path sends the script text to Microsoft's TTS endpoint. That is a fine trade for most scripts and a bad one for anything confidential, so pass `--offline` for sensitive material and the words never leave the machine. Engines 2 through 4 never touch the network.

## Requirements

macOS (for the built-in `say` voices) and `ffmpeg` on the PATH for encoding, concatenation, and
loudness normalization (`brew install ffmpeg`). For the neural default, `edge_tts` as a Python
module (`pip install edge-tts`, then invoked as `python3 -m edge_tts`); the renderer falls back
to the local engines when it is missing or unreachable. Without `ffmpeg` the script falls back to
`afconvert` or `lame` if present, or leaves a `.aiff`.
