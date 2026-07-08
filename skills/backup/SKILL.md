---
name: backup
description: Run or check the durable-asset backup — mirrors your skills, agents, hooks, CLAUDE.md, and settings to a PRIVATE GitHub repo, refusing to commit anything credential-shaped. Use when the user says "back up", "backup now", "is my backup current", or after building any new durable asset.
---

# Backup — durable-asset mirror

Mirrors the assets that are expensive to rebuild (skills, agents, hooks, operator manual,
settings) into a **private** GitHub repo. The point is recoverability, not publication:
this repo stays private and PII never enters it.

## Run it

```sh
sh backup/backup.sh
```

The script is idempotent — it commits and pushes only when something actually changed, so it's
safe to run on every session or on a daily schedule.

## What it does

1. rsyncs the included sources into a local staging mirror.
2. Runs a **secrets tripwire**: it aborts (no commit) if it finds a credential-shaped filename
   (`*.pem`, `*.key`, `*token*.json`, `.env`, `client_secret*`, `credentials*.json`) or a
   token-shaped string in the staged content.
3. Commits and pushes only the diff.

## Guardrails

- The backup repo is **private**. If you want a *public* toolkit, that's a separate,
  allowlisted export — never point this script at a public repo.
- PII (job-search, finance, personal notes) is excluded permanently. Keep it that way.
- If the tripwire ever fires, do not "fix" it by loosening the rule. Find the credential,
  remove it from the staging tree, and re-run.

## Check status

"Is my backup current?" → run the script; if it prints "no changes — nothing to back up",
the mirror already matches your working assets.
