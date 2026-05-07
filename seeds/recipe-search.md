# Agent Recipe Search Strategy

## Overview

An agent can search trusted recipe sites using WebSearch with domain filtering, then extract clean recipe content using WebFetch.

## Trusted Domain Lists

### General Cooking (default)
```
seriouseats.com
recipetineats.com
budgetbytes.com
bonappetit.com
epicurious.com
bbcgoodfood.com
smittenkitchen.com
allrecipes.com
food52.com
tasteofhome.com
```

### Baking
```
kingarthurbaking.com
sallysbakingaddiction.com
smittenkitchen.com
seriouseats.com
```

### Budget-Focused
```
budgetbytes.com
spendwithpennies.com
```

### Asian Cuisines
```
thewoksoflife.com
madewithlau.com
justonecookbook.com
maangchi.com
hot-thai-kitchen.com
hebbarskitchen.com
```

### Mexican/Latin
```
rickbayless.com
patijinich.com
```

## Search Workflow

### Step 1: WebSearch with Domain Filtering

```
WebSearch(
  query: "chicken tikka masala recipe",
  allowed_domains: ["seriouseats.com", "recipetineats.com", ...]
)
```

The `allowed_domains` parameter constrains results to trusted sites only.

### Step 2: Fetch Top Results

For each promising result URL, use WebFetch to retrieve content:

## First attempt: Use justtherecipe.com
justtherecipe.com bypasses long blog posts and ads to get just the recipe content.
For any recipe URL, the helper site strips blog content:

```
WebFetch(
  url: "https://www.justtherecipe.com/?url=https://example.com/recipe",
  prompt: "Extract the full recipe"
)
```

## Backup: WebFetch the whole site

```
WebFetch(
  url: "https://www.seriouseats.com/chicken-tikka-masala-recipe",
  prompt: "Extract the recipe: ingredients list, instructions, prep time, cook time, and servings"
)
```

### Step 3: Present Options

Show user all the recipe options with:
- Recipe title and source 
- Brief description
- Key stats (time, servings, difficulty if available)
- Direct link to original




## Domain Selection Logic

| User Query Contains | Use Domain List |
|---------------------|-----------------|
| "baking", "cake", "cookies", "bread" | Baking |
| "cheap", "budget", "affordable" | Budget-Focused |
| "chinese", "japanese", "korean", "thai", "indian" | Asian Cuisines |
| "mexican", "latin", "tacos" | Mexican/Latin |
| (default) | General Cooking |

## Example Agent Flow

**User:** "Find me a good beef stew recipe"

**Agent:**
1. Detect: general cooking query
2. Search: `WebSearch(query="beef stew recipe", allowed_domains=[general list])`
3. Get top 3 results
4. Fetch each: `WebFetch(url, prompt="Extract recipe details")`
5. Present comparison to user with links

## Notes

- Subscription sites (NYT Cooking, ATK) may have paywalled content
- Some sites load recipes dynamically; WebFetch may not capture all content
- When extraction fails, fall back to providing the direct link
