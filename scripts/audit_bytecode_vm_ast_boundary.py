#!/usr/bin/env python3
"""Guard the bytecode VM's executable AST boundary with typed hover checks.

The VM may retain source metadata temporarily, but it must not obtain an
``@ast.Stmt``/``@ast.Pattern`` value or read ``BytecodeFunction.source_body``.
This audit asks MoonBit's IDE for the type at each candidate token, so an
alias such as ``let alias = function; alias.source_body`` is checked by the
resolved type rather than by receiver spelling. The root ``source_stmts``
script envelope remains outside this VM-only scope.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import re
import subprocess
import sys


VM_PATHS = (Path("compiler/bytecode_vm.mbt"),)
FORBIDDEN_MARKERS = ("@ast.Stmt", "@ast.Pattern")
CANDIDATE = re.compile(r"source_body|@ast\.(?:Stmt|Pattern)")
FIXTURE_PATH = Path("compiler/bytecode_vm_ast_boundary_fixture_tmp.mbt")
FIXTURE_SOURCE = r'''///|
#warnings("-unused_value")
fn bytecode_vm_ast_boundary_fixture(
  function : BytecodeFunction,
  stmt : @ast.Stmt,
  pattern : @ast.Pattern,
) -> Unit {
  let retained = function
  for candidate in retained.source_body {
    match candidate {
      _ => ignore(stmt)
    }
  }
  match pattern {
    _ => ()
  }
}
'''


def run(root: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=root,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def hover(root: Path, path: Path, line: int, column: int) -> str | None:
    result = run(
        root,
        "moon",
        "ide",
        "hover",
        "--loc",
        f"{path}:{line}:{column}",
        "--output-json",
        "--no-check",
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        contents = json.loads(result.stdout)["contents"]
    except (KeyError, TypeError, json.JSONDecodeError):
        return None
    return "\n".join(contents)


def typed_ast_accesses(root: Path, paths: tuple[Path, ...]) -> list[dict[str, object]]:
    violations: list[dict[str, object]] = []
    for path in paths:
        lines = (root / path).read_text().splitlines()
        for line_number, line in enumerate(lines, start=1):
            for match in CANDIDATE.finditer(line):
                contents = hover(root, path, line_number, match.start() + 1)
                if contents is None:
                    continue
                marker = next(
                    (candidate for candidate in FORBIDDEN_MARKERS if candidate in contents),
                    None,
                )
                if marker is not None:
                    violations.append(
                        {
                            "path": str(path),
                            "line": line_number,
                            "column": match.start() + 1,
                            "token": match.group(0),
                            "type": marker,
                        }
                    )
    return violations


@contextmanager
def negative_fixture(root: Path):
    path = root / FIXTURE_PATH
    if path.exists():
        raise RuntimeError(f"fixture path already exists: {path}")
    try:
        path.write_text(FIXTURE_SOURCE)
        checked = run(root, "moon", "check", "--deny-warn", check=False)
        if checked.returncode != 0:
            raise RuntimeError(
                "AST boundary negative fixture did not type-check:\n"
                + checked.stdout
                + checked.stderr
            )
        yield
    finally:
        path.unlink(missing_ok=True)
        cleaned = run(root, "moon", "check", "--deny-warn", check=False)
        if cleaned.returncode != 0 and sys.exc_info()[0] is None:
            raise RuntimeError(
                "AST boundary fixture cleanup check failed:\n"
                + cleaned.stdout
                + cleaned.stderr
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    checked = run(root, "moon", "check", "--deny-warn", check=False)
    if checked.returncode != 0:
        print(checked.stdout + checked.stderr, file=sys.stderr)
        return checked.returncode
    violations = typed_ast_accesses(root, VM_PATHS)
    if violations:
        print("bytecode VM executable AST boundary failed:", file=sys.stderr)
        for violation in violations:
            print(json.dumps(violation, sort_keys=True), file=sys.stderr)
        return 1
    if args.self_test:
        with negative_fixture(root):
            fixture_violations = typed_ast_accesses(root, (FIXTURE_PATH,))
        found_types = {item["type"] for item in fixture_violations}
        if not {"@ast.Stmt", "@ast.Pattern"}.issubset(found_types):
            print(
                "AST boundary negative fixture did not resolve both forbidden types: "
                + json.dumps(fixture_violations, sort_keys=True),
                file=sys.stderr,
            )
            return 1
        print("ok: typed bytecode VM AST boundary rejects direct and aliased access")
    else:
        print("ok: typed bytecode VM AST boundary is clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
