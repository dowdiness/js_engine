# JS Engine: Test262 Failure Analysis & Implementation Priority

## Current Status

- **Pass rate**: 45.27% (11,678 / 25,794 executed)
- **Skipped**: 22,200 (feature-flagged)
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

### P0: Unblock Diagnostics — Preserve JsException Details

**Problem**: runtime failures collapse to:
```
Error: dowdiness/js_engine/interpreter.JsException.JsException
```

This prevents effective triage of runtime failures.

**Action**:
- In `cmd/main/main.mbt`, catch `JsException(value)` explicitly and print either:
  - `value.message` when present, or
  - `value.to_string()` fallback.
- Keep non-JS internal errors on the generic path.

**Expected impact**:
- No direct pass-rate jump.
- High leverage on every subsequent phase by making CI failures actionable.

---

### P1: Parser Fix — Generator Methods in Class/Object Bodies (~830–1,096 tests)

**Confirmed failure pattern**: `SyntaxError: Expected method name at line X, col Y`

**Examples**:
```javascript
class C { *gen() { yield 1; } }
class C { static *gen() { yield 2; } }
const obj = { *gen() { yield 1; } };
```

**Root cause**:
- `parse_class_method()` and `parse_object_literal()` do not recognize leading `*` for method definitions.

**Fix location**:
- `parser/expr.mbt` (`parse_class_method`, `parse_object_literal`)

**Expected impact**: high; mostly parser-only change.

---

### P2: Destructuring Defaults — Parser + Runtime Alignment (~644 tests)

**Confirmed failure pattern**: `SyntaxError: Expected Comma, got Assign`

**Important scope correction**:
- This is not only a parser tokenization issue.
- `parse_array_pattern()` currently cannot represent per-element defaults (e.g. `[a = 1]`).
- Runtime binding logic must also evaluate defaults for array-pattern elements when source value is `undefined`.

**Fix locations**:
- Parser: `parser/stmt.mbt`, `parser/expr.mbt` (`parse_array_pattern`, `expr_to_pattern`)
- AST: extend pattern representation so array elements can carry default initializers
- Runtime: `interpreter/interpreter.mbt` (`bind_pattern`, `assign_pattern`)

**Expected impact**: medium-high, but more effort than a parser-only patch.

---

### P3: Parser Cleanup — Remaining Syntax Gaps (~285 tests)

| Issue | Tests | Error Pattern |
|-------|-------|---------------|
| Invalid destructuring pattern (other contexts) | ~211 | `Invalid destructuring pattern` |
| Arrow parameter edge cases | ~74 | `Invalid arrow function parameter list` |

Keep this phase parser-only and close out known syntax buckets before deeper semantic work.

---

### P4: Object Descriptor Compliance + Harness Cascade (split milestones)

Large single-shot rewrite is risky; split into incremental milestones:

1. **P4a**: strict invariants for non-configurable/non-writable transitions
2. **P4b**: descriptor completeness for string + symbol keys in `getOwnPropertyDescriptor(s)`
3. **P4c**: `defineProperties` + `create` interactions and harness verification tests

**Targeted areas**:
- `interpreter/builtins_object.mbt`
- any shared property descriptor helpers

**Why split**:
- Existing implementation already covers many descriptor rules.
- Remaining failures are likely edge-case clusters, not one missing primitive.

**Expected impact**:
- Direct Object gains plus broad harness cascade across built-ins.

---

### P5: eval() Semantics (~740 tests)

**CI data**:
```
language/eval-code/direct:      217 fail
language/eval-code/indirect:     54 fail
annexB/language/eval-code:      469 fail
```

**Scope correction**:
- Implementing `eval` is not only adding a global builtin.
- Direct vs indirect behavior depends on **call-site semantics** in `eval_call` path.

**Required behavior**:
1. Direct eval in caller lexical environment
2. Indirect eval in global environment
3. Strict-eval environment isolation rules
4. Correct var leakage in non-strict direct eval

---

### P6: Strict-Mode Prerequisite Bundle (narrow, high-ROI subset)

Before `with`, implement strict checks that gate many syntax/runtime tests:

- duplicate parameters in strict functions
- assignment to `eval` / `arguments` in strict contexts
- `delete` unqualified identifier syntax error in strict mode
- strict-only reserved words

This phase should be intentionally narrow; broad strict-mode parity remains later.

---

### P7: with Statement (~151 tests)

**CI data**: `language/statements/with: 151 fail`

**Scope correction**:
- Lexer currently has no `With` keyword token; add this first.

**Required**:
1. Add `With` token in `token/token.mbt`, keyword mapping in `lexer/lexer.mbt`
2. Add `WithStmt(expr, body)` in `ast/ast.mbt`
3. Parse `with (expr) stmt` in parser
4. Interpreter object-environment chain behavior
5. Reject in strict mode (SyntaxError)
6. `Symbol.unscopables` may be deferred

---

### P8: Promise Improvements (~451 tests)

**CI data**:
```
built-ins/Promise/allSettled:   90 fail
built-ins/Promise/any:          85 fail
built-ins/Promise/all:          80 fail
built-ins/Promise/race:         75 fail
built-ins/Promise/prototype:    59 fail
```

Focus:
- iterator protocol edge cases
- thenable assimilation correctness
- job/microtask ordering
- resolve/reject race and abrupt completion handling

---

## Projected Impact (Revised)

| Phase | Content | Est. New Tests | Cumulative Rate |
|-------|---------|---------------|-----------------|
| Baseline | Date done (8C) | +345 (already landed) | ~45.3% |
| P0 | JsException diagnostics | 0 (diagnostic) | ~45.3% |
| P1 | Generator methods parser | +800–1,096 | ~48–50% |
| P2 | Destructuring defaults (parser+runtime) | +500–644 | ~50–52% |
| P3 | Remaining parser gaps | +200–285 | ~51–53% |
| P4 | Object descriptors + harness cascade | +1,500–3,000 | ~57–62% |
| P5 | eval() semantics | +400–740 | ~59–64% |
| P6 | Strict subset prerequisites | +200–500 | ~60–66% |
| P7 | with statement | +100–151 | ~60–66% |
| P8 | Promise improvements | +200–451 | ~61–68% |

## Skipped Features Needed for ES2015 (future)

These are feature-flagged as skipped but required for ES2015 compliance:
- WeakMap/WeakSet (~147 executable tests)
- Proxy/Reflect (~311+ tests) 
- TypedArray/ArrayBuffer/DataView (~1,568+ tests)
- Tail call optimization (impractical for tree-walking interpreter)
