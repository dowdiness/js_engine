#!/usr/bin/env python3
"""
Shared Test262 skip metadata for js_engine tooling.

This module has no runner side effects. It contains only the skip constants and
pure metadata classification used by scripts/test262-runner.py and
scripts/test262-analyze.py.
"""

from __future__ import annotations

from collections.abc import Iterable


SKIP_FEATURES = {
    # Features this engine definitely doesn't support yet

    # Async / Promises (async-iteration still unsupported)
    "async-iteration",
    "top-level-await",

    # Classes (advanced features not yet supported)
    "class-fields-private",
    "class-methods-private", "class-static-fields-private",
    "class-static-methods-private",
    "class-static-block",

    # Iteration / ordering
    "for-in-order",
    "iterator-helpers", "iterator-sequencing", "joint-iteration",
    "set-methods",

    # Collections
    "WeakRef",

    # Typed arrays and buffers (partially supported)
    "SharedArrayBuffer", "Float16Array", "Atomics",
    "resizable-arraybuffer", "arraybuffer-transfer", "immutable-arraybuffer",

    # Tail calls
    "tail-call-optimization",

    # Modules / dynamic import
    "import.meta", "dynamic-import",
    "json-modules", "import-assertions", "import-attributes",
    "source-phase-imports", "source-phase-imports-module-source",

    # RegExp advanced features
    "regexp-lookbehind", "regexp-unicode-property-escapes",
    "regexp-match-indices", "regexp-v-flag",
    "regexp-modifiers",
    "RegExp.escape",

    # Missing operators and syntax
    "hashbang",

    # Intl / locale
    "Intl", "intl-normative-optional",

    # Other missing features
    "FinalizationRegistry",
    "BigInt",
    "IsHTMLDDA",
    "cross-realm",
    "caller",
    "Temporal", "ShadowRealm",
    "decorators",
    "explicit-resource-management",
    "json-parse-with-source",

    # Removed in Phase 2+3 (now supported): arrow-function, template, let,
    # const, destructuring-binding, destructuring-assignment,
    # default-parameters, for-of, Object.entries, Array.prototype.flat,
    # Array.prototype.flatMap, Array.prototype.includes
    # Removed in Phase 3.6+4 (now supported): class, numeric-separator-literal,
    # logical-assignment-operators
    # Removed in Phase 6 (now supported): regexp-dotall, async-functions,
    # promise-with-resolvers, promise-try
    # Removed in Phase 5 (now supported): Promise, Promise.allSettled,
    # Promise.any, Promise.prototype.finally, Object.fromEntries, Object.is,
    # Object.hasOwn, Array.from, Array.prototype.at,
    # String.prototype.replaceAll, String.prototype.isWellFormed,
    # String.prototype.toWellFormed, change-array-by-copy,
    # array-find-from-last, string-trimming, new.target,
    # object-spread, object-rest
}


SKIP_FLAGS = {"CanBlockIsFalse", "CanBlockIsTrue"}


# Tests that depend on unsupported runtime features but don't declare
# corresponding Test262 `features` metadata.
SKIP_PATH_SUFFIXES = {
}


def skip_reason(
    filepath: str,
    features: Iterable[str] = (),
    flags: Iterable[str] = (),
    mode: str | None = None,
) -> str | None:
    """Return the metadata skip reason, or None if metadata does not skip it.

    `mode` should be "strict" or "non-strict" for runner execution. Pass None
    for analyzer-style file census where onlyStrict/noStrict do not imply that
    the file is globally inapplicable.
    """
    features = list(features)
    flags = list(flags)

    if "_FIXTURE" in filepath:
        return "fixture file"

    normalized_path = filepath.replace("\\", "/")
    for suffix, reason in SKIP_PATH_SUFFIXES.items():
        if normalized_path.endswith(suffix):
            return reason

    for flag in flags:
        if flag in SKIP_FLAGS:
            return f"unsupported flag: {flag}"

    if mode == "non-strict" and "onlyStrict" in flags:
        return "requires strict mode"
    if mode == "strict" and "noStrict" in flags:
        return "cannot run in strict mode"

    for feature in features:
        if feature in SKIP_FEATURES:
            return f"unsupported feature: {feature}"

    return None
