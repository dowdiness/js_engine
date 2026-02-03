#!/usr/bin/env python3
"""
Test262 Batch Runner - Uses file-based batch processing to eliminate subprocess overhead.

This runner writes all test sources to a batch file, then invokes MoonBit once
to process all tests, eliminating the ~50-100ms startup overhead per test.
This can provide 10-100x speedup compared to spawning a subprocess for each test.

Protocol:
    1. Python writes all test sources to batch-input.txt (separated by <<<TESTSEP>>>)
    2. Python runs: moon run cmd/test262 batch-input.txt
    3. MoonBit processes all tests and outputs one line per test: PASS/FAIL/ERROR
    4. Python reads results and cleans up

Usage:
    python3 test262-batch-runner.py [options]
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time


def discover_tests(test262_dir, filter_pattern=""):
    """Discover all test files in the test262 directory."""
    test_dir = os.path.join(test262_dir, "test")
    test_files = []

    for root, dirs, files in os.walk(test_dir):
        for file in files:
            if file.endswith(".js"):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, test262_dir)

                if not filter_pattern or filter_pattern in rel_path:
                    test_files.append(full_path)

    return sorted(test_files)


def run_tests_batch(engine_cmd, test_files):
    """Run tests using batch mode - single invocation for all tests."""
    print(f"Creating batch file with {len(test_files)} tests...")

    # Create temporary batch file
    batch_file = None
    try:
        # Write all test sources to batch file
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as f:
            batch_file = f.name
            for i, test_file in enumerate(test_files):
                try:
                    with open(test_file, "r", encoding="utf-8") as tf:
                        source = tf.read()
                        f.write(source)
                        if i < len(test_files) - 1:
                            f.write("\n<<<TESTSEP>>>\n")
                except Exception as e:
                    print(f"Warning: Failed to read {test_file}: {e}", file=sys.stderr)
                    f.write(f"// ERROR: Failed to read file\n")
                    if i < len(test_files) - 1:
                        f.write("\n<<<TESTSEP>>>\n")

        print(f"Running batch processor: {' '.join(engine_cmd + [batch_file])}")
        start_time = time.monotonic()

        # Run batch processor
        result = subprocess.run(
            engine_cmd + [batch_file],
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout
        )

        elapsed = time.monotonic() - start_time

        if result.returncode != 0 and result.stderr:
            print(f"Batch runner error: {result.stderr}", file=sys.stderr)

        # Parse results
        lines = result.stdout.strip().split("\n")
        results = []

        # First line should be READY:count
        if lines and lines[0].startswith("READY:"):
            test_count = int(lines[0].split(":")[1])
            print(f"Batch runner ready. Processing {test_count} tests...")
            lines = lines[1:]  # Skip READY line

        # Each remaining line is a result
        for i, line in enumerate(lines):
            if i >= len(test_files):
                break

            status = line.strip().lower()
            if status not in ["pass", "fail", "error"]:
                status = "error"

            results.append({
                "path": test_files[i],
                "status": status,
                "reason": ""
            })

        # Fill in missing results as errors
        while len(results) < len(test_files):
            results.append({
                "path": test_files[len(results)],
                "status": "error",
                "reason": "No result from batch runner"
            })

        print(f"Batch processing completed in {elapsed:.1f}s ({len(test_files)/elapsed:.0f} tests/sec)")

        return results

    finally:
        # Clean up batch file
        if batch_file and os.path.exists(batch_file):
            os.unlink(batch_file)


def main():
    parser = argparse.ArgumentParser(description="Test262 batch runner")
    parser.add_argument("--engine", default="moon run cmd/test262",
                        help="Command to invoke batch runner")
    parser.add_argument("--test262", default="./test262",
                        help="Path to test262 directory")
    parser.add_argument("--filter", default="",
                        help="Only run tests matching this pattern")
    parser.add_argument("--output", default="",
                        help="Write JSON results to this file")
    parser.add_argument("--summary", action="store_true",
                        help="Print summary only")

    args = parser.parse_args()

    engine_cmd = args.engine.split()
    test262_dir = os.path.abspath(args.test262)

    if not os.path.isdir(test262_dir):
        print(f"Error: test262 directory not found: {test262_dir}", file=sys.stderr)
        sys.exit(1)

    # Discover tests
    print(f"Discovering tests in {test262_dir}...")
    test_files = discover_tests(test262_dir, args.filter)
    print(f"Found {len(test_files)} test files")

    # Run tests in batch mode
    start_time = time.monotonic()
    results = run_tests_batch(engine_cmd, test_files)
    elapsed = time.monotonic() - start_time

    # Calculate summary
    passed = sum(1 for r in results if r["status"] == "pass")
    failed = sum(1 for r in results if r["status"] == "fail")
    errors = sum(1 for r in results if r["status"] == "error")
    total = len(results)

    print(f"\n{'='*70}")
    print(f"Test262 Results (Batch Mode - No Subprocess Overhead!)")
    print(f"{'='*70}")
    print(f"Passed:  {passed}/{total} ({passed/total*100:.2f}%)")
    print(f"Failed:  {failed}/{total}")
    print(f"Errors:  {errors}/{total}")
    print(f"Total time: {elapsed:.1f}s ({total/elapsed:.0f} tests/sec)")
    print(f"{'='*70}")

    # Write output
    if args.output:
        output_data = {
            "summary": {
                "passed": passed,
                "failed": failed,
                "errors": errors,
                "skipped": 0,
                "total": total,
                "pass_rate": round(passed / total * 100, 2) if total > 0 else 0,
                "duration_sec": round(elapsed, 2),
                "tests_per_sec": round(total / elapsed, 2) if elapsed > 0 else 0
            },
            "results": results
        }
        with open(args.output, "w") as f:
            json.dump(output_data, f, indent=2)
        print(f"Results written to {args.output}")


if __name__ == "__main__":
    main()
