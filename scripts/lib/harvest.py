#!/usr/bin/env python3
"""Union the traces in every deployed copy back into the repo (ADR 0002).

Agents run deployed copies that cannot reach this repo, so a skill's epilogue
appends its trace to the deployed copy's FEEDBACK.jsonl. This is the only path
home. Called by scripts/harvest-feedback.sh, which owns the target list and the
CLI; this module owns the JSON.

Rules:
  * Union, never rewrite. Lines already in the repo are left byte for byte;
    harvested lines are appended.
  * A trace is identified by (skill, ts) plus its content. Identical copies of
    the same trace in seven targets collapse to one; two distinct traces that
    happen to share a ts (skills that write a date-only ts do this constantly)
    stay two, with a warning.
  * `source` is normalised on the way in per CONTEXT.md: self -> llm,
    hybrid -> script when the trace carries `checks` else llm, missing -> llm.
    `version` is left exactly as written.
  * Unparseable lines are skipped with a warning; they are never repaired.

`iteration_count`, the compaction block it lives in, and the trigger that
decides when compaction is recommended belong to `compaction.py`.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# The compaction trigger and the CONFIG.yaml block it reads live in one module
# so log-feedback.sh, harvest-feedback.sh and compact-memo.sh cannot drift.
from compaction import (  # noqa: E402
    DEFAULT_CYCLE_THRESHOLD,
    failing,
    read_compaction,
    reasons,
    recommend,
    traces_since,
    write_iteration_count,
)


# --- traces ---------------------------------------------------------------


def normalise(trace):
    """Return the trace with `source` resolved to script | llm | user."""
    out = dict(trace)
    source = out.get("source")
    if source == "self":
        out["source"] = "llm"
    elif source == "hybrid":
        out["source"] = "script" if out.get("checks") else "llm"
    elif source is None or source == "":
        out["source"] = "llm"
    return out


def canonical(trace):
    """Stable text for a trace, independent of key order and whitespace."""
    return json.dumps(trace, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def trace_key(skill, trace):
    """(skill, ts, digest). The digest keeps same-ts traces distinct.

    The digest is taken after normalisation so a line already harvested (and
    therefore already normalised) matches the raw line it came from, which is
    what makes a second run add nothing.
    """
    ts = trace.get("ts")
    ts = ts if isinstance(ts, str) and ts.strip() else ""
    digest = hashlib.sha256(canonical(normalise(trace)).encode("utf-8")).hexdigest()
    return (skill, ts, digest)


def read_traces(path, warn):
    """Yield (raw_line, trace) for each parseable line, warning about the rest."""
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for lineno, raw in enumerate(handle, 1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                trace = json.loads(raw)
            except ValueError:
                warn(f"{path}:{lineno}: unparseable line skipped")
                continue
            if not isinstance(trace, dict):
                warn(f"{path}:{lineno}: not a JSON object, skipped")
                continue
            yield raw, trace


def sort_index(entry):
    """Appended traces go in ts order; the undated ones keep target order."""
    _, ts, _ = entry["key"]
    return (0, ts, entry["order"]) if ts else (1, "", entry["order"])


def harvest_skill(skill, repo_file, target_files, warn):
    """Append every trace the targets have and the repo lacks.

    Returns (added, total_traces, failing, collisions, first_collision_ts).
    """
    seen = {}
    kept = []
    order = 0

    if os.path.exists(repo_file):
        for raw, trace in read_traces(repo_file, warn):
            key = trace_key(skill, trace)
            seen[key] = raw
            kept.append(trace)

    by_ts = {}
    for key in seen:
        by_ts.setdefault(key[1], set()).add(key[2])

    collisions = 0
    first_collision_ts = None
    new_entries = []
    for path in target_files:
        for raw, trace in read_traces(path, warn):
            key = trace_key(skill, trace)
            if key in seen:
                continue
            if key[1] and key[1] in by_ts:
                # Same (skill, ts), different trace. The repo's line stays as
                # it is; this one is a separate trace, not a rewrite of it.
                collisions += 1
                if first_collision_ts is None:
                    first_collision_ts = key[1]
            seen[key] = raw
            by_ts.setdefault(key[1], set()).add(key[2])
            normalised = normalise(trace)
            # Re-serialise only when normalisation actually changed something,
            # so a harvested trace stays exactly as the deployed copy wrote it.
            line = raw if normalised == trace else canonical(normalised)
            new_entries.append({"key": key, "line": line, "order": order, "trace": normalised})
            order += 1

    added = len(new_entries)
    if added:
        new_entries.sort(key=sort_index)
        needs_newline = (
            os.path.exists(repo_file)
            and os.path.getsize(repo_file) > 0
            and open(repo_file, "rb").read()[-1:] != b"\n"
        )
        with open(repo_file, "a", encoding="utf-8") as handle:
            if needs_newline:
                handle.write("\n")
            for entry in new_entries:
                handle.write(entry["line"] + "\n")
        kept.extend(entry["trace"] for entry in new_entries)

    return added, kept, collisions, first_collision_ts


# --- entry point ----------------------------------------------------------


def main(argv):
    skills_dir = None
    targets = []
    only = []
    quiet = False

    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--skills-dir":
            skills_dir = args.pop(0)
        elif arg == "--target":
            targets.append(args.pop(0))
        elif arg == "--skill":
            only.append(args.pop(0))
        elif arg == "--quiet":
            quiet = True
        else:
            sys.stderr.write(f"harvest: unknown argument {arg}\n")
            return 2

    if not skills_dir:
        sys.stderr.write("harvest: --skills-dir is required\n")
        return 2

    warnings = []

    def warn(message):
        warnings.append(message)
        sys.stderr.write(f"  warning: {message}\n")

    repo_skills = set()
    if os.path.isdir(skills_dir):
        repo_skills = {
            name
            for name in os.listdir(skills_dir)
            if os.path.isdir(os.path.join(skills_dir, name))
        }

    # A skill deployed but absent from skills/ is reported, never created.
    deployed_skills = set()
    for root in targets:
        if not os.path.isdir(root):
            continue
        for name in os.listdir(root):
            if os.path.exists(os.path.join(root, name, "FEEDBACK.jsonl")):
                deployed_skills.add(name)

    if only:
        names = list(only)
    else:
        names = sorted(repo_skills | deployed_skills)

    total_added = 0
    touched = 0
    recommendations = []

    for name in names:
        if name not in repo_skills:
            if name in deployed_skills:
                warn(f"{name}: deployed copies hold traces but {skills_dir}/{name} "
                     "does not exist; skipping (harvest it where the skill lives)")
            continue

        # The same file reached through a symlinked tool directory is the same
        # file; read it once so its own same-ts traces are not reported twice.
        target_files = []
        real_seen = set()
        for root in targets:
            path = os.path.join(root, name, "FEEDBACK.jsonl")
            if not os.path.isfile(path):
                continue
            real = os.path.realpath(path)
            if real in real_seen:
                continue
            real_seen.add(real)
            target_files.append(path)

        repo_file = os.path.join(skills_dir, name, "FEEDBACK.jsonl")
        if not target_files and not os.path.exists(repo_file):
            continue

        added, traces, collisions, collision_ts = harvest_skill(
            name, repo_file, target_files, warn
        )
        if collisions:
            warn(
                f"{name}: {collisions} trace(s) share a ts with a different trace "
                f"(first {collision_ts}); kept as distinct traces"
            )

        config_path = os.path.join(skills_dir, name, "CONFIG.yaml")
        compaction = read_compaction(config_path)
        note = ""
        if compaction is None:
            if added:
                note = "  (no compaction block; iteration_count not set)"
        else:
            since = traces_since(traces, compaction.get("last_compaction"))
            count = len(since)
            write_iteration_count(config_path, count)
            threshold = int(compaction.get("cycle_threshold") or DEFAULT_CYCLE_THRESHOLD)
            bad = len(failing(since))
            note = f"  iteration_count={count}"
            # Both triggers, decided in compaction.py so this script,
            # log-feedback.sh and compact-memo.sh cannot answer differently.
            if recommend(count, threshold, bad):
                recommendations.append((name, reasons(count, threshold, bad)))

        if added:
            total_added += added
            touched += 1
            print(f"  {name}: +{added} trace(s){note}")

    if total_added:
        print(f"Harvested {total_added} trace(s) into {touched} skill(s).")
    elif not quiet:
        print("No new traces; every deployed copy is already home.")

    if recommendations and not quiet:
        print("")
        print("Compaction recommended:")
        for name, why in recommendations:
            print(f"  {name}: {'; '.join(why)}")
            print(f"    scripts/compact-memo.sh skills/{name}/")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
