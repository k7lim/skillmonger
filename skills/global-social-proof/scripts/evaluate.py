#!/usr/bin/env python3
import json
import pathlib
import re
import sys


def read_input() -> str:
    if len(sys.argv) > 1:
        return pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    return sys.stdin.read()


text = read_input()
checks = {
    "has_synthesis": bool(re.search(r"(?im)^#{1,4}\s+.*synthesis", text)),
    "has_evidence_audit": bool(
        re.search(r"(?im)^#{1,4}\s+.*evidence\s+audit", text)
    ),
    "has_coverage": bool(re.search(r"(?im)^#{1,4}\s+.*coverage", text)),
    "has_source_url": bool(re.search(r"https?://", text)),
    "mentions_language_or_translation": bool(
        re.search(r"(?i)\b(language|translation|translated|original)\b", text)
    ),
    "mentions_gap_or_limit": bool(
        re.search(r"(?i)\b(gap|deferred|not searched|access|limitation)\b", text)
    ),
}
passed = sum(checks.values())
if passed == len(checks):
    outcome, note = 5, ""
elif passed >= 5:
    outcome, note = 4, "One structural audit signal is missing."
elif passed >= 3:
    outcome, note = 3, "The outcome is usable but lacks required audit structure."
elif passed >= 1:
    outcome, note = 2, "Most required discovery-outcome sections are missing."
else:
    outcome, note = 1, "Output does not match the skill contract."

print(
    json.dumps(
        {"outcome": outcome, "note": note, "checks": checks, "source": "script"},
        ensure_ascii=False,
        separators=(",", ":"),
    )
)
