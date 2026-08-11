<!-- generated-from-config:begin -->
<!-- Generated from CONFIG.yaml:upstream by scripts/adopt-skill.sh.
     Edit CONFIG.yaml, then re-run scripts/check-upstream.sh --regenerate. -->

# Source Attribution — setup-pre-commit

| | |
|---|---|
| Repository | https://github.com/mattpocock/skills |
| Upstream path | `skills/misc/setup-pre-commit` |
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

`SKILL.md` is the only adapted file, and differs from upstream `v1.2.3` by
exactly one addition: the skillmonger "After Execution" epilogue. Nothing
upstream wrote was removed or reworded.

Everything else — `references/` and any other upstream file — is byte-identical
to `v1.2.3`, so future syncs are a checksum rather than a review. Adaptations
that would touch those go in `OVERLAY.md`.

`CONFIG.yaml`, `MEMO.md`, `SOURCE.md` are ours.

Gate 2 (dependency adaptation) was deliberately deferred this pass; anything
outstanding is recorded in `MEMO.md`.

## Resyncing

```bash
scripts/check-upstream.sh setup-pre-commit
```
