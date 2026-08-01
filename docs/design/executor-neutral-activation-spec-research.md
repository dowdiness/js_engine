# Executor-neutral activation seam: ECMAScript evidence

This memo is bounded research for #637. It records the observable activation
semantics that an executor-neutral seam must preserve; it does **not** select a
representation or package boundary.

## Primary sources

All links below are stable section links into the ECMAScript 2026 language
specification (ECMA-262), maintained by TC39.

- [EvaluateCall](https://tc39.es/ecma262/2026/multipage/ecmascript-language-expressions.html#sec-evaluatecall)
  evaluates the callee Reference, obtains its value, evaluates arguments, and
  dispatches with either the Reference's `thisValue` or `undefined`.
- [Call](https://tc39.es/ecma262/2026/multipage/abstract-operations.html#sec-call)
  checks `[[Call]]` and invokes it with the supplied receiver and argument
  list; [Construct](https://tc39.es/ecma262/2026/multipage/abstract-operations.html#sec-construct)
  separately checks `[[Construct]]` and passes `newTarget`.
- [ECMAScript function `[[Call]]`](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ecmascript-function-objects-call-thisargument-argumentslist),
  [PrepareForOrdinaryCall](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-prepareforordinarycall),
  [OrdinaryCallBindThis](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ordinarycallbindthis),
  and [OrdinaryCallEvaluateBody](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ordinarycallevaluatebody)
  specify the ordinary-function activation sequence.
- [ECMAScript function `[[Construct]]`](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ecmascript-function-objects-construct-argumentslist-newtarget),
  [OrdinaryCreateFromConstructor](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ordinarycreatefromconstructor),
  and [GetPrototypeFromConstructor](https://tc39.es/ecma262/2026/multipage/abstract-operations.html#sec-getprototypefromconstructor)
  specify allocation, prototype/realm fallback, and constructor completion.
- [GetThisValue](https://tc39.es/ecma262/2026/multipage/abstract-operations.html#sec-getthisvalue)
  specifies Reference receiver extraction. [FunctionDeclarationInstantiation](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-functiondeclarationinstantiation)
  performs parameter, declaration, and `arguments` setup before body execution.
- [Function Environment Records](https://tc39.es/ecma262/2026/multipage/executable-code-and-execution-contexts.html#sec-function-environment-records),
  [Execution Contexts](https://tc39.es/ecma262/2026/multipage/executable-code-and-execution-contexts.html#sec-execution-contexts),
  [Realms](https://tc39.es/ecma262/2026/multipage/executable-code-and-execution-contexts.html#sec-code-realms),
  and [Completion Records](https://tc39.es/ecma262/2026/multipage/ecmascript-data-types-and-values.html#sec-completion-record-specification-type)
  define the context, realm, and completion state that crosses an activation.

## Semantic obligations at the seam

| Concern | Evidence | Obligation inferred for a split activation |
| --- | --- | --- |
| Call receiver | `EvaluateCall` obtains `thisValue` from the callee Reference; `Call` receives it separately from arguments. | Preserve the already-selected receiver, including property-reference receivers. Do not reconstruct it from the function value after dispatch. |
| Strict/sloppy `this` | `OrdinaryCallBindThis` uses `[[ThisMode]]`; lexical mode skips binding, strict keeps the supplied value, and global mode substitutes the global `this` for `null`/`undefined` and boxes primitives. | The activation setup that chooses/binds `this` must remain single-shot and occur before body execution, independent of which executor runs the body. |
| Lexical environment and `new.target` | `PrepareForOrdinaryCall` creates a Function Environment Record from the function's `[[Environment]]`, installs `newTarget`, and pushes the callee execution context. | Closure environment, private environment, `this` binding status, and `new.target` are activation state, not optional executor-local conveniences. |
| Parameters and `arguments` | `FunctionDeclarationInstantiation` runs before ordinary body evaluation and creates parameter bindings, declarations, and the mapped/unmapped `arguments` object as applicable. | Parameter/default/destructuring semantics and arguments aliasing must be initialized exactly once per activation before either body executor resumes. |
| Construct path | `[[Construct]]` allocates a base-constructor receiver via `OrdinaryCreateFromConstructor`, binds it, initializes instance elements, then evaluates the body. It returns an object body result; otherwise base constructors return the allocated receiver, while derived constructors require `undefined` and retrieve their initialized `this`. | Keep call and construct admission distinct. Preserve `newTarget`, allocation/prototype choice, derived-`this` timing, instance initialization, and constructor-result substitution across the seam. |
| Prototype and realm | `GetPrototypeFromConstructor` reads `constructor.prototype`; when that is not an object it falls back to the intrinsic default prototype of `GetFunctionRealm(constructor)`. | Realm-sensitive intrinsic fallback and prototype lookup must stay attached to construction setup; moving body execution must not silently use the caller/current executor realm. |
| Normal/abrupt outcome and cleanup | Ordinary `[[Call]]` and `[[Construct]]` install a callee context, run evaluation as a Completion, then remove the context and restore the caller before propagating abrupt completion or normalizing `return`. | Any handoff must carry completion kind/value, ensure exactly-once activation cleanup/restoration, and not convert a guest throw/return into a host-only control path. |

## Ownership boundary suggested by the specification

This is a semantic grouping, **not** a proposed #637 API.

- **Runtime-owned activation contract:** callable/constructability validation;
  receiver and argument list selected by evaluation; `this` mode and binding;
  closure/lexical/private environments; `new.target`; execution-context and
  realm association; parameter/`arguments` instantiation; constructor
  allocation/result rules; and completion/cleanup propagation. These govern
  observable call/construct behaviour before or after the source body itself.
- **Executor body state:** the selected function's ECMAScript code plus the
  resumable program counter, operand/control state, and body-local evaluation
  machinery necessary to execute `EvaluateBody`. It must consume the prepared
  activation rather than recreate the runtime-owned setup.

## Limits and explicit inferences

- ECMA-262 specifies an abstract execution-context stack, not this project's
  interpreter/bytecode package layout. The ownership grouping above is an
  inference from the ordering and inputs/outputs of the cited algorithms.
- The sources establish ordinary ECMAScript function semantics. Built-ins,
  bound functions, proxies, generators, async functions, and host callbacks
  have additional internal-method algorithms and need their own admission work;
  this memo does not claim they can all share the same initial seam unchanged.
- The memo does not decide whether the code body is represented by a callback,
  opaque handle, request object, or another form. Any option remains acceptable
  only if it preserves the obligations above and does not leak executor-private
  state into the runtime contract.
