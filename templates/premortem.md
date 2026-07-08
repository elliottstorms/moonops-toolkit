<!--
WHEN TO USE: Before committing real time or money to a plan (new project, job offer, launch, big purchase).
HOW TO FILL: Assume it's 6 months later and the thing FAILED. Work backward: list the 5 most likely causes,
then for each name the earliest signal you'd actually see and the cheapest mitigation. Tripwires must be if-X-then-Y with numbers.
-->

# Premortem: <project or decision>

**Date:** <YYYY-MM-DD> · **Horizon:** <e.g. 6 months → YYYY-MM-DD> · **Owner:** <name>

## The obituary

<2-3 sentences, past tense, written from the failure date. "It's <month + 6>. <Project> is dead. What killed it was...">

## Top 5 failure causes

<!-- Likelihood: HIGH / MED / LOW. Earliest signal = something observable BEFORE the failure is obvious. -->

| # | Failure cause | Likelihood | Earliest detectable signal | Cheap mitigation (do now) |
|---|---|---|---|---|
| 1 | <specific cause, not "bad luck"> | <H/M/L> | <observable, dated, measurable> | <action < 1 hr or < $50> |
| 2 | <cause> | <H/M/L> | <signal> | <mitigation> |
| 3 | <cause> | <H/M/L> | <signal> | <mitigation> |
| 4 | <cause> | <H/M/L> | <signal> | <mitigation> |
| 5 | <cause> | <H/M/L> | <signal> | <mitigation> |

## Tripwires

<!-- Pre-committed reactions. Numbers, not adjectives. Review these at each weekly review. -->

- IF <measurable condition, e.g. "no reply by YYYY-MM-DD"> → THEN <specific action, e.g. "send nudge #2, start parallel track">
- IF <condition, e.g. "metric X below N at week 4"> → THEN <action>
- IF <condition> → THEN <action, including "kill it" where honest>

## Mitigations scheduled

<!-- Pull the "do now" column into actual commitments. Unscheduled mitigation = decoration. -->

- [ ] <mitigation 1> — by <date>
- [ ] <mitigation 2> — by <date>

## Review date

Re-run this premortem on <YYYY-MM-DD, ~1/3 of the way to horizon> or when any tripwire fires, whichever is first.
