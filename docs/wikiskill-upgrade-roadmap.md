# Skillmonger upgrade roadmap: adopting WikiSkill

Date: 2026-08-30. Source paper: WikiSkill, arXiv:2608.27454 (Tang et al.).
Vets the five-item adoption plan from the 2026-08-30 handoff and turns it into
a versioned roadmap. Numbers below were measured against `skills/` on this
date (53 skills); re-measure before acting on a later tree.

## 0. Vetting verdict

The plan's mapping is right (`FEEDBACK.jsonl` = raw traces, `MEMO.md` =
wiki, `SKILL.md` = executable) and the five items are the right items. Three
of its premises do not survive contact with the repo, and they change the
ordering and the version numbers.

### 0.1 Skillmonger has no framework version to bump

Every `version:` in the repo is a per-skill `CONFIG.yaml:skill.version`.
There is no tag, no `VERSION` file, no format field. "Major-version upgrade
of skillmonger" is undefined until one exists. The roadmap therefore versions
the **skill format** (the quad-file contract plus the script interface), not
the skills: `CONFIG.yaml:skill.format: <int>`, missing means 1. Skills keep
their own semver.

### 0.2 The trace layer is nearly empty, so the wiki shape is not the bottleneck

| Measurement | Value |
|---|---|
| Feedback entries, all 53 skills | 28 |
| ...by source | llm 27, user 1, **script 0** |
| Skills with any feedback | 8 |
| Skills with an `evaluate` script | 15 |
| Skills at or past `cycle_threshold` (15) | 0 (highest: skillmonger, 11) |
| MEMOs at or under 160 words (scaffold text) | 41 of 53 |
| MEMOs over 200 words (real content) | 11 |
| Largest MEMO | writing-voice-coach, 659 words (`memo_max` is 2000) |

WikiSkill's +15-point result came from a proposer reading a wiki consolidated
from hundreds of traces. Skillmonger has 28 traces and zero from its 15
scoring scripts: the scripts exist but nothing pipes their output into
`log-feedback.sh`. Restructuring 53 mostly-empty MEMOs into
`memo/patterns/` reorganises nothing. The first upgrade has to make traces
flow; the pattern schema comes second; the directory split is deferred until
a MEMO actually outgrows its file.

### 0.3 `MEMO.md` to `memo/` would break tooling and is unnecessary

Dependency map for the name `MEMO.md` outside `skills/`:

| Consumer | Behaviour if `MEMO.md` vanished | Breaking? |
|---|---|---|
| `scripts/compact-memo.sh` | prints "nothing to compact", exits 0 | yes, silently |
| `scripts/sync-skill-back.sh` | MEMO merge branch never runs; a `memo/` dir is not in its known set | yes |
| `scripts/lib/upstream.py` `OURS_ALWAYS` | `memo/*` reported as orphaned in all 27 adopted skills | yes |
| `scripts/ship-skill.sh` `KNOWN_FILES`/`KNOWN_DIRS` | generates a fresh MEMO.md; `memo/` prompts as "extra" | yes |
| `scripts/new-skill.sh`, `develop-skill.sh` | scaffold the old shape | yes |
| `scripts/validate-skill.sh:32` | optional-file notice only | no |
| `scripts/deploy-skill.sh` | `cp -r` / `ln -s` of the whole dir | no |
| `CONFIG.yaml:loading.on_failure: MEMO.md` (45 skills) | agent convention, no script reads it | no |
| `SKILL.md` (all 53) | zero references to MEMO | no |
| Codex, Gemini, Pi deploy targets | extra files ignored | no |
| Docs: `AGENTS.md`, `README.md`, `docs/skill-format.md`, `docs/adopting-external-skills.md`, `templates/sandbox-brief.md` | stale | doc-only |

Resolution: **`MEMO.md` stays and becomes the wiki index** (WikiSkill's
`index.md`). Pattern entries live inside it until it passes
`budget.memo_max`; only then does `compact-memo.sh` offer to move entries
to `memo/patterns/<slug>.md` and leave a one-line pointer per pattern in
`MEMO.md`. Every consumer that looks for `MEMO.md` keeps working. Two
one-line changes make the overflow directory safe before anyone needs it:
add `memo/` to `OURS_ALWAYS` and to `KNOWN_DIRS`. No skill is within 3x of
`memo_max` today, so the overflow path touches zero skills at launch.

### 0.4 The change that earns a major bump is the epilogue contract

The epilogue is the only place the framework's contract is embedded in every
`SKILL.md`, and it is inconsistent today:

| Epilogue instruction | Skills |
|---|---|
| "increment `iteration_count`" by hand | 39 |
| "append one JSON line" by hand | 5 |
| mentions `log-feedback.sh` | 2 |
| non-standard heading (`## Feedback`, `## After execution (...)`) | 4: camoufox-stealth, epub-to-md, global-social-proof, scientific-paper-searcher |

Items 2, 3 and 5 (ledger, gate, provenance) all assume feedback entries are
written by one code path so they can carry `checks`, a run id and a pattern
slug. Hand-appended entries cannot. bd `skillmonger-wzy` (concurrency-safe
feedback writes) is the same problem from the other side. Rewriting all 53
epilogues to route through `log-feedback.sh` is a workflow change under
`docs/skill-format.md`'s own convention, and that is format 2.0.

### 0.5 Blind measurement does not conflict with `on_failure: MEMO.md`

They are different contexts. `loading.on_failure` governs a live run helping
a user; MEMO on failure stays. The gate is a measurement run: the gate script
copies the skill to a temp dir, deletes `MEMO.md` and `memo/`, strips
`loading.on_failure`, and runs there. Encode as
`CONFIG.yaml:evaluation.blind: true` (default true). Nothing changes in the
45 CONFIG files that set `on_failure`.

### 0.6 Held-out prompts do not exist yet

`FEEDBACK.jsonl` holds 28 prompts, concentrated in 8 mostly qualitative
skills; the 15 programmatic skills have one prompt between them. Fixtures
have to be authored: `skills/<name>/fixtures/<case>.prompt.md`, optionally
`<case>.expect.json` with a minimum outcome. They are inputs, not gold
outputs: the skill's `evaluate` script is the oracle. Budget: 3-5 per
programmatic skill, 45-75 prompts total, plus one `claude -p` run per fixture
per gate.

### 0.7 Build-vs-borrow, re-vetted

- **promptfoo: defer, do not adopt at 2.0.** Its value is the runner and the
  diff UI; the assertion already exists (`evaluate`). `hooks/pre-push` is
  bash and the deploy targets (SRT homes, Pi) do not guarantee Node. Build
  `gate-skill.sh` (bash, ~100 lines) against the fixture layout above; a
  promptfoo adapter can read the same fixtures later if a matrix view is
  wanted.
- **GEPA: experimental, not before 2.0 has produced data.** It needs 100-500
  samples and an automatable metric per skill. Skillmonger has 28 samples in
  total. Eligible set is 14 skills (the 15 programmatic minus
  writing-voice-coach, whose `evaluate` deliberately omits `outcome`).
- **mem0, cognee, letta, zep: reject**, as the handoff said. Borrow the
  record shape only (root cause, evidence, workaround, status).
- **Not transplanted:** WikiSkill's K-iteration train/val loop. Skillmonger
  stays human-in-the-loop, per skill.

## 1. Version ladder

| Format | Name | Breaking | Skills that change | Depends on |
|---|---|---|---|---|
| 1.0 | Baseline tag | no | 0 | -- |
| 1.1 | Traces flow | no | 15 programmatic + 4 non-standard headings | 1.0 |
| 1.2 | Pattern schema, impact ledger, provenance | no | 0 mandatory; 11 content-bearing MEMOs opportunistically | 1.1 |
| 2.0 | Epilogue contract v2 and gated edits | **yes** | all 53 `SKILL.md` (scripted); 15 `CONFIG.yaml`; fixtures in 15 | 1.1, 1.2 |
| 2.1 | Memo overflow to `memo/patterns/` | no | per skill, on demand; 0 today | 1.2 |
| 3.0-exp | GEPA optimiser wrapper | no, opt-in | up to 14 | 2.0 plus 30+ gate runs per skill |

Skill classes referenced below (measured 2026-08-30):

- **Programmatic (15):** ai-talking-heads, camoufox-stealth,
  centers-of-excellence, epub-to-md, git-housekeeping, github-search,
  global-social-proof, homework-feedback-writer, isometric-explainer,
  recipe-search, scientific-paper-searcher, writing-voice-coach, youtube,
  youtube-clip, youtube-search.
- **Gate-eligible (14):** programmatic minus writing-voice-coach.
- **Qualitative (38):** everything else. Items 3 and GEPA never apply.
- **Content-bearing MEMO (11, over 200 words):** ai-talking-heads,
  centers-of-excellence, isometric-explainer, project-juggler,
  project-portfolio, ralph-orchestrator, scientific-paper-searcher,
  skillmonger, writing-voice-coach, youtube-search, yt-dlp.
- **Adopted from upstream (27):** every skill with `CONFIG.yaml:upstream`.
  Their `SKILL.md` is an `adapted` zone, so epilogue edits are ours and
  `sync-upstream.sh` already tolerates them; `MEMO.md`/`memo/` must stay in
  `OURS_ALWAYS`.
- **Special case:** remotion has no `compaction` block and a 25-word MEMO.
  Exempt from 1.1-2.0 changes except the scripted epilogue rewrite.

## 2. Format 1.0: baseline

Goal: give "major version" a referent before changing anything.

- Add `skill.format: 1` to `docs/skill-format.md` as the documented default
  (missing means 1). Do not touch the 53 CONFIG files; the default covers
  them.
- `validate-skill.sh`: read `skill.format`, accept 1 only, error on anything
  else. Later formats extend the accepted set.
- Git tag `format-1.0` on the commit that lands this.

Skills touched: 0. Migration: none.

## 3. Format 1.1: traces flow (additive)

Goal: make `FEEDBACK.jsonl` receive script-sourced entries with their
`checks`, so there is something to consolidate.

Framework changes:

- `log-feedback.sh --from-evaluate [file|-]`: read the evaluate JSON,
  take `outcome`, `note`, `source`, and store `checks` verbatim. When
  `outcome` is absent (writing-voice-coach precedent) exit 2 with a message
  that names the self-assessment path instead of writing an entry.
- `FEEDBACK.jsonl` gains optional `checks` (object) and `run` (string, the
  evaluate invocation id). `schema_version` stays 1: optional fields are
  backward-compatible for every reader in the repo (`analyze-feedback.sh`,
  `compact-memo.sh` grep on `"outcome":`).
- Epilogue scaffold in `new-skill.sh` and `develop-skill.sh`: the cascade's
  first step becomes `scripts/evaluate ... | scripts/log-feedback.sh <skill>
  --from-evaluate -`, replacing "append one JSON line".
- `analyze-feedback.sh`: show `checks` failure counts per skill when present.

Skills touched (19, wording only, no behaviour change):

- The 15 programmatic skills: epilogue step 1 pipes evaluate into
  log-feedback. writing-voice-coach keeps its "script has no score" routing;
  camoufox-stealth keeps its type-A wording but adds the pipe.
- The 4 non-standard headings (camoufox-stealth, epub-to-md,
  global-social-proof, scientific-paper-searcher) are normalised to
  `## After Execution` so 2.0's rewrite script can find them. Content
  unchanged.
- The remaining 34 qualitative skills: untouched.

Migration: manual, one commit per skill or one batched commit; 19 small
diffs. Acceptance: `analyze-feedback.sh` shows at least one `source:script`
entry for each programmatic skill after one real use.

## 4. Format 1.2: pattern schema, impact ledger, provenance (additive)

Goal: give the knowledge layer WikiSkill's record shape and a place to
record whether skill edits helped, without changing any file name.

### 4.1 Pattern entries (item 1, reshaped)

`MEMO.md` keeps its sections. An entry under "Edge Cases Log" or "Known
Failure Patterns" becomes:

```markdown
### <slug>: short title
- status: open | graduated (vX.Y.Z) | purged
- root cause: one sentence
- evidence: FEEDBACK ts, ts, ... (or "manual")
- workaround: what the agent should do now
- skill change: what SKILL.md should say if this graduates (optional)
```

Old free-form entries stay valid; `compact-memo.sh` prints a warning for
entries missing `status`/`evidence` and offers the template with `evidence`
pre-filled from feedback entries since `last_compaction`. This is the "Wiki
Maintainer" reframing: the script's job moves from "print the file and tell
Claude to review it" to "list new traces, group by `note`/`checks`, and
propose consolidated entries".

Skills touched: 0 mandatory. The 11 content-bearing MEMOs can be converted
opportunistically at their next compaction; the other 42 are scaffold text
and gain nothing from conversion.

### 4.2 Skill-impact ledger (item 2)

`skills/<name>/IMPACT.jsonl`, append-only, written by a new
`scripts/record-impact.sh`:

```json
{"ts":"...","skill":"...","from":"1.1.0","to":"1.2.0","commit":"abc123",
 "patterns":["slug"],"baseline":{"n":12,"mean":3.4},"after":null,
 "decision":"pending","schema_version":1}
```

`after` and `decision` (`accepted` | `reverted` | `pending`) are filled
later by the 2.0 gate or by hand. `analyze-feedback.sh --impact` renders the
cross-skill table (WikiSkill's `skill-impact.md`, generated rather than
maintained).

Framework changes: add `IMPACT.jsonl` to `OURS_ALWAYS`, `KNOWN_FILES`, the
"What NOT to Edit" list, `validate-skill.sh` optional set, and
`docs/skill-format.md`. Add `memo/` to `OURS_ALWAYS` and `KNOWN_DIRS` now,
ahead of 2.1.

Skills touched: 0 at launch; a ledger appears on a skill's next version bump.

### 4.3 Provenance (item 5)

The `patterns` array in `IMPACT.jsonl` is the provenance. Add a `Patterns`
column to MEMO's Iteration Log table (template only) and a
`Pattern: <slug>` git trailer convention in `AGENTS.md`. No `PURPOSE.md`;
one file per concept is enough.

Migration: none. Acceptance: `record-impact.sh` runs in `compact-memo.sh`'s
step 4 ("VERSION") and in `ship-skill.sh` when the shipped version differs
from the previous one.

## 5. Format 2.0: epilogue contract v2 and gated edits (breaking)

Goal: one code path for every feedback write, and a regression gate on
skill edits for the skills that can be scored.

### 5.1 Epilogue contract v2 (all 53 skills)

New epilogue, rendered from CONFIG by `scripts/render-epilogue.sh`:

- Programmatic mode: run evaluate, pipe to `log-feedback.sh --from-evaluate`.
- Qualitative mode: ask the skill-specific question already in the epilogue
  (preserved verbatim from the current text), then
  `log-feedback.sh <skill> --outcome N --prompt ... --source user|llm`.
- No epilogue tells the agent to hand-append JSON or hand-edit
  `iteration_count`. `log-feedback.sh` owns both (and, with the concurrency
  fix from `skillmonger-wzy`, does so safely).

`CONFIG.yaml` gains:

```yaml
skill:
  format: 2
evaluation:
  mode: programmatic | qualitative | delayed | hybrid
  script: scripts/evaluate.sh      # programmatic/hybrid only
  blind: true                      # gate runs strip MEMO
  fixtures: fixtures/              # programmatic/hybrid only
```

`validate-skill.sh` under format 2: `evaluation.mode` required; if
programmatic or hybrid, `script` must exist and be executable and
`fixtures/` must contain at least one `*.prompt.md`.

Skills touched: **all 53**, in two tiers.

- Scripted rewrite (`scripts/migrate-format-2.sh`): replaces the text from
  `## After Execution` to end of file with the rendered epilogue, keeping
  any skill-specific question it finds between the heading and the JSON
  block. Sets `skill.format: 2` and `evaluation.mode` (programmatic where
  `scripts/evaluate*` exists, qualitative otherwise). Dry-run first; review
  the diff of all 53 in one PR.
- Manual review after the script, 6 skills: writing-voice-coach (no-outcome
  evaluate, mode `hybrid`, cascade routes around the script),
  camoufox-stealth (type-A wording), epub-to-md and youtube (declare
  themselves hybrid in their evaluate headers), remotion (no compaction
  block; add one), skillmonger (its own epilogue describes the feedback
  pipeline and should reference the v2 contract).

### 5.2 Regression gate (item 3, 15 skills)

`scripts/gate-skill.sh skills/<name>/ [--baseline <sha>]`:

1. Copy the skill to a temp dir; if `evaluation.blind`, delete `MEMO.md`,
   `memo/`, and the `loading.on_failure` key.
2. For each `fixtures/*.prompt.md`, run `claude -p` with the temp skill
   loaded, pipe the output to the evaluate script, collect `outcome`.
3. Compare mean outcome to the `baseline` recorded in the latest
   `IMPACT.jsonl` entry (or, with `--baseline`, re-run step 2 on the skill
   as of that commit). Regression means mean drops by more than 0.25 or any
   fixture with `expect.json` falls below its minimum.
4. Append `after` and `decision` to `IMPACT.jsonl`. On regression print the
   `git checkout <sha> -- skills/<name>/SKILL.md` line; do not revert
   automatically (human-in-the-loop stays).

`hooks/pre-push`: for each pushed commit that touches
`skills/<name>/SKILL.md` where `evaluation.mode` is programmatic or hybrid
and `IMPACT.jsonl` has a `pending` entry, run the gate. Skip with
`SKILLMONGER_SKIP_GATE=1`. Qualitative skills are never gated.

Fixtures to author: 3-5 per programmatic skill, 15 skills. Seed from the
existing FEEDBACK prompts where they exist (ai-talking-heads has 1); the rest
are new. This is the single largest manual cost in the roadmap and it is
what makes item 3 real, so it is in 2.0 rather than deferred.

Skills touched by 5.2: the 15 programmatic. The 38 qualitative skills get
`evaluation.mode: qualitative` from the migration script and nothing else.

### 5.3 Sequencing inside 2.0

1. `log-feedback.sh` concurrency fix (`skillmonger-wzy`) and
   `--from-evaluate` (1.1) must already be in.
2. `record-impact.sh` (1.2) must already be in, or the gate has no baseline.
3. Land `render-epilogue.sh`, `migrate-format-2.sh`, validate changes, docs.
4. Run the migration on all 53; review; land as one commit; tag
   `format-2.0`.
5. Author fixtures skill by skill; each skill's fixtures land with its own
   first gated edit. Until a programmatic skill has fixtures, validate
   reports a warning, not an error, for a 30-day grace window (date it in
   the script).
6. Redeploy: `deploy-skill.sh` for all 53 so the SRT and Pi copies carry the
   new epilogue.

## 6. Format 2.1: memo overflow (additive, per skill)

Trigger: `compact-memo.sh` finds `MEMO.md` over `budget.memo_max` words or
over 12 pattern entries.

Action: move each entry to `memo/patterns/<slug>.md`; replace it in
`MEMO.md` with one line `- [<slug>](memo/patterns/<slug>.md): status, one
line`. `MEMO.md` is now the index. `loading.on_failure` stays `MEMO.md`; the
agent follows the links it needs.

Skills touched: 0 today (largest MEMO is at 33% of `memo_max`). Likely first
candidates by growth rate: skillmonger, yt-dlp, writing-voice-coach.

## 7. Format 3.0-experimental: GEPA optimiser

Wrapper `scripts/optimise-skill.sh` that hands GEPA the skill text, the
fixture prompts, and the evaluate script as the metric, and writes each
proposed patch through the 2.0 gate. Opt-in per skill via
`evaluation.optimiser: gepa`.

Preconditions, all per skill: format 2, 30 or more gate runs in
`IMPACT.jsonl`, evaluate emits `outcome`. Eligible today: 0. Eligible once
fixtures exist and have been exercised: up to 14. Never eligible:
writing-voice-coach and the 38 qualitative skills.

Do not schedule until 2.0 has run for a quarter; the data will say whether
any skill is worth it.

## 8. What is untouched throughout

- `FEEDBACK.jsonl` history: never rewritten. New fields are optional.
- `SKILL.md` bodies above the epilogue: never touched by any migration.
- `references/`, `assets/`, upstream `verbatim` zones in the 27 adopted
  skills.
- `deploy-skill.sh`, `undeploy-skill.sh`: no change in any version; they
  move whole directories.
- Cross-platform loaders (Codex, Gemini, Pi): they read `SKILL.md`
  frontmatter only and ignore the rest, before and after.

## 9. Open decisions left to the maintainer

1. Regression threshold in 5.2 (0.25 mean drop) is a guess; pick after the
   first ten gate runs.
2. Whether `claude -p` is the only gate runner or whether `codex exec`
   should also be supported, given skills deploy to both.
3. Whether the 30-day fixture grace window in 5.3 is too long for a repo
   with one maintainer, or whether fixtures should simply block the tag.
