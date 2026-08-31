#!/usr/bin/env python3
"""Group a skill's traces by the skill version that produced them.

"Did that edit help?" is a question about traces, not about a ledger. Every
trace already names the skill version it ran against, so impact is computed
from FEEDBACK.jsonl on demand and never recorded (CONTEXT.md: Impact). There
is no IMPACT.jsonl and there is not going to be one.

Called by scripts/analyze-feedback.sh --impact, which owns the CLI; this
module owns the grouping so gate-skill.sh can import it and compute a
baseline -- the gate traces per fixture at the previous version -- from the
same code that prints the table.

What the harvested traces actually look like, and what that forces:

  * `version` is whatever the epilogue wrote. Alongside real semver there are
    'unknown', '', '1', '1.0', 'n/a' and traces with no version at all. Those
    are one group, `unversioned`: dropping them would silently shrink a
    skill's history (110 of 478 traces name no version).
  * a quarter of the traces date the run with `date` or `timestamp` instead
    of `ts`, so a timestamp is read from all three, in that order. A trace
    with none sorts last within its group.
  * 105 traces carry no `outcome` at all (they score with `score` or
    `self_assessment`). They are counted in `n` but not in the mean or the
    failing count, and the caller is told how many. Repairing them is the
    epilogue contract's job (format 2.0), not this module's: traces are
    recorded as written.

Failing means outcome 1 or 2, straight from harvest.failing, which is where
CONTEXT.md's definition already lives.
"""

from __future__ import annotations

import os
import re
import sys

try:
    from harvest import failing, read_traces
except ImportError:  # imported from outside scripts/lib
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from harvest import failing, read_traces


UNVERSIONED = "unversioned"
NO_FIXTURE = "(no fixture)"

# A version is a version when it is semver. Everything else -- 'unknown', '1',
# 'n/a', '', missing -- names no release and cannot be compared to one.
SEMVER = re.compile(r"^\d+\.\d+\.\d+")

# Read in this order: the field table says `ts`, the deployed epilogues that
# predate it say `date` or `timestamp`.
TS_FIELDS = ("ts", "date", "timestamp")


# --- reading one trace ----------------------------------------------------


def version_of(trace):
    """The trace's skill version, or `unversioned` when it names none."""
    value = trace.get("version")
    if isinstance(value, str) and SEMVER.match(value.strip()):
        return value.strip()
    return UNVERSIONED


def timestamp_of(trace):
    """The trace's timestamp from `ts`, `date` or `timestamp`; "" when none."""
    for field in TS_FIELDS:
        value = trace.get(field)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def outcome_of(trace):
    """The trace's outcome when it is a usable 1-5 score, else None."""
    value = trace.get("outcome")
    if isinstance(value, bool):
        return None
    if isinstance(value, int) and 1 <= value <= 5:
        return value
    return None


def is_gate(trace):
    """True when a gate run wrote this trace rather than a real run."""
    return bool(trace.get("gate"))


def split_gate(traces):
    """(real traces, gate traces). A gate trace is never a real run."""
    real, gate = [], []
    for trace in traces:
        (gate if is_gate(trace) else real).append(trace)
    return real, gate


# --- grouping -------------------------------------------------------------


def _row(label, traces):
    stamps = sorted(ts for ts in (timestamp_of(t) for t in traces) if ts)
    outcomes = [o for o in (outcome_of(t) for t in traces) if o is not None]
    return {
        "label": label,
        "n": len(traces),
        "scored": len(outcomes),
        "unscored": len(traces) - len(outcomes),
        "mean": (sum(outcomes) / float(len(outcomes))) if outcomes else None,
        "failing": len(failing(traces)),
        "first_ts": stamps[0] if stamps else "",
        "last_ts": stamps[-1] if stamps else "",
        "outcomes": outcomes,
    }


def _by_first_ts(row):
    """Oldest group first; a group nobody dated goes last, then by label."""
    return (1, "", row["label"]) if not row["first_ts"] else (0, row["first_ts"], row["label"])


def group_by_version(traces):
    """{version: row}, oldest version first, non-semver under `unversioned`.

    A row carries label (the version), n, scored, unscored, mean, failing,
    first_ts, last_ts and outcomes. Pass real traces; gate traces are a
    separate population and belong in gate_rows.
    """
    buckets = {}
    for trace in traces:
        buckets.setdefault(version_of(trace), []).append(trace)
    rows = sorted((_row(v, ts) for v, ts in buckets.items()), key=_by_first_ts)
    return dict((row["label"], row) for row in rows)


def gate_rows(traces, fixtures=None, version=None):
    """{fixture: row} over gate traces only -- a baseline, fixture by fixture.

    `version` pins the row to one skill version (the previous one, when the
    caller is building a baseline to compare an edit against); `fixtures`
    limits it to the fixtures that still exist. Row shape matches
    group_by_version, with `version` naming the versions the row covers, so a
    caller can compare per fixture rather than by the mean alone.
    """
    wanted = None if fixtures is None else set(fixtures)
    buckets = {}
    for trace in traces:
        if not is_gate(trace):
            continue
        if version is not None and version_of(trace) != version:
            continue
        name = trace.get("fixture") or NO_FIXTURE
        if wanted is not None and name not in wanted:
            continue
        buckets.setdefault(str(name), []).append(trace)
    rows = sorted((_row(f, ts) for f, ts in buckets.items()), key=_by_first_ts)
    for row in rows:
        row["version"] = ", ".join(
            sorted({version_of(t) for t in buckets[row["label"]]})
        )
    return dict((row["label"], row) for row in rows)


# --- rendering ------------------------------------------------------------


def _table(rows, first_heading, extra=None):
    """Fixed-width rows. `extra` is an optional (heading, key) second column."""
    headings = [first_heading]
    if extra:
        headings.append(extra[0])
    headings += ["n", "mean", "failing", "first trace", "last trace"]

    body = []
    for row in rows:
        cells = [row["label"]]
        if extra:
            cells.append(row.get(extra[1], "") or "")
        cells += [
            str(row["n"]),
            "-" if row["mean"] is None else "%.1f" % row["mean"],
            str(row["failing"]),
            row["first_ts"] or "-",
            row["last_ts"] or "-",
        ]
        body.append(cells)

    widths = [len(h) for h in headings]
    for cells in body:
        for i, cell in enumerate(cells):
            widths[i] = max(widths[i], len(cell))

    # n, mean and failing read as a column of numbers; the rest read as text.
    numeric = set(range(len(headings) - 5, len(headings) - 2))

    def line(cells):
        out = []
        for i, cell in enumerate(cells):
            out.append(cell.rjust(widths[i]) if i in numeric else cell.ljust(widths[i]))
        return "  " + "  ".join(out).rstrip()

    return [line(headings)] + [line(cells) for cells in body]


def render(skill, traces):
    """The lines analyze-feedback.sh --impact prints for one skill."""
    out = ["%s (%d trace(s))" % (skill, len(traces))]
    real, gate = split_gate(traces)

    if not real:
        out.append("  no real traces")
    else:
        rows = list(group_by_version(real).values())
        out += _table(rows, "version")
        unscored = sum(row["unscored"] for row in rows)
        if unscored:
            out.append(
                "  %d of %d real trace(s) carry no outcome (they score with "
                "score/self_assessment);" % (unscored, len(real))
            )
            out.append("  they count in n, not in mean or failing.")

    # Gate traces are a blind run against a fixture, not a run somebody asked
    # for; averaging the two populations together would hide both.
    if gate:
        out.append("")
        out.append("  gate traces")
        out += ["  " + line for line in _table(list(gate_rows(gate).values()),
                                               "fixture", ("version", "version"))]
    return out


# --- entry point ----------------------------------------------------------


def load(skills_dir, skill, warn=None):
    """Every parseable trace in one skill's FEEDBACK.jsonl."""
    if warn is None:
        def warn(message):
            sys.stderr.write("  warning: %s\n" % message)
    path = os.path.join(skills_dir, skill, "FEEDBACK.jsonl")
    if not os.path.isfile(path):
        return []
    return [trace for _, trace in read_traces(path, warn)]


def self_test():
    """Check the grouping against the shapes the harvested traces actually take."""
    traces = [
        {"version": "1.0.0", "outcome": 4, "ts": "2026-01-02T00:00:00Z"},
        {"version": "1.0.0", "outcome": 2, "date": "2026-01-03"},
        {"version": "unknown", "outcome": 5, "timestamp": "2026-01-01"},
        {"version": "", "outcome": 1},
        {"version": "1", "score": 3},
        {"outcome": 5, "ts": "2026-01-04T00:00:00Z"},
        {"version": "1.1.0", "outcome": 5, "ts": "2026-02-01T00:00:00Z",
         "gate": True, "fixture": "tulips"},
        {"version": "1.0.0", "outcome": 2, "ts": "2026-01-05T00:00:00Z",
         "gate": True, "fixture": "tulips"},
    ]
    real, gate = split_gate(traces)
    assert len(real) == 6 and len(gate) == 2, "gate traces are not real traces"

    rows = group_by_version(real)
    assert list(rows) == [UNVERSIONED, "1.0.0"], list(rows)
    assert rows[UNVERSIONED]["n"] == 4, "non-semver versions are grouped, not dropped"
    assert rows[UNVERSIONED]["unscored"] == 1, "a trace scored with `score` is unscored"
    assert rows[UNVERSIONED]["scored"] == 3
    assert abs(rows[UNVERSIONED]["mean"] - 11 / 3.0) < 1e-9
    assert rows[UNVERSIONED]["failing"] == 1
    assert rows[UNVERSIONED]["first_ts"] == "2026-01-01", "timestamp falls back to `timestamp`"
    assert rows["1.0.0"]["last_ts"] == "2026-01-03", "timestamp falls back to `date`"
    assert rows["1.0.0"]["n"] == 2 and rows["1.0.0"]["mean"] == 3.0

    base = gate_rows(gate, version="1.0.0")
    assert list(base) == ["tulips"] and base["tulips"]["outcomes"] == [2], base
    assert gate_rows(gate, fixtures=["nothing"]) == {}
    assert len(gate_rows(gate)) == 1 and gate_rows(gate)["tulips"]["n"] == 2

    print("impact self-test: ok")
    return 0


def main(argv):
    skills_dir = None
    skills = []
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--skills-dir":
            skills_dir = args.pop(0)
        elif arg == "--self-test":
            return self_test()
        elif arg.startswith("-"):
            sys.stderr.write("impact: unknown argument %s\n" % arg)
            return 2
        else:
            skills.append(arg)

    if skills_dir is None:
        skills_dir = os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
            "skills",
        )

    if not os.path.isdir(skills_dir):
        sys.stderr.write("impact: no skills directory at %s\n" % skills_dir)
        return 2

    if not skills:
        skills = sorted(
            name
            for name in os.listdir(skills_dir)
            if os.path.isfile(os.path.join(skills_dir, name, "FEEDBACK.jsonl"))
        )

    printed = 0
    for skill in skills:
        traces = load(skills_dir, skill)
        if not traces:
            if len(skills) == 1:
                print("No traces for skill: %s" % skill)
            continue
        if printed:
            print("")
        for line in render(skill, traces):
            print(line)
        printed += 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
