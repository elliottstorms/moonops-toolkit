---
name: pii-gate
description: 'The routines that make pii-scan ambient instead of optional - a Claude Code PreToolUse hook that blocks PII from leaving through tool calls, a git pre-commit hook that blocks PII from entering history, and a scheduled sweep that produces a dated evidence trail. Use when setting up PII protection for a machine or repo, when the user says "make sure PII never leaks", "add the PII gate", or when a gate block needs triage.'
---

# PII Gate: three routines around one scanner

`pii-scan` is the engine; this skill is the wiring. The goal is that nobody has
to remember to check, because the checks sit on the paths PII would travel.

## Routine 1: the tool-call gate (Claude Code hook)

`bin/pii-gate-hook.sh` reads the PreToolUse payload, extracts every string in
`tool_input`, and runs the gate over it. Exit 2 blocks the call and the model
sees why on stderr.

Wire it in `settings.json` (see `settings.example.json` in this repo):

```json
{
  "matcher": "Write|Edit|WebFetch",
  "hooks": [{
    "type": "command",
    "command": "/Users/you/.claude/bin/pii-gate-hook.sh",
    "timeout": 15,
    "statusMessage": "PII gate..."
  }]
}
```

Pick matchers by leak path, not by habit: `Write|Edit` keeps PII out of files,
`WebFetch` keeps it out of URLs and prompts leaving the machine. Gating `Bash`
is possible but noisy; prefer the git hook below for commit safety.

## Routine 2: the commit gate (git hook)

`pre-commit.sample` (next to this file) scans staged blobs and refuses the
commit on findings. Install per repo:

```bash
cp skills/pii-gate/pre-commit.sample .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

History is the leak path people forget: a value committed once is in every
clone forever, and deleting the file does not delete the blob. Block at the
door, not after the party.

## Routine 3: the scheduled sweep (evidence trail)

A weekly cron or launchd job that scans the directories where sensitive work
lives and files a dated JSON report:

```bash
# crontab: every Monday 08:00
0 8 * * 1 python3 $HOME/.claude/skills/pii-scan/pii_scan.py --json \
  $HOME/work > $HOME/logs/pii-sweep-$(date +\%F).json 2>> $HOME/logs/pii-sweep.err
```

Add one row per sweep to the evidence log (`templates/pii-evidence-log.md`).
The sweep is what turns "we have a policy" into "here is the dated proof it
runs", which is the difference an examiner or auditor actually cares about.

## Triage: when the gate blocks something

1. Read the finding. If it is real PII, redact or remove it. That is the gate
   doing its job; do not reach for the allowlist first.
2. If it is a true false positive (a test fixture, a published contact email),
   add an object-form allowlist entry to `.pii-scan.json` with `why` and
   `added` filled in. Bare-string allowlist entries with no reason are how
   gates rot.
3. Never bypass with `--no-verify` or by disabling the hook. If the gate is
   wrong often enough to be tempting, fix the config and keep the receipt.
