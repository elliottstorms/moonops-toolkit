# The PII Kit

Guardrails for using AI assistants around personal data, built for shops where
"we think nobody pasted member data into a chatbot" is not an acceptable answer
to an examiner, an auditor, or a client.

Like everything in this toolkit, it was extracted from a working single-operator
setup: the private half (real names, real records) never leaves the machine, and
these are the mechanisms that enforce that. They generalize to any regulated or
privacy-serious environment: financial institutions, healthcare, gov contractors,
or a solo consultant with client files.

## The premise

AI assistants are already inside your organization, sanctioned or not. The leak
paths are not exotic. They are mundane:

1. someone pastes a customer record into a chat to "clean it up",
2. an agent reads a data directory into context while doing something unrelated,
3. a repo, site, or artifact gets published with PII in a corner nobody reread,
4. generated output (a report, a resume, a summary) embeds source PII,
5. metadata survives (docx author, EXIF, git history, HTML comments),
6. logs and transcripts quietly accumulate everything above.

Policy documents do not stop any of these. Gates on the paths do. The design
stance is the same as the rest of this toolkit: deny-by-default at the edges,
deterministic checks with exit codes, and an evidence trail for every decision.

## What is in the kit

| Piece | Where | Job |
|---|---|---|
| `pii-scan` | `skills/pii-scan/` | Deterministic scanner: SSNs, cards (Luhn), routing numbers (ABA checksum), account numbers, phones, emails, DOBs, addresses, credential-shaped strings. Three modes: report, gate, redact. |
| `pii-gate` | `skills/pii-gate/` + `bin/pii-gate-hook.sh` | The routines: a Claude Code PreToolUse hook, a git pre-commit hook, and a scheduled sweep with dated reports. |
| `pii-auditor` | `agents/pii-auditor.md` | Sweep agent for what regex cannot see: names, narrative identity, quasi-identifier bundles, metadata, git history. |
| `redaction-verifier` | `agents/redaction-verifier.md` | Adversarial single-artifact check before publishing: tries to re-identify; PASS/FAIL with the reconstruction. |
| AI use policy | `templates/ai-use-policy.md` | Fill-in acceptable-use policy: approved tools, data classes, red lines, incident response, attestation. |
| Evidence log | `templates/pii-evidence-log.md` | Append-only ledger of sweeps, blocks, overrides, and incidents. The artifact reviewers actually want. |
| Fixtures | `test/pii/` | Synthetic dirty/clean files; CI proves the gate catches and the redactor cleans on every push. |

## Threat model

| Leak path | Example | Control here |
|---|---|---|
| Paste into a tool | customer record into a chat prompt | tool-call gate (PreToolUse hook) + policy red lines |
| Agent reads data into context | assistant ingests a records dir while editing code nearby | scoped directories + sweep keeps PII out of work areas |
| Publish | PII in a pushed repo, deployed page, shared doc | pre-commit gate, `pii-auditor` sweep, `redaction-verifier` before ship |
| Generated output | a produced report embeds source PII | `redact` mode on outputs + verifier on anything outbound |
| Metadata and history | docx author field, EXIF, old git blobs | auditor checks metadata and `git log -p`; history findings rank HIGH |
| Logs and transcripts | transcripts accumulate pasted data | the gate stops PII before it enters a transcript at all |
| Vendor retention and training | prompt data retained or trained on | contractual, not technical: policy section 2 forces the tier/retention decision per tool |

## What this deliberately is not

- **Not a guarantee.** Regex plus checksums catches structured PII with low
  false positives. Unlabeled names, narrative identity, and judgment calls are
  the agents' job, and a human owns every publish decision. The scanner is the
  floor, not the ceiling.
- **Not a compliance certification.** It produces the controls and the evidence;
  mapping them to your specific obligations (GLBA Safeguards, state privacy law,
  contractual duties) is work you do with your compliance owner, using the
  policy template as the frame.
- **Not a data-loss-prevention suite.** No network appliance, no endpoint agent.
  It is the 20% that catches the 80%, wired into the exact tools where modern
  leaks start: the assistant and the repo.

## Exam readiness

If an examiner, auditor, or client due-diligence team asks about AI usage, this
kit is built so each question has a dated artifact as its answer:

| They ask | You show |
|---|---|
| "What is your AI acceptable-use policy?" | the filled, signed `ai-use-policy` |
| "How do you keep customer PII out of AI tools?" | the gate hooks in `settings.json` and `.git/hooks`, live |
| "Prove the controls run." | CI smoke test on the fixtures + dated sweep reports |
| "What have they caught?" | `block` rows in the evidence log |
| "Who can override, and how do you know it is rare?" | `override` rows, each with why and date |
| "What happens when it fails anyway?" | the incident section of the policy + `incident` rows |

## Quick start

```bash
# 1. Install the scanner and hook
cp -R skills/pii-scan ~/.claude/skills/ && cp bin/pii-gate-hook.sh ~/.claude/bin/

# 2. Wire the tool-call gate (merge the PreToolUse block from settings.example.json)

# 3. Gate a repo
cp skills/pii-gate/pre-commit.sample <repo>/.git/hooks/pre-commit && chmod +x <repo>/.git/hooks/pre-commit

# 4. Prove it works
python3 skills/pii-scan/pii_scan.py test/pii/dirty.txt   # exits 2, findings masked
python3 skills/pii-scan/pii_scan.py test/pii/clean.txt   # exits 0
```

Then fill `templates/ai-use-policy.md`, start `templates/pii-evidence-log.md`,
and schedule the weekly sweep from the `pii-gate` skill. From that point on, the
honest sentence is not "we trust people to be careful". It is "the paths PII
could take are gated, the gates are tested in CI, and here is the log."
