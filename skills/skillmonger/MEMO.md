# MEMO — skillmonger

> **Loading Trigger:** This file is loaded when the skill encounters issues or needs historical context. Do not load proactively.

## Edge Cases Log

First compaction 2026-09-01 over 16 traces (all `source: llm`, mean 4.9, none failing, two scored 4). Both 4s share one mechanism (develop-skill.sh's interactivity); the pre-1.2 free-form entries below are converted to the pattern schema with `manual` evidence where they predate harvested traces.

### develop-skill-non-interactive: drive the prompts, don't rebuild the scaffold
- status: graduated (v0.2.1)
- root cause: `develop-skill.sh` takes no arguments and prompts for seed choice, name (only when choosing 0), sometimes "Continue anyway?", then the one-liner; SKILL.md said "pass name if script supports it" — it does not — so a non-interactive run either hand-scaffolded the sandbox (drifting from the template) or stalled.
- evidence: FEEDBACK 2026-08-31T20:10:00Z ("develop-skill.sh is interactive-only; scaffolded sandbox skill manually"), 2026-09-01T18:30:21Z ("develop-skill.sh driven by piped answers" — completed cleanly)
- workaround: pipe the answers in prompt order, e.g. `printf '1\nwhat it does\n' | scripts/develop-skill.sh`; a conditional "Continue anyway? (y/N)" prompt can shift the order, so verify the scaffold landed in `~/Development/sandbox/skills/<name>` instead of trusting exit status. Never hand-build the sandbox layout.
- skill change: SKILL.md's "Start developing a seed" block shows the piped invocation and the verify step (v0.2.1).

### direct-request-skips-status: the sweep is for "where did I leave off"
- status: open
- root cause: SKILL.md's flow runs the full status sweep first, but when the user's request already names the seed or skill, the sweep adds nothing; runs that skipped it completed fine yet self-docked for deviating from the documented flow.
- evidence: FEEDBACK 2026-09-01T18:30:21Z ("Direct request named the seed, so status was skipped"; scored 4), 2026-05-11T08:14:08Z ("Matched request to existing shipped skill" — no sweep, scored 5)
- workaround: when the request names its target, go straight to the action; run the sweep only for open-ended requests ("skill status", "where did I leave off").
- skill change: if more runs self-dock for this, make Step 1 conditional in SKILL.md.

### deploy-skill-path-and-mode: a path and a mode, not a bare name
- status: graduated (v0.2.0)
- root cause: `scripts/deploy-skill.sh my-skill` fails with a confusing `cd: my-skill: No such file or directory`; it wants `scripts/deploy-skill.sh skills/my-skill --global`, and omitting the mode gives `ERROR: Specify --global, --store-only, and/or --local <dir>`.
- evidence: manual; reproduced live 2026-09-01 (maintainer hit both errors in sequence from the terminal).
- workaround: always `scripts/deploy-skill.sh skills/<name> --global` (or `--store-only` / `--local <dir>`).
- skill change: SKILL.md documents the path-not-name and mode requirement (in SKILL.md at v0.2.0).

### ship-skill-staging: aborted runs ship nothing now
- status: graduated (v0.2.1; framework fix 7f526ab, 2026-08-31)
- root cause: ship-skill.sh used to block on an extras prompt (`assets/`, `SOURCE.md`, `OVERLAY.md`) that piped input did not reliably answer, hanging and leaving a half-shipped skill. Commit 7f526ab changed the script: without a terminal it does not prompt, extras ship by default, an existing skill needs `--yes` to overwrite, and the copy is staged then moved in one step.
- evidence: manual (pre-1.2 free-form entry; the half-ship incident motivated 7f526ab).
- workaround: none needed for hangs anymore; still check the run summary's "Not shipped" list before reporting success.
- skill change: SKILL.md's adoption caveats describe the staging behavior (wording landed with 7f526ab; recorded at v0.2.1).

### check-upstream-offline: status sweeps never fetch
- status: graduated (v0.2.0)
- root cause: `check-upstream.sh` without `--offline` fetches every vendor repo; `remotion-dev/remotion` is a monorepo whose cold fetch exceeds a 45s budget and reads as a timeout.
- evidence: manual.
- workaround: always pass `--offline` for status sweeps; fetch only when actually syncing.
- skill change: SKILL.md's status flow uses `check-upstream.sh --offline` (in SKILL.md at v0.2.0).

### drift-means-provenance-lying: exit 2 is about SOURCE.md, not breakage
- status: open
- root cause: a `verbatim` file edited after adoption makes `SOURCE.md` claim something false; that is the only condition `check-upstream.sh` exits non-zero for, and it is easy to misread as "the skill is broken".
- evidence: manual.
- workaround: fix by reverting the file, or `--regenerate` to reclassify it as `adapted` — then write down why.

### record-only-what-happened: pins and accepts assert history
- status: open
- root cause: `sync-upstream.sh --accept` asserts the skill is reconciled with upstream at that ref, and a pin asserts what was taken; using either to silence an exit code records a sync or a port that never happened — the exact failure the provenance system exists to prevent.
- evidence: manual; the twelve mattpocock skills sit pinned at `b8be62f` (May 2026) rather than `v1.2.3` because the 335 intervening commits were never ported.
- workaround: pin to what was actually taken; pass `--accept` only after genuinely reconciling every adapted file.

### never-autodelete-upstream-removals: our links outlive their files
- status: open
- root cause: upstream removing a reference file says nothing about whether our adapted `SKILL.md` still links to it; syncing `tdd` to v1.2.3 wanted to drop three files that were all still linked.
- evidence: manual (tdd sync attempt).
- workaround: before accepting a deletion, grep the skill for links to the file; keep and reclassify if linked.

### skill-outlives-upstream: orphaned is a terminal status
- status: open
- root cause: `caveman` and `zoom-out` were deleted from `mattpocock/skills` after adoption; there is nothing to sync, ever, and a naive drift reading reports them as "behind".
- evidence: manual.
- workaround: they are marked `status: orphaned`; report them as orphaned, never as behind.

### upstream-renames-head-path: renames are common, not removals
- status: open
- root cause: upstream renames (`diagnose` → `diagnosing-bugs`, `to-issues` → `to-tickets`, `to-prd` → `to-spec`) look like "path missing upstream" unless the pin's `head_path` is used to diff across the move.
- evidence: manual.
- workaround: trust `head_path`; investigate a "missing upstream" only after checking for a rename.

### path-map-subdir-renames: unmapped directories misclassify wholesale
- status: open
- root cause: `remotion/references/` is upstream's `rules/`; without `path_map` all 37 files misclassify as `ours`. `sync-upstream.sh` does not follow `path_map` yet and refuses to run rather than write files to the wrong place.
- evidence: manual (remotion adoption).
- workaround: declare `path_map` in `CONFIG.yaml:upstream` for any renamed subdirectory; expect sync to refuse until it learns to follow the map.

---

## Learnings (Graduated from Past Iterations)

- v0.2.1 (2026-09-01): `develop-skill-non-interactive` — piped-answer invocation and verify step into SKILL.md; `ship-skill-staging` recorded as superseded by framework fix 7f526ab.
- v0.2.0 and earlier: `deploy-skill-path-and-mode`, `check-upstream-offline` — wording already in SKILL.md before the pattern schema existed; marked graduated at conversion.

---

## Known Failure Patterns

No failing trace (outcome 1 or 2) in 16 runs. The recurring mark-downs are the two develop-skill/status entries above.

---

## Iteration Log

| Date | Version | Change Type | Description | Patterns |
|------|---------|-------------|-------------|----------|
| 2025-02-13 | 0.1.0 | Initial | Created; history before the iteration log is in git. | - |
| 2026-08-10 | 0.2.0 | Revision | Adoption workflow, upstream drift checks, format-2 epilogue. | - |
| 2026-09-01 | 0.2.1 | Compaction | First compaction: 16 traces (mean 4.9, none failing) root-caused; one new pattern graduated (piped develop-skill invocation), free-form wiki converted to the pattern schema (11 entries, 5 graduated, 6 open). | develop-skill-non-interactive, ship-skill-staging |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- `direct-request-skips-status` — make the status sweep conditional if runs keep self-docking for skipping it.
- The six open adoption patterns — candidates for `docs/adopting-external-skills.md` cross-links rather than SKILL.md graduation; revisit when adoption traces start arriving.
