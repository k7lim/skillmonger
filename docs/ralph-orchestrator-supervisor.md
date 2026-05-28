# Ralph Orchestrator Supervisor Spec

## Purpose

Build a hybrid Ralph loop that bridges the old `rbl` bash loop with the newer `ralph-orchestrator` skill.

The goal is to keep the shell responsible for containment, process lifecycle, harness selection, retries, logs, and fresh-session handoff, while the agent orchestrator remains responsible for judgment: one issue at a time, one worker at a time, QA before close, coherent stop state, and proactive handoff before built-in chat compaction.

## Background

The older `rbl` alias path already proves the safety model:

- `~/.zshrc` only allows `rbl` under `~/Development/sandbox/...`.
- `rbl` dispatches by harness: `claude`, `kimi`, `codex`, and future `opencode`.
- `~/Development/sandbox/ralph-beads-loop.sh` uses harness-specific yolo flags.
- The Codex harness already runs:
  ```bash
  codex exec --dangerously-bypass-approvals-and-sandbox --ignore-rules --json --skip-git-repo-check
  ```
- The old loop owns useful infrastructure:
  - serialized `bd` commands
  - embedded Dolt lock retry
  - rate-limit handling
  - task retry accounting
  - interrupt cleanup
  - local completion gates

The newer `ralph-orchestrator` skill improves the decision layer:

- delegates implementation to exactly one subagent at a time
- keeps orchestration and QA in the top-level session
- independently verifies worker output
- closes issues only after QA
- writes a handoff before platform compaction or budget exhaustion
- preserves a compact ledger for fresh continuation

The desired system is not one or the other. It is a supervisor-managed chain of fresh orchestrator sessions.

## Design Principle

```text
shell supervisor lifespan: whole relay
orchestrator session lifespan: multiple issue cycles until guardrail fires
worker subagent lifespan: one implementation attempt
handoff file: boundary between orchestrator sessions
```

The orchestrator should not be restarted after every issue by default. It should process multiple issues while context is healthy, then hand off when it can no longer safely start the next issue.

## Goals

- Run Ralph unattended inside an externally isolated sandbox.
- Preserve the existing `rbl` safety property: dangerous agent flags are allowed only under `~/Development/sandbox/...`.
- Launch each orchestrator hop as a fresh top-level agent session.
- Allow each orchestrator hop to process multiple issues until its guardrail triggers.
- Use handoff files as the only continuation contract between orchestrator hops.
- Validate each hop before launching the next.
- Keep BEADS access serialized to avoid embedded Dolt false failures.
- Produce durable logs: prompts, JSONL agent stream, final message, handoff path, validation result, and session id when discoverable.

## Non-Goals

- Do not replace `ralph-orchestrator` with a pure bash implementation.
- Do not let the shell decide code correctness or acceptance criteria.
- Do not bypass sandbox checks on host repos.
- Do not rely on platform chat compaction as the continuation mechanism.
- Do not require one orchestrator session per issue unless an issue is high risk or the guardrail fires.

## Proposed Command Surface

Add a new supervisor script, initially in the experiment folder:

```bash
experiments/ralph-context-handoff/scripts/run-supervisor.sh [options] <workspace>
```

After proving it, promote a hardened version beside the old loop:

```bash
~/Development/sandbox/ralph-orchestrator-loop.sh
```

Suggested alias layer:

```zsh
# Orchestrated Ralph loop; sandbox only.
rol() { ralph-orchestrator-loop "$@"; }

# Harness-specific sugar.
col() { ralph-orchestrator-loop --harness codex "$@"; }
kol() { ralph-orchestrator-loop --harness kimi "$@"; }
clol() { ralph-orchestrator-loop --harness claude "$@"; }
```

The name should stay distinct from `rbl` until the new loop proves stable.

## Supervisor Options

Minimum:

```bash
--harness codex|claude|kimi
--mode budget|no-budget
--token-budget N
--max-hops N
--max-issues-total N
--handoff-dir DIR
--run-id ID
--validate-cmd CMD
--dry-run
```

Defaults:

```text
harness: codex
mode: no-budget
token-budget: 60000 when mode=budget
max-hops: 8
handoff-dir: /private/tmp
run-id: timestamp
validate-cmd: none unless experiment provides one
```

## Sandbox Enforcement

Before allowing harness yolo flags, the supervisor must enforce:

```bash
resolved_pwd="$(pwd -P)"
case "$resolved_pwd" in
  "$HOME"/Development/sandbox|"$HOME"/Development/sandbox/*) ;;
  *)
    echo "Refusing yolo supervisor outside ~/Development/sandbox" >&2
    exit 1
    ;;
esac
```

For experiment runs inside this repo, either:

- run the experiment workspace under `~/Development/sandbox/...`, or
- use a non-yolo/manual mode that does not bypass approvals.

The production supervisor should not accept `--dangerously-bypass-approvals-and-sandbox` outside the sandbox path check.

## Harness Ownership

Reuse the old loop's harness model.

Shell-owned:

- command construction
- yolo/permissive flags
- JSONL stream capture
- rate-limit detection
- process exit handling
- max hop limits
- serialized `bd` helper for supervisor checks

Orchestrator-owned:

- issue selection from `bd ready`
- deciding how much code/context to read
- worker packet construction
- spawning exactly one worker at a time
- QA
- close/commit/push workflow according to repo instructions
- deciding when handoff is due

## Handoff Contract

Each orchestrator hop must be started with:

```markdown
$ralph-orchestrator

Continue or start the Ralph relay for this workspace.

Run id: <run-id>
Hop: <n>
Expected handoff path: <handoff-dir>/ralph-orchestrator-<run-id>-hop-<n>.md

If a prior handoff is supplied, read it first and do not reread the previous chat:
<previous-handoff-path>

Use one worker subagent at a time. Process multiple BEADS issues until the context-budget guardrail says handoff is due. When handoff is due, write the expected handoff path and stop.
```

The handoff file must include:

- workspace
- run id and hop number
- current or next BEADS issue
- current status
- compact ledger
- QA result and gaps
- repository stop state
- exact next command
- likely relevant files
- whether built-in compaction was avoided

The supervisor should treat missing handoff as one of three outcomes:

- success if `bd ready` is empty and final response says relay complete
- failure if `bd ready` remains non-empty
- infrastructure stop if the agent hit rate limit or fatal tool failure

## Supervisor State Machine

```text
preflight
  -> launch_hop
  -> capture_stream
  -> classify_result
  -> validate_hop
  -> done | launch_next_hop | stop_failure
```

### Preflight

- Verify cwd is in sandbox for yolo mode.
- Verify `bd ready` works.
- Verify git repo state is understandable.
- Verify `ralph-orchestrator` and `handoff` skills are deployed in the target environment.
- Create run log directory:
  ```text
  .ralph-orchestrator-runs/<run-id>/
  ```

### Launch Hop

- Generate `prompt-hop-<n>.md`.
- Run the chosen harness.
- Capture:
  ```text
  hop-<n>.jsonl
  hop-<n>.stdout
  hop-<n>.stderr
  hop-<n>.final.md
  ```

For Codex:

```bash
codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  --ignore-rules \
  --json \
  --skip-git-repo-check \
  -C "$workspace" \
  "$prompt"
```

### Classify Result

Classifications:

- `complete`: no ready issues remain
- `handoff`: expected handoff exists and ready issues remain
- `rate_limited`: retryable provider condition
- `fatal_infra`: sandbox/tool rejection, broken `bd`, invalid workspace
- `bad_handoff`: handoff missing or unusable while work remains
- `agent_failure`: agent stopped without satisfying contract

### Validate Hop

Validation should be pluggable. For the current experiment:

```bash
experiments/ralph-context-handoff/scripts/validate-observation.sh <run-dir> [pj-session-id]
```

For production, a minimal validator should check:

- `bd ready` can be queried
- if handoff exists, it has continuation fields
- if workspace is dirty, handoff captures the dirty/staged state
- transcript/log does not contain compacted-state continuation markers
- no multiple-worker concurrency happened if detectable

### Continue

If classification is `handoff` and validation passes:

- increment hop
- pass the handoff path into the next prompt
- launch a new top-level orchestrator session

The supervisor, not the old orchestrator session, performs the actual process-level handoff.

## Relationship To Old `rbl`

Keep `rbl` for the worker-style direct loop:

```text
rbl = shell chooses issue, agent implements, shell gates tests/commit/close
```

Add the orchestrated loop for QA-heavy relay:

```text
rol = shell supervises sessions, orchestrator chooses issue and QA, workers implement
```

`rbl` is better for homogeneous small tasks where a single completion gate is enough.

`rol` is better when:

- acceptance criteria require judgment
- changes need review before close
- repair attempts need fresh workers
- context budget needs proactive handoff
- multi-issue sequencing matters

## Failure Handling

### Rate Limits

Reuse old `rbl` backoff:

- first rate limit: retry quickly
- repeated rate limits: exponential backoff with jitter
- hard stop after configured consecutive limit

### BEADS Locks

Reuse old `bd_cmd` wrapper:

- process-level lock directory
- retry embedded Dolt lock text
- print owner and `.beads/embeddeddolt/.lock` diagnostics

### Interrupted Hop

The supervisor should not try to infer partial issue state. It should:

- stop launching new hops
- preserve logs
- print recovery command using the last handoff if present
- if no handoff exists, instruct the user to inspect `bd ready`, `bd list --status in_progress`, and git status

### Bad Stop State

If the workspace is dirty and no handoff captures it, stop as failure.

If an issue is closed but files are staged/uncommitted without explanation, stop as failure.

If an issue is open with QA-passed work and a handoff names the exact close command, accept as coherent handoff.

## Observability

Each run should write:

```text
.ralph-orchestrator-runs/<run-id>/
  run.env
  supervisor.log
  hop-001/
    prompt.md
    stream.jsonl
    stdout.txt
    stderr.txt
    final.md
    handoff.md -> /private/tmp/...
    validation.txt
  hop-002/
    ...
```

Supervisor output should be terse:

```text
hop 1: handoff, 4 issues closed, 1 open QA-passed issue, validation passed
hop 2: handoff, 3 issues closed, validation passed
hop 3: complete, bd ready empty
```

## Rollout Plan

1. Extend the existing experiment with `run-supervisor.sh`.
2. Prove it on `ralph-context-handoff` with:
   - no-budget fallback cap
   - explicit budget
   - at least two orchestrator hops
3. Add a sandbox-only wrapper in `~/Development/sandbox/ralph-orchestrator-loop.sh`.
4. Add `rol`/`col` aliases in `.zshrc`.
5. Run against a disposable real-ish sandbox repo.
6. Promote patterns back into skillmonger source if stable.

## Acceptance Criteria

- Supervisor refuses yolo mode outside `~/Development/sandbox/...`.
- Supervisor can launch Codex orchestrator hops non-interactively.
- A hop can process multiple issues before handoff.
- Handoff launches a fresh top-level orchestrator session, not a subagent.
- Built-in chat compaction is never used as continuation.
- BEADS commands run through serialized access when shell-owned.
- Logs are sufficient to validate each hop after the fact.
- The existing experiment can complete across at least two hops.

## Open Questions

- Should the production supervisor live in skillmonger, sandbox tooling, or yolobox-pattern?
- Should `rbl` eventually delegate to the orchestrated loop for `codex`, or should both remain explicit?
- Should orchestrator hops use explicit token goals where available, or rely on fallback caps in non-interactive `codex exec`?
- How should the supervisor discover the Codex session id reliably for `pj` validation?
- Should dirty-but-documented handoffs be accepted in production, or only in experiments?
