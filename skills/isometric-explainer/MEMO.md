# MEMO — isometric-explainer

Edge cases and failure modes. Loaded when the skill fails.

## Adoption notes

Adopted from `LaurentiuGabriel/learnscape` at `5c8af77`. Everything except
`SKILL.md` is upstream verbatim — do not edit `references/`, `assets/`, or
`scripts/smoke.mjs`. Changes go in `OVERLAY.md`, or `scripts/check-upstream.sh`
will flag them as local drift.

## Known failure modes

**The canvas is blank and nothing errored.** The most common cause is a
`<script>` tag out of order in `index.html`. `iso.js` must load before
`world.js`, which must load before `sim.js` and `render.js`. `smoke.mjs` catches
this by checking for the `Iso`/`World`/`Sim`/`Renderer`/`UI` globals — if it
reports missing globals, it is a load-order problem, not a drawing problem.

**`node --check js/*.js` silently passes with broken files.** `node --check`
takes exactly one file and treats the rest as arguments. Always loop. The
evaluate script does this correctly; a hand-run check often does not.

**Playwright cannot be found even though it is installed.** It resolves from the
project's `node_modules`, not the skill's. Run `npm i -D playwright` in the
project directory. `scripts/check-prereqs.sh` reports what is actually resolvable
from `$PWD`.

**Reported as working on `node --check` alone.** This skill's whole verification
story is the smoke test plus a human looking at the screenshot. Without
Playwright, `scripts/evaluate.sh` caps the outcome at 3 and says UNVERIFIED. Do
not round that up.

**The template is the subject.** Copying `assets/template` and only renaming
things produces a PacketPost clone. `model.js` and `world.js` are meant to be
written from scratch for the new domain; only `iso.js`, `sim.js`, and `main.js`
are copied unchanged.

## Portability

`${CLAUDE_SKILL_DIR}` does not exist outside Claude Code. Under Codex, Gemini, or
Pi, copy `scripts/smoke.mjs` next to `index.html` and run it there — it imports
nothing from the skill directory.
