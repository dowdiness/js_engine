## Current State

**Test262 Pass Rate: 26.2%** (6,351 passed / 17,880 failed; 32 timeouts; 3 runner errors) — full run on 2026-02-05 (`24,231` executed / `49,647` discovered, `25,381` skipped)

The MoonBit JS engine supports basic language features (variables, arithmetic, functions, closures, control flow, try/catch, new, this, switch, for-in, bitwise ops, objects, arrays), plus template literals, arrow functions, prototype chain lookup, Function.call/apply/bind, and built-in methods for Array, String, Object, and Math. Phase 3 added: arguments object, hoisting, strict mode, default/rest parameters, destructuring, spread, for-of, property descriptors, Object.freeze/seal, RegExp, JSON, Number built-ins, Error hierarchy polish, String.fromCharCode, and array HOFs. Phase 3.5 added: optional chaining (`?.`), nullish coalescing (`??`), exponentiation (`**`), computed property names, getters/setters, TDZ for let/const, global `this`/`globalThis`, and ES spec compliance fixes. Phase 3.6 added: comma-separated variable declarations, sort comparator exception handling, built-in spec improvements, logical assignment operators (`&&=`, `||=`, `??=`), numeric separator literals, number formatting fixes, ES6 classes (`class`, `extends`, `super`, static methods), and spec compliance fixes for URI encoding, prototype property handling, and class method enumerability. Phase 4 added: Symbol primitive type, Symbol.for/keyFor, well-known symbols, symbol-keyed properties, iteration protocols (Symbol.iterator, Array/String iterators, for-of and spread using iterator protocol), ES6 Map/Set collections, Promise with microtask queue (Promise.all/race/allSettled/any, .then/.catch/.finally), Promise.resolve thenable assimilation fixes, queueMicrotask zero-argument callback invocation, and WHATWG timer APIs (setTimeout/clearTimeout/setInterval/clearInterval with event loop). Phase 5 added: skip list cleanup (removed 18 implemented features), async test harness with $DONE pattern support, object spread in object literals (`{...obj}`), and `new.target` meta-property. Phases 1-5 complete, Phase 6 next.

### Test262 Category Highlights (Phase 5 — Object Spread, new.target, Async Harness)

| Category | Pass Rate | Notes |
|----------|-----------|-------|
| language/import | 100% (6/6) | Module syntax recognized |
| language/keywords | 100% (25/25) | All keywords supported |
| language/punctuators | 100% (11/11) | Complete |
| language/block-scope | 96.8% (91/94) | TDZ working, near-complete |
| language/future-reserved-words | 87.3% (48/55) | Good coverage |
| language/asi | 81.4% (83/102) | Automatic semicolon insertion |
| language/reserved-words | 76.9% (20/26) | Reserved word handling |
| language/literals | 68.8% (231/336) | Numeric separators, hex/binary/octal |
| language/identifiers | 59.6% (124/208) | Solid |
| built-ins/parseInt | 59.3% (32/54) | Good coverage |
| built-ins/parseFloat | 58.5% (31/53) | Good coverage |
| language/rest-parameters | 54.5% (6/11) | Basic support |
| language/types | 52.7% (58/110) | Good coverage |
| built-ins/encodeURIComponent | 44.8% (13/29) | URI encoding working |
| language/expressions | 44.1% (1975/4478) | Significant improvement |
| built-ins/encodeURI | 43.3% (13/30) | URI encoding working |
| built-ins/Math | 38.2% (109/285) | Good coverage |
| built-ins/global | 34.5% (10/29) | GlobalThis working |
| built-ins/Number | 34.1% (109/320) | toPrecision, toExponential added |
| language/function-code | 33.6% (73/217) | Functions working |
| built-ins/Infinity | 33.3% (2/6) | Basic support |
| built-ins/NaN | 33.3% (2/6) | Basic support |
| built-ins/NativeErrors | 30.0% (24/80) | Error hierarchy |
| language/statements | 29.7% (978/3293) | Control flow + classes working |
| built-ins/StringIteratorPrototype | 28.6% (2/7) | String iterator with surrogate pairs |
| language/arguments-object | 25.4% (32/126) | Arguments working (improved) |
| built-ins/Boolean | 25.5% (12/47) | toString/valueOf added |
| built-ins/Set | 23.0% (41/178) | ES6 Set collections |
| built-ins/Object | 22.9% (756/3299) | Core methods working (improved) |
| built-ins/String | 22.0% (255/1158) | split limit added |
| built-ins/JSON | 21.2% (24/113) | parse/stringify working |
| built-ins/Map | 19.4% (34/175) | ES6 Map collections |
| built-ins/Array | 18.8% (541/2883) | Core methods working |
| built-ins/decodeURI | 17.0% (9/53) | URI decoding with reserved chars |
| built-ins/decodeURIComponent | 16.7% (9/54) | Full URI component decoding |
| built-ins/Symbol | 16.7% (12/72) | Core Symbol support working |
| built-ins/Function | 10.3% (44/429) | Constructor and prototype working |
| built-ins/RegExp | 10.3% (85/827) | Basic regex support |
| built-ins/ArrayIteratorPrototype | 5.9% (1/17) | Array iterator protocol |
| **built-ins/Promise** | **2.5% (15/603)** | Promise with async harness — more tests now running |

### Root Cause of Current Failures

**Template literals and arrow functions are now fully supported** (Phase 2). The assert.js harness parses and executes correctly.

The current 26.2% pass rate reflects Phase 5 completions (object spread, new.target, async harness):
- **built-ins/* category: ~10-47% pass rate** — Array, String, Object, Number, URI methods now pass many tests
- **ES6 Classes now supported** — `class`, `extends`, `super`, static methods, non-enumerable methods
- **Symbols now supported** — `Symbol()`, `Symbol.for()`, `Symbol.keyFor()`, well-known symbols, symbol-keyed properties
- **Iteration Protocols now supported** — `Symbol.iterator`, Array/String iterators, `for-of` and spread using iterator protocol
- **Map/Set now supported** — ES6 collections with basic functionality (Map 19.4%, Set 23.0% pass rates)
- **Promises now supported** — `Promise` constructor, `.then/.catch/.finally`, `Promise.all/race/allSettled/any`, thenable assimilation per ECMAScript spec, microtask queue (2.5% pass rate with async harness)
- **Async test harness ($DONE pattern)** — Test262 async tests now run via print markers (`Test262:AsyncTestComplete` / `Test262:AsyncTestFailure`)
- **Object spread in object literals** — `{...obj}` now spreads enumerable own properties
- **new.target meta-property** — Returns constructor or `undefined` for regular calls, inherits lexically in arrow functions
- **WHATWG Timer APIs now supported** — `setTimeout`, `clearTimeout`, `setInterval`, `clearInterval` with event loop and microtask checkpoints
- Language syntax coverage is strong (keywords 100%, punctuators 100%, block-scope 97%, expressions 44%)
- Remaining failures are due to: generator/async features, Promise spec edge cases, and edge cases in built-in methods

**Original harness blockers** (`this`, `throw`, `new`, `try/catch`, `switch/case`, `String()`) — **all resolved in Phase 1**.
**Template literal harness blocker** — **resolved in Phase 2**.
**Comma-separated declarations blocker** — **resolved in Phase 3.6** (enabled 17%+ of tests to run).
**ES6 Classes** — **resolved in Phase 3.6** (unlocked class-related tests).
**Symbols** — **resolved in Phase 4** (12 tests passing, 60 failing due to spec edge cases).
**Iteration Protocols** — **resolved in Phase 4** (Array/String iterators, for-of and spread using iterator protocol).
**Map/Set Collections** — **resolved in Phase 4** (basic functionality working, many spec edge cases remain).
**Promises** — **resolved in Phase 4** (15 tests passing with async harness, 588 failing due to spec edge cases).
**Timer APIs** — **resolved in Phase 4** (setTimeout/setInterval/clearTimeout/clearInterval with event loop).
**Skip list cleanup** — **resolved in Phase 5A** (removed 18 implemented features, unlocked 1,200+ tests).
**Async test harness** — **resolved in Phase 5B** ($DONE pattern support via print markers).
**Object spread** — **resolved in Phase 5C** (`{...obj}` in object literals).
**new.target** — **resolved in Phase 5D** (meta-property in constructors and functions).

---

## Phase 1: Core Language Gaps → 8.18% pass rate ✅ IMPLEMENTED

**Goal**: Get the test262 harness executing, then pass basic language tests.

**Status**: All tasks (1A–1G) implemented. 195 tests passing (`moon test --target js`).

### 1A. Lexer/Token Extensions ✅
- [x] Add keywords: `throw`, `try`, `catch`, `finally`, `new`, `this`, `switch`, `case`, `default`, `void`, `delete`, `do`, `in`, `instanceof`
- [x] Add operators: `++`, `--`, `+=`, `-=`, `*=`, `/=`, `%=`
- [x] Add bitwise operators: `&`, `|`, `^`, `~`, `<<`, `>>`, `>>>`
- [x] Add compound bitwise assignment: `&=`, `|=`, `^=`, `<<=`, `>>=`, `>>>=`

### 1B. AST Node Extensions ✅
- [x] Statements: `ThrowStmt`, `TryCatchStmt`, `SwitchStmt`, `DoWhileStmt`, `ForInStmt`, `LabeledStmt`
- [x] Expressions: `ObjectLit`, `ArrayLit`, `ComputedMember` (`obj[key]`), `MemberAssign` (`obj.prop = val`), `ComputedAssign` (`obj[key] = val`), `NewExpr`, `ThisExpr`, `UpdateExpr` (`++`/`--`), `CompoundAssign` (`+=` etc.), `Comma`
- [x] Binary ops: `BitAnd`, `BitOr`, `BitXor`, `LShift`, `RShift`, `URShift`, `In`, `Instanceof`

### 1C. Value System Overhaul ✅
- [x] Add `Object(ObjectData)` variant with `properties`, `prototype`, `callable`, `class_name`
- [x] Add `Array(ArrayData)` variant with `elements` array
- [x] **Unify functions as objects** — the harness does `assert.sameValue = function() {}` (property assignment on a function value)
- [x] Add string comparison support (currently only numbers can use `<`/`>`)

### 1D. Exception System ✅
- [x] Add `JsException(Value)` error type using MoonBit's `suberror` mechanism
- [x] Implement `throw` statement evaluation
- [x] Implement `try/catch/finally` — intercept `JsException`, bind catch variable

### 1E. Parser Extensions ✅
- [x] Object literals: `{ key: value, ... }` (disambiguate from block statements)
- [x] Array literals: `[expr, expr, ...]`
- [x] `this` keyword, `new` expression
- [x] Computed member access: `obj[key]`
- [x] Prefix/postfix `++`/`--`
- [x] Compound assignment: `+=`, `-=`, etc.
- [x] Member/computed property assignment: `obj.prop = val`, `obj[key] = val`
- [x] `switch/case/default`, `do-while`, `for-in`
- [x] `throw` statement, `try/catch/finally`
- [x] Bitwise and shift operator precedence levels
- [x] `in`, `instanceof` at relational precedence
- [x] `void`, `delete` as unary prefix operators
- [x] Comma operator (lowest precedence)
- [x] Labeled statements
- [x] Full JS precedence chain: comma → assignment → ternary → or → and → bitwise-or → bitwise-xor → bitwise-and → equality → relational → shift → additive → multiplicative → unary → postfix → call → primary

### 1F. Interpreter Extensions ✅
- [x] `throw` — evaluate expression and raise `JsException(value)`
- [x] `try/catch/finally` — wrap execution, intercept `JsException`
- [x] `new` — create object, set prototype, bind `this`, call constructor
- [x] `this` — lookup `"this"` in environment
- [x] Object/array literal evaluation
- [x] Property access/assignment for any object (not just `console`)
- [x] `switch/case` with strict equality matching and fall-through
- [x] `do-while` loop
- [x] `for-in` — iterate over enumerable property names
- [x] `++`/`--` — get value, ToNumber, add/subtract 1, assign back
- [x] Compound assignment — `x += y` semantics
- [x] Bitwise operators — convert to 32-bit integer, operate, convert back
- [x] String comparison — lexicographic ordering for `<`, `>`, `<=`, `>=`
- [x] `void` — evaluate operand, return `undefined`
- [x] `delete` — remove property from object
- [x] `in` — check property existence
- [x] `instanceof` — walk prototype chain
- [x] Comma — evaluate both sides, return right value
- [x] Fix `typeof` for undeclared variables (return `"undefined"` instead of throwing)
- [x] Type coercion fallbacks for arithmetic/comparison operators via `to_number()`
- [x] `this` binding for method calls (detect `Member`/`ComputedMember` callees in `eval_call`)

### 1G. Built-in Globals ✅
- [x] `NaN`, `Infinity`, `undefined` as global constants
- [x] `isNaN()`, `isFinite()`, `parseInt()`, `parseFloat()`
- [x] Error constructors: `Error`, `TypeError`, `ReferenceError`, `SyntaxError`, `RangeError`, `URIError`, `EvalError`
- [x] `String()`, `Number()`, `Boolean()` conversion functions

### Phase 1 Known Issues ✅ ALL FIXED

All 6 issues addressed in commit `3439764`:

1. ~~**`to_int32` does not match ECMAScript spec**~~ ✅ Rewritten with proper ECMAScript ToInt32: truncate toward zero, modulo 2^32, signed range mapping
2. ~~**Error constructors don't set prototype on instances**~~ ✅ Shared `proto_obj` between constructor's `"prototype"` property and NativeCallable closure
3. ~~**`for-in` only enumerates own properties**~~ ✅ Added `collect_for_in_keys` helper walking prototype chain with deduplication
4. ~~**`LabeledStmt` label is discarded**~~ ✅ Added `label~` parameter to `exec_stmt`, `BreakSignal(String?)` / `ContinueSignal(String?)` with label matching in all loop constructs
5. ~~**`parseFloat` uses O(n^2) progressive prefix parsing**~~ ✅ Single-pass O(n) scanner
6. ~~**`eval_update` and `eval_compound_assign` re-evaluate object expressions**~~ ✅ Rewritten to evaluate obj/key once, read via get_property, write back

### Phase 1 Implementation Notes

**Files changed**: 14 files, +2,895 / -82 lines

| File | Changes |
|------|---------|
| `token/token.mbt` | 14 keywords, 23 operators added |
| `lexer/lexer.mbt` | Longest-match-first operator scanning (4-char → 3-char → 2-char → 1-char) |
| `ast/ast.mbt` | 6 new statements, 10 new expressions, `UpdateOp`, `CompoundOp`, `Property`, `SwitchCase` |
| `parser/expr.mbt` | Full JS precedence chain with 4 new levels (bitwise-or/xor/and, shift) |
| `parser/stmt.mbt` | for-in/for-loop disambiguation via `peek_kind_at`, labeled statement detection |
| `parser/parser.mbt` | Added `peek_kind_at` lookahead helper |
| `interpreter/value.mbt` | `Object(ObjectData)`, `Array(ArrayData)`, `Callable`, `JsException`, `to_number`, `to_int32` |
| `interpreter/environment.mbt` | `def_builtin` (non-raising), `has` (scope chain lookup) |
| `interpreter/interpreter.mbt` | Rewritten: 1053 lines covering all Phase 1 features |
| `interpreter/builtins.mbt` | Global constants, parsing functions, type conversions, 7 error constructors |

**MoonBit-specific workarounds discovered**:
- `test`, `method`, `constructor` are reserved keywords — cannot be used as identifiers
- `T?` not allowed in toplevel struct declarations — must use `Option[T]`
- `type!` syntax deprecated — use `suberror` instead
- `!` error handling syntax deprecated — use `raise Error` in function signatures instead of `!Error`
- `.lsl()`, `.asr()` methods deprecated — use `<<`, `>>` infix operators
- Hex literal method calls fail to parse (e.g., `0x7FFFFFFF.asr()`) — assign to variable first
- Multiline strings (`#|`) in function call arguments trigger deprecation warning — use `let` binding

### Phase 1 Expected vs Actual Impact

| Category | Est. passes | Actual | Notes |
|----------|-------------|--------|-------|
| language/expressions | ~1,800 | 769 | Many tests depend on built-in methods |
| language/statements | ~700 | 604 | Good coverage |
| language/types + literals | ~350 | — | Partial coverage |
| language/identifiers, keywords | ~400 | 140+ | keywords 100%, identifiers 56% |
| built-ins/* | ~230 | 0 | Spec compliance gaps |
| **Phase 1 total** | **~5,000 (25-26%)** | **~1,700 (8.18%)** | Built-in 0% dragged overall down |

**Lesson learned**: Original estimates assumed passing language tests would translate to high pass rates. In practice, ~70% of test262 tests depend on built-in object methods, which have 0% pass rate due to spec compliance issues.

---

## Phase 2: Unblock Test262 Harness → 8.5% pass rate ✅ IMPLEMENTED

**Goal**: Template literals + arrow functions + prototype chain + core built-ins → unblock all 17,941 failing tests.

**Status**: All tasks (2A–2I) implemented. 282 unit tests passing (`moon test --target wasm`).

### 2A. Template Literals ✅

**Lexer** (`lexer/lexer.mbt`):
- [x] Add `template_depth_stack: Array[Int]` local variable in `tokenize()`
- [x] Add `scan_template_string()` helper: scan until `${` or closing backtick, handle escape sequences
- [x] Backtick recognition: emit `NoSubTemplate` or `TemplateHead` + push brace depth
- [x] `{` tracking: increment top of stack when inside template expression
- [x] `}` tracking: when brace depth reaches 0, resume template scanning → emit `TemplateMiddle` or `TemplateTail`

**Tokens** (`token/token.mbt`):
- [x] `NoSubTemplate(String)` — `` `hello world` ``
- [x] `TemplateHead(String)` — `` `hello ${ ``
- [x] `TemplateMiddle(String)` — `` } world ${ ``
- [x] `TemplateTail(String)` — `` } end` ``

**AST** (`ast/ast.mbt`):
- [x] `TemplateLit(Array[String], Array[Expr], @token.Loc)` — strings interleaved with expressions

**Parser** (`parser/expr.mbt`):
- [x] `NoSubTemplate(s)` → `StringLit(s, loc)`
- [x] `TemplateHead(s)` → parse expr loop until `TemplateTail` → `TemplateLit`

**Interpreter** (`interpreter/interpreter.mbt`):
- [x] Evaluate each expr, `to_string()`, concatenate with string parts

### 2B. Arrow Functions ✅

**Lexer** (`lexer/lexer.mbt`):
- [x] `Arrow` token (`=>`) — added before existing `==` check

**AST** (`ast/ast.mbt`):
- [x] `ArrowFunc(Array[String], Array[Stmt], @token.Loc)` — params + body (concise body wrapped in ReturnStmt)

**Parser** (`parser/expr.mbt`):
- [x] Single-param: `ident =>` detected by peek-ahead
- [x] Zero-param: `() =>` in `parse_primary()` LParen arm
- [x] Multi-param: parse expression, check for Arrow, extract params from Grouping/Comma
- [x] Body: `{` → block body; otherwise → assignment expression (implicit return)

**Interpreter** (`interpreter/interpreter.mbt`, `value.mbt`):
- [x] `ArrowFunc(FuncData)` variant in `Callable` enum — lexical `this` (no rebinding on call)
- [x] `eval_new` rejection: arrow functions cannot be constructors → TypeError

### 2C. Prototype Chain Property Lookup ✅

**File**: `interpreter/interpreter.mbt`
- [x] `get_property()`: when own property not found, walk `data.prototype` chain until found or Null
- [x] `get_computed_property()`: same prototype chain walking for Object arm
- [x] Unlocks: inherited method calls, `hasOwnProperty`, error `.name`/`.message` access

### 2D. Function.call / Function.apply / Function.bind ✅

**File**: `interpreter/interpreter.mbt`
- [x] Fast-path in `eval_call()` Member and ComputedMember arms for direct invocation
- [x] `FuncCallMethod(Value)` / `FuncApplyMethod(Value)` callable variants for property reads (`var c = f.call`)
- [x] `MethodCallable(String, (Value, Array[Value]) -> Value)` for this-aware built-in methods (e.g., `hasOwnProperty`)
- [x] `BoundFunc(Value, Value, Array[Value])` callable variant for `.bind()` with proper error propagation
- [x] Own property check: callable objects that override `.call`/`.apply`/`.bind` use their own properties

### 2E. Array Built-in Methods ✅

**New file**: `interpreter/builtins_array.mbt`
- [x] `push`, `pop`, `shift`, `unshift`, `splice`
- [x] `slice`, `concat`, `join`, `indexOf`, `lastIndexOf`, `includes` (SameValueZero for NaN)
- [x] `reverse`, `sort`, `fill`, `toString`
- [ ] `map`, `filter`, `reduce`, `forEach`, `find`, `findIndex`, `every`, `some` (deferred to Phase 3)
- [x] `Array.isArray()` static method — registered in `builtins_object.mbt`

### 2F. String Built-in Methods ✅

**New file**: `interpreter/builtins_string.mbt`
- [x] `charAt`, `charCodeAt`, `indexOf`, `lastIndexOf`, `includes`
- [x] `slice`, `substring`, `toLowerCase`, `toUpperCase`
- [x] `trim`, `trimStart`, `trimEnd`
- [x] `split`, `replace`, `startsWith`, `endsWith`, `repeat`, `padStart`, `padEnd`
- [x] `toString`, `valueOf`
- [ ] `String.fromCharCode()` static method (deferred to Phase 3)

### 2G. Object Built-in Methods ✅

**New file**: `interpreter/builtins_object.mbt`
- [x] Static: `Object.keys()`, `Object.values()`, `Object.entries()`, `Object.create()`, `Object.assign()`, `Object.getPrototypeOf()`, `Object.getOwnPropertyNames()`, `Object.defineProperty()`
- [x] `hasOwnProperty()` via `MethodCallable` with dynamic `this` receiver (supports method borrowing via `.call`)
- [x] `toString()` fallback for objects

### 2H. Math Object ✅

**File**: `interpreter/builtins.mbt`
- [x] Constants: `PI`, `E`, `LN2`, `LN10`, `LOG2E`, `LOG10E`, `SQRT2`, `SQRT1_2`
- [x] Methods: `abs`, `floor`, `ceil`, `round`, `trunc`, `sqrt`, `pow`, `min`, `max`, `random` (xorshift32 PRNG), `sign`, `log`, `log2`, `log10`

### 2I. Test262 Runner Update ✅

**File**: `test262-runner.py`
- [x] Remove `"template"` and `"arrow-function"` from `SKIP_FEATURES` (completed — features removed, harness now parses correctly)

### Phase 2 Implementation Notes

**Files changed**: 11 files, 3 new files created

| File | Changes |
|------|---------|
| `token/token.mbt` | 5 new token kinds (4 template + Arrow) |
| `lexer/lexer.mbt` | Template state machine with brace-depth stack, `=>` operator |
| `ast/ast.mbt` | `TemplateLit`, `ArrowFunc` expression variants |
| `parser/expr.mbt` | Template literal + arrow function parsing, `extract_arrow_params`, `parse_arrow_body` |
| `interpreter/interpreter.mbt` | Template/arrow eval, prototype chain in get_property/get_computed_property, call/apply/bind dispatch (Member + ComputedMember), FuncCallMethod/FuncApplyMethod/MethodCallable in call_value |
| `interpreter/value.mbt` | `ArrowFunc`, `BoundFunc`, `FuncCallMethod`, `FuncApplyMethod`, `MethodCallable` callable variants |
| `interpreter/builtins.mbt` | Math object with xorshift32 PRNG, setup_object_builtins/setup_math_builtins calls |
| `interpreter/builtins_array.mbt` | Array prototype methods (new file), `strict_equal_val`, `same_value_zero` |
| `interpreter/builtins_string.mbt` | String prototype methods (new file), `string_trim`, `string_trim_end` |
| `interpreter/builtins_object.mbt` | Object/Array constructors + static methods (new file) |
| `interpreter/moon.pkg.json` | Added `moonbitlang/core/math` import |

**Review fixes applied**:
- Clamp `startsWith`/`endsWith` position arguments to valid ranges
- Own property check before call/apply/bind fast-path on callable objects
- SameValueZero semantics for `Array.includes` (NaN === NaN)
- Object fallback methods (hasOwnProperty/toString) in both get_property and get_computed_property
- call/apply/bind dispatch in ComputedMember path (bracket notation)
- `Math.random` replaced constant stub with xorshift32 PRNG
- `FuncCallMethod`/`FuncApplyMethod` make `.call`/`.apply`/`.bind` retrievable as property values
- `MethodCallable` gives `hasOwnProperty` dynamic `this` receiver for method borrowing
- `BoundFunc` callable variant for proper error propagation through bound functions
- `Math.round` preserves NaN, Infinity, ±0 per ECMAScript spec
- `indexOf`/`lastIndexOf` clamp empty needle position correctly (empty string at position > length returns length)
- `hasOwnProperty()` with missing argument defaults to key `"undefined"` (JS ToPropertyKey semantics)
- `Object.prototype.valueOf` returns `this` via `MethodCallable`

---

## Phase 3: Advanced Language Features + Full Built-ins → 8.7% pass rate ✅ IMPLEMENTED

**Goal**: Arguments, hoisting, strict mode, destructuring, spread/rest, for-of, property descriptors, RegExp, JSON, Number built-ins, array HOFs.

**Status**: All tasks (3A–3G) implemented. 444 unit tests passing (`moon test --target wasm`).

### 3A. Foundation — No Architecture Changes ✅
- [x] **`arguments` object** — array-like with `.length`, indexed access, `.callee` (sloppy mode only)
- [x] **Hoisting** — `hoist_declarations` pre-pass for `var` and function declarations + var destructuring
- [x] **`String.fromCharCode()`** — static method on String constructor
- [x] **Number built-ins** — `Number.isNaN()`, `.isFinite()`, `.isInteger()`, `.parseInt()`, `.parseFloat()`, `.MAX_SAFE_INTEGER`, `.MIN_SAFE_INTEGER`, `.EPSILON`. Instance: `.toFixed()`, `.toString(radix)`, `.valueOf()`
- [x] **Error hierarchy polish** — `.name`, `.message`, `.stack` on all Error instances, `Error.prototype.toString()`
- [x] **JSON** — `JSON.parse()` (recursive descent parser) and `JSON.stringify()` (recursive serializer with cycle detection)

### 3B. Callback Architecture + Array HOFs ✅
- [x] **`InterpreterCallable` variant** added to `Callable` enum — receives interpreter instance + `this` value
- [x] **Array HOFs**: `forEach`, `map`, `filter`, `reduce`, `reduceRight`, `find`, `findIndex`, `every`, `some`, `flat`, `flatMap`

### 3C. AST Extensions + New Syntax ✅
- [x] **Tokens**: `Of` keyword, `DotDotDot` (`...`) operator
- [x] **AST nodes**: `ForOfStmt`, `Param` struct, `Pattern` enum, `SpreadExpr`, `RestElement`
- [x] **Default parameters** — `function f(a = 1) {}`
- [x] **Rest parameters** — `function f(...args) {}`
- [x] **`for-of` loops** — iterate array elements or string characters
- [x] **Spread in calls/arrays** — `f(...arr)`, `[...a, ...b]`

### 3D. Destructuring ✅
- [x] **Array destructuring** — `let [a, b, ...rest] = arr`, holes, nested
- [x] **Object destructuring** — `let {x, y: alias, ...rest} = obj`, defaults
- [x] **Parameter destructuring** — destructuring in function params
- [x] **Assignment destructuring** — `[a, b] = [1, 2]` without declaration

### 3E. Property Descriptors + Object.freeze/seal ✅
- [x] **Property descriptors** via `ObjectData.descriptors` map with `writable`/`enumerable`/`configurable` flags
- [x] **`Object.defineProperty()`** — full implementation with descriptor validation
- [x] **`Object.getOwnPropertyDescriptor()`** — returns descriptor as plain object
- [x] **`Object.defineProperties()`** — batch property definition
- [x] **`Object.freeze()`** / **`Object.seal()`** / **`Object.preventExtensions()`**
- [x] **`Object.isFrozen()`** / **`Object.isSealed()`** / **`Object.isExtensible()`**

### 3F. Strict Mode ✅
- [x] **Parse `"use strict"` directive** — detected as first statement in function/global scope
- [x] **Track strict mode** — `strict: Bool` field on `Interpreter`, saved/restored per function call
- [x] **Enforce strict semantics**: `this` is `undefined` for unbound calls, assignment to undeclared throws `ReferenceError`, `arguments.callee` omitted in strict mode
- [x] **Exception-safe restore** — strict flag restored via try/catch on function call errors
- [x] **Constructor strict mode** — `eval_new` respects `"use strict"` in constructor bodies

### 3G. RegExp (basic) ✅

**New file**: `interpreter/builtins_regex.mbt`
- [x] **Custom regex engine** — parser (pattern → `RegexNode` AST), backtracking matcher with `match_sequence`
- [x] **Supported syntax**: `.`, `*`, `+`, `?`, `{n}`, `{n,m}`, `[...]`, `[^...]`, `^`, `$`, `|`, `()` groups, `\d`, `\w`, `\s`, `\b`, `\D`, `\W`, `\S`
- [x] **Flags**: `g` (global), `i` (case-insensitive), `m` (multiline)
- [x] **Context-aware lexer** — tracks last token to disambiguate `/` vs regex; paren stack for control-flow `)` detection
- [x] **RegExp object**: `.test()`, `.exec()`, `.source`, `.flags`, `.lastIndex`, `.global`, `.ignoreCase`
- [x] **String regex methods**: `.match()`, `.search()`, `.replace()` with RegExp support
- [x] **`RegExp` constructor** — `new RegExp(pattern, flags)`

### Phase 3 Bug Fixes Applied
- [P1] Strict mode leaks after thrown errors — try/catch restore in `call_value`
- [P2] Var destructuring declarations not hoisted — `hoist_pattern` helper + `bind_pattern` assign-if-exists
- [P2] Constructor calls ignore strict mode — strict detection/restore in `eval_new`
- [P2] Regex after RParen in control-flow contexts — paren stack tracking in lexer
- Object.defineProperty defaults corrected (false, not true, when no existing descriptor)
- Case-insensitive regex with `\D`/`\W`/`\S` — per-character icase instead of pattern lowercasing
- Arrow function hoisting — `hoist_declarations` call added to ArrowFunc/ArrowFuncExt

### Phase 3 Implementation Notes

**Files changed**: 10 files, 1 new file created

| File | Changes |
|------|---------|
| `token/token.mbt` | +`Of`, `DotDotDot`, `Regex(String, String)` tokens |
| `lexer/lexer.mbt` | `...` scanning, regex literal scanning with context tracking, paren stack for control-flow `)` |
| `ast/ast.mbt` | `Param`, `ParamExt`, `Pattern`, `PropPat` structs; `ForOfStmt`, `SpreadExpr`, `DestructureDecl`, `DestructureAssign`, `RegexLit` nodes |
| `parser/expr.mbt` | Default/rest params, spread, destructuring patterns, `expr_to_pattern` helper, regex literals |
| `parser/stmt.mbt` | for-of parsing, destructuring in var decls |
| `interpreter/value.mbt` | `InterpreterCallable` callable variant |
| `interpreter/environment.mbt` | Strict mode: assignment to undeclared throws `ReferenceError` |
| `interpreter/interpreter.mbt` | arguments object, hoisting (`hoist_declarations` + `hoist_pattern`), for-of eval, destructuring eval (`bind_pattern`), spread eval, default params eval, strict mode enforcement (save/restore with exception safety), regex eval, constructor strict mode |
| `interpreter/builtins.mbt` | JSON builtins (`JSON.parse`, `JSON.stringify`), Number constructor/prototype, `String.fromCharCode`, `RegExp` constructor |
| `interpreter/builtins_array.mbt` | 11 callback-based array methods using `InterpreterCallable` |
| `interpreter/builtins_string.mbt` | `.match()`, `.search()`, regex-aware `.replace()` |
| `interpreter/builtins_object.mbt` | `defineProperties`, `freeze`/`seal`/`preventExtensions`, `isFrozen`/`isSealed`/`isExtensible`; fixed `defineProperty` defaults |
| `interpreter/builtins_regex.mbt` | **New file** — regex parser, backtracking matcher, RegExp objects, string regex helpers |

---

## Phase 3.5: Test262 Blockers + ES Spec Compliance → 8.77% pass rate ✅ IMPLEMENTED

**Goal**: Fix test262 skip list issues and implement missing ES features blocking significant test counts.

**Status**: All tasks implemented. Language syntax coverage strong; built-in method spec compliance remains the primary blocker for higher pass rates.

### 3.5A. Test262 Skip List Fixes ✅
- [x] **Add 26 missing feature tags** — `optional-chaining`, `nullish-coalescing`, `exponentiation`, `object-spread`, `object-rest`, and other unsupported features added to skip lists
- [x] **Sync analyzer and runner** — `test262-runner.py` and `test262-analyze.py` skip lists unified

### 3.5B. Optional Chaining (`?.`) ✅
- [x] **Tokens**: `QuestionDot` (`?.`)
- [x] **AST nodes**: `OptionalMember`, `OptionalComputedMember`, `OptionalCall`
- [x] **Parser**: `?.prop`, `?.[expr]`, `?.(args)` with chain propagation (`.` and `[]` after `?.` continue the optional chain)
- [x] **Interpreter**: Short-circuit to `undefined` on nullish base; arguments not evaluated when callee is nullish
- [x] **Regex context**: `QuestionDot` added to regex-start token list to prevent `/` misparse

### 3.5C. Nullish Coalescing (`??`) ✅
- [x] **Tokens**: `QuestionQuestion` (`??`)
- [x] **AST**: `NullishCoalesce` binary operator
- [x] **Parser**: Precedence between `||` and `&&`; mixing `??` with `||`/`&&` without parentheses raises SyntaxError
- [x] **Interpreter**: Short-circuit right operand unless left is `null`/`undefined`
- [x] **Regex context**: `QuestionQuestion` added to regex-start token list

### 3.5D. Exponentiation Operator (`**`) ✅
- [x] **Tokens**: `StarStar` (`**`), `StarStarAssign` (`**=`)
- [x] **AST**: `Exp` binary operator, `ExpAssign` compound operator
- [x] **Parser**: Right-associative at correct precedence; unary operators before `**` raise SyntaxError (e.g., `-2 ** 2` is invalid)
- [x] **Interpreter**: `Math.pow()` semantics

### 3.5E. Object Literal Enhancements ✅
- [x] **Computed property names**: `{ [expr]: value }` — dynamic key expressions
- [x] **Shorthand properties**: `{ x }` → `{ x: x }` — identifier keys only
- [x] **Method shorthand**: `{ foo() {} }` → `{ foo: function foo() {} }`
- [x] **Getters/Setters**: `{ get prop() {}, set prop(v) {} }` with arity validation (getter=0, setter=1)

### 3.5F. TDZ (Temporal Dead Zone) for `let`/`const` ✅
- [x] **Environment tracking**: `initialized: Bool` field on bindings
- [x] **`def_tdz()` method**: Create uninitialized binding at block start
- [x] **`initialize()` method**: Mark binding as initialized at declaration
- [x] **Access check**: Reading uninitialized binding throws `ReferenceError: Cannot access before initialization`
- [x] **`var`/`var` redeclaration**: Allowed per ES spec (updates existing binding)

### 3.5G. Global Object Enhancements ✅
- [x] **`this` in global context**: Returns global object (not `undefined`)
- [x] **`globalThis`**: Reference to global object
- [x] **`extensible: true`**: Global object property for spec compliance

### 3.5H. ES Spec Compliance Fixes ✅
- [x] **Abstract Equality (`==`)**: Full spec implementation with type coercion
- [x] **`in` operator**: Walks prototype chain
- [x] **Error types**: `JsException` with proper `ReferenceError`, `TypeError`, `SyntaxError` messages
- [x] **Property key type**: Changed `Property.key` from `String` to `Expr` to support computed keys

### Phase 3.5 Implementation Notes

**Files changed**: 9 files

| File | Changes |
|------|---------|
| `token/token.mbt` | `QuestionQuestion`, `QuestionDot`, `StarStar`, `StarStarAssign` tokens |
| `lexer/lexer.mbt` | `??`, `?.`, `**`, `**=` scanning; regex context updates |
| `ast/ast.mbt` | `NullishCoalesce`, `Exp`, `ExpAssign` ops; `OptionalMember/ComputedMember/Call`; `Property.key` → `Expr`, `computed` flag, `PropKind` |
| `parser/expr.mbt` | Optional chaining with chain propagation, nullish coalescing with mixing validation, exponentiation with unary check, computed properties, getters/setters with arity validation |
| `interpreter/interpreter.mbt` | Optional chain eval, nullish coalescing short-circuit, global `this`, `globalThis` |
| `interpreter/environment.mbt` | TDZ support (`initialized` field, `def_tdz`, `initialize`), var/var redeclaration |
| `interpreter/value.mbt` | Global object with `extensible: true` |
| `test262-runner.py` | Skip list updates |
| `test262-analyze.py` | Skip list sync |

---

## Phase 3.6: Built-in Spec Compliance + ES6 Classes → 27.1% pass rate ✅ COMPLETE

**Goal**: Fix built-in method implementations to match ECMAScript spec. Implement ES6 classes.

**Status**: Major progress achieved. Pass rate improved from 8.77% to 27.1% (+18.33 percentage points). ES6 classes fully implemented.

### 3.6 Completed Items ✅
- [x] **Comma-separated variable declarations** — `var a, b, c;` syntax now parsed correctly via `StmtList` AST node
- [x] **Sort comparator exception handling** — Exceptions in sort comparefn now propagate per ECMAScript spec
- [x] **Math.imul 32-bit masking** — Proper ToInt32 conversion for both arguments
- [x] **String.toWellFormed** — Replaces lone surrogates with U+FFFD
- [x] **String.isWellFormed** — Correctly detects lone surrogates with proper index advancement
- [x] **Array.values()** — Returns array iterator
- [x] **String.codePointAt** — Returns code point at position
- [x] **Object.fromEntries** — Creates object from iterable of key-value pairs (with TypeError for invalid entries)
- [x] **Object.setPrototypeOf** — Documented as stub
- [x] **String.normalize** — Documented as stub (returns input unchanged)
- [x] **Sort comparator sign handling** — Uses sign-based comparison to avoid truncating fractional values
- [x] **Array.prototype.toLocaleString** — Converts array elements to localized strings and joins
- [x] **Object.getOwnPropertySymbols** — Returns empty array (Symbols not implemented)
- [x] **Object.getOwnPropertyDescriptors** — Returns all property descriptors at once
- [x] **Boolean.prototype.toString** — Returns "true" or "false" string representation
- [x] **Boolean.prototype.valueOf** — Returns the boolean primitive value
- [x] **encodeURI / decodeURI** — URI encoding/decoding preserving URL special characters
- [x] **encodeURIComponent / decodeURIComponent** — Full URI component encoding with UTF-8 support
- [x] **Function constructor** — Global Function constructor with prototype
- [x] **Function.prototype.toString** — Returns proper function representation (`function name() { [native code] }`)
- [x] **Function.prototype.call/apply/bind** — Properties with correct length values
- [x] **Function.prototype.constructor** — Back-reference to Function constructor
- [x] **ES6 Classes** — `class`, `extends`, `super()`, `super.prop`, static methods, computed method names
- [x] **Class method enumerability** — Class methods and `prototype.constructor` are non-enumerable per spec
- [x] **Super constructor return values** — If parent constructor returns object, it becomes `this`
- [x] **Prototype property for non-constructables** — Arrow functions, bound functions return `undefined` for `.prototype`
- [x] **Prototype property memoization** — `f.prototype === f.prototype` now returns `true`
- [x] **decodeURI reserved characters** — Preserves `; , / ? : @ & = + $ #` per ECMA-262
- [x] **ClassConstructor callable** — Full pattern matching for length, name, toString, call semantics

**Why pass rate jumped**: The comma-separated variable declaration fix unblocked ~17% of test262 tests that were previously failing at parse time. ES6 classes implementation unlocked additional class-related tests.

### 3.6A. Array Spec Compliance (~2,000 tests)

**Priority methods** (high test coverage):
- [ ] `Array.prototype.map` — return value coercion, sparse array handling
- [ ] `Array.prototype.filter` — predicate return coercion, length caching
- [ ] `Array.prototype.reduce/reduceRight` — initial value handling, empty array TypeError
- [ ] `Array.prototype.forEach` — skip holes in sparse arrays
- [ ] `Array.prototype.find/findIndex` — return undefined vs -1
- [ ] `Array.prototype.every/some` — early termination, return coercion
- [ ] `Array.prototype.indexOf/lastIndexOf` — SameValueZero vs strict equality, NaN handling
- [ ] `Array.prototype.includes` — SameValueZero for NaN
- [ ] `Array.prototype.slice/splice` — negative index handling, length bounds
- [ ] `Array.prototype.sort` — comparefn undefined behavior, stability
- [ ] `Array.from()` — iterable protocol, mapFn, thisArg
- [ ] `Array.of()` — simple constructor
- [ ] `Array.isArray()` — cross-realm detection

### 3.6B. String Spec Compliance (~1,500 tests)

**Priority methods**:
- [x] `String.prototype.split` — limit parameter ✅ (regex separator still TODO)
- [ ] `String.prototype.replace` — replacement patterns ($1, $&, etc.)
- [ ] `String.prototype.match` — global flag behavior, capture groups
- [ ] `String.prototype.slice/substring` — negative index normalization
- [ ] `String.prototype.indexOf/lastIndexOf` — position clamping
- [ ] `String.prototype.trim/trimStart/trimEnd` — Unicode whitespace
- [ ] `String.prototype.padStart/padEnd` — fillString handling
- [ ] `String.prototype.repeat` — range validation
- [ ] `String.prototype.charAt/charCodeAt` — bounds checking
- [ ] `String.prototype.localeCompare` — basic comparison (no Intl)
- [ ] `String.fromCharCode` — multiple arguments
- [ ] `String.prototype.normalize` — NFC/NFD (stub or basic)

### 3.6C. Object Spec Compliance (~1,000 tests)

**Priority methods**:
- [ ] `Object.keys/values/entries` — enumerable own properties only, order
- [ ] `Object.assign` — property order, getter invocation
- [ ] `Object.create` — propertyDescriptor second argument
- [ ] `Object.defineProperty` — descriptor validation, accessor vs data
- [ ] `Object.getOwnPropertyDescriptor` — return format
- [ ] `Object.getOwnPropertyNames` — include non-enumerable
- [ ] `Object.freeze/seal/preventExtensions` — deep vs shallow
- [ ] `Object.isFrozen/isSealed/isExtensible` — proper checks
- [ ] `Object.getPrototypeOf/setPrototypeOf` — null handling
- [ ] `Object.is` — SameValue algorithm (NaN, -0)
- [ ] `Object.fromEntries` — iterable of key-value pairs
- [ ] `Object.hasOwn` — modern hasOwnProperty

### 3.6D. Number Spec Compliance (~500 tests)

**Priority methods**:
- [x] `Number.isNaN/isFinite/isInteger/isSafeInteger` — type checks ✅
- [ ] `Number.parseInt/parseFloat` — edge cases
- [ ] `Number.prototype.toFixed` — range validation, rounding
- [x] `Number.prototype.toPrecision` — significant digits ✅
- [x] `Number.prototype.toExponential` — scientific notation ✅
- [ ] `Number.prototype.toString` — radix parameter validation

### 3.6E. Function Spec Compliance (~300 tests)

**Priority methods**:
- [x] `Function.prototype.call/apply` — thisArg coercion ✅
- [x] `Function.prototype.bind` — partial application, length ✅
- [x] `Function.prototype.toString` — source representation ✅
- [x] `Function.prototype.length` — parameter count ✅
- [x] `Function.prototype.name` — inferred names ✅
- [x] `Function constructor` — creates functions with prototype ✅
- [x] `Function.prototype.constructor` — back-reference ✅

### Phase 3.6 Expected Impact

| Category | Current | Target | Tests Unlocked |
|----------|---------|--------|----------------|
| built-ins/Array | 0% | ~60% | ~1,200 |
| built-ins/String | 0% | ~60% | ~900 |
| built-ins/Object | 0% | ~60% | ~600 |
| built-ins/Number | 0% | ~70% | ~350 |
| built-ins/Function | 0% | ~50% | ~150 |
| **Phase 3.6 total** | **0%** | **~60%** | **~3,200 tests → 25-30% overall** |

---

## Phase 4: Modern ES6+ Features → 26.4% pass rate ✅ COMPLETE

- [x] **Classes** — `class`, `extends`, `constructor`, `super`, static methods, getters/setters ✅ DONE (Phase 3.6)
- [x] **Symbols** — `Symbol()`, `Symbol.for()`, `Symbol.keyFor()`, well-known symbols (`iterator`, `toPrimitive`, `toStringTag`, etc.), `typeof symbol`, symbol-keyed properties ✅ DONE
- [x] **Iteration Protocol** — `Symbol.iterator`, iterator objects with `next()` method, `{value, done}` result format, iterable spread operator ✅ DONE
- [x] **Map/Set** — `new Map()`, `new Set()`, `.get/.set/.has/.delete/.size/.clear`, SameValueZero equality, insertion order, iterator support ✅ DONE (Map 19.4%, Set 23.0%)
- [x] **Promises** — `Promise` constructor, `.then/.catch/.finally`, `Promise.all/race/allSettled/any`, `Promise.resolve/reject`, thenable assimilation per ECMAScript §25.6.1.3.2, `queueMicrotask`, microtask queue with index-based draining ✅ DONE (2.5% with async harness)
- [x] **Event Loop / Timers** — `setTimeout`, `clearTimeout`, `setInterval`, `clearInterval` per WHATWG Timer APIs, event loop with microtask checkpoints between tasks, `cancelled_timer_ids` map for in-callback cancellation ✅ DONE
- [ ] **Generators** — `function*`, `yield`, `yield*` (requires stack management) → Phase 7
- [ ] **async/await** — `async function`, `await` (requires generator-like suspension) → Phase 7
- [ ] **WeakMap/WeakSet** — basic reference-based collections → Phase 7

### Phase 4 Outcome

**All primary Phase 4 features complete.** Generators and async/await deferred to Phase 7 due to architectural complexity. Timer APIs (setTimeout/setInterval) are fully implemented with proper event loop semantics including microtask checkpoints between tasks.

---

## Key Architectural Decisions

1. **Functions must be objects** — `assert.sameValue = function() {}` assigns a property on a function. Merge `Function` into `Object` with a `callable` field.
2. **Exception propagation** — Use MoonBit's native `raise` with `JsException(Value)` rather than threading `ThrowSignal` through every `Signal` match.
3. **Property descriptors** — `ObjectData.descriptors` map with `writable`/`enumerable`/`configurable` flags alongside `properties`. Descriptor-aware access enforced in Phase 3E.
4. **Array storage** — Dedicated `Array(ArrayData)` variant with `elements: Array[Value]` for performance.
5. **Builtin organization** — Split into `builtins_object.mbt`, `builtins_array.mbt`, `builtins_string.mbt`, etc.

## Dependency Graph

```
Phase 1 (DONE) ──► Phase 2 (DONE) ──► Phase 3 (DONE) ──► Phase 3.5 (DONE)
                                                                │
                                                          [8.77% pass rate]
                                                                │
                                                                ▼
                                                    ┌───────────────────────┐
                                                    │  Phase 3.6 ✅         │
                                                    │  Built-in Compliance  │
                                                    │  + ES6 Classes        │
                                                    └───────────────────────┘
                                                                │
                                                          [27.1% pass rate]
                                                                │
                                                                ▼
                                                    ┌───────────────────────┐
                                                    │  Phase 4 ✅           │
                                                    │  Symbols, Map/Set     │
                                                    │  Promises, Timers     │
                                                    └───────────────────────┘
                                                                │
                                                          [26.4% pass rate]
                                                                │
                                                                ▼
                                                    ┌───────────────────────┐
                                                    │  Phase 5 ✅           │
                                                    │  Skip list cleanup    │
                                                    │  Async harness        │
                                                    │  Object spread        │
                                                    │  new.target           │
                                                    └───────────────────────┘
                                                                │
                                                          [26.2% pass rate] ✅ CURRENT
                                                                │
                                                                ▼
                                                    ┌───────────────────────┐
                                                    │  Phase 6 🔄           │
                                                    │  Spec compliance      │
                                                    │  Array/Object/String  │
                                                    └───────────────────────┘
                                                                │
                                                                ▼
                                                    ┌───────────────────────┐
                                                    │  Phase 7              │
                                                    │  Generators           │
                                                    │  async/await          │
                                                    └───────────────────────┘
                                                                │
                                                                ▼
                                                          [35-40% pass rate]
```

## Summary

| Phase | Pass Rate | Unit Tests | Key Unlock |
|-------|-----------|------------|------------|
| Phase 1 ✅ | 8.18% | 195 | Core language, harness dependencies (except template literals) |
| Phase 2 ✅ | ~8.5% | 288 | Template literals unblock assert.js, arrow functions, prototype chain, built-ins |
| Phase 3 ✅ | ~8.7% | 444 | Strict mode, destructuring, spread/rest, RegExp, JSON, property descriptors, array HOFs, Number built-ins |
| Phase 3.5 ✅ | 8.77% (1,848/21,074) | 444 | Optional chaining, nullish coalescing, exponentiation, computed properties, getters/setters, TDZ |
| Phase 3.6 ✅ | 27.1% (5,703/21,042) | 457 | ES6 Classes, comma-separated declarations, built-in spec fixes, URI encoding |
| Phase 4 ✅ | 26.4% (6,073/23,023) | — | Symbols, iteration protocols, Map/Set, Promise/microtask queue, timer APIs |
| **Phase 5** ✅ | **26.2%** (6,351/24,231) | — | **Skip list cleanup, async harness, object spread, new.target** |

**Why pass rate is 26.2% after Phase 5**: Phase 5 unlocked +1,208 additional tests for execution (23,023 → 24,231) by removing 18 implemented features from skip lists and enabling async test harness support. Absolute pass count increased by +278 (6,073 → 6,351). The pass rate decreased slightly (26.4% → 26.2%) because more tests are now running. Key wins: object spread `{...obj}` now works, `new.target` meta-property implemented, $DONE async pattern supported.

**Phase 5 impact**: Removed Promise/Object/Array/String feature tags from skip lists, added $DONE pattern support with print markers, implemented object spread in object literals, and added new.target meta-property. Promise tests now running (603 executed vs 167 before) with 2.5% pass rate due to spec edge cases.

---

## High Priority TODO List

### 🔥 Phase 6: Spec Compliance Deep Dive (NEXT)

**This is the highest-impact work remaining.** See Phase 6 section above for detailed method-by-method breakdown.

| Task | Impact | Est. Pass Rate Gain | Status |
|------|--------|---------------------|--------|
| **Array spec compliance** | ~2,000 tests | +8-10% | 🔄 TODO |
| **String spec compliance** | ~1,500 tests | +5-7% | 🔄 TODO |
| **Object spec compliance** | ~1,000 tests | +3-5% | 🔄 TODO |
| **Number spec compliance** | ~500 tests | +2-3% | ✅ MOSTLY DONE |
| **Function spec compliance** | ~300 tests | +1-2% | ✅ DONE |

**Already completed**:
- [x] `Array.from()` / `Array.of()` — already implemented ✅
- [x] `Object.is()` — SameValue algorithm (same_value function) ✅
- [x] `Object.fromEntries()` — iterable of pairs ✅
- [x] `Number.isNaN/isFinite/isInteger` — type checks ✅
- [x] `encodeURI/decodeURI/encodeURIComponent/decodeURIComponent` — URI encoding ✅
- [x] `Boolean.prototype.toString/valueOf` — Boolean methods ✅
- [x] `Function constructor and prototype` — Function built-ins ✅

### ✅ Completed (Phases 3.6–5)

| Task | Impact | Status |
|------|--------|--------|
| **Classes (`class`, `extends`, `super`)** | ~3,000 tests | ✅ DONE (Phase 3.6) |
| **Symbols (`Symbol`, `Symbol.iterator`)** | ~2,000 tests | ✅ DONE (Phase 4) |
| **Promises** | ~1,000 tests | ✅ DONE (Phase 4, 2.5% with async harness) |
| **Skip list cleanup** | ~1,200 tests unlocked | ✅ DONE (Phase 5A) |
| **Async test harness ($DONE)** | Async tests now run | ✅ DONE (Phase 5B) |
| **Object spread `{...obj}`** | ~200 tests | ✅ DONE (Phase 5C) |
| **new.target meta-property** | ~100 tests | ✅ DONE (Phase 5D) |

### 🟡 High (Phase 7 features)

| Task | Impact | Status |
|------|--------|--------|
| **Generators (`function*`, `yield`)** | ~1,500 tests | ❌ TODO |
| **async/await** | ~500 tests | ❌ TODO (requires generators) |
| **Iterators (iterator protocol)** | ~800 tests | ✅ DONE |
| **`Map` / `Set` collections** | ~600 tests | ✅ DONE (Map 19.4%, Set 23.0%) |
| **Event Loop / Timers** | ~100 tests | ✅ DONE (setTimeout/setInterval with microtask checkpoints) |
| **`instanceof` with Symbol.hasInstance** | ~200 tests | ✅ DONE |
| **Numeric separator literals (`1_000`)** | ~50 tests | ✅ DONE |
| **Logical assignment (`&&=`, `||=`, `??=`)** | ~100 tests | ✅ DONE |

### 🟢 Medium (Nice to have)

| Task | Impact | Status |
|------|--------|--------|
| **`WeakMap` / `WeakSet`** | ~200 tests | ❌ TODO |
| **`Proxy` / `Reflect`** | ~500 tests | ❌ TODO |
| **`BigInt`** | ~300 tests | ❌ TODO |
| **TypedArrays / ArrayBuffer** | ~400 tests | ❌ TODO |

### ✅ Recently Completed (Phase 5)

| Task | Commit |
|------|--------|
| **Skip list cleanup** — Removed 18 implemented features from SKIP_FEATURES | `5d07a88` |
| **Async test harness** — $DONE pattern via print markers, exit code validation | `5d07a88` |
| **Object spread** — `{...obj}` in object literals, spread enumerable own properties | `5d07a88` |
| **new.target** — Meta-property in constructors and functions with lexical inheritance | `5d07a88` |
| **PR review fixes** — type_of() in error messages, async exit code validation | `9bfbd2e` |

### ✅ Previously Completed (Phase 4)

| Task | Commit |
|------|--------|
| **Promise** — Full ECMAScript Promise implementation with microtask queue | Phase 4 |
| `Promise` constructor with executor, `Promise.resolve()`, `Promise.reject()` | Phase 4 |
| `.then()`, `.catch()`, `.finally()` with proper reaction chaining | Phase 4 |
| `Promise.all()`, `Promise.race()`, `Promise.allSettled()`, `Promise.any()` | Phase 4 |
| Thenable assimilation via `Get(resolution, "then")` with prototype chain traversal per ECMAScript §25.6.1.3.2 | Phase 4 |
| `PromiseResolveThenableJob` enqueued as microtask for spec-compliant thenable unwrapping | Phase 4 |
| `queueMicrotask()` Web Platform API | Phase 4 |
| Microtask queue with index-based O(n) draining (not O(n²) remove(0)) | Phase 4 |
| `queueMicrotask` callbacks invoked with zero args; Promise jobs keep one reaction arg | Phase 4 |
| `Promise.resolve` path now uses resolving functions so thenables are assimilated correctly | Phase 4 |
| User-defined properties on Promise values (`properties` + `symbol_properties` on PromiseData) | Phase 4 |
| Promise computed property read coerces non-string keys via ToPropertyKey | Phase 4 |
| **Event Loop / Timer APIs** — WHATWG Timer APIs with event loop | Phase 4 |
| `setTimeout(callback, delay, ...args)` / `clearTimeout(id)` | Phase 4 |
| `setInterval(callback, delay, ...args)` / `clearInterval(id)` | Phase 4 |
| Timer queue sorted by (delay, insertion_order) with microtask checkpoints between tasks | Phase 4 |
| `cancelled_timer_ids` map prevents re-enqueue when clearInterval called inside callback | Phase 4 |
| **Map/Set Collections** — ES6 `Map` and `Set` with `.get/.set/.has/.delete/.clear/.size`, SameValueZero equality, insertion order preservation, iterator support via `Symbol.iterator` | `2df0f4d` |
| Map constructor accepts iterable of `[key, value]` pairs with ES6-compliant upsert logic | `2df0f4d` |
| Set constructor accepts iterable with duplicate filtering | `2df0f4d` |
| Map/Set `.forEach(callback, thisArg)` methods | `2df0f4d` |
| Map/Set `.keys()`, `.values()`, `.entries()` iterator methods | `2df0f4d` |
| **Iteration Protocol** — `Symbol.iterator`, iterator objects, `for-of` support | Phase 4 |
| `Array.prototype[Symbol.iterator]` — returns array iterator | Phase 4 |
| `String.prototype[Symbol.iterator]` — returns string character iterator | Phase 4 |
| `Array.prototype.keys()`, `values()`, `entries()` — iterator methods | Phase 4 |
| Spread operator uses iterator protocol for custom iterables | Phase 4 |
| `for-of` statement uses iterator protocol | Phase 4 |
| **Symbols** (`Symbol()`, `Symbol.for()`, `Symbol.keyFor()`, well-known symbols) | `b4dbef4` |
| Symbol-keyed properties on objects (`symbol_properties`, `symbol_descriptors`) | `9526049` |
| `Object.getOwnPropertySymbols()` returns actual symbol keys | `b4dbef4` |
| `hasOwnProperty` / `Object.hasOwn` handle Symbol keys | `b4dbef4` |
| Object rest patterns include symbol properties | `b4dbef4` |
| Compound assignments (`+=`, `&&=`, `\|\|=`, `??=`) handle Symbol keys | `b4dbef4` |
| Symbol.keyFor O(1) reverse lookup optimization | `b4dbef4` |
| **`instanceof` with Symbol.hasInstance** — custom `[Symbol.hasInstance]` methods, GetMethod prototype chain lookup, OrdinaryHasInstance fallback | `5ba4019` |

### ✅ Recently Completed (Phase 3.6)

| Task | Commit |
|------|--------|
| **ES6 Classes** (`class`, `extends`, `super`, static) | `303772d` |
| Class method enumerability (non-enumerable per spec) | `303772d` |
| Super constructor return value handling | `303772d` |
| Prototype property for non-constructable functions | `010d3df` |
| Prototype property memoization | `010d3df` |
| decodeURI reserved character preservation | `303772d` |
| ClassConstructor pattern matching fixes | `c444ac2` |
| Comma-separated variable declarations (`var a, b, c;`) | `4cba348` |
| Sort comparator exception handling per ECMAScript spec | `0e21a2a` |
| MoonBit syntax fix: pattern matching for Option check | `943959a` |
| Document Array constructor sparse array limitation | `d23295b` |
| Test262 harness simulation tests | `67b2ad4` |
| Math.imul 32-bit masking | Phase 3.6 |
| String.toWellFormed/isWellFormed | Phase 3.6 |
| Array.values() iterator | Phase 3.6 |
| String.codePointAt | Phase 3.6 |
| Object.fromEntries with TypeError validation | Phase 3.6 |
| Number.prototype.toPrecision | Phase 3.6 |
| Number.prototype.toExponential | Phase 3.6 |
| String.prototype.split limit parameter | Phase 3.6 |
| Function.prototype.length property | Phase 3.6 |
| Function.prototype.name property | Phase 3.6 |
| Logical assignment operators (`&&=`, `||=`, `??=`) | Phase 3.6 |
| Numeric separator literals (`1_000`, `0xFF_FF`) | Phase 3.6 |
| Hex/binary/octal number literals | Phase 3.6 |
| Exponent notation (`1e10`) | Phase 3.6 |

### ✅ Previously Completed (Phase 3.5)

| Task | Commit |
|------|--------|
| Optional chaining (`?.`) | `5c22029` |
| Nullish coalescing (`??`) | `5c22029` |
| Exponentiation (`**`) | Phase 3.5 |
| Computed property names | Phase 3.5 |
| Getters/setters with arity validation | Phase 3.5 |
| TDZ for let/const | Phase 3.5 |
| Global `this`/`globalThis` | Phase 3.5 |
| Shorthand property validation (identifier keys only) | `d5edb04` |
| Exponentiation rejects typeof/void/delete unary ops | `29931fc` |
| Nullish coalescing rejects `a && b ?? c` pattern | `29931fc` |

---

## CodeRabbit Review Status

All issues from [PR #4 review](https://github.com/dowdiness/js_engine/pull/4) addressed:

| Issue | Status | Notes |
|-------|--------|-------|
| QuestionQuestion/QuestionDot regex context | ✅ Fixed | Already in regex-start list |
| var/var redeclaration | ✅ Fixed | Implemented in environment.mbt |
| OptionalCall this-binding | ✅ Fixed | Preserves receiver for method calls |
| Exponentiation unary operators | ✅ Fixed | `29931fc` - Added typeof/void/delete |
| Nullish coalescing && mixing | ✅ Fixed | `29931fc` - Rejects `a && b ?? c` |
| Getter/setter arity validation | ✅ Fixed | Getters=0, Setters=1 params |
| Global this extensible field | ✅ Fixed | Set to true |
| Skip lists sync | ✅ Fixed | Both files have generator/generators |

---

**Next step**: Execute the **10,000 Test Strategy** below.

---

## Strategy: Reaching 10,000 Passing Tests

### Executive Summary

**Current state**: 6,073 passing / 23,023 executed / 49,647 discovered / 26,590 skipped (26.4%)
**Target**: 10,000 passing tests (~43% of executed, or ~20% of total discovered)
**Gap**: +3,927 tests needed

The path to 10,000 follows three parallel tracks:

| Track | Strategy | Est. New Passes | Cumulative |
|-------|----------|----------------|------------|
| **Track 1** | Unlock skipped tests | +1,800–2,800 | ~7,900–8,900 |
| **Track 2** | Fix failing tests (spec compliance) | +1,200–1,800 | ~9,100–10,700 |
| **Track 3** | Generators + async/await | +800–1,200 | ~9,900–11,900 |

**Key insight**: 26,590 tests (53.5%) are currently skipped. Many are skipped for features that ARE already implemented but remain in the skip list. Unlocking these tests is the single highest-leverage action.

---

### Current Gap Analysis

#### Why 26,590 Tests Are Skipped

Tests are skipped for two reasons:
1. **Feature tags** in `SKIP_FEATURES` (test262-runner.py:52–139) — 97 features listed
2. **Flags** in `SKIP_FLAGS` (test262-runner.py:141) — `module`, `async`, `CanBlockIsFalse`, `CanBlockIsTrue`

**Critical finding: 15+ features in `SKIP_FEATURES` are already implemented** but were never removed from the skip list after implementation. This means thousands of tests that *could* run are being silently skipped.

#### Why 16,950 Executed Tests Fail

The 16,950 failing tests break down into:
- **Spec compliance edge cases** (~60%) — Methods exist but don't handle all edge cases per ECMAScript spec
- **Missing sub-features** (~25%) — Tests require a combination of features, one of which is missing
- **Error message format mismatches** (~10%) — Correct error type thrown but message format differs
- **Timeout/crashes** (~5%) — 31 timeouts, 3 runner errors

---

## Phase 5: Unlock Skipped Tests → 26.2% pass rate ✅ COMPLETE

### Phase 5A: Skip List Cleanup ✅ DONE

**Removed 18 implemented features from skip lists** in both `test262-runner.py` and `test262-analyze.py`:
- Promise, Promise.allSettled, Promise.any, Promise.prototype.finally
- Object.fromEntries, Object.is, Object.hasOwn
- Array.from, Array.prototype.at
- String.prototype.replaceAll, String.prototype.isWellFormed, String.prototype.toWellFormed
- change-array-by-copy, array-find-from-last, string-trimming
- new.target, object-spread, object-rest

**Impact**: Unlocked ~1,200 additional tests for execution (executed count: 23,023 → 24,231)

### Phase 5B: Async Test Harness ($DONE Pattern) ✅ DONE

**Implementation**:
- Added `print()` function preamble for console.log compatibility
- Added `$DONE` fallback that prints `Test262:AsyncTestComplete` or `Test262:AsyncTestFailure:<error>`
- Modified test runner to detect these markers in stdout/stderr
- Check failure marker before success marker (correct priority)
- Validate exit code == 0 before marking async test as passed
- Removed `async` from `SKIP_FLAGS`

**Impact**: Async tests now run (Promise pass rate: 2.5% with 603 tests executed vs 167 before)

### Phase 5C: Object Spread in Object Literals ✅ DONE

**Implementation**:
- Added `Spread` variant to `PropKind` enum in `ast/ast.mbt`
- Added DotDotDot handling in `parse_object_literal()` in `parser/expr.mbt`
- Added spread evaluation in `ObjectLit` handler in `interpreter/interpreter.mbt`:
  - Copies enumerable own string properties
  - Copies enumerable own symbol properties
  - Handles arrays (indexed elements only, no length)
  - Handles strings (character-indexed properties)
  - Skips null/undefined (no error)
  - Raises TypeError for non-iterable values in spread contexts
- Uses `type_of(val)` in error messages to avoid toString() side effects

**Impact**: Object spread syntax `{...obj}` now works

### Phase 5D: new.target Meta-Property ✅ DONE

**Implementation**:
- Added `NewTargetExpr(@token.Loc)` variant to `Expr` enum in `ast/ast.mbt`
- Added new.target detection in `parse_new_expr()` in `parser/expr.mbt`
- Added `<new.target>` environment binding in `eval_new` for UserFunc, UserFuncExt, ClassConstructor
- Added `<new.target>` binding set to Undefined in `call_value` for regular function calls
- Arrow functions inherit `<new.target>` from enclosing scope (lexical binding)
- Implicit super() in derived class constructors correctly preserves derived constructor as new.target

**Impact**: `new.target` meta-property works in constructors and functions

### Phase 5 Results

| Sub-phase | Action | Status |
|-----------|--------|--------|
| 5A | Skip list cleanup (18 features) | ✅ DONE |
| 5B | $DONE async test harness | ✅ DONE |
| 5C | Object spread in object literals | ✅ DONE |
| 5D | new.target meta-property | ✅ DONE |

**Outcome**: +278 new passing tests (6,073 → 6,351), +1,208 more tests now executed (23,023 → 24,231)

---

## Phase 6: Spec Compliance Deep Dive → ~9,000–10,000 pass rate

### Phase 6A: Systematic Failure Analysis

**Priority: HIGH — Data-driven approach to maximize pass rate gains**

Before fixing individual methods, run a failure categorization pass:

1. **Modify test262-runner.py** to capture failure categories:
   - Parse error (SyntaxError during parsing)
   - Runtime TypeError / ReferenceError / RangeError
   - Assertion failure (assert.sameValue, assert.throws)
   - Timeout
   - Unexpected output

2. **Group failures by error pattern** to find the top-N root causes:
   - Example: If 500 tests fail because `Array.prototype.map` doesn't call the callback with `(element, index, array)` (3 args), fixing that single issue resolves 500 tests
   - Example: If 300 tests fail because `Object.defineProperty` doesn't validate descriptor types correctly, that's one fix for 300 tests

3. **Prioritize fixes by impact**: Fix the root causes that unblock the most tests first

**Expected output**: Ranked list of ~20–30 root causes covering 80% of fixable failures

### Phase 6B: Array Spec Compliance (19.8% → 40%+)

**Target**: +500–700 additional Array tests passing

Key compliance gaps (in priority order):

1. **Sparse array handling** — Many Array methods must skip holes (`undefined` at index vs no index at all):
   - `forEach`, `map`, `filter`, `reduce`, `every`, `some`, `find`, `findIndex` must use `HasProperty` check
   - `Array(5)` creates sparse array with 5 holes, not 5 `undefined`s

2. **`this` coercion in callbacks** — Array HOFs must pass `thisArg` as second parameter:
   - `arr.map(fn, thisArg)` — `fn` is called with `thisArg` as `this`
   - Currently may not be handling thisArg for all methods

3. **`Array.from()`** edge cases:
   - Support `mapFn` second argument
   - Support `thisArg` third argument
   - Handle array-like objects (not just iterables)

4. **`Array.prototype.sort`** stability and spec compliance:
   - Stable sort (equal elements maintain order)
   - `comparefn` returning non-number → coerce to number
   - `undefined` elements sort to end

5. **Length coercion** — Methods must use `ToLength(Get(O, "length"))`:
   - Works with array-like objects, not just actual arrays
   - Clamps to 0..2^53-1 range

6. **Species pattern** — `Array.prototype.map/filter/slice` should respect `Symbol.species`:
   - Lower priority but affects many tests

### Phase 6C: Object Spec Compliance (18.2% → 35%+)

**Target**: +400–600 additional Object tests passing

Key compliance gaps:

1. **`Object.defineProperty` validation**:
   - Accessor descriptors (`get`/`set`) cannot have `value` or `writable` — must throw TypeError
   - Converting between accessor and data descriptors
   - Generic descriptor (neither accessor nor data)

2. **Property enumeration order**:
   - Integer indices first (in numeric order), then string keys (in insertion order), then symbols
   - Affects `Object.keys`, `Object.entries`, `for-in`, etc.

3. **`Object.assign` edge cases**:
   - Invokes getters on source, setters on target
   - Skips non-enumerable and inherited properties
   - If a setter throws, assignment stops but already-assigned properties remain

4. **`Object.create` with properties argument**:
   - Second argument is a properties descriptor object (like `Object.defineProperties`)

5. **Prototype chain operations**:
   - `Object.setPrototypeOf` cycle detection
   - `Object.getPrototypeOf` on non-objects (coerce to object first)

### Phase 6D: String and RegExp Improvements

**Target**: +200–400 additional tests passing

**String priorities**:

1. **`String.prototype.replace` replacement patterns**:
   - `$&` (matched substring), `$`` (before match), `$'` (after match)
   - `$1`–`$9` (capture group references)
   - `$$` (literal dollar sign)
   - These patterns affect many string tests

2. **`String.prototype.match`** with global flag:
   - Returns array of all matches (not just first)
   - Resets `lastIndex` between matches

3. **`String.prototype.search`** edge cases:
   - Converts string argument to RegExp

4. **Unicode correctness**:
   - Proper surrogate pair handling in `charAt`, `charCodeAt`, `codePointAt`
   - `String.prototype[Symbol.iterator]` already handles surrogates

**RegExp priorities** (lower ROI but meaningful):

1. **`regexp-named-groups`** — `(?<name>pattern)` syntax:
   - Adds `groups` property to match results
   - Unlocks ~150 tests

2. **`regexp-dotall`** — `s` flag:
   - Makes `.` match newlines
   - Unlocks ~50 tests

3. **`String.prototype.matchAll`**:
   - Returns iterator of all matches with capture groups
   - Unlocks ~80 tests

### Phase 6E: Expression and Statement Compliance

**Target**: +300–500 additional tests passing

**Expressions (44.8% → 55–60%)**:
1. **Tagged template literals** — `` tag`string ${expr}` `` — function called with string parts and expressions
2. **Destructuring edge cases** — Default value evaluation order, computed property keys in patterns
3. **Comma operator in for-loops** — `for (a = 0, b = 0; ...)` with proper sequencing
4. **Assignment target validation** — `1 = 2` should throw ReferenceError at parse time
5. **Optional chaining edge cases** — `a?.b.c.d` when `a` is null (entire chain short-circuits)

**Statements (30.5% → 45–50%)**:
1. **`for-in` with let/const** — Fresh binding per iteration
2. **`switch` fall-through edge cases** — Empty cases, default positioning
3. **Labeled statement interactions** — Nested labels, break/continue with labels in try/finally
4. **`with` statement** — Low priority but unlocks some tests
5. **Strict mode restrictions** — `eval` and `arguments` cannot be assigned in strict mode

### Phase 6 Summary

| Sub-phase | Category | Target Improvement | Est. New Passes |
|-----------|----------|-------------------|----------------|
| 6A | Failure analysis | Identify top root causes | (enables 6B–6E) |
| 6B | Array | 19.8% → 40% | +500–700 |
| 6C | Object | 18.2% → 35% | +400–600 |
| 6D | String/RegExp | 21.9% → 35% / 10.3% → 20% | +200–400 |
| 6E | Expressions/Statements | 44.8% → 55% / 30.5% → 45% | +300–500 |
| **Total** | | | **+1,400–2,200** |

**Projected cumulative**: ~9,100–11,400 passing tests

---

## Phase 7: Generators + async/await → 10,000+ pass rate

### Phase 7A: Generators

**Priority: HIGH — Largest single feature still missing**

Generators (`function*`, `yield`, `yield*`) are the most architecturally significant remaining feature. They require suspension/resumption of execution state, which is fundamentally different from the current tree-walking interpreter model.

**Architecture options**:

1. **Continuation-Passing Style (CPS) transformation**:
   - Transform generator body into state machine at AST level
   - Each `yield` becomes a state transition
   - Pro: No runtime stack manipulation needed
   - Con: Complex AST transformation, harder to debug

2. **Explicit state machine in interpreter**:
   - Track generator state: `suspended-start`, `suspended-yield`, `executing`, `completed`
   - Save/restore local variables and instruction pointer on yield/resume
   - Pro: Cleaner implementation, easier to understand
   - Con: Requires environment snapshot/restore

3. **Coroutine/fiber approach** (if MoonBit supports it):
   - Use language-level coroutines for true suspension
   - Pro: Most natural semantics
   - Con: May not be available in MoonBit/WASM

**Recommended approach**: Option 2 (explicit state machine) — convert generator function body into a series of "segments" separated by yield points. Each segment is a sequence of statements. The generator object tracks which segment to execute next, and carries the local environment.

**Implementation plan**:

1. **Parser**: Detect `function*` (generator declaration/expression), `yield` and `yield*` expressions
2. **AST**: Add `GeneratorDecl`, `GeneratorExpr`, `YieldExpr`, `YieldDelegateExpr` nodes
3. **Value**: Add `Generator(GeneratorData)` value variant with state machine
4. **Interpreter**:
   - `eval_generator_decl` — Create generator function (like regular function but returns generator object on call)
   - `eval_generator_call` — Create generator object with `next()`, `return()`, `throw()` methods
   - `eval_yield` — Save state, return `{value, done: false}`
   - Generator `next(val)` — Resume from saved state, `val` becomes yield result
   - Generator `return(val)` — Complete generator, return `{value: val, done: true}`
   - Generator `throw(err)` — Resume generator, throw error at yield point
5. **Iterator protocol**: Generator objects automatically implement `Symbol.iterator` (return `this`)
6. **`yield*`**: Delegate to another iterable, forwarding `next/return/throw`

**Test impact**: ~1,500 tests discovered, estimate 30–50% initial pass rate = +450–750 new passes
**Remove from skip lists**: `generators`, `generator`

### Phase 7B: async/await

**Priority: HIGH — Depends on generators and promises (both implemented)**

async/await is syntactic sugar over Promises + generator-like suspension:
- `async function` returns a Promise
- `await expr` suspends until Promise resolves, then resumes with resolved value
- Rejection causes `await` to throw

**Implementation plan** (assuming generators are done):

1. **Parser**: Detect `async function`, `async () =>`, `await` expression
2. **AST**: Add `AsyncFuncDecl`, `AsyncFuncExpr`, `AsyncArrowFunc`, `AwaitExpr` nodes
3. **Interpreter**:
   - `async function` wraps body in Promise: return value is resolve, thrown error is reject
   - `await` suspends execution (like `yield`), resumes when Promise settles
   - Can reuse generator state machine infrastructure

4. **Remove from skip lists**: `async-functions`
5. **Also remove `async` from `SKIP_FLAGS`** (if not already done in Phase 5B)

**Test impact**: ~500 tests with `async-functions` tag + additional async-flag tests
**Expected**: +300–400 new passes

### Phase 7 Summary

| Sub-phase | Feature | Est. New Passes |
|-----------|---------|----------------|
| 7A | Generators (`function*`, `yield`, `yield*`) | +450–750 |
| 7B | async/await | +300–400 |
| **Total** | | **+750–1,150** |

**Projected cumulative**: ~9,850–12,550 passing tests

---

## Implementation Priority & Dependency Graph

```
Phase 5 ✅ COMPLETE ─────────────────────────────────────────────────────
    │
    │   5A: Skip list cleanup ✅
    │   5B: $DONE async harness ✅
    │   5C: Object spread ✅
    │   5D: new.target ✅
    │
    ▼
Phase 6 🔄 NEXT ──────────────────────────────────────────────────────────
    │
    ├── Phase 6A ──────────────────── (failure analysis, diagnostic only)
    ├── Phase 6B ──────────────────── (Array compliance)
    ├── Phase 6C ──────────────────── (Object compliance)
    ├── Phase 6D ──────────────────── (String/RegExp compliance)
    └── Phase 6E ──────────────────── (Expression/Statement compliance)
    │
    ▼
Phase 7 ──────────────────────────────────────────────────────────────────
    │
    ├── Phase 7A ──────────────────── (generators, major architecture)
    │
    └── Phase 7B ──────────────────── (async/await, builds on 7A)
```

**Current focus**: Phase 6 spec compliance work. All Phase 6 sub-tasks can be worked on in parallel. Phase 7 (generators/async) is sequential (7B depends on 7A).

---

## Projected Milestones

| Milestone | Passes | Pass Rate | Key Deliverable |
|-----------|--------|-----------|-----------------|
| **Phase 5 (CURRENT)** | 6,351 | 26.2% | ✅ Skip list cleanup, async harness, object spread, new.target |
| **After Phase 6A–C** | ~7,500 | ~28% | Array + Object + String spec compliance |
| **After Phase 6D–E** | ~8,500 | ~32% | Expression/Statement compliance, RegExp improvements |
| **After Phase 7A** | ~9,500 | ~35% | **Generators — approaching 10K target** |
| **After Phase 7B** | ~10,500 | ~38% | **async/await — 10K target reached** |

*Note: Pass rate percentage can decrease when more tests are unlocked (larger denominator), even as absolute pass count increases. Phase 5 demonstrated this: +278 passes but -0.2% rate due to +1,208 more tests being executed.

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Generator implementation is architecturally complex | Could delay Phase 7 significantly | Start Phase 7A design early; consider CPS transformation over runtime suspension |
| Removing skip list features exposes many new failures | May temporarily decrease pass *rate* | Focus on absolute pass count, not rate; analyze failures systematically |
| $DONE harness may not work for all async patterns | Some async tests may still fail | Start with simple $DONE (synchronous microtask drain) before adding timer support |
| Spec compliance fixes have diminishing returns | Last 20% of failures may be 80% of the work | Use failure analysis (Phase 6A) to stay focused on high-impact fixes |
| MoonBit language limitations | Some JS patterns may be hard to express | Document workarounds as discovered; the team has already found solutions for many MoonBit-specific issues |

---

## Quick Win Checklist ✅ COMPLETED (Phase 5)

All quick wins from Phase 5 are now done:

- [x] Remove `Promise`, `Promise.allSettled`, `Promise.any`, `Promise.prototype.finally` from `SKIP_FEATURES` ✅
- [x] Remove `Object.fromEntries`, `Object.is`, `Object.hasOwn` from `SKIP_FEATURES` ✅
- [x] Remove `Array.from`, `Array.prototype.at` from `SKIP_FEATURES` ✅
- [x] Remove `String.prototype.replaceAll`, `String.prototype.isWellFormed`, `String.prototype.toWellFormed` from `SKIP_FEATURES` ✅
- [x] Remove `change-array-by-copy`, `array-find-from-last`, `string-trimming` from `SKIP_FEATURES` ✅
- [x] Sync same removals in `test262-analyze.py` (also removed `class`, `numeric-separator-literal`, `logical-assignment-operators`) ✅
- [x] Remove `async` from `SKIP_FLAGS` and add $DONE harness support ✅
- [x] Implement object spread `{...obj}` ✅
- [x] Implement `new.target` meta-property ✅
- [x] Run full test262 suite: 6,351 passed / 24,231 executed ✅

### Next Quick Wins (Phase 6)

Focus on spec compliance to increase pass rate:

- [ ] Analyze top failure categories to identify root causes
- [ ] Fix Array method edge cases (sparse array handling, thisArg in HOFs)
- [ ] Fix Object method edge cases (property enumeration order, defineProperty validation)
- [ ] Improve String.prototype.replace with replacement patterns ($1, $&, etc.)
