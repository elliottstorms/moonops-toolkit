---
name: ship-site
description: End-to-end ship pipeline for moonops.org — audit, fix, commit, push, then verify the live deploy is byte-identical and every check passes. Use when the user says "ship the site", "deploy my changes", "push the site live", or after finishing site edits in ~/Claude/Projects/moonops/site/.
---

# Ship Site — audit → push → verify live

moonops.org auto-deploys from GitHub: pushing `main` deploys (Netlify project
`your-netlify-project`, publish dir `site/`, config in root `netlify.toml`,
post-processing disabled so live bytes == repo bytes). Follow the steps in order;
each has a hard gate.

**Ship scope:** only `site/`, `netlify.toml`, and `.site-check.json` ship to the website.
Never `git add` paths outside them during this pipeline; if other paths have changes
(moonops-rain/ etc.), mention in one line that they exist and are not shipping.

## Step 0 — Pre-flight drift check (before editing anything)

```bash
python3 ~/.claude/skills/site-check/site_audit.py --repo ~/Claude/Projects/moonops --live
```

If this MISMATCHes while the repo is clean and pushed, the live site has drifted from the
repo (someone re-enabled Netlify Asset Optimization, or deployed from another source).
STOP and tell the user — do not proceed, do not edit local files to match live.

## Step 1 — Snapshot what will ship

```bash
cd ~/Claude/Projects/moonops
git status --short -- site/ netlify.toml .site-check.json
git diff HEAD --stat -- site/ netlify.toml .site-check.json
git log --oneline origin/main..main
```

Tell the user in one short list what is about to ship: changed in-scope files (one line
each on what changed) AND any already-committed-but-unpushed commits (those ship too).
If anything in scope was NOT work they asked for, stop and ask.

## Step 2 — Local audit (gate: exit code 0)

```bash
python3 ~/.claude/skills/site-check/site_audit.py --repo ~/Claude/Projects/moonops
```

- ❌ failures → fix per the `site-check` skill rules (minimal edits, summarize every change,
  never silence a failure via `.site-check.json` without user approval), re-run.
- If the same item still fails after 2 fix attempts, or a fix would remove content, stop
  and ask the user. Do not proceed on a failing audit. No exceptions.

## Step 3 — Commit + push (this deploys)

```bash
cd ~/Claude/Projects/moonops
git add <the specific in-scope files>     # never 'git add .'
git commit -m "Site: <what changed>"      # append the standard Co-Authored-By trailer
git push
```

- Working tree clean but commits ahead of origin (from Step 1)? Skip add/commit, just push.
- The pre-push hook re-runs the audit offline and blocks failing pushes. If it blocks:
  read its output (same audit), fix, push again. Never use `--no-verify` unless the user
  explicitly says so.

## Step 4 — Verify the live deploy (gate: IN SYNC)

```bash
python3 ~/.claude/skills/site-check/site_audit.py --repo ~/Claude/Projects/moonops --live --wait 180
```

**Run with a Bash timeout of at least 240000ms (or in the background). The command prints
nothing until polling finishes — silence is normal, do not kill and retry.**

PASS + "live: IN SYNC" = proven shipped. On MISMATCH after the wait:
- Check the deploy state: open https://app.netlify.com/projects/your-netlify-project/deploys
  (give the user this link), or use the Netlify MCP deploy reader if connected.
- If live content looks like an older or differently-formatted revision: the Netlify site
  is not building from origin/main, or post-processing was re-enabled. Report to the user;
  do not retry blindly; do not edit local files to match live.
- Network sanity: `curl -sI https://www.moonops.org` — any response means the network is fine.

## Step 5 — Report

Give the user: what shipped (Step 1 list), audit result, live-parity result, commit hash.
Rollback if ever needed: tell the user to open Netlify → Deploys → pick the previous
deploy → "Publish deploy" (one click, instant).

## Failure playbook

| Symptom | Do |
|---|---|
| Step 0 MISMATCH on clean repo | STOP; live has drifted; report to user |
| Audit fails locally | Fix flagged items only; 2 attempts max per item, then ask |
| `git commit` says nothing to commit | Tree was clean; push the already-committed work (Step 1 showed it) |
| Push rejected by hook | Read hook output (same audit); fix and retry |
| Live MISMATCH after wait | Netlify deploys page (link above); report, don't retry blindly |
| Live fetch errors | `curl -sI https://www.moonops.org`; check https://www.netlifystatus.com; report |
| Deploy fails "unrecognized Git contributor" | your GitHub isn't linked as a Netlify Git Contributor (free-plan rule for private repos). Only the account owner can fix it: https://app.netlify.com/teams/YOUR_TEAM/contributors → Edit settings → GitHub Connect (OAuth popup). Retrying without that fix is pointless — even UI-triggered builds fail. |

## Reverse-loop: log to STATUS.md

Final step, and only after Step 4's live-parity gate reported **IN SYNC** (byte-parity verified). Never log before that verification. Append one line to `~/Claude/STATUS.md` so the daily Cowork sync can auto-close the matching TASKS.md item; use the pushed commit's SHA. If `~/.claude/bin/status-append.sh` is missing, skip this silently.

```bash
[ -f ~/.claude/bin/status-append.sh ] && \
  sh ~/.claude/bin/status-append.sh code site-ship "<one-line what shipped>" "<commit sha>" yes
```

If Step 4 MISMATCHed or the pipeline stopped earlier, do not log.

