#!/bin/bash
# adopt-skill.sh - Vendor an external skill and scaffold it for adaptation
#
# Clones the upstream repo into vendor/ (gitignored), pins it to a ref, copies
# the skill into the sandbox, and records provenance in CONFIG.yaml + SOURCE.md.
# See docs/adopting-external-skills.md for the three gates you must then clear.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/vendor"
SANDBOX_DIR="${SKILLMONGER_SANDBOX:-$HOME/Development/sandbox/skills}"
TODAY=$(date +%Y-%m-%d)

# shellcheck source=lib/skill-name.sh
. "$SCRIPT_DIR/lib/skill-name.sh"

usage() {
  cat << EOF
Usage: $(basename "$0") <repo-url> <upstream-skill-path> [options]

Vendors an external skill and scaffolds it in the sandbox for adaptation.

Arguments:
  repo-url              GitHub URL or owner/repo
  upstream-skill-path   Path to the skill inside that repo
                        e.g. skills/isometric-explainer

Options:
  --ref <ref>       Tag, branch, or SHA to pin. Default: latest release, else HEAD
  --name <name>     Local skill name. Default: basename of upstream-skill-path
  --into <dir>      Target directory. Default: \$SKILLMONGER_SANDBOX/<name>
  --in-place        Adopt directly into skills/<name> (backfill; skips sandbox)
  --help            Show this help

Examples:
  $(basename "$0") LaurentiuGabriel/learnscape skills/isometric-explainer
  $(basename "$0") mattpocock/skills skills/productivity/grill-me --ref v1.2.3 --in-place
EOF
}

REPO=""; UPSTREAM_PATH=""; REF=""; NAME=""; INTO=""; IN_PLACE=false
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --into) INTO="$2"; shift 2 ;;
    --in-place) IN_PLACE=true; shift ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *)
      if [ -z "$REPO" ]; then REPO="$1"
      elif [ -z "$UPSTREAM_PATH" ]; then UPSTREAM_PATH="$1"
      else echo "Unexpected argument: $1" >&2; exit 1; fi
      shift ;;
  esac
done

if [ -z "$REPO" ] || [ -z "$UPSTREAM_PATH" ]; then
  usage >&2; exit 1
fi

UPSTREAM_PATH="${UPSTREAM_PATH%/}"
[ -n "$NAME" ] || NAME="$(basename "$UPSTREAM_PATH")"
skill_name_require "$NAME"

# Normalise repo to owner/repo plus a full URL.
SLUG="$REPO"
SLUG="${SLUG#https://github.com/}"
SLUG="${SLUG#git@github.com:}"
SLUG="${SLUG%.git}"
REPO_URL="https://github.com/$SLUG"
OWNER="${SLUG%%/*}"
REPO_NAME="${SLUG##*/}"

# Vendor dir name: repo name, or owner-repo when the bare name would collide.
VENDOR_NAME="$REPO_NAME"
if [ -d "$VENDOR_DIR/$VENDOR_NAME/.git" ]; then
  existing=$(git -C "$VENDOR_DIR/$VENDOR_NAME" remote get-url origin 2>/dev/null || echo "")
  case "$existing" in
    *"$SLUG"*) : ;;
    *) VENDOR_NAME="$OWNER-$REPO_NAME" ;;
  esac
fi
# Match the pre-existing convention for repos already vendored by hand.
[ -d "$VENDOR_DIR/$OWNER-$REPO_NAME/.git" ] && VENDOR_NAME="$OWNER-$REPO_NAME"
VENDOR_PATH="$VENDOR_DIR/$VENDOR_NAME"

# --- 1. Vendor the repo (idempotent) ---
mkdir -p "$VENDOR_DIR"
if [ -d "$VENDOR_PATH/.git" ]; then
  echo "Vendor checkout exists: vendor/$VENDOR_NAME — fetching"
  git -C "$VENDOR_PATH" fetch --tags --quiet origin
else
  echo "Cloning $REPO_URL -> vendor/$VENDOR_NAME"
  if command -v gh > /dev/null 2>&1; then
    gh repo clone "$SLUG" "$VENDOR_PATH" -- --quiet
  else
    git clone --quiet "$REPO_URL" "$VENDOR_PATH"
  fi
fi

# --- 2. Resolve the ref ---
if [ -z "$REF" ]; then
  REF=$(git -C "$VENDOR_PATH" tag --list --sort=-v:refname | head -1)
  if [ -n "$REF" ]; then
    echo "No --ref given; using latest tag: $REF"
  else
    REF=$(git -C "$VENDOR_PATH" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
    REF="origin/${REF:-main}"
    echo "No tags upstream; using $REF"
  fi
fi

if ! COMMIT=$(git -C "$VENDOR_PATH" rev-parse --verify --quiet "${REF}^{commit}"); then
  echo "ERROR: cannot resolve ref '$REF' in vendor/$VENDOR_NAME" >&2
  exit 1
fi

if ! git -C "$VENDOR_PATH" cat-file -e "$COMMIT:$UPSTREAM_PATH" 2>/dev/null; then
  echo "ERROR: '$UPSTREAM_PATH' does not exist at $REF ($COMMIT)" >&2
  echo "Available skills at that ref:" >&2
  git -C "$VENDOR_PATH" ls-tree -r --name-only "$COMMIT" \
    | grep '/SKILL\.md$' | sed 's|/SKILL.md$||;s|^|  |' >&2
  exit 1
fi

# --- 3. Detect the license ---
LICENSE="unknown"
if command -v gh > /dev/null 2>&1; then
  LICENSE=$(gh repo view "$SLUG" --json licenseInfo \
    --jq '.licenseInfo.name // "unknown"' 2>/dev/null || echo "unknown")
fi

# --- 4. Choose the target ---
if [ "$IN_PLACE" = true ]; then
  TARGET="$PROJECT_ROOT/skills/$NAME"
  [ -d "$TARGET" ] || { echo "ERROR: skills/$NAME does not exist (--in-place expects it)" >&2; exit 1; }
  echo "Backfilling provenance in place: skills/$NAME"
else
  TARGET="${INTO:-$SANDBOX_DIR/$NAME}"
  if [ -e "$TARGET" ]; then
    echo "ERROR: $TARGET already exists. Remove it or pass --into." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$TARGET")"
  echo "Copying upstream skill -> $TARGET"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  git -C "$VENDOR_PATH" archive "$COMMIT" "$UPSTREAM_PATH" | tar -x -C "$tmp"
  cp -R "$tmp/$UPSTREAM_PATH" "$TARGET"
fi

# --- 5. Record provenance ---
PYTHONPATH="$SCRIPT_DIR/lib" python3 - \
         "$TARGET" "$NAME" "$REPO_URL" "vendor/$VENDOR_NAME" "$UPSTREAM_PATH" \
         "$REF" "$COMMIT" "$LICENSE" "$TODAY" "$VENDOR_PATH" << 'PY'
import sys
from pathlib import Path

import upstream as up

(target, name, repo, vendor_rel, path, ref, commit, license_, today, vendor_abs) = sys.argv[1:11]
target = Path(target)

# A sandbox adoption starts with no CONFIG.yaml; give it a minimal identity
# block so the generated upstream: block lands under something coherent.
config = target / "CONFIG.yaml"
if not config.exists():
    config.write_text(
        "skill:\n"
        f"  name: {name}\n"
        "  version: 0.1.0\n"
        f"  created: {today}\n"
        f"  updated: {today}\n"
        "  author: kevin\n"
    )

block = {
    "repo": repo,
    "vendor": vendor_rel,
    "path": path,
    "ref": ref,
    "commit": commit,
    "license": license_,
    "synced": today,
    "status": "tracked",
}
up.write_upstream_block(target, block)
zones = up.classify(target, Path(vendor_abs), commit, path)
up.write_source_md(target, name, block, zones)

counts = {}
for zone in zones.values():
    counts[zone] = counts.get(zone, 0) + 1
print("  zones: " + ", ".join(f"{v} {k}" for k, v in sorted(counts.items())))
PY

echo ""
echo "Adopted: $NAME"
echo "  upstream:  $REPO_URL/$UPSTREAM_PATH @ $REF ($(echo "$COMMIT" | cut -c1-8))"
echo "  license:   $LICENSE"
echo "  target:    $TARGET"
echo ""
if [ "$IN_PLACE" = false ]; then
  cat << EOF
Next, in $TARGET:
  1. Clear the three gates in docs/adopting-external-skills.md
     (tool portability, dependency adaptation, upstream updatability)
  2. Add CONFIG.yaml triggers, MEMO.md, and the feedback epilogue
  3. Keep references/ and assets/ verbatim; put changes in OVERLAY.md
  4. scripts/ship-skill.sh $TARGET
EOF
fi
