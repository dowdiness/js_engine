#!/usr/bin/env python3
"""Verify that the runtime destructuring plan is opaque to compiler consumers."""

from __future__ import annotations

import re
from pathlib import Path
import subprocess
import sys


INTERFACE = Path("interpreter/runtime/pkg.generated.mbti")
FIXTURE = Path("compiler/destructure_plan_visibility_fixture_tmp.mbt")

FIXTURE_SOURCE = """///|
#warnings("-unused_value")
fn destructure_plan_visibility_fixture_tmp(
  plan : @runtime.DestructurePlan,
  property : @runtime.DestructurePropertyPlan,
) -> Unit {
  ignore(plan.node)
  ignore(property.key)
}
"""

REQUIRED_SIGNATURES = (
    "pub fn destructure_plan_array(Array[DestructurePlan?], DestructurePlan?) -> DestructurePlan",
    "pub fn destructure_plan_bind_name(String) -> DestructurePlan",
    "pub fn destructure_plan_object(Array[DestructurePropertyPlan], DestructurePlan?) -> DestructurePlan",
    "pub fn destructure_plan_property(String, DestructurePlan) -> DestructurePropertyPlan",
    "pub fn Interpreter::eval_destructure_assign_plan(Self, ExecContext, DestructurePlan, Value, Environment) -> Value raise",
)


def run(root: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=root,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def assert_interface(root: Path) -> None:
    interface = (root / INTERFACE).read_text()
    for type_name in ("DestructurePlan", "DestructurePropertyPlan"):
        block = re.search(
            rf"pub struct {type_name} \{{\n  // private fields\n\}}",
            interface,
        )
        if block is None:
            raise RuntimeError(f"{type_name} is not opaque in {INTERFACE}")
    if "pub enum DestructurePlanNode" in interface:
        raise RuntimeError("DestructurePlanNode leaked through generated interface")
    for signature in REQUIRED_SIGNATURES:
        if signature not in interface:
            raise RuntimeError(f"missing public destructuring-plan API: {signature}")


def assert_consumer_cannot_access_fields(root: Path) -> None:
    if FIXTURE.exists():
        raise RuntimeError(f"fixture already exists: {FIXTURE}")
    path = root / FIXTURE
    try:
        path.write_text(FIXTURE_SOURCE)
        result = run(root, "moon", "check", "--deny-warn", check=False)
        if result.returncode == 0:
            raise RuntimeError(
                "external compiler consumer unexpectedly accessed private "
                "destructuring-plan fields"
            )
        output = result.stdout + result.stderr
        for field in ("node", "key"):
            if field not in output:
                raise RuntimeError(
                    f"compiler boundary failure did not mention private field {field}: "
                    + output
                )
    finally:
        path.unlink(missing_ok=True)
    cleaned = run(root, "moon", "check", "--deny-warn", check=False)
    if cleaned.returncode != 0:
        raise RuntimeError(
            "compiler package did not recover after boundary fixture cleanup:\n"
            + cleaned.stdout
            + cleaned.stderr
        )


def main() -> int:
    root = Path(".").resolve()
    try:
        assert_interface(root)
        assert_consumer_cannot_access_fields(root)
        print("ok: destructuring plan interface is opaque to compiler consumers")
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"destructuring plan interface audit failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
