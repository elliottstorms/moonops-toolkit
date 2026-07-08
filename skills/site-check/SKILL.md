---
name: site-check
description: Pre-deploy audit for the moonops.org site (or any static HTML site with a .site-check.json). Checks link integrity, nav parity across pages, OG tags, required/forbidden strings (canonical LinkedIn URL), sitemap coverage, and one-page resume. Use whenever the user says "check the site", "pre-deploy audit", "audit my links", "is the site ready to ship", or before any deploy of site HTML.
---

# Site Check — deterministic pre-deploy audit

All checking logic lives in `site_audit.py` (same folder as this file). Your job is to
**run it, read the report, and fix only what it flags** — do not improvise extra checks
or skip flagged ones.

## Run it

```bash
python3 ~/.claude/skills/site-check/site_audit.py --repo ~/Claude/Projects/moonops
```

- `--live` also verifies the deployed site is byte-identical to local (post-deploy check).
- `--live --wait 180` polls after a push until Netlify finishes. **The command prints
  nothing while polling — run it with a Bash timeout of at least 240000ms or in the
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
  or invalid config. On `3`, read the printed message — it says exactly what's wrong.
- ❌ items MUST be fixed before deploy.
- ⚠️ items: report them to the user, EXCEPT these known-accepted ones which you silently
  ignore: (a) title-length warnings on `dispatches.html` and `offerings.html`,
  (b) "bot-blocked domain" warnings for skip_domains (LinkedIn etc.). Fix warnings only
  when the user asks.

## If something is missing (hard rules)

- **Config missing for the moonops repo → STOP.** Never run `--init` there: the config is
  the audit contract (versioned in git). Restore it: `cd ~/Claude/Projects/moonops && git checkout .site-check.json`,
  or ask the user. (`--init` refuses to overwrite an existing config without `--force`;
  never pass `--force` unless the user explicitly tells you to.)
- **`site_audit.py` missing → STOP and report.** Do not audit by hand.

## Fixing rules (non-negotiable)

1. **Minimal, targeted edits.** Fix exactly the flagged issue; never reformat or "improve"
   surrounding code.
2. **Summarize every change you make** — file, line, before → after. If you remove ANY
   nav item or content block, say so explicitly and get confirmation first.
3. **Never edit `.site-check.json` to make a failure pass** unless the user has explicitly
   approved changing the contract (e.g., they intentionally renamed a nav item).
4. URLs are compared character-by-character against the config. The canonical LinkedIn URL
   is `linkedin.com/in/your-handle` (WITH the hyphen) — verified live 2026-07-06.
5. Re-run the audit after every fix. If the same item still fails after 2 fix attempts, or
   a fix would remove content, stop and ask the user. Done = exit code 0.

## Known context

- `recommendations.html` is deliberately chromeless (no nav, no LinkedIn link) — already
  exempted in the config. Don't "fix" it.
- LinkedIn/X/Instagram/Facebook block bots; the script verifies those by exact string match
  instead of HTTP. Expected, not a gap.
- Netlify post-processing is disabled (`skip_processing = true` in `netlify.toml`) so
  deploys are byte-identical to the repo. If `--live` ever MISMATCHes on an otherwise clean,
  pushed repo, someone re-enabled Asset Optimization in the Netlify UI or deployed from
  another source — report that; do not edit local files to match live.
