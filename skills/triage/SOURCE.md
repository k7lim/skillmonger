<!-- generated-from-config:begin -->
<!-- Generated from CONFIG.yaml:upstream by scripts/adopt-skill.sh.
     Edit CONFIG.yaml, then re-run scripts/check-upstream.sh --regenerate. -->

# Source Attribution — triage

| | |
|---|---|
| Repository | https://github.com/mattpocock/skills |
| Upstream path | `skills/engineering/triage` |
| Pinned ref | `b8be62f` |
| Pinned commit | `b8be62ffacb0118fa3eaa29a0923c87c8c11985c` |
| License | MIT License |
| Status | tracked |
| Last synced | 2026-05-25 |
| Vendor checkout | `vendor/mattpocock-skills` |

<!-- generated-from-config:end -->

## Zones

`verbatim` files are byte-identical to upstream at the pinned commit and
are checksum-verified. Change one and it must be demoted to `adapted`
with a reason below — or, preferably, expressed in `OVERLAY.md` instead.

| File | Zone |
|---|---|
| `SKILL.md` | adapted |
| `AGENT-BRIEF.md` | verbatim |
| `OUT-OF-SCOPE.md` | verbatim |
| `CONFIG.yaml` | ours |
| `MEMO.md` | ours |

## Adaptation notes

Adapted from upstream in May 2026 for tool portability (Claude/Codex/Gemini) and for this repo's conventions. Most files show as `adapted` because months of editing happened before zone tracking existed; that is the honest state, not a target.

Backfilled on 2026-08-10, after the fact. Pinned at the commit this was actually taken from, not at the latest release — see `docs/adopting-external-skills.md`.

## Resyncing

```bash
scripts/check-upstream.sh triage
```
