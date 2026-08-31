---
name: camoufox-stealth
description: Stealth web fetching and scraping with Camoufox, an anti-detect Firefox that spoofs fingerprints at the C++ level (no detectable JS injection) behind a drop-in Playwright API. Use when a page is bot-walled or blocked, shows a Cloudflare/WAF challenge, or when you need the rendered DOM, text, or a screenshot of a JS-heavy page; when scraping through a residential proxy with geoip/locale matching; or for a persistent stealth session (login, clicks, forms, pagination). NOT for the user's own visible Chrome — use the claude-in-chrome tools for that. Triggers include scrape a site that blocks bots, get past Cloudflare, stealth browser scrape, anti-detect fetch, fetch a JS-rendered page headless, browse with a spoofed fingerprint, residential proxy scraping.
---

# camoufox-stealth

Fetch or automate pages that block ordinary requests, via Camoufox (anti-detect Firefox, Playwright API). All commands run from this skill directory. This drives a private stealth browser — it is NOT the user's visible Chrome; for that use `claude-in-chrome`.

## Prerequisites

Run `scripts/check-prereqs.sh` (exit 0 always; readiness is in the JSON). `ready:true` → proceed. Camoufox and its ~150MB browser binary auto-install on the first `fetch` (slow once, instant after; marker at `~/.cache/sm-stealth/fetched`). `check-prereqs.sh` and `doctor` never install.

| Missing | Action |
|---------|--------|
| python3 < 3.10 | Works on 3.9 but recommend 3.10+; offer to install via the platform package manager |
| camoufox not importable | Offer to run `pip install -U "camoufox[geoip]"`, or just let the first `fetch` lazy-install it |
| browser binary not fetched | Offer to run `scripts/sm-stealth doctor` then trigger it; the first `fetch` fetches it automatically |

## Workflow

1. **Check readiness** — run `scripts/check-prereqs.sh` (or `sm-stealth doctor`). Note the first `fetch` may be slow while it bootstraps.
2. **One-shot fetch** (the common path) — use `scripts/sm-stealth fetch` per the table below.
3. **Interactive / multi-step** (login, pagination, forms, structured extraction) — a single fetch is not enough; write a custom script from `references/playwright-recipes.md`.
4. **Still blocked** — work the cheapest-first escalation in `references/anti-bot-troubleshooting.md` (headed → humanize → slow down → proxy+geoip → vary os → block_webrtc → persistent profile).
5. **Responsible use** — respect robots.txt and ToS, rate-limit politely, prefer official APIs. Login-walled or non-owned targets need explicit per-target authorization. No CAPTCHA-solving, credential stuffing, mass account creation, spam, or bulk personal-data scraping. Full boundaries: `references/responsible-use.md`.

## `sm-stealth fetch` examples

| Goal | Command |
|------|---------|
| Readiness (never installs) | `scripts/sm-stealth doctor` |
| Rendered text | `scripts/sm-stealth fetch https://example.com --out text` |
| Metadata only (JSON) | `scripts/sm-stealth fetch https://example.com --out meta` |
| Full HTML, JSON envelope | `scripts/sm-stealth fetch https://example.com --out html --json` |
| Screenshot (`--output-file` required) | `scripts/sm-stealth fetch https://example.com --out screenshot --output-file shot.png` |
| Wait for JS content | `scripts/sm-stealth fetch https://quotes.toscrape.com/js/ --out text --wait-selector .quote` |
| Stealth via proxy | `scripts/sm-stealth fetch https://site.example --proxy http://user:pass@host:8080 --geoip auto --humanize --os macos` |

Key flags: `--out text|html|screenshot|meta` (default `text`; there is NO pdf mode); `--output-file PATH` (required for screenshot); `--wait-selector`, `--wait-until load|domcontentloaded|networkidle`, `--timeout MS` (30000); `--proxy URL` (or `SM_STEALTH_PROXY`; credentials auto-redacted); `--geoip auto|IP`, `--locale`, `--headed`, `--humanize`, `--os windows|macos|linux`, `--block-images`, `--json`. Full option detail: `references/camoufox-options.md`.

**Exit codes:** 0 ok · 2 usage · 3 nav/timeout · 4 bootstrap/install failure.

**Gotchas:**
- `--out pdf` fails with exit 2 (Playwright PDF is Chromium-only) — use `--out screenshot`, or HTML→PDF externally (see references).
- `--block-images` prints an advisory upstream `LeakWarning` to stderr and may aid detection on some WAFs; stdout and exit code stay clean.

## Remote mode (protected workspaces)

Inside a nono protected workspace a browser cannot launch, so `sm-stealth`
automatically talks to the host-side Camoufox fetch service at
`http://127.0.0.2:9333` whenever `$HOME/.yolobox-sandbox-home` exists
(see yolobox-pattern `docs/host-services-for-protected-workspaces.md`).
`sm-stealth doctor` shows a `remote` block with the endpoint's health. In this
mode `--proxy`, `--geoip`, `--locale`, `--os`, `--humanize`, `--headed` are
fixed server-side and ignored (announced on stderr); `--out`, `--wait-*`,
`--timeout`, `--block-images`, `--json`, `--output-file` all work. The service
refuses `file://`, loopback, LAN and metadata destinations (`kind: policy`,
exit 2). Force a local browser with `--local`; point elsewhere with
`--remote URL` / `SM_STEALTH_REMOTE`.

## After Execution

Run this skill's evaluator on the output you just produced:

```bash
echo '{"url":"<url>","out":"<text|html|screenshot|meta>","exit_code":<int>,"bytes":<int>,"title":"<title or empty>"}' | python3 scripts/evaluate.py
```

It prints `{"outcome":1-5,"note":"...","checks":{...},"source":"script"}`.

Copy its `outcome`, `note` and `checks` straight through — do not re-score
them yourself.

Append one JSON line to `FEEDBACK.jsonl` in this skill directory — the copy you
are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"camoufox-stealth","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<the evaluator's outcome>,"note":"<the evaluator's note>","checks":<the evaluator's checks object>,"source":"script","session":"<this session's id>","schema_version":1}
```

Drop `session` if you do not know this session's id. That line is the whole
record: nothing in `CONFIG.yaml` is edited by a run.

If the evaluator cannot run, say why in `note`, score the run yourself on the
standard scale (1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent), and set
`"source":"llm"`.
