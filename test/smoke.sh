#!/bin/sh
# smoke.sh: locks in the toolkit's known-good state. Everything here passes
# today; a regression in any of it means a broken kit shipped to strangers'
# machines. Run from the repo root: sh test/smoke.sh
set -eu

fail=0
note() { echo "$1"; }

note "== bash -n over every shell script =="
find . -name "*.sh" -not -path "./.git/*" | while IFS= read -r f; do
  bash -n "$f" && echo "  syntax OK: $f"
done

note "== python compiles =="
find . -name "*.py" -not -path "./.git/*" | while IFS= read -r f; do
  python3 -m py_compile "$f" && echo "  compile OK: $f"
done

note "== JSON parses =="
find . -name "*.json" -not -path "./.git/*" | while IFS= read -r f; do
  python3 -m json.tool "$f" > /dev/null && echo "  JSON OK: $f"
done

note "== site auditor answers --help =="
python3 skills/site-check/site_audit.py --help > /dev/null && echo "  site_audit OK"

note "== pii scanner: help, gate direction, redact round-trip =="
python3 skills/pii-scan/pii_scan.py --help > /dev/null && echo "  pii_scan --help OK"
if python3 skills/pii-scan/pii_scan.py --mode gate test/pii/dirty.txt > /dev/null 2>&1; then
  echo "  FAIL: dirty fixture passed the gate"; exit 2
else
  echo "  gate catches dirty fixture"
fi
if python3 skills/pii-scan/pii_scan.py --mode gate test/pii/clean.txt > /dev/null 2>&1; then
  echo "  clean fixture passes"
else
  echo "  FAIL: clean fixture tripped the gate (false positive)"; exit 2
fi
if python3 skills/pii-scan/pii_scan.py --mode redact test/pii/dirty.txt 2>/dev/null \
   | python3 skills/pii-scan/pii_scan.py --mode gate --stdin > /dev/null 2>&1; then
  echo "  redaction round-trip comes back clean"
else
  echo "  FAIL: redacted output still trips the gate"; exit 2
fi

note "== pii scanner: label, escape and usage-error gaps (2026-11-01) =="
# Fixtures are built from pieces at run time, so this file holds no assignment-shaped text.
gate_on() { printf '%s\n' "$1" | python3 skills/pii-scan/pii_scan.py --mode gate --stdin > /dev/null 2>&1; }
for t in "dbPass""word=aaaaaaaa" "DB_PASS""WORD=aaaaaaaa" '{"pass''word": "aaaaaaaa"}' \
         '{"note": "paid\n4111111111111111"}' 'q=%22card%22%3A%224111111111111111%22' 'routing=%22021000021%22'; do
  if gate_on "$t"; then printf '  FAIL: the gate passed a value it must catch: %s\n' "$t"; exit 2; fi
done
echo "  password labels inside longer names and values after an escape are caught"
if ! gate_on "pass""word reset link sent"; then echo "  FAIL: prose about a password tripped the gate"; exit 2; fi
rc=0; python3 skills/pii-scan/pii_scan.py --no-such-option > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || { echo "  FAIL: a usage error exited $rc, not 3"; exit 2; }
echo "  a usage error exits 3"

note "== no credential-shaped strings in tracked files =="
if grep -rInE "gh[pousr]_[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----" . --exclude-dir=.git --exclude=smoke.sh; then
  echo "  FAIL: token-like string found"; exit 2
fi
echo "  secrets scan clean"

echo "SMOKE: ALL PASS"
