<!-- generated-from-config:begin -->
<!-- Generated from CONFIG.yaml:upstream by scripts/adopt-skill.sh.
     Edit CONFIG.yaml, then re-run scripts/check-upstream.sh --regenerate. -->

# Source Attribution — to-prd

| | |
|---|---|
| Repository | https://github.com/mattpocock/skills |
| Upstream path | `skills/engineering/to-spec` |
| Previous upstream path | `skills/engineering/to-prd` |
| Pinned ref | `v1.2.3` |
| Pinned commit | `6acc160e4e0cd062dbbbd7a1b26ae92855edf07e` |
| License | MIT License |
| Status | tracked |
| Last synced | 2026-08-10 |
| Vendor checkout | `vendor/mattpocock-skills` |

<!-- generated-from-config:end -->
## Zones

`verbatim` files are byte-identical to upstream at the pinned commit and
are checksum-verified. Change one and it must be demoted to `adapted`
with a reason below — or, preferably, expressed in `OVERLAY.md` instead.

| File | Zone |
|---|---|
| `SKILL.md` | adapted |
| `agents/openai.yaml` | verbatim |
| `CONFIG.yaml` | ours |
| `MEMO.md` | ours |
| `SOURCE.md` | ours |


## Adaptation notes

Upstream renamed and substantially rewrote this skill (`skills/engineering/to-prd` -> `skills/engineering/to-spec`). Our version diverged first: it was adapted to beads rather than GitHub issues. Treat upstream as a source of ideas to port deliberately, not a diff to apply.

Backfilled on 2026-08-10, after the fact. Pinned at the commit this was actually taken from, not at the latest release — see `docs/adopting-external-skills.md`.

## Resyncing

```bash
scripts/check-upstream.sh to-prd
```
