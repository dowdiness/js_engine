#!/usr/bin/env python3
"""Tests for Test262 runner task-list helpers."""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


import test262_task_selection as task_selection


def assert_value_error(fn) -> None:
    try:
        fn()
    except ValueError:
        return
    raise AssertionError("expected ValueError")


def write_test_file(path: Path, frontmatter: str = "description: test") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"/*---\n{frontmatter}\n---*/\n", encoding="utf-8")


def test_slicing_and_shards(runner) -> None:
    tasks = [(f"/suite/test/language/t{i}.js", "strict") for i in range(10)]
    assert runner.slice_tasks(tasks, start=2, count=3) == tasks[2:5]
    assert runner.slice_tasks(tasks, start=8) == tasks[8:]
    assert runner.slice_tasks(tasks, start=20, count=3) == []
    assert runner.slice_tasks(tasks, start=4, count=0) == []
    assert_value_error(lambda: runner.slice_tasks(tasks, start=-1))
    assert_value_error(lambda: runner.slice_tasks(tasks, count=-1))

    assert runner.parse_shard_spec("2/3") == (2, 3)
    assert runner.parse_shard_spec(" 3 / 4 ") == (3, 4)
    assert_value_error(lambda: runner.parse_shard_spec("0/4"))
    assert_value_error(lambda: runner.parse_shard_spec("5/4"))
    assert_value_error(lambda: runner.parse_shard_spec("2-of-4"))

    shards = [runner.shard_tasks(tasks, i, 3) for i in range(1, 4)]
    assert shards == [tasks[:4], tasks[4:7], tasks[7:]]
    assert [task for shard in shards for task in shard] == tasks
    assert runner.shard_bounds(0, 1, 4) == (0, 0)
    assert runner.shard_tasks([], 4, 4) == []
    assert_value_error(lambda: runner.shard_tasks(tasks, 0, 3))

    covered_cases = []
    for total in range(0, 17):
        sample_tasks = [(f"/suite/test/t{i}.js", "strict") for i in range(total)]
        for shard_total in range(1, 8):
            covered_cases.append((total, shard_total))
            all_shards = [
                runner.shard_tasks(sample_tasks, i, shard_total)
                for i in range(1, shard_total + 1)
            ]
            assert [task for shard in all_shards for task in shard] == sample_tasks
            sizes = [len(shard) for shard in all_shards]
            assert sum(sizes) == total
            assert max(sizes) - min(sizes) <= 1
    assert (0, 7) in covered_cases
    assert (16, 1) in covered_cases
    assert (16, 7) in covered_cases


def test_tests_file_parsing(runner) -> None:
    contents = """
# comment
language/expressions/add.js
 test/language/statements/if.js   # inline comment

./language/literals/string.js
"""
    assert runner.parse_tests_file_contents(contents) == [
        "language/expressions/add.js",
        "test/language/statements/if.js",
        "./language/literals/string.js",
    ]

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "test262"
        test_root = root / "test"
        tests_file = Path(tmp) / "tests.txt"
        absolute_entry = test_root / "built-ins" / "Array" / "from.js"
        tests_file.write_text(
            "\n".join(
                [
                    "# explicit local slice",
                    "language/expressions/add.js",
                    "test/language/statements/if.js",
                    "test262/test/built-ins/Promise/all.js",
                    str(absolute_entry),
                ]
            ),
            encoding="utf-8",
        )

        loaded = runner.load_tests_file(str(tests_file), str(root))
        assert loaded == [
            str(test_root / "language" / "expressions" / "add.js"),
            str(test_root / "language" / "statements" / "if.js"),
            str(test_root / "built-ins" / "Promise" / "all.js"),
            str(absolute_entry),
        ]


def test_path_normalization_and_resume(runner) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "test262"
        test_root = root / "test"
        resume_tasks = [
            (str(test_root / "language" / "expressions" / "add.js"), "strict"),
            (str(test_root / "language" / "expressions" / "add.js"), "non-strict"),
            (str(test_root / "language" / "statements" / "if.js"), "strict"),
        ]

        assert runner.normalize_test262_path(
            str(test_root / "language" / "expressions" / "add.js"),
            str(root),
        ) == "language/expressions/add.js"
        assert runner.normalize_test262_path(
            "test262/test/language/expressions/add.js",
            str(root),
        ) == "language/expressions/add.js"
        assert runner.normalize_test262_path(
            "test/language/expressions/add.js",
            str(root),
        ) == "language/expressions/add.js"

        results_file = Path(tmp) / "results.json"
        results_file.write_text(
            json.dumps(
                {
                    "results": [
                        {
                            "path": "test262/test/language/expressions/add.js",
                            "mode": "strict",
                            "status": "pass",
                        },
                        {
                            "path": "language/expressions/add.js",
                            "mode": "non-strict",
                            "status": "fail",
                        },
                        {
                            "path": "language/statements/if.js",
                            "mode": "strict",
                            "status": "running",
                        },
                    ],
                }
            ),
            encoding="utf-8",
        )
        completed = runner.load_completed_task_keys(str(results_file), str(root))
        assert completed == {
            ("language/expressions/add.js", "strict"),
            ("language/expressions/add.js", "non-strict"),
        }
        assert runner.filter_completed_tasks(resume_tasks, completed, str(root)) == [
            (str(test_root / "language" / "statements" / "if.js"), "strict"),
        ]


def test_mode_expansion(runner) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "test262"
        test_root = root / "test"
        normal = test_root / "language" / "normal.js"
        raw = test_root / "language" / "raw.js"
        module = test_root / "language" / "module.js"
        only_strict = test_root / "language" / "only-strict.js"
        no_strict = test_root / "language" / "no-strict.js"
        missing = test_root / "language" / "missing.js"

        write_test_file(normal)
        write_test_file(raw, "flags: [raw]")
        write_test_file(module, "flags: [module]")
        write_test_file(only_strict, "flags: [onlyStrict]")
        write_test_file(no_strict, "flags: [noStrict]")

        test_files = [str(normal), str(raw), str(module), str(only_strict), str(no_strict), str(missing)]
        assert runner.build_test_tasks(test_files, "both") == [
            (str(normal), "non-strict"),
            (str(normal), "strict"),
            (str(raw), "non-strict"),
            (str(module), "non-strict"),
            (str(only_strict), "strict"),
            (str(no_strict), "non-strict"),
            (str(missing), "non-strict"),
            (str(missing), "strict"),
        ]
        assert runner.build_test_tasks(test_files, "strict") == [
            (str(normal), "strict"),
            (str(only_strict), "strict"),
            (str(missing), "strict"),
        ]
        assert runner.build_test_tasks(test_files, "non-strict") == [
            (str(normal), "non-strict"),
            (str(raw), "non-strict"),
            (str(module), "non-strict"),
            (str(no_strict), "non-strict"),
            (str(missing), "non-strict"),
        ]


def test_apply_task_selection(runner) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "test262"
        test_root = root / "test"
        tasks = [(str(test_root / "language" / f"t{i}.js"), "strict") for i in range(10)]

        selected, messages = runner.apply_task_selection(tasks, shard_spec=(2, 3))
        assert selected == tasks[4:7]
        assert messages == ["Selected shard 2/3: tasks 4:7 (3/10)"]

        selected, messages = runner.apply_task_selection(tasks, start=8, count=1)
        assert selected == tasks[8:9]
        assert messages == ["Selected task slice: start=8, count=1 (1/10)"]

        results_file = Path(tmp) / "results.json"
        results_file.write_text(
            json.dumps(
                {
                    "results": [
                        {"path": "language/t0.js", "mode": "strict", "status": "pass"},
                        {"path": "language/t1.js", "mode": "strict", "status": "timeout"},
                    ],
                }
            ),
            encoding="utf-8",
        )
        selected, messages = runner.apply_task_selection(
            tasks[:3], resume_from=str(results_file), test262_dir=str(root)
        )
        assert selected == [tasks[2]]
        assert messages == [f"Resume: skipped 2 completed task(s) from {results_file}"]


def main() -> int:
    runner = task_selection
    test_slicing_and_shards(runner)
    test_tests_file_parsing(runner)
    test_path_normalization_and_resume(runner)
    test_mode_expansion(runner)
    test_apply_task_selection(runner)
    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
