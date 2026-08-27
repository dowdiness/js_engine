#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/jetstream3-source-test.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT
trap 'exit 1' HUP INT TERM

make_source_repository() {
  local source_root="$1"
  local include_workload="$2"
  mkdir -p "$source_root/utils" "$source_root/Octane"
  printf '// cli fixture\n' >"$source_root/cli.js"
  printf '// driver fixture\n' >"$source_root/JetStreamDriver.js"
  printf '// shell config fixture\n' >"$source_root/utils/shell-config.js"
  printf '// params fixture\n' >"$source_root/utils/params.js"
  printf 'fixture license\n' >"$source_root/LICENSE"
  if [[ "$include_workload" == "yes" ]]; then
    printf '// raytrace fixture\n' >"$source_root/Octane/raytrace.js"
  fi
  git -C "$source_root" init --quiet
  git -C "$source_root" add .
  git -C "$source_root" \
    -c user.name=fixture \
    -c user.email=fixture@example.invalid \
    commit --quiet -m fixture
  git -C "$source_root" rev-parse HEAD
}

complete_source="$tmp_root/complete-source"
mkdir -p "$complete_source"
complete_commit="$(make_source_repository "$complete_source" yes)"
complete_cache="$tmp_root/complete-cache"

make --no-print-directory -C "$repo_root" jetstream3-source \
  JETSTREAM3_REPOSITORY="file://$complete_source" \
  JETSTREAM3_COMMIT="$complete_commit" \
  JETSTREAM3_DIR="$complete_cache"

test "$(git -C "$complete_cache" rev-parse HEAD)" = "$complete_commit"
test -f "$complete_cache/cli.js"
test -f "$complete_cache/JetStreamDriver.js"
test -f "$complete_cache/utils/shell-config.js"
test -f "$complete_cache/utils/params.js"
test -f "$complete_cache/Octane/raytrace.js"
test -f "$complete_cache/LICENSE"

make --no-print-directory -C "$repo_root" jetstream3-source \
  JETSTREAM3_REPOSITORY="file://$tmp_root/does-not-exist" \
  JETSTREAM3_COMMIT="$complete_commit" \
  JETSTREAM3_DIR="$complete_cache"

partial_source="$tmp_root/partial-source"
mkdir -p "$partial_source"
partial_commit="$(make_source_repository "$partial_source" no)"
partial_cache="$tmp_root/partial-cache"

if make --no-print-directory -C "$repo_root" jetstream3-source \
  JETSTREAM3_REPOSITORY="file://$partial_source" \
  JETSTREAM3_COMMIT="$partial_commit" \
  JETSTREAM3_DIR="$partial_cache"; then
  echo "incomplete JetStream source unexpectedly succeeded" >&2
  exit 1
fi

if [[ -e "$partial_cache" ]]; then
  echo "incomplete JetStream source was published to the cache" >&2
  exit 1
fi

echo "JetStream 3 source tests passed"
