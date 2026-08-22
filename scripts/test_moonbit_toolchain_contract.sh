#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_VERSION='moon 0.1.20260819 (fc2a4ee 2026-08-19)'
EXPECTED_CACHE_ID='0.1.20260819-fc2a4ee'

workflows=(
  adoption.yml
  bench.yml
  compat-table.yml
  copilot-setup-steps.yml
  playground.yml
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

  [[ "$(grep -Fc 'MOONBIT_INSTALL_VERSION: "latest"' "$workflow")" -eq 1 ]] ||
    fail "$workflow_name must select the official latest installer channel once"
  [[ "$(grep -Fc "MOONBIT_EXPECTED_VERSION: \"$EXPECTED_VERSION\"" "$workflow")" -eq 1 ]] ||
    fail "$workflow_name must declare the resolved MoonBit identity once"
  [[ "$(grep -Fc "MOONBIT_CACHE_VERSION: \"$EXPECTED_CACHE_ID\"" "$workflow")" -eq 1 ]] ||
    fail "$workflow_name must key the toolchain cache by the resolved identity"

  cache_count="$(grep -Fc 'id: toolchain-cache' "$workflow")"
  verify_count="$(grep -Fc 'run: bash scripts/verify_moonbit_toolchain.sh' "$workflow")"
  [[ "$cache_count" -gt 0 ]] || fail "$workflow_name has no toolchain cache consumer"
  [[ "$verify_count" -eq "$cache_count" ]] ||
    fail "$workflow_name must verify every restored or installed toolchain"
done

[[ -x "$ROOT_DIR/scripts/verify_moonbit_toolchain.sh" ]] ||
  fail 'scripts/verify_moonbit_toolchain.sh must exist and be executable'

actionlint_workflow="$ROOT_DIR/.github/workflows/actionlint.yml"
[[ "$(grep -Fc -- "- 'scripts/verify_moonbit_toolchain.sh'" "$actionlint_workflow")" -eq 2 ]] ||
  fail 'actionlint must run when the toolchain verifier changes'
[[ "$(grep -Fc -- "- 'scripts/test_moonbit_toolchain_contract.sh'" "$actionlint_workflow")" -eq 2 ]] ||
  fail 'actionlint must run when the toolchain contract test changes'
[[ "$(grep -Fc 'run: bash scripts/test_moonbit_toolchain_contract.sh' "$actionlint_workflow")" -eq 1 ]] ||
  fail 'actionlint must execute the toolchain contract test once'

printf 'toolchain contract: ok\n'
