#!/usr/bin/env python3
"""
Audit module-level mutable runtime/stdlib state.

This is a Stage 0 guardrail for the realm-state migration track. It does not
claim the currently-classified globals are good architecture; it prevents new
ambient mutable state from being added without an explicit classification.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
import re


SCAN_DIRS = (
    "interpreter/runtime",
    "interpreter/stdlib",
)

MUTABLE_TYPE_CONSTRUCTORS = (
    "Ref",
    "Map",
    "Array",
)

TYPE_CONSTRUCTOR_RE = re.compile(
    r"(?<![A-Za-z0-9_])"
    r"(?P<constructor>(?:@[A-Za-z0-9_./-]+\.)?[A-Za-z_][A-Za-z0-9_]*)\["
)

MODULE_LET_START_RE = re.compile(
    r"^(?P<visibility>pub(?:\([^)]*\))?\s+)?let\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b"
    r"(?P<rest>.*)$"
)


# Known ambient mutable state as of 2026-05-19. These entries are the migration
# inventory for Stage 1+. Adding a new entry here should be reviewed as an
# architecture decision, not as routine test maintenance.
CLASSIFIED_MUTABLE_STATE: dict[str, str] = {
    "interpreter/runtime/conversions.mbt:current_interpreter": (
        "temporary current-interpreter fallback; replace with explicit context"
    ),
    "interpreter/runtime/symbols.mbt:is_constructing": (
        "ambient construction context; replace with explicit call/construct context"
    ),
    "interpreter/stdlib/builtins_arraybuffer.mbt:arraybuffer_id_counter": (
        "ArrayBuffer backing-store counter; move to RealmState"
    ),
    "interpreter/stdlib/builtins_arraybuffer.mbt:arraybuffer_store": (
        "ArrayBuffer backing store; move to RealmState"
    ),
    "interpreter/stdlib/builtins_arraybuffer.mbt:detached_buffers": (
        "ArrayBuffer detached-state store; move to RealmState"
    ),
}


@dataclass(frozen=True)
class MutableBinding:
    key: str
    path: str
    line: int
    name: str
    type_name: str
    is_public: bool
    is_unannotated: bool


def is_mutable_type(type_name: str) -> bool:
    normalized = re.sub(r"\s+", "", type_name.strip())
    for match in TYPE_CONSTRUCTOR_RE.finditer(normalized):
        constructor = match.group("constructor")
        unqualified = constructor.rsplit(".", 1)[-1]
        if unqualified in MUTABLE_TYPE_CONSTRUCTORS:
            return True
    return False


def parse_module_let(lines: list[str], start: int) -> MutableBinding | None:
    line = lines[start]
    match = MODULE_LET_START_RE.match(line)
    if match is None:
        return None

    declaration = match.group("rest")
    end = start
    while "=" not in declaration and end + 1 < len(lines):
        end += 1
        declaration += "\n" + lines[end]

    before_initializer = declaration.split("=", 1)[0]
    name = match.group("name")
    raw_type: str | None = None
    if ":" in before_initializer:
        raw_type = before_initializer.split(":", 1)[1].strip()

    if raw_type is None:
        type_name = "<unannotated>"
        is_unannotated = True
    else:
        type_name = raw_type
        is_unannotated = False

    if not is_unannotated and not is_mutable_type(type_name):
        return None

    return MutableBinding(
        key="",
        path="",
        line=start + 1,
        name=name,
        type_name=type_name,
        is_public=match.group("visibility") is not None,
        is_unannotated=is_unannotated,
    )


def discover_mutable_bindings(repo_root: Path) -> list[MutableBinding]:
    bindings: list[MutableBinding] = []
    for scan_dir in SCAN_DIRS:
        root = repo_root / scan_dir
        for path in sorted(root.glob("*.mbt")):
            rel_path = path.relative_to(repo_root).as_posix()
            lines = path.read_text(encoding="utf-8").splitlines()
            for index in range(len(lines)):
                binding = parse_module_let(lines, index)
                if binding is None:
                    continue
                bindings.append(
                    MutableBinding(
                        key=f"{rel_path}:{binding.name}",
                        path=rel_path,
                        line=binding.line,
                        name=binding.name,
                        type_name=binding.type_name,
                        is_public=binding.is_public,
                        is_unannotated=binding.is_unannotated,
                    )
                )
    return bindings


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Check runtime/stdlib module-level mutable state against the "
            "Stage 0 architecture migration inventory."
        )
    )
    parser.add_argument(
        "--root",
        default=".",
        help="Repository root to scan (default: current directory)",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="Print the classified mutable state inventory.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    repo_root = Path(args.root).resolve()
    bindings = discover_mutable_bindings(repo_root)
    found = {binding.key: binding for binding in bindings}

    if args.list:
        for binding in bindings:
            public = "pub " if binding.is_public else ""
            reason = CLASSIFIED_MUTABLE_STATE.get(binding.key, "UNCLASSIFIED")
            print(
                f"{binding.path}:{binding.line}: {public}{binding.name}: "
                f"{binding.type_name} -- {reason}"
            )

    unannotated = [binding for binding in bindings if binding.is_unannotated]
    unclassified = [
        binding
        for binding in bindings
        if not binding.is_unannotated and binding.key not in CLASSIFIED_MUTABLE_STATE
    ]
    stale = sorted(set(CLASSIFIED_MUTABLE_STATE) - set(found))

    if unannotated or unclassified or stale:
        print("architecture state audit failed:", file=sys.stderr)
        if unannotated:
            print("\nunannotated module-level let bindings:", file=sys.stderr)
            for binding in unannotated:
                public = "pub " if binding.is_public else ""
                print(
                    f"- {binding.path}:{binding.line}: {public}{binding.name}",
                    file=sys.stderr,
                )
            print(
                "  Use const for fixed values, or add an explicit type so "
                "mutable state cannot be hidden by inference.",
                file=sys.stderr,
            )
        if unclassified:
            print("\nunclassified module-level mutable state:", file=sys.stderr)
            for binding in unclassified:
                public = "pub " if binding.is_public else ""
                print(
                    f"- {binding.path}:{binding.line}: {public}{binding.name}: "
                    f"{binding.type_name}",
                    file=sys.stderr,
                )
        if stale:
            print("\nstale classified entries:", file=sys.stderr)
            for key in stale:
                print(f"- {key}", file=sys.stderr)
        print(
            "\nClassify intentionally retained state in "
            "CLASSIFIED_MUTABLE_STATE, or move it behind Interpreter/HostEnv/"
            "RealmState ownership.",
            file=sys.stderr,
        )
        return 1

    print(
        "ok: runtime/stdlib module-level mutable state matches the "
        f"Stage 0 migration inventory ({len(bindings)} classified bindings)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
