# Stage B.2 — `[[GetOwnProperty]]` + `[[DefineOwnProperty]]` dispatchers

**Status**: post-Codex-review draft (v2) — 5 blockers + 4 concerns addressed inline below
**Depends on**: Stage B.1 (PR #69, landed)
**Retires**: three B.1 approximations flagged as `B.2:` comments in `interpreter/runtime/property.mbt`
**Estimated test262 delta**: +35–45 Proxy tests (from agent-todo.md line ~526)

---

## Goal

Centralize the two read-side and write-side ordinary-method dispatchers that Stage B.1 left inlined or Object-only:

1. `[[GetOwnProperty]]` — ES §10.1.5 (ordinary), §10.4.2.1 + §10.4.2.4 (array length/indexed exotics), §10.5.5 (proxy).
2. `[[DefineOwnProperty]]` — ES §10.1.6, §10.4.2.1, §10.5.6.

Current state: `Object.defineProperty` and `Reflect.defineProperty` each inline 300+ lines of per-variant descriptor logic and silently unwrap Proxy targets. `getOwnPropertyDescriptor` on Array/Map/Set/Promise silently returns `undefined`. Trap-aware Proxy paths don't exist for either method.

## Non-goals

- Revisiting `[[Set]]` semantics (Stage B.1's scope).
- Array migration to `bag`-backed storage (Stage C).
- Any spec change that reshapes descriptor representation.

## Codex review findings (2026-04-22)

Five blockers + four concerns surfaced during pre-implementation validation. Addressed below:

1. **[BLOCKER] `PropDescriptor` surface can't express VAP inputs.** Current struct has non-optional `writable/enumerable/configurable` Bools, no `value` slot, and `Value?` getter/setter conflates "absent" with "None-valued". §10.1.6.3 ValidateAndApplyPropertyDescriptor needs each field to be independently absent-or-present. **Fix**: introduce a new `PartialDescriptor` type for VAP inputs (see §"New type" below). Don't touch `PropDescriptor` — it continues to represent *stored* descriptors on objects.

2. **[BLOCKER] Folding `existing_receiver_desc_blocks` into VAP is wrong.** §10.1.9.2 step 3.e blocks BEFORE calling `[[DefineOwnProperty]]`; VAP on a configurable accessor would allow replacement, changing observable `Reflect.set` behavior. **Fix**: keep `existing_receiver_desc_blocks` as a `[[Set]]`-landing rule in `define_value_on_receiver`. Do NOT fold it.

3. **[BLOCKER] `array_set_length` must partially truncate.** §10.4.2.4: delete indices descending; on first non-configurable failure, STOP at `failedIndex + 1`, set `writable:false` if requested, return `false`. **Fix**: design's `array_set_length` updated below.

4. **[BLOCKER] Array per-index descriptor state under-specified.** Need authoritative descriptor storage for Array indexed elements to support `Object.defineProperty(arr, "0", {configurable:false})`. Array currently stores only `elements: Array[Value]` — no per-element descriptors. **Scope decision**: B.2 handles `length` descriptor fully (adds `mut length_writable : Bool` to `ArrayData`), but for *indexed* elements only implements the subset that doesn't require per-element descriptor storage: default-descriptor writes succeed; any attempt to set `configurable:false / writable:false / enumerable:false` on an indexed element returns `false` with a scoped TODO pointing to Stage C. Retirement of B.1 Array approximation is **partial** — the `Reflect.set` on `length` case is retired; the full `Object.defineProperty` on indexed elements awaits Stage C's `ArrayData.bag`.

5. **[BLOCKER] Proxy GOPD invariants incomplete.** Missing from original design:
   - Trap returns non-object non-undefined → TypeError.
   - Non-extensible target + trap hides any own property → TypeError.
   - Trap reports non-configurable + non-writable → target's descriptor must also be non-configurable + non-writable, else TypeError.
   - Target own descriptor is non-configurable accessor → trap's descriptor must match getter/setter identity.
   **Fix**: §10.5.5 step list in §"proxy helpers" below updated.

6. **[CONCERN] Proxy target operations must use the dispatcher, not `ordinary_get_own_property`.** Proxy-of-Proxy case needs `self.get_own_property(target, key)` recursion. **Fix**: trap-missing branch of `proxy_get_own_property` and `proxy_define_property` recurses through the dispatcher.

7. **[CONCERN] ToObject + ToPropertyKey coercion order.** §19.1.2.8 `Object.getOwnPropertyDescriptor` does `ToObject` on target (so `Object.getOwnPropertyDescriptor("abc", "0")` works); all four builtins must do `ToPropertyKey` on the property argument. **Fix**: keep coercion in the builtin, pre-dispatcher. Dispatcher receives canonical `String | Symbol` only.

8. **[CONCERN] `Object.getOwnPropertyDescriptor(map, "size")` test is spec-wrong.** GOPD is own-only. The `size` accessor lives on `Map.prototype`. **Fix**: drop that test expectation; replace with an own-property descriptor visibility test (e.g. `Object.getOwnPropertyDescriptor([1,2,3], "length")` returning the length descriptor, or `Object.getOwnPropertyDescriptor(arr, "0")` returning the indexed element's default descriptor).

9. **[CONCERN] Sequence risk**: generalize `target_get_own_descriptor` and add a target-`IsExtensible` helper BEFORE writing proxy helpers, not after migration. Otherwise invariant tests validate only Object-target cases. **Fix**: sequence reordered (§Sequencing below).

## New type: `PartialDescriptor`

For VAP inputs — kept separate from stored `PropDescriptor`:

```moonbit
pub(all) struct PartialDescriptor {
  value : Value?           // None = absent; Some(v) = present, even if v is Undefined
  writable : Bool?         // None = absent
  enumerable : Bool?
  configurable : Bool?
  // Accessors: outer Option encodes presence; inner Value is the function (or Undefined)
  // has_getter / has_setter disambiguate absent from "getter: undefined"
  getter : Value?
  setter : Value?
  has_getter : Bool
  has_setter : Bool
}
```

Helpers: `PartialDescriptor::from_attrs(attrs : Value, interp) -> PartialDescriptor raise Error` — consolidates the `make_define_property_func` / Reflect.defineProperty extraction logic into one place.

`ordinary_define_own_property` accepts `PartialDescriptor`. `ordinary_get_own_property` continues to return `PropDescriptor?` (stored state).

## Shape

Four new units, one file each:

### 1. `property.mbt` — ordinary helpers (private)

```
fn ordinary_get_own_property(
  val : Value,
  key : Value,
) -> PropDescriptor?
```

Reads the variant's `bag.descriptors` + `bag.properties` (or `bag.symbol_*` for Symbol keys). For `Array(arr)`, synthesizes the descriptor for indexed elements (`writable=true, enumerable=true, configurable=true`) and for `length` (`writable=true, enumerable=false, configurable=false`), with Array-named side-table for anything else. Returns `None` for primitive receivers.

```
fn ordinary_define_own_property(
  interp : Interpreter,
  val : Value,
  key : Value,               // canonical key: String or Symbol (caller does ToPropertyKey)
  desc : PartialDescriptor,  // partial — fields can be absent
  loc : @token.Loc,
) -> Bool raise Error
```

Implements ES §10.1.6.3 `ValidateAndApplyPropertyDescriptor`:
- Read existing descriptor via `ordinary_get_own_property`.
- Existing None + target not extensible → `false`.
- Existing None + target extensible → write new descriptor (filling absent fields with defaults: `writable=false, enumerable=false, configurable=false`; accessor fields default to `None`).
- Existing Some + existing non-configurable → step-by-step compatibility check:
  - Attempt to set `configurable: true` → `false`.
  - Attempt to change `enumerable` → `false`.
  - Accessor ↔ data conversion → `false`.
  - Non-writable data: `value` change → `false` (unless SameValue); `writable: false → true` → `false`.
  - Non-configurable accessor: `getter`/`setter` identity change → `false`.
- Otherwise: merge partial into existing and write.
- Primitive / Null / Undefined → `false`.
- `Array(arr)` → routes through `array_define_own_property` (below) which handles §10.4.2.1.

### 2. `property.mbt` — Array exotic (private)

**Prerequisite**: add `mut length_writable : Bool` (default `true`) to `ArrayData` in `value.mbt`. This persists the `writable` attribute on `length`, the only per-descriptor state B.2 needs before Stage C lands.

```
fn array_set_length(
  arr_data : ArrayData,
  desc : PartialDescriptor,
) -> Bool raise Error
```

ES §10.4.2.4 `ArraySetLength`, with partial truncation:
1. If `desc.value` absent → apply remaining attributes via ordinary VAP on `length`'s synthetic descriptor.
2. Coerce `desc.value` → `newLen` via `ToUint32`; if `!=` `ToNumber(desc.value)` → RangeError.
3. If `newLen >= len` → extend elements with Undefined; update length; apply attribute changes (honoring current `length_writable`).
4. If `length_writable == false` → return `false`.
5. If `desc.writable == Some(false)` → defer the writable change until after truncation completes.
6. **Partial truncation loop**: for `i = len - 1` down to `newLen`:
   - Attempt `delete arr_data.elements[i]` — succeeds for default-descriptor elements (which is all we can represent before Stage C).
   - If would fail (we don't yet have per-element configurable tracking, so this never fails in B.2) → stop, set `length = i + 1`, set `length_writable = false` if deferred, return `false`.
   - Otherwise pop element.
7. If all truncation succeeded: apply pending `writable: false` (step 5).
8. Return `true`.

*Note for Stage C*: steps 6's "would fail" check becomes live when per-element descriptors exist; this PR leaves the structure in place with a TODO pointing to Stage C.

```
fn array_define_own_property(
  interp : Interpreter,
  arr_data : ArrayData,
  key : Value,               // canonical: String or Symbol
  desc : PartialDescriptor,
  loc : @token.Loc,
) -> Bool raise Error
```

ES §10.4.2.1. Dispatches:
- `key == "length"` → `array_set_length`.
- key is array index (`ToUint32(key) < 2^32 - 1` AND matches its canonical string form) → ordinary write + grow length if needed. **B.2 limitation**: if `desc` attempts non-default descriptor flags (`configurable: Some(false)`, `writable: Some(false)`, `enumerable: Some(false)`), return `false` with a comment pointing to Stage C. Default-descriptor writes succeed.
- Otherwise → named prop via the existing Array named side table (preserve current behavior).

### 3. `property.mbt` — public dispatchers (Interpreter methods)

```
pub fn Interpreter::get_own_property(
  self : Interpreter,
  val : Value,
  key : Value,
  loc : @token.Loc,
) -> PropDescriptor? raise Error
```

- Proxy → calls new `proxy_get_own_property` helper (below).
- Otherwise → `ordinary_get_own_property`.

```
pub fn Interpreter::define_own_property(
  self : Interpreter,
  val : Value,
  key : Value,
  desc : PropDescriptor,
  loc : @token.Loc,
) -> Bool raise Error
```

- Proxy → `proxy_define_property`.
- Otherwise → `ordinary_define_own_property`.

### 4. `proxy_helpers.mbt` — trap helpers (public)

```
pub fn proxy_get_own_property(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : Value,
  loc : @token.Loc,
) -> PropDescriptor? raise Error
```

ES §10.5.5. Full invariant list (expanded from Codex review):
- Trap missing → recurse `interp.get_own_property(target, key)` (Proxy-of-Proxy works).
- Trap returns **non-object non-undefined** → TypeError (step 8).
- Target has no own descriptor + trap returns undefined → return undefined.
- Target has no own descriptor + trap returns object + target **non-extensible** → TypeError (step 17).
- Target has non-configurable own descriptor + trap returns undefined → TypeError (step 14).
- Trap returns object:
  - Target non-extensible and target has no own descriptor → TypeError.
  - Trap descriptor's `configurable: false` + target descriptor's `configurable: true` or absent → TypeError.
  - Trap reports non-configurable + non-writable → target's descriptor must ALSO be non-configurable AND non-writable, else TypeError.
  - Target has non-configurable accessor own descriptor → trap's getter/setter identity must match (SameValue), else TypeError.
- Return the completed descriptor.

```
pub fn proxy_define_property(
  interp : Interpreter,
  proxy_data : ProxyData,
  key : Value,
  desc : PropDescriptor,
  loc : @token.Loc,
) -> Bool raise Error
```

ES §10.5.6. Invariants (step 14–19):
- Trap returns true + target has no own descriptor + target non-extensible → TypeError.
- Trap returns true + incoming desc is non-configurable → target's descriptor must exist and also be non-configurable (otherwise TypeError).
- `check_proxy_set_trap_invariants`-style reuse: shared non-configurable/non-writable compatibility check.

Add a generalization of `target_get_own_descriptor` (currently Object-only, line ~162) that dispatches through `ordinary_get_own_property`. Propagates to the existing `proxy_get`, `proxy_set`, `proxy_has_property` invariant callers at no logic cost.

## Migration

### A. `Object.defineProperty` (`builtins_object_descriptors.mbt:251`)

Replace the 800-line per-variant switch (lines 369–~900) with:
1. Extract `PropDescriptor` from the `attributes` argument using the existing `ToPropertyDescriptor` code (keep intact).
2. Call `interp.define_own_property(obj, prop_val, desc, loc)`.
3. If returns `false` → raise TypeError (Object.defineProperty is strict-like).
4. Return `obj`.

### B. `Object.getOwnPropertyDescriptor` (line ~933)

1. `interp.get_own_property(obj, prop_val, loc)` → `PropDescriptor?`
2. If `None` → return `Undefined`.
3. Convert `PropDescriptor` → descriptor `Object` (existing helper applies).

### C. `Reflect.defineProperty` (`builtins_reflect.mbt:137`)

Convert `NativeCallable` → `InterpreterCallable` (needs interp for trap calls). Same extract → dispatch shape as Object.defineProperty, except: on `false` return `Value::Bool(false)` (non-throwing). Matches Reflect's contract.

### D. `Reflect.getOwnPropertyDescriptor` (line ~513)

Convert to `InterpreterCallable`. Call `interp.get_own_property` directly — Proxy traps fire naturally. Drop the `unwrap_proxy_target` call at line ~150.

### E. `define_value_on_receiver` (`property.mbt:1586`) — B.1 landing helper

Two branches change:

- `Proxy(pdata)` (1598–1605): replace the recursive unwrap with `self.define_own_property(receiver, key, data_desc, loc, strict)` where `data_desc` is constructed as `{ value: value, writable: true, enumerable: true, configurable: true, getter: None, setter: None }` (CreateDataProperty spec §7.3.5).
- `Array(_)` (1783–1803): same — call `define_own_property` instead of re-firing `set_property`. This retires the "Reflect.set on arr length" divergence.

The Object/Map/Set/Promise branches (1606–1769) stay inline OR get replaced by `ordinary_define_own_property` with the CreateDataProperty descriptor shape. Prefer replacement for uniformity; keeps the landing-helper invariants centralized.

## Key invariant: §10.1.9.2 step 3.e stays at `[[Set]]` landing

**Decision (per Codex review)**: keep `existing_receiver_desc_blocks` in `define_value_on_receiver` as a `[[Set]]`-landing rule. Do NOT fold into VAP.

Rationale: §10.1.9.2 step 3.e blocks an existing accessor or non-writable-data own descriptor on the receiver BEFORE calling `Receiver.[[DefineOwnProperty]]`. VAP on a *configurable* accessor or *configurable* non-writable data would otherwise allow replacement — observable divergence from spec in non-Proxy non-Array cases.

Landing sequence (unchanged from B.1):
1. `existing_receiver_desc_blocks(existing_desc)` → if true, strict throws TypeError, sloppy returns value.
2. Build the CreateDataProperty descriptor: `{ value: Some(v), writable: Some(true), enumerable: Some(true), configurable: Some(true), has_getter: false, has_setter: false }`.
3. Call `self.define_own_property(receiver, key, desc, loc)`.
4. If returns false → strict throws, sloppy returns value.

## Scope decision: B.1 approximation #3 (proto-chain inherited-setter walks)

**Question for reviewer**: Stage B.2 as sketched above retires approximations #1 (Array receiver landing) and #2 (Proxy receiver landing) in `define_value_on_receiver`. Approximation #3 (Map/Set/Promise/Array proto-chain inherited-setter walks) is `[[Set]]`-semantics, not `[[DefineOwnProperty]]`-semantics — it's about `set_property` missing setters on `Array.prototype` / `Map.prototype` when the receiver is a subclass instance.

The fix for #3 uses `get_constructor_prototype(env, "Array" | "Map" | "Set" | "Promise")` (already used in eval_expr.mbt:1446–1449 and conversions.mbt:742–744) to walk the implicit builtin prototype. It's additive to B.1's `[[Set]]` dispatcher.

**Options**:
- **(A) In scope for B.2.** Bundle the `[[Set]]`-side proto walk with the other B.2 work. +a few tests (the `Proxy/set/trap-is-missing-receiver-multiple-calls*` family per agent-todo.md); higher diff.
- **(B) Separate follow-up PR.** Ship B.2 clean on the `[[DefineOwnProperty]]` axis, file #3 as its own task. Lower risk, easier review.

**Decision (2026-04-22, confirmed by user)**: **(B)** — ship B.2 on the descriptor axis, file #3 as a follow-up on the `[[Set]]` dispatcher. Rationale: the three B.1 approximations are artifacts of how the TODO grouped them; they have different surface areas. A cleaner review beats a bundled PR.

## Test plan

### Regression guards (new whitebox tests)

1. `Reflect.set({}, "length", 10, arr)` on default length (writable=true) → returns `true`, length truncates. Variant: after `Object.defineProperty(arr, "length", {writable: false})`, `Reflect.set(..., 10, arr)` → `false`, length unchanged. (Retires B.1 approx #1.)
2. `Reflect.defineProperty(proxy, "x", {value: 1})` where handler defines a `defineProperty` trap → trap fires. (Retires B.1 approx #2.)
3. `Object.getOwnPropertyDescriptor(arr, "0")` on `[10, 20, 30]` → returns `{ value: 10, writable: true, enumerable: true, configurable: true }`. (Fixes descriptor visibility for Array elements.)
4. `Object.getOwnPropertyDescriptor([1,2,3], "length")` → returns `{ value: 3, writable: true, enumerable: false, configurable: false }`. (Array length descriptor visibility.)
5. `Array.prototype.__proto__` related: `Object.getOwnPropertyDescriptor(Array.prototype, "push")` returns the push method descriptor.
6. Proxy `defineProperty` trap invariant: target is non-extensible, trap reports `configurable: true` → TypeError. (§10.5.6 step 17.)
7. Proxy `getOwnPropertyDescriptor` trap invariant: target has non-configurable own descriptor, trap returns undefined → TypeError. (§10.5.5 step 14.)
8. Proxy `getOwnPropertyDescriptor` trap returns non-object non-undefined → TypeError. (§10.5.5 step 8.)
9. Proxy `getOwnPropertyDescriptor` trap reports non-config + non-writable + target has writable → TypeError. (§10.5.5 post-step-17 writable reconciliation.)
10. Proxy-of-Proxy `getOwnPropertyDescriptor` recursion: outer trap missing → inner trap fires.
11. Array `length` partial truncation: `Object.defineProperty(arr, "length", {value: 2, writable: false})` truncates then locks writable in one step.
12. `array_set_length` with `value` coercing to NaN → RangeError.

**Removed from original test plan** (Codex concern #8): the `Object.getOwnPropertyDescriptor(map, "size")` test — GOPD is own-only; the `size` accessor lives on `Map.prototype`, not on individual Map instances.

### test262 filters

After implementation:

```
python3 test262-runner.py --filter "built-ins/Reflect/defineProperty" --summary
python3 test262-runner.py --filter "built-ins/Reflect/getOwnPropertyDescriptor" --summary
python3 test262-runner.py --filter "built-ins/Proxy/defineProperty" --summary
python3 test262-runner.py --filter "built-ins/Proxy/getOwnPropertyDescriptor" --summary
python3 test262-runner.py --filter "built-ins/Proxy/set/trap-is-missing-receiver" --summary
```

Expected deltas: ~+25–35 across the four Proxy filters, ~+5 across Reflect. Zero regression on `built-ins/Object/*` (migration is pure refactor on the ordinary path).

## Risk register

| Risk | Mitigation |
|------|------------|
| Pre-existing Object.defineProperty logic has quirks that regress | Migrate incrementally; preserve behavior under existing snapshots; run full `moon test` between each migration. |
| `ordinary_define_own_property` § 10.1.6.3 compatibility algorithm is subtle | Mirror SpiderMonkey / V8 `ValidateAndApplyPropertyDescriptor` structure; add targeted whitebox unit tests *per spec step*. |
| Array index `length` cross-talk (truncation + non-configurable index) | Test262 has dedicated coverage in `built-ins/Array/length`; expect to surface pre-existing gaps. |
| `InterpreterCallable` conversion on Reflect loses arg-shape inference | Keep factory shape identical to existing Reflect entries that already use InterpreterCallable (e.g. `Reflect.set`). |
| Codex/CodeRabbit round surfaces extra invariants | Budget a follow-up commit; B.2 is structural, not semantic — refinements land cleanly. |

## Sequencing (revised per Codex concern #9)

Implementation order (each a separate commit for review):

1. Add `PartialDescriptor` type + `from_attrs` extractor + unit tests.
2. Add `mut length_writable : Bool` to `ArrayData` (value.mbt) — plumb default `true` at every Array construction site.
3. Generalize `target_get_own_descriptor` / `target_is_extensible` / `target_has_own_property` in `proxy_helpers.mbt` to cover Array/Map/Set/Promise (not just Object). This is a pre-step that also improves existing B.1 helpers. **No B.2 dispatcher yet — pure primitive generalization.**
4. Extract `ordinary_get_own_property` + `ordinary_define_own_property` + whitebox unit tests covering VAP spec steps.
5. Add `array_set_length` + `array_define_own_property` + unit tests (length attributes, partial-truncation scaffold, indexed-element writes).
6. Add `proxy_get_own_property` + `proxy_define_property` + unit tests (all six §10.5.5 invariants, all §10.5.6 invariants, Proxy-of-Proxy recursion).
7. Wire `Interpreter::get_own_property` / `define_own_property` dispatchers + unit tests.
8. Migrate `Reflect.getOwnPropertyDescriptor` (smallest — validates dispatcher end-to-end).
9. Migrate `Reflect.defineProperty`.
10. Migrate `Object.getOwnPropertyDescriptor`.
11. Migrate `Object.defineProperty`.
12. Retire `define_value_on_receiver` Array + Proxy approximations. Array retirement is **partial** — `length` case retired fully; indexed-element case retired for default descriptors only.
13. Run full test262 filters, update docs/agent-todo.md with delta.

Steps 1–3 are foundational; step 3 is the key reorder per Codex — generalizing target helpers before writing proxy helpers means the invariant tests validate all variant targets, not just Objects. Step 8 is the smallest migration and validates the dispatcher. Steps 10–11 are the largest diffs (each 200–400 lines removed).

## Out-of-scope (explicit non-goals)

- Accessor descriptor unification (PR #51 follow-up item #25 — `lookup_property_chain` ignoring `bag.descriptors`). Separate PR.
- Map/Set/Promise/Array proto-chain inherited-setter walks (B.1 approximation #3). See scope decision above.
- Descriptor typestate builder (agent-todo #12). Exploratory, separate PR.
- **Full Array indexed-element descriptor state** (added post-Codex). `Object.defineProperty(arr, "0", {configurable: false})` rejects with `false` in B.2 (no storage for per-index descriptors) — full fix awaits Stage C's `ArrayData.bag`. B.2 retires the `length` part of the B.1 Array approximation; indexed-element part retires in Stage C.

## Open questions (for Codex)

1. **Whitebox unit-test count target** — at minimum 8 new tests (one per sequencing step; two for §10.1.6.3 compatibility edge cases). Codex may flag additional spec steps requiring coverage.
2. **Receiver threading for descriptor ops** — §10.1.5 and §10.1.6 do NOT take a Receiver parameter (unlike §10.1.9 `[[Set]]`). Confirm dispatcher signature `(val, key, desc, loc)` is complete.
3. **§10.1.6.3 `ValidateAndApplyPropertyDescriptor` subtleties** — any edge cases (frozen + configurable change, accessor-to-data switch invariants) that our preserved `validate_non_configurable` helper doesn't already cover?
