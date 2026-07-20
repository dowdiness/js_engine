#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/integration/external_consumer"
cp "$ROOT_DIR/moon.mod" "$TEMP_DIR/moon.mod"
cp "$ROOT_DIR/CHANGELOG.md" "$TEMP_DIR/CHANGELOG.md"
cp "$ROOT_DIR/integration/external_consumer/moon.mod" \
  "$TEMP_DIR/integration/external_consumer/moon.mod"

"$ROOT_DIR/scripts/validate_release_metadata.sh" "$TEMP_DIR"

sed -i '/^## \[0\.6\.0\]/d' "$TEMP_DIR/CHANGELOG.md"
if "$ROOT_DIR/scripts/validate_release_metadata.sh" "$TEMP_DIR"; then
  echo 'expected a missing changelog heading to fail validation' >&2
  exit 1
fi
