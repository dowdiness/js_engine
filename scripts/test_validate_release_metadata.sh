#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
VERSION=$(sed -nE 's/^version = "([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' \
  "$ROOT_DIR/moon.mod")

mkdir -p "$TEMP_DIR/integration/external_consumer" "$TEMP_DIR/cmd/main"
cp "$ROOT_DIR/moon.mod" "$TEMP_DIR/moon.mod"
cp "$ROOT_DIR/CHANGELOG.md" "$TEMP_DIR/CHANGELOG.md"
cp "$ROOT_DIR/integration/external_consumer/moon.mod" \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
cp "$ROOT_DIR/cmd/main/main.mbt" "$TEMP_DIR/cmd/main/main.mbt"

"$ROOT_DIR/scripts/validate_release_metadata.sh" "$TEMP_DIR"

sed -i -E 's/version="[0-9]+\.[0-9]+\.[0-9]+"/version="0.0.0"/' \
  "$TEMP_DIR/cmd/main/main.mbt"
if "$ROOT_DIR/scripts/validate_release_metadata.sh" "$TEMP_DIR"; then
  echo 'expected a stale CLI version to fail validation' >&2
  exit 1
fi
cp "$ROOT_DIR/cmd/main/main.mbt" "$TEMP_DIR/cmd/main/main.mbt"

MALFORMED_VERSION=${VERSION//./x}
VERSION_PATTERN=${VERSION//./\\.}
sed -i "s|@${VERSION}|@${MALFORMED_VERSION}|" \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
if "$ROOT_DIR/scripts/validate_release_metadata.sh" "$TEMP_DIR"; then
  echo 'expected a malformed dependency version to fail validation' >&2
  exit 1
fi
cp "$ROOT_DIR/integration/external_consumer/moon.mod" \
  "$TEMP_DIR/integration/external_consumer/moon.mod"

sed -i -E \
  "s|^## \[$VERSION_PATTERN\]|## [$MALFORMED_VERSION]|" \
  "$TEMP_DIR/CHANGELOG.md"
if "$ROOT_DIR/scripts/validate_release_metadata.sh" "$TEMP_DIR"; then
  echo 'expected a malformed changelog version to fail validation' >&2
  exit 1
fi
cp "$ROOT_DIR/CHANGELOG.md" "$TEMP_DIR/CHANGELOG.md"

sed -i -E "/^## \[$VERSION_PATTERN\]/d" "$TEMP_DIR/CHANGELOG.md"
if "$ROOT_DIR/scripts/validate_release_metadata.sh" "$TEMP_DIR"; then
  echo 'expected a missing changelog heading to fail validation' >&2
  exit 1
fi
