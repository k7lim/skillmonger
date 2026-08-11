<!-- generated-from-config:begin -->
<!-- Generated from CONFIG.yaml:upstream by scripts/adopt-skill.sh.
     Edit CONFIG.yaml, then re-run scripts/check-upstream.sh --regenerate. -->

# Source Attribution — remotion

| | |
|---|---|
| Repository | https://github.com/remotion-dev/remotion |
| Upstream path | `packages/skills/skills/remotion` |
| Pinned ref | `805a30b` |
| Pinned commit | `805a30b705841c53ab0b19602972ebb5ece6a324` |
| License | Remotion License (NOT redistributable) |
| Status | tracked |
| Last synced | 2026-01-26 |
| Vendor checkout | `vendor/remotion-skills` |

<!-- generated-from-config:end -->
## Zones

`verbatim` files are byte-identical to upstream at the pinned commit and
are checksum-verified. Change one and it must be demoted to `adapted`
with a reason below — or, preferably, expressed in `OVERLAY.md` instead.

| File | Zone |
|---|---|
| `SKILL.md` | adapted |
| `references/3d.md` | verbatim |
| `references/animations.md` | verbatim |
| `references/assets.md` | verbatim |
| `references/assets/charts-bar-chart.tsx` | verbatim |
| `references/assets/text-animations-typewriter.tsx` | verbatim |
| `references/assets/text-animations-word-highlight.tsx` | verbatim |
| `references/audio.md` | verbatim |
| `references/calculate-metadata.md` | verbatim |
| `references/can-decode.md` | verbatim |
| `references/charts.md` | verbatim |
| `references/compositions.md` | verbatim |
| `references/display-captions.md` | verbatim |
| `references/extract-frames.md` | verbatim |
| `references/fonts.md` | verbatim |
| `references/get-audio-duration.md` | verbatim |
| `references/get-video-dimensions.md` | verbatim |
| `references/get-video-duration.md` | verbatim |
| `references/gifs.md` | verbatim |
| `references/images.md` | verbatim |
| `references/import-srt-captions.md` | verbatim |
| `references/lottie.md` | verbatim |
| `references/maps.md` | verbatim |
| `references/measuring-dom-nodes.md` | verbatim |
| `references/measuring-text.md` | verbatim |
| `references/parameters.md` | verbatim |
| `references/sequencing.md` | verbatim |
| `references/tailwind.md` | verbatim |
| `references/text-animations.md` | verbatim |
| `references/timing.md` | verbatim |
| `references/transcribe-captions.md` | verbatim |
| `references/transitions.md` | verbatim |
| `references/trimming.md` | verbatim |
| `references/videos.md` | verbatim |
| `CONFIG.yaml` | ours |
| `MEMO.md` | ours |
| `SOURCE.md` | ours |
| `scripts/check-prereqs.sh` | ours |

## Adaptation notes

`SKILL.md` is the only adapted file — retitled and trimmed for skillmonger's
loading conventions. Everything under `references/` is upstream's `rules/`
verbatim, recorded via `path_map` in `CONFIG.yaml`; that rename is the only
structural difference from upstream.

`scripts/check-prereqs.sh` is ours.

## Licensing — read before redistributing

**This skill is the one adoption that must NOT go into a public bundle.**
Remotion ships under the Remotion License, not MIT: free for individuals and
small companies, but it is not a permissive redistribution grant. See
`LICENSE.md` in the upstream repo. Every other adopted skill is MIT and carries
attribution in its own `SOURCE.md`.

`scripts/check-upstream.sh --licenses` flags this.

## Resyncing

```bash
scripts/check-upstream.sh remotion
scripts/sync-upstream.sh remotion --dry-run
```

`sync-upstream.sh` does not yet follow `path_map`, so remotion must be synced by
hand for now:

```bash
git -C vendor/remotion-skills pull origin main
cp -r vendor/remotion-skills/packages/skills/skills/remotion/rules/* skills/remotion/references/
scripts/check-upstream.sh remotion --regenerate
```
