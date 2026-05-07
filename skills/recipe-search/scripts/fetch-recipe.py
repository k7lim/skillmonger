#!/usr/bin/env python3
"""Fetch structured recipe data from URLs using recipe-scrapers with JSON-LD fallback."""
import ast
import json
import sys
import urllib.request

def fetch_html(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.read().decode("utf-8", errors="replace")

def _extract_steps(obj):
    """Recursively extract text from HowToStep/HowToSection dicts."""
    steps = []
    if isinstance(obj, dict):
        if "text" in obj:
            steps.append(obj["text"])
        for item in obj.get("itemListElement", []):
            steps.extend(_extract_steps(item))
    elif isinstance(obj, list):
        for item in obj:
            steps.extend(_extract_steps(item))
    return steps

def clean_instructions(steps):
    """Flatten instructions that may contain HowToSection dicts into plain text."""
    cleaned = []
    for step in steps:
        if isinstance(step, str) and step.startswith("{"):
            try:
                obj = ast.literal_eval(step)
            except (ValueError, SyntaxError):
                cleaned.append(step)
                continue
            extracted = _extract_steps(obj)
            cleaned.extend(extracted if extracted else [step])
        else:
            cleaned.append(step)
    return cleaned

def extract_with_scrapers(url):
    from recipe_scrapers import scrape_html
    html = fetch_html(url)
    scraper = scrape_html(html, org_url=url)
    raw_instructions = scraper.instructions_list()
    recipe = {
        "title": scraper.title(),
        "source": url.split("/")[2].replace("www.", ""),
        "url": url,
        "total_time": f"{scraper.total_time()} min" if scraper.total_time() else None,
        "servings": str(scraper.yields()) if scraper.yields() else None,
        "ingredients": scraper.ingredients(),
        "instructions": clean_instructions(raw_instructions),
    }
    try:
        recipe["cuisine"] = scraper.cuisine()
    except Exception:
        recipe["cuisine"] = None
    try:
        recipe["category"] = scraper.category()
    except Exception:
        recipe["category"] = None
    return recipe

def extract_with_jsonld(url):
    from scrape_schema_recipe import scrape_url
    recipes = scrape_url(url)
    if not recipes:
        raise ValueError("No JSON-LD recipe data found")
    r = recipes[0]
    instructions_raw = r.get("recipeInstructions", [])
    instructions = []
    for step in instructions_raw:
        if isinstance(step, dict):
            instructions.append(step.get("text", str(step)))
        else:
            instructions.append(str(step))
    total_time = r.get("totalTime") or r.get("cookTime")
    if total_time and total_time.startswith("PT"):
        total_time = total_time[2:].lower().replace("h", " hr ").replace("m", " min").strip()
    servings = r.get("recipeYield")
    if isinstance(servings, list):
        servings = servings[0] if servings else None
    return {
        "title": r.get("name", "Unknown"),
        "source": url.split("/")[2].replace("www.", ""),
        "url": url,
        "total_time": str(total_time) if total_time else None,
        "servings": str(servings) if servings else None,
        "ingredients": r.get("recipeIngredient", []),
        "instructions": instructions,
        "cuisine": r.get("recipeCuisine"),
        "category": r.get("recipeCategory"),
    }

def fetch_recipe(url):
    try:
        return extract_with_scrapers(url)
    except Exception:
        pass
    try:
        return extract_with_jsonld(url)
    except Exception as e:
        return {"url": url, "error": str(e)}

def main():
    if len(sys.argv) < 2:
        print("Usage: fetch-recipe.py <url> [url2 ...]", file=sys.stderr)
        sys.exit(1)
    urls = sys.argv[1:]
    results = [fetch_recipe(u) for u in urls]
    output = results[0] if len(results) == 1 else results
    json.dump(output, sys.stdout, indent=2, ensure_ascii=False)
    print()

if __name__ == "__main__":
    main()
