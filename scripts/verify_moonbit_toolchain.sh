#!/usr/bin/env bash
set -euo pipefail

expected="${MOONBIT_EXPECTED_VERSION:?MOONBIT_EXPECTED_VERSION must be set}"
version_output="$(moon version 2>&1)"
actual="${version_output%%$'\n'*}"

if [[ "$actual" != "$expected" ]]; then
  printf 'MoonBit toolchain mismatch: expected %s, got %s\n' "$expected" "$actual" >&2
  exit 1
fi

printf 'MoonBit toolchain verified: %s\n' "$actual"
