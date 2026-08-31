---
status: accepted
date: 2026-08-30
---

# Claude Code is the only gate runner

Skills deploy to Codex as well as Claude Code, so a skill could in principle
regress under one runner and not the other, and `evaluation.runner` was reserved
against that day. Measured on 2026-08-31 against codex-cli 0.150.1, a second
runner turns out to be buildable and to buy nothing yet: run over
centers-of-excellence's three fixtures with the same blind copy `gate-skill.sh`
builds and the same evaluate script, `codex exec` scored 5, 5, 5 with the
evaluator's checks identical to Claude's (10 entries, percentages summing to
100, every entry justified) — the same 5, 5, 5 the claude gate has already
recorded twice — while costing 211s, 208s and 226s per fixture against Claude's
105-169s. No fixture differed by any amount, let alone the one point that would
make it signal. Claude Code stays the only runner `gate-skill.sh` drives, and
`evaluation.runner: codex` stays a reserved value the gate refuses at exit 3
("The gate drives claude only; runner is reserved for later") rather than one it
accepts and then silently gates with the wrong tool.

Isolating the temp copy from the deployed `~/.codex/skills/<name>` is the same
problem `--plugin-dir` solves for Claude, and codex has no equivalent. Probed
with `SENTINEL-CX7Q` planted as the first body line of a temp SKILL.md and the
run asked to quote it: `codex exec -C <tmp>` with the skill at
`<tmp>/.codex/skills/<name>/`, and `codex exec --add-dir <tmp>`, both answered
`# Centers of Excellence` — the *deployed* copy's first line, wiki and all.
Only `CODEX_HOME=<tmp>` with the skill at `<tmp>/skills/<name>/` answered
`SENTINEL-CX7Q`, and a bare `CODEX_HOME` cannot authenticate at all (401
Unauthorized on the websocket and on the HTTPS fallback, the way `--bare` fails
for claude); it needs `~/.codex/auth.json` linked into the temp home. `codex
exec` authenticates otherwise, and web search has to be turned back on by hand
(`-c tools.web_search=true`) because the isolated home has no config.toml.
Codex also has no `/<plugin>:<skill>` invocation — it picks a skill from its
description — so the gate would ask for it in prose and rely on `CODEX_HOME`
having hidden every other copy of that name.

## Considered options

- Build `runner: codex` now: workable (isolated `CODEX_HOME`, a link to the
  live `auth.json`, `-c tools.web_search=true`, a second invocation builder in
  the same script), but it roughly doubles a gate run's wall clock for a
  difference no fixture showed, and it needs per-runner baselines first:
  `impact.gate_rows` buckets gate traces by fixture and version alone, so codex
  rows would average into claude's and hide the disagreement a second runner
  exists to catch.
- Make codex the only runner: pays the isolation costs above, gives up the
  plugin namespace, and every fixture and baseline in the repo was scored under
  claude.
- Accept `runner: codex` and gate it with claude anyway: exactly the failure the
  exit-3 refusal exists to prevent.

## Consequences

- A regression visible only under Codex goes unseen. The trigger to revisit is a
  harvested trace, not a hunch: a skill failing from a Codex deployed copy that
  its claude gate passes.
- Whoever builds the second runner adds `runner` to the gate trace and to
  `gate_rows`' bucket key *before* the first codex trace is written. Retrofitting
  it means guessing which runner wrote the traces already there.
- A codex run's epilogue writes its trace into the blind copy, which the gate
  throws away, the same as a claude run's. The by-hand run behind this ADR left
  `skills/centers-of-excellence/FEEDBACK.jsonl` at 46 lines; its three traces
  went to the temp copy and are not a baseline.
