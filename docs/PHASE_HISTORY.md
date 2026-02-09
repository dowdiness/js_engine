# Phase Implementation History (Archive)

Detailed implementation notes for completed phases. For current status and future plans, see [ROADMAP.md](../ROADMAP.md).

---

## Phase 1: Core Language Gaps (8.18% pass rate)

Harness dependencies: `throw`, `try/catch`, `new`, `this`, `switch/case`, `String()`.

### 1A. Lexer/Token Extensions
- 14 keywords: `throw`, `try`, `catch`, `finally`, `new`, `this`, `switch`, `case`, `default`, `void`, `delete`, `do`, `in`, `instanceof`
- Operators: `++`, `--`, `+=`, `-=`, `*=`, `/=`, `%=`, `&`, `|`, `^`, `~`, `<<`, `>>`, `>>>`, compound bitwise assignment

### 1B. AST Nodes
- Statements: `ThrowStmt`, `TryCatchStmt`, `SwitchStmt`, `DoWhileStmt`, `ForInStmt`, `LabeledStmt`
- Expressions: `ObjectLit`, `ArrayLit`, `ComputedMember`, `MemberAssign`, `ComputedAssign`, `NewExpr`, `ThisExpr`, `UpdateExpr`, `CompoundAssign`, `Comma`
- Binary ops: `BitAnd`, `BitOr`, `BitXor`, `LShift`, `RShift`, `URShift`, `In`, `Instanceof`

### 1C-1G. Value System, Exceptions, Parser, Interpreter, Builtins
- `Object(ObjectData)` + `Array(ArrayData)` value variants
- `JsException(Value)` suberror for JS exceptions
- Full JS precedence chain (15 levels)
- Built-in globals: `NaN`, `Infinity`, `undefined`, `isNaN`, `isFinite`, `parseInt`, `parseFloat`, error constructors

### Phase 1 Bug Fixes
1. `to_int32` rewritten for ECMAScript spec compliance
2. Error constructor prototypes shared correctly
3. `for-in` walks prototype chain with dedup
4. Labeled statements with break/continue label matching
5. `parseFloat` rewritten as single-pass O(n) scanner
6. `eval_update`/`eval_compound_assign` evaluate object once

**Files changed**: 14 files, +2,895/-82 lines

---

## Phase 2: Template Literals + Arrow Functions (8.5% pass rate)

Unblocked test262 harness (assert.js uses template literals).

### Features Implemented
- Template literals: lexer state machine with brace-depth stack, `TemplateLit` AST
- Arrow functions: single/zero/multi-param, block/expression body, lexical `this`
- Prototype chain property lookup in `get_property`/`get_computed_property`
- `Function.call/apply/bind` with proper dispatch
- Array methods: push/pop/shift/unshift/splice/slice/concat/join/indexOf/lastIndexOf/includes/reverse/sort/fill/toString
- String methods: charAt/charCodeAt/indexOf/lastIndexOf/includes/slice/substring/toLowerCase/toUpperCase/trim/split/replace/startsWith/endsWith/repeat/padStart/padEnd
- Object methods: keys/values/entries/create/assign/getPrototypeOf/getOwnPropertyNames/defineProperty
- Math: PI/E/LN2/LN10/LOG2E/LOG10E/SQRT2/SQRT1_2 + abs/floor/ceil/round/trunc/sqrt/pow/min/max/random/sign/log/log2/log10

**Files changed**: 11 files, 3 new files (builtins_array.mbt, builtins_string.mbt, builtins_object.mbt)

---

## Phase 3: Advanced Language Features (8.7% pass rate)

### Features Implemented
- `arguments` object with `.length`, indexed access, `.callee` (sloppy mode)
- Hoisting: `hoist_declarations` pre-pass for `var` and function declarations
- Default/rest parameters, destructuring (array, object, parameter, assignment)
- `for-of` loops, spread in calls/arrays
- Property descriptors: writable/enumerable/configurable, defineProperty, freeze/seal/preventExtensions
- Strict mode: `"use strict"` directive, TDZ enforcement in Phase 3.5
- RegExp: custom parser + backtracking matcher, flags g/i/m, `.test()/.exec()`, String regex methods
- JSON.parse (recursive descent) + JSON.stringify (cycle detection)
- Number builtins: isNaN/isFinite/isInteger/parseInt/parseFloat, toFixed/toString(radix)/valueOf, toPrecision/toExponential

**Files changed**: 10 files, 1 new file (builtins_regex.mbt)

---

## Phase 3.5: ES Spec Compliance (8.77% pass rate)

- Optional chaining (`?.`): `?.prop`, `?.[expr]`, `?.(args)` with chain propagation
- Nullish coalescing (`??`): precedence between `||` and `&&`, mixing validation
- Exponentiation (`**`): right-associative, unary operator restriction
- Computed property names, shorthand properties, method shorthand
- Getters/setters with arity validation
- TDZ for `let`/`const`: `def_tdz`/`initialize` in environment
- Global `this`/`globalThis`
- Abstract equality (`==`) full spec implementation

---

## Phase 3.6: Built-in Compliance + ES6 Classes (27.1% pass rate)

Major jump: comma-separated declarations unblocked ~17% of test262 tests.

### Key Implementations
- ES6 Classes: `class`/`extends`/`super()`/`super.prop`, static methods, computed method names
- Class method enumerability (non-enumerable per spec)
- Comma-separated variable declarations via `StmtList` AST
- Sort comparator exception handling
- URI encoding/decoding: encodeURI/decodeURI/encodeURIComponent/decodeURIComponent
- Function constructor + prototype (call/apply/bind/toString/length/name)
- Logical assignment operators (`&&=`, `||=`, `??=`)
- Numeric separator literals (`1_000`)
- String.toWellFormed/isWellFormed, codePointAt
- Object.fromEntries, getOwnPropertyDescriptors, getOwnPropertySymbols
- Boolean.prototype.toString/valueOf

---

## Phase 4: Modern ES6+ (26.4% pass rate)

Pass rate decreased because more tests were unlocked (larger denominator).

### Features Implemented
- Symbols: `Symbol()`, `Symbol.for()`, `Symbol.keyFor()`, well-known symbols, symbol-keyed properties
- Iteration protocol: `Symbol.iterator`, Array/String iterators, for-of/spread using iterator protocol
- Map/Set: constructors, get/set/has/delete/clear/size, SameValueZero, insertion order, iterators, forEach
- Promises: constructor, then/catch/finally, Promise.all/race/allSettled/any, thenable assimilation, microtask queue
- Timer APIs: setTimeout/clearTimeout/setInterval/clearInterval with event loop + microtask checkpoints
- `instanceof` with `Symbol.hasInstance`

---

## Phase 5: Skip List Cleanup + Async Harness (26.2% pass rate)

### Sub-phases
- **5A**: Removed 18 implemented features from skip lists (+1,200 tests unlocked)
- **5B**: $DONE async test harness via print markers
- **5C**: Object spread `{...obj}` in object literals
- **5D**: `new.target` meta-property with lexical inheritance in arrow functions

**Outcome**: +278 new passing (6,073 -> 6,351), +1,208 more tests executed

---

## Phase 6: Spec Compliance Deep Dive (39.4% pass rate)

### Sub-phases
| Sub | Tests | Key Changes |
|-----|-------|-------------|
| 6A | +~200 | Parser fixes, Array spec compliance |
| 6B | +~200 | String.prototype methods, array elisions, trailing commas |
| 6C | +~400 | Object.prototype chain fix for plain objects |
| 6D | +~250 | Constructor property on all built-in prototypes |
| 6E | +~450 | Unary +, empty statements, Object(null) fix |
| 6F | +~400 | Destructuring parameters in functions/arrows |
| 6G | +~250 | for-of/in destructuring, tagged templates, object method params |
| 6H | +1,202 | Error prototype chain fix (try-catch creates proper Error objects) |
| 6I | +~50 | Leading decimal literals (.5), comma-separated for-init |
| 6J | +~50 | Number.prototype this-validation, String.split limit |
| 6K | +32 | var scoping, rest destructuring, toString tags, AggregateError |
| 6L | +24 | Canonical indices, isPrototypeOf, prototype chain walk |

**Outcome**: 6,351 -> 9,545 passing tests (+3,194)

---

## Phase 7: Spec Compliance & Modules (44.2% pass rate)

### Sub-phases
| Sub | Tests | Key Changes |
|-----|-------|-------------|
| 7A | — | Full accessor descriptor support (get/set in PropDescriptor) |
| 7B | +1,047 | Unicode escapes in identifiers, strings, template literals |
| 7C-E | +65 | Bare for-of/for-in, get/set as identifiers, Math function lengths |
| 7F | +202 | ES Modules (import/export declarations) |

**Outcome**: 9,545 → 10,864 passing tests (+1,319)

---

## Phase 8: ES6 Generators (43.86% pass rate)

Full `function*` / `yield` / `yield*` support. Pass rate denominator increased significantly because generator tests were un-skipped (~3,200 tests moved from skip list to executed).

### Architecture

Used a **statement replay model** rather than the frame-stack/step-engine model originally planned in [GENERATOR_PLAN.md](GENERATOR_PLAN.md):

- Generator body is re-executed from the beginning on each `.next()` call
- Past statements are replayed (skipped via saved program counter `pc`)
- Execution resumes at the exact yield point where the generator was suspended
- This approach reuses the existing direct-style interpreter entirely, avoiding a separate step engine
- Trade-off: replay overhead on resume, but dramatically simpler implementation

### Key Implementations

- **GeneratorObject struct**: `state`, `body`, `params`, `closure`, `env`, `pc`, delegation state, loop env stack, try/catch phase tracking
- **Protocol methods**: `.next(v)`, `.throw(e)`, `.return(v)` on `%GeneratorPrototype%`
- **State machine**: SuspendedStart → Executing → SuspendedYield/Completed with re-entrancy guard
- **YieldSignal / GeneratorReturnSignal**: MoonBit suberrors used as control flow signals
- **yield***: Delegated iteration forwarding `.next()`, `.throw()`, `.return()` to delegate, with IteratorClose on abrupt completion
- **try/catch/finally**: Phase-tracked execution (`try_resume_phase`) to correctly resume into try/catch/finally blocks
- **Loop integration**: `loop_env_stack` preserves per-iteration `let` bindings across yields
- **for-of in generators**: `for_of_iterator`/`for_of_next`/`for_of_resume` fields for iterator protocol state
- **Parameter binding**: Deferred to first `.next()` per spec, including default values, destructuring, and rest params
- **Prototype chain**: generator instance → gen.prototype → %GeneratorPrototype% → %IteratorPrototype%
- **Non-constructible**: `new gen()` throws TypeError
- **Self-iterable**: `gen[Symbol.iterator]() === gen`

### Spec Compliance (PR Review Fixes)

5 rounds of code review addressed:
1. Rest param binding in simple-params branch
2. yield* TypeError for non-iterable delegates
3. `.throw()` TypeError when delegate lacks `.throw` method (with `.return()` cleanup)
4. Iterator method error messages + result validation
5. `.return()` delegation via ReturnAction + generator_continue (so `finally` blocks run)
6. GetMethod spec compliance (TypeError for non-callable non-nullish)
7. IteratorClose result validation (must be Object)
8. Memory cleanup in `complete_generator` (clear mutable fields on completion)

### Test262 Results

| Category | Passed | Failed | Rate |
|----------|--------|--------|------|
| GeneratorPrototype | 26 | 32 | 44.8% |
| GeneratorFunction | 0 | 20 | 0.0% |

Overall: 10,864 → 11,316 passing (+452), with ~3,200 previously-skipped generator tests now executed.

### Files Changed

- `interpreter/generator.mbt` (~960 lines, new file) — generator runtime
- `interpreter/interpreter.mbt` — generator-aware control flow, assign_pattern iterator protocol
- `interpreter/builtins_object.mbt` — warning cleanup
- `interpreter/errors.mbt` — warning cleanup
- `ast/ast.mbt` — GeneratorDecl, GeneratorExpr, YieldExpr AST nodes
- `parser/parser.mbt` — function*/yield/yield* parsing
- `cmd/main/main.mbt` — generator test cases
- `.github/workflows/test262.yml` — CI optimization (node direct, 4 threads, 90min timeout)
- `test262-runner.py` — removed generators from skip list, added staging skip

**Unit tests**: +59 generator-specific tests (580 → 639)

---

## Phase 8C: Date Object (45.27% pass rate)

Full ES5/ES6 Date implementation with constructor, prototype methods, static methods, and JSON.stringify improvements.

### Key Implementations

- **Date constructor**: `new Date()` (current time), `new Date(value)` (milliseconds/string), `new Date(y,m,d,h,m,s,ms)` (components)
- **Called without `new`**: `Date()` returns current date string via `is_constructing` global flag
- **Static methods**: `Date.now()`, `Date.parse()` (ISO 8601), `Date.UTC()`
- **Prototype getters**: getTime, getFullYear, getMonth, getDate, getDay, getHours, getMinutes, getSeconds, getMilliseconds (+ UTC variants)
- **Prototype setters**: setTime, setFullYear, setMonth, setDate, setHours, setMinutes, setSeconds, setMilliseconds (+ UTC variants)
- **Formatting**: toString, toISOString, toUTCString, toDateString, toTimeString, toLocaleString, toLocaleDateString, toLocaleTimeString, toGMTString
- **Conversion**: valueOf, toJSON, `Symbol.toPrimitive` with hint-based dispatch
- **Legacy**: getYear, setYear (Annex B)
- **Internal slot**: `[[DateValue]]` as non-enumerable property via PropDescriptor

### Date Algorithms

- `day_from_year(y)`: Floor division (not truncation) for correct pre-1970 leap year handling
- `year_from_time(t)`: Linear adjustment from `(d / 365.2425 + 1970)` approximation
- `month_from_time(t)`, `date_from_time(t)`: Day-in-year based with leap year awareness
- `make_day(y, m, d)`, `make_date(day, time)`: Spec-compliant date composition
- `time_clip(t)`: Uses floor/ceil instead of `.to_int()` to avoid integer overflow
- ISO 8601 parser: Manual whitespace trimming (MoonBit `String.trim` API differs)

### JSON.stringify Improvements

- Walk full prototype chain when resolving `toJSON` (while loop, not single-level)
- Invoke any callable `toJSON` via `Interpreter::call_value` (promoted from NativeCallable to InterpreterCallable)
- Filter internal `[[...]]` properties from JSON serialization

### Test262 Results

| Category | Passed | Failed | Skipped | Rate |
|----------|--------|--------|---------|------|
| built-ins/Date | 249 | 285 | 60 | 46.6% |

Overall: 11,333 → 11,678 passing (+345)

### Files Changed

- `interpreter/builtins_date.mbt` (~1,800 lines, new file) — Date implementation
- `interpreter/builtins.mbt` — Date registration, JSON.stringify improvements
- `interpreter/value.mbt` — `is_constructing` flag, `well_known_toprimitive_sym`, Date `to_number`
- `interpreter/interpreter.mbt` — `is_constructing` flag management in `eval_new`
- `interpreter/moon.pkg.json` — Added `moonbitlang/core/env` import

### Bug Fixes

1. `day_from_year` integer division → floor division for pre-1970 dates (e.g., year 1967)
2. `year_from_time` binary search → linear adjustment for negative timestamps
3. `time_clip` integer overflow → floor/ceil for large timestamps
4. `toJSON` prototype chain walk: single-level → full chain
5. `toJSON` callable dispatch: MethodCallable-only → any callable via interpreter
6. `Date()` without `new`: returned object → returns string per spec

**Unit tests**: 658 total (unchanged)

---

## Phase 9: P0–P3 Spec Compliance Sweep (74.17% pass rate)

Massive compliance push targeting four priority areas from failure analysis. Jumped from 11,678 to 19,117 passing tests (+7,439).

### P0: JsException Error Diagnostics

**Problem**: All uncaught JS exceptions printed as the opaque string `Error: dowdiness/js_engine/interpreter.JsException.JsException`, making CI failures undiagnosable.

**Fix**: Rewrote `cmd/main/main.mbt` error handler to catch `JsException(value)` and all `JsError` variants (`TypeError`, `ReferenceError`, `SyntaxError`, `RangeError`, `URIError`, `EvalError`, `InternalError`) with proper formatting.

**Impact**: No direct pass-rate change, but made every subsequent CI run actionable.

### P1: Generator Methods in Class/Object Bodies (~830–1,096 tests)

**Problem**: `SyntaxError: Expected method name at line X, col Y` when parsing `class C { *gen() { yield 1; } }` or `{ *gen() { yield } }`.

**Fix**:
- `parse_class_method()`: Added `is_generator = self.eat(Star)` after static check, wrapped get/set detection in `if not(is_generator)`, produces `GeneratorExpr`/`GeneratorExprExt` when generator
- `parse_object_literal()`: Detects `*` before method name, parses as generator with `push_generator_context(true)` for yield expression support
- Both paths include full keyword-to-name mapping (40+ keywords as valid method names)

### P2: Destructuring Defaults (~644 tests)

**Problem**: `SyntaxError: Expected Comma, got Assign` for `[a = 1] = arr` and runtime failures for `{x = 5} = obj`.

**Fix**:
- AST: Added `DefaultPat(Pattern, Expr)` variant to `Pattern` enum
- Parser: `parse_array_pattern()` handles `= expr` after each element
- Parser: `expr_to_pattern()` converts `Assign(name, expr)` to `DefaultPat(IdentPat(name), expr)` and `DestructureAssign(expr, default)` to `DefaultPat(pattern, default)`
- Interpreter: All 5 pattern-matching sites (`bind_pattern`, `assign_pattern`, `hoist_pattern`, `hoist_pattern_tdz`, `extract_pattern_export_names`) updated for `DefaultPat`
- Runtime evaluates default expression when bound value is `undefined`

### P3: Parser Cleanup (~285 tests)

**Problem**: `Invalid destructuring pattern` and `Invalid arrow function parameter list` errors across various contexts.

**Fixes**:
1. **Object destructuring `{a: b = 1}` bug**: Removed buggy special `Assign` case in ObjectLit handler of `expr_to_pattern` that was binding to property key instead of assignment target
2. **Array elision holes**: `UndefinedLit` → `None` in array pattern conversion
3. **`AssignTarget(Expr)` pattern**: New Pattern variant for member expression targets in destructuring assignment (`[obj.x] = [1]`)
4. **`Of` as contextual identifier**: Added to `expect_ident()` and `parse_primary()`
5. **Complex arrow params**: Created `expr_to_ext_arrow_params()` fallback for destructuring/default patterns in arrow function parameters
6. All 5 interpreter pattern-matching sites updated for `AssignTarget`

### PR Review Fixes

Addressed CodeRabbit review feedback:
1. **Rest-element-must-be-last validation**: `rest_seen` flag in `expr_to_pattern` raises `SyntaxError` if elements follow a rest/spread element in array or object destructuring
2. **`Yield` keyword mapping**: Added `Yield => Some("yield")` to all three keyword-to-name match blocks so `yield` is accepted as a method/property name

### Test262 Results

| Category | Passed | Failed | Rate |
|----------|--------|--------|------|
| language/expressions | 4,637 | 1,062 | 81.4% |
| language/statements | 3,130 | 1,187 | 72.5% |
| built-ins/Object | 2,834 | 466 | 85.9% |
| built-ins/Array | 2,182 | 701 | 75.7% |
| built-ins/String | 1,050 | 108 | 90.7% |
| built-ins/Date | 511 | 23 | 95.7% |
| built-ins/NativeErrors | 82 | 0 | 100.0% |

Overall: 11,678 → 19,117 passing (+7,439), 45.27% → 74.17%

### Files Changed

- `cmd/main/main.mbt` — Error handler rewrite for JsException/JsError
- `cmd/main/moon.pkg.json` — Added interpreter and errors imports
- `ast/ast.mbt` — `DefaultPat`, `AssignTarget` pattern variants
- `ast/pkg.generated.mbti` — Updated interface file
- `parser/expr.mbt` — Generator methods, destructuring patterns, arrow params, keyword mappings
- `parser/parser.mbt` — `Of` in `expect_ident()`
- `parser/stmt.mbt` — Array pattern defaults
- `interpreter/interpreter.mbt` — `DefaultPat`, `AssignTarget` in all 5 pattern sites

---

## MoonBit-Specific Workarounds

These are language-specific gotchas discovered during development:

- `test`, `method`, `constructor` are reserved keywords in MoonBit
- `T?` not allowed in toplevel struct declarations — use `Option[T]`
- `type!` syntax deprecated — use `suberror`
- `!` error handling deprecated — use `raise Error` in signatures
- `.lsl()`/`.asr()` deprecated — use `<<`/`>>` infix operators
- Hex literal method calls fail to parse (e.g., `0x7FFFFFFF.asr()`) — assign to variable first
- `at(TokenKind)` uses `==`, won't match variant payloads — use `is` pattern instead
- `source.view()[start:offset].to_string()` for string slicing in lexer

---

## CodeRabbit Review (PR #4) - All Issues Resolved

| Issue | Resolution |
|-------|-----------|
| QuestionQuestion/QuestionDot regex context | Already in regex-start list |
| var/var redeclaration | Implemented in environment.mbt |
| OptionalCall this-binding | Preserves receiver for method calls |
| Exponentiation unary operators | Added typeof/void/delete restriction |
| Nullish coalescing && mixing | Rejects `a && b ?? c` |
| Getter/setter arity validation | Getters=0, Setters=1 |
| Global this extensible field | Set to true |
| Skip lists sync | Both files synced |
