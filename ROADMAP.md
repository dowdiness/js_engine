# JS Engine Roadmap

## Current Status

**Test262**: 9,545 / 24,213 passed (39.4%) | 25,381 skipped | 14,668 failed | 56 timeouts

**Unit tests**: 534 total, 534 passed, 0 failed

## Phase History

| Phase | Tests | Cumulative | Key Changes |
|-------|-------|------------|-------------|
| 1-5 | — | 6,351 | Core language, classes, promises, iterators, skip list cleanup |
| 6A-6G | +~2,350 | ~8,500 | Parser fixes, prototype chains, destructuring, tagged templates |
| 6H | +1,202 | 9,489 | Error prototype chain fix |
| 6I-6L | +56 | 9,545 | Leading decimals, canonical indices, PR review fixes |
| 7A | +13 | 9,545* | Full accessor descriptor support (get/set in PropDescriptor) |
| JS Target | — | 9,545 | JS backend support, Error toString fix, backend-specific argv handling |

\* Phase 7A added 13 unit tests; test262 recount pending.

For detailed implementation notes on Phases 1-6, see [docs/PHASE_HISTORY.md](docs/PHASE_HISTORY.md).

---

## Failure Breakdown

### Parser/Syntax (~1,700 tests)

| Category | Count | Difficulty |
|----------|-------|------------|
| Unicode escapes in identifiers/strings | 479 | Medium |
| Bare `for (x of ...)` without let/var | 225 | Easy |
| Generator functions (`function*`, `yield`) | 160 | Hard |
| `get`/`set` as regular identifiers | 127 | Easy |
| Destructuring defaults in more contexts | ~100 | Medium |
| Async $DONE not called (event loop) | 98 | Hard |
| Additional destructuring pattern contexts | 122 | Medium |
| Other syntax gaps | ~260 | Varies |

### Runtime/Semantic (~12,476 tests)

| Category | Count | Priority |
|----------|-------|----------|
| Object.defineProperty/defineProperties | 1,350 | High |
| language/expressions | 1,233 | Medium |
| language/statements | 1,111 | Medium |
| staging/sm (SpiderMonkey) | 841 | Low |
| String.prototype | 681 | Medium |
| RegExp | 671 | Hard |
| annexB/language (legacy) | 608 | Low |
| Date | 534 | Medium |
| Promise | 446 | Medium |
| Function | 320 | Medium |
| DataView (needs TypedArray) | 311 | Hard |
| eval-code | 205 | Hard |
| Object.getOwnPropertyDescriptor | 193 | High |
| Number | 187 | Easy |
| Object.create | 176 | High |
| Map/WeakMap | 169 | Medium |
| Math | 134 | Easy |
| JSON | 59 | Medium |

---

## JavaScript Self-Hosting

**Status**: Working. The engine compiles to JavaScript via `moon build --target js` and runs on Node.js.

```bash
moon build --target js
node ./target/js/release/build/cmd/main/main.js 'console.log(1 + 2)'
# => 3
```

All 507 unit tests pass on both WASM-GC and JS targets. See [docs/SELF_HOST_JS_RESEARCH.md](docs/SELF_HOST_JS_RESEARCH.md) for full analysis.

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

### 7B: Unicode Escapes (~479 tests)

Pure parser/lexer fix.

- `\uXXXX` in identifiers: `var \u0061 = 1` means `var a = 1`
- `\u{XXXXX}` extended Unicode escapes
- Unicode escapes in string literals

### 7C: Bare for-of/for-in (~225 tests)

Parser fix: `for (x of arr)` without `let`/`var`/`const`.

### 7D: get/set as Identifiers (~127 tests)

Parser fix: `get`/`set` treated as regular identifiers outside getter/setter position.

### 7E: Math Built-ins (~134 tests)

Missing methods: `cbrt`, `log2`, `log10`, `sign`, `trunc`, `fround`, `clz32`, `imul`, `hypot`, `acosh`, `asinh`, `atanh`, `cosh`, `sinh`, `tanh`, `expm1`, `log1p`.

---

## Phase 8+ Targets (reaching 15,000+)

### Generators (~3,400 tests: 3,241 skipped + 160 failing)

`function*`, `yield`, `yield*`. Would also unblock async-iteration (3,731 more skipped).

Architecture: explicit state machine — convert generator body into segments separated by yield points. Generator object tracks current segment + local environment.

### async/await (~500 tests)

Syntactic sugar over Promises + generator-like suspension. Depends on generators.

### Other Features

| Feature | Impact | Notes |
|---------|--------|-------|
| RegExp improvements | ~671 | Capture groups, backreferences, unicode/sticky flags |
| `with` statement | ~150 | Dynamic scope injection |
| eval() improvements | ~205 | Direct vs indirect eval semantics |
| Date object | ~534 | Date parsing, formatting, prototype methods |
| WeakMap/WeakSet | ~200 | Reference-based collections |
| Proxy/Reflect | ~500 | Meta-programming |

---

## Skipped Features (25,381 tests)

| Feature | Skipped | Notes |
|---------|---------|-------|
| Temporal | 4,228 | TC39 Stage 3 date/time API |
| async-iteration | 3,731 | Requires generators |
| generators | 3,241 | function*, yield |
| class-methods-private | 1,304 | #privateMethod |
| TypedArray | 1,257 | Int8Array, Uint8Array, etc. |
| BigInt | 1,250 | Arbitrary precision integers |
| class-static-methods-private | 1,133 | static #method |
| module | 812 | import/export |
| class-fields-public | 723 | Public field declarations |
| regexp-unicode-property | 679 | Unicode property escapes |

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
