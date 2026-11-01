---
name: pii-scan
description: 'Deterministic PII scanner for files, directories, or stdin. Finds SSNs, card numbers (Luhn-validated), ABA routing numbers (checksum-validated), account/member numbers, phones, emails, DOBs, addresses, and credential-shaped strings, with masked excerpts and clean exit codes. Use before anything leaves the machine (commit, publish, upload, paste), when the user says "scan this for PII", "is this safe to share", "redact this", or as the engine behind the pii-gate hooks.'
---

# PII Scan: deterministic scanner, three modes

All detection logic lives in `pii_scan.py` (same folder as this file). Your job is to
run it, read the report, and act on what it flags. Do not eyeball files for PII when
the scanner can look first; do not overrule a finding without adding an auditable
allowlist entry.

## Run it

```bash
# Report: human-readable findings, masked excerpts
python3 ~/.claude/skills/pii-scan/pii_scan.py path/to/dir

# Gate: quiet pass/fail for hooks and CI
python3 ~/.claude/skills/pii-scan/pii_scan.py --mode gate file.md

# Redact: emit a copy with [PII:TYPE] tags in place of findings
python3 ~/.claude/skills/pii-scan/pii_scan.py --mode redact file.md > file.public.md
```

- Exit `0` = clean, `2` = findings at or above the `--fail-on` threshold
  (default `medium`), `3` = usage or config error, or a path that was not
  scanned (missing, binary, over `max_bytes`, unreadable). Each unscanned path
  is named on stderr, and findings still exit `2`. Treat `3` as a block, never
  as a pass.
- `--stdin` scans a stream, `--json` emits machine-readable findings,
  `--show` prints raw values instead of masked excerpts (use sparingly),
  `--write` (redact mode) writes `<file>.redacted` siblings.

## Validation, not vibes

A 9-digit number is only reported as a routing number if it passes the ABA
checksum and has a valid Federal Reserve prefix. Card candidates must pass
Luhn plus an issuer-prefix check. SSNs must be structurally valid (no 000/666
area, no 00 group, no 0000 serial). This is what keeps the false-positive rate
low enough that people actually leave the gate turned on.

## Config: `.pii-scan.json`

A path scan reads a config only when you pass one with `--config <path>`. It
never picks up a `.pii-scan.json` on its own, because a file inside the tree
being scanned could otherwise configure its own gate. A `--stdin` scan (the
hooks) also reads `./.pii-scan.json` from the working directory. See
`pii-scan.example.json` next to this file.

- `allowlist`: exact strings that are known-safe. Entries can be plain strings
  or `{"value", "why", "added"}` objects; use the object form so every
  exception is self-documenting.
- `allowlist_patterns`: regexes for known-safe families (e.g. your own
  published contact email).
- `custom_patterns`: institution-specific formats (member-number layouts,
  internal ticket IDs) with a name and confidence. Every pattern, these
  included, reads a curly apostrophe (U+2018, U+2019 or U+02BC) as a straight
  one, so spell an apostrophe in a pattern as `'`.
- `fail_on`: default threshold (`low` | `medium` | `high`).
- `exclude_paths`: regex fragments for paths to skip on purpose. An excluded
  path is not reported, so this is also where you acknowledge, by name, a file
  the scanner cannot read (an image, say) instead of letting it exit `3`.
- `max_bytes`: the largest file the scanner reads (default 2 MiB). A bigger
  file is named as not scanned.

## Honest limits

Regex catches structured PII. It does not catch unlabeled names, narrative
identity ("the branch manager in the story"), quasi-identifier combinations,
faces, or audio. For those, send the file to the `pii-auditor` agent, and send
anything about to be published to `redaction-verifier`. The scanner is the
floor, not the ceiling.
