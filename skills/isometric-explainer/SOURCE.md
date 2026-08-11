<!-- generated-from-config:begin -->
<!-- Generated from CONFIG.yaml:upstream by scripts/adopt-skill.sh.
     Edit CONFIG.yaml, then re-run scripts/check-upstream.sh --regenerate. -->

# Source Attribution — isometric-explainer

| | |
|---|---|
| Repository | https://github.com/LaurentiuGabriel/learnscape |
| Upstream path | `skills/isometric-explainer` |
| Pinned ref | `5c8af77` |
| Pinned commit | `5c8af77808ba11bff6f4b46297dc45514247c4a5` |
| License | MIT License |
| Status | tracked |
| Last synced | 2026-08-10 |
| Vendor checkout | `vendor/learnscape` |

<!-- generated-from-config:end -->
## Zones

`verbatim` files are byte-identical to upstream at the pinned commit and
are checksum-verified. Change one and it must be demoted to `adapted`
with a reason below — or, preferably, expressed in `OVERLAY.md` instead.

| File | Zone |
|---|---|
| `SKILL.md` | adapted |
| `assets/template/README.md` | verbatim |
| `assets/template/css/styles.css` | verbatim |
| `assets/template/index.html` | verbatim |
| `assets/template/js/iso.js` | verbatim |
| `assets/template/js/main.js` | verbatim |
| `assets/template/js/model.js` | verbatim |
| `assets/template/js/render.js` | verbatim |
| `assets/template/js/sim.js` | verbatim |
| `assets/template/js/ui.js` | verbatim |
| `assets/template/js/world.js` | verbatim |
| `references/build-order.md` | verbatim |
| `references/checklist.md` | verbatim |
| `references/fidelity.md` | verbatim |
| `references/isometric-drawing.md` | verbatim |
| `references/narration.md` | verbatim |
| `references/pacing.md` | verbatim |
| `scripts/smoke.mjs` | verbatim |
| `CONFIG.yaml` | ours |
| `MEMO.md` | ours |
| `SOURCE.md` | ours |
| `scripts/check-prereqs.sh` | ours |
| `scripts/evaluate.sh` | ours |



## Adaptation notes

`SKILL.md` is the only adapted file. Three changes, all gate work:

1. **Portability (gate 1).** The `SKIP for:` clause named `dataviz` and
   `artifact-diagramming`, which exist only in Claude Code — the conditions are
   kept, the skill names dropped. `${CLAUDE_SKILL_DIR}` became a resolution
   snippet that falls back across `~/.claude`, `~/.codex`,
   `~/.config/opencode`, and `~/.pi/agent`, with "just copy `smoke.mjs` into the
   project" as the honest last resort.
2. **Prerequisites (gate 2).** Added a pointer to `scripts/check-prereqs.sh` so
   the Playwright gap surfaces before you build rather than at verification.
3. **Feedback epilogue.** Skillmonger's "After Execution" section, pointing at
   `scripts/evaluate.sh`.

No overlay is needed: nothing in `references/` or `assets/` required changing.
`scripts/smoke.mjs` is upstream verbatim and stays that way — `evaluate.sh`
wraps it rather than editing it, which is what keeps the 3,700-line engine
resyncable by checksum.

### Ours

- `scripts/evaluate.sh` — wraps upstream's `smoke.mjs` in the skillmonger
  evaluate contract. Caps the outcome at 3 with an UNVERIFIED note when
  Playwright cannot launch, so a project that only passed `node --check` never
  logs as working. Must invoke `smoke.mjs` with cwd set to the project:
  `smoke.mjs` resolves Playwright from `process.cwd()`.
- `scripts/check-prereqs.sh` — checks node, a static server, and whether
  Playwright's chromium **binary** exists, not merely that the package resolves.
  An upgraded Playwright routinely wants a browser build that was never
  downloaded, and that fails only at launch.
- `CONFIG.yaml`, `MEMO.md`, `SOURCE.md`.

### Verified at adoption

`scripts/evaluate.sh` run against upstream's own PacketPost template:
outcome 5, 9 stations visited, run finished, fidelity ledger present.

## Resyncing

```bash
scripts/check-upstream.sh isometric-explainer
```
