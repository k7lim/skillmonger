# MEMO — codebase-design

Edge cases and failure modes. Loaded when the skill fails.

## Adoption

Adopted from `mattpocock/skills` at `v1.2.3` on 2026-08-10. Everything except
`SKILL.md` is upstream verbatim — do not edit `references/` or other upstream
files, or `scripts/check-upstream.sh` will flag local drift. Changes go in
`OVERLAY.md`.

`SKILL.md` differs from upstream only by the appended "After Execution"
epilogue.

## Deferred adaptation

Assumes a `CONTEXT.md` holding the project's domain vocabulary. Point it at whatever this project actually uses, or skip that step.

## Portability

No harness-specific assumptions found at adoption: no `${CLAUDE_*}` variables, no
Claude-only tool names, no references to skills that exist in only one harness.
