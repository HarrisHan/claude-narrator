#!/usr/bin/env python3
"""Install Claude Narrator's localhost Stop hook without touching unrelated settings."""

from __future__ import annotations

import json
import os
import shutil
import tempfile
from datetime import datetime
from pathlib import Path


SETTINGS = Path.home() / ".claude" / "settings.json"
HOOK_URL = "http://127.0.0.1:17832/claude/finished"
LEGACY_SCRIPT = str(Path.home() / ".claude" / "hooks" / "speak_last_reply.py")


def is_legacy_speaker(handler: object) -> bool:
    return (
        isinstance(handler, dict)
        and handler.get("type") == "command"
        and LEGACY_SCRIPT in str(handler.get("command", ""))
    )


def is_our_hook(handler: object) -> bool:
    return (
        isinstance(handler, dict)
        and handler.get("type") == "http"
        and handler.get("url") == HOOK_URL
    )


def main() -> None:
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    if SETTINGS.exists():
        with SETTINGS.open("r", encoding="utf-8") as source:
            data = json.load(source)
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = SETTINGS.with_name(f"settings.json.before-claude-narrator-{timestamp}.bak")
        shutil.copy2(SETTINGS, backup)
    else:
        data = {}
        backup = None

    hooks = data.setdefault("hooks", {})
    stop_groups = hooks.setdefault("Stop", [])
    cleaned_groups = []

    for group in stop_groups:
        if not isinstance(group, dict):
            cleaned_groups.append(group)
            continue
        handlers = group.get("hooks")
        if not isinstance(handlers, list):
            cleaned_groups.append(group)
            continue
        kept = [handler for handler in handlers if not is_legacy_speaker(handler) and not is_our_hook(handler)]
        if kept:
            updated = dict(group)
            updated["hooks"] = kept
            cleaned_groups.append(updated)

    cleaned_groups.append(
        {
            "hooks": [
                {
                    "type": "http",
                    "url": HOOK_URL,
                    "timeout": 5,
                }
            ]
        }
    )
    hooks["Stop"] = cleaned_groups

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

    print(f"Installed Claude Narrator Stop hook in {SETTINGS}")
    if backup:
        print(f"Backup: {backup}")


if __name__ == "__main__":
    main()
