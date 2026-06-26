#!/usr/bin/env python3
"""
Update test262-baseline.json from the latest successful main CI run.

Usage:
  python3 scripts/set-baseline.py [--buffer N] [--run-id ID] [--dry-run]

  --buffer N     subtract N from each passed count for passed_min (default: 100)
  --run-id ID    use a specific CI run instead of the latest successful main run
  --dry-run      print the proposed changes without writing the file

Always reads from a completed main-branch CI run — never from a PR branch run,
which can diverge from main before merging and produce outlier counts.
"""
import argparse, json, pathlib, subprocess, sys, tempfile
from datetime import date

REPO = "dowdiness/js_engine"
WORKFLOW = "test262.yml"
ARTIFACT = "test262-combined-report"
BASELINE_PATH = pathlib.Path(__file__).parent.parent / "test262-baseline.json"


def gh(*args):
    result = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        print(f"gh {' '.join(args)} failed:\n{result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def find_latest_main_run():
    run_id = gh(
        "api", "--method", "GET",
        f"repos/{REPO}/actions/workflows/{WORKFLOW}/runs",
        "-f", "branch=main", "-f", "status=success", "-f", "per_page=1",
        "--jq", ".workflow_runs[0].id",
    )
    if not run_id or run_id == "null":
        print("No successful main-branch CI run found.", file=sys.stderr)
        sys.exit(1)
    return run_id


def download_summary(run_id, tmpdir):
    gh("run", "download", run_id, "--repo", REPO,
       "--name", ARTIFACT, "--dir", tmpdir)
    path = pathlib.Path(tmpdir) / "test262-summary.json"
    if not path.exists():
        print(f"test262-summary.json not found in {ARTIFACT} artifact.", file=sys.stderr)
        sys.exit(1)
    with open(path) as f:
        return json.load(f)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--buffer", type=int, default=100,
                        help="Buffer below actual passed count (default: 100)")
    parser.add_argument("--run-id",
                        help="Specific CI run ID (default: latest successful main run)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print proposed changes without writing")
    args = parser.parse_args()

    run_id = args.run_id or find_latest_main_run()
    print(f"CI run: {run_id}  (buffer: {args.buffer})")

    with tempfile.TemporaryDirectory() as tmpdir:
        summary = download_summary(run_id, tmpdir)

    actuals = {
        "non-strict": summary["modes"]["non-strict"]["passed"],
        "strict":     summary["modes"]["strict"]["passed"],
        "combined":   summary["combined"]["passed"],
    }

    with open(BASELINE_PATH) as f:
        current = json.load(f)

    updated = {
        **current,
        "updated": date.today().isoformat(),
        "non-strict": {"passed_min": actuals["non-strict"] - args.buffer},
        "strict":     {"passed_min": actuals["strict"]     - args.buffer},
        "combined":   {"passed_min": actuals["combined"]   - args.buffer},
    }

    print()
    any_change = False
    for mode in ("non-strict", "strict", "combined"):
        old = current.get(mode, {}).get("passed_min", 0)
        new = updated[mode]["passed_min"]
        actual = actuals[mode]
        tag = "↑" if new > old else ("↓" if new < old else "=")
        print(f"  {mode:12}  actual={actual:6}  passed_min: {old} → {new}  {tag}")
        if new != old:
            any_change = True

    if not any_change:
        print("\nNo changes needed.")
        return

    if args.dry_run:
        print("\n--dry-run: not writing.")
        return

    with open(BASELINE_PATH, "w") as f:
        json.dump(updated, f, indent=2)
        f.write("\n")
    print(f"\nWrote {BASELINE_PATH}")
    print("Next: create a PR with this change (never commit directly to main).")


if __name__ == "__main__":
    main()
