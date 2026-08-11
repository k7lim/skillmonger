#!/bin/bash
# check-upstream.sh - Report drift between adopted skills and their upstreams
#
# Three independent signals:
#   upstream drift  upstream moved past our pin       -> read the diff, re-pin
#   local drift     a verbatim file no longer matches -> provenance is lying
#   orphaned        upstream deleted the skill        -> nothing to sync, ever
#
# Exits non-zero on local drift only: that is the case where SOURCE.md claims
# something untrue. Upstream drift is information, not a failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat << EOF
Usage: $(basename "$0") [skill...] [options]

Reports upstream and local drift for adopted skills. With no skill named,
checks every skill in skills/ that has a CONFIG.yaml upstream: block.

Options:
  --offline       Skip git fetch; report local drift only
  --regenerate    Rewrite each SOURCE.md header and zone table from CONFIG.yaml
  --licenses      List the license each adopted skill carries, then exit
  --help          Show this help

Examples:
  $(basename "$0")
  $(basename "$0") grill-me isometric-explainer
  $(basename "$0") --offline
EOF
}

SKILLS=(); OFFLINE=false; REGENERATE=false; LICENSES=false
while [ $# -gt 0 ]; do
  case "$1" in
    --offline) OFFLINE=true; shift ;;
    --regenerate) REGENERATE=true; shift ;;
    --licenses) LICENSES=true; shift ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) SKILLS+=("$1"); shift ;;
  esac
done

PYTHONPATH="$SCRIPT_DIR/lib" python3 - \
  "$PROJECT_ROOT" "$OFFLINE" "$REGENERATE" "$LICENSES" "${SKILLS[@]+"${SKILLS[@]}"}" << 'PY'
import subprocess
import sys
from pathlib import Path

import upstream as up

root = Path(sys.argv[1])
offline = sys.argv[2] == "true"
regenerate = sys.argv[3] == "true"
licenses_only = sys.argv[4] == "true"
FETCH_TIMEOUT = 45
wanted = sys.argv[5:]

skills_dir = root / "skills"
candidates = sorted(d for d in skills_dir.iterdir() if d.is_dir())
if wanted:
    by_name = {d.name: d for d in candidates}
    missing = [w for w in wanted if w not in by_name]
    if missing:
        sys.exit(f"error: no such skill(s): {', '.join(missing)}")
    candidates = [by_name[w] for w in wanted]

adopted = [(d, up.upstream_block(d)) for d in candidates]
adopted = [(d, b) for d, b in adopted if b]

if not adopted:
    print("No adopted skills found (no CONFIG.yaml upstream: block).")
    sys.exit(0)

if licenses_only:
    width = max(len(d.name) for d, _ in adopted)
    print(f"{'SKILL'.ljust(width)}  LICENSE                      UPSTREAM")
    for d, b in adopted:
        lic = str(b.get("license", "unknown"))
        print(f"{d.name.ljust(width)}  {lic[:27].ljust(27)}  {b.get('repo', '?')}")
    print("\nRedistribution in a public bundle requires a permissive license.")
    print("Anything not MIT/Apache/BSD needs checking before it ships.")
    sys.exit(0)


def fetch(vendor: Path) -> bool:
    """Refresh a vendor checkout. Bounded: remotion-dev/remotion is a monorepo
    and a cold fetch there can outlast anyone's patience. On timeout we report
    against whatever refs are already local rather than hanging the run."""
    try:
        subprocess.run(
            ["git", "-C", str(vendor), "fetch", "--tags", "--quiet", "origin"],
            capture_output=True, timeout=FETCH_TIMEOUT,
        )
        return True
    except subprocess.TimeoutExpired:
        return False


def head_ref(vendor: Path) -> str:
    """Latest release tag if the repo tags, else the default branch head."""
    tags = subprocess.run(
        ["git", "-C", str(vendor), "tag", "--list", "--sort=-v:refname"],
        capture_output=True, text=True,
    ).stdout.split()
    if tags:
        return tags[0]
    result = subprocess.run(
        ["git", "-C", str(vendor), "symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
        capture_output=True, text=True,
    )
    return result.stdout.strip() or "origin/main"


RED, YELLOW, GREEN, DIM, RESET = "\033[31m", "\033[33m", "\033[32m", "\033[2m", "\033[0m"
if not sys.stdout.isatty():
    RED = YELLOW = GREEN = DIM = RESET = ""

local_drift_total = 0
upstream_drift_total = 0
orphan_total = 0

for skill_dir, block in adopted:
    name = skill_dir.name
    vendor = root / str(block.get("vendor", ""))
    path = str(block.get("path", "")).rstrip("/")
    pinned = str(block.get("commit", ""))
    status = str(block.get("status", "tracked"))

    print(f"\n{name}")
    print(f"  {DIM}{block.get('repo')} @ {block.get('ref')} ({pinned[:8]}){RESET}")

    if not (vendor / ".git").is_dir():
        print(f"  {YELLOW}vendor checkout missing: {block.get('vendor')}{RESET}")
        print(f"  {DIM}re-clone with scripts/adopt-skill.sh{RESET}")
        continue

    if not offline and not fetch(vendor):
        print(f"  {YELLOW}fetch timed out after {FETCH_TIMEOUT}s{RESET} — "
              f"{DIM}reporting against local refs, which may be stale{RESET}")

    # --- local drift: verbatim files that no longer match the pin ---
    path_map = block.get("path_map") if isinstance(block.get("path_map"), dict) else None
    observed = up.classify(skill_dir, vendor, pinned, path, path_map)
    declared = {}
    source_md = skill_dir / "SOURCE.md"
    if source_md.exists():
        for line in source_md.read_text().splitlines():
            if line.startswith("| `") and line.rstrip().endswith("|"):
                cells = [c.strip() for c in line.strip("|").split("|")]
                if len(cells) == 2 and cells[1] in up.ZONES:
                    declared[cells[0].strip("`")] = cells[1]

    broke_verbatim = [
        rel for rel, zone in declared.items()
        if zone == "verbatim" and observed.get(rel) == "adapted"
    ]
    vanished = [rel for rel in declared if rel not in observed]

    if broke_verbatim:
        local_drift_total += len(broke_verbatim)
        print(f"  {RED}local drift: {len(broke_verbatim)} verbatim file(s) edited{RESET}")
        for rel in broke_verbatim[:10]:
            print(f"    {RED}M{RESET} {rel}")
        if len(broke_verbatim) > 10:
            print(f"    {DIM}... and {len(broke_verbatim) - 10} more{RESET}")
        print(f"    {DIM}revert, or demote to adapted in SOURCE.md with a reason{RESET}")
    if vanished:
        print(f"  {YELLOW}{len(vanished)} file(s) in SOURCE.md no longer exist{RESET}")

    counts = {}
    for zone in observed.values():
        counts[zone] = counts.get(zone, 0) + 1
    print(f"  zones: " + ", ".join(f"{v} {k}" for k, v in sorted(counts.items())))

    # --- orphaned ---
    if status == "orphaned":
        orphan_total += 1
        print(f"  {YELLOW}orphaned upstream{RESET} — deleted after "
              f"{block.get('last_seen_ref', 'an unknown ref')}; nothing to sync, ever")
        if regenerate:
            up.write_source_md(skill_dir, name, block, observed)
        continue

    # --- upstream drift ---
    if offline:
        print(f"  {DIM}upstream check skipped (--offline){RESET}")
    else:
        latest = head_ref(vendor)
        latest_sha = subprocess.run(
            ["git", "-C", str(vendor), "rev-parse", f"{latest}^{{commit}}"],
            capture_output=True, text=True,
        ).stdout.strip()

        if not latest_sha:
            print(f"  {YELLOW}could not resolve upstream head{RESET}")
        elif latest_sha == pinned:
            print(f"  {GREEN}up to date with {latest}{RESET}")
        else:
            # A renamed skill lives somewhere else at head; diff across the move.
            head_path = str(block.get("head_path") or path).rstrip("/")
            exists = subprocess.run(
                ["git", "-C", str(vendor), "cat-file", "-e", f"{latest_sha}:{head_path}"],
                capture_output=True,
            ).returncode == 0
            if not exists:
                upstream_drift_total += 1
                print(f"  {YELLOW}upstream path gone at {latest}{RESET} — renamed or "
                      f"deleted; set status: renamed (+head_path) or orphaned")
            else:
                if head_path != path:
                    diff_args = [f"{pinned}:{path}", f"{latest_sha}:{head_path}"]
                    print(f"  {DIM}renamed upstream: {path} -> {head_path}{RESET}")
                else:
                    diff_args = [pinned, latest_sha, "--", path]
                changed = subprocess.run(
                    ["git", "-C", str(vendor), "diff", "--stat"] + diff_args,
                    capture_output=True, text=True,
                ).stdout.strip().splitlines()
                if changed:
                    upstream_drift_total += 1
                    print(f"  {YELLOW}upstream drift{RESET}: {latest} "
                          f"({latest_sha[:8]}) changed {len(changed) - 1} file(s)")
                    for line in changed[:8]:
                        print(f"    {DIM}{line.strip()}{RESET}")
                    print(f"    {DIM}git -C {block.get('vendor')} diff "
                          f"{' '.join(diff_args)}{RESET}")
                else:
                    print(f"  {GREEN}upstream moved but this skill is unchanged{RESET}")

    if regenerate:
        up.write_source_md(skill_dir, name, block, observed)

print()
print(f"{len(adopted)} adopted skill(s): "
      f"{upstream_drift_total} with upstream drift, "
      f"{local_drift_total} local drift file(s), "
      f"{orphan_total} orphaned")
if regenerate:
    print("SOURCE.md regenerated from CONFIG.yaml.")

sys.exit(1 if local_drift_total else 0)
PY
