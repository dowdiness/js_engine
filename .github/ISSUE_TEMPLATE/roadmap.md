## Current State

**Test262 Pass Rate: 8.18%** (1,598 passed / 17,941 failed / 30,085 skipped)

The MoonBit JS engine currently supports basic language features (variables, arithmetic, functions, closures, control flow) but lacks the core constructs needed for real ECMAScript conformance.

### Root Cause

The Test262 harness files (`sta.js` + `assert.js`) **cannot execute** on the engine. They require `this`, property assignment on functions, `throw`, `new`, `try/catch`, `switch/case`, and `String()` — none of which are implemented. Until the harness loads, zero normal tests can pass. The 1,598 "passing" tests are almost entirely negative tests (tests expected to throw errors).

---

## Phase 1: Core Language Gaps → ~25% pass rate ✅ IMPLEMENTED

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

### Phase 1 Known Issues

Issues found during code review that should be addressed before or during Phase 2:

1. **`to_int32` does not match ECMAScript spec** (value.mbt) — Currently uses `n.to_int()` directly, which is implementation-defined for large doubles. The spec requires modular conversion: truncate toward zero, modulo 2^32, map to signed range. `to_int32(4294967296.0)` should return `0` but may not. **Impact**: Incorrect results for bitwise operations on large numbers.

2. **Error constructors don't set prototype on instances** (builtins.mbt) — `new Error("msg")` creates objects with `prototype: Null`. In real JS, the prototype should be `Error.prototype`, enabling `instanceof Error`. Currently `(new Error("msg")) instanceof Error` returns `false`. **Impact**: Test262 harness tests that check error types with `instanceof` will fail.

3. **`for-in` only enumerates own properties** (interpreter.mbt) — Does not walk the prototype chain. Per spec, `for-in` should also enumerate inherited enumerable properties. **Impact**: Limited until prototype chains are fully used in Phase 2/3.

4. **`LabeledStmt` label is discarded** (interpreter.mbt) — `break label;` / `continue label;` are not implemented. The label is parsed but ignored at runtime; `break` only breaks the innermost loop. **Impact**: Tests using labeled break/continue across nested loops will fail.

5. **`parseFloat` uses O(n^2) progressive prefix parsing** (builtins.mbt) — Builds progressively longer strings and tries `@strconv.parse_double` on each. Works correctly but is slow for long strings. **Impact**: Performance only, correctness is fine.

6. **`eval_update` and `eval_compound_assign` re-evaluate object expressions** (interpreter.mbt) — For `obj.prop++` or `obj.prop += 1`, the object expression is evaluated twice. Side-effecting getters would execute twice. **Impact**: Subtle spec non-compliance for edge cases with getters.

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
- `.lsl()`, `.asr()` methods deprecated — use `<<`, `>>` infix operators
- Hex literal method calls fail to parse (e.g., `0x7FFFFFFF.asr()`) — assign to variable first
- Multiline strings (`#|`) in function call arguments trigger deprecation warning — use `let` binding

### Phase 1 Expected Impact

| Category | Est. new passes |
|----------|----------------|
| language/expressions | ~1,800 |
| language/statements | ~700 |
| language/types + literals | ~350 |
| language/identifiers, keywords, asi | ~400 |
| built-ins/Number, Boolean, NaN | ~230 |
| **Phase 1 total** | **~5,000 (25-26%)** |

---

## Phase 2: Built-in Objects → ~48% pass rate

**Goal**: Implement the standard library to unlock `built-ins/*` tests.

### 2A. Object Built-in (3,150 applicable tests)
- [ ] `Object.keys()`, `values()`, `entries()`
- [ ] `Object.create()`, `Object.assign()`
- [ ] `Object.defineProperty()`, `getOwnPropertyDescriptor()` (requires property descriptor model: `writable`/`enumerable`/`configurable`)
- [ ] `Object.getOwnPropertyNames()`, `Object.getPrototypeOf()`
- [ ] `Object.freeze()`, `seal()`, `preventExtensions()`
- [ ] `Object.prototype.hasOwnProperty()`, `toString()`, `valueOf()`

### 2B. Array Built-in (2,555 applicable tests)
- [ ] `Array.isArray()`
- [ ] Mutators: `push`, `pop`, `shift`, `unshift`, `splice`, `sort`, `reverse`, `fill`
- [ ] Accessors: `slice`, `concat`, `join`, `indexOf`, `lastIndexOf`, `includes`
- [ ] Iterators: `map`, `filter`, `reduce`, `forEach`, `find`, `findIndex`, `every`, `some`, `flat`, `flatMap`
- [ ] `.length` auto-maintenance

### 2C. String Built-in (1,013 applicable tests)
- [ ] `.length` property, auto-boxing for method calls on primitives
- [ ] `charAt`, `charCodeAt`, `substring`, `slice`, `split`
- [ ] `indexOf`, `lastIndexOf`, `includes`
- [ ] `trim`, `trimStart`, `trimEnd`
- [ ] `toLowerCase`, `toUpperCase`
- [ ] `replace`, `startsWith`, `endsWith`, `repeat`, `padStart`, `padEnd`
- [ ] `String.fromCharCode()`

### 2D. Number and Math Built-ins
- [ ] `Number.NaN`, `Number.POSITIVE_INFINITY`, `Number.NEGATIVE_INFINITY`
- [ ] `Number.MAX_VALUE`, `MIN_VALUE`, `EPSILON`, `MAX_SAFE_INTEGER`, `MIN_SAFE_INTEGER`
- [ ] `Number.isNaN()`, `isFinite()`, `isInteger()`, `isSafeInteger()`
- [ ] `Number.prototype.toFixed()`, `toString(radix)`, `valueOf()`
- [ ] `Math.PI`, `E`, `abs`, `floor`, `ceil`, `round`, `trunc`, `sqrt`, `pow`, `min`, `max`, `random`, `sign`, `log`, `log2`, `log10`, trig functions

### 2E. Error Types and JSON
- [ ] Complete error type hierarchy with `.name`, `.message`, `.stack`, proper prototype chain
- [ ] `JSON.parse(text)` — requires a JSON tokenizer
- [ ] `JSON.stringify(value, replacer?, space?)` — recursive serialization

### 2F. RegExp (Basic, 775 applicable tests)
- [ ] RegExp literal parsing in lexer (`/pattern/flags`)
- [ ] `RegExp` constructor
- [ ] `.test(string)`, `.exec(string)`
- [ ] `String.prototype.match()`, `replace()`, `search()`, `split()` with regex support

### Phase 2 Expected Impact

| Category | Est. new passes |
|----------|----------------|
| built-ins/Object | ~1,600 |
| built-ins/Array | ~800 |
| built-ins/String | ~500 |
| built-ins/Math + Number | ~300 |
| built-ins/JSON + Error | ~150 |
| built-ins/RegExp | ~100 |
| Cross-category (propertyHelper unlocks) | ~500 |
| **Phase 2 increment** | **~4,400 (cumulative ~9,400, 48%)** |

---

## Phase 3: Advanced Language Features → ~56% pass rate

- [ ] **Prototype chain** — property lookup walks chain, `Object.create()`, constructor `.prototype`
- [ ] **`this` binding** — method calls (`obj.method()`), `.call()`, `.apply()`, `.bind()`
- [ ] **`arguments` object** — array-like, `arguments.length`, `arguments[i]`, `arguments.callee` (sloppy mode)
- [ ] **Strict mode** — `"use strict"` directive, `this` is `undefined` for unbound calls, assignment to undeclared throws, TDZ enforcement
- [ ] **Hoisting** — `var` and function declaration hoisting, two-pass execution
- [ ] **Arrow functions** — lexer (`=>`), parser, interpreter (lexical `this`)
- [ ] **Template literals** — lexer (backticks), `${expr}` interpolation
- [ ] **Default parameters** — `function f(a = 1) {}`
- [ ] **Destructuring** — array `[a, b] = arr`, object `{x, y} = obj`, in parameters
- [ ] **Spread/rest** — `...args` in function params, calls, array/object literals
- [ ] **`for-of`** loops — iterator protocol for arrays and strings

### Phase 3 Expected Impact: ~1,600 additional tests → cumulative ~11,000 (56%)

---

## Phase 4: Modern ES6+ Features → ~60%+ pass rate

- [ ] **Classes** — `class`, `extends`, `constructor`, `super`, static methods, getters/setters
- [ ] **Symbols** — `Symbol()`, `Symbol.iterator`, `Symbol.toPrimitive`, `typeof symbol`
- [ ] **Iterators/Generators** — `function*`, `yield`, `yield*`, iterator protocol
- [ ] **Promises/async-await** — `Promise`, `.then/.catch/.finally`, `async function`, `await` (requires microtask queue)
- [ ] **Map/Set** — `new Map()`, `new Set()`, `.get/.set/.has/.delete/.size/.forEach`
- [ ] **WeakMap/WeakSet** — basic reference-based collections

### Phase 4 Expected Impact: ~1,600 additional tests → cumulative ~12,600 (60%+)

---

## Key Architectural Decisions

1. **Functions must be objects** — `assert.sameValue = function() {}` assigns a property on a function. Merge `Function` into `Object` with a `callable` field.
2. **Exception propagation** — Use MoonBit's native `raise` with `JsException(Value)` rather than threading `ThrowSignal` through every `Signal` match.
3. **Property descriptors** — Introduce in Phase 2A with `writable`/`enumerable`/`configurable` flags. Phase 1 uses simple `Map[String, Value]`.
4. **Array storage** — Dedicated `Array(ArrayData)` variant with `elements: Array[Value]` for performance.
5. **Builtin organization** — Split into `builtins_object.mbt`, `builtins_array.mbt`, `builtins_string.mbt`, etc.

## Dependency Graph

```
Phase 1A Lexer ──► 1B AST ──► 1C Value types
                                     │
1E Parser ◄──────────────────────────┘
     │
     ▼
1D Exceptions ──► 1F Interpreter ──► 1G Builtins
     │                                    │
     ▼                                    ▼
 [25% pass rate]                    Phase 2 Built-ins
                                          │
                                          ▼
                                    [48% pass rate]
                                          │
                                          ▼
                                    Phase 3 + 4
                                          │
                                          ▼
                                    [56-65% pass rate]
```

## Summary

| Phase | Pass Rate | Key Unlock |
|-------|-----------|------------|
| Current | 8.18% | Negative tests only |
| Phase 1 | ~25% | Harness boots, basic language |
| Phase 2 | ~48% | Standard library |
| Phase 3 | ~56% | Prototype chain, strict mode, ES6 syntax |
| Phase 4 | ~60%+ | Classes, symbols, generators |

**Phase 1 is the critical path** — it has the highest ROI because it unblocks the harness, which is a prerequisite for every normal test to pass.
