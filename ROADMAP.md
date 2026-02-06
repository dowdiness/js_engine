# JS Engine — Test262 Compliance Roadmap

## Current Status (Phase 6 + PR Review Fixes Complete)

- **Passed**: 9,545 / 24,213 executed (39.4%)
- **Skipped**: 25,381 (features not yet implemented: Temporal, async-iteration, generators, private fields, TypedArray, BigInt, modules, etc.)
- **Failed**: 14,668
- **Timeout**: 56

### Phase History

| Phase | Tests | Cumulative | Key Changes |
|-------|-------|------------|-------------|
| 1-5 | — | 6,351 | Base interpreter, classes, promises, iterators |
| 6A | +~200 | ~6,550 | Parser fixes, Array spec compliance |
| 6B | +~200 | ~6,750 | String.prototype methods, array elisions, trailing commas |
| 6C | +~400 | ~7,150 | Object.prototype chain fix for plain objects |
| 6D | +~250 | ~7,400 | Constructor property on all built-in prototypes |
| 6E | +~450 | ~7,850 | Unary +, empty statements, Object(null) fix |
| 6F | +~400 | ~8,250 | Destructuring parameters in functions/arrows |
| 6G | +~250 | ~8,500 | for-of/in destructuring, tagged templates, object method params |
| 6H | +1,202 | 9,489 | **Error prototype chain fix** (try-catch creates proper Error objects) |
| 6I | +est.50 | ~9,540 | Leading decimal literals (.5), comma-separated for-init |
| 6J | +est.50 | ~9,590 | Number.prototype this-validation, String.split limit |
| 6K | +32 | 9,521 | PR review fixes: var scoping, rest destructuring, toString tags, AggregateError |
| 6L | +24 | 9,545 | PR review round 2: canonical indices, isPrototypeOf, prototype chain walk |

---

## Failure Breakdown

### Parser / Syntax Errors (~1,700 tests)

| Category | Count | Description | Difficulty |
|----------|-------|-------------|------------|
| Unicode escapes | 479 | `\u0041` in identifiers/strings | Medium |
| for-of destructuring (bare) | 225 | `for (x of ...)` without let/var | Easy |
| Generator functions | 160 | `function*`, `yield` keyword | Hard |
| get/set as identifiers | 127 | `get`/`set` used as regular property names | Easy |
| Destructuring defaults in patterns | ~100 | `{a = 1}` in more destructuring contexts | Medium |
| async $DONE not called | 98 | Async tests needing event loop | Hard |
| LBracket/LBrace in patterns | 122 | Additional destructuring pattern contexts | Medium |
| Comma after destructuring | ~60 | Destructuring in comma expressions | Medium |
| Other syntax | ~200 | Miscellaneous parser gaps | Varies |

### Runtime / Semantic Errors (JsException ~12,476 tests)

| Category | Count | Description | Priority |
|----------|-------|-------------|----------|
| Object.defineProperty | 809 | Property descriptor enforcement | High |
| Object.defineProperties | 541 | Bulk property definition | High (same as above) |
| language/statements | 1,111 | Statement edge cases (class, for, with) | Medium |
| language/expressions | 1,233 | Expression edge cases | Medium |
| staging/sm | 841 | SpiderMonkey staging tests | Low |
| String.prototype | 681 | String method edge cases | Medium |
| RegExp | 671 | Regular expression features | Hard |
| annexB/language | 608 | Annex B (legacy) behaviors | Low |
| Date | 534 | Date object methods | Medium |
| Promise | 446 | Promise combinators, edge cases | Medium |
| Function | 320 | Function object properties | Medium |
| DataView | 311 | Binary data views (needs TypedArray) | Hard |
| Object.create | 176 | Object.create with descriptors | High |
| Object.getOwnPropertyDescriptor | 193 | Descriptor retrieval accuracy | High |
| Math | 134 | Math method gaps | Easy |
| Number | 187 | Number method edge cases | Easy |
| Map/WeakMap | 169 | Map/WeakMap compliance | Medium |
| JSON | 59 | JSON.parse/stringify edge cases | Medium |
| eval-code | 205 | Direct/indirect eval | Hard |

---

## Recommended Phase 7 Targets (reaching 10,000+)

### 7A: Object.defineProperty & Property Descriptors (~1,500 tests potential)
**Impact: Very High** — 809 + 541 + 193 + 176 = 1,719 tests depend on this

- Implement full property descriptor semantics (writable, enumerable, configurable enforcement)
- `Object.defineProperty()` must enforce descriptor rules
- `Object.defineProperties()` for batch definitions
- `Object.getOwnPropertyDescriptor()` must return proper descriptor objects
- `Object.create()` with property descriptor map
- Property access must respect `writable: false`, `configurable: false`
- Getter/setter descriptors (accessor properties)

### 7B: Unicode Escape Sequences (~479 tests)
**Impact: High** — Pure parser/lexer fix

- Handle `\uXXXX` in identifiers: `var \u0061 = 1` means `var a = 1`
- Handle `\u{XXXXX}` extended Unicode escapes
- Handle Unicode escapes in string literals beyond current support

### 7C: Bare for-of/for-in Improvements (~225 tests)
**Impact: Medium** — Parser fix

- `for (x of arr)` without `let`/`var`/`const` (bare identifier assignment)
- Currently only handles `for (let x of ...)` pattern with destructuring

### 7D: get/set as Regular Identifiers (~127 tests)
**Impact: Medium** — Parser fix

- `get` and `set` should be treated as regular identifiers when not in getter/setter position
- e.g., `var get = 5; var set = 10;` should work

### 7E: Math Built-ins (~134 tests)
**Impact: Easy wins**

- Add missing Math methods: `Math.cbrt`, `Math.log2`, `Math.log10`, `Math.sign`, `Math.trunc`, `Math.fround`, `Math.clz32`, `Math.imul`, `Math.hypot`, `Math.acosh`, `Math.asinh`, `Math.atanh`, `Math.cosh`, `Math.sinh`, `Math.tanh`, `Math.expm1`, `Math.log1p`

---

## Recommended Phase 8+ Targets (reaching 15,000+)

### Generator Functions (~3,241 skipped + ~160 failing)
- `function*` syntax, `yield` / `yield*`
- Generator protocol (next/return/throw)
- Would also unblock async-iteration tests (3,731 more)

### Regular Expressions (~671 failing)
- Capture groups, backreferences
- Unicode flag, sticky flag
- RegExp.prototype methods

### with Statement (~150+ failing)
- Dynamic scope injection via `with (obj) { ... }`

### eval() Improvements (~205 failing)
- Direct vs indirect eval semantics
- Proper scope chain for eval

### Date Object (~534 failing)
- Date parsing, formatting
- Date.prototype methods

---

## Skipped Feature Categories (25,381 tests)

These tests require features not yet implemented:

| Feature | Skipped Tests | Notes |
|---------|--------------|-------|
| Temporal | 4,228 | TC39 Stage 3 date/time API |
| async-iteration | 3,731 | Requires generators first |
| generators | 3,241 | function*, yield |
| class-methods-private | 1,304 | #privateMethod |
| TypedArray | 1,257 | Int8Array, Uint8Array, etc. |
| BigInt | 1,250 | Arbitrary precision integers |
| class-static-methods-private | 1,133 | static #method |
| module | 812 | import/export |
| class-fields-public | 723 | Public field declarations |
| regexp-unicode-property | 679 | Unicode property escapes |
