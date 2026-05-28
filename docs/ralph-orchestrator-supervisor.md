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

## Safety Invariants

These invariants are the parts of the system that must stay true even when a worker fails, an agent times out, `bd` is locked, or the provider returns a partial stream.

- **Yolo flags are path-gated.** Any harness invocation that bypasses sandboxing or approvals must happen only after resolving the workspace with `pwd -P` and proving it is under `~/Development/sandbox/...`.
- **The shell never accepts work on content alone.** The supervisor may classify process outcomes, check files, check `bd`, and run validators. It must not decide that code is correct without the orchestrator's QA result.
- **The orchestrator never self-resumes through chat compaction.** A hop either finishes the relay, writes the expected handoff, or fails the hop contract.
- **One implementation worker is active at a time.** The orchestrator owns this rule, and the supervisor validates it where the transcript or stream exposes enough evidence.
- **BEADS calls are serialized when shell-owned.** Supervisor preflight, classification, and validation use a single `bd_cmd` wrapper with retry behavior for embedded Dolt locks.
- **Dirty state must be explained.** A non-clean workspace is allowed only when the handoff names the state, the reason, and the exact next landing or cleanup command.
- **Stop states are explicit.** The supervisor ends in one of: `complete`, `handoff`, `rate_limited`, `fatal_infra`, `bad_handoff`, `agent_failure`, or `manual_intervention`.

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

Recommended additional options before production use:

```bash
--no-yolo
--max-rate-limit-retries N
--rate-limit-base-sleep SECONDS
--bd-lock-timeout SECONDS
--require-clean-start
--stop-after-hop
--keep-going-on-validation-warning
```

Defaults:

```text
harness: codex
mode: no-budget
token-budget: 60000 when mode=budget
max-hops: 8
max-rate-limit-retries: 3
bd-lock-timeout: 120
handoff-dir: /private/tmp
run-id: timestamp
validate-cmd: none unless experiment provides one
require-clean-start: true
```

Exit codes:

```text
0  relay complete or handoff ready for next hop
2  usage or invalid options
10 sandbox/yolo safety refusal
11 preflight failure
12 validation failure
13 bad or missing handoff while work remains
14 harness process failure
15 rate limit retry budget exhausted
16 manual intervention required
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
- run directory creation
- prompt and environment snapshots
- validator invocation
- recovery command printing

Orchestrator-owned:

- issue selection from `bd ready`
- deciding how much code/context to read
- worker packet construction
- spawning exactly one worker at a time
- QA
- close/commit/push workflow according to repo instructions
- deciding when handoff is due

Shared contract:

- The shell tells the orchestrator the expected handoff path and hop number.
- The orchestrator writes only that handoff path unless it has a concrete reason to stop without one.
- The shell checks whether the expected path exists and whether it contains the minimum continuation fields.
- If the shell and orchestrator disagree, the shell stops and preserves logs instead of guessing.

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

Minimum handoff shape:

~~~markdown
# Ralph Orchestrator Handoff

Workspace: <absolute path>
Run id: <run-id>
Hop: <n>
Previous hop status: <handoff|manual_intervention|rate_limited|fatal_infra>
Built-in compaction avoided: <yes|no|unknown>

## BEADS State
- Current issue: <id and title, or none>
- Next issue: <id and title, or unknown>
- Ready issues remaining: <count or command to check>
- In-progress issues: <ids or none>

## Ledger
- <compact issue-cycle summary>

## QA
- Result: <passed|failed|not-run|blocked>
- Evidence: <commands or inspection>
- Gaps: <remaining uncertainty>

## Repository State
- Branch: <branch>
- Git status: <clean or exact dirty summary>
- Staged files: <files or none>
- Uncommitted files: <files or none>

## Next Step
Run:

```bash
<exact next command>
```

Relevant files:
- <path>
~~~

The validator can start with vocabulary checks, but production should parse these headings rather than rely on broad grep patterns.

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
- Verify the run directory does not already exist, unless `--resume-run` is added later.
- Verify the expected handoff path for hop 1 is clear, or record that a deliberate resume is in progress.
- Verify `--validate-cmd`, if supplied, is executable from the supervisor environment.
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
- `manual_intervention`: coherent state exists, but a human decision is required before another hop

Classification order matters:

1. If the harness failed before an agent session started, classify as `fatal_infra`.
2. If rate-limit text is present and retry budget remains, classify as `rate_limited`.
3. If `bd ready` is empty and final output says the relay is complete, classify as `complete`.
4. If the expected handoff exists, validate it and classify as `handoff` or `manual_intervention`.
5. If ready work remains and no handoff exists, classify as `bad_handoff`.
6. Otherwise classify as `agent_failure`.

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
- final output does not instruct the next hop to continue from chat history
- run log contains prompt, stream, stdout, stderr, final output, and validator result

Validation levels:

```text
preflight  checks the workspace can be safely launched
hop        checks one completed hop and its handoff or completion state
run        checks the aggregate run directory after multiple hops
```

Suggested validator interface:

```bash
validate-supervisor-run.sh --level preflight <run-dir>
validate-supervisor-run.sh --level hop --hop 001 <run-dir>
validate-supervisor-run.sh --level run <run-dir>
```

The script should print human-readable `PASS`/`FAIL` lines and exit non-zero on any required failure. Optional checks should print `WARN` and should not be hidden; the supervisor can decide whether warnings stop the run.

### Continue

If classification is `handoff` and validation passes:

- increment hop
- pass the handoff path into the next prompt
- launch a new top-level orchestrator session

The supervisor, not the old orchestrator session, performs the actual process-level handoff.

## Implementation Sketch

The first production-quality shell script can stay intentionally boring:

```text
main
  parse_args
  resolve_workspace
  preflight
  while hop <= max_hops:
    make_hop_dir
    write_prompt
    run_harness_capture_stream
    classify_result
    run_validator
    case classification:
      complete: print_summary; exit 0
      handoff: hop++; continue
      rate_limited: sleep_and_retry_same_hop
      manual_intervention: print_recovery; exit 16
      *: print_failure_context; exit mapped_code
  stop max_hops exceeded
```

Keep helpers small and testable:

```text
resolve_workspace
assert_sandbox_for_yolo
bd_cmd
write_prompt
run_codex_harness
classify_result
validate_handoff_minimum
print_recovery_command
```

Avoid global mutable state except for `RUN_DIR`, `WORKSPACE`, `RUN_ID`, and `HOP`. Every helper should take explicit paths where practical so shell unit tests can exercise it with fixture directories.

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

## Testing And Validation Plan

Yes, this can be built safely if the first implementation is test-first around the supervisor boundaries and only later allowed to use yolo harness flags.

### Test Layers

1. **Static checks**
   - `bash -n experiments/ralph-context-handoff/scripts/run-supervisor.sh`
   - `shellcheck experiments/ralph-context-handoff/scripts/run-supervisor.sh` when available
   - `scripts/validate-skill.sh skills/ralph-orchestrator`

2. **Pure shell unit tests**
   - `assert_sandbox_for_yolo` accepts only resolved sandbox paths.
   - option parsing rejects invalid harnesses and negative limits.
   - prompt generation includes run id, hop number, expected handoff path, and prior handoff path.
   - classification handles `complete`, `handoff`, `bad_handoff`, rate-limit text, and harness failure.
   - handoff validation rejects missing headings and dirty workspace without repository-state notes.

3. **Dry-run integration tests**
   - `--dry-run` creates run directories and prompts without launching an agent.
   - dry run refuses yolo outside sandbox.
   - dry run works in `--no-yolo` mode outside sandbox for documentation and prompt inspection.

4. **Fake harness tests**
   - Harness writes canned JSONL/stdout/final files and exits with configured status.
   - Scenario fixtures cover complete relay, valid handoff, missing handoff, rate limit, and malformed handoff.
   - No network or provider account is needed.

5. **Disposable BEADS integration**
   - Use `experiments/ralph-context-handoff/scripts/setup-experiment.sh`.
   - Run the supervisor against the generated workspace in `--no-yolo` or sandboxed yolo mode.
   - Validate with `validate-observation.sh` first, then the supervisor validator.

6. **Canary unattended run**
   - Run with `--max-hops 2`, `--max-issues-total` low, and a disposable sandbox repo.
   - Require clean start.
   - Stop on validation warnings.
   - Inspect run logs before increasing limits.

### Minimum Acceptance Tests For First Script

- Outside `~/Development/sandbox`, yolo mode exits `10` before creating or modifying anything.
- `--dry-run --no-yolo` writes prompts and run metadata but does not invoke an agent.
- A fake complete harness exits `0` only when `bd ready` is empty or the fake fixture says completion is valid.
- A fake handoff harness exits `0` and launches the next hop only after validation passes.
- A fake missing-handoff harness exits `13` when ready issues remain.
- A dirty workspace with no repository-state handoff section exits `12` or `13`.
- Rate-limit retry budget is honored and logged.
- Interrupting the supervisor leaves the run directory intact and prints the recovery path.

### Commands For The First Safe Pass

From this repo:

```bash
experiments/ralph-context-handoff/scripts/setup-experiment.sh
experiments/ralph-context-handoff/scripts/validate-observation.sh experiments/ralph-context-handoff/runs/<run-id> --preflight
bash -n experiments/ralph-context-handoff/scripts/run-supervisor.sh
experiments/ralph-context-handoff/scripts/run-supervisor.sh --dry-run --no-yolo experiments/ralph-context-handoff/runs/<run-id>/workspace
experiments/ralph-context-handoff/scripts/validate-supervisor-run.sh --level preflight experiments/ralph-context-handoff/runs/<run-id>/workspace/.ralph-orchestrator-runs/<supervisor-run-id>
```

After the fake harness passes:

```bash
experiments/ralph-context-handoff/scripts/run-supervisor.sh --harness fake --scenario valid-handoff --max-hops 2 experiments/ralph-context-handoff/runs/<run-id>/workspace
experiments/ralph-context-handoff/scripts/validate-supervisor-run.sh --level run experiments/ralph-context-handoff/runs/<run-id>/workspace/.ralph-orchestrator-runs/<supervisor-run-id>
```

Only after those pass should Codex yolo mode be tested, and only from a workspace under `~/Development/sandbox/...`.

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
2. Add a fake harness and validator fixtures.
3. Prove dry-run and fake-harness behavior outside the sandbox without yolo flags.
4. Prove it on `ralph-context-handoff` with:
   - no-budget fallback cap
   - explicit budget
   - at least two orchestrator hops
5. Add a sandbox-only wrapper in `~/Development/sandbox/ralph-orchestrator-loop.sh`.
6. Add `rol`/`col` aliases in `.zshrc`.
7. Run against a disposable real-ish sandbox repo.
8. Promote patterns back into skillmonger source if stable.

## Decision Record

### 2026-05-28: first real Codex canary approval

Human approval for `skillmonger-a0b.7` chose a bounded sandbox canary, not full production promotion.

- Production placement is deferred until after the first real canary passes. For the canary, create or use a sandbox-only wrapper at `/Users/kevin/Development/sandbox/ralph-orchestrator-loop.sh`.
- Do not promote the supervisor into skillmonger source or `yolobox-pattern` until the canary result is reviewed.
- Keep `rbl` and `rol` separate. `rbl` remains the direct worker loop; `rol` is the orchestrated supervisor loop.
- First canary workspace: `/Users/kevin/Development/sandbox/ralph-supervisor-canary`.
- First canary harness and mode: Codex harness with yolo mode allowed only because the resolved workspace is under `/Users/kevin/Development/sandbox`.
- Required canary limits: `--require-clean-start`, `--max-hops 1`, `--max-issues-total 1`.
- Warning policy: stop on validation warning; do not keep going on validation warning.
- Stop conditions: validation warning or failure, missing or bad handoff, dirty unexplained handoff, rate-limit retry budget exhausted, harness failure, manual-intervention handoff, or any failed sandbox/yolo safety check.

Approved canary command, after the sandbox wrapper exists:

```bash
/Users/kevin/Development/sandbox/ralph-orchestrator-loop.sh --harness codex --require-clean-start --max-hops 1 --max-issues-total 1 /Users/kevin/Development/sandbox/ralph-supervisor-canary
```

## Acceptance Criteria

- Supervisor refuses yolo mode outside `~/Development/sandbox/...`.
- Supervisor can launch Codex orchestrator hops non-interactively.
- Supervisor dry-run and fake-harness tests pass without provider access.
- A hop can process multiple issues before handoff.
- Handoff launches a fresh top-level orchestrator session, not a subagent.
- Built-in chat compaction is never used as continuation.
- BEADS commands run through serialized access when shell-owned.
- Logs are sufficient to validate each hop after the fact.
- The existing experiment can complete across at least two hops.
- Failure modes produce distinct exit codes and recovery instructions.

## Open Questions

- Production supervisor placement is deferred until after the first real canary. The approved canary placement is a sandbox-only wrapper at `/Users/kevin/Development/sandbox/ralph-orchestrator-loop.sh`.
- `rbl` and `rol` remain explicit and separate until canary evidence supports consolidation.
- Should orchestrator hops use explicit token goals where available, or rely on fallback caps in non-interactive `codex exec`?
- How should the supervisor discover the Codex session id reliably for `pj` validation?
- Should dirty-but-documented handoffs be accepted in production, or only in experiments?
- Should fake harness fixtures live under `experiments/ralph-context-handoff/fixtures/` or beside the eventual supervisor tests?
