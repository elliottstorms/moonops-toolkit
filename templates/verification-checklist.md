<!--
WHEN TO USE: At the END of any session that claims external effects (deploys, uploads, emails sent, files moved, configs changed).
HOW TO FILL: One row per claim. "How verified" must be reproducible evidence — a command + its output, a URL check, or a screenshot path.
If you cannot verify it, it goes in the NOT VERIFIABLE table with an exact manual check. Never promote unverified to done.
-->

# Verification checklist: <session or change in one phrase>

**Date:** <YYYY-MM-DD> · **Verifier:** <name or model> · **Scope:** <what work is being verified>

> **RULE: An unverified claim gets reported as UNVERIFIED, never as done.**
> "The tool call returned success" is a claim, not a verification. Verification = independent evidence the effect exists.

## Verified claims

<!-- Evidence column: exact command AND relevant output line, or URL + what was observed, or screenshot path. -->

| Claimed | How verified (command / output / screenshot) | Result |
|---|---|---|
| <e.g. "site deployed to prod"> | `<command run>` → `<output line that proves it>` | <PASS/FAIL> |
| <e.g. "file committed and pushed"> | `<command>` → `<output>` | <PASS/FAIL> |
| <claim> | <evidence> | <PASS/FAIL> |

## NOT verifiable from here

<!-- Anything needing auth, a human eyeball, or an external UI. Manual check must be copy-paste executable by the user. -->

| Claimed | Why not verifiable | Exact manual check for the user |
|---|---|---|
| <e.g. "email sent to X"> | <e.g. "no read access to sent folder"> | <e.g. "Open Gmail → Sent → confirm message to X dated YYYY-MM-DD"> |
| <claim> | <reason> | <step-by-step check> |

## Failed or partial

<!-- Anything that did NOT pass. Silence here after a failure is the exact bug this template exists to kill. -->

- <claim that failed + current actual state + what was attempted (max 2 fix attempts, then stop and report)>
- <or "none">

## Bottom line

**Verified done:** <n> · **Needs your manual check:** <n> · **Failed/partial:** <n>

<One sentence: is the overall claimed outcome trustworthy as-is, or contingent on the manual checks above?>
