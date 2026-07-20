#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
ROOT_VERSION_LINE=$(grep -E '^version = "[0-9]+\.[0-9]+\.[0-9]+"$' "$ROOT_DIR/moon.mod")
CONSUMER_VERSION_LINE=$(grep -E '^version = "[0-9]+\.[0-9]+\.[0-9]+"$' \
  "$ROOT_DIR/integration/external_consumer/moon.mod")

mkdir -p "$TEMP_DIR/integration/external_consumer"
cp "$ROOT_DIR/moon.mod" "$TEMP_DIR/moon.mod"
cp "$ROOT_DIR/integration/external_consumer/moon.mod" \
  "$TEMP_DIR/integration/external_consumer/moon.mod"

TAGPR_NEXT_VERSION=v9.8.7 "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"

grep -Fx "$ROOT_VERSION_LINE" "$TEMP_DIR/moon.mod"
grep -Fx "$CONSUMER_VERSION_LINE" "$TEMP_DIR/integration/external_consumer/moon.mod"
grep -Fx '  "dowdiness/js_engine@9.8.7",' \
  "$TEMP_DIR/integration/external_consumer/moon.mod"

if TAGPR_NEXT_VERSION=9.8.7 "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"; then
  echo 'expected a v-prefixed release tag' >&2
  exit 1
fi
