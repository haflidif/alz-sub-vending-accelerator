#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
script_path="$repository_root/.github/scripts/discover-subs.sh"
test_root="$repository_root/.discover-subs-tests"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_count() {
  local expected="$1"
  local output_file="$2"
  grep -qx "count=$expected" "$output_file" \
    || fail "expected count=$expected in $output_file"
}

assert_shared_changed() {
  local expected="$1"
  local output_file="$2"
  grep -qx "shared_changed=$expected" "$output_file" \
    || fail "expected shared_changed=$expected in $output_file"
}

rm -rf "$test_root"
mkdir -p "$test_root"
git -C "$test_root" init -q
git -C "$test_root" config user.email test@example.com
git -C "$test_root" config user.name "Discovery Test"
git -C "$test_root" config commit.gpgsign false
mkdir -p "$test_root/landingzones/corp" "$test_root/landingzones/online" \
  "$test_root/terraform" "$test_root/bicep" "$test_root/.github/scripts" \
  "$test_root/.github/workflows"
cp "$script_path" "$test_root/.github/scripts/discover-subs.sh"
printf '{}\n' > "$test_root/landingzones/corp/corp-one.yaml"
printf '{}\n' > "$test_root/landingzones/online/online-one.yaml"
printf 'terraform {}\n' > "$test_root/terraform/main.tf"
printf 'targetScope = '\''managementGroup'\''\n' > "$test_root/bicep/main.bicep"
printf '{}\n' > "$test_root/bicep/platform.json"
printf '{}\n' > "$test_root/bicep/default-resource-providers.json"
git -C "$test_root" add .
git -C "$test_root" commit -qm "Initial fixture"
base="$(git -C "$test_root" rev-parse HEAD)"

printf '# changed\n' >> "$test_root/landingzones/corp/corp-one.yaml"
git -C "$test_root" add .
git -C "$test_root" commit -qm "Change one subscription"
head="$(git -C "$test_root" rev-parse HEAD)"
output="$test_root/yaml-output.txt"
(
  cd "$test_root"
  MODE=changed BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 1 "$output"
assert_shared_changed false "$output"
grep -q '"sub_path":"landingzones/corp/corp-one.yaml"' "$output" \
  || fail "single YAML change did not select the changed subscription"
if grep -q 'online-one' "$output"; then
  fail "single YAML change selected an unrelated subscription"
fi

base="$head"
printf '# documentation change\n' > "$test_root/terraform/README.md"
git -C "$test_root" add .
git -C "$test_root" commit -qm "Change Terraform documentation"
head="$(git -C "$test_root" rev-parse HEAD)"
output="$test_root/terraform-docs-output.txt"
(
  cd "$test_root"
  MODE=changed BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 0 "$output"
assert_shared_changed false "$output"

base="$head"
printf '# changed\n' >> "$test_root/terraform/main.tf"
git -C "$test_root" add .
git -C "$test_root" commit -qm "Change Terraform"
head="$(git -C "$test_root" rev-parse HEAD)"
output="$test_root/terraform-output.txt"
(
  cd "$test_root"
  MODE=changed BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 2 "$output"
assert_shared_changed true "$output"
grep -q 'corp-one' "$output" || fail "Terraform change omitted corp subscription"
grep -q 'online-one' "$output" || fail "Terraform change omitted online subscription"

output="$test_root/terraform-push-output.txt"
(
  cd "$test_root"
  MODE=changed INCLUDE_SHARED_CHANGES=false BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 0 "$output"
assert_shared_changed true "$output"

base="$head"
printf '# changed\n' >> "$test_root/bicep/main.bicep"
git -C "$test_root" add .
git -C "$test_root" commit -qm "Change Bicep"
head="$(git -C "$test_root" rev-parse HEAD)"
output="$test_root/bicep-output.txt"
(
  cd "$test_root"
  MODE=changed VENDING_ENGINE=bicep BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 2 "$output"
assert_shared_changed true "$output"
grep -q 'corp-one' "$output" || fail "Bicep change omitted corp subscription"
grep -q 'online-one' "$output" || fail "Bicep change omitted online subscription"

output="$test_root/bicep-push-output.txt"
(
  cd "$test_root"
  MODE=changed VENDING_ENGINE=bicep INCLUDE_SHARED_CHANGES=false \
    BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 0 "$output"
assert_shared_changed true "$output"

base="$head"
printf ' \n' >> "$test_root/bicep/platform.json"
git -C "$test_root" add .
git -C "$test_root" commit -qm "Change Bicep platform configuration"
head="$(git -C "$test_root" rev-parse HEAD)"
output="$test_root/bicep-platform-output.txt"
(
  cd "$test_root"
  MODE=changed VENDING_ENGINE=bicep BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 2 "$output"
assert_shared_changed true "$output"

base="$head"
printf ' \n' >> "$test_root/bicep/default-resource-providers.json"
git -C "$test_root" add .
git -C "$test_root" commit -qm "Change Bicep provider defaults"
head="$(git -C "$test_root" rev-parse HEAD)"
output="$test_root/bicep-providers-output.txt"
(
  cd "$test_root"
  MODE=changed VENDING_ENGINE=bicep BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 2 "$output"
assert_shared_changed true "$output"

base="$head"
printf '# shared workflow change\n' > "$test_root/.github/workflows/apply.yml"
git -C "$test_root" add .
git -C "$test_root" commit -qm "Change shared workflow"
head="$(git -C "$test_root" rev-parse HEAD)"
output="$test_root/shared-workflow-preview-output.txt"
(
  cd "$test_root"
  MODE=changed BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 2 "$output"
assert_shared_changed true "$output"

output="$test_root/shared-workflow-push-output.txt"
(
  cd "$test_root"
  MODE=changed INCLUDE_SHARED_CHANGES=false BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 0 "$output"
assert_shared_changed true "$output"

base="$head"
printf '{"type":"object"}\n' > "$test_root/landingzones/sub.schema.json"
printf '# changed with schema\n' >> "$test_root/landingzones/corp/corp-one.yaml"
git -C "$test_root" add .
git -C "$test_root" commit -qm "Change shared request schema and request"
head="$(git -C "$test_root" rev-parse HEAD)"
output="$test_root/shared-schema-preview-output.txt"
(
  cd "$test_root"
  MODE=changed BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 2 "$output"
assert_shared_changed true "$output"

output="$test_root/shared-schema-push-output.txt"
(
  cd "$test_root"
  MODE=changed INCLUDE_SHARED_CHANGES=false BASE="$base" HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
)
assert_count 0 "$output"
assert_shared_changed true "$output"
if grep -q 'corp-one' "$output"; then
  fail "shared change allowed a co-committed request to deploy automatically"
fi

output="$test_root/manual-all-output.txt"
(
  cd "$test_root"
  MODE=all GITHUB_OUTPUT="$output" bash .github/scripts/discover-subs.sh
)
assert_count 2 "$output"
assert_shared_changed false "$output"

output="$test_root/invalid-base-output.txt"
if (
  cd "$test_root"
  MODE=changed BASE=origin/does-not-exist HEAD="$head" GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
); then
  fail "invalid BASE succeeded"
fi
[[ ! -s "$output" ]] || fail "invalid BASE emitted successful outputs"

output="$test_root/invalid-engine-output.txt"
if (
  cd "$test_root"
  MODE=all VENDING_ENGINE=invalid GITHUB_OUTPUT="$output" \
    bash .github/scripts/discover-subs.sh
); then
  fail "invalid VENDING_ENGINE succeeded"
fi
[[ ! -s "$output" ]] || fail "invalid VENDING_ENGINE emitted successful outputs"

echo "discover-subs tests passed."
