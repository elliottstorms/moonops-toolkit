---
name: restore-drill
description: "Prove the backup actually restores: clone the private GitHub mirror to a temp dir and diff it against the live sources (skills, agents, bin, CLAUDE.md, settings, Toolkit, TASKS.md, memory). An untested backup is a hope, not a backup. Use when the user says 'restore drill', 'prove the backup', 'test the backup', 'would the backup actually work', or on a quarterly cadence, and after any change to backup.sh's include list or tripwire."
---

# Restore drill: prove the backup restores

Run the bundled script. It clones `your-username/your-backup-repo` fresh from
GitHub (not the local stage: the point is proving the *cloud* copy), then
`diff -rq`s every mirrored scope against its live source.

```bash
sh ~/.claude/skills/restore-drill/restore_drill.sh
```

## Reading the result

The script classifies every difference for you against the mirror commit's own
timestamp, so you no longer hand-check mtimes (added 2026-08-26 on your
ask). Three possible verdicts:

- `RESTORE DRILL: PASS. Cloud mirror matches every live source`: nothing
  differs at all. Say so in one line.
- `RESTORE DRILL: PASS. Every live source restores; N file(s) differ purely as
  post-backup churn`: the expected result for any run more than a few minutes
  after a backup. `gmail-mirror` and `bnc-sales-watch` both write state on a
  15-minute poll, so N is rarely zero. **Exit 0. This is a pass, report it as
  one**, and name N rather than listing the files.
- `RESTORE DRILL: REAL DRIFT: N file(s) predate the ... backup and still
  differ`: **the only failing case.** Exit 1. It means the mirror is missing
  content that existed before the backup ran. Check `backup.sh`'s include list
  and its rsync excludes, and remember a PII or embedded-media holdback is the
  guard working rather than a gap: read the backup log's holdback lines before
  treating a held file as a bug.

Each drift line is annotated inline with its own verdict and timestamp:

- `[benign: edited HH:MM:SS, after the backup]`: changed since the mirror commit.
- `[benign: deleted locally since the backup]`: the mirror has a file live does
  not. Never a restore risk, since restoring would bring it back.
- `[REAL: last touched ..., before the backup, and still differs]`: the mirror
  is stale for this file.
- `[REAL: last touched ... and NOT IN THE MIRROR AT ALL]`: the file exists on
  the machine, predates the backup, and was never copied.

Clone failure: check `gh auth status` and network before anything else.

The script never writes to the live sources or the stage; it works entirely in
a throwaway temp dir and removes it on exit.

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
