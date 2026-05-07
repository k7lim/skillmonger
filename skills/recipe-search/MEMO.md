# Edge Cases

## `recipe-scrapers` API: `org_url` not `source_url`

`scrape_html(html, org_url=url)` — the parameter is `org_url`. Using `source_url` raises `TypeError`, silently falls through to JSON-LD fallback which returns worse data (stringified HowToSection dicts instead of clean text).

## HowToSection dict strings in instructions

Some sites (e.g. recipetineats.com) return instructions as stringified Python dicts containing `@type: HowToSection` with nested `HowToStep` items. `instructions_list()` gives these as raw strings when the scraper API is called incorrectly (wrong kwarg). With correct `org_url`, the library handles flattening internally. The `clean_instructions()` fallback in `fetch-recipe.py` uses `ast.literal_eval` + recursive `_extract_steps()` as a safety net.

## Token budget variance

Complex recipes (chicken tikka masala: 30 ingredients, 18 steps) → ~750 tokens. Simple recipes → ~300-400. The 500-token estimate is a median, not a ceiling.
