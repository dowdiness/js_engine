# JS Engine Roadmap

## Current Status

**Test262**: 44,933 / 53,208 tasks executed (**84.4%** pass rate, strict + non-strict) — full run 2026-02-22

**Unit tests**: 881 total, 881 passed, 0 failed

**Targeted verification (2026-02-11)**: `language/block-scope` slice is 106/106 passing (39 skipped).
**Targeted verification (2026-02-12)**: `built-ins/Promise` slice is 599/599 passing (100%, 41 skipped). `language/block-scope` is 106/106 passing (100%, 39 skipped).
**Targeted verification (2026-02-13)**: `language/white-space` slice is 66/67 passing (98.5%, was 73.1%). Small compliance sweep completed. Proxy/Reflect implemented: Proxy 94.5% (257/272), Reflect 99.3% (152/153).
**Phase 16 (2026-02-14)**: TypedArray/ArrayBuffer/DataView implemented. 9 typed array types, DataView with all getter/setter methods, ArrayBuffer with slice/detach. 79 new unit tests, all passing. Full test262 re-run: **+2,142 tests passing** (20,870 → 23,012), pass rate 82.7% → **83.7%**.
**Phase 17 (2026-02-14)**: TypedArray prototype chain conformance. Created `%TypedArray%` intrinsic constructor, set per-type constructor `[[Prototype]]` chains. TypedArray 55.1% → **92.8%** (+293), TypedArrayConstructors 86.1% → **94.4%** (+30). Estimated **+323 tests** passing overall.
**Phase 18 (2026-02-14)**: Boxed primitives (`new String/Number/Boolean`). Constructor wrapping with `[[StringData]]`/`[[NumberData]]`/`[[BooleanData]]` internal slots, `Object()` ToObject wrapping, ToPrimitive coercion in `loose_equal`, prototype method support. Also fixed TypedArray constructor name inheritance regression. Key improvements: Object 92.7% → **95.9%** (+108), String 92.0% → **95.1%** (+38), Number 83.6% → **85.7%** (+7), TypedArray 92.8% → **93.4%** (+5), TypedArrayConstructors 94.4% → **95.3%** (+3), Boolean 83.7% → **85.7%** (+1). Estimated **+162 tests** passing in targeted categories.
**Phase 19 (2026-02-15)**: Symbol/TypedArray prototype fixes and full re-run verification. Registered `[[SymbolPrototype]]` and `[[FunctionPrototype]]` as environment builtins. Boxed Symbol objects now use Symbol.prototype (was Object.prototype). `%TypedArray%` constructor gets `name`/`length` descriptors and `[[Prototype]]` set to Function.prototype. Reflect now **100%** (153/153). Full test262 re-run: **+525 tests passing** (23,012 → 23,537), pass rate 83.7% → **85.6%**.
**Phase 20 (2026-02-15)**: WeakMap/WeakSet, iterator prototypes, RegExp improvements. Implemented WeakMap (100%, 139/139) and WeakSet (100%, 84/84) with full constructor/prototype support including `getOrInsert`/`getOrInsertComputed`. Added `getOrInsert`/`getOrInsertComputed` to Map (100%). Created shared iterator prototypes (`%MapIteratorPrototype%`, `%SetIteratorPrototype%`, `%ArrayIteratorPrototype%`, `%StringIteratorPrototype%`) with proper `[Symbol.toStringTag]`, `next` method `name`/`length` descriptors. Added `Symbol.iterator` support for Map/Set/boxed String. RegExp: added lookahead `(?=…)`/`(?!…)`, multiline `^`/`$` anchoring, backreferences `\1`-`\9`, dotAll `s` flag, sticky `y` flag, unicode `u` flag properties, full ES whitespace in `\s`/`\S`, `exec` result `index`/`input`/`groups` properties. Full test262 re-run: **+223 tests passing** (23,537 → 23,760), pass rate 85.6% → **86.1%**.
**Phase 20 review fixes (2026-02-15)**: PR review fixes for regex, WeakMap/WeakSet, and array properties. RegExp: `is_line_terminator` helper for dot/multiline anchors covering `\r`/`\u2028`/`\u2029`; sticky flag reads/writes `lastIndex`; `regex_search` accepts `start_pos`. WeakMap/WeakSet: IDs moved to non-forgeable side tables with `physical_equal`; constructors reject calls without `new`; `is_constructing` flag set for `InterpreterCallable` in `eval_new`; `getOrInsertComputed` callback safety. Arrays: `set_property` persists named props to side table; `get_computed_property`/`set_computed_property` detect canonical numeric index strings; `get_computed_property` checks side table for named props. String `@@iterator` uses call-time receiver. Full test262 re-run: **+89 tests passing** (23,760 → 23,849), pass rate 86.1% → **86.4%**.
**Phase 21 (2026-02-16)**: Annex B `get_string_method` gating and conformance fixes. `get_string_method` now accepts `annex_b~` parameter and returns `Undefined` for Annex B HTML method names when flag is false, preventing direct primitive access from bypassing `setup_string_prototype` gating. All interpreter call sites forward `self.annex_b`. Replaced `str[i:i+1].to_string()` with `str.view()[i:i+1].to_string()` in String constructor. Removed dead `"annex-b" in meta.includes` clause from test262-runner.py. Full test262 re-run: **+26 tests passing** (23,849 → 23,875), pass rate 86.4% → **86.5%**. Key improvements: annexB/built-ins 66.8% → **72.7%** (+13), JSON 97.8% → **99.3%** (+2), String 95.6% → **95.1%** (more tests executed), Iterator 80.0% → **100.0%** (+1).
**Phase 22 (2026-02-17)**: Tier 1+2 conformance improvements. Tier 1: string escape sequences (`\r`, `\b`, `\v`, `\f`, `\0`, `\xHH`), `%ThrowTypeError%` intrinsic for strict arguments/caller. Tier 2: `with` statement (object environment record, SyntaxError in strict mode), Annex B block-level function hoisting (sloppy mode var binding propagation), RegExp `[Symbol.match]`/`[Symbol.replace]`/`[Symbol.split]`/`[Symbol.search]`, import syntax validation (escaped reserved words, duplicate bindings). PR review fixes: line continuation in string/template literals, escaped reserved words as IdentifierName, DataView ToIndex validation, `String.prototype.replaceAll` global-flag check, `with` primitive coercion, RegExp `Symbol.split` ToUint32 limit. Full test262 re-run: **+587 tests passing** (23,875 → 24,462), pass rate 86.5% → **88.1%**. Key improvements: annexB/language 38.1% → **87.0%** (+400), RegExp 77.3% → **86.8%** (+81), DataView 91.0% → **100.0%** (+24), Proxy 96.3% → **97.1%** (+2), language/statements 83.0% → **84.0%** (+44), language/identifiers 74.4% → **78.7%** (+9).
**Phase 23 (2026-02-18)**: Tier 4 polish & edge cases. globalThis properties (`undefined`/`NaN`/`Infinity` with correct descriptors), full LineTerminator support (`\u2028`/`\u2029` in lexer, comments, strings, line continuation), directive prologue fix (full prologue scan, reject escaped `"use strict"`), GeneratorFunction constructor (`GeneratorFunction("a", "yield a")`), generator prototype chain fix, eval completion values for loops/switch, ASI restricted productions (`throw`/`return`/postfix `++`/`--`), Unicode whitespace rejection in identifier escapes. PR review fixes: regex multiline CRLF exclusion, `@@toStringTag` error propagation, `Object.assign` Proxy symbol properties, `Object.create` descriptor deduplication. Full test262 re-run: **+57 tests passing** (24,462 → 24,519), pass rate 88.1% → **88.8%**. Key improvements: GeneratorFunction **100.0%** (21/21, was 9.5%), GeneratorPrototype **88.5%** (54/61), line-terminators **68.3%** (28/41, was 48.8%), undefined **71.4%** (5/7, was 57.1%), ASI 96.1% → **96.1%** (98/102), white-space **100.0%** (67/67, was 98.5%).

**Phase 24 (2026-02-22)**: Compiler warning cleanup and strict-mode test262 expansion. Fixed all 34 MoonBit compiler warnings: deprecated `fn` syntax → explicit `raise` annotations, unused variables prefixed with `_`, deprecated `substring` → slice syntax, reserved keyword `method` renamed, unreachable code removed, ambiguous `&&`/`||` precedence disambiguated, dead-store variable removed. Test runner now tests both strict and non-strict modes (92,291 tasks from 48,157 files). Full test262 re-run: **84.4%** pass rate (44,933/53,208 tasks). Key improvements: line-terminators **100.0%** (82/82, was 68.3%), ThrowTypeError **96.2%** (25/26, was 0.0%). Build now produces **0 warnings**.

## Phase History

| Phase | Tests | Cumulative | Key Changes |
|-------|-------|------------|-------------|
| 1-5 | — | 6,351 | Core language, classes, promises, iterators, skip list cleanup |
| 6A-6G | +~2,350 | ~8,500 | Parser fixes, prototype chains, destructuring, tagged templates |
| 6H | +1,202 | 9,489 | Error prototype chain fix |
| 6I-6L | +56 | 9,545 | Leading decimals, canonical indices, PR review fixes |
| 7A | — | 9,545 | Full accessor descriptor support (get/set in PropDescriptor) |
| 7B | +1,047 | 10,592 | Unicode escapes in identifiers, strings, template literals |
| 7C-E | +65 | 10,657 | Bare for-of/for-in, get/set as identifiers, Math function lengths |
| 7F | +202 | 10,864 | ES Modules (import/export declarations) |
| 8 | +452 | 11,316 | ES6 generators (function*, yield, yield*) |
| 8B | +17 | 11,333 | Test262 harness functions (print, $262, Function constructor) |
| 8C | +345 | 11,678 | Date object (constructor, prototype methods, static methods) |
| JS Target | — | — | JS backend support, Error toString fix, backend-specific argv handling |
| 9 | +7,439 | 19,117 | P0-P3: error diagnostics, generator methods, destructuring defaults, parser cleanup |
| 10 | — | — | P4: Object descriptor compliance — Symbol keys, function props, Array targets |
| 11 | +603 | 19,720 | P5: eval() semantics — direct/indirect eval, var hoisting, lex conflict checks |
| 12 | +3 | 19,723 | P6: Strict-mode prerequisite bundle — duplicate params, eval/arguments binding, delete identifier, reserved words, class body strict |
| 13 | +1,080 | 20,803 | P7: Promise species constructor, sloppy mode this, apply/arguments fixes — 100% Promise compliance, constructor subclassing, test harness improvements |
| 14 | +67 | 20,870 | Small compliance sweep — Unicode whitespace (98.5%), Number/String.prototype.toLocaleString, String trim aliases, String.prototype.matchAll |
| 15 | +877 | 21,747 | Proxy/Reflect — full Proxy trap support (13 traps), Reflect API (13 methods), PR review fixes, test262 conformance |
| 16 | +2,142 | 23,012 | TypedArray/ArrayBuffer/DataView — 9 TypedArray types, DataView getters/setters, ArrayBuffer slice/detach, buffer detachment validation |
| 17 | +323 | ~23,335 | TypedArray prototype chain — %TypedArray% intrinsic constructor, per-type [[Prototype]] chains, constructor.prototype linkage |
| 18 | +162 | ~23,500 | Boxed primitives (`new String/Number/Boolean`), Object() ToObject wrapping, ToPrimitive coercion, TypedArray constructor name fix |
| 19 | +525 | 23,537 | Symbol/TypedArray prototype fixes, `[[SymbolPrototype]]`/`[[FunctionPrototype]]` builtins, full re-run verification (85.6%) |
| 20 | +223 | 23,760 | WeakMap/WeakSet, iterator prototypes, RegExp improvements — full re-run verification (86.1%) |
| 20-fix | +89 | 23,849 | PR review fixes: regex line terminators/lastIndex, WeakMap/WeakSet constructor checks, array named props, canonical numeric indices (86.4%) |
| 21 | +26 | 23,875 | Annex B `get_string_method` gating, StringView fix, test runner fix (86.5%) |
| 22 | +587 | 24,462 | `with` statement, Annex B block-level function hoisting, RegExp Symbol methods, string escapes, `%ThrowTypeError%`, import validation, PR review fixes (88.1%) |
| 23 | +57 | 24,519 | Tier 4 polish: GeneratorFunction constructor, LineTerminator support, directive prologue fix, eval completion values, ASI restricted productions, Unicode whitespace in escapes (88.8%) |
| 24 | — | 44,933† | Compiler warning cleanup (34→0), test runner now tests strict + non-strict modes (84.4% of 53,208 tasks) |

† Phase 24 changed test methodology: runner now tests both strict and non-strict modes (92,291 tasks from 48,157 files), revealing strict-mode failures not previously counted. Non-strict-only pass rate remains comparable to Phase 23.

For detailed implementation notes on Phases 1-6, see [docs/PHASE_HISTORY.md](docs/PHASE_HISTORY.md).

---

## Failure Breakdown

### Failure Breakdown by Category (8,275 remaining task failures)

Top failing categories from the full test262 run (2026-02-22, strict + non-strict):

| Category | Pass | Fail | Rate | Priority |
|----------|------|------|------|----------|
| built-ins/Array | 4,573 | 1,249 | 78.5% | Medium |
| built-ins/Object | 5,642 | 1,102 | 83.7% | Medium |
| language/expressions | 10,024 | 853 | 92.2% | Medium |
| built-ins/TypedArray | 802 | 752 | 51.6% | Medium |
| language/statements | 7,615 | 647 | 92.2% | Medium |
| built-ins/RegExp | 1,102 | 586 | 65.3% | Medium |
| annexB/language | 404 | 439 | 47.9% | Medium |
| built-ins/Proxy | 224 | 310 | 41.9% | Medium |
| built-ins/String | 2,160 | 257 | 89.4% | Medium |
| built-ins/TypedArrayConstructors | 489 | 228 | 68.2% | Medium |
| built-ins/Function | 610 | 182 | 77.0% | Medium |
| language/eval-code | 283 | 169 | 62.6% | Medium |
| built-ins/Uint8Array | 16 | 120 | 11.8% | Medium |
| language/module-code | 193 | 119 | 61.9% | Medium |
| built-ins/Promise | 1,162 | 98 | 92.2% | Medium |
| built-ins/Reflect | 210 | 96 | 68.6% | Medium |
| built-ins/JSON | 180 | 90 | 66.7% | Medium |
| annexB/built-ins | 354 | 86 | 80.5% | Low (--annex-b) |
| language/import | 17 | 82 | 17.2% | Medium |
| language/identifiers | 335 | 80 | 80.7% | Medium |
| language/literals | 581 | 60 | 90.6% | Medium |
| built-ins/DataView | 700 | 54 | 92.8% | Medium |
| built-ins/Date | 1,112 | 54 | 95.4% | ✅ Done (8C) |
| built-ins/GeneratorPrototype | 78 | 44 | 63.9% | Medium |
| built-ins/Number | 640 | 30 | 95.5% | ✅ Done |
| built-ins/Map | 365 | 24 | 93.8% | Medium |
| built-ins/WeakMap | 257 | 22 | 92.1% | Medium |
| built-ins/Math | 626 | 18 | 97.2% | ✅ Done |
| built-ins/Set | 370 | 14 | 96.4% | ✅ Done |
| built-ins/WeakSet | 156 | 12 | 92.9% | Medium |
| built-ins/Boolean | 99 | 0 | 100.0% | ✅ Done |
| built-ins/Infinity | 10 | 0 | 100.0% | ✅ Done |
| built-ins/NaN | 10 | 0 | 100.0% | ✅ Done |
| built-ins/undefined | 12 | 0 | 100.0% | ✅ Done |
| built-ins/isFinite | 30 | 0 | 100.0% | ✅ Done |
| built-ins/isNaN | 30 | 0 | 100.0% | ✅ Done |
| built-ins/ThrowTypeError | 25 | 1 | 96.2% | ✅ Done (P24, was 0.0%) |
| language/line-terminators | 82 | 0 | 100.0% | ✅ Done (P24, was 68.3%) |
| language/block-scope | 215 | 0 | 100.0% | ✅ Done |
| language/white-space | 134 | 0 | 100.0% | ✅ Done (P14, P23) |
| language/asi | 204 | 0 | 100.0% | ✅ Done |
| language/keywords | 50 | 0 | 100.0% | ✅ Done |
| language/comments | 46 | 0 | 100.0% | ✅ Done |
| language/punctuators | 22 | 0 | 100.0% | ✅ Done |

### High-Performing Categories (>90% pass rate, strict + non-strict)

| Category | Pass | Fail | Rate |
|----------|------|------|------|
| built-ins/Boolean | 99 | 0 | 100.0% |
| built-ins/Infinity | 10 | 0 | 100.0% |
| built-ins/NaN | 10 | 0 | 100.0% |
| built-ins/eval | 18 | 0 | 100.0% |
| built-ins/isFinite | 30 | 0 | 100.0% |
| built-ins/isNaN | 30 | 0 | 100.0% |
| built-ins/undefined | 12 | 0 | 100.0% |
| language/asi | 204 | 0 | 100.0% |
| language/block-scope | 215 | 0 | 100.0% |
| language/comments | 46 | 0 | 100.0% |
| language/export | 3 | 0 | 100.0% |
| language/identifier-resolution | 20 | 0 | 100.0% |
| language/keywords | 50 | 0 | 100.0% |
| language/line-terminators | 82 | 0 | 100.0% |
| language/punctuators | 22 | 0 | 100.0% |
| language/source-text | 2 | 0 | 100.0% |
| language/white-space | 134 | 0 | 100.0% |
| language/function-code | 277 | 4 | 98.6% |
| language/future-reserved-words | 84 | 1 | 98.8% |
| language/directive-prologue | 61 | 1 | 98.4% |
| built-ins/parseInt | 108 | 2 | 98.2% |
| built-ins/parseFloat | 106 | 2 | 98.1% |
| built-ins/decodeURI | 106 | 2 | 98.1% |
| built-ins/NativeErrors | 172 | 4 | 97.7% |
| built-ins/Math | 626 | 18 | 97.2% |
| built-ins/Set | 370 | 14 | 96.4% |
| built-ins/decodeURIComponent | 106 | 4 | 96.4% |
| built-ins/ThrowTypeError | 25 | 1 | 96.2% |
| language/reserved-words | 51 | 2 | 96.2% |
| built-ins/Date | 1,112 | 54 | 95.4% |
| built-ins/Number | 640 | 30 | 95.5% |
| language/types | 198 | 9 | 95.7% |
| built-ins/Map | 365 | 24 | 93.8% |
| built-ins/global | 52 | 4 | 92.9% |
| built-ins/WeakSet | 156 | 12 | 92.9% |
| built-ins/DataView | 700 | 54 | 92.8% |
| built-ins/Promise | 1,162 | 98 | 92.2% |
| language/expressions | 10,024 | 853 | 92.2% |
| language/statements | 7,615 | 647 | 92.2% |
| built-ins/WeakMap | 257 | 22 | 92.1% |
| built-ins/Symbol | 138 | 12 | 92.0% |
| language/literals | 581 | 60 | 90.6% |

---

## JavaScript Self-Hosting

**Status**: Working. The engine compiles to JavaScript via `moon build --target js` and runs on Node.js.

```bash
moon build --target js
node ./_build/js/debug/build/cmd/main/main.js 'console.log(1 + 2)'
# => 3
```

All 881 unit tests pass on both WASM-GC and JS targets. See [docs/SELF_HOST_JS_RESEARCH.md](docs/SELF_HOST_JS_RESEARCH.md) for full analysis.

### What was needed
- **Backend-specific argv handling**: `process.argv` on JS includes `["node", "script.js", ...]`, so user args start at index 2 (vs index 1 on WASM). Solved with `.js.mbt` / `.wasm.mbt` / `.wasm-gc.mbt` files.
- **Error toString fix**: Error objects now format as `"TypeError: message"` instead of `"[object TypeError]"`, matching `Error.prototype.toString()`.

### Future directions
- **npm distribution**: Configure ESM/CJS output, publish as sandboxed JS evaluator
- **Browser playground**: IIFE build for in-browser JS interpretation (no fs dependencies)
- **Self-interpretation**: Run the JS-compiled engine through itself (requires higher Test262 compliance to handle MoonBit's JS output)

---

## Phase 7 Targets (reaching 10,000+)

### 7A: Property Descriptors — DONE

Implemented full accessor descriptor support:

- Extended `PropDescriptor` with `getter: Value?` and `setter: Value?` fields
- Accessor vs data descriptor validation in `defineProperty` (TypeError on mixing get/set with value/writable)
- Getter invocation during property access (own + prototype chain, correct `this` binding)
- Setter invocation during property assignment (own + prototype chain)
- `Object.create()` with accessor property descriptors
- `Object.getOwnPropertyDescriptor()` returning accessor format `{get, set, enumerable, configurable}`
- `Object.getOwnPropertyDescriptors()` accessor-aware output
- `Object.defineProperties()` accessor descriptor support
- `Object.freeze()`/`Object.seal()` preserve existing getters/setters
- Class getter/setter methods stored as accessor descriptors on prototype
- Replaced `__get__`/`__set__` prefix hack with proper PropDescriptor storage

### 7B: Unicode Escapes (~479 tests) — DONE

Pure lexer fix. Added `parse_unicode_escape()` and `write_code_point()` helpers:

- `\uXXXX` and `\u{XXXXX}` in identifiers: `var \u0061 = 1` means `var a = 1`
- Unicode escapes in string literals and template literals
- Decoded identifiers pass through `resolve_keyword()` for correct keyword resolution
- Supplementary plane support via surrogate pairs for code points > 0xFFFF

### 7C: Bare for-of/for-in (~225 tests) — DONE

Parser + interpreter fix for `for (x of arr)` without `let`/`var`/`const`:

- Speculative parsing approach: `parse_call()` to get LHS, then check for `of`/`in`
- Bare destructuring: `for ({x} of arr)`, `for ([x] of arr)` via `ForOfStmtPat`/`ForInStmtPat` with `VarKind?`
- Bare member expressions: `for (a.b of arr)` via new `ForOfExpr`/`ForInExpr` AST nodes
- Assignment to existing variables via `assign_pattern` (no new bindings)

### 7D: get/set as Identifiers (~127 tests) — DONE

Parser fix: `get`/`set` treated as regular identifiers outside getter/setter position:

- Updated `expect_ident()` to accept `Get`/`Set` tokens as identifiers
- Updated `parse_primary()` to produce `Ident("get")`/`Ident("set")` for standalone usage
- Handled in `parse_assignment()` for single-param arrow functions (`get => ...`)
- Statement-level handling: `get`/`set` as labels, expression statements

### 7E: Math Built-ins (~134 tests) — DONE

All Math methods already existed. Fixes for test262 compliance:

- Added correct `.length` property to all Math methods via `make_native_func_with_length`
- Added `Math[Symbol.toStringTag] = "Math"` via well-known symbol
- Global `well_known_tostringtag_sym` for Symbol.toStringTag access across builtins
- Reordered builtin initialization: `setup_symbol_builtins` before `setup_math_builtins`

### 7F: ES Modules — DONE

Full import/export declaration support:

- Lexer: `import`, `export`, `from`, `as` keywords
- Parser: All import/export syntax forms including default, named, namespace, re-exports, side-effect imports
- Interpreter: Module registry, module-scoped environments, export collection with live bindings
- `export default function/class` hoisting (named functions hoisted, anonymous supported)
- Module namespace objects with non-writable, non-configurable, enumerable properties
- Import/export restricted to module top-level only (SyntaxError in nested blocks)
- Public API: `run_module()` for single modules, `run_modules()` for multi-module dependency chains
- CLI `--module` flag for module execution mode; test262 runner passes flag for module-flagged tests
- `language/export`: 3/3 passing (100%)
- `language/module-code`: 176/273 passing (64.5%), 319 skipped
- `language/import`: 11/93 passing (11.8%), 19 skipped
- +12 tests in other directories (e.g., `reserved-words`) from module-related fixes

### 8: ES6 Generators (+452 tests) — DONE

Full `function*` / `yield` / `yield*` implementation:

- **Architecture**: Statement replay model — generator body is re-executed from the beginning on each `.next()`, replaying past statements and resuming at the saved program counter. Avoids the complexity of a separate frame-stack/step-engine while reusing the existing interpreter.
- **GeneratorObject**: Carries body, params, closure, env, PC, and delegation state as fields on a `Value::Object` with internal generator payload
- **Protocol**: `.next()`, `.throw()`, `.return()` with full state machine (SuspendedStart, Executing, SuspendedYield, Completed)
- **yield***: Delegated iteration with forwarding of `.next()`, `.throw()`, `.return()` to delegate iterator, IteratorClose on abrupt completion
- **Control flow**: `try/catch/finally` with phase tracking, loops with saved environment stacks, labeled break/continue
- **Spec compliance**: GetMethod semantics, IteratorClose result validation, TypeError for non-iterable yield* delegates, re-entrancy guard
- **Test262**: GeneratorPrototype 26/58 (44.8%), GeneratorFunction 0/20 (0.0%)
- **Unit tests**: 59 new generator-specific tests (580 → 639)

For the original implementation plan, see [docs/GENERATOR_PLAN.md](docs/GENERATOR_PLAN.md).

---

## Phase 8+ Targets (reaching 20,000+)

### Generators — DONE

See Phase 8 section above. `function*`, `yield`, `yield*` fully implemented with 695 unit tests and +452 test262 tests gained. Unblocks async-iteration as a next target.

### 8B: Test262 Harness Functions (+17 tests) — DONE

Host-level harness functions required by the test262 test suite:

- **`print()` builtin**: Native function that appends output, matching test262's expected host function
- **`$262` object**: Host-defined object per test262 spec with the following methods:
  - `$262.global` — reference to the global object
  - `$262.gc()` — no-op stub (garbage collection hint)
  - `$262.detachArrayBuffer()` — no-op stub (TypedArray prerequisite)
  - `$262.evalScript(code)` — evaluates code string in the current realm via `@parser.parse()`
  - `$262.createRealm()` — creates a fresh `Interpreter` with isolated global, returns a new `$262` bound to that realm
  - `$262.agent.*` — no-op stubs for SharedArrayBuffer agent protocol (start, broadcast, getReport, sleep, monotonicNow)
- **`Function` constructor**: Parses body strings via `@parser.parse()` to create real functions (enables `Function("return this;")()` pattern used by `fnGlobalObject.js` harness)
- **Global object mirroring**: Both `print` and `$262` are accessible via environment bindings and as `globalThis` properties
- **Realm isolation**: `createRealm()` returns `$262` with `NativeCallable` closures capturing the new interpreter, ensuring `evalScript` runs in the new realm (not the caller's)

### 8C: Date Object (+345 tests) — DONE

Full ES5/ES6 Date implementation:

- **Constructor**: `new Date()`, `new Date(value)`, `new Date(string)`, `new Date(y,m,d,h,min,s,ms)` with proper argument coercion
- **Called without `new`**: `Date()` returns current date as string (not an object), using `is_constructing` flag
- **Static methods**: `Date.now()`, `Date.parse()`, `Date.UTC()`
- **Prototype getters**: `getTime`, `getFullYear`, `getMonth`, `getDate`, `getDay`, `getHours`, `getMinutes`, `getSeconds`, `getMilliseconds` (+ UTC variants)
- **Prototype setters**: `setTime`, `setFullYear`, `setMonth`, `setDate`, `setHours`, `setMinutes`, `setSeconds`, `setMilliseconds` (+ UTC variants)
- **Formatting**: `toString`, `toISOString`, `toUTCString`, `toDateString`, `toTimeString`, `toLocaleDateString`, `toLocaleTimeString`, `toLocaleString`, `toGMTString`
- **Conversion**: `valueOf`, `toJSON`, `Symbol.toPrimitive` (hint-based: "string" → toString, "number"/"default" → valueOf)
- **Legacy**: `getYear`, `setYear` (Annex B)
- **ISO 8601 parsing**: `Date.parse()` handles `YYYY-MM-DDTHH:mm:ss.sssZ` with timezone offset
- **Internal slot**: `[[DateValue]]` stored as non-enumerable property with `PropDescriptor`
- **Date algorithms**: `day_from_year` (floor division for pre-1970 correctness), `year_from_time` (linear adjustment), `month_from_time`, `date_from_time`, `week_day`, `make_day`/`make_date`, `time_clip`

Also improved JSON.stringify to:
- Walk full prototype chain when resolving `toJSON` methods
- Invoke any callable `toJSON` (not just MethodCallable) by promoting to InterpreterCallable
- Filter internal `[[...]]` properties from serialization

**Test262**: built-ins/Date 511/534 passing (95.7%), 60 skipped

### 9: P0–P3 Spec Compliance Sweep (+7,439 tests) — DONE

Massive compliance push addressing four priority areas identified in failure analysis:

- **P0: Error diagnostics** — `cmd/main/main.mbt` now catches `JsException(value)` and all `JsError` variants (TypeError, ReferenceError, SyntaxError, etc.) with proper formatting instead of printing opaque MoonBit error types. Makes CI failures actionable.
- **P1: Generator methods in class/object bodies** — `parse_class_method()` and `parse_object_literal()` now recognize `*` for generator method definitions (`class C { *gen() { yield 1; } }`, `{ *gen() { yield } }`). Full keyword-to-name mapping for method names.
- **P2: Destructuring defaults** — Added `DefaultPat(Pattern, Expr)` to the Pattern enum. Parser handles `= expr` after destructuring elements. Interpreter evaluates defaults when source value is `undefined`.
- **P3: Parser cleanup** — Fixed `{a: b = 1}` binding to correct name (`b` not `a`). Added `AssignTarget(Expr)` for member expression targets in destructuring assignment. Added `Of` as contextual identifier. Arrow function parameter fallback for complex patterns via `expr_to_ext_arrow_params`. Array elision holes.
- **PR review fixes** — Rest-element-must-be-last validation in destructuring patterns. `Yield` keyword accepted as method/property name in all keyword-to-name mappings.

**Test262**: 11,678 → 19,117 passing (45.27% → 74.17%)

### 10: P4 Object Descriptor Compliance — DONE

Comprehensive object descriptor compliance (P4 from IMPLEMENTATION_PRIORITY.md):

- **Symbol key support**: `defineProperty` and `getOwnPropertyDescriptor` now handle Symbol-keyed properties, using `symbol_properties`/`symbol_descriptors` storage
- **Function property descriptors**: `getOwnPropertyDescriptor` returns correct descriptors for function `length`, `name`, and `prototype`. `make_func`/`make_func_ext` now initialize `prototype` with `{writable: true, enumerable: false, configurable: false}`
- **Array/Map/Set/Promise targets**: `defineProperty` and `defineProperties` accept all JS object types as targets and descriptors. Array targets handle index and length property definition
- **TypeError enforcement**: Non-object descriptors throw TypeError. Non-object targets throw TypeError
- **Shared validation**: Extracted `validate_non_configurable` helper (~95 lines) used by both `defineProperty` and `defineProperties`, eliminating ~150 lines of duplicated validation logic
- **defineProperties fixes**: Throws TypeError on non-object, validates non-configurable transitions, getter/setter identity checks, only iterates enumerable own properties

**Test262**: built-ins/Object 2,547/2,868 passing (88.8%)

---

### 11: P5 eval() Semantics (+603 tests) — DONE

Full direct/indirect eval implementation per ES spec (EvalDeclarationInstantiation):

- **Direct eval detection**: `eval(...)`, `(eval)(...)`, `((eval))(...)` via `unwrap_grouping` helper. Per ES spec, grouping parentheses do not change the Reference type
- **Direct vs indirect**: Direct eval runs in caller's lexical environment; indirect eval (e.g., `(0, eval)(...)`) runs in global scope
- **NonConstructableCallable**: eval uses `NonConstructableCallable` to prevent `new eval()` (throws TypeError)
- **Variable environment**: `find_var_env()` walks the scope chain to find the enclosing function/global scope for var hoisting. eval inside a block correctly hoists to the function scope, not the block
- **Non-strict var leaking**: `hoist_declarations` on `var_env` lets var/function declarations escape the eval scope into the calling function
- **Strict mode isolation**: All declarations stay in the eval scope when eval is strict
- **EvalDeclarationInstantiation step 5.a**: `eval("var x")` at global scope throws SyntaxError if a global `let`/`const` x exists
- **EvalDeclarationInstantiation step 5.d**: `eval("var x")` in a block throws SyntaxError if any intermediate scope between the eval scope and the variable environment has a `let`/`const` x
- **FuncDecl var hoisting**: FuncDecl handler uses `has_var`/`assign_var` fallback (matching VarDecl) so function declarations in eval target the correct variable environment
- **ES spec evaluation order**: Callee/receiver resolved before arguments in all `eval_call` branches per spec section 13.3.6.1

**Test262**: language/eval-code 224/330 passing (67.9%), 17 skipped

---

### 12: P6 Strict-Mode Prerequisite Bundle (+3 tests) — DONE

Narrow, high-ROI strict-mode checks that gate many test262 syntax/runtime tests:

- **Duplicate parameters in strict functions**: `check_duplicate_params()` / `check_duplicate_params_ext()` raise SyntaxError when a function with `"use strict"` (or in a strict context) has duplicate parameter names
- **Assignment to `eval`/`arguments` in strict contexts**: `validate_strict_binding_name()` raises SyntaxError for assignments (=, +=, ++, etc.), variable declarations, function declarations, and parameter names
- **`delete` unqualified identifier**: `delete x` (where x is an identifier) raises SyntaxError in strict mode
- **Strict-only reserved words**: `implements`, `interface`, `package`, `private`, `protected`, `public` cannot be used as binding names in strict mode
- **Class body implicit strict mode**: `ensure_strict_body()` prepends `"use strict"` directive to class method and constructor bodies. `ClassConstructor` execution sets `self.strict = true`
- **Class constructor parameter validation**: `check_duplicate_params()` and `validate_strict_binding_name()` applied to class constructor parameters (class bodies are always strict)
- **Sloppy duplicate params fix**: `call_value` and `eval_new` now allow duplicate parameter names in sloppy mode (last value wins)

**Test262**: 19,720 → 19,723 passing (+3), language/function-code 166/173 (96.0%)
**Unit tests**: 30 new P6-specific tests (730 total, all passing)

---

### 13: P7 Promise Species Constructor and Complete Compliance (+1,080 tests) — DONE

Achieved 100% Promise test compliance through species constructor implementation and critical interpreter fixes:

**Promise Species Constructor (Subclassing Support)**:
- **`get_promise_species_constructor()`**: Implements ES spec's SpeciesConstructor(promise, %Promise%) algorithm. Consulted by `then`, `catch`, `finally` to determine which constructor to use for derived promises
- **`Promise[Symbol.species]`**: Getter returns `this`, enabling subclasses to override constructor selection via custom species
- **Constructor preservation**: Promise subclass instances store constructor in `properties["constructor"]` with proper descriptor, enabling species lookups on subsequent method calls
- **`Promise.reject` receiver support**: Refactored to use `create_promise_capability_from_constructor` for proper subclassing
- **Promise combinator receiver support**: All four combinators (`all`, `race`, `any`, `allSettled`) refactored to respect receiver constructor via `create_promise_capability_from_constructor(interp, _this, loc)`

**Critical Interpreter Fixes (Broad Test Impact)**:
- **Sloppy mode `this` normalization**: Functions called with `this` as `undefined`/`null` now correctly substitute `globalThis` in sloppy mode, while strict mode preserves original values. Implemented via `normalize_sloppy_this` helper applied in `call_value` and `eval_new`
- **`Function.prototype.apply` array-like support**: Fixed to accept any array-like object (objects with `length` property), not just Array instances. Handles `arguments` object forwarding pattern via `to_array_like_length` and computed property iteration
- **Arguments object in constructors**: Class constructors and super constructors now have access to `arguments` object via `make_arguments_object` binding in constructor environments
- **Function `prototype.constructor` link**: Functions now establish bidirectional reference: `func.prototype.constructor === func`, enabling navigation from instances back to constructors

**Test Results**:
- **Test262**: 19,723 → 20,803 passing (+1,080), **82.41%** pass rate (was 78.22%)
- **built-ins/Promise**: 599/599 passing (**100%**, was 580/599 or 96.8%), 41 skipped
- **language/block-scope**: 106/106 passing (100%, was 47/106 or 44.3%), 39 skipped
- **language/expressions**: 4,849 passing (88.4%, was 84.0%)
- **language/statements**: 3,449 passing (82.7%, was 77.0%)
- **Unit tests**: 3 new tests for Promise species, apply array-like, and constructor arguments (763 total)

**Validation**:
```bash
python3 test262-runner.py --filter "built-ins/Promise" --summary
# Result: 599/599 passing (100.0%), 41 skipped, 0 failed
```

**Note**: Proxy support was added in Phase 15, resolving the previously deferred `this-value-proxy.js` test.

---

### 14: Small Compliance Sweep (+67 tests) — DONE

Targeted quick wins across Unicode whitespace, Number, and String built-ins:

**Lexer Enhancements**:
- **Unicode whitespace recognition**: Extended `is_js_whitespace()` to include all ECMAScript Unicode Space_Separator (Zs) characters: U+1680 (OGHAM SPACE MARK), U+2000-200A (EN QUAD through HAIR SPACE), U+202F (NARROW NO-BREAK SPACE), U+205F (MEDIUM MATHEMATICAL SPACE), U+3000 (IDEOGRAPHIC SPACE)
- **Line terminator handling**: Added U+2028 (LINE SEPARATOR) and U+2029 (PARAGRAPH SEPARATOR) recognition for proper line counting in tokenization
- **UTF-8 validation**: Confirmed MoonBit's `String::to_array()` correctly decodes UTF-8 multi-byte sequences into Unicode code points

**Number.prototype Additions**:
- **`toLocaleString()`**: Implemented with proper primitive/object wrapper handling, delegates to `toString()` for baseline compliance (full Intl.NumberFormat support deferred)

**String.prototype Additions**:
- **Trim aliases**: Added `trimLeft`/`trimRight` as deprecated aliases for `trimStart`/`trimEnd` per Annex B
- **`toLocaleString()`**: Simple delegation implementation for baseline compliance
- **`matchAll()`**: Iterator-based method with global flag validation, uses `regex_search_all()` for match collection, returns proper iterator with `next()` yielding `{value, done}` objects (44.4% pass rate - basic functionality working, advanced Symbol.matchAll cases deferred)

**Test262 Results**:
- **Overall**: 20,803 → 20,870 passing (+67), **82.7%** pass rate (was 82.41%)
- **language/white-space**: 49/67 (73.1%) → 66/67 (**98.5%**, +17 tests)
- **Number.prototype.toLocaleString**: 3/3 passing (100%)
- **String.prototype.trimLeft/trimRight**: 8/8 passing (100%)
- **String.prototype.matchAll**: 4/9 passing (44.4%, basic iterator protocol working)
- **built-ins/Number**: 265/320 passing (82.8%)
- **built-ins/String**: 1,054/1,150 passing (91.7%)

**Test Runner Fix**:
- Added `target/js/debug/build/cmd/main/main.js` to test runner's build path detection candidates for proper engine discovery

**Remaining Work**:
- One whitespace test failure (`S7.2_A5_T5.js`) requires rejecting Unicode escape sequences representing whitespace in identifier positions (e.g., `var\u00A0x;` should throw SyntaxError)
- `matchAll` Symbol.matchAll integration for full spec compliance (5/9 remaining tests)

---

### 15: Proxy and Reflect (+877 tests) — DONE

Full ES6 Proxy and Reflect implementation with 13 proxy traps and 13 Reflect methods:

**Proxy Implementation** (builtins_proxy.mbt):
- **`Proxy(target, handler)` constructor**: Creates proxy with `ProxyData` struct containing mutable `target`/`handler` fields
- **`Proxy.revocable(target, handler)`**: Returns `{proxy, revoke}` object; `revoke()` sets target/handler to `None`
- **13 traps**: `get`, `set`, `has`, `apply`, `construct`, `deleteProperty`, `defineProperty`, `ownKeys`, `preventExtensions`, `isExtensible`, `getPrototypeOf`, `setPrototypeOf`, `getOwnPropertyDescriptor`
- **ProxyData struct**: Mutable `target` and `handler` fields (None = revoked)
- **Helper functions**: `get_proxy_trap()` (with prototype chain walk), `get_proxy_target()`, `get_proxy_handler()` with TypeError on revoked proxy

**Reflect API** (builtins_reflect.mbt, ~820 lines):
- **13 methods**: `apply`, `construct`, `defineProperty`, `deleteProperty`, `get`, `getOwnPropertyDescriptor`, `getPrototypeOf`, `has`, `isExtensible`, `ownKeys`, `preventExtensions`, `set`, `setPrototypeOf`
- **`Reflect.defineProperty`**: Full non-configurable validation (extensibility check, accessor/data conflict, enumerable/configurable immutability, getter/setter identity, writable/value constraints) — returns `Bool(false)` on rejection per spec
- **`Reflect.setPrototypeOf`**: Returns `Bool(false)` for non-extensible objects
- **`Reflect.has`**: Checks both `data.properties` and `data.descriptors` for accessor-only properties
- **`Reflect.set`**: Pre-validates write constraints (accessor getter-only, non-writable, non-extensible+descriptor-only) and returns `Bool(false)` on failure
- **`create_list_from_array_like()`**: Shared helper for array-like argument conversion (used by `apply` and `construct`)
- **`unwrap_proxy_target()`**: Recursively unwraps nested Proxy chains to get underlying ObjectData
- **`Reflect.ownKeys`**: `InterpreterCallable` (not `NativeCallable`) to support invoking ownKeys trap; handles Object, Array, and Proxy targets

**Interpreter Integration**:
- **`for-in` with Proxy**: `collect_for_in_keys` throws TypeError for revoked proxies
- **`instanceof` with Proxy**: Checks `Symbol.hasInstance` on proxy before falling back to prototype chain
- **`deleteProperty` strict mode**: Throws TypeError when proxy's deleteProperty trap returns `false` in strict mode
- **`apply` trap**: Recursive callability check for nested `Proxy(Proxy(Function))` chains
- **`construct` trap**: Verifies target is constructible before executing construct trap
- **JSON.stringify**: Unwraps Proxy to target for serialization
- **Object.assign**: Extended with Proxy support; throws TypeError for revoked Proxy sources
- **Object.defineProperty/defineProperties Proxy paths**: Full `validate_non_configurable` call, accessor/data conflict validation, extensibility check, getter/setter callability validation
- **Object.getOwnPropertyDescriptor/getPrototypeOf/create**: All extended with Proxy support

**PR Review Fixes** (30 comments, 24 resolved across 4 commits):

*Commit 1* (4 issues): Reflect.construct newTarget, getOwnPropertyDescriptor accessor, Reflect.set non-writable, Reflect.get Symbol keys

*Commit 2* (12 issues): JSON.stringify Proxy, Object.assign Proxy, Object.defineProperty Proxy, Object.getOwnPropertyDescriptor Proxy, for-in ownKeys, instanceof Symbol.hasInstance, deleteProperty strict mode, apply callability, Object.getPrototypeOf revoked Proxy, Object.create Proxy, Object.defineProperties Proxy, deduplicated array-like conversion

*Commit 3*: Enabled Proxy/Reflect test262 tests, fixed all Reflect methods to accept Proxy arguments

*Commit 4* (10 issues): Reflect.defineProperty validation, Reflect.setPrototypeOf extensibility, Reflect.has descriptors, Reflect.set descriptor-aware extensibility, Object.assign revoked Proxy TypeError, Object.defineProperty Proxy validate_non_configurable, Object.defineProperties Proxy full validation, Object.create unreachable code fix, get_proxy_trap prototype chain walk, construct_value target constructability check. Also eliminated all 20 compiler warnings (deprecated_syntax `fn` → `fn raise`).

**Test262 Results**:

| Category | Passed | Failed | Skipped | Rate |
|----------|--------|--------|---------|------|
| built-ins/Proxy | 257 | 15 | 39 | 94.5% |
| built-ins/Reflect | 152 | 1 | 0 | 99.3% |

**Overall**: 20,870 → 21,747 passing (+877), **83.16%** pass rate (was 82.7%), no regressions

**Remaining 16 test failures** are pre-existing engine limitations:
- `with` statement not supported (4 Proxy tests)
- Boxed primitives `new String()`, `new Number()` not properly represented as Object (10 tests)
- Module import issue (1 test)
- Array length edge case (1 test)

**Known limitations** (6 unresolved PR review items, deferred — require larger refactoring):
- `Object.getPrototypeOf` does not invoke the `getPrototypeOf` trap (reads target prototype directly; needs `NativeCallable` → `InterpreterCallable` conversion)
- `for-in` does not invoke the `ownKeys` trap (delegates to target directly; `collect_for_in_keys` needs interpreter parameter)
- `instanceof` revoked Proxy does not invoke `getPrototypeOf` trap for prototype chain walk
- `create_list_from_array_like` bypasses Proxy traps (reads `.properties` directly; needs interpreter parameter)
- `Reflect.construct` rewires `newTarget` prototype after construction instead of before (spec requires creating object with `newTarget.prototype` before constructor runs)
- `unwrap_proxy_target` returns `None` for non-Object targets (Array, Map, Set, Promise); Reflect methods that use it may throw incorrect TypeError for Proxies wrapping non-Object types

**Files Changed**:
- `interpreter/builtins_proxy.mbt` (~240 lines) — Proxy constructor, revocable, trap helpers with prototype chain walk
- `interpreter/builtins_reflect.mbt` (~820 lines) — All 13 Reflect methods with Proxy support and full validation
- `interpreter/interpreter.mbt` — for-in, instanceof, deleteProperty, apply, construct trap fixes
- `interpreter/builtins.mbt` — JSON.stringify Proxy fix, Proxy/Reflect registration
- `interpreter/builtins_object.mbt` — Object.assign/defineProperty/getOwnPropertyDescriptor/getPrototypeOf/create/defineProperties Proxy integration with full validation
- `test262-runner.py` — Removed Proxy/Reflect from skip lists
- `test262-analyze.py` — Removed Proxy/Reflect from skip lists

**Unit tests**: 799 total (+36), 799 passed, 0 failed

---

### 16: TypedArray, ArrayBuffer, and DataView — DONE

Full TypedArray/ArrayBuffer/DataView implementation (~3,724 lines of new builtin code):

**ArrayBuffer** (builtins_arraybuffer.mbt, ~400 lines):
- **Constructor**: `new ArrayBuffer(byteLength)` with non-negative length validation
- **`ArrayBuffer.isView()`**: Detects TypedArray and DataView instances
- **`ArrayBuffer.prototype.slice()`**: Creates new ArrayBuffer with byte range copy, detachment check
- **`ArrayBuffer.prototype.byteLength`**: Getter with detachment check (throws TypeError if detached)
- **`$262.detachArrayBuffer()`**: Full implementation (was previously a no-op stub)
- **Detachment tracking**: Global registry of detached buffer IDs via `detach_arraybuffer()` / `is_arraybuffer_detached()`

**TypedArray** (builtins_typedarray.mbt, ~2,414 lines):
- **9 typed array types**: `Int8Array`, `Uint8Array`, `Uint8ClampedArray`, `Int16Array`, `Uint16Array`, `Int32Array`, `Uint32Array`, `Float32Array`, `Float64Array`
- **Constructors**: From length, from array/iterable, from another TypedArray, from ArrayBuffer with optional byteOffset/length. Rejects detached ArrayBuffer and negative/unaligned byteOffset
- **Prototype methods**: `set`, `subarray`, `slice`, `copyWithin`, `fill`, `indexOf`, `lastIndexOf`, `includes`, `join`, `toString`, `reverse`, `sort` (with custom comparator, NaN-last), `at`, `forEach`, `map`, `filter`, `reduce`, `reduceRight`, `every`, `some`, `find`, `findIndex`
- **Static methods**: `TypedArray.from()` (with optional mapFn and thisArg), `TypedArray.of()`
- **Iterators**: `entries()`, `keys()`, `values()`, `Symbol.iterator` with buffer detachment checks during iteration
- **Properties**: `buffer`, `byteLength`, `byteOffset`, `length`, `BYTES_PER_ELEMENT`, `Symbol.toStringTag`
- **Indexed access**: Canonical numeric index string handling per spec in get/set paths (3 sites in interpreter.mbt)
- **Buffer detachment validation**: `validate_typedarray_buffer()` called by all iteration methods (forEach, map, filter, reduce, reduceRight, every, some, find, findIndex)

**DataView** (builtins_dataview.mbt, ~910 lines):
- **Constructor**: `new DataView(buffer, byteOffset?, byteLength?)` with validation
- **Getter methods**: `getInt8`, `getUint8`, `getInt16`, `getUint16`, `getInt32`, `getUint32`, `getFloat32`, `getFloat64` with endianness support
- **Setter methods**: `setInt8`, `setUint8`, `setInt16`, `setUint16`, `setInt32`, `setUint32`, `setFloat32`, `setFloat64` with endianness support
- **Receiver brand check**: Validates `this` is actually a DataView (not TypedArray)
- **Properties**: `buffer`, `byteLength`, `byteOffset`, `Symbol.toStringTag`

**Interpreter Integration**:
- `Object.prototype.toString` checks `Symbol.toStringTag` via `get_tostringtag_value()` on prototype chain
- `for-in` enumerates numeric indices, skips internal `[[...]]` slots
- Canonical numeric index string handling: `"-0"` correctly falls through to ordinary property access (not a canonical index per spec)

**PR Review Fixes** (6 commits, 19 comments addressed):
- Sort comparator support and NaN handling
- TypedArray.from mapFn argument
- Int32 overflow fix for Float32Array element read (b3 >= 128)
- Denormalized float32 encoding off-by-one fix
- forEach/map/filter/reduce/reduceRight/every/some/find/findIndex detachment validation
- Missing iteration methods added to prototype
- DataView receiver brand check
- `-0` canonical numeric index fix (3 sites)

**Test262 (full run 2026-02-14)**: 23,012 / 27,491 passing (**83.7%**, was 82.7%). +2,142 new tests passing. Key category results:
- `built-ins/DataView`: 353/388 passing (**91.0%**, was 2.3%)
- `built-ins/ArrayBuffer`: 73/81 passing (**90.1%**, was 16.4%)
- `built-ins/TypedArrayConstructors`: 309/359 passing (**86.1%**, new)
- `built-ins/TypedArray`: 428/777 passing (**55.1%**, was 0%)
- `built-ins/Uint8Array`: 44/68 passing (**64.7%**, new)

**Unit tests**: 878 total (+79 new), 878 passed, 0 failed

---

### 17: TypedArray Prototype Chain Conformance (+323 tests) — DONE

Created `%TypedArray%` intrinsic constructor and established proper prototype chain per ES spec:

**%TypedArray% Constructor** (abstract, not directly constructible):
- Created as a Function object with `TypedArray` name
- Throws TypeError when directly constructed (per spec: "Abstract class TypedArray not directly constructable")
- `%TypedArray%.prototype` points to the shared TypedArray prototype (with all shared methods)
- `%TypedArray%.prototype.constructor` links back to `%TypedArray%`

**Prototype Chain Fix**:
- Each per-type constructor (Int8Array, Uint8Array, etc.) now has `[[Prototype]]` set to `%TypedArray%` constructor
  - Before: `Object.getPrototypeOf(Int8Array)` → `null`
  - After: `Object.getPrototypeOf(Int8Array)` → `%TypedArray%`
- This enables the test262 pattern: `Object.getPrototypeOf(Int8Array.prototype) === TypedArray.prototype`
- Stored as `[[TypedArrayConstructor]]` internal builtin for engine access

**Test262 Results**:

| Category | Before | After | Rate |
|----------|--------|-------|------|
| built-ins/TypedArray | 428/777 | 721/777 | **92.8%** (+293) |
| built-ins/TypedArrayConstructors | 309/359 | 339/359 | **94.4%** (+30) |

**Overall**: 23,012 → ~23,335 passing (+323 tests), **84.9%** pass rate (was 83.7%)

**Unit tests**: 881 total (+3 new), 881 passed, 0 failed

---

### 18: Boxed Primitives and TypedArray Constructor Name Fix (+162 tests) — DONE

Implemented ES spec-compliant boxed primitive wrappers and fixed TypedArray constructor name inheritance regression:

**Boxed Primitives** (`new String/Number/Boolean`):
- **String constructor**: When called with `new`, returns Object with `[[StringData]]` internal slot, indexed character properties, and `length`. Without `new`, returns primitive string (type coercion)
- **Number constructor**: When called with `new`, returns Object with `[[NumberData]]` internal slot. Without `new`, returns primitive number
- **Boolean constructor**: When called with `new`, returns Object with `[[BooleanData]]` internal slot. Without `new`, returns primitive boolean
- **`Object()` ToObject wrapping**: `Object("hello")` wraps to boxed String, `Object(42)` to boxed Number, `Object(true)` to boxed Boolean, `Object(Symbol())` to boxed Symbol
- **Prototype storage**: `[[StringPrototype]]`, `[[NumberPrototype]]`, `[[BooleanPrototype]]` stored as builtins for cross-module access
- **ToPrimitive coercion**: `loose_equal` updated to unwrap boxed primitives (`[[NumberData]]`/`[[BooleanData]]`/`[[StringData]]`) for `==` comparisons
- **`to_number` extraction**: Boxed Number/Boolean/String objects unwrap to their primitive values during numeric coercion
- **`Show` for Value**: Boxed primitives display their underlying primitive value (not `[object String]`)
- **`Boolean.prototype.valueOf/toString`**: Handle boxed Boolean objects (check `class_name == "Boolean"`, extract `[[BooleanData]]`)
- **`this_to_string`**: Updated to use `[[StringData]]` internal slot for String prototype methods

**TypedArray Constructor Name Fix**:
- Phase 17 set each constructor's `[[Prototype]]` to `%TypedArray%`, which caused `Int8Array.name` to resolve to `"TypedArray"` via prototype chain walk
- Fix: Added own `name` and `length` properties (with correct descriptors: non-writable, non-enumerable, configurable) to each typed array constructor's `ctor_props`
- This prevents prototype chain inheritance of the `%TypedArray%` constructor's name

**Test262 Results (targeted verification)**:

| Category | Before | After | Rate |
|----------|--------|-------|------|
| built-ins/Object | 3,126/3,373 | 3,234/3,373 | **95.9%** (+108) |
| built-ins/String | 1,099/1,195 | 1,137/1,195 | **95.1%** (+38) |
| built-ins/Number | 280/335 | 287/335 | **85.7%** (+7) |
| built-ins/TypedArray | 721/777 | 726/777 | **93.4%** (+5) |
| built-ins/TypedArrayConstructors | 339/359 | 342/359 | **95.3%** (+3) |
| built-ins/Boolean | 41/49 | 42/49 | **85.7%** (+1) |

**Overall**: ~23,335 → ~23,500 passing (+162 targeted), **~85.5%** pass rate (was 84.9%)

**Unit tests**: 881 total, 881 passed, 0 failed

---

### 19: Symbol/TypedArray Prototype Fixes and Full Verification (+525 tests) — DONE

Registered dedicated prototype builtins and fixed prototype chain conformance:

**Symbol.prototype Registration**:
- Registered `[[SymbolPrototype]]` via `env.def_builtin()` after Symbol constructor creation in `builtins.mbt`
- Updated `Object()` ToObject Symbol boxing branch in `builtins_object.mbt` to use `env.get("[[SymbolPrototype]]")` instead of `obj_proto` (Object.prototype)
- Matches the pattern already used by String/Number/Boolean boxing branches

**Function.prototype Registration**:
- Registered `[[FunctionPrototype]]` via `env.def_builtin()` in `setup_function_builtins`
- Enables other builtins to look up Function.prototype without direct variable access

**%TypedArray% Constructor Conformance**:
- Added `name` and `length` property descriptors (`{writable: false, enumerable: false, configurable: true}`) to `%TypedArray%` constructor
- Set `%TypedArray%` constructor's `[[Prototype]]` to Function.prototype (was `Null`)
- Per ES spec, `Object.getPrototypeOf(%TypedArray%)` should be `Function.prototype`

**Test262 Results (full run 2026-02-15)**:

| Category | Before | After | Rate |
|----------|--------|-------|------|
| built-ins/Reflect | 152/153 | 153/153 | **100.0%** (+1) |
| built-ins/Object | 3,126/3,373 | 3,234/3,373 | **95.9%** (+108) |
| built-ins/String | 1,099/1,195 | 1,137/1,195 | **95.1%** (+38) |
| built-ins/TypedArray | 428/777 | 726/777 | **93.4%** (+298) |
| built-ins/TypedArrayConstructors | 309/359 | 342/359 | **95.3%** (+33) |
| built-ins/Array | 2,494/2,945 | 2,517/2,945 | **85.5%** (+23) |
| built-ins/Number | 280/335 | 287/335 | **85.7%** (+7) |
| built-ins/RegExp | 615/837 | 621/837 | **74.2%** (+6) |
| built-ins/Proxy | 257/272 | 262/272 | **96.3%** (+5) |
| built-ins/JSON | 127/135 | 132/135 | **97.8%** (+5) |
| built-ins/ArrayBuffer | 73/78 | 73/78 | **93.6%** (-3 fail) |
| built-ins/Function | 340/411 | 342/411 | **83.2%** (+2) |

**Overall**: 23,012 → 23,537 passing (+525), **85.6%** pass rate (was 83.7%)

**Unit tests**: 881 total, 881 passed, 0 failed

---

### 22: Tier 1+2 Conformance Improvements (+587 tests) — DONE

Comprehensive conformance push implementing most of the Tier 1 and Tier 2 items from the roadmap analysis:

**Tier 1 — String Escape Sequences (1a)**:
- Added `\r` (carriage return), `\b` (backspace), `\v` (vertical tab), `\f` (form feed), `\0` (null), `\xHH` (hex escapes) to both string literal and template literal handlers in `lexer.mbt`
- PR review fix: line continuation support (`\` followed by newline) in string/template literals

**Tier 1 — `%ThrowTypeError%` Intrinsic (1b)**:
- Created single frozen `%ThrowTypeError%` function per ES spec §10.2.4
- Installed as accessor descriptor (getter/setter) on `arguments.callee`/`arguments.caller` in strict mode
- Installed on `Function.prototype.caller` and `Function.prototype.arguments`

**Tier 1 — Import Syntax Validation (1e)**:
- Parser rejects unicode-escaped reserved words in binding positions (`var`, `let`, `const`, `function`, `class`, `catch`, `import` declarations)
- Lexer emits escaped reserved words as `Ident` tokens (valid in IdentifierName positions like property keys and member access)

**Tier 2 — `with` Statement (2b)**:
- New `WithStmt(Expr, Stmt)` AST node and parser rule
- Object environment record: new scope type in `environment.mbt` where property lookups check a target object first, then fall through to outer scope
- SyntaxError in strict mode (regardless of `--annex-b` flag)
- PR review fixes: primitive-to-object coercion (ToObject), TypeError for null/undefined, inherited binding writeback

**Tier 2 — Annex B Block-Level Function Hoisting (2a)**:
- Per Annex B.3.3, block-level `FunctionDeclaration` in sloppy mode creates `var` binding in enclosing function scope
- At function entry: `var` binding initialized to `undefined`
- At block containing the declaration: block-scoped binding created
- When execution reaches declaration: block-scoped value propagated to function-scope `var` binding
- Strict mode preserves block-scoped behavior (no dual binding)
- PR review fix: bare FuncDecl in WithStmt body

**Tier 2 — RegExp Symbol Methods (2c)**:
- `RegExp.prototype[Symbol.match]`: match semantics with global/sticky flag handling
- `RegExp.prototype[Symbol.replace]`: replacement patterns (`$1`, `$&`, `$'`, `` $` ``, `$$`)
- `RegExp.prototype[Symbol.split]`: split with regex, respecting `limit`
- `RegExp.prototype[Symbol.search]`: return index of first match
- `String.prototype.match/replace/split/search` delegate to symbol methods on the argument
- Well-known symbol refs (`well_known_match_sym`, etc.) added to `value.mbt`

**PR Review Fixes**:
- Lexer: line continuation support (`\` + newline) in string/template literals
- Lexer: escaped reserved words emit as `Ident` tokens for IdentifierName positions
- Parser: reject escaped reserved words in binding positions
- DataView: `to_index()` helper for ToIndex operation, preventing PanicError on Infinity/NaN/negative
- DataView: skip immutable-arraybuffer tests (unsupported feature)
- `String.prototype.replaceAll`: enforce global-flag check before Symbol.replace delegation
- `with` statement: ToObject coercion for primitives, TypeError for null/undefined
- RegExp `Symbol.split`: ToUint32 for limit (modulo 2^32 wrap)
- Annex B hoisting: bare FuncDecl in WithStmt body

**Test262 Results (full run 2026-02-17)**:

| Category | Before | After | Rate | Delta |
|----------|--------|-------|------|-------|
| annexB/language | 311/817 | 711/817 | **87.0%** | +400 |
| built-ins/RegExp | 652/844 | 733/844 | **86.8%** | +81 |
| built-ins/DataView | 353/388 | 377/377 | **100.0%** | +24 |
| language/statements | 3,502/4,221 | 3,546/4,221 | **84.0%** | +44 |
| language/identifiers | 154/207 | 163/207 | **78.7%** | +9 |
| language/eval-code | 224/330 | 232/330 | **70.3%** | +8 |
| built-ins/Proxy | 262/272 | 264/272 | **97.1%** | +2 |

**Overall**: 23,875 → 24,462 passing (+587), **86.5% → 88.1%** pass rate (24,462/27,757 executed)

**Files Changed**:
- `lexer/lexer.mbt` — String escape sequences, line continuation, escaped reserved word handling
- `parser/parser.mbt` — Escaped reserved word rejection in binding positions
- `interpreter/interpreter.mbt` — `with` statement execution, Annex B block-level function hoisting, `to_index()` helper
- `interpreter/value.mbt` — Well-known symbol refs for match/replace/search/split
- `interpreter/builtins_regex.mbt` — RegExp Symbol.match/replace/split/search methods
- `interpreter/builtins_string.mbt` — String method delegation to symbol methods, replaceAll global-flag check
- `interpreter/builtins_dataview.mbt` — ToIndex validation for byte offsets
- `test262-runner.py` — Skip immutable-arraybuffer tests

---

## Recommended Next Steps for Conformance

Prioritized by estimated test impact and implementation effort. These are the highest-ROI items for pushing past 90% test262 pass rate.

### Path to 90%

Current: **24,519 / 27,599 executed (88.8%)**. Need **~341 more passing tests** to reach 90%. Tiers 1-2 are largely complete (Phase 22), Tier 4 polish done (Phase 23). The remaining items below are ordered by ROI.

### Tier 1 — Quick Wins (~220+ tests, low effort) — ✅ Mostly DONE (P22)

| # | Fix | Est. Impact | Status | Notes |
|---|-----|-------------|--------|-------|
| **1a** | **String escape sequences** (`\r`, `\b`, `\v`, `\f`, `\0`, `\xHH`) | ~90-120 tests | ✅ DONE (P22) | Also added line continuation support |
| **1b** | **`%ThrowTypeError%` intrinsic** | ~13 tests | ✅ DONE (P22) | Strict arguments.callee/caller, Function.prototype.caller/arguments |
| **1c** | **Annex B HTML string methods** | +13 tests | ✅ DONE (P21) | `get_string_method` gated behind `annex_b~` param |
| **1d** | **`RegExpStringIteratorPrototype`** (for `String.prototype.matchAll`) | ~17 tests | Remaining | Proper iterator prototype with `[Symbol.toStringTag]` |
| **1e** | **Import syntax validation** (reject escaped keywords, duplicate bound names) | ~10 tests | ✅ DONE (P22) | Escaped reserved words in binding positions |

**Details:**

**1a — String escape sequences.** ✅ DONE (P22). Added `\r`, `\b`, `\v`, `\f`, `\0`, `\xHH` hex escapes to both the string literal handler and template literal handler in `lexer.mbt`. Also added line continuation support (`\` followed by newline) in PR review fixes.

**1b — `%ThrowTypeError%` intrinsic.** ✅ DONE (P22). Created a single frozen `%ThrowTypeError%` function installed as accessor descriptors on `arguments.callee`/`arguments.caller` (strict mode) and `Function.prototype.caller`/`Function.prototype.arguments`.

**1c — Annex B HTML string methods.** ✅ DONE (P21). `get_string_method` gated behind `annex_b~` parameter.

**1d — `RegExpStringIteratorPrototype`.** All 17 `built-ins/RegExpStringIteratorPrototype` tests still fail (0%). `String.prototype.matchAll` is partially implemented but needs a proper iterator prototype with `[Symbol.toStringTag]` set to `"RegExp String Iterator"`, and `next` method with correct `name`/`length` descriptors. Follows the same pattern used for Map/Set/Array/String iterator prototypes in Phase 20.

### Tier 2 — Medium Wins (~650-800 tests, medium effort) — ✅ DONE (P22)

| # | Fix | Est. Impact | Status | Notes |
|---|-----|-------------|--------|-------|
| **2a** | **Annex B block-level function hoisting** (sloppy mode) | ~504 tests | ✅ DONE (P22) | annexB/language 38.1% → **87.0%** (+400) |
| **2b** | **`with` statement** | ~151 tests | ✅ DONE (P22) | Object environment record, SyntaxError in strict mode, primitive ToObject coercion |
| **2c** | **RegExp `[Symbol.match]`/`[Symbol.replace]`/`[Symbol.split]`/`[Symbol.search]`** | ~50+ tests | ✅ DONE (P22) | RegExp 77.3% → **86.8%** (+81) |

**Details:**

**2a — Annex B block-level function hoisting.** ✅ DONE (P22). Implemented per Annex B.3.3: block-level function declarations in sloppy mode create `var` bindings in enclosing function scope, with value propagation at execution time. Strict mode preserves block-scoped behavior. Also handles bare FuncDecl in WithStmt body (PR review fix). `annexB/language` improved from 38.1% to **87.0%** (+400 tests).

**2b — `with` statement.** ✅ DONE (P22). Added `WithStmt` AST node, parser rule, and object environment record in `environment.mbt` where property lookups check the target object first. SyntaxError in strict mode. PR review fixes added primitive-to-object coercion (ToObject) and TypeError for null/undefined, plus inherited binding writeback.

**2c — RegExp well-known symbol methods.** ✅ DONE (P22). Installed `[Symbol.match]`, `[Symbol.replace]`, `[Symbol.split]`, `[Symbol.search]` on `RegExp.prototype`. Updated `String.prototype.match/replace/split/search` to delegate to symbol methods. PR review fixes added `String.prototype.replaceAll` global-flag enforcement and `Symbol.split` ToUint32 limit handling.

### Tier 3 — Feature Implementations (~3,000+ skipped tests unlocked, high effort)

These are major missing language features. Each unlocks a large batch of currently-skipped tests but requires significant implementation work.

| # | Feature | Skipped Tests | Effort | Notes |
|---|---------|---------------|--------|-------|
| **3a** | **Class public fields** | ~723 | Medium | `class C { x = 1; static y = 2; }` field initializer syntax |
| **3b** | **async/await** | ~500+ executing + ~3,500 skipped | High | Syntactic sugar over Promises + generator-like suspension |
| **3c** | **Class private fields/methods** | ~2,437 | High | `#private` syntax with brand-check semantics |
| **3d** | **RegExp named groups & lookbehind** | ~679+ skipped | Medium | `(?<name>...)` capture groups and `(?<=...)`/`(?<!...)` assertions |

**Details:**

**3a — Class public fields.** Currently all tests with the `class-fields-public` and `class-static-fields-public` features are skipped (~723 tests). Implementation requires:
1. Parser: recognize field declarations in class bodies (`x = expr;` and `static x = expr;`).
2. New AST nodes for `ClassField(name, initializer, is_static)`.
3. Interpreter: evaluate field initializers in `[[Construct]]` (instance fields) or class definition time (static fields).
4. Field initializers run with `this` bound to the new instance (or the constructor for static).
5. The initializer expression is evaluated per the `[[Define]]` semantics (not `[[Set]]`), meaning it bypasses setters.

**3b — async/await.** The generator infrastructure (Phase 8) and Promise system (Phase 13, 99.4%) provide the foundation. Implementation requires:
1. Parser: `async function`, `async () =>`, `await expr` syntax.
2. Interpreter: async functions return Promises; `await` suspends and resumes via microtask queue (similar to `yield` in generators).
3. Test runner: remove `async-functions` from `SKIP_FEATURES` in `test262-runner.py`.
4. Unblocks `async-iteration` as a follow-up (~3,731 skipped tests).

**3c — Class private fields/methods.** The largest single batch of skipped tests (~2,437 across `class-fields-private`, `class-methods-private`, `class-static-fields-private`, `class-static-methods-private`). Requires:
1. Parser: `#name` syntax for fields, methods, accessors, and static variants.
2. **Brand checking**: each class gets a unique brand; instances are stamped with the brand at construction time; accessing `#field` on an object without the brand throws `TypeError`.
3. Private name resolution: lexical scope model where `#name` resolves to a per-class WeakMap-like storage slot.
4. This is the most complex single feature due to the interaction between brand checks, inheritance, and static private members.

**3d — RegExp named groups & lookbehind.** Currently skipped via `regexp-named-groups`, `regexp-lookbehind`, and `regexp-unicode-property-escapes` features. Implementation:
1. Named groups `(?<name>...)`: extend `RegexNode` enum with `NamedGroup(name, inner)`, populate `groups` object on match result.
2. Lookbehind `(?<=...)` / `(?<!...)`: requires backward matching from the current position (more complex than lookahead).
3. Unicode property escapes `\p{Letter}` / `\P{Script=Greek}`: requires Unicode property tables (large data dependency).

### Tier 4 — Polish & Edge Cases (~200-300 tests, varied effort) — ✅ Mostly DONE (P23)

Targeted fixes for specific failing subcategories within otherwise high-performing areas.

| # | Fix | Est. Impact | Effort | Category |
|---|-----|-------------|--------|----------|
| **4a** | GeneratorFunction constructor | ~19 tests | Medium | ✅ DONE (P23) — `built-ins/GeneratorFunction` 9.5% → **100.0%** |
| **4b** | Generator prototype chain fix | ~7 tests | Medium | ✅ DONE (P23) — `built-ins/GeneratorPrototype` 73.8% → **88.5%** |
| **4c** | `language/directive-prologue` edge cases | ~13 tests | Low | ✅ Improved (P23) — `language/directive-prologue` 79.0% (escaped "use strict" rejection) |
| **4d** | `language/line-terminators` (beyond `\r`) | ~10 tests | Low | ✅ DONE (P23) — 48.8% → **68.3%** |
| **4e** | `built-ins/undefined` conformance | ~3 tests | Very Low | ✅ DONE (P23) — 57.1% → **71.4%** |
| **4f** | Eval completion values | ~30-50 tests | Medium-High | ✅ Improved (P23) — loop/switch completion values fixed |
| **4g** | Module system improvements | ~50-100 tests | High | Remaining — `language/module-code` (36.5%) |

**Details:**

**4a — GeneratorFunction constructor.** ✅ DONE (P23). Implemented `GeneratorFunction("a", "yield a")` constructor by extending the `Function` constructor logic. Set up `GeneratorFunction` prototype chain with `%GeneratorFunction.prototype%` and proper `constructor` link. `built-ins/GeneratorFunction` improved from 9.5% to **100.0%** (21/21).

**4b — Generator prototype chain fix.** ✅ DONE (P23). Fixed generator function prototype so `Object.getPrototypeOf(genFunc)` returns `%GeneratorFunction.prototype%` instead of `null`. `built-ins/GeneratorPrototype` improved from 73.8% to **88.5%** (54/61). Remaining 7 failures involve `return()` with `finally` block interaction in the statement-replay model.

**4c — Directive prologue fix.** ✅ Improved (P23). Fixed directive prologue scanning to check full prologue (not just first statement) and reject escaped `"use strict"` (e.g., `"use\x20strict"`). Added `has_escape` field to `StringLit` AST node.

**4d — `language/line-terminators`.** ✅ DONE (P23). Full ECMAScript LineTerminator support: `\u2028`/`\u2029` recognized in lexer main loop, single/multi-line comments, string/template literals, and line continuation. Fixed `\r` handling as line terminator (not whitespace). 48.8% → **68.3%**.

**4e — `built-ins/undefined` conformance.** ✅ DONE (P23). Added `undefined`, `NaN`, `Infinity` as globalThis properties with correct descriptors (non-writable, non-enumerable, non-configurable). 57.1% → **71.4%**.

**4f — Eval completion values.** ✅ Improved (P23). Fixed eval completion values for loops (`while`, `for`, `do-while`, `for-in`, `for-of`) and switch statements to properly propagate body values. The 97 remaining failures in `language/eval-code` involve strict-mode scoping, arrow function `this` binding, and nested `var` hoisting.

**4g — Module system.** The 198 failures in `language/module-code` and 82 in `language/import` stem from: `import defer` syntax (Stage 3, ~50 tests), circular import resolution, live binding updates, `export * as ns` namespace re-exports, and multi-file module fixtures that the test runner doesn't supply.

### Summary: Projected Impact

| Milestone | Tests Fixed | Cumulative | Rate |
|-----------|------------|------------|------|
| Pre-P22 baseline | — | 23,875 | **86.5%** |
| Tier 1+2 (P22) | +587 | 24,462 | **88.1%** |
| Tier 4 (P23) | +57 | 24,519 | **88.8%** |
| Remaining Tier 1 (1d) | ~17 | ~24,536 | **88.9%** |
| Remaining Tier 4 (4g modules) | ~50-100 | ~24,600 | **~89.2%** |
| Tier 3a (class public fields) | ~723 unskipped | ~25,000* | **~89%*** |
| Tier 3b (async/await) | ~500+ unskipped | ~25,500* | **~89%*** |
| All tiers | ~1,500+ fixed + ~4,000+ unskipped | ~28,000+* | **~90%+*** |

\* Projected rates for Tier 3 account for both newly-passing and newly-executed (denominator increases).

### Root Cause Clustering of Remaining 3,080 Failures

| Root Cause | Est. Failures | % of Total | Key Categories Affected |
|------------|---------------|------------|-------------------------|
| Language expression/statement edge cases | ~1,237 | 40.2% | `language/expressions` (568), `language/statements` (669) |
| Built-ins/Array edge cases | ~351 | 11.4% | `built-ins/Array` |
| Module system gaps | ~280 | 9.1% | `language/module-code` (198), `language/import` (82) |
| Annex B remaining (built-ins, language edge cases) | ~164 | 5.3% | `annexB/built-ins` (58), `annexB/language` (106) |
| Built-ins/Object edge cases | ~133 | 4.3% | `built-ins/Object` |
| RegExp remaining gaps (named groups, lookbehind, edge cases) | ~128 | 4.2% | `built-ins/RegExp` (111), `built-ins/RegExpStringIteratorPrototype` (17) |
| Eval-code edge cases | ~97 | 3.2% | `language/eval-code` |
| Language/literals (octal, numeric, template) | ~89 | 2.9% | `language/literals` |
| Built-ins/Function edge cases | ~69 | 2.2% | `built-ins/Function` |
| Built-ins/String edge cases | ~58 | 1.9% | `built-ins/String` |
| Built-ins/Number edge cases | ~48 | 1.6% | `built-ins/Number` |
| Language/identifiers (Unicode) | ~44 | 1.4% | `language/identifiers` |
| Generator conformance | ~7 | 0.2% | `built-ins/GeneratorPrototype` (7 remaining) |
| Assorted spec edge cases | ~375 | 12.2% | Spread across all categories |

### Previously Completed

- **WeakMap / WeakSet** — ✅ DONE (Phase 20). Both at 100% pass rate.
- **Iterator Prototypes** — ✅ DONE (Phase 20). MapIteratorPrototype, SetIteratorPrototype, StringIteratorPrototype all at 100%.
- **RegExp Improvements** — ✅ Substantial (Phase 20+22). Lookahead, multiline, backreferences, dotAll, sticky, unicode flag, Symbol.match/replace/split/search. 86.8% pass rate.
- **Boxed Primitives** — ✅ DONE (Phase 18). `new String/Number/Boolean` with internal slots, Object() wrapping, ToPrimitive coercion.
- **`with` statement** — ✅ DONE (Phase 22). Object environment record, SyntaxError in strict mode, primitive coercion.
- **Annex B block-level function hoisting** — ✅ DONE (Phase 22). annexB/language 38.1% → 87.0%.
- **String escape sequences** — ✅ DONE (Phase 22). `\r`, `\b`, `\v`, `\f`, `\0`, `\xHH`, line continuation.
- **`%ThrowTypeError%` intrinsic** — ✅ DONE (Phase 22). Strict arguments/Function.prototype caller/arguments.
- **DataView** — ✅ DONE (Phase 16+22). 377/377 (100%).

---

## Phase 12+ Targets

### async/await (~500 tests)

Syntactic sugar over Promises + generator-like suspension. Now unblocked by generator implementation.

### Other Features

| Feature | Impact | Notes |
|---------|--------|-------|
| TypedArray prototype chain | — | ✅ Done (Phase 17-19) — TypedArray 726/777 (93.4%), TypedArrayConstructors 342/359 (95.3%) |
| Boxed primitives | — | ✅ Done (Phase 18-19) — Object 3,234/3,373 (95.9%), String 1,137/1,195 (95.1%), Number 287/335 (85.7%) |
| RegExp improvements | ~111 fail | Named groups, lookbehind; Symbol methods ✅ Done (P22), 86.8% |
| WeakMap/WeakSet | — | ✅ Done (Phase 20) — WeakMap 139/139 (100%), WeakSet 84/84 (100%) |
| Class public fields | ~723 skip | `class C { x = 1; static y = 2; }` field declarations |
| Class private fields/methods | ~2,437 skip | `#private` syntax across fields, methods, static members |
| async/await | ~500+ | Syntactic sugar over Promises; unblocked by generators |
| Date object | — | ✅ Done (8C+9) — 560/583 pass (96.1%) |
| eval() | — | ✅ Done (P5) — 224/330 pass (67.9%) |
| Proxy/Reflect | — | ✅ Done (Phase 15-19) — Proxy 262/272 (96.3%), Reflect 153/153 (100.0%) |
| Promise improvements | — | ✅ Done (Phase 13) — 614/618 pass (99.4%) |
| TypedArray/ArrayBuffer/DataView | — | ✅ Done (Phase 16-19) — DataView 353/388 (91.0%), ArrayBuffer 73/78 (93.6%), TypedArrayConstructors 342/359 (95.3%) |

### Promise Conformance Batch (Implemented)

**Status (2026-02-12)**: Implemented and verified on targeted Promise slice.

Completed work for `Promise.all`, `Promise.allSettled`, `Promise.any`, and `Promise.race`:
1. Combinators now use constructor-aware capability creation (`NewPromiseCapability(C)` style).
2. Shared abrupt completion handling is centralized and used across combinators.
3. Iterator-close behavior on abrupt iteration paths is aligned and validated.
4. Final resolve/reject calls in combinators route through abrupt-safe handling.
5. Promise resolve/thenable behavior updated for poisoned/thenable/array-like edge paths.

**Validation**:
- `python3 test262-runner.py --filter "built-ins/Promise" --summary --output test262-promise-results.json`
- Result: 599/599 passing (100%), 41 skipped, 0 failed.

**Note**: Proxy support was added in Phase 15, un-skipping the previously deferred `this-value-proxy.js` test.

---

## Annex B / Legacy Features (`--annex-b` flag)

**Status**: In progress. Deprecated and legacy ECMAScript features are gated behind the `--annex-b` CLI flag, suppressed by default. Phase 21 added `annex_b~` gating to `get_string_method` for HTML string methods.

**Rationale**: Annex B features are deprecated, banned in strict mode, and irrelevant to modern JavaScript. Implementing them unconditionally adds complexity and pollutes the core engine. Gating them behind a flag keeps the default engine clean while allowing opt-in for legacy compatibility testing.

### Design

```bash
# Default: strict-modern behavior, no Annex B
node engine.js 'with ({x: 1}) { print(x) }'
# => SyntaxError: 'with' statement is not supported

# Opt-in: enable Annex B legacy features
node engine.js --annex-b 'with ({x: 1}) { print(x) }'
# => 1
```

- **CLI**: `--annex-b` flag parsed in `cmd/main/main.mbt`, passed to interpreter as `self.annex_b : Bool`
- **Test262 runner**: `test262-runner.py` passes `--annex-b` for tests in `annexB/` directories
- **Metadata parsing**: `test262-runner.py` and `test262-analyze.py` share `test262_utils.py` and run with or without PyYAML installed
- **Feature gating**: Each Annex B feature checks `self.annex_b` before enabling legacy behavior

### Features to gate behind `--annex-b`

| Feature | Tests | Notes |
|---------|-------|-------|
| `with` statement | — | ✅ Done (P22). Object environment record, SyntaxError in strict mode |
| Legacy octal literals (`0777`) | ~30 | `0`-prefixed octals in sloppy mode |
| Legacy octal escapes (`\077`) | ~20 | Octal escape sequences in strings |
| `__proto__` property | ~40 | `Object.prototype.__proto__` getter/setter |
| HTML comment syntax (`<!--`, `-->`) | ~10 | HTML-style comments in script code |
| `String.prototype.{anchor,big,blink,...}` | ~58 fail | ✅ Gated in P21. HTML wrapper methods (`"str".bold()` → `"<b>str</b>"`) |
| `RegExp.prototype.compile` | ~10 | Legacy RegExp recompilation |
| `escape()`/`unescape()` | ~20 | Legacy encoding functions |
| Block-level function declarations (sloppy) | ~106 fail | ✅ Mostly done (P22). `annexB/language` 38.1% → 87.0%; remaining edge cases |

**Estimated total**: ~164 tests currently failing due to missing/incomplete Annex B features (was ~844 pre-P22)

### Priority

Low. These features are not required for modern JavaScript usage. Implement only after core ES2015+ compliance targets are met (>85% pass rate on non-Annex B tests).

---

## Skipped Features (~20,497 tests)

| Feature | Skipped | Notes |
|---------|---------|-------|
| Temporal | 4,482 | TC39 Stage 3 date/time API |
| async-iteration | 3,731 | Requires async generators |
| class-methods-private | 1,304 | #privateMethod |
| BigInt | 1,250 | Arbitrary precision integers |
| class-static-methods-private | 1,133 | static #method |
| class-fields-public | 723 | Public field declarations |
| regexp-unicode-property | 679 | Unicode property escapes |
| module | 422 | import/export implemented; 338 in module dirs + 84 module-flagged tests in other dirs |
| generators | — | ✅ No longer skipped (implemented in Phase 8) |
| Proxy/Reflect | — | ✅ No longer skipped (implemented in Phase 15) |
| TypedArray/ArrayBuffer/DataView | — | ✅ No longer skipped (implemented in Phase 16) |

---

## Architecture

### Key Decisions

1. **Functions are objects** — `Object` with `callable` field, enabling property assignment on functions
2. **Exception propagation** — MoonBit's native `raise` with `JsException(Value)` suberror
3. **Property descriptors** — `ObjectData.descriptors` map alongside `properties`
4. **Array storage** — Dedicated `Array(ArrayData)` variant with `elements: Array[Value]`
5. **Builtin organization** — Split into `builtins_object.mbt`, `builtins_array.mbt`, `builtins_string.mbt`, `builtins_typedarray.mbt`, `builtins_arraybuffer.mbt`, `builtins_dataview.mbt`, etc.

### Value Variants

`Number`, `String_`, `Bool`, `Null`, `Undefined`, `Object`, `Array`, `Symbol`, `Map`, `Set`, `Promise`, `Proxy`

### Signal Types

`Normal(Value)`, `ReturnSignal(Value)`, `BreakSignal(String?)`, `ContinueSignal(String?)`

### Generator Suberrors

`YieldSignal(Value)`, `GeneratorReturnSignal(Value)` — used for control flow within generator execution, caught by the generator runtime to suspend or complete the generator.
