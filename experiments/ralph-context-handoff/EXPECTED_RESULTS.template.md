# Expected Results

Run id: `{{RUN_ID}}`
Workspace: `{{WORKSPACE}}`
Expected handoff: `/private/tmp/ralph-context-handoff-{{RUN_ID}}.md`

## Expected State

- `bd ready` still shows at least one unhandled dummy issue.
- `results.log` contains one line for each completed issue: `issue-N complete`.
- Closed issues have local commits only.
- No remote push was attempted.
- The handoff file exists in `/private/tmp`.

## Handoff Must Include

- current or next BEADS issue
- current status
- latest compact ledger summary
- QA result and gaps, if any
- next command for the fresh orchestrator
- likely relevant files

## Transcript Should Show

- `$ralph-orchestrator` was used.
- Budget/status checks happened at relay boundaries.
- The handoff trigger happened before another issue was claimed.
- No message resembling `Continuing the Ralph relay from the compacted state`.

## Validator

Run from the skillmonger repo root:

```bash
experiments/ralph-context-handoff/scripts/validate-observation.sh experiments/ralph-context-handoff/runs/{{RUN_ID}} [pj-session-id]
```

Before running Ralph, validate setup only:

```bash
experiments/ralph-context-handoff/scripts/validate-observation.sh experiments/ralph-context-handoff/runs/{{RUN_ID}} --preflight
```
