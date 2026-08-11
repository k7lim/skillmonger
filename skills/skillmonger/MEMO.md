# MEMO — skillmonger

Edge cases and failure modes. Loaded when the skill fails.

## Script invocation gotchas

**`deploy-skill.sh` takes a path and a mode.** `scripts/deploy-skill.sh my-skill`
fails with a confusing `cd: my-skill: No such file or directory`. It wants
`scripts/deploy-skill.sh skills/my-skill --global`. Omitting the mode gives
`ERROR: Specify --global, --store-only, and/or --local <dir>`.

**`ship-skill.sh` blocks on a prompt.** After copying the standard files it asks
about anything extra — `assets/`, `SOURCE.md`, `OVERLAY.md`. Piping input to it
does not reliably answer the prompt; it will hang and get killed, leaving the
skill half-shipped with `SKILL.md` and `references/` present but `assets/`
missing. Check what actually landed before reporting success.

**`check-upstream.sh` with no `--offline` fetches every vendor repo.** One of
them is `remotion-dev/remotion`, a monorepo whose cold fetch exceeds a 45s
budget and gets reported as a timeout. For status sweeps always pass
`--offline`.

## Adoption failure modes

**Local drift means the provenance is lying, not that the skill is broken.** A
`verbatim` file was edited after adoption, so `SOURCE.md` now claims something
false. This is the only condition `check-upstream.sh` exits non-zero for. Fix by
reverting, or by `--regenerate` to reclassify the file as `adapted` — then write
down why.

**Never re-pin without reconciling.** `sync-upstream.sh --accept` asserts the
skill is reconciled with upstream at that ref. Passing it to make an exit-2 go
away silently discards upstream changes to every adapted file.

**Never auto-delete because upstream did.** Upstream removing a reference file
says nothing about whether our adapted `SKILL.md` still links to it. Syncing
`tdd` to v1.2.3 wants to drop three files that are all still linked.

**A skill can outlive its upstream.** `caveman` and `zoom-out` were deleted from
`mattpocock/skills` after we adopted them. They are marked `status: orphaned`
and there is nothing to sync, ever. Do not report them as "behind".

**Upstream renames are common.** `diagnose` → `diagnosing-bugs`, `to-issues` →
`to-tickets`, `to-prd` → `to-spec`. These carry `head_path` so drift still
diffs across the move. A plain "path missing upstream" reading would be wrong.

**Subdirectory renames need `path_map`.** `remotion/references/` is upstream's
`rules/`. Without the mapping, all 37 files misclassify as `ours`.
`sync-upstream.sh` does not follow `path_map` yet and refuses to run rather than
writing files to the wrong place.

## Pinning

Pin to what was **actually taken**, never to the newest release just because it
exists. The twelve mattpocock skills sit at `b8be62f` (May 2026) rather than
`v1.2.3`, because the 335 intervening commits were never ported. Recording a
sync that did not happen is the exact failure this whole system exists to
prevent.
