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


def run_tests_batch(engine_cmd, test_files, batch_size=50):
    """Run tests using batch mode - processes in chunks to avoid memory limits."""
    print(f"Processing {len(test_files)} tests in batches of {batch_size}...")

    all_results = []
    total_batches = (len(test_files) + batch_size - 1) // batch_size
    overall_start = time.monotonic()

    for batch_num in range(total_batches):
        start_idx = batch_num * batch_size
        end_idx = min(start_idx + batch_size, len(test_files))
        batch_files = test_files[start_idx:end_idx]

        print(f"Batch {batch_num + 1}/{total_batches}: Processing tests {start_idx + 1}-{end_idx}...")

        # Create temporary batch file
        batch_file = None
        try:
            # Write batch sources to file
            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as f:
                batch_file = f.name
                for i, test_file in enumerate(batch_files):
                    try:
                        with open(test_file, "r", encoding="utf-8") as tf:
                            source = tf.read()
                            f.write(source)
                            if i < len(batch_files) - 1:
                                f.write("\n<<<TESTSEP>>>\n")
                    except Exception as e:
                        print(f"Warning: Failed to read {test_file}: {e}", file=sys.stderr)
                        f.write(f"// ERROR: Failed to read file\n")
                        if i < len(batch_files) - 1:
                            f.write("\n<<<TESTSEP>>>\n")

            start_time = time.monotonic()

            # Run batch processor
            # Generous timeout: 10s per test in batch
            batch_timeout = len(batch_files) * 10
            result = subprocess.run(
                engine_cmd + [batch_file],
                capture_output=True,
                text=True,
                timeout=batch_timeout
            )

            elapsed = time.monotonic() - start_time

            if result.returncode != 0 and result.stderr:
                print(f"  Batch error (continuing): {result.stderr[:200]}", file=sys.stderr)

            # Parse results
            lines = result.stdout.strip().split("\n")
            batch_results = []

            # First line should be READY:count
            result_lines = lines
            if lines and lines[0].startswith("READY:"):
                result_lines = lines[1:]  # Skip READY line

            # Each remaining line is a result
            for i, line in enumerate(result_lines):
                if i >= len(batch_files):
                    break

                status = line.strip().lower()
                if status not in ["pass", "fail", "error"]:
                    status = "error"

                batch_results.append({
                    "path": batch_files[i],
                    "status": status,
                    "reason": ""
                })

            # Fill in missing results as errors
            while len(batch_results) < len(batch_files):
                batch_results.append({
                    "path": batch_files[len(batch_results)],
                    "status": "error",
                    "reason": "No result from batch runner"
                })

            all_results.extend(batch_results)

            rate = len(batch_files) / elapsed if elapsed > 0 else 0
            print(f"  Completed in {elapsed:.1f}s ({rate:.0f} tests/sec)")

        finally:
            # Clean up batch file
            if batch_file and os.path.exists(batch_file):
                os.unlink(batch_file)

    overall_elapsed = time.monotonic() - overall_start
    print(f"\nAll batches completed in {overall_elapsed:.1f}s ({len(test_files)/overall_elapsed:.0f} tests/sec)")

    return all_results


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
    parser.add_argument("--batch-size", type=int, default=50,
                        help="Number of tests per batch (default: 50)")

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
    results = run_tests_batch(engine_cmd, test_files, args.batch_size)
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
