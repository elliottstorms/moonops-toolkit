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
