# Skill File Format Reference

This document describes the file format for skillmonger skills.

## Format version

`skill.format` is an integer under `skill:` in `CONFIG.yaml`. It versions the
**skill format** — the contract every skill in this repo follows: which files a
skill has, what its epilogue does, what its scripts emit.

```yaml
skill:
  name: my-skill
  format: 1
```

**Missing means 1.** Skills written before the field existed are format 1 and
need no edit. `scripts/validate-skill.sh` reads the field and errors on any
value it does not know; the repo is tagged `format-N.M` at each step of the
ladder, so a skill copied out of the repo carries the contract its epilogue
follows.

Do not confuse it with two neighbouring numbers:

| Number | Lives in | Means |
|--------|----------|-------|
| `skill.format` | `CONFIG.yaml` | The contract this skill follows. One integer for the whole repo. |
| `skill.version` | `CONFIG.yaml` | This skill's own semver. Bumped when its behaviour changes. Says nothing about the format. |
| `schema_version` | each `FEEDBACK.jsonl` line | The trace record shape. Always 1. |

### Format 1

Format 1 is the contract every skill was written against before the field
existed:

- **Quad-file layout:** `SKILL.md` (required), `CONFIG.yaml`, `MEMO.md`, and an
  append-only `FEEDBACK.jsonl` created on first use.
- **Hand-appended epilogue.** Each `SKILL.md` ends with an `## After Execution`
  section written by hand for that skill. There is no renderer, so the wording,
  the heading, and the JSON example drift from skill to skill.
- The epilogue tells the agent to append one trace to `FEEDBACK.jsonl` and then
  to hand-increment `compaction.iteration_count` in `CONFIG.yaml`.
- Trace fields are the seven below plus `schema_version`; `source` is documented
  as `script | llm | user` but nothing enforces it.
- Evaluation mode is implied by whether `scripts/evaluate*` happens to exist, not
  declared anywhere.

### Format 2

Format 2 is a breaking change to the epilogue contract. The quad-file layout is
unchanged; what a skill says at the end of `SKILL.md` is not.

- **The epilogue is rendered, not written.** `scripts/render-epilogue.sh
  skills/<name>/` prints it from `CONFIG.yaml`, so all skills say the same thing
  in the same words. Editing an epilogue by hand means editing the renderer or
  the skill's question, not the file.
- **No `iteration_count` instruction.** A run appends a trace and nothing else;
  `scripts/harvest-feedback.sh` derives `compaction.iteration_count` from the
  traces it brings home (ADR 0002). The word does not appear in a format-2
  epilogue.
- **The trace still goes into the skill's own directory** — the deployed copy
  the agent is running, not this repo. A deployed copy on SRT or Pi cannot reach
  `scripts/log-feedback.sh`, so no epilogue references it. `log-feedback.sh`
  remains for in-repo use (gate runs, manual logging).
- **`source` is `script`, `llm` or `user`.** Nothing else. `hybrid` and `self`
  are not sources.
- **Evaluation is declared.** `evaluation.mode` says how the skill is scored
  instead of leaving it to be inferred from a filename.

Migrate a format-1 skill with `scripts/migrate-format-2.sh [--dry-run]
skills/<name>/`. It lifts the skill's own question out of the old epilogue,
renders the new one, and writes the CONFIG keys below. It is idempotent: a skill
already at format 2 is left alone, so hand fixes survive a re-run.

It treats the epilogue as a *section* — `## After Execution` to the next `## `
heading or end of file — cuts that section out, and appends the rendered
epilogue at end of file, so every `SKILL.md` ends with its epilogue and any
section that used to follow the old one survives. A `SKILL.md` with no
`## After Execution` heading is named and skipped with a non-zero exit rather
than gaining a second epilogue.

It derives `evaluation.mode` from what the skill already has: **hybrid** when
an evaluate script exists *and* the old epilogue carried a question of its own,
**programmatic** when the script exists and there was no question, and
**qualitative** otherwise. A mode already declared in `CONFIG.yaml` wins. The
hybrid default exists because most skills with an evaluate script also ask the
user something, and flattening them to programmatic would throw that question
away. Prose *about* the evaluator reads as a question to the migrator, so a
skill that documents its evaluator at length lands on hybrid and wants a hand
correction to programmatic.

#### The evaluation block

```yaml
skill:
  format: 2
evaluation:
  mode: programmatic     # programmatic | qualitative | delayed | hybrid
  script: scripts/evaluate.sh   # required for programmatic and hybrid
  blind: true            # gate runs withhold the wiki: MEMO.md and memo/ (ADR 0003)
  tolerance: 0.5         # mean-drop tolerance before a run counts as a regression
  runner: claude         # reserved; codex later
  script_emits_outcome: true    # optional, default true
  script_usage: scripts/evaluate.sh <project-dir>   # optional
```

| Mode | Epilogue |
|------|----------|
| `programmatic` | Run `evaluation.script`, copy its `outcome`, `note` and `checks` into the trace, `source: script`. |
| `qualitative` | Ask the skill's own question, then log `source: llm` (or `user` when the user answered). |
| `delayed` | Do not score at execution time; come back when ground truth exists and log `source: user`. |
| `hybrid` | The script part, then the question. Two traces, one per source. |

`script_emits_outcome: false` marks an evaluator whose JSON carries no `outcome`
this skill can be scored by — writing-voice-coach's `evaluate.py` scores the text
the user brought in, not the critique the skill produced. The rendered epilogue
then runs the script for evidence and routes the score to self-assessment.

`script_usage` overrides the command line the epilogue shows. The documented
contract is "skill output on stdin or as the first argument"; an evaluator that
takes something else (a project directory, a saved JSON file) says so here
rather than letting the epilogue state something untrue.

`validate-skill.sh` under format 2 requires `evaluation.mode` to be one of the
four, and for `programmatic` and `hybrid` requires `evaluation.script` to exist
and be executable.

## Directory Structure

```
skills/my-skill/
├── SKILL.md              # Core instructions (required)
├── CONFIG.yaml           # Metadata & triggers (recommended)
├── MEMO.md               # Edge cases log (recommended)
├── FEEDBACK.jsonl        # Execution feedback log (auto-created)
├── memo/                 # Wiki overflow (created only by --overflow)
│   └── patterns/
│       └── <slug>.md     # One pattern MEMO.md outgrew
├── references/           # Supporting docs (optional)
├── fixtures/             # Held-out prompts for gate runs (programmatic skills)
│   ├── <case>.prompt.md  # The prompt, whole file, nothing else
│   └── <case>.expect.json# Optional floor: {"min_outcome": N}
└── scripts/              # Deterministic helpers (optional)
    ├── evaluate.sh       # Post-execution scoring (optional)
    └── check-prereqs.sh  # Prerequisite verification (optional)
```

`fixtures/` is skillmonger furniture: adopted skills never inherit one from
upstream, and `scripts/lib/upstream.py` classifies the whole directory as
`ours` so it is never reported as drift.

## SKILL.md (Required)

The core instructions file. Must start with YAML frontmatter.

```markdown
---
name: my-skill
description: What this skill does AND when to use it. Max 1024 chars.
---

# My Skill

[Role description. Instructions. Workflow. Examples.]

---

## After Execution

[Feedback epilogue - see Feedback section below]
```

**Frontmatter requirements:**

| Field | Constraints |
|-------|-------------|
| `name` | Lowercase, hyphens, numbers only. Max 64 chars. No leading/trailing/consecutive hyphens. Must match directory name. |
| `description` | Max 1024 chars. Describe what it does AND when to use it. |

**Size guidance:** Keep under 500 lines / 5000 words. Move details to `references/`.

## CONFIG.yaml (Recommended)

Extended metadata for the tri-file system.

```yaml
skill:
  name: my-skill
  version: 1.0.0
  created: 2026-01-14
  updated: 2026-01-14
  author: your-name

triggers:
  phrases:
    - "phrase that triggers this skill"
  keywords:
    - keyword1

dependencies:
  tools:
    - WebSearch  # if needed

loading:
  primary: SKILL.md
  on_failure: MEMO.md
  always_load:
    - CONFIG.yaml

compaction:
  cycle_threshold: 15
  last_compaction: null
  iteration_count: 0

budget:
  metadata_max: 100
  skill_max: 5000
  memo_max: 2000
```

**Compaction fields:**
- `cycle_threshold`: Number of traces since `last_compaction` before compaction is recommended (default 15)
- `iteration_count`: Traces since `last_compaction`. Derived by `harvest-feedback.sh`; incremented by `log-feedback.sh` between harvests.
- `last_compaction`: Date of last compaction. Setting it is what resets the count.

Compaction is recommended when `iteration_count >= cycle_threshold` **or**
three or more failing traces (outcome 1 or 2) have arrived since
`last_compaction`. The second rule needs no CONFIG field; it is computed from
the traces. `log-feedback.sh`, `harvest-feedback.sh` and `compact-memo.sh`
all decide it in `scripts/lib/compaction.py`, so they cannot disagree.

**Budget fields:** advisory ceilings, in words.
- `metadata_max`: the SKILL.md frontmatter an agent loads before deciding to run the skill
- `skill_max`: SKILL.md itself; `validate-skill.sh` warns above 5000 words
- `memo_max`: MEMO.md. Above it, `compact-memo.sh` offers wiki overflow
  (below). The block is optional and ten skills omit it; a skill with no
  `budget.memo_max` is measured against the default **2000**, which is also
  the value every scaffold writes.

## MEMO.md (Recommended)

Edge cases and learnings. Loaded on failure or when historical context is needed.

```markdown
# my-skill - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues.

## Edge Cases Log

### [Descriptive Title]

**Issue:** [What went wrong]
**Resolution:** [How to handle it]

---

## Learnings (Graduated from Past Iterations)

_Patterns will graduate from iterations._

---

## Known Failure Patterns

_None logged yet._

---

## Iteration Log

| Date | Version | Change Type | Description | Patterns |
|------|---------|-------------|-------------|----------|
| 2026-01-14 | 1.0.0 | Initial | Skill created | - |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
```

### Pattern entries

An entry in the log is a **pattern**: one root-caused recurring failure or
strategy (CONTEXT.md). Since format 1.2 a pattern has a fixed layout:

```markdown
### <slug>: short title
- status: open | graduated (vX.Y.Z) | purged
- root cause: one sentence
- evidence: FEEDBACK ts, ts, ... (or "manual")
- workaround: what the agent should do now
- skill change: what SKILL.md should say if this graduates (optional)
```

- `<slug>` is lowercase-with-hyphens and stable. It is the name the Iteration
  Log's `Patterns` column uses when the pattern graduates, so it is the
  provenance of a skill edit.
- `evidence` cites the traces the pattern was derived from, by timestamp. Not
  every trace carries `ts` — deployed copies also date a run with `date` or
  `timestamp` — so cite whichever timestamp field the trace has, quoted as
  written. A pattern nobody has traces for cites `manual`; a pattern with no
  evidence at all is a hypothesis, not a pattern.
- `status: graduated (vX.Y.Z)` names the version whose SKILL.md absorbed the
  workaround. `purged` means the skill no longer needs it.
- A pattern has exactly one **owner skill**: the one whose mechanism it
  describes. A dependent skill points at the owner's pattern instead of
  copying it.

Old free-form entries stay valid. Nothing rewrites existing wikis; entries
convert as a compaction touches them, and `scripts/compact-memo.sh` flags the
ones still missing `status` or `evidence`.

### Wiki overflow

Since format 2.1 the wiki is one file until it outgrows one.
`scripts/compact-memo.sh` measures it on every run and, when MEMO.md is over
that skill's `budget.memo_max` words **or** holds more than 12 `### ` entries,
prints the command that spills it:

```bash
scripts/compact-memo.sh skills/<name>/ --overflow
```

Nothing is written without that flag, and the flag does nothing while the wiki
is inside both limits: lower `budget.memo_max` if a smaller wiki has already
outgrown one file. Overflow is per skill and on demand; no skill is migrated in
bulk, and no wiki in the repo is over either limit today.

`--overflow` moves each `### ` entry -- the heading and its body, up to the
next `### `, `## ` or `# ` heading or EOF -- into `memo/patterns/<slug>.md`
verbatim, and leaves one index line where the entry was:

```markdown
- [<slug>](memo/patterns/<slug>.md): <status>, <short title>
```

The slug is the entry's own, taken from a `### <slug>: short title` heading. A
free-form entry has no slug, so one is derived from the heading text
(lowercase-with-hyphens) and the run names every slug it derived -- rename
those while nothing cites them yet. The status is the entry's `- status:`
line, or `open` when it has none. Anything that is not a `### ` entry stays in
MEMO.md untouched: `## ` sections, their prose, the Iteration Log, and the
`---` rules that separate sections.

The move refuses (exit 2) rather than overwrite, when a
`memo/patterns/<slug>.md` already exists with different content or when two
entries slug the same. It is otherwise idempotent: a second `--overflow` finds
no `### ` entries left and writes nothing.

MEMO.md stays the file `loading.on_failure` names, so a failing run still loads
one file and follows one link, and CONFIG.yaml is not touched. A gate run under
`evaluation.blind` withholds `memo/` exactly as it withholds MEMO.md, so
overflowing a wiki cannot change what a gate measures (ADR 0003). The rest of
the tooling already knows the directory: `validate-skill.sh` reports it as
optional, `ship-skill.sh`
carries it, `sync-skill-back.sh` diffs `memo/**/*.md` file by file, and for an
adopted skill every path under `memo/` classifies as `ours` -- a wiki is
skillmonger's, never upstream's.

## FEEDBACK.jsonl (Auto-created)

Append-only log of execution outcomes. One JSON object per line.

```json
{"ts":"2026-01-26T14:30:00Z","skill":"my-skill","version":"1.0.0","prompt":"user's request","outcome":4,"note":"","source":"llm","schema_version":1}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `ts` | string | UTC ISO 8601 timestamp |
| `skill` | string | Skill name |
| `version` | string | Skill version from CONFIG.yaml |
| `prompt` | string | The user's original request |
| `outcome` | int 1-5 | 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent |
| `note` | string | Brief note (especially useful for scores != 4) |
| `source` | string | `script` (deterministic), `llm` (self-assessment), or `user` (manual) |
| `schema_version` | int | Always 1. It versions the record shape, not the skill format; format 2 adds optional fields rather than changing the shape. |

**Optional trace fields** (format 2). Every reader tolerates fields it does not
know, so these are added where they are known and omitted otherwise:

| Field | Type | Description |
|-------|------|-------------|
| `session` | string | Id of the session this run came from, when the agent knows it. Points at the transcript; never contains it. |
| `checks` | object | The evaluate script's `checks` object, copied through unchanged. |
| `gate` | bool | `true` when the trace came from a gate run rather than a real run. |
| `fixture` | string | The fixture the gate run used. Only meaningful with `gate: true`. |

Optional. Written only when known; every reader tolerates their absence, and
`schema_version` stays 1 because nothing above changed meaning.

| Field | Type | Description |
|-------|------|-------------|
| `session` | string | Id of the session the run came from, for `pj` to resolve |
| `checks` | object \| array | The evaluate script's `checks`, copied verbatim |
| `gate` | bool | `true` when a gate run wrote the trace instead of a real run |
| `fixture` | string | The fixture a gate run used |

`scripts/log-feedback.sh` writes them: `--session ID`, `--gate`,
`--fixture NAME`, and `--from-evaluate [file|-]`, which takes `outcome`,
`note` and `checks` straight from an evaluate script's JSON and records the
trace with `source: script`. An explicit `--outcome` or `--note` overrides the
file. An evaluate script that emits no `outcome` is not scoring the run, so
`--from-evaluate` exits 2 and points at the skill's self-assessment path
instead of inventing a score. These flags are for in-repo use -- gate runs and
manual logging; a deployed copy's epilogue still appends its own line
(ADR 0002).

**Harvest:** agents run the *deployed copy* of a skill, and its epilogue
appends the trace there, not here — deployed copies cannot reach this repo
(ADR 0002). `scripts/harvest-feedback.sh [skill]` unions every deployed copy's
FEEDBACK.jsonl into `skills/<name>/FEEDBACK.jsonl`: existing lines are never
rewritten, new ones are appended in timestamp order (a trace is new when its
(skill, ts, content digest) key is unseen, so undated and same-ts runs survive), `source` is normalised
(`self` -> `llm`, `hybrid` -> `script` when the trace carries `checks` else
`llm`, missing -> `llm`), `version` is left as written, and stays as written afterwards: 142 of the 520 traces harvested on 2026-08-30 carry no semver (`analyze-feedback.sh --impact` groups them under `unversioned`), but back-filling would rewrite existing lines, which the append-only rule forbids, and the deployed copy's version at run time is not derivable from this repo's history, so a git-derived value would record a guess as a fact, and unparseable lines
are skipped with a warning. It is idempotent, and `deploy-skill.sh` runs it
before it removes a deployed copy. Harvest also derives
`compaction.iteration_count` from the traces since `last_compaction`, so
nothing has to increment it by hand.

**Impact:** `scripts/analyze-feedback.sh --impact [skill]` answers "did that
edit help?" by grouping a skill's traces by the `version` that produced them --
one row per version with n, mean outcome, failing count (outcome 1-2) and the
first and last trace, oldest version first. Impact is always computed from the
traces and never recorded; there is no impact file. Gate traces (`gate: true`)
are listed separately, per fixture, because a blind run against a fixture is
not a run somebody asked for. Traces whose `version` is not semver (`unknown`,
`1`, `n/a`, empty, missing) are grouped under `unversioned` rather than
dropped, a timestamp is read from `ts`, then `date`, then `timestamp`, and a
trace carrying no `outcome` counts in n but not in the mean. The grouping lives
in `scripts/lib/impact.py` (`group_by_version`, `gate_rows`), which
`python3 scripts/lib/impact.py --self-test` exercises.

**Source reliability:** `script` > `user` > `llm`. Script ratings are ground truth. LLM ratings bias toward 4-5 but relative trends across versions are valid. User ratings are authoritative overrides.

**Feedback patterns:** Not all skills can be scored the same way. Choose the pattern that fits:
- **Programmatic:** An evaluate script verifies output (structural transforms, data formatting). Preferred when possible.
- **Qualitative:** Epilogue asks the user a skill-specific question or alternates between user and LLM assessment.
- **Delayed:** Don't log at execution time. Come back when ground truth is available and log with `--source user`.
- **Hybrid:** Evaluate script for verifiable parts, qualitative ask for the rest.

## Gate runs

```bash
scripts/gate-skill.sh skills/<name>/ [--baseline <sha>] [--dry-run]
```

A **gate run** re-runs a skill live against every held-out prompt in its
`fixtures/`, scores each run with the skill's own evaluate script, and compares
the scores to the **baseline** — the gate run before this edit. It answers one
question: did that edit to `SKILL.md` make the skill worse? Nothing else in the
loop asks it, because harvested traces arrive weeks apart from runs nobody
controlled.

**Which skills are gated.** `evaluation.mode` must be `programmatic` or
`hybrid`: the evaluate script is the oracle, so a skill without one has nothing
to be scored by. `fixtures/` must hold at least three `*.prompt.md`. Two more
refusals are declarations the skill already made: `script_emits_outcome: false`
(the evaluator scores something other than this skill's output, so there is no
number to compare) and `evaluation.runner` set to anything but `claude`, which
is reserved. Each is exit 3 with every reason listed at once. Qualitative skills
are never gated.

**Fixtures are inputs only.** A `<case>.prompt.md` is the prompt and nothing
else: the whole file, whitespace trimmed. There is no expected output beside it,
because the evaluate script is the judge (CONTEXT.md: **Fixture**). Seed them
from the skill's own harvested `prompt` fields plus hand-written ones, one per
kind of request the skill actually gets. An optional `<case>.expect.json`
`{"min_outcome": N}` sets a floor for that fixture.

**Blind.** The copy the runner loads has no `MEMO.md`, no `memo/` and no
`loading.on_failure`, so the score measures the skill alone (ADR 0003). Set
`evaluation.blind: false` to keep the wiki; the default is `true`. Real runs are
unaffected — they still load the wiki on failure. The copy is a temp directory;
the gate never writes into a deployed copy or into the skill it is testing.

**Gate traces live in this repo.** Each fixture appends one line to
`skills/<name>/FEEDBACK.jsonl` through `log-feedback.sh --gate --fixture <case>`:
`source: script`, `gate: true`, the evaluator's `outcome`, `note` and `checks`,
the fixture's prompt truncated, and the runner's `session` when it reports one.
That is the exception to the harvest rule — a gate run happens *in* the repo, so
its trace goes straight there and `analyze-feedback.sh --impact` lists it
separately from runs somebody asked for.

**Baseline.** Read before this run writes anything, from the gate traces already
in `FEEDBACK.jsonl` for the same fixtures: the newest version that is not the
current one, or, when a skill is gated before its version is bumped, the previous
gate run at the current version. The report says which. With `--baseline <sha>`
the gate instead checks that commit's `SKILL.md` into a second blind copy, runs
it too, and logs those traces under the version named in that commit's
`CONFIG.yaml`.

**Regression** (CONTEXT.md) is judged fixture by fixture before it is judged by
the mean:

| Rule | Trips when |
|------|-----------|
| Per fixture | A fixture scores more than one point below its baseline |
| Mean | The mean over shared fixtures falls by more than `evaluation.tolerance` (default 0.5) |
| Floor | A fixture scores under its `expect.json` `min_outcome`, with or without a baseline |

The one-point band absorbs the noise a live model makes; a two-point drop on a
single fixture is a regression even when the mean rose. On a regression the gate
exits 1 and prints the revert line:

```
git checkout <sha> -- skills/<name>/SKILL.md
```

It never runs it. `<sha>` is the `--baseline` commit when one was given, the last
commit that touched `SKILL.md` when the edit under test is uncommitted, and the
one before that when it is already committed. With no baseline at all the gate
logs its traces, says `no baseline; these traces are the baseline`, and exits 0.

`--dry-run` prints the plan — fixtures, what blinding removed, the invocation,
where the baseline comes from — without invoking the model.

**The runner.** `claude -p --output-format json --plugin-dir <tmp> --` with the
blind copy shaped as a plugin and the prompt written `/<plugin>:<skill> <fixture
prompt>`. The plugin namespace is what keeps the deployed, non-blind
`~/.claude/skills/<name>` from shadowing the copy under test; there is no flag
that hides it. The header comment in `scripts/gate-skill.sh` records what else
was tried and why it does not work.

The arithmetic — fixture discovery, the blind copy, baseline selection, the
verdict — lives in `scripts/lib/gate.py`, which imports `impact.gate_rows` so the
number the gate compares against and the table `--impact` prints cannot disagree.
`python3 scripts/lib/gate.py --self-test` and `tests/test-gate-skill.sh` exercise
all of it without a model.

## Skill Scripts (Optional)

Scripts in `scripts/` are executables that follow a standard I/O contract. Any language — the contract is the interface, not the file extension.

### check-prereqs

Run before execution. Reports whether prerequisites are met.

- **Input:** none (reads system state)
- **Output (stdout):** `{"ready": bool, "checks": [...], "context": {...}}`
- **Exit:** 0 always (readiness is in the JSON, not the exit code)

### evaluate

Run after execution. Scores the skill's output deterministically.

- **Input:** skill output via stdin or file argument
- **Output (stdout):** `{"outcome": 1-5, "note": "...", "checks": {...}, "source": "script"}`
- **Exit:** 0 on successful evaluation (even if outcome is low)

```bash
# Usage:
echo "$OUTPUT" | scripts/evaluate.sh
scripts/evaluate.py output.md
```

### Language choice

| Language | Extension | When to use |
|----------|-----------|-------------|
| Bash | `.sh` | Command checks, grep-based evaluation, no dependencies |
| Python | `.py` | API calls, library access, HTML parsing, structured diffing |
| Any | — | Just make it executable and follow the I/O contract |

The scaffold generates `.sh`. Replace with another language if the skill needs it. The SKILL.md epilogue references the actual filename.

## Versioning Convention

| Change | Version bump | Example |
|--------|-------------|---------|
| Compaction (stable patterns graduated) | Patch | 1.0.0 -> 1.0.1 |
| New capability | Minor | 1.0.1 -> 1.1.0 |
| Breaking workflow change | Major | 1.1.0 -> 2.0.0 |

## Cross-Platform Compatibility

| Platform | Base Standard | Extensions |
|----------|---------------|------------|
| Claude Code | SKILL.md + frontmatter | CONFIG.yaml, MEMO.md, FEEDBACK.jsonl |
| OpenAI Codex | agentskills.io | Ignored (no breakage) |
| Antigravity (Gemini) | SKILL.md + frontmatter | Ignored (no breakage) |

Extensions don't break compatibility. Platforms that don't understand them simply ignore them.
