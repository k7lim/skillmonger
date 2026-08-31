#!/usr/bin/env python3
"""The compaction trigger, and the CONFIG.yaml block it reads (roadmap 4.2).

Compaction (CONTEXT.md) is a human-invoked maintenance pass over one skill's
wiki. It is due when the traces since `last_compaction` reach that skill's
`cycle_threshold`, **or** when three or more of them are failing traces
(outcome 1 or 2, CONTEXT.md: Failing trace) -- whichever comes first.

The second rule exists because the first one alone never fired. For seven
months no skill reached its threshold while failing traces sat unconsolidated
in the deployed copies: trace count measures how much a skill is used, and
failures measure whether its wiki owes the agent a pattern. Only the second
one is a reason to sit down and root-cause.

`log-feedback.sh`, `harvest-feedback.sh` and `compact-memo.sh` all ask this
module rather than keeping a copy of the arithmetic each. Import `recommend`
and `reasons`; do not re-derive them.

Run directly to print the status block for one skill (log-feedback.sh does):

    python3 scripts/lib/compaction.py --skill-dir skills/<name>
"""

from __future__ import annotations

import json
import os
import sys

try:
    import yaml
except ImportError:  # the block is scanned line by line instead; see read_compaction
    yaml = None


DEFAULT_CYCLE_THRESHOLD = 15

# Three failing traces since the last compaction is the second trigger. Two is
# a bad afternoon; three is a pattern with evidence.
FAILING_TRACE_TRIGGER = 3

# A deployed copy dates its trace with whichever of these it happens to write.
TIMESTAMP_FIELDS = ("ts", "date", "timestamp")


# --- the rule -------------------------------------------------------------


def recommend(iteration_count, cycle_threshold, failing_since):
    """True when compaction is due for a skill. The whole trigger lives here.

    iteration_count -- traces since `last_compaction`
    cycle_threshold -- the skill's CONFIG.yaml `compaction.cycle_threshold`
    failing_since   -- failing traces (outcome 1 or 2) since `last_compaction`
    """
    return bool(reasons(iteration_count, cycle_threshold, failing_since))


def reasons(iteration_count, cycle_threshold, failing_since):
    """Why compaction is due, as sentences. Empty when it is not due."""
    threshold = int(cycle_threshold or DEFAULT_CYCLE_THRESHOLD)
    out = []
    if int(iteration_count) >= threshold:
        out.append(
            f"{iteration_count} traces since last compaction >= "
            f"threshold {threshold}"
        )
    if int(failing_since) >= FAILING_TRACE_TRIGGER:
        out.append(
            f"{failing_since} failing traces (outcome 1-2) since last "
            f"compaction >= {FAILING_TRACE_TRIGGER}"
        )
    return out


def status_lines(iteration_count, cycle_threshold, failing_since, indent="  "):
    """The status block every caller prints, so all three read the same."""
    threshold = int(cycle_threshold or DEFAULT_CYCLE_THRESHOLD)
    lines = [
        f"{indent}Traces since last compaction: {iteration_count}",
        f"{indent}Cycle threshold: {threshold}",
        f"{indent}Failing traces (outcome 1-2) since then: {failing_since}",
        "",
    ]
    why = reasons(iteration_count, threshold, failing_since)
    if why:
        lines.append(f"{indent}⚠ COMPACTION RECOMMENDED")
        for reason in why:
            lines.append(f"{indent}  - {reason}")
    else:
        by_count = max(0, threshold - int(iteration_count))
        by_failure = max(0, FAILING_TRACE_TRIGGER - int(failing_since))
        lines.append(
            f"{indent}Not due: {by_count} more trace(s), or "
            f"{by_failure} more failing trace(s)."
        )
    return lines


# --- traces ---------------------------------------------------------------


def trace_timestamp(trace):
    """The trace's own timestamp, whichever field it used, exactly as written.

    Harvested traces carry `ts`, `date` or `timestamp` depending on which
    epilogue wrote them; a pattern cites the trace by the one it has.
    """
    for field in TIMESTAMP_FIELDS:
        value = trace.get(field)
        if isinstance(value, str) and value.strip():
            return value.strip()
        if isinstance(value, (int, float)):
            return str(value)
    return ""


def load_traces(path):
    """Every parseable trace in a FEEDBACK.jsonl, or [] when there is none.

    Silently tolerant: a reader that is only counting must not fail on a line
    a deployed copy mangled. `harvest.read_traces` is the reporting version.
    """
    if not path or not os.path.exists(path):
        return []
    out = []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            raw = raw.strip()
            if not raw:
                continue
            try:
                trace = json.loads(raw)
            except ValueError:
                continue
            if isinstance(trace, dict):
                out.append(trace)
    return out


def traces_since(traces, last_compaction):
    """Traces newer than the last compaction; all of them when it is unset.

    A trace with no `ts` cannot be placed in time, so it counts: over-counting
    triggers a compaction that a maintainer can decline, under-counting hides
    the traces that compaction exists to consolidate.
    """
    if not last_compaction:
        return list(traces)
    out = []
    for trace in traces:
        ts = trace.get("ts")
        if not isinstance(ts, str) or not ts.strip():
            out.append(trace)
        elif ts > str(last_compaction):
            out.append(trace)
    return out


def is_failing(trace):
    """Per CONTEXT.md: a failing trace is one with outcome 1 or 2."""
    return trace.get("outcome") in (1, 2)


def failing(traces):
    """The failing traces in a list."""
    return [t for t in traces if is_failing(t)]


def low(traces):
    """Traces worth citing as evidence: failing, or merely acceptable (<= 3)."""
    return [t for t in traces if isinstance(t.get("outcome"), int) and t["outcome"] <= 3]


# --- CONFIG.yaml ----------------------------------------------------------


def _compaction_block(lines):
    """(start, end, indent) of the compaction: block, or None."""
    for i, line in enumerate(lines):
        if line.startswith("compaction:"):
            end = len(lines)
            for j in range(i + 1, len(lines)):
                stripped = lines[j].strip()
                if stripped and not lines[j][:1].isspace():
                    end = j
                    break
            indent = "  "
            for j in range(i + 1, end):
                if lines[j].strip():
                    indent = lines[j][: len(lines[j]) - len(lines[j].lstrip())]
                    break
            return i, end, indent
    return None


def read_compaction(path):
    """Return the compaction block as a dict, or None when the skill has none."""
    if not os.path.exists(path):
        return None
    text = open(path, "r", encoding="utf-8").read()
    if yaml is not None:
        try:
            config = yaml.safe_load(text) or {}
        except Exception:
            config = {}
        if isinstance(config, dict) and isinstance(config.get("compaction"), dict):
            block = dict(config["compaction"])
            last = block.get("last_compaction")
            if last is not None and not isinstance(last, str):
                block["last_compaction"] = str(last)
            return block
        if isinstance(config, dict) and "compaction" in config:
            return {}
        return None
    # Fallback: scan the block the way the sed paths in the other scripts do.
    lines = text.splitlines()
    found = _compaction_block(lines)
    if found is None:
        return None
    start, end, _ = found
    block = {}
    for line in lines[start + 1 : end]:
        if ":" not in line:
            continue
        key, _, value = line.strip().partition(":")
        value = value.strip().strip('"').strip("'")
        if value in ("null", "~", ""):
            block[key.strip()] = None
        elif value.isdigit():
            block[key.strip()] = int(value)
        else:
            block[key.strip()] = value
    return block


def write_iteration_count(path, count):
    """Set compaction.iteration_count, touching only that line.

    Rewriting the whole file through yaml.dump would drop comments and reflow
    every list, so the value is replaced in place instead.
    """
    text = open(path, "r", encoding="utf-8").read()
    lines = text.splitlines()
    found = _compaction_block(lines)
    if found is None:
        return False
    start, end, indent = found
    for i in range(start + 1, end):
        stripped = lines[i].strip()
        if stripped.startswith("iteration_count:"):
            if stripped == f"iteration_count: {count}":
                return False
            lines[i] = f"{indent}iteration_count: {count}"
            break
    else:
        lines.insert(start + 1, f"{indent}iteration_count: {count}")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + ("\n" if text.endswith("\n") else ""))
    return True


# --- entry point ----------------------------------------------------------


def main(argv):
    skill_dir = None

    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--skill-dir":
            skill_dir = args.pop(0)
        else:
            sys.stderr.write(f"compaction: unknown argument {arg}\n")
            return 2

    if not skill_dir:
        sys.stderr.write("compaction: --skill-dir is required\n")
        return 2

    skill_dir = skill_dir.rstrip("/")
    block = read_compaction(os.path.join(skill_dir, "CONFIG.yaml"))
    if block is None:
        return 0

    traces = load_traces(os.path.join(skill_dir, "FEEDBACK.jsonl"))
    since = traces_since(traces, block.get("last_compaction"))
    count = len(since)
    bad = len(failing(since))
    threshold = block.get("cycle_threshold") or DEFAULT_CYCLE_THRESHOLD

    print("=== Compaction Status ===")
    for line in status_lines(count, threshold, bad):
        print(line)
    if recommend(count, threshold, bad):
        name = os.path.basename(skill_dir)
        print(f"    Run: scripts/compact-memo.sh skills/{name}/")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
