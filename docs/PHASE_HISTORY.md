# Phase Implementation History (Archive)

Detailed implementation notes for completed phases (1-16). For current status and future plans, see [ROADMAP.md](../ROADMAP.md).

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

---

## Phase 10: P4 Object Descriptor Compliance

Comprehensive object descriptor compliance targeting the P4 milestone from [IMPLEMENTATION_PRIORITY.md](IMPLEMENTATION_PRIORITY.md). Focused on strict non-configurable invariants, Symbol key support, function property descriptors, and Array target handling.

### P4a: Symbol Key Support in defineProperty

**Problem**: `defineProperty` and `getOwnPropertyDescriptor` converted all property keys to strings via `.to_string()`, making Symbol-keyed property operations silently wrong.

**Fix**:
- `defineProperty`: Checks `prop_val is Symbol(_)` and routes to `data.symbol_properties` / `data.symbol_descriptors` instead of `data.properties` / `data.descriptors`
- `getOwnPropertyDescriptor`: Same Symbol key detection; returns correct descriptors for Symbol-keyed properties including accessor descriptors
- Full non-configurable/non-writable validation extended to Symbol-keyed properties

### P4b: Function Property Descriptors

**Problem**: `getOwnPropertyDescriptor` returned `undefined` for function built-in properties (`length`, `name`), and `prototype` had wrong descriptor flags (defaulted to all-true).

**Fix**:
- `getOwnPropertyDescriptor` on Object with `callable`: returns descriptors for `length` (param count, `{writable: false, enumerable: false, configurable: true}`), `name` (function name, same flags), and `prototype` (from existing property)
- `make_func` / `make_func_ext` in `value.mbt`: `prototype` property now created with correct descriptor `{writable: true, enumerable: false, configurable: false}` per ES spec

### P4c: defineProperties Validation + Array Targets

**Problem**: `defineProperties` had no non-configurable validation, didn't throw TypeError on non-object targets, and iterated non-enumerable properties of the descriptor object. `defineProperty` rejected Array/Map/Set/Promise targets and descriptors despite them being valid JS objects.

**Fix**:
- `defineProperty`: Accepts `Array(_) | Map(_) | Set(_) | Promise(_)` as targets and descriptors
- `defineProperty` on Array targets: handles index property setting and `length` changes (truncation/extension)
- `defineProperties`: Throws TypeError on non-object target, only iterates enumerable own properties
- Shared `validate_non_configurable` helper function (~95 lines) eliminates ~150 lines of duplicated validation logic between `defineProperty` and `defineProperties`

### PR Review Fixes (PR #30)

Addressed 4 review issues:
1. **defineProperties Array targets**: Match pattern updated to `Object(_) | Array(_) | Map(_) | Set(_) | Promise(_)`
2. **Dead code removal**: `not(existing_is_accessor) && not(is_accessor) == false` (always false due to precedence) replaced with correct generic descriptor check
3. **Accessor identity checks**: `defineProperties` now validates getter/setter identity for non-configurable accessor properties, mirroring `defineProperty`
4. **Shared validation helper**: Extracted `validate_non_configurable` used by both `defineProperty` and `defineProperties`

### Test262 Results

| Category | Passed | Failed | Skip | Rate |
|----------|--------|--------|------|------|
| built-ins/Object | 2,547 | 321 | 112 | 88.8% |

### Files Changed

- `interpreter/builtins_object.mbt` — defineProperty, getOwnPropertyDescriptor, defineProperties rewrite + shared validator (~+850/-520 lines)
- `interpreter/value.mbt` — Function prototype descriptor initialization (+20 lines)
- `docs/IMPLEMENTATION_PRIORITY.md` — P4 marked as done

**Unit tests**: 658 total, 658 passed, 0 failed (no regressions)

---

## Phase 11: P5 eval() Semantics (78.22% pass rate)

Full direct/indirect eval implementation per ES spec EvalDeclarationInstantiation. Jumped from 19,117 to 19,720 passing tests (+603).

### eval() Architecture

- **Direct eval detection**: `unwrap_grouping()` helper recursively strips `Grouping` nodes so `eval(...)`, `(eval)(...)`, `((eval))(...)` are all detected as direct eval in `eval_call`
- **Callable type**: `NonConstructableCallable("eval", fn)` — prevents `new eval()` (TypeError). Indirect eval calls intercepted in `call_value` where the Interpreter is available for `perform_eval()`
- **`perform_eval(code, caller_env, direct)`**: Core eval function handling both direct and indirect eval
- **Variable environment**: `Environment::find_var_env()` walks up the scope chain to the nearest `is_var_scope` environment (function or global), ensuring `eval("var x = 1")` inside a block hoists to the function scope, not the block

### Direct vs Indirect Eval

| Aspect | Direct eval | Indirect eval |
|--------|------------|---------------|
| Detection | `Ident("eval")` after unwrap_grouping | All other call paths |
| Scope | Caller's lexical environment | Global environment |
| var/function | Leaks to caller's variable environment | Leaks to global |
| Strict mode | Inherits caller's strict mode | Only own "use strict" |
| Example | `eval("...")` | `(0, eval)("...")`, `var e = eval; e("...")` |

### Non-strict eval: var leaking

1. `var_env = caller_env.find_var_env()` — walk up to enclosing function/global
2. `hoist_declarations(stmts, var_env)` — hoist var/function declarations to var_env
3. `exec_env = Environment::new(parent=caller_env)` — eval code runs in new scope
4. `hoist_block_tdz(stmts, exec_env)` — let/const TDZ markers stay in eval scope

### EvalDeclarationInstantiation Conflict Checks

**Step 5.a** — Global lexical conflict: If `var_env` is the global scope, check that eval's var names don't conflict with global `let`/`const` declarations. Example: `let x; eval("var x")` → SyntaxError.

**Step 5.d** — Intermediate scope conflict: Walk from `caller_env` up to `var_env`, checking each intermediate scope for binding conflicts. Example: `{ let x; { eval("var x"); } }` → SyntaxError (var can't hoist past the let x).

Helper: `collect_eval_var_names(stmts)` gathers all var/function declaration names from eval code for conflict checking, including destructuring patterns via `collect_pattern_var_names()`.

### FuncDecl var hoisting fix

FuncDecl handler in `exec_stmt` now uses `has_var`/`assign_var` fallback (matching the VarDecl pattern) so function declarations in eval target the correct variable environment rather than creating shadowing bindings in the exec scope.

### ES spec evaluation order fix

All branches of `eval_call` now resolve callee/receiver before evaluating arguments, per ES spec section 13.3.6.1 CallExpression evaluation.

### CI/Build fixes

- CI workflow: `moon build --target js --release` (was missing `--release`)
- CI workflow: Removed hardcoded `--engine` path; test262-runner.py auto-detects JS bundle
- test262-runner.py: `should_skip()` now respects `onlyStrict`/`noStrict` flags
- Fixed deprecated MoonBit syntax: `raise` annotations on closures, `nobreak` for `else` in for loops
- All 254 `deprecated_syntax` warnings resolved

### Test262 Results

| Category | Passed | Failed | Skip | Rate |
|----------|--------|--------|------|------|
| language/eval-code | 224 | 106 | 17 | 67.9% |
| language/eval-code/direct/var-env-* | 20 | 0 | 7 | 100.0% |

Overall: 19,117 → 19,720 passing (+603), 74.17% → 78.22%

### Files Changed

- `interpreter/interpreter.mbt` — `unwrap_grouping`, `perform_eval`, `eval_call` direct eval detection, `find_var_env` usage, `collect_eval_var_names`/`collect_pattern_var_names`, FuncDecl `has_var`/`assign_var` fix, evaluation order fix
- `interpreter/environment.mbt` — `find_var_env()`, `has_var()`, `assign_var()` methods, `is_var_scope` field
- `interpreter/builtins.mbt` — eval as `NonConstructableCallable`
- `interpreter/interpreter_test.mbt` — eval-specific tests (+37 tests, 658 → 695)
- `interpreter/builtins_array.mbt`, `builtins_date.mbt`, `builtins_map_set.mbt`, `builtins_object.mbt`, `builtins_promise.mbt`, `builtins_string.mbt`, `generator.mbt` — deprecated fn syntax fixes
- `js_engine.mbt` — `nobreak` keyword fix
- `.github/workflows/test262.yml` — release build, auto-detect engine path
- `test262-runner.py` — auto-detect JS bundle, `onlyStrict`/`noStrict` skip logic

**Unit tests**: 695 total, 695 passed, 0 failed

---

## Phase 12: P6 Strict-Mode Prerequisite Bundle (78.22% pass rate)

Narrow, high-ROI strict-mode checks that gate many test262 syntax/runtime tests. Gained +3 test262 tests (19,720 → 19,723).

### Key Implementations

- **Duplicate parameters in strict functions**: `check_duplicate_params()` / `check_duplicate_params_ext()` raise SyntaxError when a function with `"use strict"` (or in a strict context) has duplicate parameter names. Applied in `call_value` and `eval_new` for both `UserFunc` and `UserFuncExt`.
- **Assignment to `eval`/`arguments` in strict contexts**: `validate_strict_binding_name()` checks applied at all binding sites: `Assign`, `eval_update` (++/--), `eval_compound_assign` (+=, etc.), logical assignment operators (&&=, ||=, ??=), `VarDecl`, `FuncDecl`/`FuncDeclExt`, and function parameter binding.
- **`delete` unqualified identifier**: Added `Ident` case in the `Delete` unary operator handler — raises SyntaxError when `self.strict` is true.
- **Strict-only reserved words**: `is_strict_reserved_word()` checks `implements`, `interface`, `package`, `private`, `protected`, `public`. Enforced via `validate_strict_binding_name()` at all binding sites.
- **Class body implicit strict mode**: `ensure_strict_body()` prepends `"use strict"` directive to class method bodies and constructor bodies in `create_class()`. `ClassConstructor` execution in `eval_new` saves/restores `self.strict = true`.
- **Class constructor parameter validation**: `check_duplicate_params()` and `validate_strict_binding_name()` applied to class constructor parameters — `constructor(eval)`, `constructor(a, a)`, `constructor(arguments)` now correctly throw SyntaxError.
- **Sloppy duplicate params fix**: `call_value` and `eval_new` now allow duplicate parameter names in sloppy mode (last value wins) instead of throwing.

### PR Review Fixes (PR #32)

3 rounds of code review addressed:
1. Generator function name validation — strict-mode reserved words checked via `validate_strict_binding_name()` for `function* eval()` and `function* arguments()`
2. Class constructor parameter validation — `check_duplicate_params()` and `validate_strict_binding_name()` applied to class constructor params
3. Early-return strict-state restore comment — explanatory comment on `self.strict = saved_strict` before `return v` in eval_new
4. Test TODO comment — added note explaining sloppy `this` returning "undefined" due to missing globalThis binding

### Test262 Results

| Category | Passed | Failed | Rate |
|----------|--------|--------|------|
| language/function-code | 166 | 7 | 96.0% |
| language/arguments-object | 145 | 7 | 95.4% |

Overall: 19,720 → 19,723 passing (+3), 78.22%

### Files Changed

- `interpreter/interpreter.mbt` — `check_duplicate_params`, `validate_strict_binding_name`, `is_strict_reserved_word`, `ensure_strict_body`, class constructor param validation, early-return comment
- `interpreter/interpreter_test.mbt` — P6-specific tests (+30 tests, 695 → 730)
- `interpreter/builtins.mbt` — strict-mode validation in generator function declarations

**Unit tests**: 730 total, 730 passed, 0 failed

---

## Phase 13: P7 Promise Species Constructor and Complete Compliance (82.41% pass rate)

Achieved 100% Promise test compliance through species constructor implementation and critical interpreter fixes with broad impact. Gained +1,080 test262 tests (19,723 → 20,803).

### Key Implementations

**Promise Species Constructor (Subclassing Support)**:
- **`get_promise_species_constructor()`**: Implements ES spec's SpeciesConstructor(promise, %Promise%) algorithm, consulted by `then`, `catch`, `finally` to determine constructor for derived promises
- **`Promise[Symbol.species]`**: Getter returns `this`, enabling subclasses to override constructor selection
- **Constructor preservation**: Promise subclass instances store constructor in `properties["constructor"]` with proper descriptor for species lookups
- **`Promise.reject` receiver support**: Refactored to use `create_promise_capability_from_constructor` for proper subclassing
- **Constructor-aware combinators**: `Promise.all/race/any/allSettled` refactored to respect receiver constructor via `create_promise_capability_from_constructor(interp, _this, loc)`

**Critical Interpreter Fixes (Broad Test Impact)**:
- **Sloppy mode `this` normalization**: Functions called with `this` as `undefined`/`null` now correctly substitute `globalThis` in sloppy mode via `normalize_sloppy_this` helper. Fixed test harness compatibility and ~200+ sloppy mode tests
- **`Function.prototype.apply` array-like support**: Fixed to accept any array-like object (objects with `length` property), not just Array instances. Handles `arguments` object forwarding pattern via computed property iteration
- **Arguments object in constructors**: Class constructors and super constructors now have access to `arguments` object via `make_arguments_object` binding
- **Function `prototype.constructor` link**: Functions now establish bidirectional reference (`func.prototype.constructor === func`), enabling navigation from instances back to constructors

**Previous Combinator Work** (from earlier commit):
- Shared abrupt path handling and iterator-close alignment across combinators
- Thenable assimilation fixes for edge cases
- Final resolve/reject safety in combinator paths

### Test262 Results

| Category | Passed | Failed | Skipped | Rate | Notes |
|----------|--------|--------|---------|------|-------|
| built-ins/Promise | 599 | 0 | 41 | 100.0% | ✅ Complete (was 580/599, 96.8%) |
| language/block-scope | 106 | 0 | 39 | 100.0% | ✅ Complete (was 47/106, 44.3%) |
| language/expressions | 4,849 | 638 | 5,490 | 88.4% | +236 tests (was 84.0%) |
| language/statements | 3,449 | 723 | 5,106 | 82.7% | +236 tests (was 77.0%) |
| built-ins/Function | 325 | 68 | 116 | 82.7% | +31 tests (was 74.8%) |

**Overall: 19,723 → 20,803 passing (+1,080), 78.22% → 82.41%**

The 41 skipped Promise tests include one deferred `Proxy`-dependent case:
`built-ins/Promise/prototype/finally/this-value-proxy.js`.

### Files Changed

- `interpreter/builtins_promise.mbt` — species constructor implementation, `then/catch/finally` species support, combinator capability refactoring, `Promise.reject` capability, `Promise[Symbol.species]` getter, constructor preservation
- `interpreter/interpreter.mbt` — sloppy mode `this` normalization (`normalize_sloppy_this`), `Function.prototype.apply` array-like support, arguments object in constructors, `maybe_set_promise_constructor` helper
- `interpreter/value.mbt` — function `prototype.constructor` bidirectional link in `make_func` and `make_func_ext`
- `interpreter/interpreter_test.mbt` — 3 new tests: Promise species, apply array-like, constructor arguments; updated sloppy mode test expectations

**Unit tests**: 763 total (+3), 763 passed, 0 failed

---

## Phase 14: Small Compliance Sweep (82.7% pass rate)

Targeted quick wins across Unicode whitespace, Number, and String built-ins. Gained +67 test262 tests (20,803 → 20,870).

### Key Implementations

- **Unicode whitespace**: Extended `is_js_whitespace()` to include all ECMAScript Unicode Space_Separator (Zs) characters: U+1680, U+2000-200A, U+202F, U+205F, U+3000. Added U+2028/U+2029 line terminator recognition.
- **Number.prototype.toLocaleString()**: Implemented with proper primitive/object wrapper handling, delegates to `toString()`.
- **String.prototype.trimLeft/trimRight**: Deprecated aliases for `trimStart`/`trimEnd` per Annex B.
- **String.prototype.toLocaleString()**: Simple delegation implementation.
- **String.prototype.matchAll()**: Iterator-based method with global flag validation, returns proper iterator with `next()` yielding `{value, done}` objects.

### Test262 Results

| Category | Passed | Failed | Rate |
|----------|--------|--------|------|
| language/white-space | 66 | 1 | 98.5% |

Overall: 20,803 → 20,870 passing (+67), 82.41% → 82.7%

### Files Changed

- `lexer/lexer.mbt` — `is_js_whitespace()` Unicode extension, line terminator recognition
- `interpreter/builtins_string.mbt` — matchAll, trimLeft/trimRight, toLocaleString
- `interpreter/builtins.mbt` — Number.prototype.toLocaleString registration

---

## Phase 15: Proxy and Reflect (83.16% pass rate)

Full ES6 Proxy and Reflect implementation with 13 proxy traps and 13 Reflect methods. Gained +877 test262 tests (20,870 → 21,747).

### Proxy Architecture

- **`Proxy` Value variant**: New `Proxy(ProxyData)` variant in the `Value` enum. `ProxyData` struct has mutable `target: Value?` and `handler: Value?` fields (None = revoked).
- **`Proxy(target, handler)` constructor**: Validates target/handler are objects, creates ProxyData.
- **`Proxy.revocable(target, handler)`**: Returns `{proxy, revoke}` object; `revoke()` sets target/handler to `None`.
- **Trap resolution**: `get_proxy_trap(proxy_data, trap_name)` looks up handler property, validates callable, returns `None` for absent traps. TypeError on revoked proxy.
- **Target/handler access**: `get_proxy_target(proxy_data)` and `get_proxy_handler(proxy_data)` with revocation checks.

### 13 Proxy Traps

All traps are handled via a consistent pattern: check for trap in handler, call trap if present, fall through to target operation if absent.

| Trap | Intercepted Operations |
|------|----------------------|
| `get` | Property access (`obj.prop`, `obj[expr]`) |
| `set` | Property assignment (`obj.prop = val`, `obj[expr] = val`) |
| `has` | `in` operator |
| `apply` | Function calls (`proxy(args)`, `Reflect.apply`) |
| `construct` | `new proxy(args)`, `Reflect.construct` |
| `deleteProperty` | `delete proxy.prop` |
| `defineProperty` | `Object.defineProperty(proxy, ...)` |
| `ownKeys` | `Object.keys()`, `Reflect.ownKeys()`, `for-in` |
| `getPrototypeOf` | `Object.getPrototypeOf()` |
| `setPrototypeOf` | `Object.setPrototypeOf()` |
| `isExtensible` | `Object.isExtensible()` |
| `preventExtensions` | `Object.preventExtensions()` |
| `getOwnPropertyDescriptor` | `Object.getOwnPropertyDescriptor()` |

### Reflect API

13 static methods on the `Reflect` object, each corresponding to a proxy trap:

- **`Reflect.apply(target, thisArg, args)`**: Calls target with specified `this` and arguments via `create_list_from_array_like()`
- **`Reflect.construct(target, args, newTarget?)`**: Invokes constructor, supports optional `newTarget` for prototype selection
- **`Reflect.defineProperty(target, key, desc)`**: Returns boolean (vs Object.defineProperty which returns the object)
- **`Reflect.deleteProperty(target, key)`**: Returns boolean success
- **`Reflect.get(target, key, receiver?)`**: Property access with optional receiver for getter `this` binding; supports Symbol keys
- **`Reflect.getOwnPropertyDescriptor(target, key)`**: Returns property descriptor or undefined
- **`Reflect.getPrototypeOf(target)`**: Returns prototype
- **`Reflect.has(target, key)`**: `in` operator as a function
- **`Reflect.isExtensible(target)`**: Returns extensibility flag
- **`Reflect.ownKeys(target)`**: Returns all own keys (string + symbol); `InterpreterCallable` for Proxy ownKeys trap support
- **`Reflect.preventExtensions(target)`**: Sets extensible to false
- **`Reflect.set(target, key, value, receiver?)`**: Property assignment returning boolean; respects non-writable descriptors
- **`Reflect.setPrototypeOf(target, proto)`**: Returns boolean success

**Key helper functions**:
- `create_list_from_array_like(val)`: Converts Array or array-like Object to `Array[Value]` per spec's CreateListFromArrayLike
- `unwrap_proxy_target(val)`: Recursively unwraps `Proxy(Proxy(Object))` chains to get underlying `ObjectData`

### Interpreter Integration

- **`for-in`**: `collect_for_in_keys` signature changed to `raise Error`, invokes ownKeys trap for Proxy targets, throws TypeError for revoked proxies
- **`instanceof`**: Checks `Symbol.hasInstance` on Proxy before falling back to prototype chain walk
- **`delete`**: Strict mode throws TypeError when proxy's deleteProperty trap returns `false` (both member and computed member)
- **`apply`**: Recursive `check_callable` for nested proxy chains (`Proxy(Proxy(Function))`)
- **JSON.stringify**: Unwraps Proxy to target for serialization instead of hardcoded `{}`
- **Object built-ins**: `Object.assign`, `Object.defineProperty`, `Object.getOwnPropertyDescriptor`, `Object.getPrototypeOf`, `Object.create`, `Object.defineProperties` all extended with Proxy support

### PR Review Fixes

3 commits addressing 16 total review issues:

**Commit 1** (4 issues): Reflect.construct newTarget, getOwnPropertyDescriptor accessor, Reflect.set non-writable, Reflect.get Symbol keys

**Commit 2** (12 issues): JSON.stringify Proxy, Object.assign Proxy, Object.defineProperty Proxy, Object.getOwnPropertyDescriptor Proxy, for-in ownKeys trap, instanceof Symbol.hasInstance, deleteProperty strict mode, apply trap callability, Object.getPrototypeOf Proxy, Object.create Proxy, Object.defineProperties Proxy, deduplicated array-like conversion

**Commit 3**: Enabled Proxy/Reflect test262 tests (removed from skip lists), fixed all Reflect methods to accept Proxy arguments via `unwrap_proxy_target()`, converted Reflect.ownKeys to InterpreterCallable, added recursive proxy callability check for apply trap

**Commit 4** (PR #33 review follow-up, 10 issues): Reflect.defineProperty extensibility + non-configurable validation (returns `Bool(false)` per spec), Reflect.setPrototypeOf extensibility check, Reflect.has + Reflect.set descriptor awareness, Object.assign revoked Proxy TypeError, Object.defineProperty/defineProperties Proxy paths with `validate_non_configurable` and full accessor/data validation, Object.create unreachable code fix, `get_proxy_trap` prototype chain walk, `construct_value` target constructability pre-check. Also eliminated all 20 compiler `deprecated_syntax` warnings by adding `raise` annotations to `fn` closures.

### Test262 Results

| Category | Passed | Failed | Skipped | Rate |
|----------|--------|--------|---------|------|
| built-ins/Proxy | 257 | 15 | 39 | 94.5% |
| built-ins/Reflect | 152 | 1 | 0 | 99.3% |

Overall: 20,870 → 21,747 passing (+877), 82.7% → **83.16%**, no regressions

### Remaining Failures (16 tests)

| Root Cause | Count | Notes |
|------------|-------|-------|
| `with` statement not supported | 4 | Proxy tests requiring `with(proxy)` |
| Boxed primitives (`new String()`, `new Number()`) | 10 | Not represented as Object internally |
| Module import issue | 1 | Pre-existing limitation |
| Array length edge case | 1 | Pre-existing limitation |

### Known Limitations (6 deferred items)

These require larger refactoring (e.g., `NativeCallable` → `InterpreterCallable` conversions, function signature changes) and are deferred to a future phase:

| Issue | Root Cause | Impact |
|-------|-----------|--------|
| `Object.getPrototypeOf` skips `getPrototypeOf` trap | Uses `NativeCallable`, can't call interpreter | Low — only affects Proxy with custom `getPrototypeOf` handler |
| `for-in` skips `ownKeys` trap | `collect_for_in_keys` is standalone fn, needs interpreter | Low — delegates to target directly |
| `instanceof` revoked Proxy prototype walk | Doesn't invoke `getPrototypeOf` trap | Low — only affects revoked Proxy edge case |
| `create_list_from_array_like` skips Proxy traps | Reads `.properties` directly | Low — only affects Proxy wrapping array-like |
| `Reflect.construct` prototype timing | Rewires `newTarget` prototype after construction instead of before | Low — spec compliance edge case |
| `unwrap_proxy_target` rejects non-Object | Returns `None` for Array/Map/Set/Promise targets | Low — Reflect methods may throw incorrect TypeError |

### Files Changed

- `interpreter/builtins_proxy.mbt` (~240 lines) — Proxy constructor, revocable, trap helpers with prototype chain walk
- `interpreter/builtins_reflect.mbt` (~820 lines) — All 13 Reflect methods, `create_list_from_array_like`, `unwrap_proxy_target`, full validation
- `interpreter/interpreter.mbt` — for-in, instanceof, deleteProperty, apply, construct trap fixes
- `interpreter/builtins.mbt` — JSON.stringify Proxy fix, Proxy/Reflect registration
- `interpreter/builtins_object.mbt` — Object.assign/defineProperty/getOwnPropertyDescriptor/getPrototypeOf/create/defineProperties Proxy integration with full validation
- `interpreter/value.mbt` — `Proxy(ProxyData)` value variant, ProxyData struct
- `test262-runner.py` — Removed Proxy/Reflect from skip lists
- `test262-analyze.py` — Removed Proxy/Reflect from skip lists
- `js_engine_test.mbt` — Proxy/Reflect regression tests

**Unit tests**: 799 total (+36), 799 passed, 0 failed

---

## Phase 16: TypedArray, ArrayBuffer, and DataView (pending test262 re-run)

Full TypedArray/ArrayBuffer/DataView implementation with 9 typed array types, DataView with all getter/setter methods, and ArrayBuffer with slice/detach support. ~3,724 lines of new builtin code across 3 new files.

### ArrayBuffer Implementation (builtins_arraybuffer.mbt, ~400 lines)

- **Constructor**: `new ArrayBuffer(byteLength)` with non-negative length validation, `requires new` check
- **`ArrayBuffer.isView(arg)`**: Returns `true` for TypedArray and DataView instances
- **`ArrayBuffer.prototype.slice(begin, end)`**: Creates new buffer with byte range copy; throws TypeError if detached
- **`ArrayBuffer.prototype.byteLength`**: Getter that throws TypeError on detached buffer
- **Detachment tracking**: Global `Set[Int]` of detached buffer IDs. `detach_arraybuffer(id)` marks detached, `is_arraybuffer_detached(id)` queries state
- **`$262.detachArrayBuffer(buf)`**: Full implementation replacing the previous no-op stub; enables test262 detachment tests
- **Buffer validation helper**: `validate_typedarray_buffer(data)` throws TypeError on detached buffer; used by all TypedArray iteration methods

### TypedArray Implementation (builtins_typedarray.mbt, ~2,414 lines)

**9 typed array types**:
- `Int8Array` (1 byte, signed -128..127)
- `Uint8Array` (1 byte, unsigned 0..255)
- `Uint8ClampedArray` (1 byte, clamped 0..255)
- `Int16Array` (2 bytes, signed)
- `Uint16Array` (2 bytes, unsigned)
- `Int32Array` (4 bytes, signed)
- `Uint32Array` (4 bytes, unsigned)
- `Float32Array` (4 bytes, IEEE 754 single precision)
- `Float64Array` (8 bytes, IEEE 754 double precision)

**Constructors** (4 paths):
1. From length: `new Uint8Array(10)` — allocates new buffer
2. From array/iterable: `new Uint8Array([1, 2, 3])` — copies element values
3. From another TypedArray: `new Int32Array(uint8)` — type conversion copy
4. From ArrayBuffer: `new Uint8Array(buf, offset, length)` — view over existing buffer
   - Rejects detached ArrayBuffer (TypeError)
   - Validates byteOffset alignment and non-negative value (RangeError)
   - Validates length bounds against buffer size

**Prototype methods** (25 methods):
- Mutation: `set`, `copyWithin`, `fill`, `reverse`, `sort`
- Slicing: `subarray`, `slice`
- Search: `indexOf`, `lastIndexOf`, `includes`
- Iteration: `forEach`, `map`, `filter`, `reduce`, `reduceRight`, `every`, `some`, `find`, `findIndex`
- Conversion: `join`, `toString`, `at`
- `sort` supports custom comparator function, NaN-sorts-last per spec

**Static methods**:
- `TypedArray.from(source, mapFn?, thisArg?)` — creates from array-like/iterable with optional mapping
- `TypedArray.of(...items)` — creates from arguments

**Iterators**:
- `entries()`, `keys()`, `values()`, `Symbol.iterator` — all with buffer detachment checks per iteration step

**Properties**:
- `buffer`, `byteLength`, `byteOffset`, `length` (instance)
- `BYTES_PER_ELEMENT` (instance and constructor)
- `Symbol.toStringTag` (returns type name)

**Buffer detachment validation**:
- All 9 iteration methods (forEach, map, filter, reduce, reduceRight, every, some, find, findIndex) call `validate_typedarray_buffer()` at entry
- Iterator `next()` re-validates detachment per spec

### DataView Implementation (builtins_dataview.mbt, ~910 lines)

- **Constructor**: `new DataView(buffer, byteOffset?, byteLength?)` with full validation (requires ArrayBuffer, rejects detached, validates offset/length bounds)
- **8 getter methods**: `getInt8`, `getUint8`, `getInt16`, `getUint16`, `getInt32`, `getUint32`, `getFloat32`, `getFloat64` — all with byte offset bounds checking and optional littleEndian parameter
- **8 setter methods**: `setInt8`, `setUint8`, `setInt16`, `setUint16`, `setInt32`, `setUint32`, `setFloat32`, `setFloat64` — matching getter signatures
- **Receiver brand check**: `validate_dataview_access()` verifies `this.class_name == "DataView"` to prevent TypedArray objects from calling DataView methods
- **Properties**: `buffer`, `byteLength`, `byteOffset`, `Symbol.toStringTag`

### Interpreter Integration

- **`Object.prototype.toString`**: New `get_tostringtag_value(data)` function walks prototype chain, checks `Symbol.toStringTag` in symbol descriptors, evaluates getter descriptors. Returns correct `[object Uint8Array]` etc.
- **Indexed property access**: 3 sites in `interpreter.mbt` handle TypedArray indexed get/set with canonical numeric index string validation per spec
- **`"-0"` fix**: Removed `"-0"` short-circuit from all 3 property access sites. Per spec, `ToString(ToNumber("-0"))` yields `"0"`, so `"-0"` is NOT a canonical numeric index string and falls through to ordinary property access
- **`for-in` enumeration**: `collect_for_in_keys` enumerates numeric indices `"0"` through `"length-1"`, skips internal `[[...]]` slots

### Float32 Implementation Details

- **Read**: Reconstructs IEEE 754 bits using `Int64` arithmetic to avoid `Int32` overflow for high byte >= 128. Extracts sign, exponent, mantissa, handles denormals, infinity, and NaN
- **Write**: Encodes double to 4-byte IEEE 754 single-precision format via sign/exponent/mantissa extraction, normalization loop, denormal encoding, and infinity/NaN special cases

### PR Review Fixes (PR #34)

6 commits addressing 19 review comments from coderabbitai[bot] and chatgpt-codex-connector[bot]:

**Commit 1** (`17b7aff`, 7 issues): Sort comparator support + NaN handling, TypedArray.from mapFn argument, DataView receiver brand check, canonical numeric index validation improvement

**Commit 2** (`091fc75`): Enabled test262 tests — removed ArrayBuffer, DataView, TypedArray, Uint8Array from skip lists. Fixed `$262.detachArrayBuffer()` implementation

**Commit 3** (`922422d`, 4 issues): Int32 overflow fix for Float32Array reads (use Int64 arithmetic), denormalized float32 encoding off-by-one fix, added missing forEach/map/filter/reduce/reduceRight to prototype, fallback `buf_id = 0` → `-1` sentinel. Also eliminated all deprecated syntax warnings

**Commit 4** (`7738a52`, 3 issues): Iterator detachment checks per next() call, test snapshot regeneration, `get_tostringtag_value` non-string short-circuit and getter type support

**Commit 5** (`fa76e81`, 2 issues): Buffer detachment validation in all 9 iteration methods (forEach, map, filter, reduce, reduceRight, every, some, find, findIndex), `"-0"` canonical numeric index fix across 3 sites

### Test262 Results

Pending full re-run (test262 directory not available in current environment). ~2,400 tests previously skipped for ArrayBuffer/DataView/TypedArray/Uint8Array features are now enabled for execution.

Previous baseline (pre-Phase 16):
| Category | Pass | Fail | Skip | Rate |
|----------|------|------|------|------|
| built-ins/ArrayBuffer | 10 | 51 | 135 | 16.4% |
| built-ins/DataView | 7 | 304 | 250 | 2.3% |
| built-ins/TypedArray | 0 | 9 | 1,429 | 0.0% |
| built-ins/TypedArrayConstructors | 0 | 0 | 736 | N/A |
| built-ins/Uint8Array | 0 | 0 | 68 | N/A |

### Files Changed

- `interpreter/builtins_arraybuffer.mbt` (~400 lines, new file) — ArrayBuffer constructor, prototype methods, detachment tracking, buffer validation helper
- `interpreter/builtins_typedarray.mbt` (~2,414 lines, new file) — 9 TypedArray types, constructors, 25 prototype methods, static methods, iterators
- `interpreter/builtins_dataview.mbt` (~910 lines, new file) — DataView constructor, 16 getter/setter methods, brand check
- `interpreter/interpreter.mbt` (+109 lines) — TypedArray indexed access (get/set), canonical numeric index, for-in enumeration, `-0` fix
- `interpreter/value.mbt` (+54 lines) — `get_tostringtag_value()` for Symbol.toStringTag support
- `interpreter/builtins.mbt` (+45/-7 lines) — Registration calls, `$262.detachArrayBuffer` implementation
- `interpreter/builtins_object.mbt` (+7/-1 lines) — toString Symbol.toStringTag integration
- `interpreter/interpreter_test.mbt` (+1,202/-1 lines) — 79 new tests
- `test262-runner.py` (+6/-8 lines) — Removed TypedArray features from skip list
- `test262-analyze.py` — Removed TypedArray features from skip list (updated in docs commit)

**Unit tests**: 878 total (+79), 878 passed, 0 failed
