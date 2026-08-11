# MEMO — implement

Edge cases and failure modes. Loaded when the skill fails.

## Adoption

Adopted from `mattpocock/skills` at `v1.2.3` on 2026-08-10. Everything except
`SKILL.md` is upstream verbatim — do not edit `references/` or other upstream
files, or `scripts/check-upstream.sh` will flag local drift. Changes go in
`OVERLAY.md`.

`SKILL.md` differs from upstream only by the appended "After Execution"
epilogue.

## Deferred adaptation

GATE 2 DEFERRED: assumes a GitHub-shaped issue tracker. In this repo issues are beads (`bd show <id>`, `bd update <id> --claim`). Translate ticket operations to bd, or ask the user which tracker applies.

## Portability

Upstream sets `disable-model-invocation: true`, a Claude Code frontmatter field
meaning the skill fires only when invoked explicitly, never automatically. That is
upstream's deliberate design and is preserved. Other harnesses ignore the field, so
there the skill may auto-trigger — if that is wrong for your setup, say so rather
than assuming the Claude Code behaviour holds everywhere.
