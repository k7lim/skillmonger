---
name: camoufox-options
description: Install, binary management, and full constructor option reference for Camoufox (anti-detect Firefox with Playwright API)
tags: camoufox, playwright, setup, install, constructor, options, fingerprint
---

# Camoufox Setup & Options Reference

Camoufox v0.5.5 (Aug 2026). Open-source anti-detect Firefox fork — spoofs browser fingerprints at the C++ level (no detectable JS injection), rotates fingerprints per launch, drop-in Playwright Python API.

## Install

```bash
pip install -U "camoufox[geoip]"
```

`[geoip]` extra pulls in the MaxMind DB lookups used to match timezone/locale to a proxy's exit IP. Strongly recommended whenever a `proxy` is configured — without it, `geoip=True` cannot resolve IP → timezone/locale.

Optional GUI extra (for the config/fingerprint browser UI, not required for automation):

```bash
pip install -U "camoufox[gui]"
```

Python 3.10–3.14 supported.

## Fetch & manage the browser binary

Camoufox ships as a pinned Firefox build (~150MB download), separate from Playwright's own browser cache. Fetch it once per environment:

```bash
python -m camoufox fetch
```

| Command | Effect |
|---|---|
| `camoufox fetch` | Download the currently pinned binary (first-time setup, or after `remove`) |
| `camoufox set official/stable` | Track the `stable` release channel, auto-following new releases |
| `camoufox set official/prerelease` | Track the `prerelease` channel |
| `camoufox set official/stable/<version>` | Pin to an exact version (no auto-follow) |
| `camoufox active` | Show which binary/channel is currently active |
| `camoufox remove [-y]` | Delete the downloaded binary (`-y` skips confirmation) |

Run `python -m camoufox fetch` (or the equivalent `camoufox fetch` if the console script is on PATH) before first use in any new environment/container — the constructor will fail without a fetched binary.

## Basic usage

Drop-in replacement for Playwright's Firefox launcher. All standard Playwright launch/context/page options pass through unless overridden below.

```python
# Sync
from camoufox.sync_api import Camoufox

with Camoufox() as browser:
    page = browser.new_page()
    page.goto("https://example.com")
    print(page.content())
```

```python
# Async
import asyncio
from camoufox.async_api import AsyncCamoufox

async def main():
    async with AsyncCamoufox() as browser:
        page = await browser.new_page()
        await page.goto("https://example.com")
        print(await page.content())

asyncio.run(main())
```

## Constructor options

```python
Camoufox(
    headless=...,
    os=...,
    screen=...,
    window=...,
    humanize=...,
    geoip=...,
    locale=...,
    proxy=...,
    block_images=...,
    block_webrtc=...,
    fonts=...,
    persistent_context=...,
    user_data_dir=...,
    browser=...,
    # + any standard Playwright launch/context kwarg
)
```

| Option | Type / values | Effect |
|---|---|---|
| `headless` | `True` \| `False` \| `"virtual"` | `"virtual"` runs headless-with-a-virtual-display on Linux (Xvfb-style) — use this instead of plain `True` when a target fingerprints headless mode |
| `os` | `"windows"` \| `"macos"` \| `"linux"` \| list of these | Fingerprint OS to spoof. A list lets Camoufox pick randomly per launch |
| `screen` | `browserforge.fingerprints.Screen(max_width=..., max_height=...)` | Constrains the generated screen-resolution fingerprint |
| `window` | `(width, height)` tuple | Sets the actual browser window size |
| `humanize` | `True` \| `float` | Adds human-like cursor movement. `True` = default max duration; a float sets the max cursor-move duration in seconds |
| `geoip` | `True` \| IP string | `True` auto-detects geolocation/timezone/locale from the current (possibly proxied) egress IP; a literal IP string forces that IP's geo data without a live lookup |
| `locale` | `str` \| list of `str` | e.g. `"en-US"`, or `["en-US", "fr-FR"]` to pick randomly. Should match `geoip`/`proxy` region to avoid mismatch signals |
| `proxy` | `dict` | `{"server": "http://host:port", "username": ..., "password": ...}` — standard Playwright proxy shape |
| `block_images` | `bool` | Blocks image loads (faster scraping, lower bandwidth) |
| `block_webrtc` | `bool` | Disables WebRTC to prevent local/real IP leakage through STUN |
| `fonts` | `list[str]` | Explicit font list to expose in the fingerprint, instead of the generated default |
| `persistent_context` | `True` | Launches a persistent browser context (cookies/storage survive across runs). Requires `user_data_dir` |
| `user_data_dir` | path (`str`/`Path`) | Directory backing the persistent profile. Required when `persistent_context=True` |
| `browser` | `str`, e.g. `"official/beta.20"` | Selects a specific fetched build/channel to launch, overriding the default active binary |

Any other keyword is forwarded to Playwright's underlying `launch()`/`launch_persistent_context()` call.

## Beyond the Python API (mention only)

- **`camoufox server`** — runs Camoufox as a remote Playwright server (connect via `playwright.firefox.connect()`-style workflows) for cases where the browser process needs to live outside the calling process/container.
- **`camoufox-mcp`** (separate PyPI package) — exposes Camoufox as an MCP server for MCP-client-driven browsing, distinct from this skill's direct Playwright usage.

Both are out of scope for this skill's recipes; consult their own docs if a workflow specifically needs a remote server or MCP integration.
