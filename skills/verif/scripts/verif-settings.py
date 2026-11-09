#!/usr/bin/env python3
"""verif-settings.py — read the OPTIONAL personal interview settings of /verif.

Contract: ~/.claude/skills/_shared/verif.json = {"interview": "auto|ask", "decisions": "auto|ask"}.
The file is personal (it is never shipped with the plugin). A missing key means "ask" for that key.

  interview: auto  → the A3.0 mode question is not asked, the interview runs in auto mode.
  interview: ask   → today's behaviour: the mode question is asked.
  decisions: auto  → in auto mode a decision with an arbiter recommendation apply/skip is applied
                     without a question; only the guarded cases are asked (interview-apply.md A3.3).
  decisions: ask   → today's behaviour: every decision is asked.

Prints ONE JSON line:
  {"interview": "...", "decisions": "...", "source": "<path>|flag|null", "reason": "..."}
No file, unreadable JSON, or an unknown value in any key → both "ask" (exactly today's behaviour)
and a reason. `--manual` (the /verif flag) wins over the file: {"interview": "manual", ...}.
Exit code is always 0. Override the path with VERIF_SETTINGS_FILE (tests).
"""
import json
import os
import sys

PATH = os.environ.get("VERIF_SETTINGS_FILE") or os.path.expanduser("~/.claude/skills/_shared/verif.json")
VALUES = ("auto", "ask")
DEFAULT = {"interview": "ask", "decisions": "ask", "source": None}


def main(argv):
    if "--manual" in argv:
        return {"interview": "manual", "decisions": "ask", "source": "flag", "reason": "--manual"}
    if not os.path.isfile(PATH):
        return {**DEFAULT, "reason": "no file"}
    try:
        with open(PATH, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return {**DEFAULT, "reason": "unreadable JSON"}
    if not isinstance(data, dict):
        return {**DEFAULT, "reason": "unreadable JSON"}
    out = {}
    for key in ("interview", "decisions"):
        value = data.get(key, "ask")
        if value not in VALUES:
            return {**DEFAULT, "reason": f"bad {key} value"}
        out[key] = value
    return {**out, "source": PATH, "reason": "file"}


if __name__ == "__main__":
    print(json.dumps(main(sys.argv[1:]), ensure_ascii=False))
