# MoonOps Design System — brand book

One system, two surfaces: the **web brand** (moonops.org, dashboards, internal tools) and the
**channel brand** (MoonOps sleep-video YouTube). Tokens in `tokens.css`, living component demo
in `components.html`. This file is the rules.

**MoonOps is design-first: craft outranks every other consideration. When in doubt, the calmer,
quieter option wins. the design lead (CCO) holds the veto on channel work; on web work, the veto is
"would this look at home on the live site?"**

## Web brand (site, dashboards, tools)

**Palette** — never hardcode; use the tokens:

| Token | Value | Use |
|---|---|---|
| `--ink` | `#0d162a` | Page background. Never pure black. |
| `--card` | `#16224a` | Raised surfaces. |
| `--cream` | `#f6f0eb` | Primary text. Never pure white. |
| `--steel` | `#92a2c4` | Secondary text, labels. |
| `--purple` | `#b95cff` | THE accent: links, primary actions. |
| `--green` | `#4aff9e` | Success/live, plus its one bounded second role: the mono-label/data accent (eyebrows, stats, timeline years). Never on a button, CTA, or large fill — that's a veto. |
| `--amber` / `--rose` | `#ffc86b` / `#ff6b8a` | Warn / blocked (tool UIs only). |
| `--text-lead` / `--text-body` | `#cdd6e8` / `#dbe2f0` | Lead and long-form text tints on gradient pages (between steel and cream). |
| `--grad-mid` / `--grad-deep` | `#131d3a` / `#1a1c44` | The body gradient's mid and deepest stops (with `--ink` at the ends). |

**Type** — Poppins for display and body; JetBrains Mono for eyebrows, labels, and data;
Georgia only for pull quotes. The `// eyebrow` mono label is the signature cue — every major
section gets one.

**Shape & motion** — 16px radius on cards and buttons (legacy 11–18px variants converge to 16
opportunistically, never as a repaint), pill radius on chips; one hover motion
(`translateY(-2px)`, .15s ease) everywhere, with .2s reserved for image zooms; one shadow.
Nothing bounces, nothing spins.

**Named exceptions (Council resolution 2026-07-11, 5-0)** — the index turntable set-piece is the
one sanctioned spin (it's a record; records spin) and must stay inside `prefers-reduced-motion`;
citing it to justify a second spin anywhere is a veto. SVG internals (the moonmark gradient stops on all
five pages, the turntable record-label gradient stops on index, `favicon.svg`) intentionally carry
literal hex — hand-sync them if `--purple-bright` ever changes (a one-shared-CSS-rule fix is pre-approved for after 2026-07-15).

**Hard rules**
1. Dark surfaces only. No light-mode variant exists.
2. Purple is the protagonist; green is punctuation. If a screen has more green than purple,
   it's wrong.
3. Body copy in steel, headings in cream — hierarchy comes from color, not size inflation.
4. The crescent moon mark appears once per page (nav or header), not scattered.
5. Quote inline attribute JS with double-quoted attributes + single-quoted strings
   (`onmouseover="this.style.x='y'"`) — and remember Netlify post-processing stays OFF.

## Channel brand (YouTube)

1. **Calm is the product.** No thunder/transients in "gentle" content lines; screen fades to
   black (45s standard) because a dark room is the actual feature.
2. **Titles:** ≤100 chars hard cap (YouTube rejects over), duration-prefixed when accurate
   ("12 Hours…"), no em dashes anywhere in public copy, no claims we can't guarantee
   (e.g. "No Ads").
3. **Thumbnails:** MoonOps system only — night palette, crescent moon, silhouette subjects.
   No stock faces, no yellow arrows, no red circles.
4. **The caretaker line** (kid-friendly nightlight, pet-friendly) extends the brand; it never
   turns into stimulation content ("Dog TV" motion is a non-goal).
5. the design lead's veto is real: a render that fails the "calm, beautiful, 2am viewer" bar doesn't ship,
   regardless of schedule.

## Names and referents (procedural audio)

Added 2026-08-09 by the design lead's proposal, after the rule caught four scenes in one night and
turned out to exist nowhere but in Council minutes.

**A name is a promise about a sound, and it is public copy.** This rule binds every surface a
name reaches, with no gradient of seriousness between them:

- video titles, descriptions, tags and chapter lines
- on-screen affirmations burned into the render
- packaged filenames
- the embedded metadata title tag inside the audio file itself
- store listing copy

The filename and the embedded tag matter as much as the title. They are what a buyer reads in
their own music player, after paying, which is the worst possible moment to discover the name
was decoration.

**The rule: no name may assert a sound the engine cannot produce.**

A procedural engine built from noise sources, filters, tremolo and drift generates *stationary*
texture. It has no impulse, grain or event generator, so it cannot produce a discrete acoustic
event: a water droplet, a thunder clap, a crackle, a heartbeat, a blade-pass tone. Broadband
continuous referents are honestly reachable and always were. Rain, wind, gale, surf and waterfall
roar are genuinely stationary broadband in the real world, so they ship honestly. A brook is not.
This is a rule about what a referent actually sounds like, not a ban on any subject.

**An exception requires a listen plus a measurement. Never a recipe parameter.**

This is the whole rule in one line, and it is the one that keeps getting broken, because a recipe
parameter is so persuasive. A tremolo set to 4.6 Hz is not a babbling brook. A tremolo set to
1.1 Hz is not a heartbeat, even though 1.1 Hz is exactly 66 beats per minute. A tremolo set to
4.5 Hz is not a fan. In all three cases the number looked like evidence and was not, because the
generator was still emitting a smooth swell and the name was claiming an event.

**Build a positive control before you trust any of this**

The most expensive mistake available here is running a detector against a quiet negative control
and reading the difference as meaning. Synthesize the event you are testing for, at the same
modulation depth as the audio under test, and confirm your detector separates it. Two thirds of
the metrics in the first version of this section did not survive that step, and they had already
been written down as evidence.

Specifically, **spectral-flux onset density is not a usable test on filtered noise.** Measured on
purpose-built files: audio with real, audible cardiac thumps scored 1.458 events/sec, audio with
no events at all scored 1.217/sec, and the stationary control scored 1.212/sec. The detector
cannot tell them apart, because broadband noise generates flux peaks continuously. **Crest factor
is worse than useless: it inverts.** Real thumps measured 6.74 dB against 14.49 dB for the
event-free file, because a genuine transient raises the RMS more than it raises the peak in
already-dense noise. Do not cite either number.

**The test that does work: fold the envelope**

Band-limit to where the event would live, take the analytic (Hilbert) envelope, find the candidate
modulation rate, and fold every cycle onto one. Then read four things off the folded cycle:

- **Harmonic ratio**, energy at 2f and 3f against the fundamental. At matched depth: a pure sine
  swell scores about 0.13, a heavily muffled two-part beat 0.85, a single thump 1.23, a clean
  two-part beat 1.62.
- **Sine fit R squared** on the folded cycle. Above about 0.98 the envelope *is* a sinusoid.
- **Peaks per cycle**, which distinguishes a two-part beat from one swell.
- **Rise time against fall time.** A swell is symmetric. An event is not.

Use this in one direction only. A low ratio plus a high sine fit proves the envelope is a sinusoid,
and a sinusoid is never an event, so the noun is refused. The reverse does not hold: an asymmetric
gain swell containing no events at all scores 0.64, so a high ratio never *grants* an event noun.
Nothing here can grant one. Only a listen can.

**A fifth check that is worth more than it looks: per-band modulation depth.** Measure the swell
depth separately in each octave. A real source modulates its own band and leaves the others alone,
so the spread across bands is large, 12 to 34 dB in testing. A single modulator on a whole mix
moves every band together: spread of 2.8 dB, which is a volume knob, not a body. This is the check
that catches a claim whose rate is perfectly right, and rate is the thing that fools people.

**Measure the artifact that shipped, not its sibling.** A pack render and a video render can come
from the same recipe through different code paths and differ in channel count, loudness and
engine version. If the shipped file is gone, say the finding rests on reconstruction and say so
in the record.

**When a name fails**

Rename rather than pull, where the audio is honest and only the label lied. Fix the filename and
the embedded tag together, remux with a stream copy so the audio stays bit identical, and add the
corrected name to whatever export map the build uses, or the next rebuild silently restores the
old one. Archive the prior name, tags and checksums before touching anything.

## Using this system in a new project

1. Copy `tokens.css` (or its `:root` block) in verbatim.
2. Steal components from `components.html` — they're dependency-free.
3. Run the result past the checklist: dark base ✓ eyebrows ✓ one accent hierarchy ✓
   single hover motion ✓ moon mark once ✓.
4. For any AI model building UI: paste this README + tokens.css into context and instruct
   "use only these tokens and components; do not invent new colors or motions."

## For scripts that render branded assets

Any Python/automation that generates a branded asset (thumbnails, cards, report images) must **not**
hardcode hex values. Import the machine-readable mirrors of this palette — both generated from
`tokens.css`:

- **`palette.py`** — constants `INK, CARD, CREAM, STEEL, PURPLE, GREEN, AMBER, ROSE, FONT_DISPLAY, FONT_MONO`.
- **`palette.json`** — the same tokens as JSON (`ink`, `card`, … `font_display`, `font_mono`).

`tokens.css` stays the source of truth; when it changes, mirror the change into `palette.py` and
`palette.json`.
