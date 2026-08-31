#!/usr/bin/env python3
"""Shared provenance helpers for adopted skills.

CONFIG.yaml's `upstream:` block is the source of truth. SOURCE.md is a
generated human-readable view of it plus the zone table. These helpers are the
only place that knows the format, so adopt-skill.sh and check-upstream.sh can
never disagree about it.

Zones:
  verbatim  byte-identical to upstream at the pinned commit (checksum-checked)
  adapted   we rewrote it; upstream changes need a human read
  ours      no upstream counterpart (skillmonger furniture)
"""

from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - surfaced to the caller as a clear error
    sys.stderr.write(
        "error: PyYAML is required for upstream provenance tooling.\n"
        "       pip install pyyaml\n"
    )
    raise SystemExit(2)

ZONES = ("verbatim", "adapted", "ours")
STATUSES = ("tracked", "renamed", "orphaned")

# Skillmonger furniture: never has an upstream counterpart.
OURS_ALWAYS = {
    "CONFIG.yaml",
    "MEMO.md",
    "SOURCE.md",
    "FEEDBACK.jsonl",
    "scripts/evaluate",
    "scripts/evaluate.sh",
    "scripts/evaluate.py",
    "scripts/check-prereqs",
    "scripts/check-prereqs.sh",
    "scripts/check-prereqs.py",
    "OVERLAY.md",
}

# Same, but matched by directory prefix rather than exact file path: every
# file under these directories is furniture, however deeply nested. `memo/`
# holds wiki overflow (format 2.1, `memo/patterns/<slug>.md`) ahead of any
# skill actually using it.
OURS_ALWAYS_PREFIXES = (
    "memo/",
)

SOURCE_HEADER_BEGIN = "<!-- generated-from-config:begin -->"
SOURCE_HEADER_END = "<!-- generated-from-config:end -->"


# --- config access ----------------------------------------------------------


def load_config(skill_dir: Path) -> dict:
    path = Path(skill_dir) / "CONFIG.yaml"
    if not path.exists():
        return {}
    return yaml.safe_load(path.read_text()) or {}


def upstream_block(skill_dir: Path) -> dict | None:
    block = load_config(skill_dir).get("upstream")
    return block if isinstance(block, dict) else None


def write_upstream_block(skill_dir: Path, block: dict) -> None:
    """Insert or replace the upstream: block, preserving the rest of the file.

    Deliberately textual rather than a yaml round-trip: CONFIG.yaml is written
    and read by humans, and yaml.dump would reflow comments and key order.
    """
    path = Path(skill_dir) / "CONFIG.yaml"
    rendered = "upstream:\n" + "".join(
        f"  {k}: {_scalar(v)}\n" for k, v in block.items() if v is not None
    )

    if not path.exists():
        path.write_text(rendered)
        return

    text = path.read_text()
    # Match `upstream:` and everything indented beneath it.
    pattern = re.compile(r"^upstream:\n(?:[ \t]+.*\n|\n(?=[ \t]))*", re.MULTILINE)
    if pattern.search(text):
        text = pattern.sub(rendered, text, count=1)
    else:
        # Land it after the `skill:` block so provenance reads near identity.
        anchor = re.compile(r"^(skill:\n(?:[ \t]+.*\n|\n(?=[ \t]))*)", re.MULTILINE)
        match = anchor.search(text)
        if match:
            text = text[: match.end()] + "\n" + rendered + text[match.end() :]
        else:
            text = rendered + "\n" + text
    path.write_text(text)


def _scalar(value) -> str:
    text = str(value)
    if text == "" or re.search(r"[:#]|^\s|\s$", text):
        return '"' + text.replace('"', '\\"') + '"'
    return text


# --- checksums and zones ----------------------------------------------------


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def skill_files(skill_dir: Path) -> list[str]:
    """Every tracked-worthy file in the skill, as posix-relative paths."""
    skill_dir = Path(skill_dir)
    out = []
    for path in sorted(skill_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(skill_dir).as_posix()
        if rel.startswith(".git/") or "/.git/" in rel:
            continue
        if path.name in (".DS_Store",):
            continue
        out.append(rel)
    return out


def git_show(vendor: Path, ref: str, path: str) -> bytes | None:
    """Contents of `path` at `ref` in the vendor repo, or None if absent."""
    result = subprocess.run(
        ["git", "-C", str(vendor), "show", f"{ref}:{path}"],
        capture_output=True,
    )
    return result.stdout if result.returncode == 0 else None


def git_ls_tree(vendor: Path, ref: str, path: str) -> list[str]:
    """Files under `path` at `ref`, relative to `path`."""
    result = subprocess.run(
        ["git", "-C", str(vendor), "ls-tree", "-r", "--name-only", ref, "--", path],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []
    prefix = path.rstrip("/") + "/"
    return [
        line[len(prefix) :]
        for line in result.stdout.splitlines()
        if line.startswith(prefix)
    ]


def map_rel(rel: str, path_map: dict | None) -> str:
    """Translate a local relative path to its upstream one.

    Adoptions routinely rename a subdirectory — upstream `rules/` becomes our
    `references/`, say. Without this the renamed files look like they have no
    upstream counterpart, and every one of them is misfiled as `ours`.
    """
    if not path_map:
        return rel
    for local_prefix, upstream_prefix in path_map.items():
        local_prefix = local_prefix.rstrip("/") + "/"
        if rel.startswith(local_prefix):
            return upstream_prefix.rstrip("/") + "/" + rel[len(local_prefix):]
    return rel


def classify(
    skill_dir: Path,
    vendor: Path,
    ref: str,
    upstream_path: str,
    path_map: dict | None = None,
) -> dict:
    """Compare every local file against upstream at `ref`.

    Returns {relpath: zone} using observed reality, not aspiration: a file that
    still matches upstream byte-for-byte is verbatim, one that differs is
    adapted, one with no upstream counterpart is ours.
    """
    skill_dir = Path(skill_dir)
    zones = {}
    for rel in skill_files(skill_dir):
        if rel in OURS_ALWAYS or rel.startswith(OURS_ALWAYS_PREFIXES):
            zones[rel] = "ours"
            continue
        blob = git_show(vendor, ref, f"{upstream_path.rstrip('/')}/{map_rel(rel, path_map)}")
        if blob is None:
            zones[rel] = "ours"
        elif hashlib.sha256(blob).hexdigest() == sha256_file(skill_dir / rel):
            zones[rel] = "verbatim"
        else:
            zones[rel] = "adapted"
    return zones


# --- SOURCE.md --------------------------------------------------------------


def render_header(skill_name: str, block: dict) -> str:
    rows = [
        ("Repository", block.get("repo", "?")),
        ("Upstream path", f"`{block.get('path', '?')}`"),
        ("Pinned ref", f"`{block.get('ref', '?')}`"),
        ("Pinned commit", f"`{block.get('commit', '?')}`"),
        ("License", block.get("license", "?")),
        ("Status", block.get("status", "tracked")),
        ("Last synced", block.get("synced", "?")),
        ("Vendor checkout", f"`{block.get('vendor', '?')}`"),
    ]
    if block.get("previous_path"):
        rows.insert(2, ("Previous upstream path", f"`{block['previous_path']}`"))
    if block.get("last_seen_ref"):
        rows.insert(3, ("Last seen at", f"`{block['last_seen_ref']}`"))

    lines = [
        SOURCE_HEADER_BEGIN,
        "<!-- Generated from CONFIG.yaml:upstream by scripts/adopt-skill.sh.",
        "     Edit CONFIG.yaml, then re-run scripts/check-upstream.sh --regenerate. -->",
        "",
        f"# Source Attribution — {skill_name}",
        "",
        "| | |",
        "|---|---|",
    ]
    lines += [f"| {label} | {value} |" for label, value in rows]
    lines += ["", SOURCE_HEADER_END]
    return "\n".join(lines)


def render_zone_table(zones: dict) -> str:
    lines = [
        "## Zones",
        "",
        "`verbatim` files are byte-identical to upstream at the pinned commit and",
        "are checksum-verified. Change one and it must be demoted to `adapted`",
        "with a reason below — or, preferably, expressed in `OVERLAY.md` instead.",
        "",
        "| File | Zone |",
        "|---|---|",
    ]
    order = {"adapted": 0, "verbatim": 1, "ours": 2}
    for rel in sorted(zones, key=lambda r: (order[zones[r]], r)):
        lines.append(f"| `{rel}` | {zones[rel]} |")
    return "\n".join(lines)


def write_source_md(
    skill_dir: Path, skill_name: str, block: dict, zones: dict, notes: str | None = None
) -> None:
    path = Path(skill_dir) / "SOURCE.md"
    header = render_header(skill_name, block)
    table = render_zone_table(zones)

    if path.exists():
        text = path.read_text()
        # Replace the generated header in place, keep everything a human wrote.
        if SOURCE_HEADER_BEGIN in text and SOURCE_HEADER_END in text:
            pre, rest = text.split(SOURCE_HEADER_BEGIN, 1)
            _, post = rest.split(SOURCE_HEADER_END, 1)
            body = post
        else:
            pre, body = "", "\n\n" + text
        # The zone table is generated too; drop the stale one.
        body = re.sub(r"\n## Zones\n.*?(?=\n## |\Z)", "\n", body, flags=re.DOTALL)
        path.write_text(f"{pre}{header}\n{table}\n{body.rstrip()}\n")
        return

    default_notes = (
        "_Explain every `adapted` file and every overlay here: what changed and"
        " why upstream's version could not be used as-is._"
    )
    parts = [
        header,
        "",
        table,
        "",
        "## Adaptation notes",
        "",
        notes or default_notes,
        "",
        "## Resyncing",
        "",
        "```bash",
        f"scripts/check-upstream.sh {skill_name}",
        "```",
        "",
    ]
    path.write_text("\n".join(parts))
