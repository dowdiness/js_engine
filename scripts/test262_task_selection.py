"""Task-list and resume helpers for scripts/test262-runner.py.

The runner expands each Test262 file into one or more ``(path, mode)`` tasks.
This module keeps that pure-ish selection logic separate from engine execution
and reporting so it can be tested without invoking the JavaScript engine.
"""

from __future__ import annotations

import json
import os
import re
from typing import Optional

from test262_utils import as_list, parse_yaml_frontmatter


FINISHED_RESULT_STATUSES = {"pass", "fail", "skip", "timeout", "error"}


def parse_tests_file_contents(contents: str) -> list[str]:
    """Return non-empty test entries from a tests-file body.

    Lines beginning with ``#`` are comments. Inline comments are also allowed
    because Test262 paths do not use ``#``.
    """
    entries = []
    for raw_line in contents.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "#" in line:
            line = line.split("#", 1)[0].rstrip()
        if line:
            entries.append(line)
    return entries


def resolve_test_entry(entry: str, test262_dir: str) -> str:
    """Resolve a tests-file entry to a concrete filesystem path.

    Relative entries default to paths under ``<test262_dir>/test``. Entries
    starting with ``test/`` are resolved under ``test262_dir``; absolute paths
    are normalized and returned unchanged.
    """
    entry = entry.strip()
    if not entry:
        raise ValueError("empty Test262 test entry")
    if os.path.isabs(entry):
        return os.path.normpath(entry)

    normalized = os.path.normpath(entry)
    slash_path = normalized.replace("\\", "/")
    if slash_path.startswith("test262/test/"):
        suffix = slash_path[len("test262/test/") :]
        return os.path.abspath(os.path.join(test262_dir, "test", suffix))
    if slash_path.startswith("test/"):
        return os.path.abspath(os.path.join(test262_dir, normalized))
    return os.path.abspath(os.path.join(test262_dir, "test", normalized))


def load_tests_file(tests_file: str, test262_dir: str) -> list[str]:
    """Load an explicit test file list, preserving the file's order."""
    with open(tests_file, "r", encoding="utf-8") as f:
        entries = parse_tests_file_contents(f.read())
    return [resolve_test_entry(entry, test262_dir) for entry in entries]


def slice_tasks(
    tasks: list[tuple[str, str]],
    start: int = 0,
    count: Optional[int] = None,
) -> list[tuple[str, str]]:
    """Return a contiguous 0-based slice of expanded ``(test, mode)`` tasks."""
    if start < 0:
        raise ValueError("task slice start must be >= 0")
    if count is not None and count < 0:
        raise ValueError("task slice count must be >= 0")
    end = None if count is None else start + count
    return list(tasks[start:end])


def parse_shard_spec(spec: str) -> tuple[int, int]:
    """Parse a user-facing 1-based shard spec of the form ``i/n``."""
    match = re.fullmatch(r"\s*(\d+)\s*/\s*(\d+)\s*", spec)
    if match is None:
        raise ValueError("shard must use i/n syntax, for example 2/8")
    shard_index = int(match.group(1))
    shard_total = int(match.group(2))
    if shard_total <= 0:
        raise ValueError("shard total must be > 0")
    if shard_index <= 0 or shard_index > shard_total:
        raise ValueError("shard index must be between 1 and shard total")
    return shard_index, shard_total


def shard_bounds(total_tasks: int, shard_index: int, shard_total: int) -> tuple[int, int]:
    """Return the half-open task bounds for a balanced contiguous shard."""
    if total_tasks < 0:
        raise ValueError("total task count must be >= 0")
    if shard_total <= 0:
        raise ValueError("shard total must be > 0")
    if shard_index <= 0 or shard_index > shard_total:
        raise ValueError("shard index must be between 1 and shard total")

    base, remainder = divmod(total_tasks, shard_total)
    start = (shard_index - 1) * base + min(shard_index - 1, remainder)
    end = start + base + (1 if shard_index <= remainder else 0)
    return start, end


def shard_tasks(
    tasks: list[tuple[str, str]],
    shard_index: int,
    shard_total: int,
) -> list[tuple[str, str]]:
    """Return the task subset for a 1-based balanced contiguous shard."""
    start, end = shard_bounds(len(tasks), shard_index, shard_total)
    return list(tasks[start:end])


def normalize_test262_path(path: str, test262_dir: str = "") -> str:
    """Return a stable slash-separated path relative to ``test262/test`` when possible."""
    raw = path.strip()
    if not raw:
        return ""

    if test262_dir:
        test_root = os.path.abspath(os.path.join(test262_dir, "test"))
        candidate = raw if os.path.isabs(raw) else os.path.abspath(raw)
        try:
            rel = os.path.relpath(candidate, test_root)
        except ValueError:
            rel = ""
        if rel and rel != os.pardir and not rel.startswith(os.pardir + os.sep):
            return rel.replace(os.sep, "/")

    normalized = os.path.normpath(raw).replace("\\", "/")
    if normalized.startswith("./"):
        normalized = normalized[2:]
    for prefix in ("test262/test/", "test/"):
        if normalized.startswith(prefix):
            return normalized[len(prefix) :]
    marker = "/test262/test/"
    marker_index = normalized.find(marker)
    if marker_index >= 0:
        return normalized[marker_index + len(marker) :]
    return normalized


def task_key(task: tuple[str, str], test262_dir: str = "") -> tuple[str, str]:
    """Return the stable resume key for an expanded ``(test_path, mode)`` task."""
    test_path, mode = task
    return (normalize_test262_path(test_path, test262_dir), mode)


def load_completed_task_keys(
    results_file: str,
    test262_dir: str = "",
) -> set[tuple[str, str]]:
    """Load completed task keys from a runner JSON results file."""
    with open(results_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    results = data.get("results", []) if isinstance(data, dict) else []
    completed = set()
    for record in results:
        if not isinstance(record, dict):
            continue
        if record.get("status") not in FINISHED_RESULT_STATUSES:
            continue
        path = record.get("path")
        if not path:
            continue
        mode = record.get("mode", "non-strict")
        completed.add((normalize_test262_path(str(path), test262_dir), str(mode)))
    return completed


def filter_completed_tasks(
    tasks: list[tuple[str, str]],
    completed_keys: set[tuple[str, str]],
    test262_dir: str = "",
) -> list[tuple[str, str]]:
    """Drop tasks whose stable ``(path, mode)`` key is already completed."""
    return [task for task in tasks if task_key(task, test262_dir) not in completed_keys]


def modes_for_metadata_flags(flags: list, run_mode: str) -> list[str]:
    """Return the modes for one readable test file, preserving runner semantics."""
    if "raw" in flags or "module" in flags:
        return ["non-strict"] if run_mode != "strict" else []
    if "onlyStrict" in flags:
        return ["strict"] if run_mode != "non-strict" else []
    if "noStrict" in flags:
        return ["non-strict"] if run_mode != "strict" else []
    return default_modes_for_run_mode(run_mode)


def default_modes_for_run_mode(run_mode: str) -> list[str]:
    """Return normal strict/non-strict modes for a test without mode flags."""
    modes = []
    if run_mode in ("both", "non-strict"):
        modes.append("non-strict")
    if run_mode in ("both", "strict"):
        modes.append("strict")
    return modes


def metadata_flags_for_test(test_file: str) -> list:
    """Read Test262 metadata flags from one file."""
    with open(test_file, "r", encoding="utf-8") as f:
        source = f.read()
    data = parse_yaml_frontmatter(source)
    if data is None:
        return []
    return as_list(data.get("flags", []))


def build_test_tasks(test_files: list[str], run_mode: str) -> list[tuple[str, str]]:
    """Expand discovered files into ``(test_file, mode)`` tasks."""
    test_tasks = []
    for test_file in test_files:
        try:
            modes = modes_for_metadata_flags(metadata_flags_for_test(test_file), run_mode)
        except Exception:
            modes = default_modes_for_run_mode(run_mode)
        for mode in modes:
            test_tasks.append((test_file, mode))
    return test_tasks


def apply_task_selection(
    test_tasks: list[tuple[str, str]],
    shard_spec: Optional[tuple[int, int]] = None,
    start: int = 0,
    count: Optional[int] = None,
    resume_from: str = "",
    test262_dir: str = "",
) -> tuple[list[tuple[str, str]], list[str]]:
    """Apply shard/slice/resume selection and return status messages."""
    selected_tasks = list(test_tasks)
    messages = []

    if shard_spec is not None:
        shard_index, shard_total = shard_spec
        slice_start, slice_end = shard_bounds(len(selected_tasks), shard_index, shard_total)
        before_count = len(selected_tasks)
        selected_tasks = slice_tasks(
            selected_tasks,
            start=slice_start,
            count=slice_end - slice_start,
        )
        messages.append(
            f"Selected shard {shard_index}/{shard_total}: "
            f"tasks {slice_start}:{slice_end} ({len(selected_tasks)}/{before_count})"
        )
    elif start != 0 or count is not None:
        before_count = len(selected_tasks)
        selected_tasks = slice_tasks(selected_tasks, start=start, count=count)
        count_label = "remaining" if count is None else str(count)
        messages.append(
            f"Selected task slice: start={start}, count={count_label} "
            f"({len(selected_tasks)}/{before_count})"
        )

    if resume_from:
        completed_keys = load_completed_task_keys(resume_from, test262_dir)
        before_count = len(selected_tasks)
        selected_tasks = filter_completed_tasks(selected_tasks, completed_keys, test262_dir)
        messages.append(
            f"Resume: skipped {before_count - len(selected_tasks)} completed task(s) "
            f"from {resume_from}"
        )

    return selected_tasks, messages
