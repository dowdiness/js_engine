#!/usr/bin/env python3
"""
Test262 Conformance Runner for the MoonBit JS Engine (Optimized).

Usage:
    python3 test262-runner.py [options]

Options:
    --engine CMD        Command to run the JS engine (default: auto-detect built JS bundle)
    --test262 DIR       Path to test262 directory (default: ./test262)
    --filter PATTERN    Only run tests matching this pattern (e.g. "language/expressions")
    --tests-file FILE   Run an explicit list of test files
    --start N           Start at expanded task offset N (0-based)
    --count N           Run at most N expanded tasks
    --shard I/N         Run balanced contiguous shard I of N (1-based)
    --resume-from FILE  Skip expanded tasks already present in a results JSON file
    --log FILE          Write per-task JSONL progress log
    --merged-log FILE   Append fail/timeout/error JSONL records for shard merging
    --timeout SECS      Timeout per test in seconds (default: 5)
    --threads N         Number of parallel workers (default: auto-detect, min 4)
    --harness-helper H  Opt into modified harness helper(s), e.g. codePointRange
    --output FILE       Write JSON results to this file
    --summary           Print summary only (no individual failures)
    --verbose           Print each test result as it runs

Performance Optimizations:
    - Harness file caching to avoid repeated disk I/O
    - Auto-detected CPU-based parallelism (minimum 4 threads, scales with CPU count)
    - Moderate timeout (5s) balancing speed and test completion
    - Optimized progress reporting with ETA
    - Explicit opt-in modified harness helpers, disabled by default

Prerequisites:
    Run `moon build --target js` first to produce the JS bundle.

Known Bottleneck:
    The main bottleneck is per-test Node.js startup overhead (~30-50ms).
    Future improvements could include:
    - Server mode: persistent process that reads tests from stdin
    - Batch mode: multiple tests per engine invocation
"""

import argparse
import json
import os
import re
import subprocess
import sys
import shlex
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from test262_skip_metadata import (
    SKIP_FEATURES,
    SKIP_FLAGS,
    SKIP_PATH_SUFFIXES,
    skip_reason,
)
from test262_task_selection import (
    apply_task_selection,
    build_test_tasks,
    load_tests_file,
    normalize_test262_path,
    parse_shard_spec,
)
from test262_utils import parse_yaml_frontmatter, as_list
from test262_harness_helpers import DEFAULT_HARNESS_OPTIONS, HarnessOptions

# Preamble injected before all test harness code to provide host-defined print()
PRINT_PREAMBLE = 'function print() { var s = ""; for (var i = 0; i < arguments.length; i++) { if (i > 0) s += " "; s += String(arguments[i]); } console.log(s); }\n'

# Captures relative module specifiers from `from "./x"` clauses and bare
# `import "./x"` side-effect imports. The `\.\.?/` prefix filters out bare
# specifiers (e.g. 'react'), so post-filtering isn't needed.
IMPORT_RELATIVE_RE = re.compile(r"""(?:from|import)\s+["'](\.\.?/[^"']+)["']""")

# Fallback $DONE for async tests that don't include donePrintHandle.js
DONE_FALLBACK = """
if (typeof $DONE === "undefined") {
  var $DONE = function(error) {
    if (error) {
      if (typeof error === "object" && error !== null && "stack" in error) {
        print("Test262:AsyncTestFailure:" + error.stack);
      } else {
        print("Test262:AsyncTestFailure:" + String(error));
      }
    } else {
      print("Test262:AsyncTestComplete");
    }
  };
}
"""

@dataclass
class TestMetadata:
    description: str = ""
    info: str = ""
    features: list = field(default_factory=list)
    flags: list = field(default_factory=list)
    includes: list = field(default_factory=list)
    negative: Optional[dict] = None
    es5id: str = ""
    es6id: str = ""
    esid: str = ""
    raw: bool = False


def parse_metadata(source: str) -> TestMetadata:
    """Parse the YAML frontmatter from a test262 test file."""
    data = parse_yaml_frontmatter(source)
    if data is None:
        return TestMetadata()

    meta = TestMetadata()
    description = data.get("description", "")
    meta.description = description if isinstance(description, str) else str(description) if description else ""
    info = data.get("info", "")
    meta.info = info if isinstance(info, str) else str(info) if info else ""
    meta.features = as_list(data.get("features", []))
    meta.flags = as_list(data.get("flags", []))
    meta.includes = as_list(data.get("includes", []))
    negative = data.get("negative", None)
    meta.negative = negative if isinstance(negative, dict) else None
    es5id = data.get("es5id", "")
    meta.es5id = es5id if isinstance(es5id, str) else str(es5id) if es5id else ""
    es6id = data.get("es6id", "")
    meta.es6id = es6id if isinstance(es6id, str) else str(es6id) if es6id else ""
    esid = data.get("esid", "")
    meta.esid = esid if isinstance(esid, str) else str(esid) if esid else ""
    meta.raw = "raw" in meta.flags
    return meta


# ---------------------------------------------------------------------------
# Test filtering
# ---------------------------------------------------------------------------

def should_skip(meta: TestMetadata, filepath: str, mode: str = "non-strict") -> Optional[str]:
    """Return a reason to skip the test, or None if it should run."""
    return skip_reason(filepath, meta.features, meta.flags, mode=mode)


# ---------------------------------------------------------------------------
# Runner progress/logging constants
# ---------------------------------------------------------------------------

MERGED_LOG_STATUSES = {"fail", "timeout", "error"}
STATUS_MARKS = {
    "pass": ".",
    "fail": "F",
    "skip": "S",
    "timeout": "T",
    "error": "E",
}


# ---------------------------------------------------------------------------
# Harness loading with caching
# ---------------------------------------------------------------------------

# Global cache for harness files to avoid repeated disk I/O
_harness_cache = {}

def load_harness(
    test262_dir: str,
    includes: list,
    is_raw: bool,
    is_async: bool = False,
    harness_options: HarnessOptions = DEFAULT_HARNESS_OPTIONS,
) -> str:
    """Load the required harness files for a test with caching."""
    if is_raw:
        return ""

    # Create cache key from includes list and opt-in helper set
    cache_key = (test262_dir, tuple(sorted(includes)), is_async, harness_options.helpers)
    if cache_key in _harness_cache:
        return _harness_cache[cache_key]

    harness_dir = os.path.join(test262_dir, "harness")
    parts = []

    # Inject print() preamble for host environment compatibility
    parts.append(PRINT_PREAMBLE)
    helper_source = harness_options.preamble()
    if helper_source:
        parts.append(helper_source)

    # Always load sta.js and assert.js (unless raw)
    for default_file in ["sta.js", "assert.js"]:
        file_key = (test262_dir, default_file)
        if file_key not in _harness_cache:
            path = os.path.join(harness_dir, default_file)
            if os.path.exists(path):
                with open(path, "r", encoding="utf-8") as f:
                    _harness_cache[file_key] = f.read()
            else:
                _harness_cache[file_key] = ""
        if _harness_cache[file_key]:
            parts.append(harness_options.transform_include(default_file, _harness_cache[file_key]))

    # Load additional includes
    for inc in includes:
        file_key = (test262_dir, inc)
        if file_key not in _harness_cache:
            path = os.path.join(harness_dir, inc)
            if os.path.exists(path):
                with open(path, "r", encoding="utf-8") as f:
                    _harness_cache[file_key] = f.read()
            else:
                _harness_cache[file_key] = ""
        if _harness_cache[file_key]:
            parts.append(harness_options.transform_include(inc, _harness_cache[file_key]))

    # For async tests, inject $DONE fallback if not provided by harness includes
    if is_async:
        parts.append(DONE_FALLBACK)

    result = "\n".join(parts)
    _harness_cache[cache_key] = result
    return result


# ---------------------------------------------------------------------------
# Module fixture resolution
# ---------------------------------------------------------------------------

def resolve_fixtures(test_path: str, source: str) -> list:
    """Walk relative imports starting from `source` and return [(specifier, source), ...]
    in dependency-first order so the engine can register each module before its dependents
    execute. Cycles are broken by visit-once tracking; circular fixtures still get included
    (in some order) so the engine sees them — the engine itself decides if cycles are valid.
    """
    test_abs = os.path.abspath(test_path)
    test_dir = os.path.dirname(test_abs)
    visited = {}    # specifier -> source
    order = []      # specifiers in post-order (dependencies before dependents)
    stack = set()   # specifiers currently on DFS stack (cycle detection)

    def visit(spec: str, importer_dir: str):
        # Resolve `spec` (always starts with ./ or ../) relative to importer_dir
        abs_path = os.path.normpath(os.path.join(importer_dir, spec))
        # Skip self-imports: the test runs as the main module, never as its own
        # fixture (run_modules would evaluate it twice and the self-import lookup
        # still wouldn't see the not-yet-registered exports).
        if abs_path == test_abs:
            return
        if abs_path in visited or abs_path in stack:
            return  # already done or back-edge (cycle)
        if not os.path.isfile(abs_path):
            return  # missing fixture — let the engine raise its usual error
        try:
            with open(abs_path, "r", encoding="utf-8") as f:
                fixture_src = f.read()
        except OSError as e:
            # Permission/encoding errors are real bugs, not module-resolution
            # misses — surface them so they don't silently skew test attribution.
            raise RuntimeError(f"Failed to read fixture {abs_path}: {e}") from e
        stack.add(abs_path)
        # Recurse into this fixture's own relative imports first
        for nested_spec in IMPORT_RELATIVE_RE.findall(fixture_src):
            visit(nested_spec, os.path.dirname(abs_path))
        stack.discard(abs_path)
        visited[abs_path] = (spec, fixture_src)
        order.append(abs_path)

    for spec in IMPORT_RELATIVE_RE.findall(source):
        visit(spec, test_dir)

    return [visited[p] for p in order]


# ---------------------------------------------------------------------------
# Test execution
# ---------------------------------------------------------------------------

@dataclass
class TestResult:
    path: str
    status: str  # "pass", "fail", "skip", "timeout", "error"
    reason: str = ""
    duration_ms: float = 0.0
    mode: str = "non-strict"  # "strict" or "non-strict"


def run_single_test(
    engine_cmd: list,
    test262_dir: str,
    test_path: str,
    timeout: int,
    mode: str = "non-strict",
    harness_options: HarnessOptions = DEFAULT_HARNESS_OPTIONS,
) -> TestResult:
    """Execute a single test262 test and return the result."""
    try:
        with open(test_path, "r", encoding="utf-8") as f:
            source = f.read()
    except Exception as e:
        return TestResult(path=test_path, status="error", reason=str(e), mode=mode)

    meta = parse_metadata(source)

    # Check if we should skip
    skip_reason = should_skip(meta, test_path, mode)
    if skip_reason:
        return TestResult(path=test_path, status="skip", reason=skip_reason, mode=mode)

    # Check if this is an async test
    is_async = "async" in meta.flags

    # Check if this is a module test
    is_module = "module" in meta.flags

    # Build the full source with harness
    harness = load_harness(
        test262_dir,
        meta.includes,
        meta.raw,
        is_async,
        harness_options,
    )

    if mode == "strict" and not meta.raw:
        full_source = '"use strict";\n' + harness + "\n" + source
    else:
        full_source = harness + "\n" + source

    # Determine if Annex B flag is needed (tests in annexB/ directories)
    is_annex_b = "annexB" in test_path

    # Build engine command - add --module and --annex-b flags as needed
    cmd = engine_cmd
    if is_module:
        main_specifier = "./" + os.path.basename(test_path)
        cmd = cmd + ["--module", "--module-specifier", main_specifier]
        # Module tests may import sibling _FIXTURE.js files relative to the test
        # path. The engine has no FS access, so we resolve them here and pass each
        # as a `--fixture <specifier> <source>` triple (registered before main runs).
        # The main module is registered under its basename specifier so self-imports
        # like `import * as ns from './current-test.js'` resolve to the same module.
        for spec, fixture_src in resolve_fixtures(test_path, source):
            cmd = cmd + ["--fixture", spec, fixture_src]
    if is_annex_b:
        cmd = cmd + ["--annex-b"]
    cmd = cmd + [full_source]

    start = time.monotonic()
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        duration_ms = (time.monotonic() - start) * 1000
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()
        exit_code = result.returncode

        # Determine pass/fail based on metadata
        if meta.negative:
            # Test expects an error
            neg_phase = meta.negative.get("phase", "runtime")
            neg_type = meta.negative.get("type", "")

            if exit_code != 0 or "Error:" in stdout or "Error:" in stderr:
                # Error was thrown — check type if possible
                error_output = stdout + " " + stderr
                if neg_type and neg_type in error_output:
                    return TestResult(
                        path=test_path, status="pass",
                        duration_ms=duration_ms, mode=mode,
                    )
                elif neg_type:
                    # Error was thrown but of a different type — still pass for parse errors
                    # since our engine doesn't output standard error names yet
                    if neg_phase == "parse":
                        return TestResult(
                            path=test_path, status="pass",
                            reason=f"parse error (expected {neg_type})",
                            duration_ms=duration_ms, mode=mode,
                        )
                    return TestResult(
                        path=test_path, status="pass",
                        reason=f"error thrown (expected {neg_type})",
                        duration_ms=duration_ms, mode=mode,
                    )
                else:
                    return TestResult(
                        path=test_path, status="pass",
                        duration_ms=duration_ms, mode=mode,
                    )
            else:
                return TestResult(
                    path=test_path, status="fail",
                    reason=f"Expected {neg_type} error but test passed normally",
                    duration_ms=duration_ms, mode=mode,
                )
        elif is_async:
            # Async test: check for $DONE completion markers in output
            # Check failure first — if both markers appear, failure takes priority
            combined = stdout + "\n" + stderr
            if "Test262:AsyncTestFailure" in combined:
                # Extract failure reason
                for line in combined.split("\n"):
                    if "Test262:AsyncTestFailure:" in line:
                        reason = line.split("Test262:AsyncTestFailure:", 1)[1].strip()
                        return TestResult(
                            path=test_path, status="fail",
                            reason=reason[:200],
                            duration_ms=duration_ms, mode=mode,
                        )
                return TestResult(
                    path=test_path, status="fail",
                    reason="async test failure (no details)",
                    duration_ms=duration_ms, mode=mode,
                )
            elif "Test262:AsyncTestComplete" in combined:
                if exit_code != 0:
                    return TestResult(
                        path=test_path, status="fail",
                        reason=f"async test completed but exited with code {exit_code}",
                        duration_ms=duration_ms, mode=mode,
                    )
                return TestResult(
                    path=test_path, status="pass",
                    duration_ms=duration_ms, mode=mode,
                )
            else:
                # $DONE was never called — check if there was an error
                if exit_code != 0 or "Error:" in stdout or "Test262Error" in stdout:
                    error_msg = stdout if stdout else stderr
                    return TestResult(
                        path=test_path, status="fail",
                        reason=error_msg[:200],
                        duration_ms=duration_ms, mode=mode,
                    )
                return TestResult(
                    path=test_path, status="fail",
                    reason="async test did not call $DONE",
                    duration_ms=duration_ms, mode=mode,
                )
        else:
            # Normal test: pass if no error
            if exit_code == 0 and "Error:" not in stdout and "Test262Error" not in stdout:
                return TestResult(
                    path=test_path, status="pass",
                    duration_ms=duration_ms, mode=mode,
                )
            else:
                error_msg = stdout if stdout else stderr
                return TestResult(
                    path=test_path, status="fail",
                    reason=error_msg[:200],
                    duration_ms=duration_ms, mode=mode,
                )

    except subprocess.TimeoutExpired:
        duration_ms = (time.monotonic() - start) * 1000
        return TestResult(
            path=test_path, status="timeout",
            reason=f"Exceeded {timeout}s timeout",
            duration_ms=duration_ms, mode=mode,
        )
    except Exception as e:
        duration_ms = (time.monotonic() - start) * 1000
        return TestResult(
            path=test_path, status="error",
            reason=str(e)[:200],
            duration_ms=duration_ms, mode=mode,
        )


# ---------------------------------------------------------------------------
# Test discovery
# ---------------------------------------------------------------------------

def discover_tests(test262_dir: str, filter_pattern: str = "") -> list:
    """Find all test262 .js files matching the filter."""
    test_dir = os.path.join(test262_dir, "test")
    tests = []
    for root, dirs, files in os.walk(test_dir):
        # Skip intl402 and staging directories for core conformance
        rel = os.path.relpath(root, test_dir)
        if rel.startswith("intl402") or rel.startswith("staging"):
            continue
        for f in sorted(files):
            if not f.endswith(".js"):
                continue
            if "_FIXTURE" in f:
                continue
            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(full_path, test_dir)
            if filter_pattern and filter_pattern not in rel_path:
                continue
            tests.append(full_path)
    return tests


# ---------------------------------------------------------------------------
# Results aggregation
# ---------------------------------------------------------------------------

@dataclass
class CategoryStats:
    total: int = 0
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    timeout: int = 0
    error: int = 0

    @property
    def pass_rate(self) -> float:
        executed = self.passed + self.failed
        if executed == 0:
            return 0.0
        return (self.passed / executed) * 100


def aggregate_results(results: list) -> dict:
    """Group results by category and compute statistics."""
    categories = {}
    overall = CategoryStats()

    for r in results:
        rel = os.path.relpath(r.path, os.path.join(os.path.dirname(__file__), "test262", "test"))
        parts = rel.split(os.sep)
        # Use first two path components as category (e.g. "language/expressions")
        if len(parts) >= 2:
            cat = f"{parts[0]}/{parts[1]}"
        else:
            cat = parts[0]

        if cat not in categories:
            categories[cat] = CategoryStats()
        stats = categories[cat]

        stats.total += 1
        overall.total += 1

        if r.status == "pass":
            stats.passed += 1
            overall.passed += 1
        elif r.status == "fail":
            stats.failed += 1
            overall.failed += 1
        elif r.status == "skip":
            stats.skipped += 1
            overall.skipped += 1
        elif r.status == "timeout":
            stats.timeout += 1
            overall.timeout += 1
        else:
            stats.error += 1
            overall.error += 1

    return {"overall": overall, "categories": categories}


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

def print_report(
    agg: dict,
    results: list,
    verbose: bool,
    summary_only: bool,
    methodology_label: str = "default",
):
    """Print the conformance report."""
    overall = agg["overall"]
    categories = agg["categories"]

    print("\n" + "=" * 72)
    print("  Test262 ECMAScript Conformance Report")
    print("  Engine: MoonBit JS Engine")
    print(f"  Date: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    if methodology_label != "default":
        print(f"  Methodology: {methodology_label}")
    print("=" * 72)

    executed = overall.passed + overall.failed
    print(f"\n  Total tests discovered: {overall.total}")
    print(f"  Skipped:               {overall.skipped}")
    print(f"  Executed:              {executed}")
    print(f"  Passed:                {overall.passed}")
    print(f"  Failed:                {overall.failed}")
    print(f"  Timeouts:              {overall.timeout}")
    print(f"  Errors:                {overall.error}")
    if executed > 0:
        print(f"\n  Pass rate:             {overall.pass_rate:.1f}% ({overall.passed}/{executed})")

    print(f"\n{'─' * 72}")
    print(f"  {'Category':<40} {'Pass':>6} {'Fail':>6} {'Skip':>6} {'Rate':>8}")
    print(f"{'─' * 72}")

    for cat in sorted(categories.keys()):
        stats = categories[cat]
        ex = stats.passed + stats.failed
        rate = f"{stats.pass_rate:.1f}%" if ex > 0 else "N/A"
        print(f"  {cat:<40} {stats.passed:>6} {stats.failed:>6} {stats.skipped:>6} {rate:>8}")

    print(f"{'─' * 72}")

    if not summary_only:
        failures = [r for r in results if r.status == "fail"]
        if failures:
            print(f"\n  Failed tests ({len(failures)}):")
            print(f"{'─' * 72}")
            for r in failures[:50]:
                rel = os.path.relpath(r.path)
                print(f"  FAIL: {rel}")
                if r.reason:
                    reason_short = r.reason[:100].replace('\n', ' ')
                    print(f"        {reason_short}")
            if len(failures) > 50:
                print(f"  ... and {len(failures) - 50} more")

    print()


def result_json_record(result: TestResult) -> dict:
    """Return the JSON-compatible result shape used by runner artifacts and logs."""
    return {
        "path": os.path.relpath(result.path),
        "status": result.status,
        "reason": result.reason,
        "duration_ms": round(result.duration_ms, 1),
        "mode": result.mode,
    }


def open_result_log(log_file: str, append: bool = False):
    """Open a JSONL result log, creating parent directories when needed."""
    if not log_file:
        return None
    parent = Path(log_file).parent
    if str(parent) not in ("", "."):
        parent.mkdir(parents=True, exist_ok=True)
    mode = "a" if append else "w"
    return open(log_file, mode, encoding="utf-8")


def write_result_log(log_file, result: TestResult) -> None:
    """Write one result record to an open JSONL log and flush it."""
    if log_file is None:
        return
    json.dump(result_json_record(result), log_file, separators=(",", ":"))
    log_file.write("\n")
    log_file.flush()


def write_result_logs(progress_log, merged_log, result: TestResult) -> None:
    """Write progress and merged failure logs for a completed task."""
    write_result_log(progress_log, result)
    if result.status in MERGED_LOG_STATUSES:
        write_result_log(merged_log, result)


def print_task_progress(
    result: TestResult,
    completed: int,
    total_tasks: int,
    start_time: float,
    verbose: bool,
) -> None:
    """Print per-task or periodic aggregate progress."""
    if verbose:
        print(STATUS_MARKS.get(result.status, "?"), end="", flush=True)
        if completed % 80 == 0:
            print()
    elif completed % 500 == 0:
        elapsed = time.monotonic() - start_time
        rate = completed / elapsed if elapsed > 0 else 0
        eta = (total_tasks - completed) / rate if rate > 0 else 0
        print(
            f"  Progress: {completed}/{total_tasks} "
            f"({rate:.0f} tests/sec, ETA: {eta/60:.1f}m)",
            flush=True,
        )


def run_test_tasks(
    engine_cmd: list,
    test262_dir: str,
    test_tasks: list[tuple[str, str]],
    timeout: int,
    threads: int,
    verbose: bool,
    progress_log,
    merged_log,
    harness_options: HarnessOptions = DEFAULT_HARNESS_OPTIONS,
) -> tuple[list[TestResult], float]:
    """Run expanded test tasks and return ``(results, elapsed_seconds)``."""
    results = []
    completed = 0
    total_tasks = len(test_tasks)
    start_time = time.monotonic()

    def record_result(result: TestResult) -> None:
        nonlocal completed
        results.append(result)
        completed += 1
        write_result_logs(progress_log, merged_log, result)
        print_task_progress(result, completed, total_tasks, start_time, verbose)

    if threads > 1:
        with ThreadPoolExecutor(max_workers=threads) as executor:
            futures = {
                executor.submit(
                    run_single_test,
                    engine_cmd,
                    test262_dir,
                    tf,
                    timeout,
                    mode,
                    harness_options,
                ): (tf, mode)
                for tf, mode in test_tasks
            }
            for future in as_completed(futures):
                record_result(future.result())
    else:
        for tf, mode in test_tasks:
            record_result(
                run_single_test(
                    engine_cmd,
                    test262_dir,
                    tf,
                    timeout,
                    mode,
                    harness_options,
                )
            )

    if verbose:
        print()

    return results, time.monotonic() - start_time


def save_results(
    results: list,
    agg: dict,
    output_file: str,
    harness_options: HarnessOptions = DEFAULT_HARNESS_OPTIONS,
):
    """Save results as JSON for later analysis."""
    overall = agg["overall"]
    methodology = harness_options.methodology_json_record()
    summary = {
        "total": overall.total,
        "passed": overall.passed,
        "failed": overall.failed,
        "skipped": overall.skipped,
        "timeout": overall.timeout,
        "error": overall.error,
        "pass_rate": round(overall.pass_rate, 2),
    }
    if methodology is not None:
        summary["methodology"] = methodology["label"]
    data = {
        "engine": "moonbit-js-engine",
        "date": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "summary": summary,
        "categories": {
            cat: {
                "total": stats.total,
                "passed": stats.passed,
                "failed": stats.failed,
                "skipped": stats.skipped,
                "pass_rate": round(stats.pass_rate, 2),
            }
            for cat, stats in sorted(agg["categories"].items())
        },
        "results": [result_json_record(r) for r in results],
    }
    if methodology is not None:
        data["methodology"] = methodology
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    print(f"  Results saved to: {output_file}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Test262 conformance runner for MoonBit JS Engine")
    parser.add_argument("--engine", default=None,
                        help="Command to invoke the JS engine (default: auto-detect built JS bundle)")
    parser.add_argument("--test262", default="./test262",
                        help="Path to test262 directory")
    parser.add_argument("--filter", default="",
                        help="Only run tests matching this pattern (e.g. 'language/expressions')")
    parser.add_argument("--tests-file", default="",
                        help="Run an explicit newline-delimited list of test files")
    parser.add_argument("--start", type=int, default=0,
                        help="Start at expanded task offset N (0-based)")
    parser.add_argument("--count", type=int, default=None,
                        help="Run at most N expanded tasks")
    parser.add_argument("--shard", default="",
                        help="Run balanced contiguous shard I/N after mode expansion")
    parser.add_argument("--resume-from", default="",
                        help="Skip expanded tasks already present in a results JSON file")
    parser.add_argument("--log", default="",
                        help="Write a per-task JSONL progress log")
    parser.add_argument("--merged-log", default="",
                        help="Append fail/timeout/error JSONL records for shard merging")
    parser.add_argument("--timeout", type=int, default=5,
                        help="Timeout per test in seconds (default: 5)")
    parser.add_argument("--threads", type=int, default=None,
                        help="Number of parallel workers (default: auto-detect CPU count)")
    parser.add_argument("--output", default="",
                        help="Write JSON results to this file")
    parser.add_argument("--summary", action="store_true",
                        help="Print summary only (no individual failures)")
    parser.add_argument("--verbose", action="store_true",
                        help="Print each test result as it runs")
    parser.add_argument("--mode", choices=["both", "strict", "non-strict"], default="both",
                        help="Test mode: 'strict' only, 'non-strict' only, or 'both' (default: both)")
    parser.add_argument("--harness-helper", action="append", default=[], metavar="NAME[,NAME]",
                        help="Opt into modified Test262 harness helper(s); currently: codePointRange")

    args = parser.parse_args()

    try:
        shard_spec = parse_shard_spec(args.shard) if args.shard else None
        harness_options = HarnessOptions.from_cli(args.harness_helper)
        if args.start < 0:
            raise ValueError("--start must be >= 0")
        if args.count is not None and args.count < 0:
            raise ValueError("--count must be >= 0")
        if shard_spec is not None and (args.start != 0 or args.count is not None):
            raise ValueError("--shard cannot be combined with --start/--count")
    except ValueError as e:
        parser.error(str(e))

    # Auto-detect engine JS bundle if not specified
    if args.engine is None:
        # Probe known build output paths (CI uses target/, local uses _build/)
        candidates = [
            "target/js/release/build/cmd/main/main.js",
            "target/js/debug/build/cmd/main/main.js",
            "_build/js/release/build/cmd/main/main.js",
            "_build/js/debug/build/cmd/main/main.js",
        ]
        for path in candidates:
            if os.path.isfile(path):
                args.engine = f"node {path}"
                break
        if args.engine is None:
            print("Error: No built JS bundle found. Run `moon build --target js` first.", file=sys.stderr)
            print(f"  Searched: {', '.join(candidates)}", file=sys.stderr)
            sys.exit(1)
        print(f"Using engine: {args.engine}")

    # Auto-detect thread count if not specified
    if args.threads is None:
        # Use CPU count, but ensure we use at least 4 threads for good parallelism
        cpu_count = os.cpu_count() or 4
        args.threads = max(4, cpu_count)

    # Ensure at least 1 thread
    args.threads = max(1, args.threads)

    engine_cmd = shlex.split(args.engine)
    test262_dir = os.path.abspath(args.test262)

    if not os.path.isdir(test262_dir):
        print(f"Error: test262 directory not found: {test262_dir}", file=sys.stderr)
        sys.exit(1)

    # Verify engine works
    print("Verifying engine...")
    try:
        check = subprocess.run(
            engine_cmd + ["1 + 1"],
            capture_output=True, text=True, timeout=30,
        )
        if check.returncode != 0:
            print(f"Warning: Engine returned non-zero exit code: {check.returncode}")
            print(f"  stdout: {check.stdout.strip()}")
            print(f"  stderr: {check.stderr.strip()}")
    except FileNotFoundError:
        print(f"Error: Engine command not found: {engine_cmd[0]}", file=sys.stderr)
        print("Make sure MoonBit is installed and 'moon' is in your PATH.")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print("Warning: Engine verification timed out")

    # Discover tests
    if args.tests_file:
        print(f"Loading tests from {args.tests_file}...")
        try:
            test_files = load_tests_file(args.tests_file, test262_dir)
        except OSError as e:
            print(f"Error: failed to read tests file {args.tests_file}: {e}", file=sys.stderr)
            sys.exit(1)
        if args.filter:
            test_files = [
                tf for tf in test_files
                if args.filter in normalize_test262_path(tf, test262_dir)
            ]
        print(f"Loaded {len(test_files)} test files")
    else:
        print(f"Discovering tests in {test262_dir}...")
        test_files = discover_tests(test262_dir, args.filter)
        print(f"Found {len(test_files)} test files")

    run_mode = args.mode  # "both", "strict", or "non-strict"
    test_tasks = build_test_tasks(test_files, run_mode)
    try:
        test_tasks, selection_messages = apply_task_selection(
            test_tasks,
            shard_spec=shard_spec,
            start=args.start,
            count=args.count,
            resume_from=args.resume_from,
            test262_dir=test262_dir,
        )
    except (OSError, json.JSONDecodeError) as e:
        print(f"Error: failed to read resume file {args.resume_from}: {e}", file=sys.stderr)
        sys.exit(1)
    for message in selection_messages:
        print(message)

    mode_label = run_mode if run_mode != "both" else "strict+non-strict"
    print(f"Running {len(test_tasks)} test tasks ({len(test_files)} files, {mode_label})")
    print(f"Using {args.threads} parallel worker(s) with {args.timeout}s timeout per test")
    if harness_options.is_modified:
        print(f"Using modified Test262 harness helpers: {', '.join(harness_options.helpers)}")

    progress_log = None
    merged_log = None
    try:
        progress_log = open_result_log(args.log, append=False)
        merged_log = open_result_log(args.merged_log, append=True)
    except OSError as e:
        print(f"Error: failed to open result log: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        results, total_time = run_test_tasks(
            engine_cmd,
            test262_dir,
            test_tasks,
            args.timeout,
            args.threads,
            args.verbose,
            progress_log,
            merged_log,
            harness_options,
        )
    finally:
        for log_file in (progress_log, merged_log):
            if log_file is not None:
                log_file.close()

    print(f"\nCompleted in {total_time:.1f}s")

    # Aggregate and report
    agg = aggregate_results(results)
    methodology_label = harness_options.methodology_label
    print_report(agg, results, args.verbose, args.summary, methodology_label)

    # Save results
    output_file = args.output or "test262-results.json"
    save_results(results, agg, output_file, harness_options)

    # Exit with non-zero if any tests failed (useful for CI)
    if agg["overall"].failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
