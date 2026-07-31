#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
ROOT_DIR=${STACK_SAFETY_GATE_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
MAKEFILE="$ROOT_DIR/Makefile"
WORKFLOW="$ROOT_DIR/.github/workflows/adoption.yml"
CONSUMER_PACKAGE="$ROOT_DIR/integration/external_consumer/moon.pkg"
CONSUMER_SUITE="$ROOT_DIR/integration/external_consumer/stack_safety_test.mbt"
DEFERRED_SUITE="$ROOT_DIR/interpreter/stack_safety_deferred_test.mbt"
CHECK_ONLY=false

if [[ ${1:-} == "--check-only" ]]; then
  CHECK_ONLY=true
elif [[ $# -ne 0 ]]; then
  echo "usage: $0 [--check-only]" >&2
  exit 2
fi

fail() {
  echo "stack-safety gate validation: $1" >&2
  exit 1
}

[[ -f "$MAKEFILE" ]] || fail 'Makefile is missing'
[[ -f "$WORKFLOW" ]] || fail 'adoption workflow is missing'
[[ -f "$CONSUMER_PACKAGE" ]] || fail 'external-consumer package manifest is missing'
[[ -f "$CONSUMER_SUITE" ]] || fail 'external-consumer stack-safety suite is missing'

grep -Fq 'stack-safety-test' "$MAKEFILE" ||
  fail 'focused stack-safety Make target is missing'
grep -Fq 'PROFILE' "$MAKEFILE" ||
  fail 'focused stack-safety Make target lacks profile selection'
grep -Fq 'stack-safety:' "$WORKFLOW" ||
  fail 'focused stack-safety workflow job is missing'
grep -Eq 'run: make stack-safety-test TARGET=.*PROFILE=' "$WORKFLOW" ||
  fail 'workflow does not invoke the focused Make target with its matrix profile'

expected_pairs=$(printf '%s\n' \
  'native debug' \
  'native release' \
  'js debug' \
  'js release' \
  'wasm debug' \
  'wasm release' \
  'wasm-gc debug' \
  'wasm-gc release' | sort)
actual_pairs=$(awk '
  /^  stack-safety:/ { in_stack=1; next }
  in_stack && /^    steps:/ { exit }
  in_stack && /^          - target:/ { target=$3; next }
  in_stack && /^            profile:/ { print target " " $2; target="" }
' "$WORKFLOW" | sort)
actual_count=$(printf '%s\n' "$actual_pairs" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
unique_count=$(printf '%s\n' "$actual_pairs" | sed '/^[[:space:]]*$/d' | sort -u | wc -l | tr -d ' ')
[[ "$actual_count" -eq 8 ]] ||
  fail "workflow stack-safety matrix must contain exactly 8 pairs (found $actual_count)"
[[ "$unique_count" -eq 8 ]] ||
  fail 'workflow stack-safety matrix contains duplicate target/profile pairs'
if ! diff -u <(printf '%s\n' "$expected_pairs") <(printf '%s\n' "$actual_pairs") >/dev/null; then
  fail 'workflow stack-safety matrix has a missing or decoy target/profile pair'
fi

selected_suites=(
  "$ROOT_DIR/interpreter/stack_safety_test.mbt"
  "$ROOT_DIR/interpreter/runtime/activation_dispatch_stack_safety_wbtest.mbt"
  "$ROOT_DIR/interpreter/runtime/execution_control_dispatch_wbtest.mbt"
  "$CONSUMER_SUITE"
)
for suite in "${selected_suites[@]}"; do
  [[ -f "$suite" ]] || fail "selected stack-safety suite is missing: ${suite#"$ROOT_DIR/"}"
  if grep -Eq '#skip|nested_comma_source\(512, "7"\)' "$suite"; then
    fail "selected stack-safety suite contains deferred #608 runtime coverage: ${suite#"$ROOT_DIR/"}"
  fi
done

for suite in \
  'interpreter/stack_safety_test.mbt' \
  'interpreter/runtime/activation_dispatch_stack_safety_wbtest.mbt' \
  'interpreter/runtime/execution_control_dispatch_wbtest.mbt'; do
  grep -Fq "$suite" "$MAKEFILE" ||
    fail "focused Make target omits the $suite suite"
done
grep -Fq '(cd integration/external_consumer' "$MAKEFILE" ||
  fail 'focused Make target omits the external-consumer suite'
grep -Fq 'moon test --target "$(TARGET)" $$release stack_safety_test.mbt' "$MAKEFILE" ||
  fail 'focused Make target does not select the external-consumer suite'

[[ -f "$DEFERRED_SUITE" ]] || fail 'deferred #608 suite is missing'
grep -Fq '#skip("blocked by #608 runtime evaluator stack safety")' "$DEFERRED_SUITE" ||
  fail 'deferred #608 suite no longer records its skip reason'
grep -Fq 'nested_comma_source(512, "7")' "$DEFERRED_SUITE" ||
  fail 'deferred #608 suite no longer records the deferred workload'
if grep -Fq 'stack_safety_deferred_test.mbt' "$MAKEFILE"; then
  fail 'deferred #608 suite was admitted to the focused Make target'
fi

grep -Fq 'import {' "$CONSUMER_PACKAGE" ||
  fail 'external-consumer package manifest is missing its facade import'
grep -Fq '"dowdiness/js_engine"' "$CONSUMER_PACKAGE" ||
  fail 'external-consumer package does not import the stable facade'

if grep -Eq 'NODE_OPTIONS|--stack-size|stack_size|stack-size' "$WORKFLOW" "$MAKEFILE"; then
  fail 'host stack-size override found in the permanent gate'
fi
if grep -Eq 'step\([^)]*,|nested_comma_source\(512, "7"\)' "$CONSUMER_SUITE"; then
  fail 'deferred #608 runtime workload was admitted to the public gate'
fi

if [[ "$CHECK_ONLY" == true ]]; then
  echo 'stack-safety gate validation: ok'
  exit 0
fi

GATE_TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$GATE_TMP_ROOT"' EXIT

# Regression: a failing engine suite must fail the Make target even if the
# external-consumer commands return success.
fake_moon_dir="$GATE_TMP_ROOT/fake-moon"
mkdir -p "$fake_moon_dir"
fake_moon="$fake_moon_dir/moon"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'for arg in "$@"; do' \
  '  if [[ "$arg" == "interpreter/stack_safety_test.mbt" ]]; then' \
  '    exit 42' \
  '  fi' \
  'done' \
  'exit 0' > "$fake_moon"
chmod +x "$fake_moon"
if PATH="$fake_moon_dir:$PATH" make -s -C "$ROOT_DIR" stack-safety-test TARGET=native PROFILE=debug >/dev/null 2>&1; then
  fail 'Make target masked an engine-suite failure with external-consumer success'
fi

copy_fixture() {
  local fixture=$1
  mkdir -p \
    "$fixture/.github/workflows" \
    "$fixture/interpreter/runtime" \
    "$fixture/integration/external_consumer"
  cp "$MAKEFILE" "$fixture/Makefile"
  cp "$WORKFLOW" "$fixture/.github/workflows/adoption.yml"
  cp "$CONSUMER_PACKAGE" "$fixture/integration/external_consumer/moon.pkg"
  cp "$CONSUMER_SUITE" "$fixture/integration/external_consumer/stack_safety_test.mbt"
  cp "$ROOT_DIR/interpreter/stack_safety_test.mbt" "$fixture/interpreter/stack_safety_test.mbt"
  cp \
    "$ROOT_DIR/interpreter/runtime/activation_dispatch_stack_safety_wbtest.mbt" \
    "$fixture/interpreter/runtime/activation_dispatch_stack_safety_wbtest.mbt"
  cp \
    "$ROOT_DIR/interpreter/runtime/execution_control_dispatch_wbtest.mbt" \
    "$fixture/interpreter/runtime/execution_control_dispatch_wbtest.mbt"
  cp "$DEFERRED_SUITE" "$fixture/interpreter/stack_safety_deferred_test.mbt"
}

expect_fixture_failure() {
  local fixture=$1
  local mutation=$2
  if STACK_SAFETY_GATE_ROOT="$fixture" "$SCRIPT_PATH" --check-only >/dev/null 2>&1; then
    fail "validator accepted $mutation stack-safety matrix mutation"
  fi
}

# Regression fixtures: check-only validation must reject a missing pair, a
# duplicate pair, and a decoy pair while accepting the unmodified matrix.
fixture="$GATE_TMP_ROOT/missing-pair"
copy_fixture "$fixture"
awk '
  /^  stack-safety:/ { in_stack=1 }
  in_stack && !removed && $0 == "          - target: wasm-gc" { removed=1; skip_profile=1; next }
  in_stack && skip_profile && $0 == "            profile: debug" { skip_profile=0; next }
  { print }
' "$fixture/.github/workflows/adoption.yml" > "$fixture/adoption.yml.tmp"
mv "$fixture/adoption.yml.tmp" "$fixture/.github/workflows/adoption.yml"
expect_fixture_failure "$fixture" 'missing-pair'

fixture="$GATE_TMP_ROOT/duplicate-pair"
copy_fixture "$fixture"
awk '
  /^  stack-safety:/ { in_stack=1 }
  in_stack && !inserted && $0 == "            profile: debug" {
    print
    print "          - target: native"
    print "            profile: debug"
    inserted=1
    next
  }
  { print }
' "$fixture/.github/workflows/adoption.yml" > "$fixture/adoption.yml.tmp"
mv "$fixture/adoption.yml.tmp" "$fixture/.github/workflows/adoption.yml"
expect_fixture_failure "$fixture" 'duplicate-pair'

fixture="$GATE_TMP_ROOT/decoy-pair"
copy_fixture "$fixture"
awk '
  /^  stack-safety:/ { in_stack=1 }
  in_stack && !mutated && $0 == "          - target: wasm-gc" {
    print "          - target: decoy"
    mutated=1
    next
  }
  { print }
' "$fixture/.github/workflows/adoption.yml" > "$fixture/adoption.yml.tmp"
mv "$fixture/adoption.yml.tmp" "$fixture/.github/workflows/adoption.yml"
expect_fixture_failure "$fixture" 'decoy-pair'

echo 'stack-safety gate validation: ok'
