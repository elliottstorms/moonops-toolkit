#!/usr/bin/env python3
"""state_update.py — atomically update fields in ~/.claude/self-heal/state.json.

Why this exists: every gate in the loop (the hook's content-age cutoff, the
sweep watermark) reads state.json. Before this helper, heal passes rewrote the
file with ad-hoc inline python — a truncate-then-write that a crash mid-write
turns into corrupt JSON, silently disarming the gates. This writes to a temp
file in the same directory and os.replace()s it into place: the file is always
either the old state or the new state, never half of each.

Usage:
    state_update.py KEY=VALUE [KEY=VALUE ...]

Values: parsed as JSON when possible ("3" -> 3, '"x"' -> "x"), else kept as
string. Two conveniences:
    KEY=+N        increment existing numeric field by N   (runs=+1)
    KEY=now       current local time, ISO seconds         (last_run=now)

`proposals_open` is NEVER taken from an argument. It is derived on every run by
counting the un-Statused `## Proposal N` blocks in pending-review.md, and an
explicit proposals_open=N is ignored with a warning. Why: it is a shared counter
and passes read-modify-write it as arithmetic off a value they read minutes
earlier. On 2026-08-28 three sessions wrote to self-heal inside ten minutes and
that arithmetic broke the count twice in one afternoon, once in each direction.
Arithmetic assumes a single writer; counting the file does not.

Also debuggable on its own:
    state_update.py --count-only [pending-review.md]

Prints the resulting JSON to stdout. Exit 0 on success, 2 on any failure —
and on failure the original file is untouched.
"""

import json
import os
import re
import sys
import tempfile
from datetime import datetime

PATH = os.path.expanduser("~/.claude/self-heal/state.json")
PENDING = os.path.expanduser("~/.claude/self-heal/pending-review.md")

# THE canonical proposal counter. As of 2026-08-29 (proposal 64 option 2) the
# SessionStart banner in ~/.claude/bin/session-start.sh calls this via
# `--count-only` instead of carrying its own awk, so there is exactly one
# implementation of "is this proposal open" and state.json and the banner cannot
# print different numbers for the same file.
#
# Every rule here was a production bug in that awk first, dated in this loop's
# ledger. Do not simplify any of them away:
#   - the decided word may live in the HEADING (`## Proposal 12 — APPLIED …`)
#     (2026-07-23: missing this read every closed proposal as open forever);
#   - a `**Status:` line only closes when it names a decided outcome, so
#     `**Status: DEFERRED` correctly stays open;
#   - LAST marker wins rather than latching (2026-07-28: a proposal closed and
#     later reopened, as Proposal 17 was, read closed forever otherwise);
#   - any other `^## ` heading ends the block;
#   - prose that merely quotes another proposal's status must not self-close,
#     which is why only a line START matches.
#
# Vocabulary is one list, matched case-insensitively in BOTH positions. The old
# awk had two lists that disagreed (DECIDED was heading-only, "closed" was
# body-only) and neither contained DECLINED, the word this loop actually writes
# when you declines something. Proposal 60 escaped only because its status
# sentence happened to end in "closed" (proposal 64, 2026-08-29).
_DECIDED_WORDS = (
    "APPLIED", "DECLINED", "REJECTED", "DECIDED",
    "RESOLVED", "WITHDRAWN", "SUPERSEDED", "CLOSED",
)
_H_PROPOSAL = re.compile(r"^## Proposal ")
_H_ANY = re.compile(r"^## ")
_STATUS = re.compile(r"^\*\*Status:")
_DECIDED = re.compile("|".join(_DECIDED_WORDS), re.IGNORECASE)
# Heading matching is stricter than body matching, and has to be. A heading is a
# TITLE, so a decided word can legitimately appear in it as subject matter: this
# very rule was caught by proposal 64, whose own title is about the word DECLINED
# and which self-closed the moment the vocabulary widened. The file's convention
# is `## Proposal N — APPLIED 2026-07-28 — title`, so require the word to sit
# after a dash separator, and keep it case-sensitive on the uppercase convention
# (the old awk's comment made the same point about "undecided" colliding).
# `— PARTIALLY APPLIED` must still close, so the word need not be adjacent to the
# dash, only after one.
_DASH = re.compile(r"[—–-]")
_DECIDED_UPPER = re.compile("|".join(_DECIDED_WORDS))


def _heading_decided(line):
    m = _DASH.search(line)
    return bool(m) and bool(_DECIDED_UPPER.search(line[m.end():]))


def count_open_proposals(path=PENDING):
    """Return the number of open proposal blocks, or None if uncountable.

    None, never 0, on a missing or unreadable file: a vanished pending-review.md
    and a genuinely empty one produce the same clean zero, and writing that zero
    would silently clear the banner you reads. The caller leaves the previous
    value alone and says so.
    """
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return None

    open_count = 0
    in_block = False
    dec = False
    for line in lines:
        if _H_PROPOSAL.match(line):
            if in_block and not dec:
                open_count += 1
            in_block = True
            dec = _heading_decided(line)
        elif _H_ANY.match(line):
            if in_block and not dec:
                open_count += 1
            in_block = False
        elif in_block and _STATUS.match(line):
            dec = bool(_DECIDED.search(line))
    if in_block and not dec:
        open_count += 1
    return open_count


def main(argv):
    if argv and argv[0] == "--count-only":
        target = argv[1] if len(argv) > 1 else PENDING
        n = count_open_proposals(target)
        if n is None:
            print(f"state_update: cannot read {target}", file=sys.stderr)
            return 2
        print(n)
        return 0

    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        with open(PATH, encoding="utf-8") as f:
            state = json.load(f)
    except FileNotFoundError:
        state = {}
    except (OSError, json.JSONDecodeError) as e:
        print(f"state_update: cannot read {PATH}: {e}", file=sys.stderr)
        return 2

    for arg in argv:
        if "=" not in arg:
            print(f"state_update: not KEY=VALUE: {arg!r}", file=sys.stderr)
            return 2
        key, raw = arg.split("=", 1)
        if key == "proposals_open":
            print(
                "state_update: ignoring proposals_open="
                f"{raw}; it is derived by counting pending-review.md",
                file=sys.stderr,
            )
            continue
        if raw == "now":
            state[key] = datetime.now().replace(microsecond=0).isoformat()
        elif raw.startswith("+") and raw[1:].isdigit():
            base = state.get(key, 0)
            if not isinstance(base, (int, float)):
                print(f"state_update: cannot increment non-numeric {key!r}", file=sys.stderr)
                return 2
            state[key] = base + int(raw[1:])
        else:
            try:
                state[key] = json.loads(raw)
            except json.JSONDecodeError:
                state[key] = raw

    derived = count_open_proposals()
    if derived is None:
        print(
            f"state_update: cannot read {PENDING}; leaving proposals_open as-is",
            file=sys.stderr,
        )
    else:
        state["proposals_open"] = derived

    out = json.dumps(state, indent=2) + "\n"
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(PATH), prefix=".state.")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(out)
        os.replace(tmp, PATH)
    except OSError as e:
        print(f"state_update: write failed: {e}", file=sys.stderr)
        if tmp is not None:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        return 2

    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
