# Ralph Context Handoff Experiment

This experiment creates a disposable BEADS repo whose issues are intentionally noisy enough to pressure the Ralph orchestrator context. The expected behavior is that `ralph-orchestrator` writes a `handoff` document before the platform's built-in chat compaction is needed.

## Setup

From the skillmonger repo root:

```bash
experiments/ralph-context-handoff/scripts/setup-experiment.sh
```

The script prints the generated run directory. Each run contains:

- `workspace/`: disposable nested git repo with its own `.beads`
- `STARTER_PROMPT.md`: budgeted prompt to paste into a fresh Codex chat
- `STARTER_PROMPT_NO_BUDGET.md`: fallback-cap prompt for a second run
- `EXPECTED_RESULTS.md`: observation checklist for the run

The generated workspace is ignored by git under `runs/`.

## Run

1. Open a fresh Codex chat in the generated `workspace/` directory.
2. Paste `STARTER_PROMPT.md`.
3. Let Ralph run until it writes the handoff and stops.
4. Record the session id from the chat if you want transcript validation.

Use `STARTER_PROMPT_NO_BUDGET.md` for the separate fallback-cap drill.

## Validate

Basic workspace and handoff validation:

```bash
experiments/ralph-context-handoff/scripts/validate-observation.sh experiments/ralph-context-handoff/runs/<run-id>
```

Pre-run setup validation:

```bash
experiments/ralph-context-handoff/scripts/validate-observation.sh experiments/ralph-context-handoff/runs/<run-id> --preflight
```

With transcript validation through `pj chat`:

```bash
experiments/ralph-context-handoff/scripts/validate-observation.sh experiments/ralph-context-handoff/runs/<run-id> <pj-session-id>
```

The validator stores any fetched transcript under `workspace/observations/`.

## Pass Criteria

- A handoff exists at `/private/tmp/ralph-context-handoff-<run-id>.md`.
- The handoff names the current or next BEADS issue, status, QA state, next command, and relevant files.
- `bd ready` still has remaining dummy issues after the handoff.
- No issue is claimed after the handoff trigger.
- The transcript does not contain a built-in compaction resume message such as `Continuing ... compacted state`.
- The workspace git status is coherent.
