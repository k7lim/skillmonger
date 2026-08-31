#!/usr/bin/env python3
"""evaluate.py — type A (programmatic) feedback scorer for sm-stealth runs.

Reads a JSON run-record from stdin:
  {"url":..., "out":..., "exit_code":..., "bytes":..., "title":...}
Scores 1–5: did the fetch succeed and return non-trivial content of the requested kind?
Emits: {"outcome":1-5,"note":"...","checks":{...},"source":"script"}
"""
from __future__ import annotations

import json
import sys

# Minimum "non-trivial" payload size by output mode (bytes).
MIN_BYTES = {"text": 40, "html": 200, "screenshot": 1024, "meta": 20}


def score(rec: dict) -> dict:
    out = rec.get("out", "text")
    exit_code = rec.get("exit_code")
    nbytes = rec.get("bytes")
    title = rec.get("title")

    checks: dict = {}
    checks["exit_ok"] = exit_code == 0

    if exit_code != 0:
        return {"outcome": 1, "source": "script", "checks": checks,
                "note": f"fetch failed (exit_code={exit_code})"}

    floor = MIN_BYTES.get(out, 40)
    big_enough = isinstance(nbytes, (int, float)) and nbytes >= floor
    checks["bytes"] = nbytes
    checks["bytes_floor"] = floor
    checks["non_trivial"] = bool(big_enough)

    # title is meaningful for meta/html/text renders; not for screenshots
    title_ok = bool(title) and str(title).strip() != ""
    if out != "screenshot":
        checks["has_title"] = title_ok

    if not big_enough:
        return {"outcome": 2, "source": "script", "checks": checks,
                "note": f"exit 0 but payload trivial ({nbytes} < {floor} bytes for --out {out})"}

    if out == "screenshot":
        outcome = 5
        note = f"screenshot captured, {nbytes} bytes"
    elif title_ok:
        outcome = 5
        note = f"succeeded: {nbytes} bytes, title present"
    else:
        outcome = 4
        note = f"succeeded: {nbytes} bytes but no page title"

    return {"outcome": outcome, "source": "script", "checks": checks, "note": note}


def main() -> int:
    raw = sys.stdin.read()
    try:
        rec = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        print(json.dumps({"outcome": 1, "source": "script", "checks": {},
                          "note": "invalid or empty JSON run-record on stdin"}))
        return 0
    print(json.dumps(score(rec)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
