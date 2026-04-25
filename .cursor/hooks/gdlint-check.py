#!/usr/bin/env python3
"""stop hook: lint only .gd files that were edited in this session."""

import json
import os
import subprocess
import sys
import tempfile

TRACK_FILE = os.path.join(tempfile.gettempdir(), "gdlint_edited_files.txt")


def main():
    try:
        json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        pass

    if not os.path.isfile(TRACK_FILE):
        json.dump({}, sys.stdout)
        return

    with open(TRACK_FILE, "r", encoding="utf-8") as f:
        raw = f.read().strip()

    os.remove(TRACK_FILE)

    if not raw:
        json.dump({}, sys.stdout)
        return

    files = sorted(set(raw.split("\n")))
    existing = [p for p in files if os.path.isfile(p)]
    if not existing:
        json.dump({}, sys.stdout)
        return

    try:
        result = subprocess.run(
            ["gdlint"] + existing,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except FileNotFoundError:
        json.dump(
            {"followup_message": "gdlint is not installed. Run: pip install \"gdtoolkit==4.*\""},
            sys.stdout,
        )
        return
    except subprocess.TimeoutExpired:
        json.dump(
            {"followup_message": "gdlint timed out"},
            sys.stdout,
        )
        return

    output = (result.stdout.strip() + "\n" + result.stderr.strip()).strip()
    if result.returncode != 0 and output:
        lines = output.split("\n")
        n = len(existing)
        header = f"gdlint checked {n} edited file(s), found {len(lines)} issue(s):\n"
        summary = header + "\n".join(lines[:30])
        if len(lines) > 30:
            summary += f"\n... and {len(lines) - 30} more"
        json.dump({"followup_message": summary}, sys.stdout)
    else:
        json.dump({}, sys.stdout)


if __name__ == "__main__":
    main()
