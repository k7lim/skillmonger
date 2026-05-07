#!/usr/bin/env python3
"""Evaluate recipe skill output. Reads JSON from stdin or file arg. Scores 1-5."""
import json
import sys

REQUIRED_FIELDS = ["title", "ingredients", "instructions"]

def score_recipe(data):
    checks = {}
    if not isinstance(data, dict):
        return 1, "Not a JSON object", checks

    # Check for error entry
    if "error" in data:
        checks["error_entry"] = True
        return 1, f"Error entry: {data['error']}", checks

    # Required fields present
    for field in REQUIRED_FIELDS:
        checks[f"has_{field}"] = field in data
    missing = [f for f in REQUIRED_FIELDS if f not in data]
    if missing:
        return 2, f"Missing fields: {', '.join(missing)}", checks

    # ingredients is a non-empty list
    ing = data["ingredients"]
    checks["ingredients_is_list"] = isinstance(ing, list)
    checks["ingredients_non_empty"] = isinstance(ing, list) and len(ing) > 0
    if not checks["ingredients_is_list"] or not checks["ingredients_non_empty"]:
        return 3, "ingredients must be a non-empty list", checks

    # instructions is a non-empty list
    ins = data["instructions"]
    checks["instructions_is_list"] = isinstance(ins, list)
    checks["instructions_non_empty"] = isinstance(ins, list) and len(ins) > 0
    if not checks["instructions_is_list"] or not checks["instructions_non_empty"]:
        return 3, "instructions must be a non-empty list", checks

    # Bonus fields
    bonus = ["source", "url", "total_time", "servings"]
    bonus_present = sum(1 for f in bonus if data.get(f))
    checks["bonus_fields"] = bonus_present
    if bonus_present >= 3:
        return 5, "", checks
    return 4, "Some optional fields missing", checks

def main():
    if len(sys.argv) >= 2:
        with open(sys.argv[1]) as f:
            raw = f.read()
    else:
        raw = sys.stdin.read()

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        result = {"outcome": 1, "note": f"Invalid JSON: {e}", "checks": {}, "source": "script"}
        json.dump(result, sys.stdout)
        print()
        return

    # Handle array of recipes — score each, take minimum
    if isinstance(data, list):
        scores = []
        all_checks = {}
        notes = []
        for i, recipe in enumerate(data):
            s, n, c = score_recipe(recipe)
            scores.append(s)
            all_checks[f"recipe_{i}"] = c
            if n:
                notes.append(f"[{i}] {n}")
        outcome = min(scores) if scores else 1
        note = "; ".join(notes) if notes else ""
    else:
        outcome, note, all_checks = score_recipe(data)

    result = {"outcome": outcome, "note": note, "checks": all_checks, "source": "script"}
    json.dump(result, sys.stdout)
    print()

if __name__ == "__main__":
    main()
