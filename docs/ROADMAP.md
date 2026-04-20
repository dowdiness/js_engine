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

For per-phase implementation notes, see [archive/phase-history.md](archive/phase-history.md).

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

All 881 unit tests pass on both WASM-GC and JS targets. See [SELF_HOST_JS_RESEARCH.md](SELF_HOST_JS_RESEARCH.md) for full analysis.

### What was needed
- **Backend-specific argv handling**: `process.argv` on JS includes `["node", "script.js", ...]`, so user args start at index 2 (vs index 1 on WASM). Solved with `.js.mbt` / `.wasm.mbt` / `.wasm-gc.mbt` files.
- **Error toString fix**: Error objects now format as `"TypeError: message"` instead of `"[object TypeError]"`, matching `Error.prototype.toString()`.

### Future directions
- **npm distribution**: Configure ESM/CJS output, publish as sandboxed JS evaluator
- **Browser playground**: IIFE build for in-browser JS interpretation (no fs dependencies)
- **Self-interpretation**: Run the JS-compiled engine through itself (requires higher Test262 compliance to handle MoonBit's JS output)

---

## Recommended Next Steps for Conformance

Prioritized by estimated test impact and implementation effort. These are the highest-ROI items for pushing past 90% test262 pass rate.

### Path to 90%

Current: **24,519 / 27,599 executed (88.8%)**. Need **~341 more passing tests** to reach 90%. Tiers 1-2 are largely complete (Phase 22), Tier 4 polish done (Phase 23). The remaining items below are ordered by ROI.

### Tier 3 — Feature Implementations (~3,000+ skipped tests unlocked, high effort)

These are major missing language features. Each unlocks a large batch of currently-skipped tests but requires significant implementation work.

| # | Feature | Skipped Tests | Effort | Notes |
|---|---------|---------------|--------|-------|
| **3a** | **Class public fields** | — | — | ✅ DONE (pre-2026-04-16). Feature flags removed, ~97% pass rate |
| **3b** | **async/await** | — | — | ✅ DONE (PR #45, 2026-04-12). Feature flag removed |
| **3c** | **Class private fields/methods** | ~2,437 | High | `#private` syntax with brand-check semantics |
| **3d** | **RegExp named groups & lookbehind** | ~679+ skipped | Medium | Named groups ✅ DONE (PR #47). Lookbehind remaining |

**Details:**

**3a — Class public fields.** ✅ DONE. `ClassField` AST node, parser field detection, instance field installation in `construct.mbt`, static field evaluation at class definition time. Feature flags `class-fields-public` and `class-static-fields-public` removed from skip list. Computed property name tests at ~97% pass rate.

**3b — async/await.** ✅ DONE (PR #45, 2026-04-12). `async function`, `async () =>`, `await expr` all parse and execute. Feature flag `async-functions` removed. Remaining: `async-iteration` (`for await`) still skipped (~3,731 tests).

**3c — Class private fields/methods.** The largest single batch of skipped tests (~2,437 across `class-fields-private`, `class-methods-private`, `class-static-fields-private`, `class-static-methods-private`). Requires:
1. Parser: `#name` syntax for fields, methods, accessors, and static variants.
2. **Brand checking**: each class gets a unique brand; instances are stamped with the brand at construction time; accessing `#field` on an object without the brand throws `TypeError`.
3. Private name resolution: lexical scope model where `#name` resolves to a per-class WeakMap-like storage slot.
4. This is the most complex single feature due to the interaction between brand checks, inheritance, and static private members.

**3d — RegExp named groups & lookbehind.** Named groups ✅ DONE (PR #47, 2026-04-15). Lookbehind `(?<=...)` / `(?<!...)` still skipped via `regexp-lookbehind` feature flag. Requires backward matching from the current position. Unicode property escapes `\p{Letter}` / `\P{Script=Greek}` still skipped — requires Unicode property tables (large data dependency).

### Summary: Projected Impact

| Milestone | Tests Fixed | Cumulative | Rate |
|-----------|------------|------------|------|
| Pre-P22 baseline | — | 23,875 | **86.5%** |
| Tier 1+2 (P22) | +587 | 24,462 | **88.1%** |
| Tier 4 (P23) | +57 | 24,519 | **88.8%** |
| Tier 1d + regex replace (2026-04-16) | ~+60 | ~24,579 | **~89.0%** |
| Proxy trap invariants (2026-04-16) | +136 | ~24,715 | **~89.5%** |
| Remaining Tier 4 (4g modules) | ~50-100 | ~24,815 | **~89.9%** |

**Note**: Tier 3a (class public fields) and Tier 3b (async/await) were already implemented and unlocked prior to 2026-04-16. The `class-fields-public` and `async-functions` feature flags are no longer in the skip list. Remaining gains come from fixing many small issues across categories.

### Root Cause Clustering of Remaining Failures (updated 2026-04-16)

Failures are now widely distributed. No single fix unlocks 300+ tests. Progress requires many small, targeted fixes.

| Category | Pass | Fail | Rate | Top Failure Causes |
|----------|------|------|------|--------------------|
| `built-ins/Array` | 4,664 | 1,157 | 80.1% | Species, sparse arrays, iteration model |
| `language/expressions` | ~10,810 | ~1,018 | ~91.4% | Scattered; class-private skipped |
| `language/statements` | ~7,615 | ~647 | ~89.8% | Scattered; class-private skipped |
| `built-ins/RegExp` | ~1,148 | ~628 | ~64.6% | No lookbehind, subclass exec forwarding |
| `built-ins/Proxy` | 366 | 170 | 68.3% | Improved 2026-04-16: ownKeys 100%, isExtensible 91%, +7 traps with invariant checks. Remaining: set receiver forwarding (36), setPrototypeOf (12), getOwnPropertyDescriptor (8) |
| `built-ins/Object` | ~5,658 | ~1,092 | ~83.8% | Descriptor edge cases |
| `built-ins/String` | ~2,405 | ~216 | ~91.6% | Improved 2026-04-16 |
| `built-ins/Function` | 608 | 206 | 74.7% | Constructor edge cases, prototype descriptors |
| `language/eval-code` | 283 | 169 | 62.6% | Strict scoping, var hoisting edge cases |
| `built-ins/RegExpStringIteratorPrototype` | 20 | 14 | 58.8% | Improved 2026-04-16; remaining need lazy exec() |

---

## Phase 12+ Targets

### Other Features

| Feature | Impact | Notes |
|---------|--------|-------|
| TypedArray prototype chain | — | ✅ Done (Phase 17-19) — TypedArray 726/777 (93.4%), TypedArrayConstructors 342/359 (95.3%) |
| Boxed primitives | — | ✅ Done (Phase 18-19) — Object 3,234/3,373 (95.9%), String 1,137/1,195 (95.1%), Number 287/335 (85.7%) |
| RegExp improvements | — | Named groups ✅ Done (PR #47), lookbehind remaining; Symbol methods ✅ Done (P22) |
| WeakMap/WeakSet | — | ✅ Done (Phase 20) — WeakMap 139/139 (100%), WeakSet 84/84 (100%) |
| Class public fields | — | ✅ Done (pre-2026-04-16) — feature flags removed, ~97% pass rate |
| Class private fields/methods | ~2,437 skip | `#private` syntax across fields, methods, static members |
| async/await | — | ✅ Done (PR #45) — feature flag removed; `async-iteration` still skipped |
| RegExpStringIteratorPrototype | — | ✅ Mostly done (2026-04-16) — 20/34 passing, matchAll 44/48 |
| Regex callback replace | — | ✅ Done (2026-04-16) — `[Symbol.replace]` supports function replacements |
| Date object | — | ✅ Done (8C+9) — 560/583 pass (96.1%) |
| eval() | — | ✅ Done (P5) — 224/330 pass (67.9%) |
| Proxy/Reflect | — | ✅ Done (Phase 15-19) — Proxy 262/272 (96.3%), Reflect 153/153 (100.0%) |
| Promise improvements | — | ✅ Done (Phase 13) — 614/618 pass (99.4%) |
| TypedArray/ArrayBuffer/DataView | — | ✅ Done (Phase 16-19) — DataView 353/388 (91.0%), ArrayBuffer 73/78 (93.6%), TypedArrayConstructors 342/359 (95.3%) |

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


## Structural Refactoring (In Progress)

Next-phase structural pressures identified after the April-15 restructure. Full analysis in [architecture-redesign-2026-04-17-probes.md](architecture-redesign-2026-04-17-probes.md); stage ordering tracked in [agent-todo.md](agent-todo.md).

**Stage A — PropertyBag extraction** ✅ (2026-04-17, PR #49)
Introduced `PropertyBag` struct consolidating the quartet
`properties / symbol_properties / descriptors / symbol_descriptors`
into a single `bag : PropertyBag` field on every exotic variant
(`ObjectData`, `ArrayData`, `MapData`, `SetData`, `PromiseData`). Any
future descriptor-invariant fix is now applied once, not five times.
Also introduced custom-constructor methods (`PropertyBag::new`,
`MapData::new`, `SetData::new`) per MoonBit idiom. Pure refactor: 0
test262 delta, 884/884 unit tests. CodeRabbit surfaced 4 pre-existing
bugs (tracked in `agent-todo.md` as items #7-10).

**Stage B.1 — `[[Set]]` dispatcher: receiver threading + landing rule** ✅ (PR #69)
Proxy/Reflect `[[Set]]` now threads the receiver through proto walks and
lands writes per the ES §10.1.9.2 rules. Proxy 71.5% / Reflect 84.3% in
targeted verification after this change.

**Stages B.2 / C / B.3 / D** — planned. Stage C (`ArrayData.bag`) and
B.2 (dispatcher consolidation debt inherited from B.1) are the next
test262-positive targets.

## Architecture

For design principles, value model, control flow, and host integration, see [architecture.md](architecture.md). Completed restructuring analyses are in [archive/](archive/).
