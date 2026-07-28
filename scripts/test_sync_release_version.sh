#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
ROOT_VERSION_LINE=$(grep -E '^version = "[0-9]+\.[0-9]+\.[0-9]+"$' "$ROOT_DIR/moon.mod")
CONSUMER_VERSION_LINE=$(grep -E '^version = "[0-9]+\.[0-9]+\.[0-9]+"$' \
  "$ROOT_DIR/integration/external_consumer/moon.mod")

mkdir -p "$TEMP_DIR/integration/external_consumer" "$TEMP_DIR/cmd/main"
cp "$ROOT_DIR/moon.mod" "$TEMP_DIR/moon.mod"
cp "$ROOT_DIR/integration/external_consumer/moon.mod" \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
cp "$ROOT_DIR/cmd/main/main.mbt" "$TEMP_DIR/cmd/main/main.mbt"

TAGPR_NEXT_VERSION=v9.8.7 "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"

grep -Fx "$ROOT_VERSION_LINE" "$TEMP_DIR/moon.mod"
grep -Fx "$CONSUMER_VERSION_LINE" "$TEMP_DIR/integration/external_consumer/moon.mod"
grep -Fx '  "dowdiness/js_engine@9.8.7",' \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
grep -Fx '    version="9.8.7",' "$TEMP_DIR/cmd/main/main.mbt"

cp "$ROOT_DIR/cmd/main/main.mbt" "$TEMP_DIR/cmd/main/main.mbt"
printf '\n// version="1.2.3"\n' >> "$TEMP_DIR/cmd/main/main.mbt"
TAGPR_NEXT_VERSION=v9.8.7 "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"
grep -Fx '    version="9.8.7",' "$TEMP_DIR/cmd/main/main.mbt"
grep -Fx '// version="1.2.3"' "$TEMP_DIR/cmd/main/main.mbt"

cp "$ROOT_DIR/cmd/main/main.mbt" "$TEMP_DIR/cmd/main/main.mbt"
sed -i -E '/^[[:space:]]*version="[0-9]+\.[0-9]+\.[0-9]+",$/d' \
  "$TEMP_DIR/cmd/main/main.mbt"
if TAGPR_NEXT_VERSION=v9.8.7 \
  "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"; then
  echo 'expected a missing CLI version to fail synchronization' >&2
  exit 1
fi

cp "$ROOT_DIR/cmd/main/main.mbt" "$TEMP_DIR/cmd/main/main.mbt"
printf '\n    version="1.2.3",\n' >> "$TEMP_DIR/cmd/main/main.mbt"
if TAGPR_NEXT_VERSION=v9.8.7 \
  "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"; then
  echo 'expected multiple CLI versions to fail synchronization' >&2
  exit 1
fi

cp "$ROOT_DIR/cmd/main/main.mbt" "$TEMP_DIR/cmd/main/main.mbt"
cp "$ROOT_DIR/integration/external_consumer/moon.mod" \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
printf '\n// "dowdiness/js_engine@1.2.3",\n' >> \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
TAGPR_NEXT_VERSION=v9.8.7 "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"
grep -Fx '  "dowdiness/js_engine@9.8.7",' \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
grep -Fx '// "dowdiness/js_engine@1.2.3",' \
  "$TEMP_DIR/integration/external_consumer/moon.mod"

cp "$ROOT_DIR/integration/external_consumer/moon.mod" \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
sed -i -E \
  '/^[[:space:]]*"dowdiness\/js_engine@[0-9]+\.[0-9]+\.[0-9]+",$/d' \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
if TAGPR_NEXT_VERSION=v9.8.7 \
  "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"; then
  echo 'expected a missing js_engine dependency to fail synchronization' >&2
  exit 1
fi

cp "$ROOT_DIR/integration/external_consumer/moon.mod" \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
printf '\n  "dowdiness/js_engine@1.2.3",\n' >> \
  "$TEMP_DIR/integration/external_consumer/moon.mod"
if TAGPR_NEXT_VERSION=v9.8.7 \
  "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"; then
  echo 'expected multiple js_engine dependencies to fail synchronization' >&2
  exit 1
fi

if TAGPR_NEXT_VERSION=9.8.7 "$ROOT_DIR/scripts/sync_release_version.sh" "$TEMP_DIR"; then
  echo 'expected a v-prefixed release tag' >&2
  exit 1
fi
