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
