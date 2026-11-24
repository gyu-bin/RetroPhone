#!/usr/bin/env python3
"""Lists Korean UI strings passed to L()/LF() that have no English entry in any EnglishTable.
Usage: python3 scripts/check_l10n.py [--json]"""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent / "RetroPhone"
call = re.compile(r'\bLF?\(\s*"((?:[^"\\]|\\.)*)"')
entry = re.compile(r'"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"')
hangul = re.compile(r'[가-힣]')
used, table = {}, set()
for f in root.rglob("*.swift"):
    text = f.read_text(encoding="utf-8")
    if "EnglishTable" in text:
        for block in re.split(r"static let \w+", text)[1:]:
            keys = [k for k, _ in entry.findall(block.split("]\n")[0] if "]\n" in block else block)]
            dupes = {k for k in keys if keys.count(k) > 1}
            for d in sorted(dupes):
                print(f"DUPLICATE KEY (runtime crash!) in {f.relative_to(root)}: {d}")
            table.update(keys)
    for s in call.findall(text):
        if hangul.search(s):
            used.setdefault(s, str(f.relative_to(root)))
missing = {k: v for k, v in sorted(used.items()) if k not in table}
if "--json" in sys.argv:
    print(json.dumps(missing, ensure_ascii=False, indent=1))
else:
    for k, v in missing.items():
        print(f"{v}: {k}")
    print(f"\n{len(missing)} untranslated of {len(used)} strings", file=sys.stderr)
