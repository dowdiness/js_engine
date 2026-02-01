## Current State

**Test262 Pass Rate: 8.18%** (1,598 passed / 17,941 failed / 30,085 skipped)

The MoonBit JS engine currently supports basic language features (variables, arithmetic, functions, closures, control flow) but lacks the core constructs needed for real ECMAScript conformance.

### Root Cause

The Test262 harness files (`sta.js` + `assert.js`) **cannot execute** on the engine. They require `this`, property assignment on functions, `throw`, `new`, `try/catch`, `switch/case`, and `String()` — none of which are implemented. Until the harness loads, zero normal tests can pass. The 1,598 "passing" tests are almost entirely negative tests (tests expected to throw errors).

---

## Phase 1: Core Language Gaps → ~25% pass rate

**Goal**: Get the test262 harness executing, then pass basic language tests.

### 1A. Lexer/Token Extensions
- [ ] Add keywords: `throw`, `try`, `catch`, `finally`, `new`, `this`, `switch`, `case`, `default`, `void`, `delete`, `do`, `in`, `instanceof`
- [ ] Add operators: `++`, `--`, `+=`, `-=`, `*=`, `/=`, `%=`
- [ ] Add bitwise operators: `&`, `|`, `^`, `~`, `<<`, `>>`, `>>>`
- [ ] Add compound bitwise assignment: `&=`, `|=`, `^=`, `<<=`, `>>=`, `>>>=`

### 1B. AST Node Extensions
- [ ] Statements: `ThrowStmt`, `TryCatchStmt`, `SwitchStmt`, `DoWhileStmt`, `ForInStmt`, `LabeledStmt`
- [ ] Expressions: `ObjectLit`, `ArrayLit`, `ComputedMember` (`obj[key]`), `MemberAssign` (`obj.prop = val`), `ComputedAssign` (`obj[key] = val`), `NewExpr`, `ThisExpr`, `UpdateExpr` (`++`/`--`), `CompoundAssign` (`+=` etc.), `Comma`
- [ ] Binary ops: `BitAnd`, `BitOr`, `BitXor`, `LShift`, `RShift`, `URShift`, `In`, `Instanceof`

### 1C. Value System Overhaul
- [ ] Add `Object(ObjectData)` variant with `properties`, `prototype`, `callable`, `class_name`
- [ ] Add `Array(ArrayData)` variant with `elements` array
- [ ] **Unify functions as objects** — the harness does `assert.sameValue = function() {}` (property assignment on a function value)
- [ ] Add string comparison support (currently only numbers can use `<`/`>`)

### 1D. Exception System
- [ ] Add `JsException(Value)` error type using MoonBit's `raise` mechanism
- [ ] Implement `throw` statement evaluation
- [ ] Implement `try/catch/finally` — intercept `JsException`, bind catch variable

### 1E. Parser Extensions
- [ ] Object literals: `{ key: value, ... }` (disambiguate from block statements)
- [ ] Array literals: `[expr, expr, ...]`
- [ ] `this` keyword, `new` expression
- [ ] Computed member access: `obj[key]`
- [ ] Prefix/postfix `++`/`--`
- [ ] Compound assignment: `+=`, `-=`, etc.
- [ ] Member/computed property assignment: `obj.prop = val`, `obj[key] = val`
- [ ] `switch/case/default`, `do-while`, `for-in`
- [ ] `throw` statement, `try/catch/finally`
- [ ] Bitwise and shift operator precedence levels
- [ ] `in`, `instanceof` at relational precedence
- [ ] `void`, `delete` as unary prefix operators
- [ ] Comma operator (lowest precedence)
- [ ] Labeled statements

### 1F. Interpreter Extensions
- [ ] `throw` — evaluate expression and raise `JsException(value)`
- [ ] `try/catch/finally` — wrap execution, intercept `JsException`
- [ ] `new` — create object, set prototype, bind `this`, call constructor
- [ ] `this` — lookup `"this"` in environment
- [ ] Object/array literal evaluation
- [ ] Property access/assignment for any object (not just `console`)
- [ ] `switch/case` with strict equality matching and fall-through
- [ ] `do-while` loop
- [ ] `for-in` — iterate over enumerable property names
- [ ] `++`/`--` — get value, ToNumber, add/subtract 1, assign back
- [ ] Compound assignment — `x += y` semantics
- [ ] Bitwise operators — convert to 32-bit integer, operate, convert back
- [ ] String comparison — lexicographic ordering for `<`, `>`, `<=`, `>=`
- [ ] `void` — evaluate operand, return `undefined`
- [ ] `delete` — remove property from object
- [ ] `in` — check property existence
- [ ] `instanceof` — walk prototype chain
- [ ] Comma — evaluate both sides, return right value
- [ ] Fix `typeof` for undeclared variables (return `"undefined"` instead of throwing)

### 1G. Built-in Globals
- [ ] `NaN`, `Infinity`, `undefined` as global constants
- [ ] `isNaN()`, `isFinite()`, `parseInt()`, `parseFloat()`
- [ ] Error constructors: `Error`, `TypeError`, `ReferenceError`, `SyntaxError`, `RangeError`, `URIError`, `EvalError`
- [ ] `String()`, `Number()`, `Boolean()` conversion functions

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
