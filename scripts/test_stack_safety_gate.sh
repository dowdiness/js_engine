#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
ROOT_DIR=${STACK_SAFETY_GATE_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
MAKEFILE="$ROOT_DIR/Makefile"
WORKFLOW="$ROOT_DIR/.github/workflows/adoption.yml"
DEVELOPMENT_DOC="$ROOT_DIR/docs/development.md"
CONSUMER_PACKAGE="$ROOT_DIR/integration/external_consumer/moon.pkg"
CONSUMER_SUITE="$ROOT_DIR/integration/external_consumer/stack_safety_test.mbt"
BOUNDED_SUITE="$ROOT_DIR/integration/external_consumer/bounded_eval_test.mbt"
ACTIVATION_SUITE="$ROOT_DIR/interpreter/runtime/activation_dispatch_numeric_activation_wbtest.mbt"
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
[[ -f "$DEVELOPMENT_DOC" ]] || fail 'development documentation is missing'
[[ -f "$CONSUMER_PACKAGE" ]] || fail 'external-consumer package manifest is missing'
[[ -f "$CONSUMER_SUITE" ]] || fail 'external-consumer stack-safety suite is missing'
[[ -f "$BOUNDED_SUITE" ]] || fail 'bounded external-consumer suite is missing'
[[ -f "$ACTIVATION_SUITE" ]] || fail 'numeric activation cleanup suite is missing'

grep -Fq 'stack-safety-test' "$MAKEFILE" ||
  fail 'focused stack-safety Make target is missing'
grep -Fq 'PROFILE' "$MAKEFILE" ||
  fail 'focused stack-safety Make target lacks profile selection'
grep -Fq '$(origin TARGET)' "$MAKEFILE" ||
  fail 'focused Make target does not require a command-line TARGET'
grep -Fq '$(origin PROFILE)' "$MAKEFILE" ||
  fail 'focused Make target does not require a command-line PROFILE'
grep -Fq 'native|js|wasm|wasm-gc' "$MAKEFILE" ||
  fail 'focused Make target does not validate the four supported targets'
grep -Fq 'PROFILE must be debug or release' "$MAKEFILE" ||
  fail 'focused Make target does not validate debug/release profiles'
grep -Fq 'stack-safety:' "$WORKFLOW" ||
  fail 'focused stack-safety workflow job is missing'
grep -Eq 'run: make stack-safety-test TARGET=.*PROFILE=' "$WORKFLOW" ||
  fail 'workflow does not invoke the focused Make target with its matrix profile'
aggregator_count=$(grep -c '^  stack-safety-required:$' "$WORKFLOW" || true)
[[ "$aggregator_count" -eq 1 ]] ||
  fail 'workflow must define exactly one stack-safety-required job'
aggregator_block=$(awk '
  /^  stack-safety-required:/ { in_aggregator=1; next }
  in_aggregator && /^  [^ ]/ { exit }
  in_aggregator { print }
' "$WORKFLOW")
[[ -n "$aggregator_block" ]] ||
  fail 'stack-safety-required job body is missing'
if ! grep -Fq '    name: stack-safety-required' <<<"$aggregator_block"; then
  fail 'stack-safety-required must expose its stable check name'
fi
if ! grep -Fq '    needs: [stack-safety]' <<<"$aggregator_block"; then
  fail 'stack-safety-required must need the stack-safety matrix job'
fi
if ! grep -Fq '    if: always()' <<<"$aggregator_block"; then
  fail 'stack-safety-required must run with if: always()'
fi
if ! grep -Fq '          STACK_SAFETY_RESULT: ${{ needs.stack-safety.result }}' <<<"$aggregator_block"; then
  fail 'stack-safety-required does not expose needs.stack-safety.result to its shell'
fi
if ! grep -Fq 'test "$STACK_SAFETY_RESULT" = success' <<<"$aggregator_block"; then
  fail 'stack-safety-required does not fail closed on non-success results'
fi
grep -Fq 'make stack-safety-test TARGET=<native|js|wasm|wasm-gc> PROFILE=<debug|release>' "$DEVELOPMENT_DOC" ||
  fail 'development documentation omits the exact stack-safety command syntax'
if grep -Fq '`PROFILE=debug` is the default' "$DEVELOPMENT_DOC"; then
  fail 'development documentation still claims a stack-safety profile default'
fi

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
  "$ACTIVATION_SUITE"
  "$ROOT_DIR/interpreter/runtime/execution_control_dispatch_wbtest.mbt"
  "$CONSUMER_SUITE"
  "$BOUNDED_SUITE"
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
  'interpreter/runtime/activation_dispatch_numeric_activation_wbtest.mbt' \
  'interpreter/runtime/execution_control_dispatch_wbtest.mbt'; do
  grep -Fq "$suite" "$MAKEFILE" ||
    fail "focused Make target omits the $suite suite"
done
grep -Fq '(cd integration/external_consumer' "$MAKEFILE" ||
  fail 'focused Make target omits the external-consumer suite'
grep -Fq 'moon test --target "$(TARGET)" $$release stack_safety_test.mbt bounded_eval_test.mbt' "$MAKEFILE" ||
  fail 'focused Make target does not select both external-consumer suites'

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

# Contract regressions: missing and unknown command-line values must be
# rejected before the first MoonBit invocation.
contract_moon_dir="$GATE_TMP_ROOT/contract-moon"
mkdir -p "$contract_moon_dir"
contract_moon="$contract_moon_dir/moon"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf invoked > "$MOON_MARKER"' \
  'exit 0' > "$contract_moon"
chmod +x "$contract_moon"
expect_rejected_without_moon() {
  local label=$1
  shift
  local marker="$GATE_TMP_ROOT/$label.moon-invoked"
  if MOON_MARKER="$marker" PATH="$contract_moon_dir:$PATH" \
    make -s -C "$ROOT_DIR" stack-safety-test "$@" >/dev/null 2>&1; then
    fail "Make target accepted invalid $label contract input"
  fi
  if [[ -e "$marker" ]]; then
    fail "Make target invoked MoonBit for invalid $label contract input"
  fi
}
expect_rejected_without_moon missing-target PROFILE=debug
expect_rejected_without_moon missing-profile TARGET=native
expect_rejected_without_moon unknown-target TARGET=decoy PROFILE=debug
expect_rejected_without_moon unknown-profile TARGET=native PROFILE=profiling

copy_fixture() {
  local fixture=$1
  mkdir -p \
    "$fixture/.github/workflows" \
    "$fixture/docs" \
    "$fixture/interpreter/runtime" \
    "$fixture/integration/external_consumer"
  cp "$MAKEFILE" "$fixture/Makefile"
  cp "$WORKFLOW" "$fixture/.github/workflows/adoption.yml"
  cp "$DEVELOPMENT_DOC" "$fixture/docs/development.md"
  cp "$CONSUMER_PACKAGE" "$fixture/integration/external_consumer/moon.pkg"
  cp "$CONSUMER_SUITE" "$fixture/integration/external_consumer/stack_safety_test.mbt"
  cp "$BOUNDED_SUITE" "$fixture/integration/external_consumer/bounded_eval_test.mbt"
  cp "$ROOT_DIR/interpreter/stack_safety_test.mbt" "$fixture/interpreter/stack_safety_test.mbt"
  cp \
    "$ROOT_DIR/interpreter/runtime/activation_dispatch_stack_safety_wbtest.mbt" \
    "$fixture/interpreter/runtime/activation_dispatch_stack_safety_wbtest.mbt"
  cp "$ACTIVATION_SUITE" "$fixture/interpreter/runtime/activation_dispatch_numeric_activation_wbtest.mbt"
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

fixture="$GATE_TMP_ROOT/missing-aggregator"
copy_fixture "$fixture"
awk '
  /^  stack-safety-required:/ { in_aggregator=1; next }
  in_aggregator && /^  [^ ]/ { in_aggregator=0 }
  !in_aggregator { print }
' "$fixture/.github/workflows/adoption.yml" > "$fixture/adoption.yml.tmp"
mv "$fixture/adoption.yml.tmp" "$fixture/.github/workflows/adoption.yml"
expect_fixture_failure "$fixture" 'missing-aggregator'

fixture="$GATE_TMP_ROOT/weak-aggregator"
copy_fixture "$fixture"
awk '
  /^  stack-safety-required:/ { in_aggregator=1 }
  in_aggregator && $0 == "    if: always()" {
    print "    if: success()"
    next
  }
  { print }
' "$fixture/.github/workflows/adoption.yml" > "$fixture/adoption.yml.tmp"
mv "$fixture/adoption.yml.tmp" "$fixture/.github/workflows/adoption.yml"
expect_fixture_failure "$fixture" 'weak-aggregator'

fixture="$GATE_TMP_ROOT/missing-bounded-suite"
copy_fixture "$fixture"
sed -i 's/ stack_safety_test.mbt bounded_eval_test.mbt/ stack_safety_test.mbt/' "$fixture/Makefile"
expect_fixture_failure "$fixture" 'missing-bounded-suite'

fixture="$GATE_TMP_ROOT/missing-activation-suite"
copy_fixture "$fixture"
sed -i '/activation_dispatch_numeric_activation_wbtest.mbt/d' "$fixture/Makefile"
expect_fixture_failure "$fixture" 'missing-activation-suite'

echo 'stack-safety gate validation: ok'
