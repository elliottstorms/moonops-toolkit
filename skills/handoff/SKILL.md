---
name: handoff
description: Produce a dispatch handoff — capture in-flight work, lock the decisions already made, and stage a paste-ready spec in ~/Claude/Handoffs/inbox/ for a fresh session or Claude Code to execute. Use when the user says "create a handoff", "stage this for a new session", "hand this off to Code", or "stage what I need for my credit reset / pass 1 of 2".
---

# Handoff — capture state, lock decisions, stage a dispatch

A handoff is a filled copy of the dispatch template that lets a DIFFERENT session (a fresh
Cowork chat, another agent, or Claude Code) resume the work with zero re-litigation. This skill
only PRODUCES the file — `/run-handoff` executes it. One format, one place: the template is
`~/Claude/Toolkit/templates/dispatch-request.md`, the destination is `~/Claude/Handoffs/inbox/`,
the name is `DISPATCH_<YYYY-MM-DD>_<slug>.md` (convention doc: `~/Claude/Handoffs/README.md`).

This also covers the "stage what I need for my 10:19pm credit reset / pass 1 of 2" case: that is
just a dispatch whose deliverable is "resume exactly here", with the exact next steps as its Spec.

## Step 1 — Gather current state (never from memory)

Read the source of truth first:

```bash
sed -n '1,40p' ~/Claude/TASKS.md
```

From TASKS.md plus the work done in this session, extract four things:

1. **In-flight work** — the ONE deliverable being handed off, not the whole backlog.
2. **Decisions already locked** — every choice that is settled (title, format, scope, paths, tokens).
3. **Exact next steps** — what the receiver does first, second, third to finish it.
4. **Provenance paths** — absolute paths to source of truth, prior versions, and research/decision docs, each with a date.

If any of the four is genuinely unknown, ask the user ONE question to fill it — never guess a
locked decision, and never invent a path.

## Step 2 — Copy the template

```bash
TODAY=$(date +%F)
SLUG=<short-kebab-deliverable>          # e.g. campfire-render, credit-reset-pass1
cp ~/Claude/Toolkit/templates/dispatch-request.md \
   ~/Claude/Handoffs/inbox/DISPATCH_${TODAY}_${SLUG}.md
```

## Step 3 — Fill every slot

Edit the new file top to bottom. Delete the template's `<!-- guidance -->` comments as you go
(they are notes to the author, not part of the dispatch), and replace every placeholder:

| Section | Fill with |
|---|---|
| Title / Date / Owner / Producer / Due | Deliverable in one phrase; today; who approves (usually you); who executes (Claude Code / next session); due date or "next session" |
| What's being produced | 2-3 sentences: the deliverable, its destination (upload / publish / commit / path), and the definition of done |
| Decisions already made | One ✅ bullet per locked decision from Step 1 — the receiver executes these as-is and may NOT reopen them |
| Spec | One row per hard constraint; every file path ABSOLUTE (source assets, output location, style/brand token) |
| Metadata / copy block | The exact strings the receiver pastes verbatim — titles, descriptions, tags, alt text; zero placeholders left inside the fenced block |
| Needs from owner | Blockers ONLY the owner can clear (missing credential, approval, asset). Nothing outstanding → write "none" so the receiver runs unattended |
| Provenance | Source-of-truth path + date; prior versions (or "none — first build"); related research/decision docs |

Rules while filling:

- Lock a decision by moving it into the ✅ list. Anything left unlocked becomes the receiver's
  judgment call — so lock everything you have already settled.
- Every path is absolute. The receiver is a fresh session with none of your context.
- The copy block is paste-ready. If a value is still unknown, either fill it or move it to
  Needs-from-owner — never leave a placeholder inside the copy block.

## Step 4 — Verify no placeholder survived (gate: zero angle brackets)

```bash
grep -nE '<[^>]+>' ~/Claude/Handoffs/inbox/DISPATCH_${TODAY}_${SLUG}.md
```

Filled means zero angle brackets remain. Any hit is an unfilled slot or a leftover template
comment — go back to Step 3 and clear it. No output = the dispatch is executable.

## Step 5 — Report

Tell the user:

- the absolute path of the staged file,
- the one-phrase deliverable and how many decisions are locked,
- that it is staged in `inbox/` and Claude Code's `/run-handoff` will execute it start-to-finish
  (the SessionStart hook also announces any waiting dispatch when a new Code session opens).

## Hard rules

1. Produce only — never execute the deliverable here; `/run-handoff` does that.
2. Lock everything settled into the ✅ list; an unlocked decision becomes the receiver's to make.
3. Absolute paths only — the receiver has none of your session memory.
4. No placeholder survives the copy block: fill it, or move it to Needs-from-owner.
