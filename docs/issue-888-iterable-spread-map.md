# Issue #888 iterable-spread responsibility map

This map records the source-verified implementation boundary used by #888.
The branch starts at `22ddc9925869f8da72c6ddb71398033673e7ceea`.

## Preserved assumptions

1. The stable `Engine` default remains Tree-walker; candidate routing is the only bytecode consumer.
2. Runtime owns all observable iterator protocol work; compiler/VM carry only evaluated values and concrete sinks.
3. Completion returns one owned, closed batch and each VM sink appends it exactly once.

## Lowering and callers

`BytecodeBuilder::compile_dynamic_args` emits `StartArgs`, `ArgPushValue`, and
`ArgPushSpread`. Its consumers are:

- `emit_call` for plain calls, ending in `CallSpread`;
- `emit_call_with_receiver` for property, method, optional, and chain calls,
  ending in `CallSpreadWithReceiver`;
- `emit_construct` for `new`, ending in `ConstructSpread`;
- the direct-eval branch in `compile_expr`, ending in `CallDirectEval`.

Array literals have a separate `StartArray` / `ArrayPushValue` /
`ArrayPushHole` / `ArrayPushSpread` sequence. `compile_call_args` dispatches
to the shared dynamic-argument path whenever any argument is a spread, so
admitting `ArgPushSpread` would otherwise admit constructor spread too.

## Reachable values

The spread operand is any runtime `Value`: `Array`, `String_`, ordinary or
callable `Object`, `Proxy`, `Map`, `Set`, `Iterator`, `Undefined`, `Null`, and
other primitives. The iterator protocol can therefore enter guest code through
`Symbol.iterator` lookup/call, `next` lookup/call, `done` lookup/ToBoolean,
`value` lookup, and nested Proxy operations. Every call receiver is the value
whose method was retrieved (`iterable` for `@@iterator`, `iterator` for
`next`).

## Runtime owners and lifetime

The legacy owner is `Interpreter::spread_iterable` in
`interpreter/runtime/call.mbt`; it delegates lookup, calls, validation,
truthiness, and errors to existing runtime helpers. The managed operation must
compose those helpers in a private frame with phases for acquisition, next
lookup/call, result validation, done, and value. The frame is held by the
executor-neutral activation stack and receives child completions without
exposing a VM callback or sink.

`ExecutorIterableSpreadRequest` contains only the evaluated iterable and source
location. Its closed result contains only an owned `Array[Value]`; the VM wraps
that result in `AppendArraySpread` or `AppendArgumentSpread` pending
destinations. Normal completion appends once; abrupt completion preserves prior
effects and does not append a partial batch. No `IteratorClose` is introduced.

## Admission and exclusions

`ArrayPushSpread` and `ArgPushSpread` graduate to `ManagedSuspension` only with
the request/frame in place. `ConstructSpread` becomes typed
`UnsupportedBeforeActivation(ConstructSpread)` (or the existing typed
construction-specific reason); `CallDirectEval`, `ObjectSpread`,
destructuring/rest, `for-of`, async iteration, and default routing remain
unsupported or unchanged. The explicit own `Array[Symbol.iterator] = undefined`
case must be handled by the canonical legacy/runtime acquisition owner so it
raises the ordinary iterable TypeError instead of taking a built-in fast path.
