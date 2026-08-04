# Tree-walker binary-expression evaluation research

## Scope and premise

This note records the ECMAScript requirements relevant to a common tree-walker
driver for the left-associated expression `a() + b() + c()`. It does not
recommend expanding the currently admitted value domain.

## Required order

`AdditiveExpression` is left-recursive, so the program parses as
`(a() + b()) + c()`. The addition production delegates to
[`EvaluateStringOrNumericBinaryExpression`](https://tc39.es/ecma262/#sec-evaluatestringornumericbinaryexpression).
That shared algorithm does the following in order: evaluate the left syntax,
`GetValue` its result, evaluate the right syntax, `GetValue` its result, and
only then apply `ToPrimitive` to the left and right values. The addition
production itself is specified [here](https://tc39.es/ecma262/#sec-addition-operator-plus-runtime-semantics-evaluation).

Consequently, with no abrupt completion, the observable sequence is:

1. Evaluate and `GetValue` `a()`; evaluate and `GetValue` `b()`.
2. Apply `ToPrimitive` to the two inner operands, then execute the inner `+`.
   For a non-string addition, the driver applies `ToNumeric` to the two
   primitive values, rejects differing numeric types, and performs the numeric
   operation.
3. Evaluate and `GetValue` `c()`.
4. Apply `ToPrimitive` to the inner result and to `c()`'s value, then perform
   the outer `+` using the same string-or-numeric branch.

The specification's general algorithm convention also explicitly makes complex
expressions left-to-right and inside-to-outside
([§5.2.1](https://tc39.es/ecma262/#sec-evaluation-order)). An explicit
`Work`/continuation representation must therefore capture the completed left
value and schedule the right expression; it must not start the right expression
before the left has completed and been dereferenced.

## `GetValue`, conversion, and abrupt completions

`GetValue` is semantically required even when a host implementation might
already hold a value: a Reference Record can perform environment lookup or a
property get, and that operation can be observable or abrupt. See
[`GetValue`](https://tc39.es/ecma262/#sec-getvalue). The shared binary driver
uses `?` for each evaluation, `GetValue`, and conversion step. Per
[§5.2.4.3](https://tc39.es/ecma262/#sec-shorthands-for-unwrapping-completion-records),
`?` propagates an abrupt completion immediately. Thus an abrupt result from
`a()` or its `GetValue` prevents `b()` and `c()`; one from `b()` or its
`GetValue` prevents conversion and `c()`; and conversion failure after the
inner pair prevents `c()`.

`ToPrimitive` is called after *both* operand values have been acquired. It can
call `%Symbol.toPrimitive%`, `valueOf`, or `toString`, and can throw; see
[`ToPrimitive`](https://tc39.es/ecma262/#sec-toprimitive). For a non-string
operation, `ToNumeric` follows `ToPrimitive` and may produce Number or BigInt
or throw ([`ToNumeric`](https://tc39.es/ecma262/#sec-tonumeric)). Therefore a
driver must not move primitive/numeric conversion ahead of right-operand
evaluation, nor interchange the two conversion calls.

## Why exact numeric-only admission is a useful seam

If the common driver is admitted only when the actual left and right results
are already Number values, it can preserve the evaluation/`GetValue` ordering
above and perform Number addition without implementing object coercion, string
concatenation, BigInt handling, mixed-numeric TypeErrors, or user-observable
`ToPrimitive` calls. This is an intentionally narrower implementation scope,
not a different interpretation of the specification. Admission must be exact:
accepting objects, strings, BigInts, or a broad "numeric-like" category would
silently take responsibility for the conversion and error behaviour described
above.

## Error and source-observation constraints for a work plan

The specification fixes completion ordering and propagation, but does not
standardize an implementation's diagnostic source-location presentation. The
plan should nonetheless preserve these observations:

- Bubble an existing abrupt completion unchanged through every pending binary
  continuation; do not replace a child throw with an operator error.
- If the implementation itself rejects an unsupported operand/operator, retain
  the binary operator's source location in the work item so the failure remains
  attributable to that operation.
- Keep the child expression's own location attached to failures raised while
  evaluating or dereferencing the child. In particular, a left-child failure
  must remain the first observed failure and must suppress right-child work.
- Preserve the same source location across suspension/resumption; a continuation
  carrying only values and no operation/span cannot faithfully construct a
  later operator-originated error.

The first two constraints follow from the `?` completion convention and the
ordered shared binary algorithm; the source-location details are implementation
observations to pin with tests rather than ECMAScript-defined metadata.

## Primary sources

- ECMAScript, [Addition operator evaluation](https://tc39.es/ecma262/#sec-addition-operator-plus-runtime-semantics-evaluation)
- ECMAScript, [EvaluateStringOrNumericBinaryExpression](https://tc39.es/ecma262/#sec-evaluatestringornumericbinaryexpression) and [ApplyStringOrNumericBinaryOperator](https://tc39.es/ecma262/#sec-applystringornumericbinaryoperator)
- ECMAScript, [Evaluation order](https://tc39.es/ecma262/#sec-evaluation-order) and [completion shorthand](https://tc39.es/ecma262/#sec-shorthands-for-unwrapping-completion-records)
- ECMAScript, [`GetValue`](https://tc39.es/ecma262/#sec-getvalue), [`ToPrimitive`](https://tc39.es/ecma262/#sec-toprimitive), and [`ToNumeric`](https://tc39.es/ecma262/#sec-tonumeric)
- Test262, [left operand abrupt completion](https://github.com/tc39/test262/blob/main/test/language/expressions/addition/S11.6.1_A2.4_T2.js) and [ToPrimitive abrupt sequencing](https://github.com/tc39/test262/blob/main/test/language/expressions/addition/coerce-symbol-to-prim-err.js)
