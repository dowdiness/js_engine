#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=${1:-"$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"}
ROOT_MOD="$REPO_ROOT/moon.mod"
CONSUMER_MOD="$REPO_ROOT/integration/external_consumer/moon.mod"
CLI_MAIN="$REPO_ROOT/cmd/main/main.mbt"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

VERSION=$(sed -nE 's/^version = "([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "$ROOT_MOD")
if [[ $(printf '%s\n' "$VERSION" | sed '/^$/d' | wc -l) -ne 1 ]]; then
  echo "expected exactly one release version in $ROOT_MOD" >&2
  exit 1
fi
CLI_VERSION=$(sed -nE \
  's/^[[:space:]]*version="([0-9]+\.[0-9]+\.[0-9]+)",$/\1/p' \
  "$CLI_MAIN")
if [[ $(printf '%s\n' "$CLI_VERSION" | sed '/^$/d' | wc -l) -ne 1 ]]; then
  echo "expected exactly one CLI version in $CLI_MAIN" >&2
  exit 1
fi
if [[ $CLI_VERSION != "$VERSION" ]]; then
  echo "expected $CLI_MAIN version $CLI_VERSION to match release $VERSION" >&2
  exit 1
fi

DEPENDENCY="\"dowdiness/js_engine@$VERSION\","
VERSION_PATTERN=${VERSION//./\\.}
DEPENDENCY_PATTERN="\"dowdiness/js_engine@$VERSION_PATTERN\","
if [[ $(grep -Ec "^[[:space:]]*$DEPENDENCY_PATTERN$" "$CONSUMER_MOD") -ne 1 ]]; then
  echo "expected $CONSUMER_MOD to depend on js_engine@$VERSION" >&2
  exit 1
fi

if ! grep -Eq "^## \[$VERSION_PATTERN\]" "$CHANGELOG"; then
  echo "expected $CHANGELOG to contain a ## [$VERSION] heading" >&2
  exit 1
fi
