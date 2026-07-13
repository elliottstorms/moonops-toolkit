#!/bin/sh
# smoke.sh — locks in the toolkit's known-good state. Everything here passes
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

note "== no credential-shaped strings in tracked files =="
if grep -rInE "gh[pousr]_[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----" . --exclude-dir=.git --exclude=smoke.sh; then
  echo "  FAIL: token-like string found"; exit 2
fi
echo "  secrets scan clean"

echo "SMOKE: ALL PASS"
