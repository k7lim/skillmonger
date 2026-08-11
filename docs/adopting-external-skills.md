# Adopting External Skills

How to take a skill someone else wrote and make it a skillmonger skill without
losing the ability to pull their improvements later.

The failure mode this exists to prevent: in May 2026 twelve skills were adopted
from `mattpocock/skills` and adapted well, but nothing recorded where they came
from. By August upstream was 335 commits ahead, two of the twelve had been
deleted upstream and three renamed — and none of that was visible from inside
this repo. Adaptation was never the hard part. Provenance is.

## The three gates

Every adoption must clear these before it lands in `skills/`. They come from the
original adoption interview and still hold.

1. **Tool portability.** The skill must work under Claude Code, Codex, and
   Gemini. Rewrite Claude-only nouns: `${CLAUDE_SKILL_DIR}` → `$SKILL_DIR` with a
   resolution note, "the Agent tool" → "a subagent, if your harness has one",
   `/skill-name` invocation → "invoke this skill". Cross-references to skills
   that only exist in one harness (`dataviz`, `artifact-diagramming`) become
   conditional, not assumed.
2. **Dependency adaptation.** Every concretion the upstream author assumed is
   either validated as useful here or replaced. GitHub issues become beads. Their
   `CONTEXT.md`/ADR layout becomes ours or gets dropped. External binaries get a
   `scripts/check-prereqs` so the skill degrades with a clear message instead of
   failing mid-run.
3. **Upstream updatability.** Non-negotiable, and the gate that silently failed
   last time. The skill records where it came from, at which commit, and which of
   its files are still byte-identical to upstream. `scripts/check-upstream.sh`
   must be able to report drift without a human remembering anything.

## Zone policy: strict verbatim

Every file in an adopted skill has exactly one zone. The zones are what make
resync cheap.

| Zone | Meaning | How drift is detected |
|---|---|---|
| `verbatim` | byte-identical to upstream at the pinned commit | sha256 comparison |
| `adapted` | we rewrote it; upstream changes need a human read | semantic diff |
| `ours` | no upstream counterpart | not checked |

**Default everything to `verbatim`. `SKILL.md` is normally the only `adapted`
file.** Skillmonger's own furniture — `CONFIG.yaml`, `MEMO.md`, `SOURCE.md`,
`FEEDBACK.jsonl`, `scripts/evaluate`, `scripts/check-prereqs` — is `ours`.

This matters most for bulky skills. `learnscape/isometric-explainer` ships 3,700
lines of engine JavaScript that upstream explicitly says to copy unchanged. Kept
verbatim, resync is a checksum. Edited freely, resync is a 3,700-line review
every time.

When an adaptation *would* touch a verbatim file, don't. Put it in `OVERLAY.md`
and have `SKILL.md` point at it:

> `references/pacing.md` is upstream's. Where it says to store reading state in
> `localStorage`, see `OVERLAY.md` — we use the project's own state file.

A file only becomes `adapted` when an overlay genuinely can't express the change.
Record why in `SOURCE.md`.

## Provenance: two files, one source of truth

`CONFIG.yaml` holds the machine-readable block. `SOURCE.md` holds the human
account and the zone table. **`CONFIG.yaml` is authoritative** — the header of
`SOURCE.md` is generated from it, and `check-upstream.sh` errors if they disagree.
That way "two places to keep in sync" is a validated invariant rather than a
promise.

### `CONFIG.yaml`

```yaml
upstream:
  repo: https://github.com/mattpocock/skills
  vendor: vendor/mattpocock-skills
  path: skills/productivity/grill-me
  ref: v1.2.3
  commit: 6acc160e4e0cd062dbbbd7a1b26ae92855edf07e
  license: MIT
  synced: 2026-08-10
  status: tracked
```

`status` values:

- `tracked` — upstream path still exists at the pinned ref. Normal case.
- `renamed` — upstream moved it. Keep `path` pointing at the current upstream
  location and record `previous_path` so history stays diffable.
- `orphaned` — upstream deleted it. `path` is the last known location and
  `last_seen_ref` is where it lived. The skill is ours alone now; drift checks
  report it as unmaintained upstream rather than broken.

Pin to a **release tag** when the upstream repo publishes them, a commit SHA
otherwise. `commit` is always the resolved SHA — tags move.

### `SOURCE.md`

Generated header, then the zone table, then adaptation notes explaining every
`adapted` file and every overlay. See `skills/remotion/SOURCE.md` for the format
this grew out of.

## The workflow

```bash
# 1. Vendor the upstream repo, pinned. Idempotent.
scripts/adopt-skill.sh https://github.com/LaurentiuGabriel/learnscape \
  skills/isometric-explainer --ref 5c8af77

# 2. Build in the sandbox against the three gates above.
cd ~/Development/sandbox/skills/isometric-explainer
# ... adapt SKILL.md, add CONFIG.yaml/MEMO.md/evaluate, write OVERLAY.md ...

# 3. Ship and deploy as normal.
cd ~/Development/host/skillmonger
scripts/ship-skill.sh ~/Development/sandbox/skills/isometric-explainer
scripts/deploy-skill.sh isometric-explainer
```

`adopt-skill.sh` clones into `vendor/` (gitignored), resolves the ref to a SHA,
copies the upstream skill into the sandbox, and writes `CONFIG.yaml:upstream` and
a `SOURCE.md` with every file marked `verbatim`. You demote files to `adapted` as
you change them — or rather, `check-upstream.sh --regenerate` does it for you by
observing which files no longer match, so the zone table reflects reality instead
of intention.

Pass `--in-place` to backfill provenance onto a skill already in `skills/`.

## Checking for upstream changes

```bash
scripts/check-upstream.sh              # every adopted skill
scripts/check-upstream.sh grill-me     # one
scripts/check-upstream.sh --offline    # no network; local drift only
```

It reports three independent things, and they mean different things:

- **Upstream drift** — upstream moved past our pin. Read the diff, port what's
  worth porting, re-pin.
- **Local drift** — a `verbatim` file no longer matches upstream. Either someone
  edited it (move it to `adapted` with a reason, or revert) or the pin is wrong.
- **Orphaned** — upstream deleted the skill. Nothing to sync, ever. Consider
  dropping the `upstream` block entirely and keeping it as an original.

Exit code is non-zero when there is local drift, because that is the case where
the recorded provenance is actively lying.

## Handling upstream updates

`check-upstream.sh` detects; `sync-upstream.sh` applies. The zone policy is what
makes applying safe — a `verbatim` file is *provably* unmodified by us, so
upstream's newer version can replace it without losing anything.

```bash
scripts/sync-upstream.sh grill-me --dry-run        # what would change
scripts/sync-upstream.sh grill-me --to v1.2.3      # do it
scripts/sync-upstream.sh grill-me --to v1.2.3 --accept   # after reviewing
```

With no `--to`, it targets the **latest upstream release tag**, falling back to
the default branch for untagged repos. `mattpocock/skills` started tagging in
June 2026 (`v1.0.0` … `v1.2.3`), so releases are the right unit there; adopt-time
pins from before that are raw SHAs and stay valid.

Per file:

| Zone | Upstream changed it | Upstream deleted it | Upstream added it |
|---|---|---|---|
| `verbatim` | fast-forwarded automatically | reported, never deleted | added |
| `adapted` | **blocks**; you get before/after to diff | reported | — |
| `ours` | untouched | untouched | untouched |

Two rules keep this honest:

**A sync is all-or-nothing.** If anything needs a human, nothing is written. A
partially-applied sync would leave fast-forwarded files matching neither the old
pin nor any recorded state, and `check-upstream.sh` would then correctly — and
confusingly — report them as local drift. Reconcile, then re-run with `--accept`
to apply everything and re-pin together.

**Deletions are never automatic.** Upstream dropping a reference file says
nothing about whether *our* adapted `SKILL.md` still links to it. Syncing `tdd`
to `v1.2.3` wants to remove `deep-modules.md`, `interface-design.md`, and
`refactoring.md` — all three are still linked from our `SKILL.md`, so the script
reports `STILL REFERENCED BY` and leaves them alone. It prints the `rm` for the
ones nothing references; running it is your call.

Re-pinning is the claim "this skill is reconciled with upstream at REF". The
script only makes that claim when it is true, which is why `--accept` exists as a
separate, deliberate step rather than a `--force`.

### What a real sync looks like

```
$ scripts/sync-upstream.sh tdd --to v1.2.3
tdd: b8be62f (b8be62ff) -> v1.2.3 (6acc160e)
  1 unchanged, 1 to fast-forward, 1 new, 3 removed upstream, 1 need review
    FF   tests.md
    NEW  agents/openai.yaml
    !!   SKILL.md  (adapted — upstream changed it too)
    DEL? deep-modules.md  (upstream removed it)  STILL REFERENCED BY SKILL.md
    ...
Nothing was written and the pin stays at b8be62f.
```

Exit codes: `0` synced or already current, `2` needs review, `1` error.

Note the `NEW agents/openai.yaml`. Upstream added per-skill OpenAI manifests
after our adoption — that is their answer to gate 1, and syncing picks it up for
free. Worth taking on the skills where it exists.

## Licensing, and publishing our own

Adopted skills carry the upstream license. `upstream.license` in `CONFIG.yaml`
exists so this is answerable by script rather than by memory.

Both current sources are MIT, which permits redistribution with attribution. If
this repo ever publishes a public skills distribution, that attribution has to
travel with the skills — the generated `SOURCE.md` in each skill directory is the
attribution, which is why it lives inside the skill and not in a central index.
Anything adopted under a license that forbids redistribution (`skills/remotion`
is under the Remotion license, not MIT) must be excluded from a public bundle;
`check-upstream.sh --licenses` lists what each adopted skill is under.

## Current adoptions

| Source | Vendored at | Skills |
|---|---|---|
| `mattpocock/skills` | `vendor/mattpocock-skills` | 12 (see backfill note below) |
| `LaurentiuGabriel/learnscape` | `vendor/learnscape` | `isometric-explainer` |
| `remotion-dev/remotion` | `vendor/remotion-skills` | `remotion` |

The twelve mattpocock skills were adopted before this process existed and were
backfilled against `v1.2.3` on 2026-08-10. Because they were adapted for months
with no zone tracking, most of their files came back `adapted` rather than
`verbatim` — that is the honest state, not a target. New adoptions should start
almost entirely `verbatim` and stay that way.
