# Bytecode ordinary-call trampoline: ECMAScript evidence

This is bounded research for #631 slice 1. It records only the ordinary-call
semantics a bytecode call/trampoline path must preserve. It makes no package,
representation, or scheduling decision.

## Delta from the executor-neutral activation memo

`executor-neutral-activation-spec-research.md` already records the shared
activation seam: receiver selection, `this` binding, callee environment/realm,
parameter instantiation, and completion cleanup. The #631-specific delta is
the **caller/callee hand-off**: call evaluation must finish in source order
before dispatch, a bytecode caller must later receive the ordinary call's
normal value or the same abrupt value, and arrow calls must retain their
lexical-only distinctions. This memo does not repeat construction, generic
executor-boundary, or package-boundary conclusions from that memo.

## Spec-observable obligations

| Concern | Primary-source evidence | #631 slice-1 consequence |
| --- | --- | --- |
| Call evaluation order | A `CallExpression` first evaluates the callee Reference, obtains its value, then delegates to `EvaluateCall`. `EvaluateCall` derives the receiver from that already-evaluated Reference, evaluates the argument list, validates the function, and only then invokes `Call`. [EvaluateCall](https://tc39.es/ecma262/2026/multipage/ecmascript-language-expressions.html#sec-evaluatecall) | Preserve this order and the preselected receiver; do not enter the callee early or reconstruct a receiver from the function value after argument evaluation. Abrupt callee/argument evaluation must prevent later steps. |
| Ordinary-call admission and lifecycle | ECMAScript function `[[Call]]` creates/prepares a callee context, rejects class-constructor calls in that context, binds `this`, evaluates the body as a Completion, restores the caller context, unwraps a `return`, and propagates a throw. [ECMAScript function `[[Call]]`](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ecmascript-function-objects-call-thisargument-argumentslist) | Runtime semantics must retain callable validation, activation/cleanup ordering, and result-kind handling. A suspended caller cannot observe a body result before callee cleanup/restoration. |
| Activation state, realm, and error identity | `PrepareForOrdinaryCall` gives the callee its function, function realm, script/module, function environment, and private environment; it suspends the caller and makes the callee running. Exceptions produced afterwards are associated with the callee realm. [PrepareForOrdinaryCall](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-prepareforordinarycall) | Runtime-owned state includes the callee realm and active-function context; an abrupt completion must carry the guest-thrown value unchanged, rather than replacing it with a host error or one made in the caller realm. |
| `this` | Lexical `this` skips binding; strict mode preserves the supplied receiver; global mode substitutes the callee realm's global `this` for `null`/`undefined` and boxes other primitives in the callee realm. [OrdinaryCallBindThis](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ordinarycallbindthis) | Runtime must own one-time `this` binding and callee-realm coercion. A trampoline may not apply a second binding when it resumes a call. |
| Parameters, declarations, and `arguments` | `FunctionDeclarationInstantiation` establishes parameter/declaration bindings before body execution; its algorithm chooses mapped versus unmapped `arguments` according to strictness and parameter shape. [FunctionDeclarationInstantiation](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-functiondeclarationinstantiation) | Runtime must perform this exactly once for each admitted activation, before the selected body begins or resumes. |
| Return and normal-result normalization | `return;` produces `ReturnCompletion(undefined)`; `return expr;` evaluates/get-values the expression then produces `ReturnCompletion(exprValue)`. Ordinary `[[Call]]` converts a return completion to its value only after restoring the caller. [ReturnStatement](https://tc39.es/ecma262/2026/multipage/ecmascript-language-statements-and-declarations.html#sec-return-statement) [ECMAScript function `[[Call]]`](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ecmascript-function-objects-call-thisargument-argumentslist) | Preserve `return` as an internal completion until the ordinary-call boundary; deliver its value as the caller expression's normal result only there. Do not turn `return` into a throw-like host unwind. |
| Completion kinds and thrown-value identity | Completion Records distinguish normal, return, and throw (among other abrupt kinds); a throw completion holds the ECMAScript value that was thrown. [Completion Records](https://tc39.es/ecma262/2026/multipage/ecmascript-data-types-and-values.html#sec-completion-record-specification-type) | The cross-call result must distinguish normal value from abrupt completion and preserve the original thrown ECMAScript value identity. |
| Arrow call semantics | Arrow instantiation captures the current lexical and private environments and creates an ordinary function with `lexical-this`; arrows define no local `arguments`, `super`, `this`, or `new.target`. An expression body evaluates to a return completion. [InstantiateArrowFunctionExpression](https://tc39.es/ecma262/2026/multipage/ecmascript-language-functions-and-classes.html#sec-instantiatearrowfunctionexpression) [Arrow ExpressionBody evaluation](https://tc39.es/ecma262/2026/multipage/ecmascript-language-functions-and-classes.html#sec-arrow-function-definitions) | Treat an arrow call as a callable body with lexical receiver/environment behavior, not as an ordinary receiver-binding call. Its expression-body value reaches the caller through the same ordinary return normalization. |
| Arrow non-constructability | Arrow creation calls `OrdinaryFunctionCreate`; that operation creates a function with `[[Call]]` and no `[[Construct]]` unless another operation later adds one. Arrow instantiation performs no such addition. [InstantiateArrowFunctionExpression](https://tc39.es/ecma262/2026/multipage/ecmascript-language-functions-and-classes.html#sec-instantiatearrowfunctionexpression) [OrdinaryFunctionCreate](https://tc39.es/ecma262/2026/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ordinaryfunctioncreate) | Slice 1 must not admit arrow functions through a construction route. This is a call-path constraint, not a request to implement construction. |

## Runtime semantics versus executor-private mechanics

The specification requires an execution context to contain whatever code
evaluation state is necessary to evaluate, suspend, and resume associated code;
it explicitly allows a suspended context to later resume at its prior point.
Its `Function` and `Realm` components determine the active function and current
realm. [Execution Contexts](https://tc39.es/ecma262/2026/multipage/executable-code-and-execution-contexts.html#sec-execution-contexts)

Therefore, source-visible semantics that the runtime must preserve are:

- source-order callee/receiver/argument evaluation and callable failure;
- callee activation, realm, active function, lexical/private environment,
  `this`, parameter/declaration/`arguments` initialization, and cleanup;
- normal-result versus abrupt-result propagation, including thrown-value
  identity; and
- arrow lexical `this`/environment behavior, result normalization, and lack of
  constructability.

The bytecode program counter, operand stack, pending-instruction record,
continuation representation, and the mechanics used to suspend/resume an
executor are implementation-private evaluation state. This classification is
an inference from the execution-context allowance above: it does not prescribe
an architecture, API, or scheduler, and it is valid only while the listed
observable semantics remain intact.
