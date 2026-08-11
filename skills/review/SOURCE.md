<!-- generated-from-config:begin -->
<!-- Generated from CONFIG.yaml:upstream by scripts/adopt-skill.sh.
     Edit CONFIG.yaml, then re-run scripts/check-upstream.sh --regenerate. -->

# Source Attribution — review

| | |
|---|---|
| Repository | https://github.com/mattpocock/skills |
| Upstream path | `skills/engineering/code-review` |
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
| `CONFIG.yaml` | ours |
| `MEMO.md` | ours |

## Adaptation notes

Backfilled 2026-08-10. This was an **undeclared adoption**: the skill was taken
from upstream's `code-review` at some point before the adoption pipeline existed
and renamed to `review`, with no provenance recorded anywhere. It was found by
noticing that its description was near-identical to upstream's.

Two deliberate differences from upstream `v1.2.3`:

1. **Renamed `code-review` -> `review`.** Claude Code ships a built-in
   `/code-review` command; keeping upstream's name would collide with it.
2. **"issue/PRD" instead of "issue/spec"** in the description, matching the
   vocabulary used elsewhere in this repo.

Pinned at `v1.2.3` rather than at the original (unknown) adoption commit,
because the local file matches `v1.2.3` apart from those two edits — so this pin
is true. It is the one backfill where the latest release was the honest target.

`CONFIG.yaml`, `MEMO.md`, `SOURCE.md` are ours.

## Resyncing

```bash
scripts/check-upstream.sh review
```
