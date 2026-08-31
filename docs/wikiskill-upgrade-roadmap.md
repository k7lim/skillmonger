# Skillmonger upgrade roadmap: adopting WikiSkill

Date: 2026-08-30 (revised the same day after a grilling session; decisions
marked **decided** were taken by the maintainer). Source paper: WikiSkill,
arXiv:2608.27454 (Tang et al.). Vocabulary is pinned in `CONTEXT.md`;
architectural decisions in `docs/adr/`. Numbers were measured against
`skills/` and the four deploy targets on this date; re-measure before acting
on a later tree.

## 0. Vetting verdict

The plan's mapping is right (`FEEDBACK.jsonl` = traces, `MEMO.md` = wiki,
`SKILL.md` = executable) and the five items are the right items. Three of
its premises did not survive contact with the repo, and one of my own
findings did not survive contact with the deploy targets.

### 0.1 Skillmonger had no framework version

Every `version:` in the repo is a per-skill semver. The roadmap versions the
**skill format** via `CONFIG.yaml:skill.format: <int>` (missing means 1) and
git tags `format-N.M`. See ADR 0001. **Decided.**

### 0.2 The trace layer is not empty; it is stranded and being destroyed

The first draft of this document said the repo held 28 traces and concluded
the knowledge layer had nothing to consolidate. The repo does hold 28. The
four deploy targets hold **373 unique traces** from 25 skills (296 from
August 2026 alone, 55 of them script-sourced), because the epilogue appends
to the *deployed copy's* `FEEDBACK.jsonl` and nothing brings them home.
`deploy-skill.sh` runs `rm -rf` before `cp -r`, so every redeploy destroys
whatever the deployed copy had accumulated. What exists today is only what
survived since the last deploy.

| Where | Entries | Not in repo |
|---|---|---|
| `skills/*/FEEDBACK.jsonl` (repo) | 28 | -- |
| `~/.local/share/skillmonger/skills` | 368 | 342 |
| yolobox home, Claude | 267 | 241 |
| yolobox home, Codex | 243 | 217 |
| `~/.pi/agent/skills` | 199 | 173 |
| Unique across all, by (skill, ts) | 373 | ~345 |

Schema drift in the wild: `source` values `self`, `hybrid`, and missing;
`version` values `unknown`, `''`, `1`, `n/a`. Outcomes skew 4-5 (219 fives,
135 fours, 3 failing), as `docs/skill-format.md` predicts for LLM
self-assessment.

So the first upgrade is a harvest, not a schema. See ADR 0002. **Decided.**

### 0.3 `MEMO.md` to `memo/` would break tooling and is unnecessary

Dependency map for the name `MEMO.md` outside `skills/`:

| Consumer | Behaviour if `MEMO.md` vanished | Breaking? |
|---|---|---|
| `scripts/compact-memo.sh` | prints "nothing to compact", exits 0 | yes, silently |
| `scripts/sync-skill-back.sh` | MEMO merge branch never runs; `memo/` unknown | yes |
| `scripts/lib/upstream.py` `OURS_ALWAYS` | `memo/*` orphaned in all 27 adopted skills | yes |
| `scripts/ship-skill.sh` `KNOWN_FILES`/`KNOWN_DIRS` | regenerates MEMO.md; `memo/` prompts as extra | yes |
| `scripts/new-skill.sh`, `develop-skill.sh` | scaffold the old shape | yes |
| `scripts/validate-skill.sh:32` | optional-file notice | no |
| `scripts/deploy-skill.sh` | copies whole dirs | no |
| `CONFIG.yaml:loading.on_failure` (45 skills) | agent convention | no |
| `SKILL.md` (all 53) | zero references | no |
| Codex, Gemini, Pi loaders | extra files ignored | no |

Resolution: `MEMO.md` stays and is the wiki (CONTEXT.md: **Wiki**). The
wiki is per skill; a pattern lives only in its owner skill's wiki and
dependents point at it via `dependencies.skills` (CONTEXT.md: **Owner
skill**). **Decided.** Overflow to `memo/patterns/` happens per skill only
when a wiki passes `budget.memo_max`; no wiki is within 3x of it.

### 0.4 The change that earns a major bump is the epilogue contract

| Epilogue instruction today | Skills |
|---|---|
| "increment `iteration_count`" by hand | 39 |
| "append one JSON line" by hand | 5 |
| mentions `log-feedback.sh` | 2 |
| non-standard heading | 4: camoufox-stealth, epub-to-md, global-social-proof, scientific-paper-searcher |

The hand-append exists for a reason: a deployed copy on SRT or Pi cannot
reach `scripts/log-feedback.sh`. The epilogue therefore keeps writing in
place (ADR 0002); what changes is *what* it writes. **Decided.**

### 0.5 Runtime wiki loading stays; only the gate is blind

WikiSkill found wiki access at inference time hurt (63.7 to 60.9). Skillmonger
keeps `loading.on_failure: MEMO.md`: a failing human-in-the-loop run is the
situation the workarounds exist for. Gate runs withhold the wiki so the score
measures the skill alone. See ADR 0003. **Decided.**

### 0.6 Held-out prompts do not exist yet

Fixtures (CONTEXT.md: **Fixture**) are inputs only; the evaluate script is
the oracle. They are required the first time a programmatic skill's
`SKILL.md` is edited after format 2.0, at least three per skill, seeded from
that skill's harvested traces plus hand-written ones. No grace window, no
deadline, and format 2.0 tags without them. **Decided.**

### 0.7 Build-vs-borrow, re-vetted

- **promptfoo: defer.** `hooks/pre-push` is bash and the deploy targets do
  not guarantee Node. `gate-skill.sh` is bash against the existing evaluate
  contract; a promptfoo adapter can read the same fixtures later.
- **GEPA: experimental, after 2.0 has produced gate traces.** Eligible set
  is 14 skills (programmatic minus writing-voice-coach, whose evaluate omits
  `outcome`).
- **mem0, cognee, letta, zep: reject.** Borrow the record shape only.
- **Not transplanted:** the K-iteration train/val loop.

## 1. Version ladder

| Format | Name | Breaking | Skills that change | Depends on |
|---|---|---|---|---|
| 1.0 | Baseline tag | no | 0 | -- |
| 1.1 | Harvest | no | 0 | 1.0 |
| 1.2 | Pattern schema and failure-triggered compaction | no | 0 mandatory; 11 content-bearing wikis opportunistically | 1.1 |
| 2.0 | Epilogue contract v2 and gate tooling | **yes** | all 53 `SKILL.md` (scripted); 15 `CONFIG.yaml` | 1.1, 1.2 |
| 2.1 | Wiki overflow to `memo/patterns/` | no | per skill on demand; 0 today | 1.2 |
| 3.0-exp | GEPA optimiser wrapper | no, opt-in | up to 14 | 2.0 plus 30 gate traces per skill |

Skill classes (measured 2026-08-30):

- **Programmatic (15):** ai-talking-heads, camoufox-stealth,
  centers-of-excellence, epub-to-md, git-housekeeping, github-search,
  global-social-proof, homework-feedback-writer, isometric-explainer,
  recipe-search, scientific-paper-searcher, writing-voice-coach, youtube,
  youtube-clip, youtube-search.
- **Gate-eligible (14):** programmatic minus writing-voice-coach.
- **Qualitative (38):** everything else. Gate and GEPA never apply.
- **Content-bearing wiki (11, over 200 words):** ai-talking-heads,
  centers-of-excellence, isometric-explainer, project-juggler,
  project-portfolio, ralph-orchestrator, scientific-paper-searcher,
  skillmonger, writing-voice-coach, youtube-search, yt-dlp.
- **Adopted from upstream (27):** `SKILL.md` is an `adapted` zone, so
  epilogue edits are ours; `MEMO.md`/`memo/` stay in `OURS_ALWAYS`.
- **Special case:** remotion has no `compaction` block and a 25-word wiki.

## 2. Format 1.0: baseline

- `docs/skill-format.md` documents `skill.format: 1` as the default.
- `validate-skill.sh` reads `skill.format`; accepts 1; errors on others.
- Tag `format-1.0`.

Skills touched: 0.

## 3. Format 1.1: harvest (additive, framework only)

Goal: bring the stranded traces home and stop destroying them.

- `scripts/harvest-feedback.sh [skill]`: for each deploy target that
  `deploy-skill.sh` knows, union the deployed copy's `FEEDBACK.jsonl` into
  `skills/<name>/FEEDBACK.jsonl`, dedupe by (skill, ts), normalise `source`
  per CONTEXT.md's flagged ambiguity, leave `version` as written, and set
  `compaction.iteration_count` to the count of traces since
  `last_compaction`. Idempotent. Prints per-skill added counts.
- `deploy-skill.sh`: call the harvester for the skill before every `rm -rf`.
- `analyze-feedback.sh`: run the harvester first unless `--no-harvest`.
- `log-feedback.sh`: accept `--session <id>` and `--from-evaluate [file|-]`
  (copies `outcome`, `note`, `checks` from evaluate output; exit 2 when
  `outcome` is absent). This is for in-repo use (gate runs, manual logging);
  deployed epilogues do not call it.
- Trace fields: optional `session`, `checks`, `gate`, `fixture`.
  `schema_version` stays 1; every reader tolerates extra fields.
- Run the harvest once, commit the ~345 recovered traces.

Skills touched: 0. Acceptance: after one deploy cycle, no deploy target
holds a trace the repo lacks.

## 4. Format 1.2: pattern schema and failure-triggered compaction

### 4.1 Pattern entries

A wiki entry becomes:

```markdown
### <slug>: short title
- status: open | graduated (vX.Y.Z) | purged
- root cause: one sentence
- evidence: FEEDBACK ts, ts, ... (or "manual")
- workaround: what the agent should do now
- skill change: what SKILL.md should say if this graduates (optional)
```

Old free-form entries stay valid. `compact-memo.sh` becomes the Maintainer's
tool: it lists traces since `last_compaction` (harvesting first), groups by
`note`/`checks`, flags entries missing `status`/`evidence`, and prints the
template with evidence pre-filled. For dependent skills it checks whether a
proposed pattern belongs to an owner skill's wiki instead.

### 4.2 Compaction trigger

`log-feedback.sh`, `harvest-feedback.sh`, and `compact-memo.sh` recommend
compaction when `iteration_count >= cycle_threshold` **or** three or more
failing traces have arrived since `last_compaction`. No CONFIG change; the
second condition is computed.

### 4.3 Provenance and impact

No new file. The wiki's Iteration Log gains a `Patterns` column naming the
slugs each version graduated. `analyze-feedback.sh --impact` groups
harvested traces by `version` and prints before/after outcomes per bump.
Gate runs (2.0) log gate traces into the repo, so baselines are gate traces
at the previous version.

Framework: add `memo/` to `OURS_ALWAYS` and `KNOWN_DIRS` now, ahead of 2.1.

Skills touched: 0 mandatory; the 11 content-bearing wikis convert at their
next compaction.

## 5. Format 2.0: epilogue contract v2 and gate tooling (breaking)

### 5.1 Epilogue v2, all 53 skills

Rendered from CONFIG by `scripts/render-epilogue.sh`. Every epilogue still
appends one JSON line to `FEEDBACK.jsonl` in the skill's own directory (the
deployed copy). What changes:

- No instruction to increment `iteration_count`; harvest derives it.
- The line includes `session` when the agent knows its session id.
- `source` is one of `script | llm | user`; nothing else.
- Programmatic mode: run the evaluate script, copy its `outcome`, `note`,
  `checks` into the line with `source: script`. writing-voice-coach's
  no-outcome routing is preserved.
- Qualitative mode: the skill's existing self-assessment question is kept
  verbatim; the line uses `source: llm` or `user`.

`CONFIG.yaml` gains:

```yaml
skill:
  format: 2
evaluation:
  mode: programmatic | qualitative | delayed | hybrid
  script: scripts/evaluate.sh   # programmatic/hybrid
  blind: true                   # gate runs withhold the wiki
  tolerance: 0.5                # mean-drop tolerance for regression
  runner: claude                # reserved; codex later
```

`validate-skill.sh` under format 2: `evaluation.mode` required; for
programmatic/hybrid, `script` must exist and be executable.

Migration: **scripted big-bang, one PR** (`scripts/migrate-format-2.sh`):
replaces the text from `## After Execution` (or the 4 non-standard
headings) to end of file, preserving the skill-specific question found
between heading and JSON block; sets `skill.format: 2` and
`evaluation.mode`. Dry-run, review all 53 diffs, land, tag `format-2.0`,
redeploy all 53. Hand review in the same PR for six skills:
writing-voice-coach, camoufox-stealth, epub-to-md, youtube, remotion,
skillmonger.

### 5.2 Gate tooling, 15 skills

`scripts/gate-skill.sh skills/<name>/ [--baseline <sha>]`:

1. Refuse to run unless `fixtures/` holds at least three `*.prompt.md`.
2. Copy the skill to a temp dir; delete `MEMO.md`, `memo/`, and the
   `loading.on_failure` key.
3. For each fixture run the skill through `claude -p --plugin-dir <tmp>`
   as `/<plugin>:<skill> <prompt>` (measured 2026-08-30: `--bare` cannot
   authenticate without `ANTHROPIC_API_KEY`, and `--add-dir` lets the
   deployed copy shadow the temp one; the plugin namespace is the
   isolation), pipe the output to the evaluate script, and log a gate trace
   (`source: script`, `gate: true`, `fixture: <name>`, `version`) into the
   repo's `FEEDBACK.jsonl`.
4. Baseline = gate traces for the same fixtures at the previous version
   (or re-run at `--baseline <sha>` if none).
5. Regression (CONTEXT.md: **Regression**) = any fixture more than one
   point below its baseline, or mean drop beyond `evaluation.tolerance`.
   Print the revert line; never revert automatically.

`hooks/pre-push`: for each pushed commit touching `skills/<name>/SKILL.md`
where mode is programmatic/hybrid, run the gate; block if fixtures are
missing or the run regressed. `SKILLMONGER_SKIP_GATE=1` bypasses.
Qualitative skills are never gated.

Fixtures: required at the first gated edit, seeded from harvested traces'
`prompt` fields (centers-of-excellence has 38 to choose from,
global-social-proof 37) plus hand-written ones.

### 5.3 Sequencing

1. 1.1 harvest and 1.2 tooling landed.
2. Land `render-epilogue.sh`, `migrate-format-2.sh`, `gate-skill.sh`,
   validate and pre-push changes, docs.
3. Run the migration; review; land; tag `format-2.0`; redeploy all 53.
4. Fixtures arrive skill by skill with each skill's first gated edit.

## 6. Format 2.1: wiki overflow (additive, per skill)

Trigger: `compact-memo.sh` finds `MEMO.md` over `budget.memo_max` words or
over 12 patterns. Action: move each entry to `memo/patterns/<slug>.md` and
leave one index line per pattern in `MEMO.md`. `loading.on_failure` stays
`MEMO.md`. Skills touched: 0 today.

## 7. Format 3.0-experimental: GEPA optimiser

`scripts/optimise-skill.sh` hands GEPA the skill text, the fixtures, and the
evaluate script as metric, and routes each proposed patch through the gate.
Opt-in via `evaluation.optimiser: gepa`. Preconditions per skill: format 2,
30 or more gate traces, evaluate emits `outcome`. Eligible today: 0. Do not
schedule until 2.0 has run for a quarter.

## 8. Untouched throughout

- `FEEDBACK.jsonl` history: harvest appends, never rewrites.
- `SKILL.md` bodies above the epilogue.
- `references/`, `assets/`, upstream `verbatim` zones in adopted skills.
- `undeploy-skill.sh`; `deploy-skill.sh` changes only by harvesting first.
- Codex, Gemini, Pi loaders: frontmatter only, before and after.

## 9. Open items

1. `evaluation.tolerance` default 0.5 and the one-point per-fixture rule
   are starting values; revisit after ten gate runs.
2. `codex exec --add-dir` as a second gate runner: reserved field, not
   built.
3. Whether `version` in harvested traces should be back-filled from git
   history when it reads `unknown`; left as written for now.
