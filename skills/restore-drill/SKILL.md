---
name: restore-drill
description: "Prove the backup actually restores: clone the private GitHub mirror to a temp dir and diff it against the live sources (skills, agents, bin, CLAUDE.md, settings, Toolkit, TASKS.md, memory). An untested backup is a hope, not a backup. Use when the user says 'restore drill', 'prove the backup', 'test the backup', 'would the backup actually work', or on a quarterly cadence — and after any change to backup.sh's include list or tripwire."
---

# Restore drill — prove the backup restores

Run the bundled script. It clones `your-username/your-backup-repo` fresh from
GitHub (not the local stage — the point is proving the *cloud* copy), then
`diff -rq`s every mirrored scope against its live source.

```bash
sh ~/.claude/skills/restore-drill/restore_drill.sh
```

## Reading the result

- `RESTORE DRILL: PASS` — every scope matches; the cloud copy would rebuild
  your machine's durable assets byte-for-byte. Say so in one line.
- `drift:` lines — files that differ between live and the cloud mirror. This is
  NORMAL for anything edited since the last 17:30 backup; check the timestamps
  it prints. Only flag drift as a problem when a file changed BEFORE the last
  backup ran and still differs (that means the mirror is missing something —
  check backup.sh's include list and rsync excludes).
- Clone failure — check `gh auth status` and network before anything else.

The script never writes to the live sources or the stage; it works entirely in
a throwaway temp dir and removes it on exit.

## Also prove the learning loop, not just the files

A restore drill proves the durable assets would come back. It says nothing about
whether the machine that keeps them current still runs. Pair it with:

```bash
bash ~/.claude/skills/self-heal/selftest.sh
```

26 checks over the self-heal chain (capture hook, both content-age gates, the
trust boundary, atomic state writes, managed-block marker balance). It restores
its own state on exit and is safe to run beside the drill. Report both results
together: a green backup with a red selftest means you are faithfully preserving
a loop that quietly stopped learning.
