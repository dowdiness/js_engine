# JS Engine Roadmap

## Current Status

**Test262**: 20,870 / 25,222 passed (82.7%) | 22,741 skipped | 4,352 failed | 157 timeouts

**Unit tests**: 763 total, 763 passed, 0 failed

**Targeted verification (2026-02-11)**: `language/block-scope` slice is 106/106 passing (39 skipped).
**Targeted verification (2026-02-12)**: `built-ins/Promise` slice is 599/599 passing (100%, 41 skipped). `language/block-scope` is 106/106 passing (100%, 39 skipped).
**Targeted verification (2026-02-13)**: `language/white-space` slice is 66/67 passing (98.5%, was 73.1%). Small compliance sweep completed.

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

For detailed implementation notes on Phases 1-6, see [docs/PHASE_HISTORY.md](docs/PHASE_HISTORY.md).

---

## Failure Breakdown

### Failure Breakdown by Category (4,352 remaining failures)

Top failing categories from the latest CI run (2026-02-13):

| Category | Pass | Fail | Rate | Priority |
|----------|------|------|------|----------|
| language/expressions | 4,897 | 590 | 89.2% | Medium |
| language/statements | 3,454 | 720 | 82.8% | Medium |
| built-ins/Array | 2,414 | 454 | 84.2% | Medium |
| built-ins/Object | 3,025 | 266 | 91.9% | Low (P4 done) |
| annexB/language | 312 | 505 | 38.2% | Low (--annex-b) |
| built-ins/Promise | 598 | 0 | 100.0% | ✅ Done (P7) |
| built-ins/DataView | 7 | 304 | 2.3% | Hard (needs TypedArray) |
| built-ins/RegExp | 604 | 222 | 73.1% | Hard |
| language/module-code | 114 | 184 | 38.3% | Medium |
| language/eval-code | 224 | 106 | 67.9% | Low (P5 done) |
| built-ins/String | 1,054 | 96 | 91.7% | Low |
| built-ins/Function | 325 | 68 | 82.7% | Medium |
| language/literals | 231 | 88 | 72.4% | Medium |
| built-ins/Number | 265 | 55 | 82.8% | Easy |
| language/identifiers | 154 | 53 | 74.4% | Medium |
| language/block-scope | 106 | 0 | 100.0% | ✅ Done |
| built-ins/ArrayBuffer | 10 | 51 | 16.4% | Hard (needs TypedArray) |
| built-ins/Map | 139 | 29 | 82.7% | Medium |
| language/white-space | 66 | 1 | 98.5% | ✅ Done (P14) |

### High-Performing Categories (>90% pass rate)

| Category | Pass | Fail | Rate |
|----------|------|------|------|
| built-ins/Promise | 598 | 0 | 100.0% |
| language/block-scope | 106 | 0 | 100.0% |
| built-ins/NativeErrors | 80 | 0 | 100.0% |
| built-ins/global | 27 | 0 | 100.0% |
| built-ins/isFinite | 14 | 0 | 100.0% |
| built-ins/isNaN | 14 | 0 | 100.0% |
| language/punctuators | 11 | 0 | 100.0% |
| language/source-text | 1 | 0 | 100.0% |
| language/white-space | 66 | 1 | 98.5% |
| built-ins/Math | 281 | 5 | 98.3% |
| built-ins/parseFloat | 52 | 1 | 98.1% |
| built-ins/parseInt | 53 | 1 | 98.1% |
| built-ins/Set | 172 | 4 | 97.7% |
| built-ins/decodeURIComponent | 52 | 2 | 96.3% |
| built-ins/decodeURI | 51 | 2 | 96.2% |
| language/arguments-object | 146 | 6 | 96.1% |
| language/function-code | 166 | 7 | 96.0% |
| language/keywords | 24 | 1 | 96.0% |
| built-ins/Date | 511 | 23 | 95.7% |
| built-ins/AggregateError | 21 | 1 | 95.5% |
| language/comments | 22 | 1 | 95.7% |
| language/computed-property-names | 45 | 3 | 93.8% |
| built-ins/encodeURIComponent | 28 | 2 | 93.3% |
| built-ins/encodeURI | 28 | 2 | 93.3% |
| language/asi | 95 | 7 | 93.1% |
| built-ins/JSON | 105 | 8 | 92.9% |
| language/reserved-words | 25 | 2 | 92.6% |
| language/future-reserved-words | 34 | 3 | 91.9% |
| built-ins/Object | 3,025 | 266 | 91.9% |
| built-ins/String | 1,054 | 96 | 91.7% |
| language/rest-parameters | 10 | 1 | 90.9% |

---

## JavaScript Self-Hosting

**Status**: Working. The engine compiles to JavaScript via `moon build --target js` and runs on Node.js.

```bash
moon build --target js
node ./_build/js/debug/build/cmd/main/main.js 'console.log(1 + 2)'
# => 3
```

All 746 unit tests pass on both WASM-GC and JS targets. See [docs/SELF_HOST_JS_RESEARCH.md](docs/SELF_HOST_JS_RESEARCH.md) for full analysis.

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

**Note**: One skipped Promise test (`built-ins/Promise/prototype/finally/this-value-proxy.js`) is Proxy-dependent and deferred until Proxy support is implemented.

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

## Phase 12+ Targets

### async/await (~500 tests)

Syntactic sugar over Promises + generator-like suspension. Now unblocked by generator implementation.

### Other Features

| Feature | Impact | Notes |
|---------|--------|-------|
| RegExp improvements | ~225 fail | Capture groups, backreferences, unicode/sticky flags |
| Date object | — | ✅ Done (8C+9) — 511/534 pass (95.7%) |
| eval() | — | ✅ Done (P5) — 224/330 pass (67.9%) |
| WeakMap/WeakSet | ~59 fail | Reference-based collections |
| Proxy/Reflect | ~500 | Meta-programming |
| Promise improvements | — | ✅ Done (Phase 13) — 599/599 pass (100%, 41 skipped) |

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

**Deferred**:
- `Proxy` remains unsupported; dependent test is intentionally skipped:
  `built-ins/Promise/prototype/finally/this-value-proxy.js`.

---

## Annex B / Legacy Features (`--annex-b` flag)

**Status**: Planned. Deprecated and legacy ECMAScript features will be gated behind an `--annex-b` CLI flag, suppressed by default.

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
- **Test262 runner**: `test262-runner.py` passes `--annex-b` for tests in `annexB/` directories or tests with `includes: [annexB]` metadata
- **Metadata parsing**: `test262-runner.py` and `test262-analyze.py` share `test262_utils.py` and run with or without PyYAML installed
- **Feature gating**: Each Annex B feature checks `self.annex_b` before enabling legacy behavior

### Features to gate behind `--annex-b`

| Feature | Tests | Notes |
|---------|-------|-------|
| `with` statement | ~151 fail | Object environment record, dynamic scope injection. SyntaxError in strict mode regardless of flag |
| Legacy octal literals (`0777`) | ~30 | `0`-prefixed octals in sloppy mode |
| Legacy octal escapes (`\077`) | ~20 | Octal escape sequences in strings |
| `__proto__` property | ~40 | `Object.prototype.__proto__` getter/setter |
| HTML comment syntax (`<!--`, `-->`) | ~10 | HTML-style comments in script code |
| `String.prototype.{anchor,big,blink,...}` | ~73 fail | HTML wrapper methods (`"str".bold()` → `"<b>str</b>"`) |
| `RegExp.prototype.compile` | ~10 | Legacy RegExp recompilation |
| `escape()`/`unescape()` | ~20 | Legacy encoding functions |
| Block-level function declarations (sloppy) | ~503 fail | `annexB/language` — FunctionDeclaration in blocks under sloppy mode (Annex B.3.3) |

**Estimated total**: ~857 tests currently failing due to missing Annex B features

### Priority

Low. These features are not required for modern JavaScript usage. Implement only after core ES2015+ compliance targets are met (>85% pass rate on non-Annex B tests).

---

## Skipped Features (22,748 tests)

| Feature | Skipped | Notes |
|---------|---------|-------|
| Temporal | 4,228 | TC39 Stage 3 date/time API |
| async-iteration | 3,731 | Requires async generators |
| class-methods-private | 1,304 | #privateMethod |
| TypedArray | 1,257 | Int8Array, Uint8Array, etc. |
| BigInt | 1,250 | Arbitrary precision integers |
| class-static-methods-private | 1,133 | static #method |
| class-fields-public | 723 | Public field declarations |
| regexp-unicode-property | 679 | Unicode property escapes |
| module | 422 | import/export implemented; 338 in module dirs + 84 module-flagged tests in other dirs |
| generators | — | ✅ No longer skipped (implemented in Phase 8) |

---

## Architecture

### Key Decisions

1. **Functions are objects** — `Object` with `callable` field, enabling property assignment on functions
2. **Exception propagation** — MoonBit's native `raise` with `JsException(Value)` suberror
3. **Property descriptors** — `ObjectData.descriptors` map alongside `properties`
4. **Array storage** — Dedicated `Array(ArrayData)` variant with `elements: Array[Value]`
5. **Builtin organization** — Split into `builtins_object.mbt`, `builtins_array.mbt`, `builtins_string.mbt`, etc.

### Value Variants

`Number`, `String_`, `Bool`, `Null`, `Undefined`, `Object`, `Array`, `Symbol`, `Map`, `Set`, `Promise`

### Signal Types

`Normal(Value)`, `ReturnSignal(Value)`, `BreakSignal(String?)`, `ContinueSignal(String?)`

### Generator Suberrors

`YieldSignal(Value)`, `GeneratorReturnSignal(Value)` — used for control flow within generator execution, caught by the generator runtime to suspend or complete the generator.
