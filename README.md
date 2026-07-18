# MoonOps Toolkit

A reusable toolkit for running an AI operator setup on top of [Claude Code](https://docs.claude.com/en/docs/claude-code) — the sub-agents, hooks, skills, templates, and design system that make a single-person operation run like a team.

Everything here is deliberately generic. It was extracted from a working personal setup, with all private context (tasks, contacts, finances, personal profile, credentials) removed. Drop the pieces you want into your own `~/.claude/` and adapt them.

## What's inside

| Folder | What it is |
|---|---|
| `agents/` | Seven focused sub-agents: `researcher`, `builder`, `reviewer`, `verifier`, `brand-guardian`, `pii-auditor`, and `redaction-verifier`. Each has one job and a strict output contract. |
| `bin/` | Claude Code hook scripts — em-dash checks on public copy, a static-site link check, a PII gate on tool calls, a session-start orientation printout, a durable-asset backup nudge, and a GitHub MCP launcher that reads its token from the `gh` keychain at runtime (no secret on disk). |
| `skills/` | Reusable skills: `site-check` (offline static-site audit), `ship-site` (audit → commit → push → verify), `handoff` / `run-handoff` (pass in-flight work between sessions), `backup` (mirror durable assets to a private repo with a secrets tripwire), `audiocast` (text to clean offline mp3), and the PII kit: `pii-scan` (deterministic scanner with checksum validation) and `pii-gate` (hook, pre-commit, and sweep routines). |
| `design-system/` | The MoonOps design tokens, palette, a living component demo, and the brand rulebook. A real, working example of a small dark-mode design system. |
| `templates/` | Fill-in-the-blank templates: decision memo, dispatch request, market research, premortem, verification checklist, weekly review. |
| `backup/` | A reference `backup.sh` that mirrors your assets to a private GitHub repo and refuses to commit anything credential-shaped. |
| `settings.example.json` | Example Claude Code hook wiring. |
| `CLAUDE.template.md` | A blank operator-manual template — the structure of a good `CLAUDE.md`, with none of the personal content. |

## The PII kit

The newest family: guardrails for using AI assistants around personal data in
regulated or privacy-serious environments. A checksum-validating scanner, gates
on the tool-call and commit paths, two adversarial review agents, and policy +
evidence-log templates, with CI proving the gate catches on every push.
[PII.md](PII.md) has the threat model and the exam-readiness mapping.

## Design principles

1. **The intelligence lives in scripts and contracts, not the model.** Every check is a script with an exit code, so it runs the same on any model tier.
2. **Deny-by-default on anything that ships publicly.** The backup and publish patterns use an explicit allowlist plus a fail-closed secrets tripwire.
3. **Verify external effects.** "The tool returned success" is a claim, not a verification — the `verifier` agent and the verification-checklist template exist to enforce that.
4. **Read before you write; report every change.** The `builder` agent never makes a silent edit.

## Using it

1. Copy the folders you want into `~/.claude/` (agents → `~/.claude/agents/`, hooks → `~/.claude/bin/`, skills → `~/.claude/skills/`).
2. Wire the hooks by merging `settings.example.json` into your `~/.claude/settings.json` and fixing the absolute paths for your machine.
3. Copy `CLAUDE.template.md` to `~/.claude/CLAUDE.md` and fill it in.
4. Adapt the `backup/` script: set your own private backup repo, then schedule it.

## What's intentionally not here

Personal profile, task lists, contacts, financial data, job-search materials, and anything credential-shaped. This repo is generated from a private source through an allowlist and a secrets/PII tripwire; the private half never leaves the machine.

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, adapt it.
