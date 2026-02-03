#!/usr/bin/env python3
"""
Test262 Batch Runner - Uses persistent MoonBit process to eliminate subprocess overhead.

This runner starts a single MoonBit process that reads tests from stdin,
eliminating the ~50-100ms startup overhead per test. This can provide
10-100x speedup compared to spawning a subprocess for each test.

Protocol:
    Python -> MoonBit: <<<SOURCE>>>\n<javascript code>\n<<<END>>>
    MoonBit -> Python: PASS or FAIL or ERROR

Usage:
    python3 test262-batch-runner.py [options]
"""

import argparse
import json
import os
import subprocess
import sys
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
    """Run tests using batch mode - single process for all tests."""
    print(f"Starting batch runner: {' '.join(engine_cmd)}")

    # Start the batch runner process
    proc = subprocess.Popen(
        engine_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,  # Line buffered
    )

    # Wait for READY signal
    try:
        ready_line = proc.stdout.readline()
        if "READY" not in ready_line:
            stderr = proc.stderr.read()
            print(f"Error: Batch runner didn't signal READY", file=sys.stderr)
            print(f"Stdout: {ready_line}", file=sys.stderr)
            print(f"Stderr: {stderr}", file=sys.stderr)
            proc.terminate()
            return []
    except Exception as e:
        print(f"Error waiting for READY: {e}", file=sys.stderr)
        proc.terminate()
        return []

    print(f"Batch runner ready. Processing {len(test_files)} tests...")

    results = []
    start_time = time.monotonic()

    for i, test_file in enumerate(test_files):
        # Read test source
        try:
            with open(test_file, "r", encoding="utf-8") as f:
                source = f.read()
        except Exception as e:
            results.append({
                "path": test_file,
                "status": "error",
                "reason": f"Failed to read file: {e}"
            })
            continue

        # Send test to batch runner using delimiter protocol
        try:
            proc.stdin.write("<<<SOURCE>>>\n")
            proc.stdin.write(source)
            if not source.endswith("\n"):
                proc.stdin.write("\n")
            proc.stdin.write("<<<END>>>\n")
            proc.stdin.flush()
        except Exception as e:
            results.append({
                "path": test_file,
                "status": "error",
                "reason": f"Failed to send test: {e}"
            })
            break

        # Read result
        try:
            result_line = proc.stdout.readline()
            if not result_line:
                results.append({
                    "path": test_file,
                    "status": "error",
                    "reason": "Batch runner died"
                })
                break

            status = result_line.strip().lower()
            if status not in ["pass", "fail", "error"]:
                results.append({
                    "path": test_file,
                    "status": "error",
                    "reason": f"Invalid status: {result_line}"
                })
            else:
                results.append({
                    "path": test_file,
                    "status": status,
                    "reason": ""
                })

        except Exception as e:
            results.append({
                "path": test_file,
                "status": "error",
                "reason": f"Failed to read result: {e}"
            })
            break

        # Progress reporting
        if (i + 1) % 1000 == 0:
            elapsed = time.monotonic() - start_time
            rate = (i + 1) / elapsed
            eta = (len(test_files) - (i + 1)) / rate if rate > 0 else 0
            print(f"  Progress: {i+1}/{len(test_files)} ({rate:.0f} tests/sec, ETA: {eta/60:.1f}m)")

    # Send EXIT command
    try:
        proc.stdin.write("EXIT\n")
        proc.stdin.flush()
        proc.wait(timeout=5)
    except:
        proc.terminate()

    return results


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
