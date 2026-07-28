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

Prints the resulting JSON to stdout. Exit 0 on success, 2 on any failure —
and on failure the original file is untouched.
"""

import json
import os
import sys
import tempfile
from datetime import datetime

PATH = os.path.expanduser("~/.claude/self-heal/state.json")


def main(argv):
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
