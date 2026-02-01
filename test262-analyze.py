#!/usr/bin/env python3
"""
Test262 Static Conformance Analysis for the MoonBit JS Engine.

Analyzes Test262 test files against the known capabilities of the engine
to produce conformance metrics without requiring the engine to be compiled.

This is useful for:
- Understanding how many tests are applicable to the engine's feature set
- Identifying which test categories the engine should target next
- Getting a baseline measurement before running actual tests

Usage:
    python3 test262-analyze.py [--test262 DIR] [--output FILE]
"""

import argparse
import json
import os
import re
import sys
import time
import yaml
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

YAML_PATTERN = re.compile(r'/\*---(.*?)---\*/', re.DOTALL)

# ===========================================================================
# Engine capability model
# ===========================================================================

# Features the engine DOES support (based on source code analysis)
SUPPORTED_FEATURES = {
    # Basics
    "numeric_literals",
    "string_literals",
    "boolean_literals",
    "null_literal",
    "undefined_value",

    # Variables
    "var_declaration",
    "let_declaration",
    "const_declaration",

    # Operators
    "arithmetic_operators",     # + - * / %
    "comparison_operators",     # < > <= >=
    "equality_operators",       # == === != !==
    "logical_operators",        # && || !
    "unary_operators",          # - ! typeof
    "ternary_operator",         # ? :
    "assignment_operator",      # =

    # Control flow
    "if_else",
    "while_loop",
    "for_loop",
    "break_continue",
    "return_statement",

    # Functions
    "function_declaration",
    "function_expression",
    "closures",
    "recursion",

    # Other
    "block_scoping",
    "comments",                 # // and /* */
    "console_log",
    "string_concatenation",
    "type_coercion_basic",
    "typeof_operator",
}

# Test262 features that map to engine capabilities
# If a test requires NONE of the listed features OR only supported features,
# the engine could potentially handle it.
FEATURE_SUPPORT_MAP = {
    # Features we can handle (test262 feature name -> supported)
    # Empty = no special features needed, just basic JS
}

# Test262 features the engine definitely cannot handle
UNSUPPORTED_TEST262_FEATURES = {
    "Symbol", "Symbol.iterator", "Symbol.hasInstance", "Symbol.species",
    "Symbol.toPrimitive", "Symbol.toStringTag", "Symbol.asyncIterator",
    "Symbol.match", "Symbol.replace", "Symbol.search", "Symbol.split",
    "Symbol.prototype.description",
    "well-known-symbol",

    "Promise", "Promise.allSettled", "Promise.any", "Promise.prototype.finally",
    "promise-with-resolvers", "promise-try",
    "async-functions", "async-iteration", "top-level-await",

    "generators",

    "class", "class-fields-private", "class-fields-public",
    "class-methods-private", "class-static-fields-private",
    "class-static-fields-public", "class-static-methods-private",
    "class-static-block",

    "computed-property-names",
    "destructuring-binding", "destructuring-assignment",
    "default-parameters", "rest-parameters",

    "for-of", "for-in-order",
    "Map", "Set", "WeakMap", "WeakSet", "WeakRef",
    "Proxy", "Reflect",

    "ArrayBuffer", "SharedArrayBuffer", "DataView",
    "TypedArray", "Float16Array", "Atomics",
    "resizable-arraybuffer", "arraybuffer-transfer",

    "arrow-function",
    "template",

    "tail-call-optimization",
    "import.meta", "dynamic-import",
    "import-assertions", "import-attributes",
    "json-modules",

    "regexp-lookbehind", "regexp-named-groups",
    "regexp-unicode-property-escapes",
    "regexp-match-indices", "regexp-v-flag", "regexp-dotall",
    "String.prototype.matchAll",

    "Object.fromEntries", "Object.is", "Object.entries",
    "Object.hasOwn",
    "Array.prototype.flat", "Array.prototype.flatMap",
    "Array.prototype.includes", "Array.from",
    "Array.prototype.at",

    "Intl", "intl-normative-optional",
    "globalThis",
    "optional-chaining", "nullish-coalescing",
    "numeric-separator-literal",
    "logical-assignment-operators",
    "FinalizationRegistry",
    "BigInt",
    "IsHTMLDDA",
    "cross-realm",
    "caller",
    "Temporal", "ShadowRealm",
    "decorators",
    "iterator-helpers", "set-methods",
    "explicit-resource-management",
    "source-phase-imports", "source-phase-imports-module-source",
    "change-array-by-copy",
    "hashbang",
    "String.prototype.isWellFormed",
    "String.prototype.toWellFormed",
    "json-parse-with-source",
    "RegExp.escape",
    "Uint8Array",
}

UNSUPPORTED_FLAGS = {"module", "async", "CanBlockIsFalse", "CanBlockIsTrue"}

# Test262 categories that map well to engine capabilities
CATEGORY_ANALYSIS = {
    "language/literals/null": {
        "relevance": "high",
        "notes": "Engine supports null literals",
    },
    "language/literals/boolean": {
        "relevance": "high",
        "notes": "Engine supports boolean literals",
    },
    "language/literals/numeric": {
        "relevance": "high",
        "notes": "Engine supports numeric literals (IEEE 754 doubles)",
    },
    "language/literals/string": {
        "relevance": "medium",
        "notes": "Engine supports basic string literals, but may not handle all escape sequences",
    },
    "language/expressions/addition": {
        "relevance": "high",
        "notes": "Engine supports + operator with type coercion",
    },
    "language/expressions/subtraction": {
        "relevance": "high",
        "notes": "Engine supports - operator",
    },
    "language/expressions/multiplication": {
        "relevance": "high",
        "notes": "Engine supports * operator",
    },
    "language/expressions/division": {
        "relevance": "high",
        "notes": "Engine supports / operator",
    },
    "language/expressions/modulus": {
        "relevance": "high",
        "notes": "Engine supports % operator",
    },
    "language/expressions/equals": {
        "relevance": "high",
        "notes": "Engine supports == with type coercion",
    },
    "language/expressions/strict-equals": {
        "relevance": "high",
        "notes": "Engine supports === strict equality",
    },
    "language/expressions/does-not-equals": {
        "relevance": "high",
        "notes": "Engine supports != operator",
    },
    "language/expressions/strict-does-not-equals": {
        "relevance": "high",
        "notes": "Engine supports !== operator",
    },
    "language/expressions/typeof": {
        "relevance": "high",
        "notes": "Engine supports typeof operator",
    },
    "language/expressions/logical-and": {
        "relevance": "high",
        "notes": "Engine supports && with short-circuit",
    },
    "language/expressions/logical-or": {
        "relevance": "high",
        "notes": "Engine supports || with short-circuit",
    },
    "language/expressions/logical-not": {
        "relevance": "high",
        "notes": "Engine supports ! operator",
    },
    "language/expressions/conditional": {
        "relevance": "high",
        "notes": "Engine supports ternary ?: operator",
    },
    "language/expressions/assignment": {
        "relevance": "high",
        "notes": "Engine supports = assignment",
    },
    "language/statements/if": {
        "relevance": "high",
        "notes": "Engine supports if/else statements",
    },
    "language/statements/while": {
        "relevance": "high",
        "notes": "Engine supports while loops",
    },
    "language/statements/for": {
        "relevance": "high",
        "notes": "Engine supports for loops",
    },
    "language/statements/break": {
        "relevance": "high",
        "notes": "Engine supports break statements",
    },
    "language/statements/continue": {
        "relevance": "high",
        "notes": "Engine supports continue statements",
    },
    "language/statements/return": {
        "relevance": "high",
        "notes": "Engine supports return statements",
    },
    "language/statements/variable": {
        "relevance": "medium",
        "notes": "Engine supports var/let/const but not all edge cases",
    },
    "language/statements/block": {
        "relevance": "high",
        "notes": "Engine supports block statements with scoping",
    },
    "language/function-code": {
        "relevance": "medium",
        "notes": "Engine supports functions but not all spec edge cases",
    },
    "language/types/null": {
        "relevance": "high",
        "notes": "Engine supports null type",
    },
    "language/types/undefined": {
        "relevance": "high",
        "notes": "Engine supports undefined type",
    },
    "language/types/boolean": {
        "relevance": "high",
        "notes": "Engine supports boolean type",
    },
    "language/types/number": {
        "relevance": "high",
        "notes": "Engine supports number type (IEEE 754)",
    },
    "language/types/string": {
        "relevance": "high",
        "notes": "Engine supports string type",
    },
    "language/comments": {
        "relevance": "high",
        "notes": "Engine supports single-line and multi-line comments",
    },
    "language/identifiers": {
        "relevance": "medium",
        "notes": "Engine supports basic identifiers",
    },
    "language/keywords": {
        "relevance": "medium",
        "notes": "Engine recognizes JS keywords",
    },
    "language/block-scope": {
        "relevance": "medium",
        "notes": "Engine supports block scoping with let/const",
    },
}


# ===========================================================================
# Analysis functions
# ===========================================================================

def parse_metadata(source):
    match = YAML_PATTERN.search(source)
    if not match:
        return {}
    try:
        data = yaml.safe_load(match.group(1))
    except yaml.YAMLError:
        return {}
    return data if isinstance(data, dict) else {}


def classify_test(filepath, metadata):
    """
    Classify a test as:
    - 'applicable': Test could potentially run on our engine
    - 'skip_feature': Test requires unsupported features
    - 'skip_flag': Test requires unsupported flags
    - 'skip_fixture': Test is a fixture file
    """
    if "_FIXTURE" in filepath:
        return "skip_fixture", "fixture file"

    flags = metadata.get("flags", []) or []
    for flag in flags:
        if flag in UNSUPPORTED_FLAGS:
            return "skip_flag", f"unsupported flag: {flag}"

    features = metadata.get("features", []) or []
    for feature in features:
        if feature in UNSUPPORTED_TEST262_FEATURES:
            return "skip_feature", f"unsupported feature: {feature}"

    return "applicable", ""


def analyze_test_file(filepath, test_dir):
    """Analyze a single test file."""
    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            source = f.read()
    except Exception as e:
        return {
            "path": filepath,
            "classification": "error",
            "reason": str(e),
            "category": "",
            "metadata": {},
        }

    metadata = parse_metadata(source)
    classification, reason = classify_test(filepath, metadata)

    rel_path = os.path.relpath(filepath, test_dir)
    parts = rel_path.split(os.sep)
    if len(parts) >= 2:
        category = f"{parts[0]}/{parts[1]}"
    else:
        category = parts[0]

    # Check if test uses features beyond basic JS
    uses_eval = "eval(" in source
    uses_try_catch = "try {" in source or "try{" in source
    uses_new = "new " in source
    uses_object_literal = re.search(r'\{[^}]*:', source) is not None
    uses_array = "[" in source and "]" in source
    uses_regex = re.search(r'/[^/\n]+/[gimsuy]*', source) is not None
    uses_this = "this" in source
    uses_prototype = ".prototype" in source
    uses_throw = "throw " in source

    # Additional complexity markers for applicable tests
    complexity = "simple"
    if classification == "applicable":
        complex_features = []
        if uses_eval:
            complex_features.append("eval")
        if uses_try_catch:
            complex_features.append("try-catch")
        if uses_new:
            complex_features.append("new")
        if uses_object_literal:
            complex_features.append("object-literal")
        if uses_array:
            complex_features.append("array")
        if uses_regex:
            complex_features.append("regex")
        if uses_this:
            complex_features.append("this")
        if uses_prototype:
            complex_features.append("prototype")
        if uses_throw:
            complex_features.append("throw")

        if len(complex_features) >= 3:
            complexity = "complex"
        elif len(complex_features) >= 1:
            complexity = "moderate"

    return {
        "path": rel_path,
        "classification": classification,
        "reason": reason,
        "category": category,
        "complexity": complexity,
        "features_required": metadata.get("features", []) or [],
        "flags": metadata.get("flags", []) or [],
        "uses_eval": uses_eval,
        "uses_try_catch": uses_try_catch,
        "uses_new": uses_new,
        "uses_this": uses_this,
        "uses_prototype": uses_prototype,
    }


def discover_tests(test262_dir):
    test_dir = os.path.join(test262_dir, "test")
    tests = []
    for root, dirs, files in os.walk(test_dir):
        rel = os.path.relpath(root, test_dir)
        if rel.startswith("intl402"):
            continue
        for f in sorted(files):
            if not f.endswith(".js"):
                continue
            tests.append(os.path.join(root, f))
    return tests, test_dir


# ===========================================================================
# Report generation
# ===========================================================================

def generate_report(analyses, output_file):
    """Generate comprehensive conformance analysis report."""
    total = len(analyses)
    by_classification = defaultdict(int)
    by_category = defaultdict(lambda: defaultdict(int))
    by_complexity = defaultdict(int)
    feature_gaps = defaultdict(int)
    applicable_by_category = defaultdict(int)
    total_by_category = defaultdict(int)

    for a in analyses:
        by_classification[a["classification"]] += 1
        cat = a["category"]
        by_category[cat][a["classification"]] += 1
        total_by_category[cat] += 1

        if a["classification"] == "applicable":
            by_complexity[a["complexity"]] += 1
            applicable_by_category[cat] += 1

        if a["classification"] == "skip_feature":
            for feat in a["features_required"]:
                if feat in UNSUPPORTED_TEST262_FEATURES:
                    feature_gaps[feat] += 1

    applicable = by_classification["applicable"]
    skipped_feature = by_classification["skip_feature"]
    skipped_flag = by_classification["skip_flag"]
    skipped_fixture = by_classification["skip_fixture"]

    print("\n" + "=" * 76)
    print("  Test262 ECMAScript Conformance Analysis")
    print("  Engine: MoonBit JS Engine (tree-walking interpreter)")
    print(f"  Date: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 76)

    print(f"\n  Total test files analyzed:  {total:>6}")
    print(f"  Applicable (could run):    {applicable:>6} ({applicable/total*100:.1f}%)")
    print(f"  Skipped (unsupported feat):{skipped_feature:>6} ({skipped_feature/total*100:.1f}%)")
    print(f"  Skipped (unsupported flag):{skipped_flag:>6} ({skipped_flag/total*100:.1f}%)")
    print(f"  Skipped (fixture files):   {skipped_fixture:>6}")

    print(f"\n  Applicable test complexity breakdown:")
    for complexity in ["simple", "moderate", "complex"]:
        count = by_complexity[complexity]
        pct = (count / applicable * 100) if applicable > 0 else 0
        print(f"    {complexity:<12} {count:>6} ({pct:.1f}%)")

    print(f"\n{'─' * 76}")
    print(f"  {'Category':<45} {'Applicable':>10} {'Total':>8} {'%':>7}")
    print(f"{'─' * 76}")

    sorted_cats = sorted(
        total_by_category.keys(),
        key=lambda c: applicable_by_category.get(c, 0),
        reverse=True,
    )
    for cat in sorted_cats:
        app = applicable_by_category.get(cat, 0)
        tot = total_by_category[cat]
        pct = (app / tot * 100) if tot > 0 else 0
        if tot >= 5:  # Only show categories with enough tests
            marker = ""
            if cat in CATEGORY_ANALYSIS:
                rel = CATEGORY_ANALYSIS[cat]["relevance"]
                if rel == "high":
                    marker = " *"
            print(f"  {cat:<45} {app:>10} {tot:>8} {pct:>6.1f}%{marker}")

    print(f"{'─' * 76}")
    print("  * = high relevance to engine's current features")

    print(f"\n  Top 15 unsupported features (by test count):")
    print(f"{'─' * 76}")
    sorted_gaps = sorted(feature_gaps.items(), key=lambda x: -x[1])[:15]
    for feat, count in sorted_gaps:
        print(f"    {feat:<40} {count:>6} tests")

    # Categories with high relevance
    print(f"\n  Engine feature coverage assessment:")
    print(f"{'─' * 76}")
    for cat, info in sorted(CATEGORY_ANALYSIS.items()):
        app = applicable_by_category.get(cat, 0)
        tot = total_by_category.get(cat, 0)
        if tot > 0:
            pct = app / tot * 100
            print(f"  [{info['relevance']:>6}] {cat:<36} {app:>4}/{tot:<4} applicable")
            print(f"           {info['notes']}")

    # Summary
    print(f"\n{'=' * 76}")
    print(f"  SUMMARY")
    print(f"{'=' * 76}")
    print(f"  The MoonBit JS engine could potentially execute {applicable} out of")
    print(f"  {total} Test262 tests ({applicable/total*100:.1f}% of the suite).")
    print(f"")
    simple = by_complexity["simple"]
    print(f"  Of the applicable tests:")
    print(f"    - {simple} are simple (basic language features only)")
    print(f"    - {by_complexity['moderate']} use moderate features (try/catch, objects, etc.)")
    print(f"    - {by_complexity['complex']} use complex features (eval, prototypes, etc.)")
    print(f"")
    print(f"  Note: 'Applicable' means the test doesn't require features the engine")
    print(f"  explicitly lacks. Actual pass rate will be lower due to:")
    print(f"    - Missing built-in objects (Array, Object, RegExp, Error, etc.)")
    print(f"    - Missing standard library methods")
    print(f"    - Incomplete spec compliance in supported features")
    print(f"    - Missing error types and exception handling")
    print(f"")
    print(f"  To run actual conformance tests:")
    print(f"    make test262          # Full suite")
    print(f"    make test262-quick    # Quick subset (language/literals)")
    print(f"{'=' * 76}\n")

    # Save JSON report
    report = {
        "engine": "moonbit-js-engine",
        "analysis_type": "static",
        "date": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "summary": {
            "total_tests": total,
            "applicable": applicable,
            "skipped_feature": skipped_feature,
            "skipped_flag": skipped_flag,
            "skipped_fixture": skipped_fixture,
            "applicable_pct": round(applicable / total * 100, 2) if total > 0 else 0,
        },
        "complexity": dict(by_complexity),
        "categories": {
            cat: {
                "applicable": applicable_by_category.get(cat, 0),
                "total": total_by_category[cat],
                "applicable_pct": round(
                    applicable_by_category.get(cat, 0) / total_by_category[cat] * 100, 2
                ) if total_by_category[cat] > 0 else 0,
            }
            for cat in sorted(total_by_category.keys())
            if total_by_category[cat] >= 5
        },
        "feature_gaps": dict(sorted(feature_gaps.items(), key=lambda x: -x[1])[:30]),
    }

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"  Results saved to: {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description="Static conformance analysis of Test262 for MoonBit JS Engine"
    )
    parser.add_argument("--test262", default="./test262", help="Path to test262 directory")
    parser.add_argument("--output", default="test262-analysis.json", help="Output JSON file")
    args = parser.parse_args()

    test262_dir = os.path.abspath(args.test262)
    if not os.path.isdir(test262_dir):
        print(f"Error: test262 directory not found: {test262_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Discovering tests in {test262_dir}...")
    test_files, test_dir = discover_tests(test262_dir)
    print(f"Found {len(test_files)} test files")

    print("Analyzing tests...")
    analyses = []
    for i, tf in enumerate(test_files):
        a = analyze_test_file(tf, test_dir)
        analyses.append(a)
        if (i + 1) % 5000 == 0:
            print(f"  Analyzed {i+1}/{len(test_files)}...")

    generate_report(analyses, args.output)


if __name__ == "__main__":
    main()
