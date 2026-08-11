<!-- generated-from-config:begin -->
<!-- Generated from CONFIG.yaml:upstream by scripts/adopt-skill.sh.
     Edit CONFIG.yaml, then re-run scripts/check-upstream.sh --regenerate. -->

# Source Attribution — diagnose

| | |
|---|---|
| Repository | https://github.com/mattpocock/skills |
| Upstream path | `skills/engineering/diagnose` |
| Pinned ref | `b8be62f` |
| Pinned commit | `b8be62ffacb0118fa3eaa29a0923c87c8c11985c` |
| License | MIT License |
| Status | renamed |
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
| `scripts/hitl-loop.template.sh` | verbatim |
| `CONFIG.yaml` | ours |
| `FEEDBACK.jsonl` | ours |
| `MEMO.md` | ours |

## Adaptation notes

Upstream renamed and substantially rewrote this skill (`skills/engineering/diagnose` -> `skills/engineering/diagnosing-bugs`). Our version diverged first: it was adapted to beads rather than GitHub issues. Treat upstream as a source of ideas to port deliberately, not a diff to apply.

Backfilled on 2026-08-10, after the fact. Pinned at the commit this was actually taken from, not at the latest release — see `docs/adopting-external-skills.md`.

## Resyncing

```bash
scripts/check-upstream.sh diagnose
```
