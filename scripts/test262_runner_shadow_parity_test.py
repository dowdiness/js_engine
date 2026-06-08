#!/usr/bin/env python3
"""Parity slices for the MoonBit Test262 runner shadow.

Python remains authoritative. This test builds the native MoonBit shadow
executable directly, runs it and ``scripts/test262-runner.py`` against the same
small checked-out Test262 tests-file plus deterministic synthetic CLI/error
fixtures, and compares their artifacts with ``scripts/compare-test262-results.py``.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass, replace
from pathlib import Path
from types import ModuleType
from typing import Any, Iterator, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
COMPARE_SCRIPT = SCRIPT_DIR / "compare-test262-results.py"
TASK_SELECTION_SCRIPT = SCRIPT_DIR / "test262_task_selection.py"
SHADOW_EXE = REPO_ROOT / "_build/native/debug/build/cmd/test262_runner/test262_runner.exe"
JS_ENGINE = REPO_ROOT / "_build/js/debug/build/cmd/main/main.js"
MERGED_LOG_STATUSES = {"fail", "timeout", "error"}

# Deliberately tiny, but each file pins a distinct runner path over the real
# checked-out suite: ordinary strict/non-strict expansion, raw source handling,
# module fixture registration, async $DONE handling, negative tests, and a
# shared skip-metadata result.
CURATED_TESTS = (
    "language/literals/numeric/S7.8.3_A1.1_T1.js",
    "language/directive-prologue/10.1.1-8gs.js",
    "language/module-code/instn-resolve-order-src.js",
    "harness/asyncHelpers-asyncTest-returns-undefined.js",
    "language/keywords/ident-ref-this.js",
    "language/comments/hashbang/not-empty.js",
)
ASYNC_TEST = "harness/asyncHelpers-asyncTest-returns-undefined.js"
RESUME_RECORDS = (
    {"path": ASYNC_TEST, "mode": "non-strict", "status": "fail"},
    {"path": ASYNC_TEST, "mode": "strict", "status": "fail"},
)
CURATED_MARKERS = (
    ("language/directive-prologue/10.1.1-8gs.js", "raw flag", "flags: [raw]"),
    ("language/module-code/instn-resolve-order-src.js", "module flag", "flags: [module]"),
    ("language/module-code/instn-resolve-order-src.js", "module fixture import", "_FIXTURE.js"),
    (ASYNC_TEST, "async flag", "flags: [async]"),
    (ASYNC_TEST, "async $DONE", "$DONE"),
    ("language/keywords/ident-ref-this.js", "negative metadata", "negative:"),
    ("language/comments/hashbang/not-empty.js", "skip metadata feature", "features: [hashbang]"),
)


@dataclass(frozen=True)
class SupportModules:
    compare: ModuleType
    task_selection: ModuleType


@dataclass(frozen=True)
class RunnerArtifacts:
    runner: str
    output: Path
    progress_log: Path
    merged_log: Path

    @classmethod
    def for_run(cls, tmp: Path, label: str, runner: str) -> RunnerArtifacts:
        prefix = f"{label}-{runner}"
        return cls(
            runner=runner,
            output=tmp / f"{prefix}.json",
            progress_log=tmp / f"{prefix}-progress.jsonl",
            merged_log=tmp / f"{prefix}-merged.jsonl",
        )


@dataclass(frozen=True)
class PairResult:
    python: RunnerArtifacts
    moonbit: RunnerArtifacts
    exit_code: int


@dataclass(frozen=True)
class PairConfig:
    engine: str
    test262: Path
    tests_file: Path
    tmp: Path
    resume_from: Path | None = None
    filter: str = ""
    mode: str = "both"
    start: int = 0
    count: int | None = None
    shard: str = ""
    timeout: int = 5
    harness_helpers: tuple[str, ...] = ()


JsonRecord = dict[str, Any]
ResultKey = tuple[str, str]
ComparableResult = tuple[str, str]


def load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def load_support_modules() -> SupportModules:
    return SupportModules(
        compare=load_module("compare_test262_results_for_shadow_parity", COMPARE_SCRIPT),
        task_selection=load_module("test262_task_selection_for_shadow_parity", TASK_SELECTION_SCRIPT),
    )


def run_checked(args: list[str], *, timeout: int = 180) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        args,
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    if proc.returncode != 0:
        raise AssertionError(format_process_failure(args, proc))
    return proc


def format_process_failure(args: list[str], proc: subprocess.CompletedProcess[str]) -> str:
    return (
        f"command failed ({proc.returncode}): {shlex_join(args)}\n"
        f"stdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}"
    )


def shlex_join(args: list[str]) -> str:
    return " ".join(subprocess.list2cmdline([arg]) for arg in args)


def path_arg(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def build_shadow_executable() -> Path:
    run_checked(["moon", "build", "--target", "native", "cmd/test262_runner"])
    if not SHADOW_EXE.is_file():
        raise AssertionError(f"native shadow executable not found: {SHADOW_EXE}")
    return SHADOW_EXE


def engine_command(explicit_engine: str) -> str:
    if explicit_engine:
        return explicit_engine
    if shutil.which("node"):
        run_checked(["moon", "build", "--target", "js", "cmd/main"])
        if not JS_ENGINE.is_file():
            raise AssertionError(f"JS engine bundle not found: {JS_ENGINE}")
        return f"node {JS_ENGINE}"
    # Developer fallback: still preserves the external subprocess model, but is
    # slower than the prebuilt JS bundle used when node is available.
    return "moon run cmd/main --"


def validate_curated_subset(test262_root: Path) -> None:
    test_root = test262_root / "test"
    missing = [rel for rel in CURATED_TESTS if not (test_root / rel).is_file()]
    if missing:
        raise AssertionError(
            "curated Test262 file(s) missing from checked-out suite: " + ", ".join(missing)
        )

    failed = [
        label
        for rel, label, marker in CURATED_MARKERS
        if marker not in (test_root / rel).read_text(encoding="utf-8")
    ]
    if failed:
        raise AssertionError("curated Test262 coverage check(s) failed: " + ", ".join(failed))


@contextmanager
def python_category_anchor(test262_root: Path) -> Iterator[Path]:
    """Expose the checked-out suite at scripts/test262 for Python category parity.

    The authoritative Python runner currently groups artifact categories relative
    to ``scripts/test262/test``. The real suite is checked out at ``./test262``;
    a temporary symlink lets both runners execute the same files while preserving
    Python's current artifact shape. The symlink is removed after the parity run
    and does not promote or alter the authoritative runner.
    """

    anchor = SCRIPT_DIR / "test262"
    expected = test262_root.resolve()
    created = False
    original_target: str | None = None
    if anchor.exists() or anchor.is_symlink():
        if anchor.resolve() == expected:
            yield anchor
            return
        if not anchor.is_symlink():
            raise AssertionError(f"{anchor} exists but does not resolve to {expected}")
        original_target = os.readlink(anchor)
        anchor.unlink()

    os.symlink(os.path.relpath(expected, SCRIPT_DIR), anchor, target_is_directory=True)
    created = True
    try:
        yield anchor
    finally:
        if created and (anchor.exists() or anchor.is_symlink()):
            anchor.unlink()
        if original_target is not None:
            os.symlink(original_target, anchor, target_is_directory=True)


@contextmanager
def parity_temp_dir(keep_temp: bool) -> Iterator[Path]:
    if keep_temp:
        tmp_dir = Path(tempfile.mkdtemp(prefix="test262-runner-shadow-parity-"))
        try:
            yield tmp_dir
        finally:
            print(f"kept temp dir: {tmp_dir}")
    else:
        with tempfile.TemporaryDirectory(prefix="test262-runner-shadow-parity-") as name:
            yield Path(name)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def write_executable(path: Path, text: str) -> None:
    write_text(path, text)
    path.chmod(0o755)


def write_tests_file(path: Path, tests: Sequence[str] = CURATED_TESTS) -> None:
    write_text(path, "\n".join(tests) + "\n")


def write_resume_file(path: Path) -> None:
    write_text(path, json.dumps({"results": list(RESUME_RECORDS)}, indent=2) + "\n")


def run_one_runner(
    args: list[str],
    *,
    output: Path,
    timeout: int = 120,
) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        args,
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    if not output.is_file():
        raise AssertionError(format_process_failure(args, proc) + f"\nmissing output: {output}")
    return proc


def compare_artifacts(left: Path, right: Path, *, ignore_reason: bool = False) -> None:
    args = [sys.executable, str(COMPARE_SCRIPT), str(left), str(right)]
    if ignore_reason:
        args.append("--ignore-reason")
    run_checked(args, timeout=60)


def runner_base(runner: str) -> list[str]:
    if runner == "python":
        return [sys.executable, "scripts/test262-runner.py"]
    if runner == "moonbit":
        return [str(SHADOW_EXE)]
    raise AssertionError(f"unknown runner: {runner}")


def runner_command(artifacts: RunnerArtifacts, config: PairConfig) -> list[str]:
    args = runner_base(artifacts.runner) + [
        "--engine",
        config.engine,
        "--test262",
        path_arg(config.test262),
        "--tests-file",
        str(config.tests_file),
        "--mode",
        config.mode,
        "--threads",
        "1",
        "--timeout",
        str(config.timeout),
        "--summary",
        "--output",
        str(artifacts.output),
        "--log",
        str(artifacts.progress_log),
        "--merged-log",
        str(artifacts.merged_log),
    ]
    if config.filter:
        args += ["--filter", config.filter]
    if config.start != 0:
        args += ["--start", str(config.start)]
    if config.count is not None:
        args += ["--count", str(config.count)]
    if config.shard:
        args += ["--shard", config.shard]
    if config.resume_from is not None:
        args += ["--resume-from", str(config.resume_from)]
    for helper in config.harness_helpers:
        args += ["--harness-helper", helper]
    return args


def run_runner(artifacts: RunnerArtifacts, config: PairConfig) -> subprocess.CompletedProcess[str]:
    return run_one_runner(runner_command(artifacts, config), output=artifacts.output)


def assert_same_exit_status(
    label: str,
    python_proc: subprocess.CompletedProcess[str],
    moonbit_proc: subprocess.CompletedProcess[str],
) -> None:
    if python_proc.returncode == moonbit_proc.returncode:
        return
    raise AssertionError(
        "runner exit status mismatch for "
        f"{label}: python={python_proc.returncode}, moonbit={moonbit_proc.returncode}\n"
        f"python stdout:\n{python_proc.stdout}\npython stderr:\n{python_proc.stderr}\n"
        f"moonbit stdout:\n{moonbit_proc.stdout}\nmoonbit stderr:\n{moonbit_proc.stderr}"
    )


def run_unchecked(args: list[str], *, timeout: int = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def assert_runner_error_case(
    label: str,
    common_args: list[str],
    *,
    expected_code: int,
    fragments: Sequence[str],
) -> None:
    py_proc = run_unchecked(runner_base("python") + common_args)
    mb_proc = run_unchecked(runner_base("moonbit") + common_args)
    assert_same_exit_status(label, py_proc, mb_proc)
    if py_proc.returncode != expected_code:
        raise AssertionError(
            f"{label}: expected exit {expected_code}, got {py_proc.returncode}\n"
            + format_process_failure(runner_base("python") + common_args, py_proc)
        )
    for runner, proc in (("python", py_proc), ("moonbit", mb_proc)):
        missing = [fragment for fragment in fragments if fragment not in proc.stderr]
        if missing:
            raise AssertionError(
                f"{label} {runner}: missing diagnostic fragment(s) {missing}\n"
                f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
            )


def run_pair(label: str, config: PairConfig, *, ignore_reason: bool = False) -> PairResult:
    python = RunnerArtifacts.for_run(config.tmp, label, "python")
    moonbit = RunnerArtifacts.for_run(config.tmp, label, "moonbit")
    py_proc = run_runner(python, config)
    mb_proc = run_runner(moonbit, config)
    assert_same_exit_status(label, py_proc, mb_proc)
    compare_artifacts(python.output, moonbit.output, ignore_reason=ignore_reason)
    return PairResult(python=python, moonbit=moonbit, exit_code=py_proc.returncode)


def load_json(path: Path) -> JsonRecord:
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise AssertionError(f"{path} must contain a JSON object")
    return data


def load_jsonl(path: Path) -> list[JsonRecord]:
    if not path.is_file():
        raise AssertionError(f"log file was not created: {path}")
    records: list[JsonRecord] = []
    for index, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        record = json.loads(line)
        if not isinstance(record, dict):
            raise AssertionError(f"{path}:{index} must contain a JSON object")
        records.append(record)
    return records


def artifact_results(path: Path) -> list[JsonRecord]:
    results = load_json(path).get("results")
    if not isinstance(results, list):
        raise AssertionError(f"{path}: results must be an array")
    if not all(isinstance(record, dict) for record in results):
        raise AssertionError(f"{path}: every result must be an object")
    return results


def result_key(record: JsonRecord, compare: ModuleType) -> ResultKey:
    return (compare.normalize_path(record["path"]), record["mode"])


def comparable_records(
    records: list[JsonRecord],
    *,
    label: str,
    compare: ModuleType,
) -> dict[ResultKey, ComparableResult]:
    diffs: list[str] = []
    out: dict[ResultKey, ComparableResult] = {}
    for index, record in enumerate(records):
        cur_diffs: list[str] = []
        compare.validate_result(f"{label}[{index}]", record, cur_diffs)
        if cur_diffs:
            diffs.extend(cur_diffs)
            continue
        key = result_key(record, compare)
        if key in out:
            diffs.append(f"{label}: duplicate key {key[0]} [{key[1]}]")
            continue
        out[key] = (record["status"], record["reason"])
    if diffs:
        raise AssertionError("\n".join(diffs))
    return out


def assert_records_match(
    label: str,
    left: list[JsonRecord],
    right: list[JsonRecord],
    compare: ModuleType,
) -> None:
    left_map = comparable_records(left, label=f"{label}.left", compare=compare)
    right_map = comparable_records(right, label=f"{label}.right", compare=compare)
    if left_map != right_map:
        raise AssertionError(f"{label} records differ:\nleft={left_map}\nright={right_map}")


def assert_log_contract(label: str, artifacts: RunnerArtifacts, compare: ModuleType) -> None:
    results = artifact_results(artifacts.output)
    progress_records = load_jsonl(artifacts.progress_log)
    merged_records = load_jsonl(artifacts.merged_log)
    expected_merged = [record for record in results if record.get("status") in MERGED_LOG_STATUSES]
    assert_records_match(f"{label} progress log", results, progress_records, compare)
    assert_records_match(f"{label} merged log", expected_merged, merged_records, compare)


def artifact_keys(path: Path, compare: ModuleType) -> set[ResultKey]:
    return {result_key(record, compare) for record in artifact_results(path)}


def expected_task_keys(config: PairConfig, support: SupportModules) -> set[ResultKey]:
    test_files = support.task_selection.load_tests_file(str(config.tests_file), str(config.test262))
    if config.filter:
        test_files = [
            path
            for path in test_files
            if config.filter in support.task_selection.normalize_test262_path(path, str(config.test262))
        ]
    tasks = support.task_selection.build_test_tasks(test_files, config.mode)
    shard_spec = support.task_selection.parse_shard_spec(config.shard) if config.shard else None
    tasks, _ = support.task_selection.apply_task_selection(
        tasks,
        shard_spec=shard_spec,
        start=config.start,
        count=config.count,
        resume_from=str(config.resume_from) if config.resume_from is not None else "",
        test262_dir=str(config.test262),
    )
    return {(support.compare.normalize_path(path), mode) for path, mode in tasks}


def assert_expected_keys(label: str, actual: set[ResultKey], expected: set[ResultKey]) -> None:
    if actual != expected:
        raise AssertionError(
            f"{label} task keys differ:\n"
            f"missing={sorted(expected - actual)}\n"
            f"extra={sorted(actual - expected)}"
        )


def assert_pair_contract(label: str, pair: PairResult, expected_keys: set[ResultKey], compare: ModuleType) -> None:
    for artifacts in (pair.python, pair.moonbit):
        assert_expected_keys(f"{label} {artifacts.runner}", artifact_keys(artifacts.output, compare), expected_keys)
        assert_log_contract(f"{label} {artifacts.runner}", artifacts, compare)
    assert_records_match(
        f"{label} progress logs",
        load_jsonl(pair.python.progress_log),
        load_jsonl(pair.moonbit.progress_log),
        compare,
    )


def assert_artifact_statuses(label: str, artifacts: RunnerArtifacts, expected: Sequence[str]) -> None:
    statuses = [record.get("status") for record in artifact_results(artifacts.output)]
    if statuses != list(expected):
        raise AssertionError(f"{label} {artifacts.runner}: statuses {statuses} != {list(expected)}")


def write_synthetic_test(
    test262_root: Path,
    rel: str,
    *,
    frontmatter: str = "description: synthetic",
    body: str = "",
) -> None:
    write_text(test262_root / "test" / rel, "/*---\n" + frontmatter + "\n---*/\n" + body + "\n")


def assert_invalid_cli_parity() -> None:
    cases: tuple[tuple[str, tuple[str, ...], tuple[str, ...]], ...] = (
        ("unknown option", ("--badflag",), ("unrecognized arguments: --badflag",)),
        ("missing --start value", ("--start",), ("argument --start: expected one argument",)),
        ("non-integer --start", ("--start", "nope"), ("argument --start: invalid int value", "nope")),
        ("negative --start", ("--start", "-1"), ("--start must be >= 0",)),
        ("negative --count", ("--count", "-1"), ("--count must be >= 0",)),
        ("bad --shard", ("--shard", "0/2"), ("shard index must be between 1",)),
        (
            "mixed --shard and slice",
            ("--shard", "1/2", "--start", "1"),
            ("--shard cannot be combined with --start/--count",),
        ),
        (
            "bad --mode",
            ("--mode", "weird"),
            ("argument --mode: invalid choice", "weird"),
        ),
        (
            "bad --harness-helper",
            ("--harness-helper", "notAHelper"),
            ("unknown harness helper 'notAHelper'", "codePointRange"),
        ),
    )
    for label, extra_args, fragments in cases:
        assert_runner_error_case(
            f"invalid CLI {label}",
            list(extra_args),
            expected_code=2,
            fragments=fragments,
        )


def assert_bad_path_parity(tmp: Path, anchored_test262: Path, tests_file: Path, engine: Path) -> None:
    common_runtime = [
        "--engine",
        str(engine),
        "--test262",
        path_arg(anchored_test262),
        "--mode",
        "non-strict",
        "--threads",
        "1",
        "--timeout",
        "1",
        "--summary",
    ]
    assert_runner_error_case(
        "missing Test262 directory",
        [
            "--engine",
            str(engine),
            "--test262",
            str(tmp / "missing-test262"),
            "--summary",
            "--output",
            str(tmp / "missing-test262.json"),
        ],
        expected_code=1,
        fragments=("Error: test262 directory not found",),
    )
    assert_runner_error_case(
        "missing --tests-file",
        common_runtime
        + [
            "--tests-file",
            str(tmp / "missing-tests.txt"),
            "--output",
            str(tmp / "missing-tests-file.json"),
        ],
        expected_code=1,
        fragments=("Error: failed to read tests file", "missing-tests.txt"),
    )
    assert_runner_error_case(
        "missing --resume-from",
        common_runtime
        + [
            "--tests-file",
            str(tests_file),
            "--resume-from",
            str(tmp / "missing-resume.json"),
            "--output",
            str(tmp / "missing-resume-file.json"),
        ],
        expected_code=1,
        fragments=("Error: failed to read resume file", "missing-resume.json"),
    )
    bad_log_dir = tmp / "bad-progress-log-dir"
    bad_log_dir.mkdir()
    assert_runner_error_case(
        "bad --log path",
        common_runtime
        + [
            "--tests-file",
            str(tests_file),
            "--count",
            "0",
            "--output",
            str(tmp / "bad-progress-log.json"),
            "--log",
            str(bad_log_dir),
        ],
        expected_code=1,
        fragments=("Error: failed to open result log",),
    )
    bad_merged_log_dir = tmp / "bad-merged-log-dir"
    bad_merged_log_dir.mkdir()
    assert_runner_error_case(
        "bad --merged-log path",
        common_runtime
        + [
            "--tests-file",
            str(tests_file),
            "--count",
            "0",
            "--output",
            str(tmp / "bad-merged-log.json"),
            "--merged-log",
            str(bad_merged_log_dir),
        ],
        expected_code=1,
        fragments=("Error: failed to open result log",),
    )


def assert_modified_harness_metadata(label: str, artifacts: RunnerArtifacts) -> None:
    data = load_json(artifacts.output)
    summary = data.get("summary")
    if not isinstance(summary, dict):
        raise AssertionError(f"{label} {artifacts.runner}: summary must be an object")
    if summary.get("methodology") != "modified harness (helpers: codePointRange)":
        raise AssertionError(f"{label} {artifacts.runner}: missing modified-harness summary label")
    methodology = data.get("methodology")
    if not isinstance(methodology, dict) or methodology.get("harness_helpers") != ["codePointRange"]:
        raise AssertionError(f"{label} {artifacts.runner}: missing codePointRange methodology record")


def run_synthetic_parity(tmp: Path, support: SupportModules) -> None:
    synthetic_root = tmp / "synthetic-test262"
    write_text(synthetic_root / "harness" / "sta.js", "")
    write_text(synthetic_root / "harness" / "assert.js", "")

    selection_tests = (
        "language/selection/keep-a.js",
        "language/selection/keep-b.js",
        "language/selection/drop.js",
        "language/selection/tail.js",
    )
    for rel in selection_tests:
        write_synthetic_test(synthetic_root, rel, body="0;")
    timeout_test = "language/status/timeout.js"
    error_test = "language/status/error.js"
    helper_test = "language/harness/helper.js"
    write_synthetic_test(synthetic_root, timeout_test, body="0;")
    write_synthetic_test(synthetic_root, error_test, body="0;")
    write_synthetic_test(synthetic_root, helper_test, body="0;")

    selection_file = tmp / "synthetic-selection-tests.txt"
    timeout_file = tmp / "synthetic-timeout-tests.txt"
    error_file = tmp / "synthetic-error-tests.txt"
    helper_file = tmp / "synthetic-helper-tests.txt"
    write_tests_file(selection_file, selection_tests)
    write_tests_file(timeout_file, (timeout_test,))
    write_tests_file(error_file, (error_test,))
    write_tests_file(helper_file, (helper_test,))

    pass_engine = tmp / "pass-engine.sh"
    timeout_engine = tmp / "timeout-engine.sh"
    helper_engine = tmp / "helper-engine.sh"
    error_engine_python = tmp / "permission-error-engine-python.sh"
    error_engine_moonbit = tmp / "permission-error-engine-moonbit.sh"
    write_executable(pass_engine, "#!/bin/sh\nexit 0\n")
    write_executable(
        timeout_engine,
        "#!/bin/sh\nif [ \"${1:-}\" = \"1 + 1\" ]; then exit 0; fi\nsleep 2\nexit 0\n",
    )
    write_executable(
        helper_engine,
        (
            "#!/bin/sh\n"
            "if [ \"${1:-}\" = \"1 + 1\" ]; then exit 0; fi\n"
            "last=\"\"\n"
            "for arg in \"$@\"; do last=\"$arg\"; done\n"
            "case \"$last\" in\n"
            "  *'$262.codePointRange'*) exit 0 ;;\n"
            "  *) echo 'Error: missing codePointRange'; exit 1 ;;\n"
            "esac\n"
        ),
    )
    permission_error_engine = (
        "#!/bin/sh\n"
        "if [ \"${1:-}\" = \"1 + 1\" ]; then chmod -x \"$0\"; exit 0; fi\n"
        "exit 0\n"
    )
    write_executable(error_engine_python, permission_error_engine)
    write_executable(error_engine_moonbit, permission_error_engine)

    assert_invalid_cli_parity()
    with python_category_anchor(synthetic_root) as anchored_test262:
        assert_bad_path_parity(tmp, anchored_test262, selection_file, pass_engine)

        selection_base = PairConfig(
            engine=str(pass_engine),
            test262=anchored_test262,
            tests_file=selection_file,
            tmp=tmp,
            mode="non-strict",
        )
        for label, config in (
            ("filter", replace(selection_base, filter="selection/keep")),
            ("slice", replace(selection_base, start=1, count=2)),
            ("shard", replace(selection_base, shard="2/3")),
        ):
            pair = run_pair(label, config)
            assert_pair_contract(label, pair, expected_task_keys(config, support), support.compare)

        timeout_config = PairConfig(
            engine=str(timeout_engine),
            test262=anchored_test262,
            tests_file=timeout_file,
            tmp=tmp,
            mode="non-strict",
            timeout=1,
        )
        timeout_pair = run_pair("timeout", timeout_config)
        assert_pair_contract("timeout", timeout_pair, expected_task_keys(timeout_config, support), support.compare)
        for artifacts in (timeout_pair.python, timeout_pair.moonbit):
            assert_artifact_statuses("timeout", artifacts, ["timeout"])

        error_config = PairConfig(
            engine=str(error_engine_python),
            test262=anchored_test262,
            tests_file=error_file,
            tmp=tmp,
            mode="non-strict",
        )
        error_python = RunnerArtifacts.for_run(tmp, "infrastructure-error", "python")
        error_moonbit = RunnerArtifacts.for_run(tmp, "infrastructure-error", "moonbit")
        py_proc = run_runner(error_python, error_config)
        mb_proc = run_runner(
            error_moonbit,
            replace(error_config, engine=str(error_engine_moonbit)),
        )
        assert_same_exit_status("infrastructure-error", py_proc, mb_proc)
        compare_artifacts(error_python.output, error_moonbit.output, ignore_reason=True)
        error_pair = PairResult(python=error_python, moonbit=error_moonbit, exit_code=py_proc.returncode)
        expected_error = expected_task_keys(error_config, support)
        for artifacts in (error_pair.python, error_pair.moonbit):
            assert_expected_keys(
                f"infrastructure-error {artifacts.runner}",
                artifact_keys(artifacts.output, support.compare),
                expected_error,
            )
            assert_log_contract(f"infrastructure-error {artifacts.runner}", artifacts, support.compare)
            assert_artifact_statuses("infrastructure-error", artifacts, ["error"])

        helper_config = PairConfig(
            engine=str(helper_engine),
            test262=anchored_test262,
            tests_file=helper_file,
            tmp=tmp,
            mode="non-strict",
            harness_helpers=("codePointRange",),
        )
        helper_pair = run_pair("harness-helper", helper_config)
        assert_pair_contract("harness-helper", helper_pair, expected_task_keys(helper_config, support), support.compare)
        for artifacts in (helper_pair.python, helper_pair.moonbit):
            assert_artifact_statuses("harness-helper", artifacts, ["pass"])
            assert_modified_harness_metadata("harness-helper", artifacts)


def run_parity(args: argparse.Namespace) -> None:
    test262_root = (REPO_ROOT / args.test262).resolve()
    if not (test262_root / "test").is_dir():
        raise AssertionError(f"Test262 checkout not found: {test262_root}")
    validate_curated_subset(test262_root)
    build_shadow_executable()
    engine = engine_command(args.engine)
    support = load_support_modules()

    with parity_temp_dir(args.keep_temp) as tmp_dir:
        tests_file = tmp_dir / "curated-tests.txt"
        resume_file = tmp_dir / "resume.json"
        write_tests_file(tests_file)
        write_resume_file(resume_file)

        with python_category_anchor(test262_root) as anchored_test262:
            base_config = PairConfig(engine=engine, test262=anchored_test262, tests_file=tests_file, tmp=tmp_dir)
            expected_full = expected_task_keys(base_config, support)

            full_pair = run_pair("full", base_config)
            assert_pair_contract("full", full_pair, expected_full, support.compare)

            resume_config = replace(base_config, resume_from=resume_file)
            resume_pair = run_pair("resume", resume_config)
            assert_pair_contract("resume", resume_pair, expected_task_keys(resume_config, support), support.compare)
            if resume_pair.exit_code != 0:
                raise AssertionError(
                    f"resume parity slice should have no failed executed tests, got exit {resume_pair.exit_code}"
                )

        run_synthetic_parity(tmp_dir, support)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run deterministic Test262 runner shadow parity slices."
    )
    parser.add_argument("--test262", default="./test262", help="checked-out Test262 directory")
    parser.add_argument(
        "--engine",
        default="",
        help="engine command to pass to both runners (default: build/use JS bundle when node exists)",
    )
    parser.add_argument("--keep-temp", action="store_true", help="keep temporary artifacts for debugging")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    run_parity(parse_args(argv))
    print("ok: MoonBit Test262 runner shadow matches Python on curated, CLI/error, timeout, and selection parity slices")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
