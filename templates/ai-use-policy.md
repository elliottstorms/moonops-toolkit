<!--
WHEN TO USE: Standing up AI-assistant usage in any shop that handles regulated or
sensitive data (financial institution, healthcare, gov contractor, or just a company
with customers). Fill it, get it signed, review it quarterly.
HOW TO FILL: Replace every <angle-bracket> item. Delete rows that do not apply.
This is a working template, not legal advice; have counsel or your compliance
officer review the filled version before adoption.
-->

# AI Acceptable Use Policy: <organization>

**Effective:** <YYYY-MM-DD> · **Owner:** <name, role> · **Review cadence:** <quarterly>
**Applies to:** <all staff / named teams> · **Version:** <1.0>

## 1. Purpose

AI assistants are in use here, sanctioned or not. This policy makes the sanctioned
path safer and easier than the unsanctioned one: approved tools, clear data rules,
automatic gates, and an evidence trail, so that <organization> gets the leverage
without donating <customer/member> data to a third party.

## 2. Approved tools

| Tool | Tier | Approved data classes | Account type | Notes |
|---|---|---|---|---|
| <e.g. Claude (enterprise plan)> | Sanctioned | Public, Internal | <SSO enterprise seat> | <zero-retention agreement: yes/no> |
| <e.g. Claude Code on managed laptops> | Sanctioned with gates | Public, Internal | <enterprise> | pii-gate hook required (see section 5) |
| <personal/free AI accounts> | Prohibited for work content | none | n/a | includes pasting work text into personal accounts |

## 3. Data classification

| Class | Definition | Examples | AI rule |
|---|---|---|---|
| Public | already published | site copy, press releases | any approved tool |
| Internal | non-public, non-personal | process docs, code without secrets | approved tools only |
| Sensitive | business-confidential | pricing, contracts, strategy | <named tools with retention terms> |
| Regulated PII | identifies a person | <member/customer> records, SSNs, account numbers, DOBs | never enters any AI tool; no exceptions without section 7 |

## 4. Red lines

1. No Regulated PII in any prompt, upload, or context, in any tool, on any plan.
2. No credentials (passwords, tokens, keys) in any prompt, ever.
3. No pasting AI output containing factual claims into <customer/member/regulator>
   communications without a named human verifying the claims.
4. No personal AI accounts for work content, including "just this once".

## 5. Controls (what enforces this, beyond promises)

- **Tool-call gate:** the pii-gate hook blocks PII at the moment of use.
- **Commit gate:** the pre-commit hook blocks PII from entering repositories.
- **Scheduled sweep:** <weekly> scan of <paths/systems>, report filed to
  <location>, one row per sweep in the evidence log.
- **Evidence log:** every gate block, override, and sweep is a row in
  `pii-evidence-log` (see that template). Reviewed <monthly> by <owner>.

## 6. Incident response

If PII reaches an AI tool: (1) stop, note tool, time, and data class; (2) report
to <owner> within <24h>, no blame for self-reports; (3) <owner> logs the incident,
requests deletion via <vendor process>, and assesses notification duties under
<GLBA / state law / contract>; (4) the gate or policy gap that allowed it gets a
fix, logged in the evidence log.

## 7. Exceptions

Exceptions are written, named, time-boxed, and approved by <owner>. Each one is a
row in the evidence log with its reason. Standing exceptions are a policy smell;
if one lives past <90 days>, amend the policy instead.

## 8. Attestation

Each covered person signs annually: "I have read this policy, I understand which
data classes may enter which tools, and I know the red lines."

| Name | Role | Date | Signature |
|---|---|---|---|
| | | | |
