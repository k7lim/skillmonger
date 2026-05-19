# New Project Triage Memo

- Default unclear project ideas to `~/Development/sandbox/research/`; promoting research to a concrete project later is easier than demoting an over-scoped project.
- Use `~/Development/host/` only when host-level access is actually required, such as SSH keys, local system configuration, or credentials that are not mounted into sandbox.
- The upgraded behavior should act, not just advise: create the chosen directory and copy the user's original project notes into `NOTES.md` using `scripts/create-project.sh`.
- Never overwrite existing notes. If the same directory already has `NOTES.md`, add a timestamped notes file there when it is the same project, or choose a more specific folder name when it is unrelated.
