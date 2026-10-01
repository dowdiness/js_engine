# Bytecode block scopes

This change starts the lexical-scope work tracked by #385. It admits ordinary
identifier `let` and `const` declarations in blocks, including blocks within
existing loops, labels, and try/catch/finally statements.

## Execution model

Lowering collects the block's lexical declarations and temporarily hides
same-named activation slots while compiling that block. References then resolve
through its environment. The original slot mappings are restored when lowering
continues outside the block.

A lexical scope uses the existing completion-handler stack. It has a protected
body and no catch or finally body. Entry creates a fresh runtime environment and
uninitialized bindings. Exit restores the saved environment and passes the
pending completion outward unchanged. An enclosing finally can still replace
that completion. No separate scope-unwinding engine is introduced.

The region's entry instruction identifies the static scope. Its runtime
environment is a separate instance on each entry. Closures retain runtime
binding cells after the enclosing block exits.

The control-flow verifier checks region ancestry, forbids bypassing entry, and
rejects transfers into sibling scopes. A scope entry has only a fallthrough
successor; it is not an exception handler destination.

These choices follow [Block evaluation and BlockDeclarationInstantiation](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html#sec-block-runtime-semantics-evaluation).
Runtime environment operations continue to own TDZ, initialization, and const
assignment semantics.

## Boundaries

Lexical loop headers, per-iteration loop-header bindings, switch declarations,
block function declarations, destructuring declarations, and for-of remain
separate work. Existing direct-eval and for-in activation selection is retained.
Explicit bytecode script execution is tested for eval access to the active block
and enumeration when finally replaces a break with a continue.

There is no performance claim. Scope entry currently saves the same execution
resources as other completion handlers, including live enumeration state.

## Validation notes

The regression test first failed because the function used the tree executor.
The tests now check JavaScript results and private evidence of bytecode execution,
plus malformed region transfers. Declaration conflicts are checked before body
effects.

- `moon check --target all --deny-warn` and the normal strict check pass.
- Full default-target suite: 4,373 passed; full JS suite: 4,375 passed.
- The five scope tests pass on JS, native, Wasm, and Wasm GC.
- Node.js agrees with all eleven binding/completion examples.
- `moon info` produces no public interface changes; formatting and diff checks pass.
- State, import, representation, semantic-edge, AST-boundary,
  destructuring-plan, and continuation-ownership audits pass without
  command-line warning overrides.

The installed toolchain is moon 0.1.20260920 / moonc v0.10.14+7d59c7ec9.
The prerequisite compiler compatibility fix is
[PR #1058](https://github.com/dowdiness/js_engine/pull/1058). Both the baseline
and the block-scope candidate include that fix.

The local Test262 regression subset uses revision `2b2ecead6e82` and selects
`language/statements/block`, `let`, and `const`. Every per-file outcome is
unchanged. These semantics previously used the tree executor, so unchanged
conformance results accompany the expanded bytecode execution path.

| Mode | Passed / Executed, before and after | Passed / Discovered, before and after | Skipped | Existing failures | New regressions |
| --- | --- | --- | --- | --- | --- |
| strict | 291 / 297 | 291 / 299 | 2 | 6 | 0 |
| non-strict | 293 / 299 | 293 / 299 | 0 | 6 | 0 |
