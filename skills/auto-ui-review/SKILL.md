---
name: auto-ui-review
description: Automated UX/UI, accessibility, screenshot, GEO, and copy review of any reachable web page, with deterministic checks (axe-core, ARIA, metadata, AI crawlability) and optional multimodal LLM critique. Use when the user asks for a UI/UX/accessibility/copy review of a URL, and proactively on web projects after meaningful UI changes, before shipping a page, or when evaluating what to improve next against a high-level goal. Works identically on the host and inside a nono protected workspace (reviews auto-forward to the host review service). Triggers include review this page, UX review, accessibility audit, screenshot review, how does the landing page look, is this page ready to ship, GEO/AI-crawlability check.
---

# auto-ui-review

Review a live web page along four axes — `headless` (axe-core accessibility +
ARIA + metadata), `screenshot` (multi-viewport multimodal LLM critique), `geo`
(AI crawlability), `copy` (copy quality) — and get one JSON/markdown/HTML
report. All commands run through `scripts/aur` from this skill directory; it
finds the project checkout and works in and out of the sandbox unchanged.

## When to invoke unprompted

On a web project, run a review without being asked when:
- you just made a meaningful UI change and the page is deployed or reachable;
- the user asks "what should I improve next" / "is this ready" about a page;
- you are evaluating a site against a high-level executive goal — feed that
  goal in as the `brief` and let the reviewers ground your recommendations.

Say you are running it; it is read-only (no side effects on the page). Note the
target must be a **publicly reachable http(s) URL** — localhost/private hosts
are refused inside a protected workspace, so review the deployed URL.

## Workflow

1. **Write a request** — one JSON file; free text goes in `brief`/`concerns`:

```json
{
  "url": "https://example.com",
  "target": {
    "page_type": "landing_page",
    "audience": "solo founders evaluating analytics tools",
    "primary_goal": "start a free trial",
    "discoverability": "public_matters",
    "auth": "public",
    "form_factor": "mobile_first"
  },
  "brief": "First page after a referral link. Executive goal: ...",
  "user_paths": ["Land, understand the product, start a trial"],
  "concerns": ["CTA clarity", "mobile navigation", "trust signals"],
  "execution": { "reviewers": "auto", "providers": ["anthropic"], "format": "html" }
}
```

A longer brief can live in a markdown file instead: drop `brief` from the JSON
and pass `--brief-file brief.md` with legacy flags (not with `--request`).

2. **Dry-run** (validates everything, launches nothing):

```
scripts/aur review --request request.json --dry-run
```

3. **Run**:

```
scripts/aur review --request request.json --format html -o output/report.html
```

4. **Read the envelope** — every response is `{"success", "data", "meta"}`;
   scores per reviewer, `wcag_violations`, `issues`, `slop_hits`. Exit codes:
   0 ok, 1 user error, 2 runtime error. Turn findings into next steps ranked
   against the stated goal, not a raw issue dump.

## Quick calls (no request file)

| Goal | Command |
|------|---------|
| Deterministic a11y/UX audit, no LLM | `scripts/aur review <url> --reviewers headless --format markdown` |
| GEO + copy checks, no LLM | `scripts/aur review <url> --reviewers 'geo\|copy' --providers '' --format markdown` |
| Focused review | `scripts/aur review <url> --concerns "mobile layout, CTA clarity" --format markdown` |
| Multi-provider screenshot compare | `scripts/aur review <url> --compare --providers anthropic,gemini --format html -o report.html` |
| Schema introspection | `scripts/aur review --describe json` |

Reviewers are `|`-separated, providers comma-separated. Full flag table and
request schema: `SKILL.md` in the project checkout, or `--describe json`.

## Sandbox vs host (handled for you)

- **Host**: the CLI drives a local Playwright Chromium; LLM providers need keys
  in the environment (`ANTHROPIC_API_KEY`, ...).
- **Protected workspace** (nono jail; `$HOME/.yolobox-sandbox-home` exists):
  browsers cannot launch, so the CLI transparently forwards the review to the
  host service at `http://127.0.0.2:9334` and relays its output. Keys stay on
  the host. `--session`/`auth` are host-only; dry runs stay local.
  If forwarding fails, check `curl -s http://127.0.0.2:9334/healthz` and (on
  the host) `yolobox-pattern/scripts/install-auto-ui-review-host-server.sh`.

## Prerequisites

`scripts/aur` needs the project checkout (default
`~/Development/sandbox/projects/auto-ui-review`, override `AUR_PROJECT`) and
`uv`. On the host, Playwright Chromium: `uv run --project <checkout> playwright
install chromium`. In a protected workspace with no checkout at all, POST the
request JSON directly: `curl -s -X POST http://127.0.0.2:9334/review -d @request.json`.

## Gotchas

- `auto-ui-review <url>` is not a valid invocation; the subcommand is `review`.
- Do not combine `--request` with `--reviewers/--providers/--concerns/--brief*`.
- `--reviewers` uses `|`, not commas.
- Authenticated pages + external LLM providers can leak PII in screenshots:
  prefer `--no-screenshot` or `--reviewers 'headless|geo'` with `--session`.
