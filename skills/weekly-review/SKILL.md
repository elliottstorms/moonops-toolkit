---
name: weekly-review
description: Run the weekly review; gather live data from every active workstream, fill the weekly-review template, update the task list, and surface the top 3 for next week. Includes gated quarterly proofs (restore drill, backup tripwire self-test). Use when the user says "weekly review", "how did this week go", "wrap up the week", or on a Friday/Sunday cadence ask.
---

# Weekly review, the operating cadence

Fills `templates/weekly-review.md` from live sources, never from recall, and files it
where the nightly backup catches it. The review exists to keep three counters honest:
days-silent on people you are waiting on, drift between plan and reality, and any dated
tripwires you have set for yourself.

## Gather (all read-only, in one pass)

Adapt this list to your own sources; the shape is what matters. Every number in the
review has a file behind it.

1. **The task list**: done versus open, per section. Note anything that slipped multiple
   weeks running.
2. **Completions log**, if your dashboard or task UI writes one. That is the record of
   what actually got checked off.
3. **Shipping evidence**: `git -C <repo> log --oneline --since="7 days ago"` for each
   active repo. What shipped is a fact, not a feeling.
4. **Health checks** for anything you run in production (a site audit, a link check, a
   test suite). Run them in offline or read-only mode.
5. **Waiting-on days-silent**: compute from the last-contact dates in your task list.
6. **Backup health**: `tail -3 <backup log>`. Flag it if the last success is over 48
   hours old.

## Fill and file

- Copy the template to `reviews/YYYY-'W'WW.md` (create the directory once) and fill
  every `<placeholder>`. Filled means zero angle brackets remain.
- Wins come from the done list, the git log, and the completions log, not from vibes.
- Check every dated tripwire you have set (a deadline, a renewal, a decision window) and
  state the days remaining explicitly.
- Top 3 for next week: ranked by payoff. Whatever is time-critical outranks whatever is
  merely important.
- One thing to stop doing: propose it honestly. A task that has slipped three weeks is a
  candidate for deletion, not another carry-over.

## Close out

1. Update the task list: move confirmed-done items to Done with dates, and flag stale
   ones rather than silently carrying them forward.
2. Give the human the 60-second version: wins, the one worrying number, the top 3, and
   any days-silent counter at 4 or more.
3. Run the backup so the review itself lands off-machine.

## Quarterly proofs (gated)

Anchor these to a fixed date each quarter so they cannot drift. Check the marker first
(`cat reviews/.quarterly-last`, an ISO date; missing means never run). Run the block only
when the marker is at least 80 days old AND today is on or after the current quarter's
anchor date. If a scheduled task fires on the same anchors, whichever runs first writes
the marker and the other skips.

1. **Restore drill**: prove the backup mirror actually restores, rather than merely
   existing. An untested backup is a hope, not a backup.
2. **Backup tripwire self-test**: prove the secrets tripwire still fires on a planted
   credential-shaped file.
3. **Any read-only audits** you run on live surfaces (accessibility, SEO, security
   headers). Findings get ranked into the task list; fixes ship later through the normal
   pipeline, never inline here.

Then stamp the marker (`date +%F > reviews/.quarterly-last`), add a "Quarterly proofs"
block with each proof's verdict to this week's review file, and turn every failure into a
task-list item. A failed proof is never a silent skip.

## Hard rules

1. Numbers come from files, not recall. Every count in the review has a source.
2. The review never edits history. Last week's file is immutable once written.
3. If a section's source is missing, write "no data". Do not infer.
4. Quarterly proofs run at most once a quarter (the marker gates them), and their
   failures always land in the task list.
