---
name: backup
description: 'Run or check the durable-asset backup; it mirrors your skills, agents, hooks, CLAUDE.md, and settings to a PRIVATE GitHub repo, refusing to commit anything credential-shaped. Use when the user says "back up", "backup now", "is my backup current", or after building any new durable asset.'
---

# Backup: the durable-asset mirror

Mirrors the assets that are expensive to rebuild (skills, agents, hooks, operator manual,
settings) into a **private** GitHub repo. The point is recoverability, not publication:
this repo stays private and PII never enters it.

## Run it

```sh
sh backup/backup.sh
```

The script is idempotent: it commits and pushes only when something actually changed, so it's
safe to run on every session or on a daily schedule.

## What it does

1. rsyncs the included sources into a local staging mirror.
2. Runs a **secrets tripwire**: it aborts (no commit) if it finds a credential-shaped filename
   (`*.pem`, `*.key`, `*token*.json`, `.env`, `client_secret*`, `credentials*.json`) or a
   token-shaped string in the staged content.
3. Commits and pushes only the diff.

## Guardrails

- The backup repo is **private**. If you want a *public* toolkit, that's a separate,
  allowlisted export; never point this script at a public repo.
- PII (job-search, finance, personal notes) is excluded permanently. Keep it that way.
- If the tripwire ever fires, the fix is removing the credential from the staging tree,
  not negotiating with the tripwire.
- **A file held back by a content filter is the guard working.** If you carve out an
  exception to a PII exclusion, filter it by content rather than trusting the folder, log
  every file held back by name rather than dropping it silently, and use
  `rsync --delete-excluded` so a file that LATER gains a sensitive mention is retracted
  from the mirror instead of left stale. When the log names a file you expected to see
  mirrored, read the match. Never reword the file so it slips past the filter.
- **When a file splits, the include list follows it in the same change.** The list names
  files, so rolling a growing file into an archive or a log quietly drops that content
  from the mirror while the backup keeps reporting success. Treat any cleanup that moves
  content between files as a backup change too.

## Check status

"Is my backup current?" → run the script; if it prints "no changes, nothing to back up",
the mirror already matches your working assets.
