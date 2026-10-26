#!/usr/bin/env python3
"""Remove only Claude Narrator's Stop hook; leave all other settings untouched."""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path


SETTINGS = Path.home() / ".claude" / "settings.json"
HOOK_URL = "http://127.0.0.1:17832/claude/finished"


def main() -> None:
    if not SETTINGS.exists():
        return
    with SETTINGS.open("r", encoding="utf-8") as source:
        data = json.load(source)

    hooks = data.get("hooks", {})
    groups = hooks.get("Stop", [])
    kept_groups = []
    for group in groups:
        if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
            kept_groups.append(group)
            continue
        handlers = [
            handler
            for handler in group["hooks"]
            if not (
                isinstance(handler, dict)
                and handler.get("type") == "http"
                and handler.get("url") == HOOK_URL
            )
        ]
        if handlers:
            updated = dict(group)
            updated["hooks"] = handlers
            kept_groups.append(updated)
    hooks["Stop"] = kept_groups

    fd, temporary_name = tempfile.mkstemp(prefix="settings.", suffix=".json", dir=SETTINGS.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as target:
            json.dump(data, target, ensure_ascii=False, indent=2)
            target.write("\n")
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary_name, SETTINGS)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)

    print(f"Removed Claude Narrator Stop hook from {SETTINGS}")


if __name__ == "__main__":
    main()
