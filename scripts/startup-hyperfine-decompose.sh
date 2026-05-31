#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/startup-hyperfine-decompose.sh [options]

Build the JS release CLI and run reporting-only Hyperfine probes that split
host startup, native host expression evaluation, js_engine bundle load, and
js_engine execution for a tiny source program.

Options:
  --warmup N          Hyperfine --warmup count (default: 10)
  --min-runs N        Hyperfine --min-runs count (default: 50)
  --source SRC        JavaScript source for expression probes (default: 1 + 1)
  --output-root DIR   Root for timestamped output dirs
                      (default: _build/startup-hyperfine-decompose)
  --timestamp NAME    Timestamp/output directory name override
                      (default: UTC YYYYMMDDTHHMMSSZ)
  --include-bun       Require Bun and include Bun host probes
  --no-bun            Skip Bun host probes even when Bun is on PATH
  --no-build          Skip moon build and use the existing release bundle
  -h, --help          Show this help

Environment defaults:
  STARTUP_HYPERFINE_WARMUP, STARTUP_HYPERFINE_MIN_RUNS, STARTUP_SOURCE,
  STARTUP_OUTPUT_ROOT, STARTUP_TIMESTAMP, STARTUP_BUN_MODE=auto|include|none
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

is_nonnegative_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

join_command() {
  python3 - "$@" <<'PY'
import shlex
import sys

print(shlex.join(sys.argv[1:]))
PY
}

expect_stdout() {
  local name=$1
  local expected=$2
  shift 2

  local stdout_file stderr_file output
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  if "$@" >"$stdout_file" 2>"$stderr_file"; then
    output=$(<"$stdout_file")
    if [[ "$output" != "$expected" ]]; then
      echo "error: $name produced unexpected stdout" >&2
      echo "expected: [$expected]" >&2
      echo "actual:   [$output]" >&2
      if [[ -s "$stderr_file" ]]; then
        echo "stderr:" >&2
        cat "$stderr_file" >&2
      fi
      rm -f "$stdout_file" "$stderr_file"
      exit 1
    fi
  else
    local status=$?
    echo "error: $name failed with exit status $status" >&2
    if [[ -s "$stdout_file" ]]; then
      echo "stdout:" >&2
      cat "$stdout_file" >&2
    fi
    if [[ -s "$stderr_file" ]]; then
      echo "stderr:" >&2
      cat "$stderr_file" >&2
    fi
    rm -f "$stdout_file" "$stderr_file"
    exit 1
  fi
  rm -f "$stdout_file" "$stderr_file"
}

expect_usage_output() {
  local name=$1
  shift

  local stdout_file stderr_file output
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  if "$@" >"$stdout_file" 2>"$stderr_file"; then
    output=$(<"$stdout_file")
    if [[ "$output" != Usage:* || "$output" != *$'\nExample:'* ]]; then
      echo "error: $name did not produce the expected usage text" >&2
      echo "actual stdout:" >&2
      cat "$stdout_file" >&2
      if [[ -s "$stderr_file" ]]; then
        echo "stderr:" >&2
        cat "$stderr_file" >&2
      fi
      rm -f "$stdout_file" "$stderr_file"
      exit 1
    fi
  else
    local status=$?
    echo "error: $name failed with exit status $status" >&2
    if [[ -s "$stdout_file" ]]; then
      echo "stdout:" >&2
      cat "$stdout_file" >&2
    fi
    if [[ -s "$stderr_file" ]]; then
      echo "stderr:" >&2
      cat "$stderr_file" >&2
    fi
    rm -f "$stdout_file" "$stderr_file"
    exit 1
  fi
  rm -f "$stdout_file" "$stderr_file"
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)

warmup=${STARTUP_HYPERFINE_WARMUP:-10}
min_runs=${STARTUP_HYPERFINE_MIN_RUNS:-50}
startup_source=${STARTUP_SOURCE:-"1 + 1"}
output_root=${STARTUP_OUTPUT_ROOT:-"_build/startup-hyperfine-decompose"}
timestamp=${STARTUP_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
bun_mode=${STARTUP_BUN_MODE:-auto}
do_build=1

while (($# > 0)); do
  case "$1" in
    --warmup)
      (($# >= 2)) || die "--warmup requires a value"
      warmup=$2
      shift 2
      ;;
    --warmup=*)
      warmup=${1#*=}
      shift
      ;;
    --min-runs)
      (($# >= 2)) || die "--min-runs requires a value"
      min_runs=$2
      shift 2
      ;;
    --min-runs=*)
      min_runs=${1#*=}
      shift
      ;;
    --source)
      (($# >= 2)) || die "--source requires a value"
      startup_source=$2
      shift 2
      ;;
    --source=*)
      startup_source=${1#*=}
      shift
      ;;
    --output-root)
      (($# >= 2)) || die "--output-root requires a value"
      output_root=$2
      shift 2
      ;;
    --output-root=*)
      output_root=${1#*=}
      shift
      ;;
    --timestamp)
      (($# >= 2)) || die "--timestamp requires a value"
      timestamp=$2
      shift 2
      ;;
    --timestamp=*)
      timestamp=${1#*=}
      shift
      ;;
    --include-bun)
      bun_mode=include
      shift
      ;;
    --no-bun)
      bun_mode=none
      shift
      ;;
    --no-build)
      do_build=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

is_nonnegative_int "$warmup" || die "--warmup must be a non-negative integer"
is_nonnegative_int "$min_runs" || die "--min-runs must be a positive integer"
((min_runs >= 1)) || die "--min-runs must be at least 1"
[[ -n "$timestamp" ]] || die "--timestamp must not be empty"

case "$bun_mode" in
  auto|include|none) ;;
  *) die "STARTUP_BUN_MODE must be one of: auto, include, none" ;;
esac

cd "$repo_root"

require_command moon
require_command node
require_command hyperfine
require_command python3

include_bun=0
case "$bun_mode" in
  include)
    require_command bun
    include_bun=1
    ;;
  auto)
    if command -v bun >/dev/null 2>&1; then
      include_bun=1
    fi
    ;;
  none)
    include_bun=0
    ;;
esac

js_engine_cli="_build/js/release/build/cmd/main/main.js"

if ((do_build)); then
  moon build cmd/main --target js --release
fi

[[ -f "$js_engine_cli" ]] || die "release JS CLI bundle not found: $js_engine_cli"

bundle_bytes=$(wc -c <"$js_engine_cli" | tr -d '[:space:]')
bundle_lines=$(wc -l <"$js_engine_cli" | tr -d '[:space:]')

# Capture source-tree state before creating output artifacts so custom
# non-ignored output directories do not make the run mark itself dirty.
git_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
git_dirty=false
if [[ -n "$(git status --porcelain --untracked-files=all 2>/dev/null)" ]]; then
  git_dirty=true
fi

expect_stdout "Node.js empty process" "" node -e ""
expect_stdout "Node.js native expression" "2" node -p "$startup_source"
if ((include_bun)); then
  expect_stdout "Bun empty process" "" bun -e ";"
  expect_stdout "Bun native expression" "2" bun -p "$startup_source"
fi
expect_usage_output "js_engine load/no-source" node "$js_engine_cli"
expect_stdout "js_engine CLI expression" "2" node "$js_engine_cli" "$startup_source"
if ((include_bun)); then
  expect_stdout "Bun-hosted js_engine CLI expression" "2" bun "$js_engine_cli" "$startup_source"
fi

declare -a command_names=()
declare -a command_strings=()

add_probe() {
  local name=$1
  shift
  command_names+=("$name")
  command_strings+=("$(join_command "$@")")
}

add_probe "Node.js empty process" node -e ""
add_probe "Node.js native expression" node -p "$startup_source"
if ((include_bun)); then
  add_probe "Bun empty process" bun -e ";"
  add_probe "Bun native expression" bun -p "$startup_source"
fi
add_probe "js_engine load/no-source" node "$js_engine_cli"
add_probe "js_engine CLI expression" node "$js_engine_cli" "$startup_source"
if ((include_bun)); then
  add_probe "Bun-hosted js_engine CLI expression" bun "$js_engine_cli" "$startup_source"
fi

if [[ "$output_root" != /* ]]; then
  output_root="$repo_root/$output_root"
fi
out_dir="$output_root/$timestamp"
mkdir -p "$output_root"
mkdir "$out_dir" || die "output directory already exists: $out_dir"

hyperfine_json="$out_dir/startup-hyperfine-decompose.json"
hyperfine_markdown="$out_dir/startup-hyperfine-decompose-table.md"
summary_markdown="$out_dir/startup-hyperfine-decompose-summary.md"
metadata_json="$out_dir/startup-hyperfine-decompose-metadata.json"
versions_file="$out_dir/startup-versions.txt"
commands_tsv="$out_dir/startup-hyperfine-decompose-commands.tsv"

{
  echo "MoonBit: $(moon version 2>&1 | head -1)"
  echo "Node.js: $(node --version)"
  if command -v bun >/dev/null 2>&1; then
    echo "Bun: $(bun --version)"
  else
    echo "Bun: not found"
  fi
  echo "Hyperfine: $(hyperfine --version)"
  echo "Python: $(python3 --version 2>&1)"
  echo "Kernel: $(uname -a)"
} >"$versions_file"

: >"$commands_tsv"
for i in "${!command_names[@]}"; do
  printf '%s\t%s\n' "${command_names[$i]}" "${command_strings[$i]}" >>"$commands_tsv"
done

hyperfine_args=(
  --warmup "$warmup"
  --min-runs "$min_runs"
  --export-json "$hyperfine_json"
  --export-markdown "$hyperfine_markdown"
)
for i in "${!command_names[@]}"; do
  hyperfine_args+=(--command-name "${command_names[$i]}" "${command_strings[$i]}")
done

hyperfine "${hyperfine_args[@]}"

created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

export STARTUP_REPO_ROOT="$repo_root"
export STARTUP_CREATED_AT="$created_at"
export STARTUP_OUT_DIR="$out_dir"
export STARTUP_SOURCE_VALUE="$startup_source"
export STARTUP_WARMUP="$warmup"
export STARTUP_MIN_RUNS="$min_runs"
export STARTUP_INCLUDE_BUN="$include_bun"
export STARTUP_BUNDLE_PATH="$js_engine_cli"
export STARTUP_BUNDLE_BYTES="$bundle_bytes"
export STARTUP_BUNDLE_LINES="$bundle_lines"
export STARTUP_GIT_COMMIT="$git_commit"
export STARTUP_GIT_DIRTY="$git_dirty"
export STARTUP_VERSIONS_FILE="$versions_file"
export STARTUP_COMMANDS_TSV="$commands_tsv"
export STARTUP_HYPERFINE_JSON="$hyperfine_json"
export STARTUP_HYPERFINE_MARKDOWN="$hyperfine_markdown"
export STARTUP_SUMMARY_MARKDOWN="$summary_markdown"
export STARTUP_METADATA_JSON="$metadata_json"

python3 - <<'PY'
import json
import os
from pathlib import Path

repo_root = Path(os.environ["STARTUP_REPO_ROOT"]).resolve()
out_dir = Path(os.environ["STARTUP_OUT_DIR"]).resolve()
versions_path = Path(os.environ["STARTUP_VERSIONS_FILE"]).resolve()
commands_path = Path(os.environ["STARTUP_COMMANDS_TSV"]).resolve()
hyperfine_json = Path(os.environ["STARTUP_HYPERFINE_JSON"]).resolve()
hyperfine_markdown = Path(os.environ["STARTUP_HYPERFINE_MARKDOWN"]).resolve()
summary_markdown = Path(os.environ["STARTUP_SUMMARY_MARKDOWN"]).resolve()
metadata_json = Path(os.environ["STARTUP_METADATA_JSON"]).resolve()


def display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(repo_root))
    except ValueError:
        return str(path)


def md_cell(text: str) -> str:
    return text.replace("\\", "\\\\").replace("|", "\\|").replace("\n", "<br>")


def md_code(text: str) -> str:
    return "`" + text.replace("`", "\\`") + "`"

commands = []
for line in commands_path.read_text().splitlines():
    if not line:
        continue
    name, command = line.split("\t", 1)
    commands.append({"name": name, "command": command})

versions = versions_path.read_text().strip()
table = hyperfine_markdown.read_text().strip()
include_bun = os.environ["STARTUP_INCLUDE_BUN"] == "1"
metadata = {
    "schema": "startup-hyperfine-decompose/v1",
    "created_at_utc": os.environ["STARTUP_CREATED_AT"],
    "git": {
        "commit": os.environ["STARTUP_GIT_COMMIT"],
        "dirty": os.environ["STARTUP_GIT_DIRTY"] == "true",
    },
    "settings": {
        "warmup": int(os.environ["STARTUP_WARMUP"]),
        "min_runs": int(os.environ["STARTUP_MIN_RUNS"]),
        "source": os.environ["STARTUP_SOURCE_VALUE"],
        "include_bun_probes": include_bun,
    },
    "bundle": {
        "path": os.environ["STARTUP_BUNDLE_PATH"],
        "byte_size": int(os.environ["STARTUP_BUNDLE_BYTES"]),
        "line_count": int(os.environ["STARTUP_BUNDLE_LINES"]),
    },
    "artifacts": {
        "output_dir": display_path(out_dir),
        "hyperfine_json": display_path(hyperfine_json),
        "hyperfine_markdown": display_path(hyperfine_markdown),
        "summary_markdown": display_path(summary_markdown),
        "metadata_json": display_path(metadata_json),
        "versions": display_path(versions_path),
        "commands": display_path(commands_path),
    },
    "commands": commands,
}
metadata_json.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")

command_rows = ["| Probe | Command |", "|---|---|"]
for item in commands:
    command_rows.append(
        f"| {md_cell(item['name'])} | {md_code(md_cell(item['command']))} |"
    )

notes = [
    "- Reporting-only helper: no thresholds, PR comments, or publishing are performed.",
    "- `js_engine load/no-source` runs the CLI without a source argument. It exercises bundle load and the CLI usage path, but it does not parse or execute JavaScript source.",
    "- `startup/tiny_program` remains the in-process dashboard guardrail; this helper measures process-level startup decomposition.",
]
if include_bun:
    notes.append("- Bun probes were included because Bun was requested or available on PATH.")
else:
    notes.append("- Bun probes were skipped; rerun with `--include-bun` after installing Bun to require them.")

summary = "\n".join(
    [
        "# Startup Hyperfine decomposition",
        "",
        "Lower is better. Results are for investigation and follow-up issue scoping only.",
        "",
        f"- Created: `{os.environ['STARTUP_CREATED_AT']}`",
        f"- Commit: `{os.environ['STARTUP_GIT_COMMIT']}`",
        f"- Dirty tree: `{os.environ['STARTUP_GIT_DIRTY']}`",
        f"- Output directory: `{display_path(out_dir)}`",
        f"- Probe source: `{os.environ['STARTUP_SOURCE_VALUE']}`",
        f"- Warmup runs: `{os.environ['STARTUP_WARMUP']}`",
        f"- Minimum measured runs: `{os.environ['STARTUP_MIN_RUNS']}`",
        f"- Bundle: `{os.environ['STARTUP_BUNDLE_PATH']}` "
        f"({int(os.environ['STARTUP_BUNDLE_BYTES']):,} bytes, "
        f"{int(os.environ['STARTUP_BUNDLE_LINES']):,} lines)",
        "",
        "## Tool versions",
        "",
        "```text",
        versions,
        "```",
        "",
        "## Probes",
        "",
        *command_rows,
        "",
        "## Results",
        "",
        table,
        "",
        "## Notes",
        "",
        *notes,
        "",
    ]
)
summary_markdown.write_text(summary)
PY

echo "Wrote startup decomposition artifacts to: $out_dir"
echo "Summary: $summary_markdown"
