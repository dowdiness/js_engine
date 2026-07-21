#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=${1:-"$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"}
TAG=${TAGPR_NEXT_VERSION:?TAGPR_NEXT_VERSION must be set by tagpr}

if [[ ! $TAG =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "expected TAGPR_NEXT_VERSION to be a v-prefixed SemVer tag, got: $TAG" >&2
  exit 1
fi

VERSION=${TAG#v}
CONSUMER_MOD="$REPO_ROOT/integration/external_consumer/moon.mod"
DEPENDENCY_PATTERN='"dowdiness/js_engine@[0-9]+\.[0-9]+\.[0-9]+",'

if [[ $(grep -Ec "$DEPENDENCY_PATTERN" "$CONSUMER_MOD") -ne 1 ]]; then
  echo "expected exactly one js_engine dependency in $CONSUMER_MOD" >&2
  exit 1
fi

sed -i -E \
  "s|(\"dowdiness/js_engine@)[0-9]+\.[0-9]+\.[0-9]+(\",)|\\1$VERSION\\2|" \
  "$CONSUMER_MOD"
