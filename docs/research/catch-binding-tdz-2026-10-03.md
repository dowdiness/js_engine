# Catch binding TDZ prerequisite

Baseline: `905a0193b8127b3b173b314140eecb18c2c14dd2`.
Fixed criteria: [#1071](https://github.com/dowdiness/js_engine/issues/1071).
This is a correctness prerequisite for shared BindingInitialization under
[#1042](https://github.com/dowdiness/js_engine/issues/1042).

## Problem and change

Catch defaults and computed keys can read outer same-name values because the
catch's bindings are created one at a time during initialization. For example,
with outer `later = 42`, `catch ([first = later, later])` reaches the body on
the baseline. The required result is ReferenceError before the body.

[CatchClauseEvaluation](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html#sec-runtime-semantics-catchclauseevaluation)
creates every catch BoundName before BindingInitialization. The change
predeclares all those names as uninitialized mutable cells in the existing fresh
catch environment, then invokes the existing binding operation. The same cells
are initialized in order and retained by escaped closures. Existing binding
failure, iterator cleanup and finally handling keep their ownership.

The native baseline reproduction returns `[["body","finally"],42]`; Node
returns `[["finally","ReferenceError"],42]`. The initial regression actually
failed before the runtime change. The saved red log records one test, zero
passes and one failure.

## Scope and evidence

The source change is confined to catch-entry preparation. Declaration and
parameter policies, public interfaces, Bytecode admission, skip decisions and
CI are unchanged. Pattern catch remains selected as Tree before execution;
this fix does not complete the prepared Bytecode binding consumer.

Six focused behavioral tests cover:

- self/forward reads and a rest-bound name before initialization;
- object defaults and computed keys;
- a successful direct default read of an earlier initialized cell and an
  escaped closure over both cells;
- closures escaping partial initialization, with the later cell still in TDZ;
- one IteratorClose on initialization failure, original ReferenceError winning
  over a throwing iterator return, and finally preceding the outer catch.

The tests assert values, error category and effect order through the existing
Tree/candidate helper. They do not assert opcode layout or mutable internals.
Independent review caught the missing direct earlier-binding read in the
initial positive fixture. That fixture was strengthened without adding another
test or changing the implementation.

The final focused tests pass 6/6 separately on JS, native, Wasm and WasmGC.
After the review adjustment, the full default suite passes 4,471/4,471 and
the JS suite passes 4,473/4,473. Strict all-target checking, interface/format
checks, diff checks and the full architecture audit pass; generated public
interfaces are unchanged. Independent Terra review passes. Final PR evidence
must record the reviewed, rebased CI head. Local test results are regression evidence, not a conformance rate.

## Remaining work

Prepared default/computed expression execution needs its own representation,
verification and caller-environment contract before Stage 2 is runnable.
The independent binding object-rest copy defect is tracked separately under
[#1072](https://github.com/dowdiness/js_engine/issues/1072). Neither prerequisite
authorizes a default-executor or public API change.
