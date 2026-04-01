#!/usr/bin/env python3
"""List Antigravity workspaces from VS Code workspace storage.

Reads PLAY_AG_WS_STORAGE and PLAY_DIR from the environment.
Outputs pipe-delimited lines: mtime|name|path
Sorted by most recently used first.
"""

import json
import os
import glob
import sys
import urllib.parse


def main():
    ws_dir = os.environ.get("PLAY_AG_WS_STORAGE", "")
    play_dir = os.environ.get("PLAY_DIR", "")
    home = os.path.expanduser("~")

    if not ws_dir or not os.path.isdir(ws_dir):
        sys.exit(0)

    # Configurable exclude prefixes via env (pipe-separated), with sensible defaults
    extra = os.environ.get("PLAY_AG_EXCLUDE", "")
    exclude_prefixes = [
        play_dir,
        os.path.join(home, ".gemini"),
        os.path.join(home, ".ssh"),
        os.path.join(home, ".config"),
        os.path.join(home, ".dotfiles"),
        os.path.join(home, ".antigravity"),
        os.path.join(home, "playgrounds"),
        os.path.join(home, "delete"),
        os.path.join(home, "quick"),
    ]
    if extra:
        exclude_prefixes.extend(extra.split("|"))

    results = []
    seen_paths = set()

    for wf in glob.glob(os.path.join(ws_dir, "*", "workspace.json")):
        try:
            with open(wf) as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            continue

        folder = data.get("folder", "")
        if not folder.startswith("file:///"):
            continue

        path = urllib.parse.unquote(folder[7:])

        # Skip home dir itself
        if path.rstrip("/") == home:
            continue

        # Skip excluded prefixes
        if any(path.startswith(p) for p in exclude_prefixes if p):
            continue

        # Skip if path no longer exists
        if not os.path.isdir(path):
            continue

        # Deduplicate
        rpath = path.rstrip("/")
        if rpath in seen_paths:
            continue
        seen_paths.add(rpath)

        # Use workspace storage dir mtime as "last used"
        try:
            mtime = int(os.path.getmtime(os.path.dirname(wf)))
        except OSError:
            continue

        results.append((mtime, path))

    results.sort(reverse=True)
    for mtime, path in results:
        name = os.path.basename(path.rstrip("/"))
        print(f"{mtime}|{name}|{path}")


if __name__ == "__main__":
    main()
