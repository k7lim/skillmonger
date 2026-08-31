---
name: git-housekeeping
description: Clean up a dirty local Git working tree into a clear commit trail. Use when the user asks to commit, organize, split, save, sync, push, recover from unstaged or untracked changes, handle divergence with a remote, or make sense of local Git state before landing work.
---

# Git Housekeeping

You turn messy local Git state into an honest, reviewable commit trail without losing work.

## Operating Rules

- Treat every local change as user work until proven otherwise. Never discard, overwrite, or reset it without explicit user approval.
- Prefer a sequence of small commits that each explain one intent over one broad "misc" commit.
- Inspect before staging. Use `git diff`, `git diff --staged`, `git status --short --branch`, and file reads as needed.
- Do not hide uncertainty. If a change's purpose is unclear, isolate it in its own commit or ask before mixing it with related work.
- Sync only after local work is committed or intentionally stashed. Resolve remote divergence deliberately.
- Push only when the destination is clear and the user asked to land or share the work. If no remote exists, leave clean local commits and report the missing remote.

## Workflow

### 1. Preflight

Run `scripts/check-prereqs.sh` from this skill directory when available. Use its JSON as a quick map of:

- whether the current directory is inside a Git worktree
- branch and upstream
- remote count
- ahead/behind counts
- working tree dirtiness

If not in a Git repo, stop and tell the user.

### 2. Inventory

Capture:

```bash
git status --short --branch
git diff --stat
git diff --staged --stat
git log --oneline --decorate -8
git remote -v
```

Then inspect changed files. Use file-level diffs first, then full hunks for files that will be committed.

Group changes by intent:

- feature behavior
- bug fix
- tests
- docs
- generated or lockfile updates
- formatting-only churn
- local config or secrets that should not be committed
- unrelated work that should be left alone

### 3. Make A Commit Plan

Before staging, state the planned commits in plain language when there is more than one logical group or any remote risk.

For each commit, include:

- files or hunks to stage
- commit message
- verification to run before or after the commit
- anything intentionally left uncommitted

If the user is AFK and the grouping is clear, proceed. If a file mixes unrelated hunks, use patch staging when practical. If patch staging would be fragile, make a conservative whole-file commit and state the tradeoff.

### 4. Protect Work

Before any risky operation such as rebase, pull, branch switch, conflict resolution, or dependency regeneration:

- ensure all intended work is committed, or
- create a named stash with `git stash push -u -m "git-housekeeping: <reason>"`, after telling the user why.

Do not use destructive cleanup commands. Do not delete untracked files just to make status clean.

### 5. Commit

For each planned commit:

1. Stage only the chosen paths or hunks.
2. Re-run `git diff --staged --stat` and inspect the staged diff.
3. Commit with a specific message.
4. Keep a note of the commit SHA and purpose.

Good message forms:

- `Add <capability>`
- `Fix <broken behavior>`
- `Document <workflow>`
- `Test <scenario>`
- `Refactor <module> for <reason>`

Avoid vague messages like `updates`, `wip`, `misc`, or `cleanup` unless preserving an opaque state is the explicit goal.

### 6. Sync With Remote

After local commits exist:

- If there is no remote, stop after local commits and say what command would add a remote if known.
- If there is a remote but no upstream, set upstream on push only when the branch name and remote are obvious.
- If behind remote, fetch and inspect. Prefer `git pull --rebase` for local commits on top of remote work, but only when the working tree is clean.
- If conflicts occur, resolve them as normal code changes, run relevant verification, and continue the rebase. Never skip or abort without explaining why.
- If the branch has diverged and the risk is non-trivial, pause with the exact ahead/behind state and proposed command.

### 7. Verify

Run the lightest useful quality gates suggested by the repository:

- changed tests if obvious
- existing lint/typecheck/build commands if documented and relevant
- validation scripts for generated artifacts or skills

If no test command is obvious or tests are too expensive for the scope, say that clearly.

### 8. Final Report

Report:

- commits created, with short SHA and message
- files intentionally left uncommitted
- remote/upstream state and whether push succeeded
- verification run and result
- any follow-up the user needs to decide, such as adding a remote

## Composition

This is a hub skill. Use existing narrower skills when they clearly apply:

- Use `review` before committing when the user asks for review or when the diff is large and the intended spec matters.
- Use `diagnose` first when the dirty state is caused by a failing bug investigation.
- Use `tdd` when the user explicitly wants test-first cleanup or a regression test before the commit.

Use deterministic scripts in this skill for sensing and evaluation. Keep judgment in the prompt.

---

## After Execution

Two things are worth recording about this run: what the evaluator can check,
and what only a person can judge.

**1. Run the evaluator.**

Run this skill's evaluator on the output you just produced:

```bash
scripts/evaluate.sh   # takes the output on stdin, or as its first argument
```

It prints `{"outcome":1-5,"note":"...","checks":{...},"source":"script"}`.

**2. Ask, then judge.**

Self-assess against these criteria:

- Did you preserve all user work?
- Did each commit have one clear intent?
- Did you explain or resolve remote/upstream risk?
- Did you run relevant verification or state why not?
- Did final `git status --short --branch` match the reported state?

Map: 5=clean atomic commits, verified, remote state handled; 4=good commit trail with minor residuals; 3=work preserved but grouping or verification was partial; 2=mostly inspection with little cleanup; 1=lost work, mixed unrelated changes, or misreported state.

**3. Record both.** Append one JSON line per source to `FEEDBACK.jsonl` in this
skill directory — the copy you are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"git-housekeeping","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<the evaluator's outcome>,"note":"<the evaluator's note>","checks":<the evaluator's checks object>,"source":"script","session":"<this session's id>","schema_version":1}
{"ts":"<UTC ISO 8601>","skill":"git-housekeeping","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"user","session":"<this session's id>","schema_version":1}
```

Use `"source":"llm"` on the second line when you judged the run yourself
instead of asking. Drop `session` if you do not know this session's id. Those
lines are the whole record: nothing in `CONFIG.yaml` is edited by a run.
