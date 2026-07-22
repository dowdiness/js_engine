#!/usr/bin/env bash

set -euo pipefail

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/compat-table-download-test.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT
trap 'exit 1' HUP INT TERM

complete_source="$tmp_root/complete-source/compat-table-fixture"
mkdir -p "$complete_source/test-utils"
printf '{}\n' > "$complete_source/data-common.json"
printf 'exports.name = "ES5"; exports.tests = [];\n' > "$complete_source/data-es5.js"
printf 'exports.name = "ES6"; exports.tests = [];\n' > "$complete_source/data-es6.js"
printf 'exports.name = "ES2016+"; exports.tests = [];\n' > "$complete_source/data-es2016plus.js"
printf 'exports.createIterableHelper = "";\n' > "$complete_source/test-utils/testHelpers.js"
printf 'fixture license\n' > "$complete_source/LICENSE"
tar -czf "$tmp_root/complete.tar.gz" -C "$tmp_root/complete-source" compat-table-fixture

complete_cache="$tmp_root/complete-cache"
make --no-print-directory compat-table-download \
  COMPAT_TABLE_COMMIT=fixture-complete \
  COMPAT_TABLE_DIR="$complete_cache" \
  COMPAT_TABLE_ARCHIVE_URL="file://$tmp_root/complete.tar.gz"

test -f "$complete_cache/.complete"
test -f "$complete_cache/data-es5.js"
test -f "$complete_cache/data-es6.js"
test -f "$complete_cache/data-es2016plus.js"
test -f "$complete_cache/data-common.json"
test -f "$complete_cache/test-utils/testHelpers.js"

make --no-print-directory compat-table-download \
  COMPAT_TABLE_COMMIT=fixture-complete \
  COMPAT_TABLE_DIR="$complete_cache" \
  COMPAT_TABLE_ARCHIVE_URL="file://$tmp_root/does-not-exist.tar.gz"

partial_source="$tmp_root/partial-source/compat-table-fixture"
mkdir -p "$partial_source"
printf 'exports.name = "ES2016+"; exports.tests = [];\n' > "$partial_source/data-es2016plus.js"
tar -czf "$tmp_root/partial.tar.gz" -C "$tmp_root/partial-source" compat-table-fixture

partial_cache="$tmp_root/partial-cache"
if make --no-print-directory compat-table-download \
  COMPAT_TABLE_COMMIT=fixture-partial \
  COMPAT_TABLE_DIR="$partial_cache" \
  COMPAT_TABLE_ARCHIVE_URL="file://$tmp_root/partial.tar.gz"; then
  echo "partial compat-table archive unexpectedly succeeded" >&2
  exit 1
fi

if [ -e "$partial_cache" ]; then
  echo "partial compat-table archive was published to the cache" >&2
  exit 1
fi

echo "compat-table download tests passed"
