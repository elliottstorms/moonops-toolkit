<!--
WHEN TO USE: The moment you turn on any PII gate or adopt the AI use policy.
This is the artifact an auditor, examiner, or client due-diligence team actually
wants: not "we have controls" but dated proof the controls run and what they caught.
HOW TO FILL: Append-only. One row per event. Never edit or delete a row; corrections
get a new row referencing the old one. Keep it in version control so the history is
tamper-evident.
-->

# PII Evidence Log: <organization or machine>

**Started:** <YYYY-MM-DD> · **Owner:** <name> · **Reviewed:** <monthly, by whom>

## Event types

- `sweep`: scheduled scan ran (attach or link the report)
- `block`: a gate stopped something (tool-call, commit, publish)
- `override`: a human allowlisted or bypassed a finding (requires `why`)
- `incident`: PII reached somewhere it should not have (links to incident notes)
- `change`: gate config, policy, or scanner version changed
- `review`: periodic human review of this log happened

## The log

| Date (UTC) | Type | Surface | Actor | Model/tool | Data class involved | Outcome | Why / notes |
|---|---|---|---|---|---|---|---|
| <2026-01-06> | sweep | <~/work> | <cron> | pii-scan <ver> | none found | clean | weekly sweep, report at <path> |
| <2026-01-09> | block | <git pre-commit> | <name> | pii-scan <ver> | account number | commit stopped, value redacted | caught in <file>, synthetic per fixture policy: no |
| <2026-01-12> | override | <.pii-scan.json> | <name> | n/a | email | allowlisted | published contact address, entry carries why+date |

## How a reviewer reads this

Blocks with fixes are the system working. Overrides without a `why` are the
system rotting. Zero events for a quarter means the gates are off, not that
nothing happened: pair every quiet stretch with a `sweep` row proving the
machinery still runs.
