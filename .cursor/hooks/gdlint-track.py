#!/usr/bin/env python3
"""afterFileEdit hook: record edited .gd file paths to a temp file."""

import json
import os
import sys
import tempfile

TRACK_FILE = os.path.join(tempfile.gettempdir(), "gdlint_edited_files.txt")


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        json.dump({}, sys.stdout)
        return

    filepath = payload.get("path", "")
    if not filepath.endswith(".gd"):
        json.dump({}, sys.stdout)
        return

    with open(TRACK_FILE, "a", encoding="utf-8") as f:
        f.write(filepath + "\n")

    json.dump({}, sys.stdout)


if __name__ == "__main__":
    main()
