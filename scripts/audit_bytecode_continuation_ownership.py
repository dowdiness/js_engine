#!/usr/bin/env python3
"""Keep bytecode continuation publication and consumption single-owner."""

from __future__ import annotations

import argparse
from pathlib import Path
import re


VM_PATH = Path("compiler/bytecode_vm.mbt")
WRITE = re.compile(r"\b(self|frame)\.pending_continuation\s*=\s*(Some\(|None\b)")
FUNCTION = re.compile(r"^fn\s+([^\s(]+)|\bwith fn\s+([^\s(]+)")


def enclosing_function(lines: list[str], index: int) -> str:
    for line in reversed(lines[: index + 1]):
        match = FUNCTION.search(line.strip())
        if match:
            return match.group(1) or match.group(2)
    return "<toplevel>"


def ownership_violations(source: str) -> list[str]:
    lines = source.splitlines()
    writes: list[tuple[int, str, str, str]] = []
    for index, line in enumerate(lines):
        match = WRITE.search(line)
        if match:
            writes.append(
                (
                    index + 1,
                    enclosing_function(lines, index),
                    match.group(1),
                    match.group(2),
                ),
            )

    violations: list[str] = []
    expected = {
        ("BytecodeFrame::publish_suspension", "self", "Some("),
        ("deliver_activation_completion", "self", "None"),
    }
    actual = {(function, receiver, value) for _, function, receiver, value in writes}
    for line, function, receiver, value in writes:
        if (function, receiver, value) not in expected:
            violations.append(
                f"line {line}: continuation write outside its owner: "
                f"{function} ({receiver} = {value})",
            )
    for missing in sorted(expected - actual):
        violations.append(
            "missing continuation owner write: " + " / ".join(missing),
        )
    if len(writes) != len(expected):
        violations.append(
            f"expected exactly {len(expected)} continuation writes, found {len(writes)}",
        )
    if "pending_activation_result" in source:
        violations.append("legacy pending_activation_result storage remains")
    return violations


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()

    violations = ownership_violations((root / VM_PATH).read_text())
    if violations:
        print("bytecode continuation ownership audit failed:")
        for violation in violations:
            print(f"  {violation}")
        return 1

    if args.self_test:
        good = """
fn BytecodeFrame::publish_suspension(self : BytecodeFrame) {
  self.pending_continuation = Some(suspension.continuation)
}
impl Trait for BytecodeFrame with fn deliver_activation_completion(self) {
  self.pending_continuation = None
}
"""
        bad = good + """
fn BytecodeFrame::step_bytecode(frame : BytecodeFrame) {
  frame.pending_continuation = Some(PushValue)
}
"""
        if ownership_violations(good):
            print("continuation ownership audit rejected its positive fixture")
            return 1
        if not ownership_violations(bad):
            print("continuation ownership audit accepted a direct VM write")
            return 1
        print(
            "ok: bytecode continuation ownership has one publisher and one consumer",
        )
    else:
        print("ok: bytecode continuation ownership is clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
