---
status: accepted
date: 2026-08-30
---

# Version the skill format separately from each skill

Skillmonger had no framework version: every `version:` in the repo was a
per-skill semver, so "a breaking change to the quad-file contract" had no
referent. We record the contract version as `skill.format: N` in each skill's
CONFIG.yaml (missing means 1) and tag the repo `format-N.M` at each step, so
`validate-skill.sh` and migration scripts can tell a migrated skill from an
unmigrated one, and a skill copied out of the repo carries the contract its
epilogue follows. Per-skill semver keeps meaning what it meant.

## Considered options

- Git tags only: cheaper, but a deployed or re-exported skill carries no
  record of its contract.
- No framework version: a scripted rewrite of 53 epilogues cannot be made
  idempotent without something to key off.
