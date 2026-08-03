# Issue #608: retained-argument slice — ECMAScript research

## Scope and source

This note records facts relevant to the exact #616 program:

```js
function step(n, x) {
  if (n === 0) return x;
  return 1 + step(n - 1, x);
}
step(256, (0, /* ... */, 7));
```

The specification links below are to the current TC39 ECMA-262 draft, read on
2026-08-03. “Normative” describes the required ECMAScript behaviour. “Baseline
source” describes merged main `05d9e32b` as checked out by the dedicated #786
worktree before #790; it is not a claim about the retained-argument slice
implemented by #790. The root checkout was older during the first research
pass, so all source-boundary facts below were re-verified against that newer
checkpoint.

## Normative requirements

### Call evaluation and argument-list order

**Normative.** A normal call evaluates the callee reference and gets its value
before it evaluates its arguments. `EvaluateCall` then obtains the receiver
from that reference, evaluates the argument-list node, verifies callability,
and invokes `Call` with the resulting list.
[ECMA-262 §13.3.6.2, EvaluateCall](https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#sec-evaluatecall)

**Normative.** `ArgumentListEvaluation` builds a list of values. For a
non-spread argument it evaluates the expression and applies `GetValue`; for a
multi-argument list it evaluates the preceding list before the later argument.
Consequently `step(256, commaExpression)` must evaluate `256` completely before
the comma expression, and a later argument must not start when an earlier one
abruptly completes. The spread productions additionally obtain an iterator and
exhaust it before proceeding to a later argument.
[ECMA-262 §13.3.8.1, ArgumentListEvaluation](https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#sec-runtime-semantics-argumentlistevaluation)

**Implementation inference.** An accelerated admission path for this source
may consume an already-evaluated two-element argument list. It must not move
the `step` lookup, `256` evaluation, or evaluation of `(0, ..., 7)` past the
function-call boundary, and it must preserve an abrupt completion from any of
those operations.

### Comma expression

**Normative.** For `left, right`, evaluation first evaluates `left` and calls
`GetValue(leftRef)`, then evaluates `right` and returns `GetValue(rightRef)`.
The discarded left value is still required to be obtained because that can be
observable. A nested comma chain therefore evaluates every leading literal or
expression in source order and returns only the final `7` value.
[ECMA-262 §13.16.1, Comma Operator Evaluation](https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#sec-comma-operator)

**Implementation inference.** After normal expression evaluation has produced
the second argument, the activation loop can retain that resulting `Value` as
`x`; it must not represent the comma AST as a deferred computation or evaluate
its discarded operands again for each recursive activation.

### Ordinary function call, binding, and body completion

**Normative.** An ECMAScript function's `[[Call]]` prepares an ordinary call
context, binds `this`, evaluates its body, removes the callee context, and
returns the body result. For an ordinary function body,
`OrdinaryCallEvaluateBody` performs `FunctionDeclarationInstantiation` with the
already-created argument list before evaluating the function body.
[ECMA-262 §10.2.1, ECMAScript Function Objects `[[Call]]`](https://tc39.es/ecma262/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ecmascript-function-objects-call-thisargument-argumentslist)
[ECMA-262 §10.2.1.4, OrdinaryCallEvaluateBody](https://tc39.es/ecma262/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ordinarycallevaluatebody)

**Normative.** `FunctionDeclarationInstantiation` gives each formal parameter
the corresponding indexed argument value, or `undefined` if the list is too
short, and creates/initializes the parameter bindings before body execution.
For this simple parameter list the observable bindings at each activation are
therefore `n = supplied first argument` and `x = supplied second argument`.
[ECMA-262 §10.2.11, FunctionDeclarationInstantiation](https://tc39.es/ecma262/multipage/ordinary-and-exotic-objects-behaviours.html#sec-functiondeclarationinstantiation)

**Normative.** `return expression;` evaluates the expression, gets its value,
and produces `ReturnCompletion(value)` (with the async-only await adjustment
irrelevant to this ordinary function). The function-call machinery turns that
return completion into the call's value; a normal fall-through has the
ordinary-function-body result instead.
[ECMA-262 §14.10.1, ReturnStatement Evaluation](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html#sec-return-statement)
[ECMA-262 §10.2.1.4, OrdinaryCallEvaluateBody](https://tc39.es/ecma262/multipage/ordinary-and-exotic-objects-behaviours.html#sec-ordinarycallevaluatebody)

**Implementation inference.** Retaining `x` in a numeric-recursion activation
record is sound only if every logical activation behaves as though it received
the previously evaluated value in a fresh call's second parameter binding.
The base activation must return that exact `Value`, and each pending caller
must receive the resulting return value as its recursive-call result.

### Addition evaluation

**Normative.** A binary additive expression evaluates and gets the left operand
before it evaluates and gets the right operand, then invokes
`ApplyStringOrNumericBinaryOperator`. For `+`, that operation performs
`ToPrimitive` on the left value before the right value, selects string
concatenation if either primitive is a String, otherwise converts both through
`ToNumeric` and requires matching numeric types.
[ECMA-262 §13.8.1, Additive Operators Evaluation](https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#sec-additive-operators)
[ECMA-262 §13.15.3, ApplyStringOrNumericBinaryOperator](https://tc39.es/ecma262/multipage/ecmascript-language-expressions.html#sec-applystringornumericbinaryoperator)

**Implementation inference.** In the exact workload, the left operand is the
primitive literal `1`, but the recursive call is still the right operand and
its completion must be obtained before the addition occurs. An admission rule
that is generalized beyond literal numeric `x` must not replace the specified
`+` coercion/abrupt-completion behaviour with raw host-number arithmetic.

## Baseline source boundaries before #790

- `eval_args_with_spread` in
  [`interpreter/runtime/call.mbt`](../../interpreter/runtime/call.mbt) evaluates
  argument expressions in stored order. Its spread arm exhausts the iterator
  before advancing to the next argument. This remains the legacy argument-list
  boundary.
- The `Comma` arm in
  [`interpreter/runtime/eval_expr.mbt`](../../interpreter/runtime/eval_expr.mbt)
  delegates to `eval_direct_comma` in
  [`interpreter/runtime/eval_comma.mbt`](../../interpreter/runtime/eval_comma.mbt).
  That helper uses an explicit LIFO worklist for comma nodes, observes each
  nested node, evaluates every non-comma leaf through `eval_expr`, and returns
  the last value.
- `prepare_user_func_activation` in
  [`interpreter/runtime/call.mbt`](../../interpreter/runtime/call.mbt) is shared
  by legacy `UserFunc` execution and the resumable activation shell. It binds
  positional parameters from the already-evaluated `args` array, using
  `Undefined` when an argument is absent, before hoisting the body.
- `Interpreter::run` classifies a root through
  `classify_activation_dispatch_root_program`. Exact admitted roots execute via
  `run_activation_dispatch_root_program`; every other root still uses the
  recursive `exec_stmt` / `eval_expr` tree-walker path.
- Before #790, the numeric admission in
  [`interpreter/runtime/activation_dispatch_admission.mbt`](../../interpreter/runtime/activation_dispatch_admission.mbt)
  accepts exactly one formal parameter, one root argument, and one recursive
  argument. `enter_numeric_call` in
  [`interpreter/runtime/activation_dispatch_shell.mbt`](../../interpreter/runtime/activation_dispatch_shell.mbt)
  likewise requires one numeric `Value`. `DispatchNumericExpression` currently
  represents one parameter and single-argument calls only.
- #790 extends that closed family with exactly two numeric parameters, an
  iterative one-grouping comma-tree classifier, and explicit two-argument
  call/retained-parameter continuations. The broader call and expression
  surface remains on the legacy path under #608.
- Call arguments are parsed at assignment-expression precedence, so the
  parenthesized comma operand in #616 is represented as one `Grouping` around
  the comma tree. At runtime `eval_expr` observes that Grouping before entering
  the comma worklist. The exact closed argument therefore has 528 engine
  expression observations: one Grouping, 263 Comma nodes, and 264 Number
  literals.

These source observations identify the narrow #616 gap: the direct comma
worklist already removes comma-node host recursion, and generic activation
preparation already knows how to bind multiple positional arguments, but the
managed numeric recipe excludes the retained second parameter and therefore
routes the mixed program back to the legacy recursive call path.

## Invariant checklist for Sol

- Resolve/get the callee before evaluating either argument.
- Evaluate arguments left-to-right, fully expanding any spread before the next
  argument; propagate the first abrupt completion.
- Evaluate every comma-left operand through value retrieval once, in source
  order, and retain only the final comma value.
- Bind each logical activation's `n` and `x` from the already-evaluated argument
  values; retain the `x` `Value` without reevaluation or conversion.
- On the base case, return the retained `x` value exactly.
- On unwinding, evaluate/apply `1 + recursiveResult` only after the recursive
  call completes, preserving the specified `+` semantics and abrupt behaviour.
