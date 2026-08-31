# Skillmonger

A git repo of reusable agent skills that improve over time through a feedback
loop. This glossary pins the language of that loop so the raw, knowledge, and
executable layers stay distinct.

## Language

### Layers

**Skill**:
One directory under `skills/` that an agent loads on demand: the executable
layer. Identified by its directory name.
_Avoid_: prompt, command, plugin

**Wiki**:
A skill's `MEMO.md`: the knowledge layer, holding that skill's patterns. Each
skill has exactly one wiki; there is no repo-wide wiki.
_Avoid_: memo (as a noun for the layer), notes, knowledge base

**Pattern**:
One root-caused entry in a wiki: a recurring failure or strategy with its
evidence and workaround. A pattern has exactly one owner skill.
_Avoid_: edge case, learning, lesson, tip

**Owner skill**:
The skill whose mechanism a pattern describes. A pattern lives only in its
owner's wiki; skills that depend on the owner point at the pattern rather than
copying it.
_Avoid_: source skill, upstream (reserved for external repos)

**Dependent skill**:
A skill that lists another skill under `dependencies.skills` in its
CONFIG.yaml and therefore inherits that skill's patterns by reference.

**Trace**:
One entry in a skill's `FEEDBACK.jsonl`: the raw layer. Records one run's
prompt, outcome, note, and, when known, a pointer to the session it came
from. Traces are append-only and never rewritten.
_Avoid_: feedback (as a countable noun), log entry, iteration

**Deployed copy**:
The copy of a skill that an agent actually runs, installed by deploy into a
host tool directory or a sandbox home. Traces are written into the deployed
copy, not into the repo; the repo is the source and the deployed copy is
where runs happen.
_Avoid_: install, symlink (one deploy target happens to symlink; the term is
about the copy)

**Session**:
The full transcript of the agent run a trace came from. Lives outside the
repo, indexed by `pj`; a trace points at it by session id rather than
containing it.
_Avoid_: transcript, trajectory, conversation

**Evidence**:
The set of traces a pattern was derived from. Every pattern cites its
evidence; a pattern with no evidence is a hypothesis, not a pattern.

### The loop

**Compaction**:
A human-invoked maintenance pass over one skill's wiki in which the agent
consolidates new traces into patterns and graduates stable patterns into the
skill. Triggered by trace count reaching the threshold or by three or more
failing traces since the last pass, whichever comes first.
_Avoid_: review, cleanup, sweep

**Harvest**:
Collecting traces from every deployed copy into the repo's `FEEDBACK.jsonl`
for that skill, deduplicated and normalised. Harvest runs before any deploy
and before any compaction; it is the only way a trace enters the repo.
_Avoid_: sync (reserved for SKILL.md and wiki content), import, pull

**Maintainer**:
The role the agent plays during compaction: root-causing traces into
patterns. Distinct from the role it plays when executing the skill.
_Avoid_: reviewer, curator

**Failing trace**:
A trace with outcome 1 or 2.

### Gating

**Fixture**:
A held-out prompt kept under a skill's `fixtures/`, used to exercise the skill
in a gate run. A fixture is an input only; the skill's evaluate script judges
the output.
_Avoid_: test case, gold output, example

**Gate run**:
A blind, live execution of a skill on all of its fixtures, scored by its
evaluate script, performed to decide whether an edit to the skill is kept.
Blind means the wiki is withheld so the score measures the skill alone.
_Avoid_: eval, test run, benchmark

**Baseline**:
The gate run of a skill before an edit, kept per fixture, against which the
edit's gate run is compared.

**Gate trace**:
A trace written by a gate run rather than by a real run: one per fixture,
source `script`, flagged as a gate and naming its fixture. Gate traces live
in the repo's FEEDBACK.jsonl beside harvested traces; a baseline is the set
of gate traces at the previous skill version.

**Impact**:
The change in outcomes between one skill version and the next, derived from
traces grouped by version. Never recorded separately; always computed.
_Avoid_: ledger, score delta

**Graduation**:
Moving a pattern's workaround into the skill itself during compaction, after
which the pattern is marked graduated and the skill version is bumped. The
wiki's iteration log names the patterns each version graduated; that is the
provenance of a skill edit.
_Avoid_: promote, merge

**Regression**:
A gate run in which any single fixture scores more than one point below its
baseline, or the mean across fixtures falls by more than the skill's stated
tolerance. Judged fixture by fixture, never by the mean alone.

### Versions

**Format**:
The version of the skill contract itself (which files a skill has, what its
epilogue does, what its scripts emit). An integer in CONFIG.yaml; missing
means 1. Distinct from a skill's own version.
_Avoid_: framework version, schema version (reserved for FEEDBACK lines)

**Skill version**:
A skill's own semver in CONFIG.yaml, bumped when that skill's behaviour
changes. Says nothing about the format.

## Flagged ambiguities

- **Trace `source`** is documented as `script | llm | user`, but deployed
  copies contain `self`, `hybrid`, and missing values. Resolution: `self` is
  `llm`; `hybrid` is `script` when a script produced the outcome, else `llm`;
  missing is `llm`. Harvesting normalises; new writes must use the three.

- **"Upstream"** means an external repo a skill was adopted from
  (`CONFIG.yaml:upstream`). It never means an owner skill inside this repo.

## Example dialogue

**Dev:** The youtube-clip skill keeps failing with "sign in to confirm you're
not a bot". Should I add that to youtube-clip's wiki?

**Expert:** Whose mechanism is it? yt-dlp's. So yt-dlp is the owner skill and
the pattern goes in yt-dlp's wiki. youtube-clip is a dependent skill; it
already lists yt-dlp under `dependencies.skills`, so it inherits the pattern by
reference.

**Dev:** And if youtube-clip has its own workaround that yt-dlp doesn't need?

**Expert:** Then that's a second pattern, owned by youtube-clip, which cites the
yt-dlp pattern as its cause.
