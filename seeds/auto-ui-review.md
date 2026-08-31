# auto-ui-review

Wrap the auto-ui-review CLI (project: `~/Development/sandbox/projects/auto-ui-review`)
as a global skill so agents on any web project (wantavision, georep, bookhopper, ...)
reach for a UX/UI/accessibility/GEO/copy review without being told how.

Raised twice (2026-06-06, 2026-06-15): the mechanism works but nothing makes an
agent think to run it, and Kevin forgets the invocation. The in-repo half
(SKILL.md, `--brief-file`, request template) exists; this is the cross-project
half.

Must work in and out of the guardrailed state: on the host the CLI runs a local
Playwright browser; inside a nono protected workspace the CLI auto-forwards to
the host review service on http://127.0.0.2:9334 (installed by
`yolobox-pattern/scripts/install-auto-ui-review-host-server.sh`).

Done looks like: a skill that documents the request/brief JSON shape, wraps
`auto-ui-review review --request request.json`, and states when an agent should
invoke it unprompted (after meaningful UI changes, before shipping a page, when
asked "what next" on a web project with a reachable deployment).
