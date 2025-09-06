#!/usr/bin/env bash
set -euo pipefail

# clone_siimut_application (kept filename for compatibility)
#
# Idempotent, safe clone/update script for:
#   https://github.com/juniyasyos/siimut-application
#
# Defaults:
#   - Clones into "$HOME/siimut-docker/site/siimut-application" by default
#   - Uses HTTPS by default; `--ssh` switches to SSH
#   - Optional `--branch <name>` and `--shallow`
#   - Safe update: refuses to modify dirty working tree unless `--hard-update`
#
# Usage examples:
#   scripts/clone_siimut_application
#   scripts/clone_siimut_application --dir /var/www/site
#   scripts/clone_siimut_application --ssh --branch main --shallow
#   scripts/clone_siimut_application --hard-update

REPO_PATH="juniyasyos/siimut-application"
HTTPS_URL="https://github.com/${REPO_PATH}.git"
SSH_URL="git@github.com:${REPO_PATH}.git"

TARGET_PARENT="${HOME}/siimut-docker/site"
REPO_NAME="siimut-application"
# Leave BRANCH empty to use the repo default branch (safer)
BRANCH=""
SHALLOW=false
USE_SSH=false
HARD_UPDATE=false

usage() {
  cat <<EOF
Clone or update ${REPO_PATH} into a local directory.

Options:
  --dir <path>        Parent directory (default: ${HOME}/siimut-docker/site)
  --branch <name>     Checkout and track a specific branch
  --shallow           Use shallow clone (depth=1)
  --ssh               Use SSH remote instead of HTTPS
  --hard-update       If repo exists and dirty, reset hard to update
  -h, --help          Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --dir /var/www/site
  $(basename "$0") --ssh --branch main --shallow
  $(basename "$0") --hard-update
EOF
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: '$1' not found; please install it." >&2
    exit 1
  }
}

normalize_remote() {
  # Print normalized owner/repo path for comparison
  # Accepts an arbitrary Git remote URL
  local url="$1"
  # Strip protocol prefixes and .git suffix
  url="${url#git@github.com:}"
  url="${url#https://github.com/}"
  url="${url#ssh://git@github.com/}"
  url="${url%.git}"
  printf '%s\n' "$url"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      [[ $# -ge 2 ]] || { echo "--dir requires a value" >&2; exit 2; }
      TARGET_PARENT="$2"; shift 2 ;;
    --branch)
      [[ $# -ge 2 ]] || { echo "--branch requires a value" >&2; exit 2; }
      BRANCH="$2"; shift 2 ;;
    --shallow)
      SHALLOW=true; shift ;;
    --ssh)
      USE_SSH=true; shift ;;
    --hard-update)
      HARD_UPDATE=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

require git

# Recompute clone dir after parsing options (honor --dir)
CLONE_DIR="${TARGET_PARENT}/${REPO_NAME}"

REMOTE_URL="$HTTPS_URL"
if [[ "$USE_SSH" == true ]]; then
  REMOTE_URL="$SSH_URL"
fi

mkdir -p "$TARGET_PARENT"

trap 'echo "Aborted." >&2' INT TERM

if [[ ! -d "$CLONE_DIR/.git" ]]; then
  echo "Cloning into: $CLONE_DIR"
  args=("$REMOTE_URL" "$CLONE_DIR")
  if [[ -n "$BRANCH" ]]; then
    args=("--branch" "$BRANCH" "--single-branch" "${args[@]}")
  fi
  if [[ "$SHALLOW" == true ]]; then
    args=("--depth=1" "${args[@]}")
  fi
  git clone "${args[@]}"
  cd "$CLONE_DIR"
else
  echo "Repository exists at: $CLONE_DIR"
  cd "$CLONE_DIR"
  # Verify remote origin points to the same repo
  current_origin="$(git remote get-url origin || true)"
  if [[ -n "$current_origin" ]]; then
    want="$(normalize_remote "$REMOTE_URL")"
    have="$(normalize_remote "$current_origin")"
    if [[ "$want" != "$have" ]]; then
      echo "Updating origin from '$current_origin' to '$REMOTE_URL'"
      git remote set-url origin "$REMOTE_URL"
    fi
  else
    git remote add origin "$REMOTE_URL"
  fi
fi

# Safety: avoid clobbering local changes unless explicitly requested
if [[ -n "$(git status --porcelain)" ]]; then
  if [[ "$HARD_UPDATE" == true ]]; then
    echo "Working tree dirty; applying hard reset as requested."
    git reset --hard
  else
    echo "Working tree has uncommitted changes. Use --hard-update to reset." >&2
    exit 1
  fi
fi

git fetch --prune origin

if [[ -n "$BRANCH" ]]; then
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git checkout "$BRANCH"
  else
    # Create local branch tracking origin/BRANCH if it exists
    if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
      git checkout -B "$BRANCH" "origin/$BRANCH"
    else
      echo "Branch '$BRANCH' not found on origin; staying on current branch." >&2
    fi
  fi
fi

# Fast-forward only to avoid unintended merges
if git rev-parse --verify -q HEAD >/dev/null; then
  if git rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
    git pull --ff-only --no-rebase origin "$(git rev-parse --abbrev-ref HEAD)" || true
  fi
fi

echo "Done. Location: $CLONE_DIR"
