#!/usr/bin/env python3
"""
report-test262.py — download a test262 CI run's artifacts and print a
paste-ready per-mode pass-rate block.

Follows the repo's test262 reporting convention (see AGENTS.md
"Test262 Reporting Convention"): always per-mode, always both
denominators (Passed / Executed *and* Passed / Discovered), numbers
pulled from CI not doc prose.

Usage:
    scripts/report-test262.py                       # latest successful main run
    scripts/report-test262.py --run 24730849102     # specific run id
    scripts/report-test262.py --with-editions       # append per-edition tables
    scripts/report-test262.py --keep-artifacts dir  # retain downloads in dir

Requires `gh` (authenticated). Artifacts go to a temp directory that is
removed on exit unless --keep-artifacts is passed.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def gh(*args: str) -> str:
    result = subprocess.run(["gh", *args], check=True, capture_output=True, text=True)
    return result.stdout.strip()


def resolve_run(repo: str | None, workflow: str, run_id: int | None) -> dict:
    """Return {id, sha, created_at, url} for the requested run."""
    repo_flag = ["-R", repo] if repo else []
    fields = "databaseId,headSha,createdAt,url"
    if run_id is None:
        raw = gh("run", "list", "--workflow", workflow, "--branch", "main",
                 "--status", "success", "--limit", "1", "--json", fields, *repo_flag)
        data = json.loads(raw)
        if not data:
            sys.exit(f"No successful run found for workflow={workflow} on main.")
        entry = data[0]
    else:
        raw = gh("run", "view", str(run_id), "--json", fields, *repo_flag)
        entry = json.loads(raw)
    return {
        "id": entry["databaseId"],
        "sha": entry["headSha"],
        "created_at": entry["createdAt"],
        "url": entry["url"],
    }


def download_artifacts(run_id: int, repo: str | None, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    repo_flag = ["-R", repo] if repo else []
    gh("run", "download", str(run_id), "-p", "test262-*-results",
       "-D", str(out_dir), *repo_flag)


def find_results(artifact_dir: Path) -> tuple[Path, Path]:
    strict = next(artifact_dir.rglob("test262-strict-results.json"), None)
    nonstrict = next(artifact_dir.rglob("test262-non-strict-results.json"), None)
    if not strict or not nonstrict:
        sys.exit(f"Missing strict or non-strict results under {artifact_dir}. "
                 "Did both CI jobs succeed?")
    return strict, nonstrict


def load_summary(path: Path) -> dict:
    with path.open() as f:
        return json.load(f)["summary"]


def pct(num: int, denom: int) -> str:
    return f"{100.0 * num / denom:.1f}%" if denom else "—"


def load_baseline(path: Path) -> dict | None:
    """Read test262-baseline.json if present; return None if missing."""
    if not path.is_file():
        return None
    with path.open() as f:
        return json.load(f)


def render_baseline_line(baseline: dict, strict: dict, nonstrict: dict) -> str:
    """Format the 'CI regression baseline' sentence matching ROADMAP style."""
    s_min = baseline.get("strict", {}).get("passed_min", 0)
    n_min = baseline.get("non-strict", {}).get("passed_min", 0)
    s_delta = strict["passed"] - s_min
    n_delta = nonstrict["passed"] - n_min
    updated = baseline.get("updated", "unknown date")
    s_sign = "+" if s_delta >= 0 else ""
    n_sign = "+" if n_delta >= 0 else ""
    status = (" **REGRESSION**"
              if s_delta < 0 or n_delta < 0 else "")
    return (f"CI regression baseline: `test262-baseline.json` (min "
            f"{n_min:,} non-strict / {s_min:,} strict passed, updated "
            f"{updated}; currently {n_sign}{n_delta:,} / {s_sign}{s_delta:,} "
            f"above).{status}")


def render_changelog(run: dict, strict: dict, nonstrict: dict,
                     baseline: dict | None = None) -> str:
    """Prose format for CHANGELOG 'Conformance' sections — paste-ready.

    Deliberately omits unit-test count and prior-release comparison:
    those belong to the human writing the release notes, not to the
    number-fetching tool.
    """
    def numbers(s: dict) -> tuple[int, int, int]:
        passed = s["passed"]
        executed = passed + s["failed"]
        discovered = s["total"]
        return passed, executed, discovered

    sp, se, sd = numbers(strict)
    np, ne, nd = numbers(nonstrict)
    date = run["created_at"][:10]
    sha = run["sha"][:7]
    parts = [
        "test262 (each file run in both strict and non-strict modes,",
        "reported separately — summing would double-count files):",
        "",
        f"- **Passed / Executed**: {pct(sp, se)} strict ({sp:,} / {se:,}),",
        f"  {pct(np, ne)} non-strict ({np:,} / {ne:,}). Excludes ~40% of",
        "  discovered files skipped for unimplemented features.",
        f"- **Passed / Discovered**: {pct(sp, sd)} strict, {pct(np, nd)}",
        "  non-strict. Counts skipped files as un-passed.",
        "",
        f"Measured on CI run {run['id']} (tip `{sha}`, {date}).",
    ]
    if baseline:
        s_min = baseline.get("strict", {}).get("passed_min", 0)
        n_min = baseline.get("non-strict", {}).get("passed_min", 0)
        s_delta = sp - s_min
        n_delta = np - n_min
        parts.append(
            f"Regression baseline: +{n_delta:,} non-strict / +{s_delta:,} "
            f"strict vs `test262-baseline.json` (min {n_min:,} / {s_min:,})."
            if s_delta >= 0 and n_delta >= 0
            else f"Regression baseline: {n_delta:+,} non-strict / "
                 f"{s_delta:+,} strict vs `test262-baseline.json` "
                 f"(min {n_min:,} / {s_min:,}). **REGRESSION**"
        )
    return "\n".join(parts)


def render_report(run: dict, strict: dict, nonstrict: dict,
                  baseline: dict | None = None) -> str:
    sha = run["sha"][:7]
    date = run["created_at"][:10]
    lines = [
        f"**Test262** — CI run [{run['id']}]({run['url']}) on tip `{sha}`, "
        f"{date}. Each test file is run twice (strict + non-strict); the two "
        "are reported separately because summing would double-count files.",
        "",
        "| Mode | Discovered | Skipped | Executed | Passed | Failed | Timeouts "
        "| Passed / Executed | Passed / Discovered |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for mode, s in [("strict", strict), ("non-strict", nonstrict)]:
        discovered = s["total"]
        skipped = s["skipped"]
        passed = s["passed"]
        failed = s["failed"]
        timeout = s.get("timeout", 0)
        # Runner convention: Executed = Passed + Failed.
        # Timeouts and errors sit outside that bucket, so
        # Discovered = Skipped + Executed + Timeouts + Errors.
        executed = passed + failed
        lines.append(
            f"| {mode} | {discovered:,} | {skipped:,} | {executed:,} | "
            f"{passed:,} | {failed:,} | {timeout:,} | "
            f"**{pct(passed, executed)}** | {pct(passed, discovered)} |"
        )
    if baseline:
        lines += ["", render_baseline_line(baseline, strict, nonstrict)]
    errors = strict.get("error", 0) + nonstrict.get("error", 0)
    if errors:
        lines += ["", f"_Note: {errors} runner error(s) excluded from the "
                  "Timeouts column; inspect results JSON for details._"]
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--run", type=int, default=None,
                   help="CI run id (default: latest successful main run)")
    p.add_argument("--repo", default=None,
                   help="owner/name; default inferred from current repo by gh")
    p.add_argument("--workflow", default="test262.yml",
                   help="workflow file name (default: test262.yml)")
    p.add_argument("--keep-artifacts", metavar="DIR", default=None,
                   help="retain downloaded artifacts in DIR")
    p.add_argument("--with-editions", action="store_true",
                   help="also run scripts/classify-by-edition.py and print "
                        "per-edition tables below the headline "
                        "(table format only)")
    p.add_argument("--format", choices=["table", "changelog"], default="table",
                   help="table (markdown headline + per-mode table, for "
                        "ROADMAP/README) or changelog (prose bullets, for "
                        "CHANGELOG entries). Default: table.")
    p.add_argument("--baseline", metavar="PATH",
                   default="test262-baseline.json",
                   help="baseline JSON path (default: test262-baseline.json; "
                        "silently skipped if absent)")
    p.add_argument("--no-baseline", action="store_true",
                   help="skip the CI regression baseline delta line")
    args = p.parse_args()

    if shutil.which("gh") is None:
        sys.exit("gh CLI not found; install from https://cli.github.com/")

    run = resolve_run(args.repo, args.workflow, args.run)

    if args.keep_artifacts:
        art_dir = Path(args.keep_artifacts).resolve()
        cleanup = False
    else:
        art_dir = Path(tempfile.mkdtemp(prefix="test262-ci-"))
        cleanup = True

    try:
        download_artifacts(run["id"], args.repo, art_dir)
        strict_path, nonstrict_path = find_results(art_dir)
        strict = load_summary(strict_path)
        nonstrict = load_summary(nonstrict_path)
        baseline = None if args.no_baseline else load_baseline(Path(args.baseline))
        if args.format == "changelog":
            print(render_changelog(run, strict, nonstrict, baseline))
        else:
            print(render_report(run, strict, nonstrict, baseline))
        if args.format == "table" and args.with_editions:
            print()
            sys.stdout.flush()  # ensure headline lands before subprocess output
            classifier = Path(__file__).resolve().parent / "classify-by-edition.py"
            subprocess.run(
                [sys.executable, str(classifier), "--markdown",
                 str(strict_path), str(nonstrict_path)],
                check=True,
            )
    finally:
        if cleanup:
            shutil.rmtree(art_dir, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
