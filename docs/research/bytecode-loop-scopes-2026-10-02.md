# Bytecode lexical for loops

Ordinary identifier `let` and `const` declarations in a C-style `for` header
can now use bytecode execution. This builds on the block-scope work in #1059.

## Environment lifetime

The loop enters a lexical environment before evaluating its initializer. All
header bindings exist in the temporal dead zone until their declarations
initialize them. Lowering hides same-named activation slots throughout the
initializer, condition, body, and update expression, and restores those slot
mappings after the loop.

For `let`, execution copies the initialized header values into fresh binding
cells before the first condition and after each continuing body completion,
before the update expression. Each new environment has the same outer
environment. Initializer closures retain the original cells; body and condition
closures retain their iteration's cells. Updating the next iteration does not
change an earlier closure's binding.

For `const`, the header uses one immutable environment and no per-iteration
copies. Assignment continues to raise a TypeError through the runtime binding
operations.

Block and loop lowering share scope entry and exit. The existing completion
unwind restores the outer environment on normal exit, break, return, and throw.
A finally may replace an exit with a continue; the next iteration's cells are
created only after the finally finishes.

The verifier admits iteration-environment creation only within the innermost
active lexical scope with a nonempty set of `let` bindings. Ordinary region
ancestry and resource checks still apply.

These rules follow [ForLoopEvaluation, ForBodyEvaluation, and
CreatePerIterationEnvironment](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html#sec-for-statement).

## Validation and boundaries

The minimal closure test failed before implementation because the enclosing
function selected the tree executor. Regression tests assert both JavaScript
results and private evidence that the enclosing function ran bytecode. Named
cases cover initializer, condition, body, and update closures; multiple bindings;
TDZ; const assignment; shadowed activation slots; and finally and labeled exits.
Malformed bytecode tests cover absent scopes, const scopes, and an intervening
catch handler. Explicit bytecode script execution also covers direct eval in the
active iteration environment.

The full default-target and JS test suites pass. The four new test blocks pass
on JS, native, Wasm, and Wasm GC. Strict all-target checking passes, and public
interfaces are unchanged. Node.js agrees with all fifteen named cases.
The complete architecture audit passes, including semantic-edge, typed AST,
destructuring-plan, and continuation-ownership self-tests.

Destructuring declarations, lexical for-in and for-of binding, generator/async
execution, and existing unsupported instruction admission remain separate work.
No performance improvement is claimed.

The local Test262 regression subset uses revision `2b2ecead6e82` and selects
156 files directly under `language/statements/for`, `let/syntax`, and
`const/syntax`. The baseline is main at `a7f4121a9042759019d17467f8412515942cca81`;
both engines use release JS builds and the native authoritative runner. Every
per-file outcome is unchanged. This subset checks the current public execution
path; the route assertions above separately establish the new bytecode coverage.

| Mode | Passed / Executed, before and after | Passed / Discovered, before and after | Skipped | Existing failures | New regressions |
| --- | --- | --- | --- | --- | --- |
| strict | 136 / 143 | 136 / 147 | 4 | 7 | 0 |
| non-strict | 143 / 151 | 143 / 151 | 0 | 8 | 0 |
