#!/usr/bin/env python3
"""pii_scan.py - deterministic PII scanner for text files and streams.

Finds structured PII (SSNs, card numbers, routing numbers, phones, emails,
DOBs, account numbers, addresses, credential-shaped strings) with checksum
and structural validation to keep false positives down. Stdlib only.

Modes:
  report  (default) print findings with masked excerpts; exit 2 if any
          finding meets the --fail-on threshold, else 0
  gate    quiet pass/fail for hooks and CI; one-line summary on stderr
  redact  print the input with findings replaced by [PII:TYPE] tags

Exit codes: 0 clean, 2 findings at/above threshold, 3 usage/config error.
(Same contract as site_audit.py: scripts decide, models obey.)

What this cannot catch: unlabeled names, narrative PII in prose, faces,
audio. That is what the pii-auditor and redaction-verifier agents are for.
"""

import argparse
import json
import os
import re
import sys

CONF_ORDER = {"low": 1, "medium": 2, "high": 3}
DEFAULT_MAX_BYTES = 2 * 1024 * 1024
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".next", "dist"}
KEYWORD_WINDOW = 48

# ---------------------------------------------------------------- validators

def luhn_ok(digits):
    total = 0
    for i, ch in enumerate(reversed(digits)):
        d = int(ch)
        if i % 2 == 1:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return total % 10 == 0


def iin_ok(d):
    """Card number starts with a plausible issuer prefix."""
    return (
        d[0] == "4"
        or 51 <= int(d[:2]) <= 55
        or 2221 <= int(d[:4]) <= 2720
        or d[:2] in ("34", "37")
        or d[:4] == "6011"
        or d[:2] == "65"
        or 644 <= int(d[:3]) <= 649
        or d[:2] == "35"
    )


def aba_ok(d):
    """ABA routing number: checksum plus a valid Federal Reserve prefix."""
    if len(d) != 9:
        return False
    n = [int(c) for c in d]
    if (3 * (n[0] + n[3] + n[6]) + 7 * (n[1] + n[4] + n[7]) + (n[2] + n[5] + n[8])) % 10 != 0:
        return False
    p = int(d[:2])
    return p <= 12 or 21 <= p <= 32 or 61 <= p <= 72 or p == 80


def ssn_ok(area, group, serial):
    a, g, s = int(area), int(group), int(serial)
    return a not in (0, 666) and a < 900 and g != 0 and s != 0


def near_keyword(text, start, end, keywords):
    lo = max(0, start - KEYWORD_WINDOW)
    window = text[lo:end + 16].lower()
    return any(k in window for k in keywords)

# ---------------------------------------------------------------- detectors
# Each: (type, confidence, priority, compiled regex, check(match, text) -> bool)
# priority breaks ties when spans overlap: validated types beat keyword types.

MONTHS = r"(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*"

DETECTORS = [
    ("ssn", "high", 9,
     re.compile(r"(?<!\d)(\d{3})-(\d{2})-(\d{4})(?!\d)"),
     lambda m, t: ssn_ok(m.group(1), m.group(2), m.group(3))),

    ("ssn-bare", "medium", 6,
     re.compile(r"(?<![\d.\-])\d{9}(?![\d.\-])"),
     lambda m, t: near_keyword(t, m.start(), m.end(), ("ssn", "social security"))
     and ssn_ok(m.group(0)[:3], m.group(0)[3:5], m.group(0)[5:])),

    ("card", "high", 9,
     re.compile(r"(?<![\dA-Za-z])(?:\d[ \-]?){12,18}\d(?![\dA-Za-z])"),
     lambda m, t: 13 <= len(re.sub(r"\D", "", m.group(0))) <= 19
     and luhn_ok(re.sub(r"\D", "", m.group(0)))
     and iin_ok(re.sub(r"\D", "", m.group(0)))),

    ("routing", "high", 8,
     re.compile(r"(?<![\d.\-])\d{9}(?![\d.\-])"),
     lambda m, t: aba_ok(m.group(0))
     and near_keyword(t, m.start(), m.end(), ("routing", "aba", "wire", "ach"))),

    ("routing-candidate", "medium", 5,
     re.compile(r"(?<![\d.\-])\d{9}(?![\d.\-])"),
     lambda m, t: aba_ok(m.group(0))
     and not near_keyword(t, m.start(), m.end(), ("routing", "aba", "wire", "ach"))),

    ("account-number", "high", 7,
     re.compile(r"\b(?:account|acct|member|loan|card|iban)\s*(?:no|num|number|id)?\.?\s*[:#]?\s*(\d[\d \-]{4,18}\d)", re.I),
     lambda m, t: True),

    ("dob", "high", 7,
     re.compile(r"\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b|\b(?:19|20)\d{2}-\d{2}-\d{2}\b|\b" + MONTHS + r" \d{1,2},? \d{4}\b", re.I),
     lambda m, t: near_keyword(t, m.start(), m.end(), ("dob", "date of birth", "born", "birthdate", "birthday"))),

    ("phone-us", "medium", 5,
     re.compile(r"(?<!\d)(?:\+1[ .\-]?)?\(?([2-9]\d{2})\)?[ .\-]([2-9]\d{2})[ .\-](\d{4})(?!\d)"),
     lambda m, t: True),

    ("email", "medium", 5,
     re.compile(r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"),
     lambda m, t: True),

    ("street-address", "low", 3,
     re.compile(r"\b\d{1,6}\s+(?:[A-Z][A-Za-z'.]+\s+){1,3}(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Circle|Cir|Place|Pl|Way|Terrace|Ter|Parkway|Pkwy|Highway|Hwy)\b\.?"),
     lambda m, t: True),

    ("ip-address", "low", 3,
     re.compile(r"\b(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\b"),
     lambda m, t: not m.group(0).startswith(("10.", "127.", "192.168.", "0."))),

    ("id-document", "medium", 5,
     re.compile(r"\b(?:passport|driver'?s?\s+licen[cs]e|dl)\s*(?:no|num, number|id)?\.?\s*[:#]?\s*([A-Z0-9][A-Z0-9\-]{4,14})\b", re.I),
     lambda m, t: True),
]

# Credential-shaped strings. Patterns are concatenated so this file never
# contains a token-shaped literal that trips a secrets grep.
CREDENTIAL_PATTERNS = [
    ("aws-access-key", "AKIA" + r"[0-9A-Z]{16}"),
    ("github-token", r"gh[pousr]_" + r"[A-Za-z0-9]{20,}"),
    ("slack-token", r"xox[baprs]-" + r"[A-Za-z0-9\-]{10,}"),
    ("anthropic-key", r"sk-ant-" + r"[A-Za-z0-9\-]{20,}"),
    ("private-key", "-----BEGIN " + r"[A-Z ]*" + "PRIVATE KEY-----"),
    ("password-assignment", r"(?i)\bpassword\s*[:=]\s*\S{6,}"),
]
for _name, _pat in CREDENTIAL_PATTERNS:
    DETECTORS.append((_name, "high", 9, re.compile(_pat), lambda m, t: True))

# ------------------------------------------------------------------- config

def load_config(path, explicit):
    cfg = {"allowlist": [], "allowlist_patterns": [], "custom_patterns": [],
           "exclude_paths": [], "max_bytes": DEFAULT_MAX_BYTES, "fail_on": "medium"}
    if path is None:
        return cfg, None
    try:
        with open(path, "r", encoding="utf-8") as f:
            raw = json.load(f)
    except FileNotFoundError:
        if explicit:
            print("pii_scan: config not found: %s" % path, file=sys.stderr)
            sys.exit(3)
        return cfg, None
    except (json.JSONDecodeError, OSError) as e:
        print("pii_scan: bad config %s: %s" % (path, e), file=sys.stderr)
        sys.exit(3)
    for k in cfg:
        if k in raw:
            cfg[k] = raw[k]
    return cfg, os.path.abspath(path)


def allow_values(cfg):
    """Allowlist entries may be plain strings or {value, why, added} objects."""
    vals = []
    for entry in cfg.get("allowlist", []):
        vals.append(entry["value"] if isinstance(entry, dict) else entry)
    return vals


def compile_custom(cfg):
    out = []
    for c in cfg.get("custom_patterns", []):
        try:
            rx = re.compile(c["pattern"])
        except (re.error, KeyError, TypeError) as e:
            print("pii_scan: bad custom pattern %r: %s" % (c, e), file=sys.stderr)
            sys.exit(3)
        conf = c.get("confidence", "medium")
        if conf not in CONF_ORDER:
            print("pii_scan: bad confidence %r (low|medium|high)" % conf, file=sys.stderr)
            sys.exit(3)
        out.append((c.get("name", "custom"), conf, 6, rx, lambda m, t: True))
    return out

# ------------------------------------------------------------------ masking

def mask(kind, s):
    if kind == "email":
        local, _, domain = s.partition("@")
        return (local[:1] + "***@" + domain) if domain else "***"
    if kind in ("dob", "street-address"):
        return re.sub(r"\d", "*", s)
    if kind in ("aws-access-key", "github-token", "slack-token", "anthropic-key",
                "private-key", "password-assignment"):
        return s[:6] + "..."
    digits = sum(c.isdigit() for c in s)
    if digits >= 4:
        out, keep = [], 4
        for c in reversed(s):
            if c.isdigit():
                if keep > 0:
                    out.append(c)
                    keep -= 1
                else:
                    out.append("*")
            else:
                out.append(c)
        return "".join(reversed(out))
    return s[:2] + "..." if len(s) > 8 else "***"

# ----------------------------------------------------------------- scanning

def scan_text(text, detectors, allow, allow_rx):
    raw = []
    for kind, conf, prio, rx, check in detectors:
        for m in rx.finditer(text):
            val = m.group(0)
            if val in allow:
                continue
            if any(a.search(val) for a in allow_rx):
                continue
            try:
                if not check(m, text):
                    continue
            except (ValueError, IndexError):
                continue
            raw.append((m.start(), m.end(), kind, conf, prio, val))
    # Higher-priority detectors claim their spans first (a Luhn-validated card
    # beats a keyword match that happens to overlap it), then report in
    # document order.
    raw.sort(key=lambda f: (-f[4], -CONF_ORDER[f[3]], f[0], -(f[1] - f[0])))
    kept = []
    for f in raw:
        if any(f[0] < k[1] and k[0] < f[1] for k in kept):
            continue
        kept.append(f)
    kept.sort(key=lambda f: f[0])
    return kept


def line_col(text, offset):
    line = text.count("\n", 0, offset) + 1
    col = offset - (text.rfind("\n", 0, offset) + 1) + 1
    return line, col


def iter_files(paths, cfg, cfg_path):
    skipped_big = []
    for root_path in paths:
        if os.path.isfile(root_path):
            candidates = [root_path]
        else:
            candidates = []
            for dirpath, dirnames, filenames in os.walk(root_path):
                dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
                candidates.extend(os.path.join(dirpath, f) for f in sorted(filenames))
        for p in candidates:
            ap = os.path.abspath(p)
            if cfg_path and ap == cfg_path:
                continue
            if p.endswith(".redacted"):
                continue
            if any(re.search(g, p) for g in cfg.get("exclude_paths", [])):
                continue
            try:
                size = os.path.getsize(p)
                if size > cfg.get("max_bytes", DEFAULT_MAX_BYTES):
                    skipped_big.append(p)
                    continue
                with open(p, "rb") as fh:
                    head = fh.read(8192)
                    if b"\0" in head:
                        continue
                    data = head + fh.read()
            except OSError:
                continue
            yield p, data.decode("utf-8", errors="replace")
    if skipped_big:
        print("pii_scan: skipped %d file(s) over max_bytes (not scanned): %s"
              % (len(skipped_big), ", ".join(skipped_big)), file=sys.stderr)

# --------------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Deterministic PII scanner. Exit 0 clean, 2 findings, 3 usage error.")
    ap.add_argument("paths", nargs="*", help="files or directories to scan")
    ap.add_argument("--mode", choices=("report", "gate", "redact"), default="report")
    ap.add_argument("--stdin", action="store_true", help="read stdin instead of paths")
    ap.add_argument("--config", default=None, help="path to .pii-scan.json")
    ap.add_argument("--fail-on", choices=("low", "medium", "high"), default=None,
                    help="minimum confidence that fails the scan (default: config or medium)")
    ap.add_argument("--json", action="store_true", help="machine-readable report output")
    ap.add_argument("--show", action="store_true",
                    help="print raw matched values instead of masked excerpts")
    ap.add_argument("--write", action="store_true",
                    help="redact mode: write <file>.redacted next to each input")
    args = ap.parse_args(argv)

    explicit = args.config is not None
    cfg_file = args.config if explicit else (
        ".pii-scan.json" if os.path.exists(".pii-scan.json") else None)
    cfg, cfg_path = load_config(cfg_file, explicit)
    fail_on = args.fail_on or cfg.get("fail_on", "medium")
    if fail_on not in CONF_ORDER:
        print("pii_scan: bad fail_on %r" % fail_on, file=sys.stderr)
        sys.exit(3)
    threshold = CONF_ORDER[fail_on]

    detectors = DETECTORS + compile_custom(cfg)
    allow = set(allow_values(cfg))
    try:
        allow_rx = [re.compile(p) for p in cfg.get("allowlist_patterns", [])]
    except re.error as e:
        print("pii_scan: bad allowlist_pattern: %s" % e, file=sys.stderr)
        sys.exit(3)

    if args.stdin:
        sources = [("<stdin>", sys.stdin.read())]
    elif args.paths:
        sources = list(iter_files(args.paths, cfg, cfg_path))
    else:
        ap.print_help()
        sys.exit(3)

    all_findings = []
    redactions = {}
    for path, text in sources:
        found = scan_text(text, detectors, allow, allow_rx)
        for start, end, kind, conf, _prio, val in found:
            line, col = line_col(text, start)
            all_findings.append({
                "path": path, "line": line, "col": col, "type": kind,
                "confidence": conf,
                "excerpt": val if args.show else mask(kind, val),
            })
        if args.mode == "redact":
            out, last = [], 0
            for start, end, kind, _c, _p, _v in found:
                out.append(text[last:start])
                out.append("[PII:%s]" % kind.upper())
                last = end
            out.append(text[last:])
            redactions[path] = "".join(out)

    failing = [f for f in all_findings if CONF_ORDER[f["confidence"]] >= threshold]
    counts = {c: sum(1 for f in all_findings if f["confidence"] == c)
              for c in ("high", "medium", "low")}

    if args.mode == "redact":
        if args.write and not args.stdin:
            for path, text in redactions.items():
                with open(path + ".redacted", "w", encoding="utf-8") as f:
                    f.write(text)
                print("wrote %s.redacted" % path, file=sys.stderr)
        else:
            for text in redactions.values():
                sys.stdout.write(text)
        return 0

    if args.mode == "gate":
        if failing:
            kinds = ", ".join(sorted({f["type"] for f in failing}))
            print("PII gate: BLOCKED. %d finding(s) at/above %s (%s). "
                  "Run --mode report for detail." % (len(failing), fail_on, kinds),
                  file=sys.stderr)
            return 2
        return 0

    if args.json:
        print(json.dumps({"findings": all_findings, "counts": counts,
                          "fail_on": fail_on, "failing": len(failing)}, indent=2))
    else:
        current = None
        for f in all_findings:
            if f["path"] != current:
                current = f["path"]
                print(current)
            print("  %4d:%-4d %-6s %-18s %s"
                  % (f["line"], f["col"], f["confidence"].upper(), f["type"], f["excerpt"]))
        print("SUMMARY: %d finding(s) (%d high, %d medium, %d low), %d at/above %s"
              % (len(all_findings), counts["high"], counts["medium"], counts["low"],
                 len(failing), fail_on))
    return 2 if failing else 0


if __name__ == "__main__":
    sys.exit(main())
