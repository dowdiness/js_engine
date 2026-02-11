# Project Glossary

Domain-specific terms used in this JavaScript engine, organized by specification origin and implementation layer.

---

## Event Loop (WHATWG)

| Term | Aliases / Related | Definition |
|------|-------------------|------------|
| **task** | (informally "macrotask") | A unit of work queued for the event loop. Timer callbacks (`setTimeout`, `setInterval`) are tasks. The WHATWG spec uses "task" — "macrotask" is informal jargon not found in the spec. |
| **task queue** | timer queue | Ordered queue of pending tasks. In this engine, `timer_queue` on the `Interpreter` struct. |
| **microtask** | job (ECMAScript) | A unit of work that runs after the current task completes but before the next task. Promise reactions and `queueMicrotask` callbacks are microtasks. |
| **microtask queue** | job queue (ECMAScript) | FIFO queue of pending microtasks. Drained completely at each microtask checkpoint. |
| **microtask checkpoint** | — | The point where all pending microtasks are drained. Occurs after script execution and after each timer task callback. |
| **event loop** | — | The processing model that picks a task, runs it, performs a microtask checkpoint, and repeats. See WHATWG HTML spec §8.1.7. |

**Spec reference:** <https://html.spec.whatwg.org/multipage/webappapis.html#event-loops>

---

## Promises (ECMAScript)

| Term | Aliases / Related | Definition |
|------|-------------------|------------|
| **Promise** | — | A value representing the eventual result of an asynchronous operation. Has internal state, result, and reaction queues. |
| **PromiseState** | state | Enum: `Pending`, `Fulfilled`, `Rejected`. A promise starts Pending and transitions once to either Fulfilled or Rejected. |
| **settle** | settlement | The act of transitioning a promise from Pending to Fulfilled or Rejected. A settled promise never changes state again. |
| **fulfill** | resolve (loosely) | Transition a promise to the Fulfilled state with a value. Triggers all fulfill reactions. |
| **reject** | — | Transition a promise to the Rejected state with a reason. Triggers all reject reactions. |
| **PromiseReaction** | reaction record | A record storing a handler callback, resolve/reject capabilities for the dependent promise, and a reaction type (Fulfill or Reject). |
| **PromiseReactionJob** | NewPromiseReactionJob | A microtask that executes a reaction handler and resolves or rejects the dependent promise with the result. |
| **HostEnqueuePromiseJob** | enqueue_microtask | The host hook that schedules a promise job as a microtask. Implemented by `Interpreter::enqueue_microtask()`. |
| **resolving functions** | capability functions | A paired (resolve, reject) created by `create_resolving_functions()`. Guarded by `already_resolved` to prevent multiple resolution. |
| **executor** | — | The callback passed to `new Promise(executor)`. Called synchronously with (resolve, reject). |
| **thenable** | — | Any object with a callable `.then` property. The resolve algorithm detects thenables and assimilates them via `PromiseResolveThenableJob`. |
| **thenable assimilation** | PromiseResolveThenableJob | When resolving a promise with a thenable, the engine enqueues a microtask that calls `thenable.then(resolve, reject)` to unwrap it. |
| **self-resolution** | chaining cycle | When a promise's resolve function is called with the promise itself. Rejected with a TypeError per spec. |
| **PromiseResolve** | promise_resolve_value | Algorithm (§27.2.4.7): if the value is already a Promise, return it; otherwise wrap in a new fulfilled Promise. |
| **handler** | onFulfilled, onRejected | The callback in a reaction. If `None`, the default identity (pass-through) or thrower (re-throw) behavior applies. |
| **dependent promise** | result promise | The new promise returned by `.then()`, `.catch()`, or `.finally()`. Its settlement depends on the handler's return value. |
| **is_handled** | — | Flag on PromiseData. Set to `true` when an `onRejected` handler is attached. Used for unhandled rejection tracking. |
| **thunk** | finallyValueThunk, finallyThrowerThunk | Internal wrapper functions used by `.finally()` to await the onFinally result and then pass through the original value or re-throw the original reason. |

**Spec reference:** <https://tc39.es/ecma262/#sec-promise-objects>

---

## Timers (WHATWG)

| Term | Aliases / Related | Definition |
|------|-------------------|------------|
| **TimerTask** | — | Struct representing a scheduled timer. Fields: `id`, `callback`, `args`, `delay`, `cancelled`, `is_interval`, `insertion_order`. |
| **delay** | timeout | Millisecond value controlling timer ordering. In this synchronous interpreter, used for relative ordering rather than real waiting. |
| **insertion_order** | — | Monotonically increasing counter used as a stable sort tiebreaker so timers with equal delays fire in registration order. |
| **cancelled** | — | Flag set by `clearTimeout`/`clearInterval`. Cancelled timers are skipped during processing. |
| **is_interval** | — | Flag distinguishing `setInterval` (repeating, re-enqueued after each invocation) from `setTimeout` (one-shot). |
| **safety limit** | max_iterations | Upper bound (10,000) on timer processing iterations to prevent infinite loops from `setInterval`. |

**Spec reference:** <https://html.spec.whatwg.org/multipage/timers-and-user-prompts.html#timers>

---

## Interpreter Architecture

| Term | Aliases / Related | Definition |
|------|-------------------|------------|
| **tree-walking interpreter** | — | An interpreter that directly traverses the AST and evaluates nodes recursively, without compiling to bytecode. |
| **Interpreter** | — | The main struct holding execution state: output buffer, global environment, `global_this`, strict mode flag, microtask queue, and timer queue. |
| **Value** | — | Enum representing all JS value types: `Number`, `String_`, `Bool`, `Null`, `Undefined`, `Object`, `Array`, `Symbol`, `Map`, `Set`, `Promise`. |
| **ObjectData** | — | Struct for JS objects. Contains `properties`, `symbol_properties`, `prototype`, optional `callable`, `class_name`, `descriptors`, `extensible`. |
| **PromiseData** | — | Struct for Promise internals: `state`, `result`, `fulfill_reactions`, `reject_reactions`, `is_handled`, `properties` (for user-defined props). |
| **ArrayData** | — | Struct wrapping an `elements: Array[Value]` for JS arrays. |
| **Callable** | — | Enum of function kinds: `UserFunc`, `ArrowFunc`, `NativeCallable`, `InterpreterCallable`, `ConstructorOnlyCallable`, `BoundFunc`, `ClassConstructor`, and others. |
| **ConstructorOnlyCallable** | — | Callable variant that throws TypeError when invoked without `new`. Used for the Promise constructor. |
| **InterpreterCallable** | — | Callable variant for builtins that need access to the `Interpreter` instance (e.g., for enqueuing microtasks). |
| **NativeCallable** | — | Callable variant for simple builtins that only receive arguments (no interpreter or `this`). |
| **NonConstructableCallable** | — | Callable variant that throws TypeError when invoked with `new`. Used for arrow-like builtins. |
| **Environment** | scope | A lexical scope with a `bindings` map and optional `parent` for scope chain traversal. |
| **scope chain** | parent chain | Linked list of `Environment` nodes traversed during variable lookup. |
| **closure** | captured environment | The `Environment` captured by a function at definition time, enabling lexical scoping. |
| **Signal** | — | Control flow enum: `Normal`, `ReturnSignal`, `BreakSignal`, `ContinueSignal`. |
| **hoisting** | hoist_declarations | JS behavior where `var` and function declarations are moved to the top of their scope before execution. |
| **TDZ** | Temporal Dead Zone | The period between entering a scope and a `let`/`const` declaration being evaluated, during which access throws `ReferenceError`. |
| **strict mode** | "use strict" | Opt-in mode enabling stricter error checking (e.g., assignment to read-only properties throws). |

---

## eval() Semantics

| Term | Aliases / Related | Definition |
|------|-------------------|------------|
| **direct eval** | — | A call to `eval(...)` where the callee expression is syntactically `eval` (or parenthesized: `(eval)(...)`). Executes in the caller's lexical environment. |
| **indirect eval** | — | Any other invocation of the eval function, e.g., `(0, eval)(...)`, `var e = eval; e(...)`. Executes in the global environment. |
| **variable environment** | var_env | The nearest function or global scope where `var` declarations are hoisted. Found by `Environment::find_var_env()`. |
| **is_var_scope** | — | Boolean flag on `Environment`. True for function and global scopes. Used by `find_var_env()` to walk past block scopes. |
| **EvalDeclarationInstantiation** | — | ES spec algorithm (§19.2.1.3) that processes declarations in eval code. Steps 5.a and 5.d check for var/lexical conflicts before hoisting. |
| **var/lex conflict** | — | When eval's `var` declaration name collides with a `let`/`const` in an intermediate scope or global lexical binding. Throws SyntaxError per spec. |
| **unwrap_grouping** | — | Helper function that recursively strips `Grouping` AST nodes, so `((eval))` is still detected as direct eval. Per spec, parentheses don't change Reference type. |
| **NonConstructableCallable** | — | Callable variant that throws TypeError on `new`. Used for eval (and arrow-like builtins) to prevent construction. |
| **perform_eval** | — | Internal method `Interpreter::perform_eval(code, caller_env, direct)` implementing eval execution: parsing, scope setup, var hoisting, and statement execution. |

**Spec reference:** <https://tc39.es/ecma262/#sec-eval-x>

---

## Property Model

| Term | Aliases / Related | Definition |
|------|-------------------|------------|
| **PropDescriptor** | property descriptor | Struct with `writable`, `enumerable`, `configurable` flags controlling property behavior. |
| **writable** | — | If `false`, assignment to the property silently fails (or throws in strict mode). |
| **enumerable** | — | If `false`, the property is skipped during `for...in` and `Object.keys()`. |
| **configurable** | — | If `false`, the descriptor cannot be modified or deleted. |
| **extensible** | — | Object-level flag. If `false`, new properties cannot be added (`Object.preventExtensions`). |

---

## Iterator Protocol

| Term | Aliases / Related | Definition |
|------|-------------------|------------|
| **iterator protocol** | — | Convention where an object's `[Symbol.iterator]()` method returns an iterator with a `next()` method. |
| **Symbol.iterator** | well-known symbol | The symbol key used to access an object's default iterator factory. |
| **next()** | — | Method on iterators returning `{ value, done }` objects. |
| **spread_iterable** | — | Internal function using the iterator protocol to expand an iterable into an `Array[Value]`. |

---

## Symbols

| Term | Aliases / Related | Definition |
|------|-------------------|------------|
| **SymbolData** | — | Struct with a unique `id` and optional `description` string. |
| **well-known symbol** | — | Spec-defined symbols with engine-wide semantics: `Symbol.iterator`, `Symbol.hasInstance`, `Symbol.toStringTag`, `Symbol.species`. |

---

## Type Conversion & Comparison

| Term | Aliases / Related | Definition |
|------|-------------------|------------|
| **is_truthy** | truthy / falsy | Determines truthiness per ES spec. Falsy: `0`, `NaN`, `""`, `false`, `null`, `undefined`. Everything else is truthy. |
| **strict_equal** | `===` | Equality without type coercion. Promises use `physical_equal` for identity comparison. |
| **loose_equal** | `==` | Equality with type coercion per the Abstract Equality algorithm. |
| **physical_equal** | reference equality | MoonBit identity check. Used for promise self-resolution detection. |
| **SameValueZero** | — | Comparison algorithm used by `Map` and `Set`: like `===` but treats `NaN === NaN` as `true`. |

---

## MoonBit Language

| Term | Aliases / Related | Definition |
|------|-------------------|------------|
| **MoonBit** | — | Statically-typed language that compiles to WebAssembly. The implementation language for this JS engine. |
| **Ref[T]** | mutable reference | MoonBit's mutable box type (e.g., `Ref[Int]`, `Ref[Bool]`), used for counters and shared mutable state in closures. |
| **.mbt** | — | MoonBit source file extension. |
| **moon.mod.json** | — | MoonBit module manifest declaring package name, version, and dependencies. |
