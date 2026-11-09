#!/usr/bin/env python3
"""changed_sections.py — which Markdown sections an edit touched (for the final reading block).

Usage:
  changed_sections.py <snapshot> <current> [<snapshot> <current> ...]

`<snapshot>` may be /dev/null (the file did not exist before). For each pair prints one JSON line:
  {"file": "<current>", "sections": ["## Heading", ...], "changed_lines": N}
A section is the nearest Markdown heading (`#` … `######`, outside fenced code) above a changed
line of the CURRENT file; a pure deletion is attributed to the heading above the deletion point.
Lines before the first heading go to "(начало файла)". Order = order in the file, no duplicates.
"""
import difflib
import json
import re
import sys

HEAD = re.compile(r"^(#{1,6})\s+\S")
FENCE = re.compile(r"^\s*(```|~~~)")


def headings(lines):
    """For every line index, the heading text in force at that line."""
    out, current, fenced = [], "(начало файла)", False
    for line in lines:
        if FENCE.match(line):
            fenced = not fenced
        elif not fenced and HEAD.match(line):
            current = line.strip()
        out.append(current)
    return out


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except FileNotFoundError:
        return []


def sections(old_path, new_path):
    old, new = read(old_path), read(new_path)
    under = headings(new)
    seen, result, changed = set(), [], 0
    sm = difflib.SequenceMatcher(a=old, b=new, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        changed += max(i2 - i1, j2 - j1)
        if j2 > j1:
            idx = range(j1, j2)
        else:  # pure deletion: the heading in force just above the deletion point
            idx = [max(j1 - 1, 0)] if new else []
        for j in idx:
            h = under[j] if j < len(under) else "(начало файла)"
            if h not in seen:
                seen.add(h)
                result.append(h)
    return {"file": new_path, "sections": result, "changed_lines": changed}


def main(argv):
    if len(argv) < 2 or len(argv) % 2:
        print(__doc__, file=sys.stderr)
        return 64
    for k in range(0, len(argv), 2):
        print(json.dumps(sections(argv[k], argv[k + 1]), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
