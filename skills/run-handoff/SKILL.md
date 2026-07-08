---
name: run-handoff
description: Execute the newest staged dispatch in ~/Claude/Handoffs/inbox/ start-to-finish — honor its locked decisions, do the work, verify, append an Outcome block, log external effects, and move it to done/. Use when the user says "run the handoff", "execute the latest dispatch", or "pick up where we left off".
---

# Run Handoff — consume the newest inbox dispatch

The counterpart to `/handoff`. A dispatch is a filled copy of
`~/Claude/Toolkit/templates/dispatch-request.md` staged in `~/Claude/Handoffs/inbox/`. This skill
executes exactly ONE — the newest — start-to-finish. The contract: honor every locked decision,
finish the Spec, prove it, record the outcome, log any external effect, file it under `done/`.
Convention doc: `~/Claude/Handoffs/README.md`.

## Step 1 — Find the newest dispatch (gate: one exists, or stop)

```bash
ls -t ~/Claude/Handoffs/inbox/*.md 2>/dev/null | head -1
```

- No output → tell the user "no dispatch waiting in ~/Claude/Handoffs/inbox/" and STOP. Do not
  invent work.
- A path prints → that single file is your target. Refer to it as `$F` below; substitute the
  actual path in each command (shell variables do not persist between calls). If several are
  waiting, this is the newest only — process it, then rerun to take the next.

## Step 2 — Read it in full

```bash
cat "$F"
```

Read every section: What's being produced, Decisions already made, Spec, Metadata / copy block,
Needs from owner, Provenance. The **Spec table is the contract**; anything not in it is your
judgment. The copy block is used verbatim.

## Step 3 — Honor the locked decisions (never reopen)

Every ✅ bullet under "Decisions already made" is settled. Execute it as-is. If one looks wrong,
you do NOT change it and you do NOT redesign around it — you finish per Spec and record the
objection for the owner in the Outcome block. Reopening a locked decision is the one thing this
skill must never do.

## Step 4 — Clear or surface blockers

Check "Needs from owner". If it lists anything unchecked that actually blocks execution (missing
credential, absent asset, required approval): do the part you can, then STOP at the blocker and
tell the user exactly what is needed. "none" or all boxes clear → run start-to-finish unattended.

## Step 5 — Execute the Spec start-to-finish

Do the work the dispatch describes, using the copy block verbatim and the Spec paths exactly:

- Site work → follow the `ship-site` skill (audit → push → verify live).
- Video work → follow the relevant publish skill for that surface.
- Doc / code / file work → produce it at the exact output path named in the Spec.

Use the absolute paths from Spec and Provenance — never rebuild from a stale copy you remember.

## Step 6 — Verify against the definition of done

Check the deliverable against "What's being produced" (the definition of done) and any Spec gate.
Separate what you VERIFIED (a check ran, a URL loaded, an exit code was 0) from what you only
assume. You record both, honestly, in the next step.

## Step 7 — Append the Outcome block

Append to the SAME file (do not edit anything above it). Fill each value before writing — no
angle brackets left:

```bash
cat >> "$F" <<'EOF'

## Outcome
- Shipped: <what was produced>
- Where: <URL / commit hash / absolute path>
- Verified: <what a check actually confirmed> · Not verified: <what remains assumed, or "none">
- Notes for owner: <objections to a locked decision, deviations, follow-ups — or "none">
EOF
```

## Step 8 — Log every external effect

For each real-world effect (upload, site ship, sale, backup, or a job that failed), append one
line to the reverse loop so the daily Cowork sync can auto-close the matching TASKS.md item:

```bash
sh ~/.claude/bin/status-append.sh code <type> "<summary>" "<url_or_commit>" <yes|no>
```

`<type>` is one of: `video-upload | site-ship | gumroad-sale | backup | job-failure | note`. Use
`verified=yes` ONLY for an effect you actually confirmed in Step 6. A dispatch that produced no
external effect (a local doc) needs no status line.

## Step 9 — File it under done/ and report

```bash
mv "$F" ~/Claude/Handoffs/done/
```

Then give the user a short summary: which dispatch ran, what shipped, where (URL / commit / path),
verified vs not, and any blocker or objection surfaced.

## Hard rules

1. Newest one only; empty inbox = stop, never invent work.
2. Never reopen a ✅ locked decision — execute as-is, object (if needed) in Outcome.
3. Verified means a check actually ran — never mark `verified=yes` on assumption.
4. Every external effect gets a `status-append.sh` line; then the file moves to `done/`.
