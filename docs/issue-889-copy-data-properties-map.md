# Issue #889 CopyDataProperties responsibility map

This map records the source-verified implementation boundary for #889. The
branch starts at `4f036ec6eb99e07356f034a93e0eca94094be9eb` and follows the
accepted #383 object-spread matrix.

## Preserved assumptions

1. Stable `Engine` routing and the public API remain unchanged; only candidate
   bytecode admission changes.
2. Runtime owns observable property operations and private continuation state;
   compiler/VM carry evaluated values and one concrete completion destination.
3. Object spread is the only admitted consumer; object rest/destructuring and
   #890 remain Tree-walker paths.

## Current lowering and consumers

`BytecodeBuilder::compile_object_lit` lowers each spread property as
`StartObject -> source -> ObjectSpread(loc)`. `ObjectSpread` currently has a
typed `UnsupportedBeforeActivation(ObjectSpread)` contract and the VM pops
the source before synchronously calling
`Interpreter::copy_object_spread_properties(target, source, loc)`.

The same runtime helper is also called by the Tree-walker object-literal path
in `Interpreter::eval_expr`. Object-rest/destructuring has separate consumers
in `runtime/destructuring.mbt` and must not be redirected to this operation.

## Semantic owners and may-call-user-code paths

The existing helper delegates to these canonical owners:

- `Interpreter::own_property_keys` / `proxy_own_property_keys`: own-key
  snapshot, `ownKeys` trap, array-like result length/index reads, duplicate and
  Proxy invariants;
- `Interpreter::get_own_property` / `proxy_get_own_property`: descriptor
  lookup, `getOwnPropertyDescriptor` trap, descriptor conversion and
  invariants;
- `get_computed_property` and the executor property-get activation: source
  `[[Get]]`, accessors, and nested Proxy `get` dispatch;
- `define_own_property` / ordinary target definition: incremental
  `CreateDataProperty` with no batched VM writes.

Guest entry can occur during `ownKeys` trap lookup/call, array-like trap
result `length`/indexed reads, nested Proxy target checks, descriptor trap
lookup/call and descriptor getters, source getters, and source Proxy `get`.
The operation must snapshot keys once, then process each key as exclusion,
`[[GetOwnProperty]]`, enumerable check, `[[Get]]`, and one data-property
creation, retaining prior writes on abrupt completion.

## Lifetime and completion boundary

`ExecutorCopyDataPropertiesRequest` owns the source, target, immutable copied
excluded keys, and source location. Its private frame owns the key snapshot,
current key index, and one in-flight property operation. It returns a closed
normal value only as an internal completion token; the VM destination performs
no stack change because the target remains on top. No generic sink callback,
compiler type, replay, fallback, post-start route change, or `IteratorClose`
analogue is introduced.

## Scope exclusions

Only object-literal spread is admitted. Object rest/destructuring,
`Object.assign`, `for-in`/`for-of`, array/call/constructor spread, default
routing, public `Engine` API changes, and #890 are out of scope.
