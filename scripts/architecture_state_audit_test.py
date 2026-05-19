#!/usr/bin/env python3
"""Tests for the architecture state audit guardrail."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent


def load_audit():
    spec = importlib.util.spec_from_file_location(
        "architecture_state_audit",
        SCRIPT_DIR / "architecture-state-audit.py",
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load architecture-state-audit.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["architecture_state_audit"] = module
    spec.loader.exec_module(module)
    return module


def write_mbt(root: Path, rel_path: str, content: str) -> None:
    path = root / rel_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main() -> int:
    audit = load_audit()

    assert audit.is_mutable_type("Ref[Int]")
    assert audit.is_mutable_type("@ref.Ref[Int]")
    assert audit.is_mutable_type("Ref[@runtime.Value]")
    assert audit.is_mutable_type("Map[String, @ast.Expr]")
    assert audit.is_mutable_type("@immut/hashmap.Map[String, Int]")
    assert audit.is_mutable_type("@immut/hashmap.Map[String, @ast.Expr]")
    assert audit.is_mutable_type("@array.Array[Int]")
    assert audit.is_mutable_type("Option[Ref[Int]]")
    assert audit.is_mutable_type("Result[Array[Int], String]")
    assert audit.is_mutable_type("Option[@ref.Ref[Int]]")
    assert not audit.is_mutable_type("String")
    assert not audit.is_mutable_type("Arrayish[Int]")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_mbt(
            root,
            "interpreter/runtime/qualified.mbt",
            "\n".join(
                [
                    "let cache : @ref.Ref[Int] = { val: 0 }",
                    "pub let table : @immut/hashmap.Map[String, Int] = {}",
                    "pub(all) let public_cache : Ref[Int] = { val: 0 }",
                    "let exprs : Map[String, @ast.Expr] = {}",
                    "let current : Ref[@runtime.Value] = { val: @runtime.Undefined }",
                    "let optional_ref : Option[Ref[Int]] = None",
                    "let result_array : Result[Array[Int], String] = Ok([])",
                    "let wrapped : Map[",
                    "  String,",
                    "  @runtime.Value,",
                    "] = {}",
                    "let fixed : Int = 1",
                ]
            ),
        )
        write_mbt(
            root,
            "interpreter/stdlib/unannotated.mbt",
            "let cache = [0]\n",
        )

        bindings = audit.discover_mutable_bindings(root)
        found = {binding.key: binding for binding in bindings}

        assert set(found) == {
            "interpreter/runtime/qualified.mbt:cache",
            "interpreter/runtime/qualified.mbt:table",
            "interpreter/runtime/qualified.mbt:public_cache",
            "interpreter/runtime/qualified.mbt:exprs",
            "interpreter/runtime/qualified.mbt:current",
            "interpreter/runtime/qualified.mbt:optional_ref",
            "interpreter/runtime/qualified.mbt:result_array",
            "interpreter/runtime/qualified.mbt:wrapped",
            "interpreter/stdlib/unannotated.mbt:cache",
        }
        assert found["interpreter/runtime/qualified.mbt:cache"].type_name == "@ref.Ref[Int]"
        assert not found["interpreter/runtime/qualified.mbt:cache"].is_unannotated
        assert found["interpreter/runtime/qualified.mbt:table"].is_public
        assert found["interpreter/runtime/qualified.mbt:public_cache"].is_public
        assert found["interpreter/runtime/qualified.mbt:wrapped"].line == 8
        assert audit.is_mutable_type(found["interpreter/runtime/qualified.mbt:wrapped"].type_name)
        assert found["interpreter/stdlib/unannotated.mbt:cache"].is_unannotated

    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
