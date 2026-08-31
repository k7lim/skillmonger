#!/usr/bin/env python3
"""The arithmetic behind a gate run: fixtures, the blind copy, and the verdict.

`scripts/gate-skill.sh` owns the live part -- copying the skill, calling the
runner, piping output to the evaluate script, appending gate traces through
`log-feedback.sh`. Everything it can decide without a model lives here so it
can be tested without one (`python3 scripts/lib/gate.py --self-test`).

The baseline comes from the same `impact.gate_rows` that
`analyze-feedback.sh --impact` prints, so the table a maintainer reads and the
number the gate compares against cannot disagree (CONTEXT.md: Baseline).

Two rules decide a regression (CONTEXT.md: Regression), and they are judged
fixture by fixture before they are judged by the mean:

  * any single fixture more than one point below its baseline, and
  * a mean drop larger than `evaluation.tolerance`.

A third is independent of the baseline: a fixture with a
`<case>.expect.json` naming `min_outcome` regresses when it scores under
that, even on the very first gate run, because that floor is a claim about
the skill rather than about the last run.

Baseline selection is deliberately not "the previous semver". A gate run
happens before the version is bumped as often as after, so the baseline is
the newest gate traces for these fixtures that were already in
FEEDBACK.jsonl when this run started: the previous *version* when there is
one, otherwise the previous *run* at the current version. Either way the
comparison is against something that actually ran, and the label says which.

CONFIG.yaml is read with PyYAML when it is importable and with a two-level
scalar reader otherwise, matching render-epilogue.sh: the gate must not be
the one script in the repo that needs a dependency the others do not.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

try:
    import impact
except ImportError:  # imported from outside scripts/lib
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import impact


FIXTURE_SUFFIX = ".prompt.md"
EXPECT_SUFFIX = ".expect.json"

# The gate scores skills, not prose: only these two modes name a script that
# can be the oracle.
GATEABLE_MODES = ("programmatic", "hybrid")

# `evaluation.runner` is reserved. Today the only runner the gate knows how to
# drive is Claude Code; a skill that names another one is refused rather than
# quietly gated with the wrong tool. `codex exec` was measured as a second
# runner and declined: ADR 0004.
KNOWN_RUNNERS = ("claude",)

MIN_FIXTURES = 3
DEFAULT_TOLERANCE = 0.5

# Placeholders in `evaluation.script_usage` that mean "the skill's output, as a
# file". Anything else in a usage string is an input the gate cannot invent.
FILE_HINTS = ("<output-file>", "<output>", "<file>", "output.md", "$1")


# --- CONFIG.yaml ------------------------------------------------------------


def _yaml_load(path):
    try:
        import yaml
    except ImportError:
        return None
    try:
        with open(path) as handle:
            return yaml.safe_load(handle) or {}
    except Exception:
        return {}


_KEY = re.compile(r"^(\s*)([A-Za-z0-9_.-]+):\s*(.*?)\s*$")


def _scalar_load(path):
    """Two-level scalars from a CONFIG.yaml, without PyYAML.

    Enough for `skill.version` and the `evaluation:` block, which is all the
    gate reads. Nested lists and multi-line scalars come back absent rather
    than wrong.
    """
    data = {}
    top = None
    try:
        with open(path) as handle:
            lines = handle.read().splitlines()
    except OSError:
        return data
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = _KEY.match(line)
        if not match:
            continue
        indent, key, value = match.group(1), match.group(2), match.group(3)
        value = value.split(" #", 1)[0].strip().strip("'\"")
        if not indent:
            top = key
            data[key] = value if value else {}
        elif top and isinstance(data.get(top), dict):
            data[top][key] = value
    return data


def load_config(skill_dir):
    path = os.path.join(skill_dir, "CONFIG.yaml")
    if not os.path.isfile(path):
        return {}
    data = _yaml_load(path)
    if data is None:
        data = _scalar_load(path)
    return data if isinstance(data, dict) else {}


def _get(config, *path, **kw):
    node = config
    for part in path:
        if not isinstance(node, dict):
            return kw.get("default")
        node = node.get(part)
    return kw.get("default") if node is None else node


def _as_bool(value, default):
    if value is None or value == "":
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("1", "true", "yes", "on")


def _as_float(value, default):
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return default


# --- fixtures ---------------------------------------------------------------


def fixtures_dir(skill_dir):
    return os.path.join(skill_dir, "fixtures")


def fixtures(skill_dir):
    """Every `<case>.prompt.md` under `fixtures/`, by case name, sorted."""
    directory = fixtures_dir(skill_dir)
    if not os.path.isdir(directory):
        return []
    return sorted(
        name[: -len(FIXTURE_SUFFIX)]
        for name in os.listdir(directory)
        if name.endswith(FIXTURE_SUFFIX) and not name.startswith(".")
    )


def fixture_prompt(skill_dir, case):
    with open(os.path.join(fixtures_dir(skill_dir), case + FIXTURE_SUFFIX)) as handle:
        return handle.read().strip()


def expectations(skill_dir, cases=None):
    """{case: {"min_outcome": N}} for the fixtures that carry an expect.json."""
    out = {}
    for case in fixtures(skill_dir) if cases is None else cases:
        path = os.path.join(fixtures_dir(skill_dir), case + EXPECT_SUFFIX)
        if not os.path.isfile(path):
            continue
        try:
            with open(path) as handle:
                data = json.load(handle)
        except ValueError as exc:
            raise SystemExit("gate: %s is not JSON (%s)" % (path, exc))
        if isinstance(data, dict) and data.get("min_outcome") is not None:
            out[case] = {"min_outcome": int(data["min_outcome"])}
    return out


# --- the evaluation contract ------------------------------------------------


def evaluate_input_mode(usage):
    """('stdin'|'file', None) or (None, reason) for `evaluation.script_usage`.

    The documented contract is "skill output on stdin or as the first
    argument". A usage string that names anything else -- a project
    directory, a saved report -- describes an input the gate has no way to
    produce, so the gate says so instead of feeding it the wrong thing.
    """
    if not usage:
        return "stdin", None
    parts = usage.split()
    tail = " ".join(parts[1:]).strip() if len(parts) > 1 else ""
    if not tail or tail == "-":
        return "stdin", None
    if any(hint in tail for hint in FILE_HINTS):
        return "file", None
    return None, (
        "evaluation.script_usage names an input the gate cannot supply: %s\n"
        "       The gate can pass the skill's output on stdin or as the first\n"
        "       argument; anything else has to be produced by hand." % usage
    )


def contract(skill_dir):
    """Everything the gate needs from CONFIG.yaml, plus why it may not run.

    `refusal` is None when the skill is gateable and a message otherwise. The
    caller turns that into exit 3; collecting the reasons here keeps the
    refusal wording in one place and testable without a model.
    """
    skill_dir = os.path.abspath(skill_dir)
    name = os.path.basename(skill_dir.rstrip(os.sep))
    config = load_config(skill_dir)

    mode = str(_get(config, "evaluation", "mode", default="") or "").strip()
    script = str(_get(config, "evaluation", "script", default="") or "").strip()
    usage = str(_get(config, "evaluation", "script_usage", default="") or "").strip()
    runner = str(_get(config, "evaluation", "runner", default="") or "").strip()
    emits = _as_bool(_get(config, "evaluation", "script_emits_outcome"), True)
    blind = _as_bool(_get(config, "evaluation", "blind"), True)
    tolerance = _as_float(_get(config, "evaluation", "tolerance"), DEFAULT_TOLERANCE)
    version = str(_get(config, "skill", "version", default="") or "").strip()

    cases = fixtures(skill_dir)
    input_mode, usage_error = evaluate_input_mode(usage)

    # Every reason at once. A maintainer making a skill gateable wants the
    # whole list, not one refusal per run.
    reasons = []
    gateable = mode in GATEABLE_MODES
    if not gateable:
        reasons.append(
            "%s is %s, not %s.\n"
            "    A gate run is scored by the skill's own evaluate script; a skill\n"
            "    with no script has no oracle and is never gated."
            % (name, mode or "format 1 (no evaluation.mode)", " or ".join(GATEABLE_MODES))
        )
    if gateable and runner and runner not in KNOWN_RUNNERS:
        reasons.append(
            "%s declares evaluation.runner: %s.\n"
            "    The gate drives %s only; runner is reserved for later."
            % (name, runner, ", ".join(KNOWN_RUNNERS))
        )
    if gateable and not emits:
        reasons.append(
            "%s declares evaluation.script_emits_outcome: false.\n"
            "    Its evaluate script does not score this skill's own output, so a\n"
            "    gate run has no outcome to compare. Score it by hand instead:\n"
            "      scripts/log-feedback.sh %s --outcome N --note ... --source llm"
            % (name, name)
        )
    if gateable and emits:
        if not script:
            reasons.append(
                "%s declares evaluation.mode: %s but no evaluation.script." % (name, mode))
        elif not os.path.isfile(os.path.join(skill_dir, script)):
            reasons.append("%s: evaluation.script not found: %s" % (name, script))
        elif usage_error:
            reasons.append("%s: %s" % (name, usage_error))
    if len(cases) < MIN_FIXTURES:
        reasons.append(
            "%s has %d fixture(s); the gate needs at least %d.\n"
            "    A fixture is a held-out prompt at\n"
            "      skills/%s/fixtures/<case>%s\n"
            "    with an optional floor beside it at\n"
            "      skills/%s/fixtures/<case>%s   {\"min_outcome\": N}\n"
            "    Seed them from this skill's own harvested prompts."
            % (name, len(cases), MIN_FIXTURES, name, FIXTURE_SUFFIX, name, EXPECT_SUFFIX)
        )
    refusal = None
    if reasons:
        refusal = "%s cannot be gated:\n  - %s" % (name, "\n  - ".join(reasons))

    return {
        "name": name,
        "skill_dir": skill_dir,
        "mode": mode,
        "script": script,
        "script_usage": usage,
        "input_mode": input_mode or "stdin",
        "script_emits_outcome": emits,
        "blind": blind,
        "tolerance": tolerance,
        "runner": runner or KNOWN_RUNNERS[0],
        "version": version or "unknown",
        "fixtures": cases,
        "refusal": refusal,
    }


def run_evaluate(skill_dir, script, input_mode, output_path):
    """Run the skill's evaluate script over one gate run's output.

    Returns its stdout. The evaluate script is the oracle (CONTEXT.md:
    Fixture); the gate never scores the output itself.
    """
    argv = [os.path.join(skill_dir, script)]
    with open(output_path, "rb") as handle:
        if input_mode == "file":
            argv.append(output_path)
            proc = subprocess.run(argv, stdout=subprocess.PIPE, cwd=skill_dir)
        else:
            proc = subprocess.run(argv, stdin=handle, stdout=subprocess.PIPE, cwd=skill_dir)
    if proc.returncode != 0:
        raise SystemExit(
            "gate: %s exited %d on %s" % (script, proc.returncode, output_path)
        )
    return proc.stdout.decode("utf-8", "replace")


# --- the blind copy ---------------------------------------------------------


def strip_on_failure(config_path):
    """Drop `loading.on_failure` from a CONFIG.yaml, line by line.

    Line-based rather than load-and-dump so the copy still reads like the
    skill's own CONFIG: a gate run that reformatted the file would make the
    diff between the copy and the source unreadable when something goes wrong.
    """
    if not os.path.isfile(config_path):
        return False
    with open(config_path) as handle:
        lines = handle.read().splitlines(True)

    out, in_loading, drop_depth, dropped = [], False, None, False
    for line in lines:
        stripped = line.strip()
        top_level = bool(stripped) and not line[:1].isspace()

        if drop_depth is not None:
            # The key's own value may run over several deeper-indented lines.
            if not stripped or _depth(line) > drop_depth:
                continue
            drop_depth = None

        if top_level:
            in_loading = (not stripped.startswith("#")
                          and stripped.split(":", 1)[0] == "loading")

        if in_loading and not top_level:
            match = _KEY.match(line)
            if match and match.group(2) == "on_failure":
                drop_depth, dropped = _depth(line), True
                continue

        out.append(line)

    if dropped:
        with open(config_path, "w") as handle:
            handle.write("".join(out))
    return dropped


def _depth(line):
    return len(line) - len(line.lstrip())


def blind_copy(src, dest, blind=True, skill_md=None):
    """Copy a skill to `dest` and withhold its wiki (ADR 0003).

    Blind means `MEMO.md`, `memo/` and `loading.on_failure` are gone from the
    copy, so the gate scores the skill alone. `skill_md` replaces SKILL.md in
    the copy, which is how `--baseline <sha>` runs an older skill against
    today's references.
    """
    if os.path.exists(dest):
        shutil.rmtree(dest)
    shutil.copytree(src, dest, symlinks=True)
    removed = []
    if blind:
        memo = os.path.join(dest, "MEMO.md")
        if os.path.exists(memo):
            os.remove(memo)
            removed.append("MEMO.md")
        memo_dir = os.path.join(dest, "memo")
        if os.path.isdir(memo_dir):
            shutil.rmtree(memo_dir)
            removed.append("memo/")
        if strip_on_failure(os.path.join(dest, "CONFIG.yaml")):
            removed.append("loading.on_failure")
    if skill_md is not None:
        with open(os.path.join(dest, "SKILL.md"), "w") as handle:
            handle.write(skill_md)
    return removed


# --- the baseline -----------------------------------------------------------


def _chronological(traces):
    return sorted(traces, key=lambda t: (impact.timestamp_of(t) == "", impact.timestamp_of(t)))


def baseline(traces, cases, current_version=None):
    """The gate traces this run is judged against, per fixture.

    Prefers the newest version that is not `current_version`; falls back to
    the current version's own earlier gate traces, because a skill is often
    gated before its version is bumped. `label` says which happened so the
    report never implies a comparison it did not make.
    """
    wanted = set(cases)
    gate_traces = _chronological(
        t for t in traces if impact.is_gate(t) and str(t.get("fixture") or "") in wanted
    )
    if not gate_traces:
        return {"version": None, "label": "none", "outcomes": {}}

    by_version = {}
    for trace in gate_traces:
        by_version.setdefault(impact.version_of(trace), []).append(trace)

    def newest(version):
        stamps = [impact.timestamp_of(t) for t in by_version[version]]
        return max(stamps) if stamps else ""

    ordered = sorted(by_version, key=lambda v: (newest(v), v), reverse=True)
    others = [v for v in ordered if v != current_version]
    if others:
        chosen, label = others[0], "version %s" % others[0]
    else:
        chosen, label = ordered[0], "previous gate run at %s" % ordered[0]

    rows = impact.gate_rows(gate_traces, fixtures=cases, version=chosen)
    outcomes = {}
    for case, row in rows.items():
        if row["outcomes"]:
            outcomes[case] = row["outcomes"][-1]
    return {"version": chosen, "label": label, "outcomes": outcomes}


# --- the verdict ------------------------------------------------------------


def _mean(values):
    return (sum(values) / float(len(values))) if values else None


def compare(payload):
    """(report lines, regressed) for one gate run against its baseline."""
    cases = sorted(payload["current"])
    current = payload["current"]
    base = payload.get("baseline") or {}
    expect = payload.get("expect") or {}
    tolerance = float(payload.get("tolerance", DEFAULT_TOLERANCE))
    label = payload.get("baseline_label") or "none"

    reasons = []
    rows = []
    for case in cases:
        now = current[case]
        was = base.get(case)
        delta = "-" if was is None else "%+d" % (now - was)
        floor = expect.get(case, {}).get("min_outcome")
        verdict = "ok"
        if was is not None and now < was - 1:
            verdict = "REGRESSION"
            reasons.append(
                "%s: %d, %d below its baseline of %d (more than one point)"
                % (case, now, was - now, was)
            )
        if floor is not None and now < floor:
            verdict = "REGRESSION"
            reasons.append(
                "%s: %d, under the %s floor of %d"
                % (case, now, case + EXPECT_SUFFIX, floor)
            )
        rows.append([case, str(now), "-" if was is None else str(was), delta,
                     "-" if floor is None else str(floor), verdict])

    shared = [c for c in cases if c in base]
    mean_now = _mean([current[c] for c in shared])
    mean_was = _mean([base[c] for c in shared])
    lines = ["  baseline: %s" % label]
    headings = ["fixture", "now", "base", "delta", "min", ""]
    widths = [max(len(headings[i]), *(len(r[i]) for r in rows)) for i in range(len(headings))] \
        if rows else [len(h) for h in headings]

    def render(cells):
        return "  " + "  ".join(c.ljust(widths[i]) for i, c in enumerate(cells)).rstrip()

    lines.append(render(headings))
    for row in rows:
        lines.append(render(row))

    if mean_now is not None and mean_was is not None:
        lines.append("  mean over %d shared fixture(s): %.2f -> %.2f (tolerance %.2f)"
                     % (len(shared), mean_was, mean_now, tolerance))
        if mean_was - mean_now > tolerance:
            reasons.append(
                "mean fell %.2f (%.2f -> %.2f), beyond the %.2f tolerance"
                % (mean_was - mean_now, mean_was, mean_now, tolerance)
            )
    elif not base:
        lines.append("  no baseline; these traces are the baseline")

    if reasons:
        lines.append("")
        lines.append("  REGRESSION:")
        for reason in reasons:
            lines.append("    - %s" % reason)
        revert = payload.get("revert")
        if revert:
            lines.append("")
            lines.append("  The gate never reverts. To put the previous SKILL.md back:")
            lines.append("    %s" % revert)
    return lines, bool(reasons)


# --- CLI --------------------------------------------------------------------


def _shell_quote(value):
    return "'" + str(value).replace("'", "'\\''") + "'"


def cmd_config(args):
    skill_dir = args.pop(0)
    shell = "--shell" in args
    data = contract(skill_dir)
    if not shell:
        print(json.dumps(data, indent=2, sort_keys=True))
        return 0
    for key in ("name", "mode", "script", "script_usage", "input_mode",
                "blind", "tolerance", "runner", "version", "refusal"):
        value = data[key]
        if isinstance(value, bool):
            value = "true" if value else "false"
        print("GATE_%s=%s" % (key.upper(), _shell_quote("" if value is None else value)))
    print("GATE_FIXTURES=%s" % _shell_quote(" ".join(data["fixtures"])))
    return 0


def cmd_version(args):
    """skill.version out of any directory holding a CONFIG.yaml.

    Used for `--baseline <sha>`, whose CONFIG.yaml is checked out to a temp
    directory: the gate traces from that run must name the version that
    actually produced them, not today's.
    """
    version = _get(load_config(args[0]), "skill", "version", default="")
    print(str(version).strip() or "unknown")
    return 0


def cmd_fixtures(args):
    for case in fixtures(args[0]):
        print(case)
    return 0


def cmd_prompt(args):
    """The fixture's prompt, whole, or flattened to one truncated line.

    Truncation happens here rather than in `head -c | tr` because a fixture is
    prose: cutting bytes lands mid-character on the first em dash, and BSD tr
    then refuses the line outright.
    """
    text = fixture_prompt(args[0], args[1])
    if "--truncate" in args:
        limit = int(args[args.index("--truncate") + 1])
        text = " ".join(text.split())
        if len(text) > limit:
            text = text[: limit - 3].rstrip() + "..."
        print(text)
    else:
        sys.stdout.write(text)
    return 0


def cmd_blind(args):
    src, dest = args[0], args[1]
    blind = "--no-blind" not in args
    skill_md = None
    if "--skill-md" in args:
        with open(args[args.index("--skill-md") + 1]) as handle:
            skill_md = handle.read()
    for item in blind_copy(src, dest, blind=blind, skill_md=skill_md):
        print(item)
    return 0


def cmd_baseline(args):
    skills_dir, skill = args[0], args[1]
    cases, version = [], None
    rest = args[2:]
    while rest:
        flag = rest.pop(0)
        if flag == "--fixtures":
            cases = rest.pop(0).split()
        elif flag == "--current-version":
            version = rest.pop(0)
        else:
            raise SystemExit("gate baseline: unknown argument %s" % flag)
    traces = impact.load(skills_dir, skill)
    print(json.dumps(baseline(traces, cases, current_version=version)))
    return 0


def cmd_evaluate(args):
    skill_dir, output_path = args[0], args[1]
    data = contract(skill_dir)
    sys.stdout.write(
        run_evaluate(skill_dir, data["script"], data["input_mode"], output_path)
    )
    return 0


def cmd_expect(args):
    print(json.dumps(expectations(args[0])))
    return 0


def cmd_compare(args):
    payload = json.load(sys.stdin)
    lines, regressed = compare(payload)
    for line in lines:
        print(line)
    return 1 if regressed else 0


def self_test():
    import tempfile

    # --- the evaluation contract, refusals included ---
    root = tempfile.mkdtemp()
    skill = os.path.join(root, "example-skill")
    os.makedirs(os.path.join(skill, "scripts"))
    os.makedirs(os.path.join(skill, "fixtures"))
    os.makedirs(os.path.join(skill, "memo", "patterns"))
    with open(os.path.join(skill, "scripts", "evaluate.sh"), "w") as handle:
        handle.write("#!/bin/bash\ncat >/dev/null\necho '{\"outcome\":4}'\n")
    os.chmod(os.path.join(skill, "scripts", "evaluate.sh"), 0o755)
    with open(os.path.join(skill, "MEMO.md"), "w") as handle:
        handle.write("# wiki\n")
    with open(os.path.join(skill, "memo", "patterns", "p.md"), "w") as handle:
        handle.write("pattern\n")
    with open(os.path.join(skill, "SKILL.md"), "w") as handle:
        handle.write("---\nname: example-skill\ndescription: x\n---\n\nbody\n")
    config = (
        "skill:\n  name: example-skill\n  version: 1.2.0\n  format: 2\n"
        "loading:\n  primary: SKILL.md\n  on_failure: MEMO.md\n"
        "  always_load:\n    - CONFIG.yaml\n"
        "evaluation:\n  mode: programmatic\n  script: scripts/evaluate.sh\n"
        "  blind: true\n  tolerance: 0.5\n"
    )
    with open(os.path.join(skill, "CONFIG.yaml"), "w") as handle:
        handle.write(config)

    data = contract(skill)
    assert data["version"] == "1.2.0", data["version"]
    assert data["tolerance"] == 0.5 and data["blind"] is True
    assert data["runner"] == "claude", data["runner"]
    assert "fixtures/<case>.prompt.md" in data["refusal"], data["refusal"]
    assert "0 fixture(s)" in data["refusal"], data["refusal"]

    for case in ("alpha", "beta", "gamma"):
        with open(os.path.join(skill, "fixtures", case + FIXTURE_SUFFIX), "w") as handle:
            handle.write("prompt for %s\n" % case)
    assert fixtures(skill) == ["alpha", "beta", "gamma"], fixtures(skill)
    assert fixture_prompt(skill, "beta") == "prompt for beta"
    assert contract(skill)["refusal"] is None, contract(skill)["refusal"]

    with open(os.path.join(skill, "fixtures", "alpha" + EXPECT_SUFFIX), "w") as handle:
        handle.write('{"min_outcome": 4}\n')
    assert expectations(skill) == {"alpha": {"min_outcome": 4}}, expectations(skill)

    # The three refusals a fully-fixtured skill can still earn.
    def reword(extra):
        with open(os.path.join(skill, "CONFIG.yaml"), "w") as handle:
            handle.write(config + extra)
        return contract(skill)["refusal"] or ""

    assert "script_emits_outcome" in reword("  script_emits_outcome: false\n")
    assert "runner: codex" in reword("  runner: codex\n")
    assert "cannot supply" in reword("  script_usage: scripts/evaluate.sh <project-dir>\n")
    reword("")
    assert contract(skill)["refusal"] is None

    # --- the blind copy ---
    dest = os.path.join(root, "blind")
    removed = blind_copy(skill, dest)
    assert sorted(removed) == ["MEMO.md", "loading.on_failure", "memo/"], removed
    assert not os.path.exists(os.path.join(dest, "MEMO.md"))
    assert not os.path.exists(os.path.join(dest, "memo"))
    copied = open(os.path.join(dest, "CONFIG.yaml")).read()
    assert "on_failure" not in copied, copied
    assert "primary: SKILL.md" in copied and "always_load" in copied, copied
    assert "version: 1.2.0" in copied, "the rest of CONFIG survives the strip"
    assert os.path.exists(os.path.join(skill, "MEMO.md")), "the source is never touched"

    sighted = blind_copy(skill, os.path.join(root, "sighted"), blind=False)
    assert sighted == [] and os.path.exists(os.path.join(root, "sighted", "MEMO.md"))

    swapped = blind_copy(skill, os.path.join(root, "old"), skill_md="---\nold\n---\n")
    assert swapped and open(os.path.join(root, "old", "SKILL.md")).read() == "---\nold\n---\n"

    # --- script_usage ---
    assert evaluate_input_mode("") == ("stdin", None)
    assert evaluate_input_mode("scripts/evaluate.sh") == ("stdin", None)
    assert evaluate_input_mode("scripts/evaluate.sh -") == ("stdin", None)
    assert evaluate_input_mode("scripts/evaluate.py <output-file>") == ("file", None)
    mode, reason = evaluate_input_mode("scripts/evaluate.sh <project-dir>")
    assert mode is None and "cannot supply" in reason, reason

    # --- the baseline ---
    cases = ["alpha", "beta", "gamma"]
    traces = [
        # alpha ran twice at 1.0.0; the later run is the baseline.
        {"version": "1.0.0", "outcome": 2, "ts": "2026-01-01T00:00:00Z", "gate": True,
         "fixture": "alpha"},
        {"version": "1.0.0", "outcome": 5, "ts": "2026-01-01T00:00:30Z", "gate": True,
         "fixture": "alpha"},
        {"version": "1.0.0", "outcome": 4, "ts": "2026-01-01T00:01:00Z", "gate": True,
         "fixture": "beta"},
        {"version": "1.0.0", "outcome": 3, "ts": "2026-01-01T00:02:00Z", "gate": True,
         "fixture": "gamma"},
        {"version": "1.0.0", "outcome": 1, "ts": "2026-01-01T00:03:00Z", "prompt": "real"},
    ]
    base = baseline(traces, cases, current_version="1.2.0")
    assert base["version"] == "1.0.0" and base["label"] == "version 1.0.0", base
    assert base["outcomes"] == {"alpha": 5, "beta": 4, "gamma": 3}, base["outcomes"]

    # A gate before the version bump compares against the previous run.
    same = baseline(traces, cases, current_version="1.0.0")
    assert same["label"] == "previous gate run at 1.0.0", same["label"]
    assert same["outcomes"]["alpha"] == 5, "the newest trace per fixture wins"

    assert baseline([], cases, current_version="1.0.0") == {
        "version": None, "label": "none", "outcomes": {}}
    assert baseline(traces, ["delta"])["outcomes"] == {}, "fixtures that no longer exist"

    # --- the verdict ---
    lines, bad = compare({"current": {"alpha": 5, "beta": 4, "gamma": 3},
                          "baseline": {}, "tolerance": 0.5})
    assert not bad and any("no baseline" in line for line in lines), lines

    lines, bad = compare({"current": {"alpha": 5, "beta": 4, "gamma": 3},
                          "baseline": base["outcomes"], "baseline_label": base["label"],
                          "tolerance": 0.5})
    assert not bad, lines

    # One fixture two points down is a regression even when the mean holds.
    lines, bad = compare({"current": {"alpha": 3, "beta": 5, "gamma": 5},
                          "baseline": {"alpha": 5, "beta": 4, "gamma": 3},
                          "tolerance": 0.5, "revert": "git checkout abc -- x"})
    assert bad and any("more than one point" in line for line in lines), lines
    assert any("git checkout abc -- x" in line for line in lines), lines

    # One point down on every fixture: no single fixture trips, the mean does.
    lines, bad = compare({"current": {"alpha": 4, "beta": 3, "gamma": 2},
                          "baseline": {"alpha": 5, "beta": 4, "gamma": 3},
                          "tolerance": 0.5})
    assert bad and any("mean fell" in line for line in lines), lines

    lines, bad = compare({"current": {"alpha": 4, "beta": 3, "gamma": 2},
                          "baseline": {"alpha": 5, "beta": 4, "gamma": 3},
                          "tolerance": 1.0})
    assert not bad, "a tolerance of 1.0 absorbs a one-point drift"

    # The floor is a claim about the skill, so it bites without a baseline.
    lines, bad = compare({"current": {"alpha": 3}, "baseline": {},
                          "expect": {"alpha": {"min_outcome": 4}}, "tolerance": 0.5})
    assert bad and any("floor of 4" in line for line in lines), lines

    shutil.rmtree(root)
    print("gate self-test: ok")
    return 0


COMMANDS = {
    "config": cmd_config,
    "version": cmd_version,
    "fixtures": cmd_fixtures,
    "prompt": cmd_prompt,
    "blind": cmd_blind,
    "baseline": cmd_baseline,
    "evaluate": cmd_evaluate,
    "expect": cmd_expect,
    "compare": cmd_compare,
}


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        sys.stderr.write(
            "Usage: gate.py <%s> ...\n       gate.py --self-test\n"
            % "|".join(sorted(COMMANDS))
        )
        return 2
    if argv[0] == "--self-test":
        return self_test()
    command = COMMANDS.get(argv[0])
    if command is None:
        sys.stderr.write("gate.py: unknown command %s\n" % argv[0])
        return 2
    return command(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
