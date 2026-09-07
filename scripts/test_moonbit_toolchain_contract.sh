#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

workflows=(
  adoption.yml
  bench.yml
  compat-table.yml
  copilot-setup-steps.yml
  playground.yml
  jetstream3-admission.yml
  startup-hyperfine.yml
  test262.yml
)

fail() {
  printf 'toolchain contract: %s\n' "$1" >&2
  exit 1
}

for workflow_name in "${workflows[@]}"; do
  workflow="$ROOT_DIR/.github/workflows/$workflow_name"
  [[ -f "$workflow" ]] || fail "$workflow_name is missing"

  [[ "$(grep -Fc 'MOONBIT_INSTALL_VERSION: "nightly"' "$workflow")" -eq 1 ]] ||
    fail "$workflow_name must select the official nightly channel once"
  if grep -Eq 'MOONBIT_EXPECTED_VERSION|MOONBIT_CACHE_VERSION|toolchain-cache|verify_moonbit_toolchain' "$workflow"; then
    fail "$workflow_name must not pin or restore an obsolete toolchain"
  fi
  install_count="$(grep -Fc 'run: curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash' "$workflow")"
  version_count="$(grep -Fc 'moon version --all' "$workflow")"
  [[ "$install_count" -gt 0 && "$version_count" -eq "$install_count" ]] ||
    fail "$workflow_name must install and record the toolchain in every MoonBit job"
  if grep -F "version=\$(moon version" "$workflow" | grep -Fv "\$(moonc -v)"; then
    fail "$workflow_name must include the compiler identity in cache keys"
  fi

done

unit_test_block="$(sed -n '/^  unit-test:$/,/^  unit-test-runner:$/p' "$ROOT_DIR/.github/workflows/test262.yml")"
[[ "$(grep -Fc 'timeout-minutes: 30' <<<"$unit_test_block")" -eq 1 ]] ||
  fail 'test262 unit-test must allow 30 minutes for architecture audit and the full test suite'

actionlint_workflow="$ROOT_DIR/.github/workflows/actionlint.yml"
[[ "$(grep -Fc -- "- 'scripts/test_moonbit_toolchain_contract.sh'" "$actionlint_workflow")" -eq 2 ]] ||
  fail 'actionlint must run when the toolchain contract test changes'
[[ "$(grep -Fc 'run: bash scripts/test_moonbit_toolchain_contract.sh' "$actionlint_workflow")" -eq 1 ]] ||
  fail 'actionlint must execute the toolchain contract test once'

printf 'toolchain contract: ok\n'
