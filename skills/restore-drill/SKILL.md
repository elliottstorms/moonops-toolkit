---
name: restore-drill
description: "Prove the backup actually restores: clone the private GitHub mirror to a temp dir and compare it against every live source it mirrors (skills, agents, bin, CLAUDE.md, settings, Toolkit, TASKS.md, STATUS.md and the other workspace files, memory, launchd plists, the LinkedIn carve-out, the Projects allow-list, and the Proposals, Handoffs, Archive and Audio extras), using backup.sh's own copy rules so its deliberate holdbacks never read as drift. An untested backup is a hope, not a backup. Use when the user says 'restore drill', 'prove the backup', 'test the backup', 'would the backup actually work', or on a quarterly cadence, and after any change to backup.sh's include list or tripwire."
---

# Restore drill: prove the backup restores

Run the bundled script. It clones `your-username/your-backup-repo` fresh from
GitHub (not the local stage: the point is proving the *cloud* copy), then
compares every mirrored scope against its live source. It takes about a minute.

```bash
sh ~/.claude/skills/restore-drill/restore_drill.sh
```

## How it knows what should be there

The plain copies (Toolkit, skills, agents, bin, memory, settings, and every
single file `backup.sh` copies with `cp`) are compared with `diff`. The rest of
the mirror is copied with rules: rsync exclusions, a 5 MB cap, and per-file
holdbacks for privacy terms and for pages that embed media as base64 text.

Since 2026-09-23 the drill keeps no copy of those rules. It reads them out of
`backup.sh` each time it runs, asks rsync in dry-run mode which files
`backup.sh` would copy right now, recomputes the holdbacks with `backup.sh`'s own
patterns (proved first against `backup.sh`'s own canary lines), and compares
that set with the clone. Change a rule in `backup.sh` and the drill's
expectation changes with it.

The few pieces that are code rather than data (which scopes run which holdback,
and where each workspace extra lands) are restated in the drill beside a shape
check. If `backup.sh` changes shape there, the drill stops with `CANNOT RUN`
instead of comparing against rules that no longer apply. A scope group that a
`backup.sh` does not configure at all is skipped, not failed.

## Reading the result

The verdict is the last `RESTORE DRILL:` line (exit code in brackets):

- `RESTORE DRILL: PASS. Cloud mirror matches every live source` (0): nothing
  differs at all. Say so in one line.
- `RESTORE DRILL: PASS. Every live source restores; N file(s) differ purely as
  post-backup churn` (0): the expected result for any run more than a few
  minutes after a backup. `gmail-mirror` and `bnc-sales-watch` both write state
  on a 15-minute poll, so N is rarely zero. **This is a pass, report it as one**,
  and name N rather than listing the files.
- `RESTORE DRILL: REAL DRIFT: N file(s) would not come back as they are` (1):
  **the failing case.** The lines under it split N by cause:
  - files that predate the backup and are missing from it or still differ:
    check `backup.sh`'s include list and its rsync excludes;
  - files the backup copies but git never commits, because a project's own
    `.gitignore` applies inside the mirror (grouped by rule, so one rule
    covering thousands of files is one line);
  - copies ON GITHUB that hold a term the privacy or embedded-media filter
    should have kept off them: a privacy incident, handled before anything else.
- `RESTORE DRILL: INCOMPLETE` (2): every checked file restores, but some files
  in the mirror sit outside every check, so the pass says nothing about them.
  Teach the drill the scope they come from.
- `RESTORE DRILL: CANNOT RUN` (2): the drill could not read its copy rules out
  of `backup.sh`. Nothing was compared. Update the drill to match `backup.sh`.

A privacy or embedded-media holdback is the guard working, not a gap. The last
lines of every run count the holdbacks and the files over the size cap: those
come back only from a local backup such as Time Machine, never from the mirror.

Each difference is annotated inline with its own verdict. The clock is the
file's change time (ctime), not its modification time, because `cp -p`,
`rsync -a` and git checkouts all stamp a fresh copy with an old mtime:

- `[benign: changed HH:MM:SS, after the backup]`: changed since the mirror commit.
- `[benign: changed HH:MM:SS, while the backup was running; the next backup
  settles it]`: changed in the 15 minutes before the mirror commit, while the
  backup was still copying scope by scope.
- `[benign: deleted locally since the backup]`, and the other `benign:` labels
  for a file the mirror has and live does not (or no longer copies). Never a
  restore risk, since restoring would bring it back.
- `[REAL: last touched ..., before the backup, and still differs]`: the mirror
  is stale for this file.
- `[REAL: last touched ... and NOT IN THE MIRROR AT ALL]`: the file exists on
  the machine, predates the backup, and was never copied.
- `[REAL: never reaches GitHub]`: the `.gitignore` rule that keeps git from
  committing files the backup copies, with a count and one example.
- `[REAL: this copy ON GITHUB holds a term ...]`: a filter failed at some point.

Clone failure: check `gh auth status` and network before anything else.

The script never writes to the live sources or the stage; it works entirely in
a throwaway temp dir and removes it on exit.

## Testing the drill itself

Two overrides exist for that and nothing else. `MIRROR_CLONE=<dir>` compares
against an existing clone instead of a fresh one (the first output line then
says TEST MODE), so a deliberately damaged clone proves a missing or altered
file is caught. `BACKUP_SH=<file>` reads the rules from a copy of `backup.sh`,
so a deliberately broken copy proves the drill follows the rules it reads
rather than rules of its own. Never report a TEST MODE run as a drill result.

## Also prove the learning loop, not just the files

A restore drill proves the durable assets would come back. It says nothing about
whether the machine that keeps them current still runs. Pair it with:

```bash
bash ~/.claude/skills/self-heal/selftest.sh
```

29 checks over the self-heal chain (capture hook, both content-age gates, the
trust boundary, atomic state writes, managed-block marker balance). It restores
its own state on exit and is safe to run beside the drill. Report both results
together: a green backup with a red selftest means you are faithfully preserving
a loop that quietly stopped learning.
