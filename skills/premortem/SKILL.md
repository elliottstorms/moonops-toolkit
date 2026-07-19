---
name: premortem
description: Run a structured pre-mortem on any plan, project, or launch — jump to a failure horizon ("it's 6 months later and this failed"), reconstruct the death, rank root causes, then write preventions back INTO the live plan as checkable gates. Use when the user says "premortem", "pre-mortem", "assume this failed", "why will this fail", "stress-test this plan", "poke holes in this", "what kills this", or before any launch/major commitment whose plan has no failure analysis yet.
---

# Pre-mortem — kill the plan on paper first

Prospective hindsight: declaring failure as an accomplished fact unlocks specific causes that
"what might go wrong?" never surfaces (Klein's technique). The deliverable is NOT the document —
it's the **diff to the live plan**. A pre-mortem that produces prose but changes no gate, task,
or calendar entry has failed.

## Procedure

1. **Fix the horizon and define "failed" concretely.** Not "it didn't work" — pick the date and
   the observable corpse: "January 2027, <$500 revenue, no commits in 8 weeks, renewal email
   unanswered." Ask the user for the horizon only if it isn't obvious from the plan.
2. **Write the reconstruction as a retrospective.** Dated timeline, written in past tense, with
   plausible numbers **labeled illustrative** and anchored to category base rates (research them
   if unknown — never anchor to hopes). The tone is a competent post-mortem, not a horror story.
3. **Rank root causes by the sufficiency test:** "would this alone have killed it?" Sufficient
   causes outrank contributors. Demand specificity — each cause must be falsifiable and name the
   missing artifact or behavior ("zero distribution milestones existed" ✓; "didn't market
   enough" ✗). Include the **human causes** — attention budgets, competing priorities,
   incentive gaps, how the operator emotionally reads early numbers — and check them against
   the user's documented blind spots (CLAUDE.md); plans rarely die of mechanics alone.
4. **Steelman what went right.** One section. It keeps the exercise honest, protects the parts
   that shouldn't change, and makes the criticism land as analysis instead of doom.
5. **Map preventions 1:1 to causes.** Every prevention is a checkable gate — an owner, a date,
   a threshold, a scheduled review — never an adverb ("market harder" is not a prevention;
   "waitlist page live by day 3, gate on submission" is).
6. **Integrate.** Edit the live plan document, add/update tasks in the task system, put the
   decision reviews on a real calendar or scheduler. Then commit/push if the plan lives in git.

## Output format (template)

```
# Post-Mortem: <name> (<start> – <horizon>)
*Written as a pre-mortem on <today> — dated forward and worked backward. Timeline is a
plausible reconstruction; numbers are illustrative of base rates. Root causes are real today.*

## The one-line verdict
## What happened (reconstruction)      ← dated table
## Root causes, ranked                 ← sufficiency-tested, specific, human causes included
## What we got right
## The preventions (added to <plan doc>)  ← table: # | kills cause | prevention (checkable)
## The sentence to remember
```

## Quality bar — reject your own draft if:

- A cause flatters the plan ("we were too ambitious") or blames only outsiders.
- A prevention has no owner, date, threshold, or calendar artifact.
- There are more than ~6 root causes — rank harder; it's an analysis, not a listicle.
- The most likely cause of death (usually **distribution/attention**, not construction) is
  missing. Builders' pre-mortems chronically over-index on the build.
- Nothing got edited: no plan diff, no new tasks, no scheduled review ⇒ not done.

## Canonical example

`~/Claude/Projects/dopamine-app/docs/PREMORTEM.md` (2026-07-10) — verdict "the app dies of
silence, not defects"; six ranked causes; preventions merged into LAUNCH_PLAN.md the same hour.
