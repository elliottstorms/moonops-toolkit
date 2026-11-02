---
name: site-check
description: 'Pre-deploy audit for the moonops.org site (or any static HTML site with a .site-check.json). Checks link integrity, nav parity across pages, OG tags, required/forbidden strings (canonical LinkedIn URL), sitemap coverage, and one-page resume. Use whenever the user says "check the site", "pre-deploy audit", "audit my links", "is the site ready to ship", or before any deploy of site HTML.'
---

# Site Check: deterministic pre-deploy audit

All checking logic lives in `site_audit.py` (same folder as this file). Your job is to
**run it, read the report, and fix only what it flags**: do not improvise extra checks
or skip flagged ones.

## Run it

```bash
python3 ~/.claude/skills/site-check/site_audit.py --repo ~/Claude/Projects/moonops
```

- `--live` also verifies the deployed site is byte-identical to local (post-deploy check).
  Its requests to the site itself identify as a monitor (`SELF_UA`), so the moonops.org
  visitor counter files them as bot traffic; external link checks keep the browser-like
  `UA`. Before 2026-09-23 each live run added one human view per page; the affected days
  are in `~/Claude/Projects/moonops/site-analytics/AUDIT_LOADS.md`.
- `--live --wait 180` polls after a push until Netlify finishes. **The command prints
  nothing while polling: run it with a Bash timeout of at least 240000ms or in the
  background; silence is normal, do not kill and retry.**
- `--offline` skips external HTTP checks (fast mode; the git pre-push hook uses this).
- `--json` for machine-readable output.
- For a *different* static site (never the moonops repo):
  `python3 ~/.claude/skills/site-check/site_audit.py --repo <other_repo> --init --site-dir <dir> --base-url <url>`
  then ask the user which exact URLs/strings must always appear (required_strings) and
  which known-bad ones must never appear (forbidden_strings), and add them to the
  generated `.site-check.json`.

## Read the result

- Exit `0` = PASS (warnings allowed) · `2` = audit failures · `3` = usage error, missing
  or invalid config. On `3`, read the printed message: it says exactly what's wrong.
- ❌ items get fixed before deploy, because they are audit failures (exit `2`) and the ship
  pipeline does not proceed on a failing audit.
- ⚠️ items: report them to the user, EXCEPT these known-accepted ones which you silently
  ignore: (a) title-length warnings on `dispatches.html` and `offerings.html`,
  (b) "bot-blocked domain" warnings for skip_domains (LinkedIn etc.). Fix warnings only
  when the user asks.

## Forbidden patterns read from another file

A config may also carry `forbidden_patterns_from` (2026-11-01). It names a file, the shell
variable in it that holds a POSIX ERE in single quotes (`NAME='a|b'`), the alternatives this
site may carry (`allow`, spelled exactly as in that file), and a file of exact, case-sensitive
phrases blanked out of each line first (`phrase_exceptions_file`). The list is read on every
run, so the audit and any other gate that reads the same list can never drift apart. It
sweeps every text file under `site_dir`, not only `.html`, and its ✅ line counts the binary
files it could not read.

- A hit is ❌, with the file and line: fix the page. Never add an `allow` entry or an
  exception phrase to get past a hit, and never remove the block. That is editing the
  contract to pass (fixing rule 3), and a hit is the guard working.
- A list it cannot read, or a pattern it cannot translate to the meaning grep gives it, exits
  `3`. On a CI runner (`CI=true`) a missing file is a ⚠️ instead, since the file lives on one
  machine; the pre-push hook still checks it there.
- ⚠️ for an `allow` entry the list no longer has, or an exception phrase that is off the site
  or holds no term: report them, since they mean the config can shrink.
- In the moonops repo it reads the public build's DENY list (`build-public-toolkit.sh`), so
  the site and the public toolkit share one term list. `tools/test_site_audit_deny.py` proves
  the translation against grep and the audit's behavior; run it after any change here.

## If something is missing (hard rules)

- **Config missing for the moonops repo → STOP.** Never run `--init` there: the config is
  the audit contract (versioned in git). Restore it: `cd ~/Claude/Projects/moonops && git checkout .site-check.json`,
  or ask the user. (`--init` refuses to overwrite an existing config without `--force`;
  never pass `--force` unless the user explicitly tells you to.)
- **`site_audit.py` missing → STOP and report.** Do not audit by hand.

## Fixing rules (non-negotiable)

1. **Minimal, targeted edits.** Fix exactly the flagged issue; never reformat or "improve"
   surrounding code.
2. **Summarize every change you make**: file, line, before → after. If you remove ANY
   nav item or content block, say so explicitly and get confirmation first.
3. **Never edit `.site-check.json` to make a failure pass** unless the user has explicitly
   approved changing the contract (e.g., they intentionally renamed a nav item), because the
   contract is the guard and a guard edited to pass protects nothing.
4. URLs are compared character-by-character against the config. The canonical LinkedIn URL
   is `linkedin.com/in/your-handle` (WITH the hyphen): verified live 2026-07-06.
5. Re-run the audit after every fix. If the same item still fails after 2 fix attempts, or
   a fix would remove content, stop and ask the user. Done = exit code 0.

## Known context

- `recommendations.html` is deliberately chromeless (no nav, no LinkedIn link): already
  exempted in the config. Don't "fix" it.
- LinkedIn/X/Instagram/Facebook block bots; the script verifies those by exact string match
  instead of HTTP. Expected, not a gap.
- Netlify post-processing is disabled (`skip_processing = true` in `netlify.toml`) so
  deploys are byte-identical to the repo. If `--live` ever MISMATCHes on an otherwise clean,
  pushed repo, someone re-enabled Asset Optimization in the Netlify UI or deployed from
  another source: report that; do not edit local files to match live.


