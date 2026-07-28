#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
artifact_dir="$script_dir/artifacts"
viewer_mode="${1:-interactive}"

if [[ "$viewer_mode" != "interactive" && "$viewer_mode" != "--scripted-viewer" ]]; then
  echo "usage: $0 [--scripted-viewer]" >&2
  exit 2
fi

if command -v moon >/dev/null 2>&1; then
  moon_bin="$(command -v moon)"
elif [[ -x /home/antisatori/.moon/bin/moon ]]; then
  moon_bin=/home/antisatori/.moon/bin/moon
else
  echo "moon executable not found" >&2
  exit 1
fi

mkdir -p "$artifact_dir"

echo "PROTOTYPE: checking standalone coroutine module"
(cd "$script_dir" && "$moon_bin" check --deny-warn)

for target in native js wasm wasm-gc; do
  echo "PROTOTYPE: running deterministic $target probe"
  (cd "$script_dir" && "$moon_bin" run cmd/probe --target "$target" --quiet) \
    > "$artifact_dir/$target.jsonl"
done

for target in js wasm wasm-gc; do
  if ! cmp -s "$artifact_dir/native.jsonl" "$artifact_dir/$target.jsonl"; then
    echo "PROTOTYPE: transcript mismatch: native vs $target" >&2
    diff -u "$artifact_dir/native.jsonl" "$artifact_dir/$target.jsonl" || true
    exit 1
  fi
done

(
  cd "$artifact_dir"
  sha256sum native.jsonl js.jsonl wasm.jsonl wasm-gc.jsonl \
    > transcript-sha256.txt
)
printf '%s\n' \
  'PROTOTYPE parity: native == js == wasm == wasm-gc (byte-for-byte)' \
  > "$artifact_dir/parity.txt"

echo "PROTOTYPE: four-target transcripts are byte-identical"
echo "PROTOTYPE: launching native inactive-user state viewer"
if [[ "$viewer_mode" == "--scripted-viewer" ]]; then
  printf 'start\nread-inactive\nwrite-ok\nresume-again\nquit\n' \
    | (cd "$script_dir" && "$moon_bin" run cmd/viewer --target native --quiet) \
    | tee "$artifact_dir/inactive-user-walkthrough.txt"
elif [[ "$viewer_mode" == "interactive" ]]; then
  (cd "$script_dir" && "$moon_bin" run cmd/viewer --target native --quiet) \
    | tee "$artifact_dir/inactive-user-walkthrough.txt"
fi
