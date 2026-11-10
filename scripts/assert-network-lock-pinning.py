#!/usr/bin/env python3
"""Fail when a flake.lock contains path-pinned network-* inputs.

This repository consumes many ``network-*`` flakes. A ``type = "path"`` lock
entry for one of them silently replaces the pinned GitHub revision with a
local checkout, which defeats the revision pinning the spec chain relies on.
"""

from __future__ import annotations

import json
import pathlib
import sys
from typing import Any


def is_network_node(name: str, value: dict[str, Any]) -> bool:
    if name.startswith("network-"):
        return True
    repo = value.get("repo")
    if isinstance(repo, str) and repo.startswith("network-"):
        return True
    path = value.get("path")
    if isinstance(path, str) and pathlib.Path(path).name.startswith("network-"):
        return True
    return False


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: assert-network-lock-pinning.py FLAKE_LOCK", file=sys.stderr)
        return 2

    lock_path = pathlib.Path(sys.argv[1])
    data = json.loads(lock_path.read_text(encoding="utf-8"))
    violations: list[str] = []

    for name, node in sorted(data.get("nodes", {}).items()):
        if not isinstance(node, dict):
            continue
        for section in ("locked", "original"):
            value = node.get(section)
            if not isinstance(value, dict):
                continue
            if value.get("type") == "path" and is_network_node(name, value):
                path = value.get("path", "")
                violations.append(f"{name}.{section}: type=path path={path}")

    if violations:
        print(f"FAIL network lock pinning: {lock_path} contains network-* path inputs", file=sys.stderr)
        for violation in violations:
            print(f"  {violation}", file=sys.stderr)
        return 1

    print(f"PASS network lock pinning: {lock_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
