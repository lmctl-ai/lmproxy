#!/usr/bin/env python3
"""Verify checked-in compile-only lmcode source and bytecode pins."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / sys.argv[1]).read_text(encoding="utf-8"))
if manifest.get("format") != 1:
    raise SystemExit("unsupported lmcode fixture manifest format")
entries = manifest.get("programs")
if not isinstance(entries, list) or len(entries) != 7:
    raise SystemExit("fixture manifest must pin four examples and three runtime programs")
seen = set()
for entry in entries:
    name = entry["name"]
    if name in seen:
        raise SystemExit(f"duplicate fixture name: {name}")
    seen.add(name)
    for field in ("source", "bytecode"):
        path = root / entry[field]
        if not path.is_file():
            raise SystemExit(f"missing {field} fixture: {entry[field]}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != entry[field + "_sha256"]:
            raise SystemExit(f"{field} fixture hash mismatch: {entry[field]}")
    raw = (root / entry["bytecode"]).read_bytes()
    if len(raw) < 6 or raw[:4] != b"DSLB" or raw[5] != 6:
        raise SystemExit(f"fixture is not lmcode bytecode v6: {entry['bytecode']}")
print(f"verified {len(entries)} lmcode fixture pins from {manifest['compiler']['commit']}")
