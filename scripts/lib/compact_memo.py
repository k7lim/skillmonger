#!/usr/bin/env python3
"""The Maintainer's brief for one skill's wiki (roadmap 4.1).

Printed, never written: compaction is a judgement the agent makes, and this
only lays out what it has to judge. Called by scripts/compact-memo.sh, which
owns the harvest and the process text.

Four sections:
  * the compaction status, decided in compaction.py;
  * the traces since `last_compaction`, grouped by note or checks, failing
    traces first, identical notes collapsed with counts;
  * the wiki's `### ` entries that predate the pattern layout;
  * a pattern template with `evidence:` already filled from the traces that
    scored 3 or below, plus -- for a dependent skill -- the owner skills the
    pattern may belong to instead.

Trace schemas in the wild differ: `ts` or `date` or `timestamp`, `checks` as
a dict or a list, `note` sometimes absent. Everything here tolerates that.
"""

from __future__ import annotations

import os
import re
import sys
import textwrap

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from compaction import (  # noqa: E402
    DEFAULT_CYCLE_THRESHOLD,
    failing,
    is_failing,
    load_traces,
    low,
    read_compaction,
    status_lines,
    trace_timestamp,
    traces_since,
)

try:
    import yaml
except ImportError:
    yaml = None


WIDTH = 76
MAX_EVIDENCE = 12

# Failing groups are never capped -- they are the reason to compact. The rest
# are, so a skill with 163 traces still prints a brief an agent will read.
OTHER_GROUP_LIMIT = 15


# --- grouping -------------------------------------------------------------


def checks_summary(checks):
    """A one-line rendering of `checks`, whether it is a dict or a list."""
    if isinstance(checks, dict):
        return ", ".join(f"{k}={checks[k]}" for k in sorted(checks))
    if isinstance(checks, list):
        parts = []
        for item in checks:
            if isinstance(item, dict):
                parts.append(str(item.get("name") or item.get("check") or item))
            else:
                parts.append(str(item))
        return ", ".join(parts)
    if checks:
        return str(checks)
    return ""


def group_key(trace):
    """What makes two traces the same story: their note, else their checks."""
    note = " ".join((trace.get("note") or "").split())
    if note:
        return note
    summary = checks_summary(trace.get("checks"))
    if summary:
        return f"checks: {summary}"
    return "(no note)"


def group(traces):
    """Collapse identical notes. Groups with a failing trace sort first."""
    buckets = {}
    for trace in traces:
        buckets.setdefault(group_key(trace), []).append(trace)
    groups = []
    for key, members in buckets.items():
        outcomes = [t["outcome"] for t in members if isinstance(t.get("outcome"), int)]
        groups.append(
            {
                "key": key,
                "traces": members,
                "count": len(members),
                "worst": min(outcomes) if outcomes else None,
                "best": max(outcomes) if outcomes else None,
                "failing": any(is_failing(t) for t in members),
            }
        )
    groups.sort(key=lambda g: (not g["failing"], -g["count"], g["key"]))
    return groups


def outcome_label(entry):
    if entry["worst"] is None:
        return "outcome ?"
    if entry["worst"] == entry["best"]:
        return f"outcome {entry['worst']}"
    return f"outcome {entry['worst']}-{entry['best']}"


def evidence_list(traces, limit=MAX_EVIDENCE):
    """Timestamps to cite, in the field each trace actually used."""
    stamps = [ts for ts in (trace_timestamp(t) for t in traces) if ts]
    shown = stamps[:limit]
    extra = len(stamps) - len(shown)
    text = ", ".join(shown)
    if extra > 0:
        text += f", (+{extra} more)"
    untimed = len(traces) - len(stamps)
    return text, untimed


def print_group(entry, evidence_limit=6):
    head = f"  [{entry['count']}x] {outcome_label(entry)}"
    body = textwrap.fill(
        entry["key"],
        width=WIDTH,
        initial_indent=f"{head}  ",
        subsequent_indent="         ",
    )
    print(body)
    text, untimed = evidence_list(entry["traces"], limit=evidence_limit)
    if text:
        print(
            textwrap.fill(
                text,
                width=WIDTH,
                initial_indent="         evidence: ",
                subsequent_indent="                   ",
            )
        )
    if untimed:
        print(f"         ({untimed} of them carry no timestamp field)")


# --- the wiki -------------------------------------------------------------


def read_entries(memo_path):
    """Every `### ` entry in the wiki, with the lines that belong to it."""
    if not os.path.exists(memo_path):
        return []
    lines = open(memo_path, "r", encoding="utf-8", errors="replace").read().splitlines()
    entries = []
    current = None
    for lineno, line in enumerate(lines, 1):
        if line.startswith("### "):
            if current:
                entries.append(current)
            current = {"line": lineno, "title": line[4:].strip(), "body": []}
        elif line.startswith("## "):
            if current:
                entries.append(current)
            current = None
        elif current is not None:
            current["body"].append(line)
    if current:
        entries.append(current)
    return entries


def missing_fields(entry):
    """Which of the pattern layout's required fields the entry does not have."""
    body = "\n".join(entry["body"])
    missing = []
    for field in ("status", "evidence"):
        if not re.search(rf"^\s*[-*]?\s*{field}\s*:", body, re.IGNORECASE | re.MULTILINE):
            missing.append(field)
    return missing


# --- dependencies ---------------------------------------------------------


def _as_list(value):
    if isinstance(value, str):
        return [v.strip() for v in value.split(",") if v.strip()]
    if isinstance(value, list):
        return [str(v).strip() for v in value if str(v).strip()]
    return []


def dependency_skills(config_path):
    """Skills this one depends on, so the brief can name the owner candidates.

    `dependencies.skills` is the one key (CONTEXT.md, Dependent skill).
    """
    if not os.path.exists(config_path):
        return []
    names = []
    if yaml is not None:
        try:
            config = yaml.safe_load(open(config_path, encoding="utf-8")) or {}
        except Exception:
            config = {}
        deps = config.get("dependencies") if isinstance(config, dict) else None
        if isinstance(deps, dict):
            names.extend(_as_list(deps.get("skills")))
    else:
        inside = False
        key = None
        for line in open(config_path, encoding="utf-8", errors="replace"):
            if line.startswith("dependencies:"):
                inside = True
                continue
            if inside and line.strip() and not line[:1].isspace():
                break
            if not inside:
                continue
            match = re.match(r"\s+(skills)\s*:(.*)$", line)
            if match:
                key = match.group(1)
                rest = match.group(2).strip()
                if rest.startswith("["):
                    names.extend(_as_list(rest.strip("[]")))
                    key = None
                continue
            if key and re.match(r"\s+-\s", line):
                names.append(line.split("-", 1)[1].strip())
            elif key and line.strip():
                key = None
    seen = []
    for name in names:
        if name and name not in seen:
            seen.append(name)
    return seen


# --- the brief ------------------------------------------------------------


def main(argv):
    if len(argv) != 1:
        sys.stderr.write("compact_memo: usage: compact_memo.py <skill-dir>\n")
        return 2
    skill_dir = argv[0].rstrip("/")
    skill_name = os.path.basename(skill_dir)
    config_path = os.path.join(skill_dir, "CONFIG.yaml")
    memo_path = os.path.join(skill_dir, "MEMO.md")
    feedback_path = os.path.join(skill_dir, "FEEDBACK.jsonl")

    block = read_compaction(config_path) or {}
    last = block.get("last_compaction")
    threshold = block.get("cycle_threshold") or DEFAULT_CYCLE_THRESHOLD

    traces = load_traces(feedback_path)
    since = traces_since(traces, last)
    bad = failing(since)

    # --- status ---
    print("=== Compaction Status ===")
    if not os.path.exists(config_path):
        print("  No CONFIG.yaml; compaction is untracked for this skill.")
    else:
        print(f"  Last compaction: {last or 'never'}")
        for line in status_lines(len(since), threshold, len(bad)):
            print(line)
    print("")

    # --- corpus ---
    if traces:
        scores = [t["outcome"] for t in traces if isinstance(t.get("outcome"), int)]
        sources = {}
        for trace in traces:
            sources[trace.get("source") or "?"] = sources.get(trace.get("source") or "?", 0) + 1
        print(f"=== Trace corpus ({len(traces)}) ===")
        if scores:
            print(f"  Mean outcome: {sum(scores) / len(scores):.1f} / 5.0")
        print("  Sources: " + "  ".join(f"{k}={v}" for k, v in sorted(sources.items())))
        print("")

    # --- traces ---
    scope = "since last compaction" if last else "in the wiki's whole history"
    print(f"=== Traces {scope} ({len(since)} of {len(traces)}) ===")
    if not since:
        print("  None. Nothing new to consolidate into patterns.")
    else:
        groups = group(since)
        failing_groups = [g for g in groups if g["failing"]]
        other_groups = [g for g in groups if not g["failing"]]
        if failing_groups:
            print("")
            print("  Failing traces (outcome 1-2) -- these are what compaction is for:")
            for entry in failing_groups:
                print_group(entry)
        if other_groups:
            print("")
            print("  Everything else:")
            for entry in other_groups[:OTHER_GROUP_LIMIT]:
                print_group(entry, evidence_limit=3)
            hidden = len(other_groups) - OTHER_GROUP_LIMIT
            if hidden > 0:
                print(f"  (+{hidden} more group(s); read FEEDBACK.jsonl for them)")
    print("")

    # --- wiki entries ---
    entries = read_entries(memo_path)
    stale = [(e, missing_fields(e)) for e in entries]
    stale = [(e, m) for e, m in stale if m]
    print(f"=== Wiki entries ({len(entries)}) ===")
    if not entries:
        print("  No `### ` entries yet.")
    elif not stale:
        print("  Every entry carries status and evidence.")
    else:
        print("  These predate the pattern layout. Old free-form entries stay")
        print("  valid; convert one when you touch it, not in bulk.")
        for entry, missing in stale:
            title = entry["title"][:44]
            print(f"    MEMO.md:{entry['line']:<5} {title:<46} missing: {', '.join(missing)}")
    print("")

    # --- pattern template ---
    cited = low(since)
    text, untimed = evidence_list(cited)
    print("=== Pattern template ===")
    print("")
    print("  One entry per root cause. The slug is lowercase-with-hyphens and")
    print("  stable: it is the name the Iteration Log's `Patterns` column uses")
    print("  when the pattern graduates, so it is the provenance of the edit.")
    print("")
    print("### <slug>: short title")
    print("- status: open")
    print("- root cause: one sentence")
    if text:
        print(f"- evidence: FEEDBACK {text}")
    else:
        print('- evidence: manual')
    print("- workaround: what the agent should do now")
    print("- skill change: what SKILL.md should say if this graduates (optional)")
    print("")
    if text:
        print(f"  evidence pre-filled from the {len(cited)} trace(s) scoring 3 or below")
        print("  since the last compaction; cut the ones a given pattern did not")
        print("  come from. Timestamps are quoted from whichever field each trace")
        print("  wrote (`ts`, `date` or `timestamp`).")
        if untimed:
            print(f"  {untimed} of them carry no timestamp field and cannot be cited.")
    else:
        print("  No trace scored 3 or below, so a pattern written now is `manual`:")
        print("  evidence you brought, not evidence the traces produced.")
    print("")

    # --- owner skills ---
    deps = dependency_skills(config_path)
    if deps:
        print("=== Owner skills ===")
        print("")
        print(f"  {skill_name} depends on: {', '.join(deps)}")
        print("")
        print("  A pattern has exactly one owner skill: the one whose mechanism")
        print("  it describes. Before writing any pattern above into this wiki,")
        print("  ask whose mechanism failed. If it is one of those skills, the")
        print("  pattern belongs in its wiki --")
        for dep in deps:
            print(f"    skills/{dep}/MEMO.md")
        print("  -- and this wiki points at it rather than copying it.")
        print("")
        print(f"  Only a workaround that is {skill_name}'s own, one the owner")
        print("  skill does not need, is a pattern owned here; it cites the")
        print("  owner's pattern as its cause.")
        print("")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
