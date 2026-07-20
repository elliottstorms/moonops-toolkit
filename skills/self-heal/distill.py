#!/usr/bin/env python3
"""distill.py — compress a Claude session transcript (JSONL) into a compact
learning digest for the self-heal loop.

Design constraints (why this script is shaped the way it is):
- ONLY your own words count as preference signal. Assistant text and
  tool_result content are excluded entirely: they are where prompt-injection
  from web pages / tool output would live, and they dwarf user text in size.
- <system-reminder> spans inside user messages are harness noise (injected
  CLAUDE.md, hook output), not the user — stripped.
- Sidechain (subagent) and meta lines are not the user either — skipped.
- Slash-command invocations are kept as one-line markers: which skills she
  reaches for, and with what arguments, is itself a signal.
- Output is hard-capped so a heal pass over several sessions stays cheap.

Exit codes: 0 = digest on stdout, 3 = gated/skip (not an error), 2 = failure.
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime

SYSTEM_REMINDER_RE = re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL)
COMMAND_NAME_RE = re.compile(r"<command-name>(.*?)</command-name>", re.DOTALL)
COMMAND_MSG_RE = re.compile(r"<command-message>.*?</command-message>", re.DOTALL)
COMMAND_ARGS_RE = re.compile(r"<command-args>(.*?)</command-args>", re.DOTALL)
# Harness-injected spans that arrive as user-role lines but are not the user:
# background-task completion notices and local command stdout echoes.
HARNESS_NOISE_RE = re.compile(
    r"<task-notification>.*?</task-notification>|<local-command-stdout>.*?</local-command-stdout>",
    re.DOTALL,
)


def clean(text):
    text = SYSTEM_REMINDER_RE.sub("", text)
    text = HARNESS_NOISE_RE.sub("", text)
    return text.strip()


def shorten(text, cap):
    if len(text) <= cap:
        return text
    head = text[: max(cap - 300, 200)]
    tail = text[-200:]
    return f"{head}\n…[truncated {len(text) - len(head) - len(tail)} chars]…\n{tail}"


def parse_user_turn(obj):
    """Return (kind, text) for a user line, or None if it isn't real user input.
    kind is 'typed' | 'command' | 'note'."""
    msg = obj.get("message") or {}
    content = msg.get("content")

    if isinstance(content, str):
        cmd = COMMAND_NAME_RE.search(content)
        if cmd:
            args = COMMAND_ARGS_RE.search(content)
            arg_txt = clean(args.group(1))[:200] if args else ""
            name = cmd.group(1).strip()
            return ("command", f"invoked {name}" + (f" — args: {arg_txt}" if arg_txt else ""))
        text = clean(content)
        return ("typed", text) if text else None

    if isinstance(content, list):
        parts, attachments = [], 0
        for block in content:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "text":
                t = clean(block.get("text") or "")
                if t:
                    parts.append(t)
            elif btype == "image":
                attachments += 1
            # tool_result and everything else: not the user — dropped.
        if parts:
            prefix = f"[attached {attachments} image(s)] " if attachments else ""
            return ("typed", prefix + "\n".join(parts))
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript")
    ap.add_argument("--facets-dir", default=os.path.expanduser("~/.claude/usage-data/facets"))
    ap.add_argument("--max-chars", type=int, default=10000, help="total budget for the messages section")
    ap.add_argument("--per-msg", type=int, default=1200)
    ap.add_argument("--min-user-msgs", type=int, default=0,
                    help="exit 3 unless at least this many typed user messages")
    ap.add_argument("--skip-if-first-cmd", default="",
                    help="exit 3 if the first user turn is a command invocation containing this substring (loop guard)")
    ap.add_argument("--skip-if-content-before", default="",
                    help="exit 3 if the transcript's FIRST timestamp predates this ISO datetime. "
                         "File mtime is unreliable as a recency signal (resumed/rewritten sessions "
                         "carry fresh mtimes over month-old content), so the sweep gates on content age.")
    args = ap.parse_args()

    turns = []          # (timestamp, kind, text)
    meta = {"cwd": "", "gitBranch": "", "version": "", "entrypoint": "", "sessionId": ""}
    first_ts = last_ts = None
    counts = {"assistant": 0, "user_lines": 0}
    commands = []

    try:
        with open(args.transcript, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    obj = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue
                if not isinstance(obj, dict):
                    continue
                ltype = obj.get("type")
                ts = obj.get("timestamp") or ""
                if ts:
                    first_ts = first_ts or ts
                    last_ts = ts
                if ltype == "assistant":
                    counts["assistant"] += 1
                    continue
                if ltype != "user" or obj.get("isSidechain") or obj.get("isMeta"):
                    continue
                counts["user_lines"] += 1
                for key in meta:
                    if not meta[key] and obj.get(key):
                        meta[key] = str(obj[key])
                parsed = parse_user_turn(obj)
                if parsed:
                    kind, text = parsed
                    if kind == "command":
                        name = text.split(" — ")[0].replace("invoked ", "")
                        commands.append(name)
                    turns.append((ts, kind, text))
    except OSError as e:
        print(f"distill: cannot read transcript: {e}", file=sys.stderr)
        return 2

    typed = [t for t in turns if t[1] == "typed"]

    # Loop guard: a session whose first user turn invokes self-heal IS a heal
    # run — learning from it would make the loop study itself. Two shapes reach
    # here: a slash-command invocation (kind "command"), and a scheduled-task
    # run, which arrives as a typed message whose text is a <scheduled-task>
    # block. Catch both, but keep the typed case precise — only gate when the
    # turn is actually a scheduled-task block referencing the skip substring, so
    # an ordinary message that merely mentions "self-heal" is not swallowed.
    if args.skip_if_first_cmd and turns:
        first_kind, first_text = turns[0][1], turns[0][2]
        is_command_run = first_kind == "command" and args.skip_if_first_cmd in first_text
        is_scheduled_run = "<scheduled-task" in first_text and args.skip_if_first_cmd in first_text
        if is_command_run or is_scheduled_run:
            print(f"distill: gated (first turn is {args.skip_if_first_cmd} run)", file=sys.stderr)
            return 3

    # General scheduled-task guard: a session whose ONLY typed messages are
    # <scheduled-task> blocks carries no preference signal — it is an automated
    # run (self-heal-daily, treat-weekly-council, treat-pickup-brief, …), not
    # you working, and it burns a drain slot a real session needs. If she
    # typed any genuine follow-up in the same session, that is a real typed turn
    # and keeps the session out of this gate.
    if typed and all("<scheduled-task" in t[2] for t in typed):
        print("distill: gated (scheduled-task run, no user signal)", file=sys.stderr)
        return 3

    # Autonomous skill-launcher guard: some loops (gitscore weekly, etc.) start a
    # session with a machine-generated "run one full cycle in Automated mode"
    # message. It is a launcher firing a skill, not you working — no
    # preference signal, and it burns a drain slot. Gate a session whose EVERY
    # typed message is such a launch. A single genuine follow-up she types keeps
    # the session in (same escape hatch as the scheduled-task guard above).
    _launch = re.compile(r"run\s+(?:one\s+)?full\s+cycle\s+in\s+automated\s+mode", re.I)
    if typed and all(_launch.search(t[2]) for t in typed):
        print("distill: gated (autonomous skill-launcher run, no user signal)", file=sys.stderr)
        return 3

    # Content-age gate. The sweep must not re-mine history that predates the loop
    # (already covered by /insights) — but file mtime lies: a resumed or rewritten
    # transcript carries today's mtime over month-old content, so mtime-based
    # sweeping keeps dragging stale sessions back in. Gate on when the session
    # ACTUALLY happened. Fails open on an unparseable cutoff so a bad argument
    # can never silently block the whole sweep.
    # Compare the session's END, not its start: the sweep's real question is
    # "did this session END since the last sweep", so a long session that spans
    # the watermark (or a genuinely resumed one) is still captured, while a file
    # merely rewritten today over old content is not. Measured on this machine:
    # every drifted transcript's last real turn predates its mtime by days.
    if args.skip_if_content_before and (last_ts or first_ts):
        try:
            cutoff = datetime.fromisoformat(args.skip_if_content_before.replace("Z", "+00:00"))
            if cutoff.tzinfo is None:
                cutoff = cutoff.astimezone()
            ended = datetime.fromisoformat((last_ts or first_ts).replace("Z", "+00:00"))
            if ended < cutoff:
                print(f"distill: gated (content ends {ended.astimezone():%Y-%m-%d %H:%M} local, "
                      f"before cutoff {cutoff.astimezone():%Y-%m-%d %H:%M})", file=sys.stderr)
                return 3
        except (ValueError, TypeError):
            pass

    if len(typed) < args.min_user_msgs:
        print(f"distill: gated ({len(typed)} typed user messages < {args.min_user_msgs})", file=sys.stderr)
        return 3

    sid = meta["sessionId"] or os.path.basename(args.transcript).replace(".jsonl", "")

    def fmt_ts(ts):
        # Transcript timestamps are UTC (ISO-8601 with a trailing Z). Render in
        # the machine's local timezone so evidence dates/times in digests match
        # the wall clock you actually spoke at (an evening EDT session was
        # being attributed to the next UTC day). Fall back to the raw slice if
        # parsing fails.
        if not ts:
            return "?"
        try:
            return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d %H:%M")
        except (ValueError, TypeError):
            return ts.replace("T", " ")[:16]

    # Render messages within budget; if over, shrink the per-message cap so
    # nothing is dropped outright (corrections often come late in a session).
    def render(per_msg):
        out = []
        for ts, kind, text in turns:
            stamp = fmt_ts(ts)[11:16] or "--:--"
            if kind == "command":
                out.append(f"[{stamp}] ({text})")
            else:
                out.append(f"[{stamp}] {shorten(text, per_msg)}")
        return "\n\n".join(out)

    body = render(args.per_msg)
    if len(body) > args.max_chars and turns:
        body = render(max(300, args.max_chars // max(len(turns), 1)))
        body = body[: args.max_chars] + "\n…[digest hit total budget]"

    lines = [
        f"# Session digest: {sid}",
        f"- when: {fmt_ts(first_ts)} → {fmt_ts(last_ts)}",
        f"- cwd: {meta['cwd'] or '?'} | branch: {meta['gitBranch'] or '-'} | app: {meta['entrypoint'] or '?'} v{meta['version'] or '?'}",
        f"- volume: {len(typed)} typed user messages, {counts['assistant']} assistant turns",
        f"- commands invoked: {', '.join(dict.fromkeys(commands)) or 'none'}",
        "- content: user-authored text only; assistant/tool output excluded by design",
        "",
        "## User messages (chronological)",
        body or "(none)",
    ]

    facet_path = os.path.join(args.facets_dir, f"{sid}.json")
    if os.path.isfile(facet_path):
        try:
            with open(facet_path, encoding="utf-8") as f:
                facet = json.load(f)
            keep = ["underlying_goal", "outcome", "session_type", "claude_helpfulness",
                    "user_satisfaction_counts", "friction_counts", "friction_detail",
                    "primary_success", "brief_summary"]
            lines += ["", "## Insights facet (pre-analyzed by /insights)"]
            for k in keep:
                v = facet.get(k)
                if v not in (None, "", {}, []):
                    lines.append(f"- {k}: {json.dumps(v) if isinstance(v, (dict, list)) else v}")
        except (OSError, json.JSONDecodeError):
            pass

    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
