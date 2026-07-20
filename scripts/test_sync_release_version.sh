#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/integration/external_consumer"
cp "$ROOT_DIR/moon.mod" "$TEMP_DIR/moon.mod"
cp "$ROOT_DIR/integration/external_consumer/moon.mod" \
  "$TEMP_DIR/integration/external_consumer/moon.mod"

TAGPR_NEXT_VERSION=v9.8.7 "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"

grep -Fx 'version = "0.6.0"' "$TEMP_DIR/moon.mod"
grep -Fx 'version = "0.1.0"' "$TEMP_DIR/integration/external_consumer/moon.mod"
grep -Fx '  "dowdiness/js_engine@9.8.7",' \
  "$TEMP_DIR/integration/external_consumer/moon.mod"

if TAGPR_NEXT_VERSION=9.8.7 "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"; then
  echo 'expected a v-prefixed release tag' >&2
  exit 1
fi
