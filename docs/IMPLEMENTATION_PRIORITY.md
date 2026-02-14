# JS Engine: Test262 Failure Analysis & Implementation Priority

## Current Status

- **Pass rate**: **84.9%** (~23,335 / 27,491 executed) — post-Phase 17 2026-02-14
- **Skipped**: 20,497 (feature-flagged)
- **Failed**: 4,479
- **Timeouts**: 156
- **Unit tests**: 878 total, 878 passed, 0 failed

Note: This document is a phase-planning snapshot. For latest live totals, targeted slices, and recommended next steps, see [ROADMAP.md](../ROADMAP.md).

### Previous Baseline (Phase 8C)

- **Pass rate**: 45.27% (11,678 / 25,794 executed)
- **Failed**: 14,116
- **Timeouts**: 144

## Failure Breakdown (Pre-8C Categorized Run)

```
Parser SyntaxErrors (test can't even run):     2,719  (19%)
Runtime JsException (no error detail):        11,600  (80%)
async $DONE not called:                           97  ( 1%)
Timeouts:                                        146  ( 1%)
```

## Critical Finding: JsException Error Messages Are Lost

A large portion of runtime failures collapse to the identical string:
```
Error: dowdiness/js_engine/interpreter.JsException.JsException
```

The actual JS error message (TypeError, ReferenceError, Test262Error, etc.) is not propagated to stderr. This makes diagnosing runtime failures impossible from CI output.

**Action**: In the engine's top-level error handler (`cmd/main/main.mbt`), when catching `JsException(value)`, print the JS value's `.message` or string representation to stderr before exiting with error code. This will make every future CI run dramatically more informative.

Local smoke check still reproduces the issue:
```bash
moon run cmd/main -- 'throw new TypeError("boom")'
# Error: dowdiness/js_engine/interpreter.JsException.JsException
```

---

## Implementation Priority (Revised)

### P0: Unblock Diagnostics — Preserve JsException Details ✅ DONE

**Problem**: runtime failures collapse to:
```
Error: dowdiness/js_engine/interpreter.JsException.JsException
```

**Resolution**: Rewrote `cmd/main/main.mbt` error handler to catch `JsException(value)` and all `JsError` variants with proper formatting. CI failures are now actionable.

---

### P1: Parser Fix — Generator Methods in Class/Object Bodies ✅ DONE

**Resolution**: `parse_class_method()` and `parse_object_literal()` now recognize `*` for generator method definitions. Both paths produce `GeneratorExpr`/`GeneratorExprExt` with full keyword-to-name mapping (40+ keywords as valid method names).

---

### P2: Destructuring Defaults — Parser + Runtime Alignment ✅ DONE

**Resolution**: Added `DefaultPat(Pattern, Expr)` to Pattern enum. Parser handles `= expr` after destructuring elements. All 5 interpreter pattern-matching sites updated to evaluate defaults when source value is `undefined`.

---

### P3: Parser Cleanup — Remaining Syntax Gaps ✅ DONE

**Resolution**: Fixed `{a: b = 1}` binding bug, added `AssignTarget(Expr)` for member expression targets, `Of` as contextual identifier, `expr_to_ext_arrow_params()` fallback for complex arrow parameters, array elision holes, rest-element-must-be-last validation, `Yield` keyword in method name mappings.

---

### P4: Object Descriptor Compliance + Harness Cascade ✅ DONE

**Resolution**: Comprehensive descriptor compliance rewrite across `defineProperty`, `getOwnPropertyDescriptor`, `defineProperties`, and related helpers.

Key changes:
1. **P4a**: `defineProperty` now supports Symbol keys (was string-only). Strict invariant validation for non-configurable/non-writable property transitions preserved and extended to Symbol-keyed properties.
2. **P4b**: `getOwnPropertyDescriptor` now supports Symbol keys and returns correct descriptors for function built-in properties (`length`, `name`, `prototype`). Function `prototype` property now has correct descriptor flags (`writable: true, enumerable: false, configurable: false`).
3. **P4c**: `defineProperties` now throws TypeError on non-object target, validates non-configurable transitions, and only iterates enumerable own properties of the descriptors object. `defineProperty` now throws TypeError on non-object descriptors and accepts Array/Map/Set/Promise as valid JS object types for both target and descriptor arguments. Array targets support basic index and length property definition.

**PR review fixes** (PR #30):
1. `defineProperties` now accepts Array/Map/Set/Promise targets (was Object-only)
2. Fixed dead code in non-configurable generic descriptor check (`not(is_accessor) == false` → correct logic)
3. Added getter/setter identity validation in `defineProperties` for non-configurable accessor properties
4. Extracted shared `validate_non_configurable` helper (~95 lines), eliminating ~150 lines of duplicated validation

**Object test results**: 88.8% pass rate (2547/2868 executed) on `built-ins/Object`.

---

### P5: eval() Semantics ✅ DONE

**Resolution**: Full direct/indirect eval implementation per ES spec EvalDeclarationInstantiation.

Key changes:
1. **Direct eval detection**: `unwrap_grouping()` strips parentheses so `eval(...)`, `(eval)(...)`, `((eval))(...)` are all detected as direct eval
2. **NonConstructableCallable**: eval can't be called with `new` (TypeError)
3. **Variable environment**: `find_var_env()` walks scope chain to function/global scope for correct var hoisting
4. **Non-strict var leaking**: `hoist_declarations` on `var_env` lets declarations escape eval scope
5. **Strict mode isolation**: All declarations stay in eval scope when eval is strict
6. **Lex conflict checks**: Steps 5.a (global lex) and 5.d (intermediate lex) throw SyntaxError when eval's var declarations would hoist past let/const
7. **FuncDecl fix**: Function declarations in eval use `has_var`/`assign_var` to target correct variable environment
8. **Evaluation order**: Callee/receiver resolved before arguments per spec section 13.3.6.1

**eval-code test results**: 224/330 passing (67.9%), 17 skipped. var-env-* tests: 20/20 (100%).

---

### P6: Strict-Mode Prerequisite Bundle (narrow, high-ROI subset) ✅ DONE

**Resolution**: Implemented the narrow strict-mode checks that gate many test262 syntax/runtime tests.

Key changes:
1. **Duplicate parameters in strict functions** (SyntaxError): `check_duplicate_params()` / `check_duplicate_params_ext()` validate parameter uniqueness when entering strict function bodies. Applied in `call_value` and `eval_new` for both `UserFunc` and `UserFuncExt`.
2. **Assignment to `eval`/`arguments` in strict contexts** (SyntaxError): `validate_strict_binding_name()` checks applied in `Assign`, `eval_update` (++/--), `eval_compound_assign` (+=, etc.), all three logical assignment operators (&&=, ||=, ??=), `VarDecl`, `FuncDecl`/`FuncDeclExt`, and function parameter binding.
3. **`delete` unqualified identifier** (SyntaxError): Added `Ident` case in the `Delete` unary operator handler — raises SyntaxError when `self.strict` is true.
4. **Strict-only reserved words**: `is_strict_reserved_word()` checks `implements`, `interface`, `package`, `private`, `protected`, `public`. Enforced via `validate_strict_binding_name()` at all binding sites.
5. **Class body implicit strict mode**: `ensure_strict_body()` prepends `"use strict"` directive to class method bodies and constructor bodies in `create_class()`. `ClassConstructor` execution in `eval_new` saves/restores `self.strict = true`.
6. **Class constructor parameter validation**: `check_duplicate_params()` and `validate_strict_binding_name()` applied to class constructor parameters — `constructor(eval)`, `constructor(a, a)`, `constructor(arguments)` now throw SyntaxError.
7. **Sloppy duplicate params**: Fixed `call_value` and `eval_new` to allow duplicate parameter names in sloppy mode (last value wins) instead of throwing.

**Test262**: 19,720 → 19,723 passing (+3), language/function-code 166/173 (96.0%).
**Unit tests**: 30 new P6-specific tests (730 total, all passing).

---

### P7: Promise Species Constructor and Complete Compliance ✅ DONE

**Implemented outcomes**:
- **Promise species constructor**: `get_promise_species_constructor()` implements SpeciesConstructor algorithm, consulted by `then/catch/finally`. `Promise[Symbol.species]` getter enables subclass override
- **Constructor-aware capability**: All combinators (`all/race/any/allSettled`) and `Promise.reject` refactored to use `create_promise_capability_from_constructor(interp, _this, loc)`
- **Critical interpreter fixes with broad impact**:
  - Sloppy mode `this` normalization (undefined/null → globalThis)
  - `Function.prototype.apply` array-like support (handles `arguments` object forwarding)
  - Arguments object in class constructors
  - Function `prototype.constructor` bidirectional link
- **Combinator abrupt/iterator-close**: Proper handling across all Promise combinators
- **Thenable/poisoned-iterable**: Edge-case fixes in Promise resolve/combinator flows

**Results (2026-02-12)**:
- `built-ins/Promise`: **599/599 passing (100%)**, 41 skipped, 0 failed
- **Global impact**: 19,723 → 20,803 passing (**+1,080 tests**, 78.22% → 82.41%)
- `language/block-scope`: 106/106 passing (100%)
- `language/expressions`: 4,849 passing (88.4%, was 84.0%)
- `language/statements`: 3,449 passing (82.7%, was 77.0%)

**Note**: One skipped Promise test is Proxy-dependent and deferred until Proxy implementation.

---

## Actual vs Projected Impact

| Phase | Content | Projected | Actual | Rate |
|-------|---------|-----------|--------|------|
| Baseline | Date done (8C) | — | 11,678 | 45.3% |
| P0 | JsException diagnostics | 0 | 0 (diagnostic) | 45.3% |
| P1 | Generator methods parser | +800–1,096 | — | — |
| P2 | Destructuring defaults | +500–644 | — | — |
| P3 | Remaining parser gaps | +200–285 | — | — |
| **P0–P3 combined** | **All four phases** | **+1,500–2,025** | **+7,439** | **74.2%** |
| P4 | Object descriptors + harness cascade | +500–1,500 | — | — |

The actual gain from P0–P3 (+7,439) far exceeded the projected range (+1,500–2,025) because:
1. Error message propagation (P0) unlocked many tests that were failing due to assertion format mismatches
2. Generator method fixes (P1) cascaded through class and object expression tests
3. Destructuring defaults (P2) fixed patterns used pervasively in test262 harness code
4. Parser cleanup (P3) fixed arrow function parameters that gated large test suites

### Completed Phases (P5–P16)

| Phase | Content | Actual New Tests | Cumulative Rate |
|-------|---------|-----------------|-----------------|
| **P5** | **eval() semantics** | **+603** | **78.2%** |
| **P6** | **Strict-mode prerequisites** | **+3** | **78.2%** |
| **P7** | **Promise species + interpreter fixes** | **+1,080** | **82.4%** |
| **P8** | **Small compliance sweep** | **+67** | **82.7%** |
| **P9** | **Proxy/Reflect** | **+877** | **83.16%** |
| **P10** | **TypedArray/ArrayBuffer/DataView** | **+2,142** | **83.7%** |
| **P11** | **TypedArray prototype chain** | **+323** | **84.9%** |

### Projected Next Phases

| Phase | Content | Est. New Tests | Notes |
|-------|---------|---------------|-------|
| P12 | Boxed primitives | ~100+ | Medium effort, cross-cutting impact |
| P13 | RegExp sticky/unicode flags | ~222 | High effort, unlocks RegExp category |
| P14 | Iterator/Generator protocol | ~35+ | Medium effort, multiple iterator categories |
| P15 | WeakMap/WeakSet | ~57 | Low-medium effort |
| Annex B | `--annex-b` gated features | ~857 | Low priority |

---

## Annex B / Legacy Features (`--annex-b` flag)

**Status**: Planned. All deprecated and legacy ECMAScript Annex B features will be gated behind an `--annex-b` CLI flag, suppressed by default.

**Rationale**: Annex B features are deprecated, banned in strict mode, and irrelevant to modern JavaScript. The `with` statement (previously P7, ~151 tests) is the most complex Annex B feature — it requires a new object environment record type that adds complexity to the scope chain. Gating all Annex B features behind a flag keeps the core engine clean.

### Features to gate behind `--annex-b`

| Feature | Failing Tests | Notes |
|---------|---------------|-------|
| Block-level function decls (sloppy) | ~503 | `annexB/language` — FunctionDeclaration in blocks under sloppy mode (B.3.3) |
| `with` statement | ~151 | Object environment record, dynamic scope injection |
| `String.prototype.{anchor,big,...}` | ~73 | HTML wrapper methods |
| `__proto__` property | ~40 | `Object.prototype.__proto__` getter/setter |
| Legacy octal literals (`0777`) | ~30 | `0`-prefixed octals in sloppy mode |
| Legacy octal escapes (`\077`) | ~20 | Octal escape sequences in strings |
| `escape()`/`unescape()` | ~20 | Legacy encoding functions |
| HTML comment syntax (`<!--`) | ~10 | HTML-style comments in script code |
| `RegExp.prototype.compile` | ~10 | Legacy RegExp recompilation |

**Estimated total**: ~857 tests currently failing

### Implementation plan

1. Add `--annex-b` CLI flag in `cmd/main/main.mbt`, pass as `self.annex_b : Bool` to interpreter
2. Update `test262-runner.py` to pass `--annex-b` for `annexB/` tests and tests with Annex B metadata
3. Implement features incrementally, each gated behind `self.annex_b` check
4. Priority: low — implement after core ES2015+ compliance targets are met (>85% non-Annex B pass rate)

---

## Skipped Features Needed for ES2015 (future)

These are feature-flagged as skipped but required for ES2015 compliance:
- WeakMap/WeakSet (~147 executable tests) — Not yet implemented
- Proxy/Reflect — ✅ Done (Phase 15): Proxy 94.5% (257/272), Reflect 99.3% (152/153)
- TypedArray/ArrayBuffer/DataView — ✅ Done (Phase 16-17): DataView 91.0%, ArrayBuffer 90.1%, TypedArrayConstructors 94.4%, TypedArray 92.8%
- Tail call optimization (impractical for tree-walking interpreter)

## Recommended Next Steps (Post-Phase 16)

See [ROADMAP.md](../ROADMAP.md) for the full prioritized list. Top items by ROI:

1. **Boxed primitives** (`new String()`, `new Number()`, `new Boolean()`) — ~100+ tests, medium effort
2. **RegExp sticky/unicode flags** — ~222 tests, high effort
3. **Iterator/Generator protocol compliance** — ~35+ tests, medium effort. GeneratorFunction (9.5%), iterator prototypes (27.3%)
4. **WeakMap/WeakSet** — ~57 tests, low-medium effort
6. **`with` statement** (behind `--annex-b`) — ~151 tests, medium effort
7. **Class public fields** — ~723 skipped tests, medium effort
8. **Class private fields/methods** — ~2,437 skipped tests, high effort
9. **async/await** — ~500+ tests, medium effort
