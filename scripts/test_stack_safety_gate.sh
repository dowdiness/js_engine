#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MAKEFILE="$ROOT_DIR/Makefile"
WORKFLOW="$ROOT_DIR/.github/workflows/adoption.yml"
CONSUMER="$ROOT_DIR/integration/external_consumer/stack_safety_test.mbt"

fail() {
  echo "stack-safety gate validation: $1" >&2
  exit 1
}

grep -Fq 'stack-safety-test' "$MAKEFILE" ||
  fail 'focused stack-safety Make target is missing'
grep -Fq 'PROFILE' "$MAKEFILE" ||
  fail 'focused stack-safety Make target lacks profile selection'
grep -Fq 'stack-safety:' "$WORKFLOW" ||
  fail 'focused stack-safety workflow job is missing'
for target in native js wasm wasm-gc; do
  grep -Fq "target: $target" "$WORKFLOW" ||
    fail "workflow matrix is missing target $target"
done
for profile in debug release; do
  grep -Fq "profile: $profile" "$WORKFLOW" ||
    fail "workflow matrix is missing profile $profile"
done
grep -Fq 'make stack-safety-test' "$WORKFLOW" ||
  fail 'workflow does not invoke the focused Make target'
grep -Fq 'interpreter/stack_safety_test.mbt' "$MAKEFILE" ||
  fail 'focused Make target omits the interpreter stack-safety suite'
grep -Fq 'integration/external_consumer' "$MAKEFILE" ||
  fail 'focused Make target omits the external-consumer suite'
grep -Fq 'import {' "$ROOT_DIR/integration/external_consumer/moon.pkg" ||
  fail 'external-consumer package manifest is missing its facade import'
grep -Fq '"dowdiness/js_engine"' "$ROOT_DIR/integration/external_consumer/moon.pkg" ||
  fail 'external-consumer package imports more than the stable facade'

if grep -Eq 'NODE_OPTIONS|--stack-size|stack_size|stack-size' "$WORKFLOW" "$MAKEFILE"; then
  fail 'host stack-size override found in the permanent gate'
fi
if grep -Eq 'step\([^)]*,|nested_comma_source\(512, "7"\)' "$CONSUMER"; then
  fail 'deferred #608 runtime workload was admitted to the public gate'
fi

echo 'stack-safety gate validation: ok'
