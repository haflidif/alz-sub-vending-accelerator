#!/usr/bin/env bash
# =============================================================================
# discover-subs.sh
# -----------------------------------------------------------------------------
# Emits a GitHub Actions matrix (JSON) of subscriptions to operate on.
#
# Each subscription is described by ONE flat YAML file:
#   landingzones/<archetype>/<sub-name>.yaml
#
# Modes:
#   changed  — subs whose YAML was added/modified between $BASE and $HEAD
#              Shared engine/platform changes select every subscription when
#              $INCLUDE_SHARED_CHANGES is true (the default for PR previews).
#   single   — only the subscription at $SUB_PATH (the .yaml file, OR just the
#              <archetype>/<sub-name> stem; .yaml is appended if missing)
#   all      — every landingzones/*/*.yaml in the repo
#
# Outputs (written to $GITHUB_OUTPUT):
#   matrix=<json>            -- {"include":[{"sub_path":"...","archetype":"...","name":"...","state_key":"..."}]}
#   count=<int>
#   shared_changed=<bool>    -- selected-engine/shared delivery files changed
# =============================================================================
set -euo pipefail

MODE="${MODE:-changed}"
BASE="${BASE:-origin/main}"
HEAD="${HEAD:-HEAD}"
SUB_PATH="${SUB_PATH:-}"
VENDING_ENGINE="${VENDING_ENGINE:-terraform}"
INCLUDE_SHARED_CHANGES="${INCLUDE_SHARED_CHANGES:-true}"
shared_changed=false

case "$VENDING_ENGINE" in
  terraform|bicep) ;;
  *) echo "::error::unknown VENDING_ENGINE: $VENDING_ENGINE" >&2; exit 1 ;;
esac
case "$INCLUDE_SHARED_CHANGES" in
  true|false) ;;
  *) echo "::error::INCLUDE_SHARED_CHANGES must be true or false" >&2; exit 1 ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

discover_all() {
  find landingzones -mindepth 2 -maxdepth 2 -type f -name '*.yaml' | sort
}

validate_diff_refs() {
  # Only fetch when BASE looks like a remote ref. Commit SHAs (from
  # github.event.before on push) are already in the repo when fetch-depth=0.
  if [[ "$BASE" == origin/* ]]; then
    git fetch --no-tags --prune --unshallow origin "${BASE#origin/}" >/dev/null 2>&1 \
      || git fetch --no-tags --prune origin "${BASE#origin/}" >/dev/null 2>&1 \
      || true
  fi

  if ! git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
    echo "::error::BASE does not resolve to a commit: $BASE" >&2
    return 1
  fi
  if ! git rev-parse --verify --quiet "${HEAD}^{commit}" >/dev/null; then
    echo "::error::HEAD does not resolve to a commit: $HEAD" >&2
    return 1
  fi
}

changed_files() {
  git diff --name-only "${BASE}...${HEAD}" -- \
    "$VENDING_ENGINE" \
    '.github/workflows/**' \
    '.github/scripts/**' \
    'landingzones/sub.schema.json' \
    'landingzones/*/*.yaml'
}

detect_shared_change() {
  local changed
  changed="$(changed_files)"
  if [[ "$VENDING_ENGINE" == "terraform" ]] \
    && grep -Eq '^terraform/.*\.tf(\.json)?$' <<<"$changed"; then
    echo true
  elif [[ "$VENDING_ENGINE" == "bicep" ]] \
    && grep -Eq '^bicep/(.*\.(bicep|psm1)|platform\.json|default-resource-providers\.json)$' <<<"$changed"; then
    echo true
  elif grep -Eq '^(\.github/(workflows|scripts)/|landingzones/sub\.schema\.json$)' <<<"$changed"; then
    echo true
  else
    echo false
  fi
}

discover_changed() {
  if [[ "$shared_changed" == "true" ]]; then
    if [[ "$INCLUDE_SHARED_CHANGES" == "true" ]]; then
      discover_all
    fi
  else
    git diff --name-only --diff-filter=AM "${BASE}...${HEAD}" \
      -- 'landingzones/*/*.yaml' | sort -u
  fi
}

files=()
case "$MODE" in
  all)
    discovered="$(discover_all)"
    [[ -z "$discovered" ]] || mapfile -t files <<<"$discovered"
    ;;
  changed)
    validate_diff_refs
    shared_changed="$(detect_shared_change)"
    discovered="$(discover_changed)"
    [[ -z "$discovered" ]] || mapfile -t files <<<"$discovered"
    ;;
  single)
    if [[ -z "$SUB_PATH" ]]; then
      echo "::error::mode=single requires SUB_PATH (e.g. landingzones/corp/prod-corp-erp-001 or landingzones/corp/prod-corp-erp-001.yaml)" >&2
      exit 1
    fi
    if [[ "$SUB_PATH" == *.yaml ]]; then
      files=("$SUB_PATH")
    else
      files=("${SUB_PATH%/}.yaml")
    fi
    [[ -f "${files[0]}" ]] || { echo "::error::not found: ${files[0]}" >&2; exit 1; }
    ;;
  *) echo "::error::unknown MODE: $MODE" >&2; exit 1 ;;
esac

include="[]"
count=0
for f in "${files[@]:-}"; do
  [[ -z "$f" ]] && continue
  # landingzones/<archetype>/<name>.yaml
  arch="$(echo "$f" | awk -F'/' '{print $2}')"
  base="$(echo "$f" | awk -F'/' '{print $3}')"
  name="${base%.yaml}"
  [[ -z "$arch" || -z "$name" || "$base" == "$name" ]] && { echo "::warning::skipping malformed path: $f"; continue; }
  entry=$(jq -nc --arg p "$f" --arg a "$arch" --arg n "$name" \
    '{sub_path:$p, archetype:$a, name:$n, state_key:("\($a)/\($n).tfstate")}')
  include=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$include")
  count=$((count + 1))
done

matrix=$(jq -nc --argjson inc "$include" '{include:$inc}')
{
  echo "matrix=${matrix}"
  echo "count=${count}"
  echo "shared_changed=${shared_changed}"
} >>"${GITHUB_OUTPUT:-/dev/stdout}"

echo "Discovered $count subscription(s) for mode=$MODE"
echo "Shared change detected: $shared_changed"
jq . <<<"$matrix" || true
