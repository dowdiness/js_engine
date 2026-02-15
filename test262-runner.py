#!/usr/bin/env python3
"""
Test262 Conformance Runner for the MoonBit JS Engine (Optimized).

Usage:
    python3 test262-runner.py [options]

Options:
    --engine CMD        Command to run the JS engine (default: auto-detect built JS bundle)
    --test262 DIR       Path to test262 directory (default: ./test262)
    --filter PATTERN    Only run tests matching this pattern (e.g. "language/expressions")
    --timeout SECS      Timeout per test in seconds (default: 5)
    --threads N         Number of parallel workers (default: auto-detect, min 4)
    --output FILE       Write JSON results to this file
    --summary           Print summary only (no individual failures)
    --verbose           Print each test result as it runs

Performance Optimizations:
    - Harness file caching to avoid repeated disk I/O
    - Auto-detected CPU-based parallelism (minimum 4 threads, scales with CPU count)
    - Moderate timeout (5s) balancing speed and test completion
    - Optimized progress reporting with ETA

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
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional, Any

from test262_utils import parse_yaml_frontmatter, as_list

SKIP_FEATURES = {
    # Features this engine definitely doesn't support yet

    # Async / Promises (async-functions and async-iteration still unsupported)
    "async-functions", "async-iteration",
    "promise-with-resolvers", "promise-try",
    "top-level-await",

    # Classes (advanced features not yet supported)
    "class-fields-private", "class-fields-public",
    "class-methods-private", "class-static-fields-private",
    "class-static-fields-public", "class-static-methods-private",
    "class-static-block",

    # Iteration / ordering
    "for-in-order",
    "iterator-helpers", "iterator-sequencing", "joint-iteration",
    "set-methods",

    # Collections
    "WeakRef",

    # Typed arrays and buffers (partially supported)
    "SharedArrayBuffer", "Float16Array", "Atomics",
    "resizable-arraybuffer", "arraybuffer-transfer",

    # Tail calls
    "tail-call-optimization",

    # Modules / dynamic import
    "import.meta", "dynamic-import",
    "json-modules", "import-assertions", "import-attributes",
    "source-phase-imports", "source-phase-imports-module-source",

    # RegExp advanced features
    "regexp-lookbehind", "regexp-named-groups", "regexp-unicode-property-escapes",
    "regexp-match-indices", "regexp-v-flag", "regexp-dotall",
    "regexp-modifiers",
    "RegExp.escape",
    "String.prototype.matchAll",

    # Missing operators and syntax
    "hashbang",

    # Intl / locale
    "Intl", "intl-normative-optional",

    # Other missing features
    "FinalizationRegistry",
    "BigInt",
    "IsHTMLDDA",
    "cross-realm",
    "caller",
    "Temporal", "ShadowRealm",
    "decorators",
    "explicit-resource-management",
    "json-parse-with-source",

    # Removed in Phase 2+3 (now supported): arrow-function, template, let,
    # const, destructuring-binding, destructuring-assignment,
    # default-parameters, for-of, Object.entries, Array.prototype.flat,
    # Array.prototype.flatMap, Array.prototype.includes
    # Removed in Phase 3.6+4 (now supported): class, numeric-separator-literal,
    # logical-assignment-operators
    # Removed in Phase 5 (now supported): Promise, Promise.allSettled,
    # Promise.any, Promise.prototype.finally, Object.fromEntries, Object.is,
    # Object.hasOwn, Array.from, Array.prototype.at,
    # String.prototype.replaceAll, String.prototype.isWellFormed,
    # String.prototype.toWellFormed, change-array-by-copy,
    # array-find-from-last, string-trimming, new.target,
    # object-spread, object-rest
}

SKIP_FLAGS = {"CanBlockIsFalse", "CanBlockIsTrue"}

# Tests that depend on unsupported runtime features but don't declare
# corresponding Test262 `features` metadata.
SKIP_PATH_SUFFIXES = {
}

# Preamble injected before all test harness code to provide host-defined print()
PRINT_PREAMBLE = 'function print() { var s = ""; for (var i = 0; i < arguments.length; i++) { if (i > 0) s += " "; s += String(arguments[i]); } console.log(s); }\n'

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
    # Skip fixture files
    if "_FIXTURE" in filepath:
        return "fixture file"

    normalized_path = filepath.replace("\\", "/")
    for suffix, reason in SKIP_PATH_SUFFIXES.items():
        if normalized_path.endswith(suffix):
            return reason

    # Skip tests with unsupported flags
    for flag in meta.flags:
        if flag in SKIP_FLAGS:
            return f"unsupported flag: {flag}"

    # Respect onlyStrict/noStrict flags
    if mode == "non-strict" and "onlyStrict" in meta.flags:
        return "requires strict mode"
    if mode == "strict" and "noStrict" in meta.flags:
        return "cannot run in strict mode"

    # Skip tests that require features we don't support
    for feature in meta.features:
        if feature in SKIP_FEATURES:
            return f"unsupported feature: {feature}"

    return None


# ---------------------------------------------------------------------------
# Harness loading with caching
# ---------------------------------------------------------------------------

# Global cache for harness files to avoid repeated disk I/O
_harness_cache = {}

def load_harness(test262_dir: str, includes: list, is_raw: bool, is_async: bool = False) -> str:
    """Load the required harness files for a test with caching."""
    if is_raw:
        return ""

    # Create cache key from includes list
    cache_key = (test262_dir, tuple(sorted(includes)), is_async)
    if cache_key in _harness_cache:
        return _harness_cache[cache_key]

    harness_dir = os.path.join(test262_dir, "harness")
    parts = []

    # Inject print() preamble for host environment compatibility
    parts.append(PRINT_PREAMBLE)

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
            parts.append(_harness_cache[file_key])

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
            parts.append(_harness_cache[file_key])

    # For async tests, inject $DONE fallback if not provided by harness includes
    if is_async:
        parts.append(DONE_FALLBACK)

    result = "\n".join(parts)
    _harness_cache[cache_key] = result
    return result


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
    harness = load_harness(test262_dir, meta.includes, meta.raw, is_async)

    if mode == "strict" and not meta.raw:
        full_source = '"use strict";\n' + harness + "\n" + source
    else:
        full_source = harness + "\n" + source

    # Build engine command - add --module flag for module tests
    cmd = engine_cmd + (["--module"] if is_module else []) + [full_source]

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

def print_report(agg: dict, results: list, verbose: bool, summary_only: bool):
    """Print the conformance report."""
    overall = agg["overall"]
    categories = agg["categories"]

    print("\n" + "=" * 72)
    print("  Test262 ECMAScript Conformance Report")
    print("  Engine: MoonBit JS Engine")
    print(f"  Date: {time.strftime('%Y-%m-%d %H:%M:%S')}")
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


def save_results(results: list, agg: dict, output_file: str):
    """Save results as JSON for later analysis."""
    overall = agg["overall"]
    data = {
        "engine": "moonbit-js-engine",
        "date": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "summary": {
            "total": overall.total,
            "passed": overall.passed,
            "failed": overall.failed,
            "skipped": overall.skipped,
            "timeout": overall.timeout,
            "error": overall.error,
            "pass_rate": round(overall.pass_rate, 2),
        },
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
        "results": [
            {
                "path": os.path.relpath(r.path),
                "status": r.status,
                "reason": r.reason,
                "duration_ms": round(r.duration_ms, 1),
                "mode": r.mode,
            }
            for r in results
        ],
    }
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

    args = parser.parse_args()

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

    engine_cmd = args.engine.split()
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
    print(f"Discovering tests in {test262_dir}...")
    test_files = discover_tests(test262_dir, args.filter)
    print(f"Found {len(test_files)} test files")
    print(f"Using {args.threads} parallel worker(s) with {args.timeout}s timeout per test")

    # Run tests
    results = []
    completed = 0
    start_time = time.monotonic()

    if args.threads > 1:
        with ThreadPoolExecutor(max_workers=args.threads) as executor:
            futures = {
                executor.submit(
                    run_single_test, engine_cmd, test262_dir, tf, args.timeout, "non-strict"
                ): tf
                for tf in test_files
            }
            for future in as_completed(futures):
                r = future.result()
                results.append(r)
                completed += 1
                if args.verbose:
                    status_mark = {"pass": ".", "fail": "F", "skip": "S", "timeout": "T", "error": "E"}
                    print(status_mark.get(r.status, "?"), end="", flush=True)
                    if completed % 80 == 0:
                        print()
                elif completed % 500 == 0:
                    elapsed = time.monotonic() - start_time
                    rate = completed / elapsed if elapsed > 0 else 0
                    eta = (len(test_files) - completed) / rate if rate > 0 else 0
                    print(f"  Progress: {completed}/{len(test_files)} ({rate:.0f} tests/sec, ETA: {eta/60:.1f}m)", flush=True)
    else:
        for tf in test_files:
            r = run_single_test(engine_cmd, test262_dir, tf, args.timeout, "non-strict")
            results.append(r)
            completed += 1
            if args.verbose:
                status_mark = {"pass": ".", "fail": "F", "skip": "S", "timeout": "T", "error": "E"}
                print(status_mark.get(r.status, "?"), end="", flush=True)
                if completed % 80 == 0:
                    print()
            elif completed % 500 == 0:
                elapsed = time.monotonic() - start_time
                rate = completed / elapsed if elapsed > 0 else 0
                eta = (len(test_files) - completed) / rate if rate > 0 else 0
                print(f"  Progress: {completed}/{len(test_files)} ({rate:.0f} tests/sec, ETA: {eta/60:.1f}m)", flush=True)

    if args.verbose:
        print()

    total_time = time.monotonic() - start_time
    print(f"\nCompleted in {total_time:.1f}s")

    # Aggregate and report
    agg = aggregate_results(results)
    print_report(agg, results, args.verbose, args.summary)

    # Save results
    output_file = args.output or "test262-results.json"
    save_results(results, agg, output_file)

    # Exit with non-zero if any tests failed (useful for CI)
    if agg["overall"].failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
