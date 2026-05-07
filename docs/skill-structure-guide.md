# Core Structure of an Agent Skill

```
skill-name/
├── SKILL.md          # Required: metadata + instructions
├── scripts/          # Optional: executable code
├── references/       # Optional: documentation
└── assets/           # Optional: templates, resources
```

## SKILL.md — The only required file

YAML frontmatter (`name` + `description`) followed by markdown instructions. The frontmatter is cheap (~100 tokens) and loaded at startup for *all* installed skills so the agent can decide which to activate. The body (<5000 tokens recommended) loads only when activated.

**What goes here:** Role, workflow, decision guidance, examples, edge cases. This is what the agent reads to know what to do and how to think. Keep it under 500 lines — if it's growing past that, offload detail to `references/`.

**Key frontmatter fields:**
- `name` — lowercase, hyphens, numbers. Must match the directory name.
- `description` — what it does AND when to use it. This is the trigger — make it specific with keywords the agent will pattern-match against.

## scripts/ — Deterministic helpers

Executables the agent can run. The design principle: **scripts produce data, prompts interpret meaning**. Anything that can be verified or computed by code belongs here, not in the prompt.

**Examples:** API wrappers, prerequisite checks, output validators, data extraction, rate limiters. Any language works — the interface is the contract (stdin/stdout), not the file extension.

Scripts should be self-contained, document their dependencies, and include helpful error messages.

## references/ — On-demand documentation

Supporting docs the agent loads only when needed. Keep files focused and small — each one costs context when pulled in.

**Examples:** API field listings, syntax references, strategy guides, domain-specific knowledge. The prompt says "consult `references/foo.md`" rather than inlining dense material.

## assets/ — Static resources

Templates, images, data files, schemas, lookup tables. Things the skill uses but doesn't reason about.

---

## The layering principle

The spec is designed around **progressive disclosure**:

1. **Metadata** (~100 tokens) — loaded for all skills at startup (just name + description)
2. **Instructions** (<5000 tokens) — loaded when activated (SKILL.md body)
3. **Resources** (as needed) — loaded on demand (scripts, references, assets)

This means: put trigger-quality keywords in the description, put workflow in SKILL.md, and push everything else one level out. The agent's context is the scarce resource — respect it.
