#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=${1:-"$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"}
ROOT_MOD="$REPO_ROOT/moon.mod"
CONSUMER_MOD="$REPO_ROOT/integration/external_consumer/moon.mod"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

VERSION=$(sed -nE 's/^version = "([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "$ROOT_MOD")
if [[ $(printf '%s\n' "$VERSION" | sed '/^$/d' | wc -l) -ne 1 ]]; then
  echo "expected exactly one release version in $ROOT_MOD" >&2
  exit 1
fi

DEPENDENCY="\"dowdiness/js_engine@$VERSION\","
if [[ $(grep -Ec "^[[:space:]]*$DEPENDENCY$" "$CONSUMER_MOD") -ne 1 ]]; then
  echo "expected $CONSUMER_MOD to depend on js_engine@$VERSION" >&2
  exit 1
fi

if ! grep -Eq "^## \[$VERSION\]" "$CHANGELOG"; then
  echo "expected $CHANGELOG to contain a ## [$VERSION] heading" >&2
  exit 1
fi
