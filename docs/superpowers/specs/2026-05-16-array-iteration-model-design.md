# Array iteration model — design

**Status:** v5 — three rounds of Codex design review + one round of executed-code verification via `moon test`. Pending implementation plan.
**Target cluster:** `built-ins/Array/prototype/*` Sub-cohort A.
**Projected recovery sanity range:** +150 to +240 strict in the targeted directories. The cluster's raw filename count is 242 strict / 253 non-strict, but precise projection is unreliable because splice is deferred and foundational helpers cascade in both directions (`feedback_reason_cluster_undercounts.md`). CI's per-mode baseline diff is the authoritative figure.
**Base tip:** `e52d3ea` on main (PR-branch-equivalent `3f0080f`, CI run `25924976445`).

## Problem

At base tip `e52d3ea`, `built-ins/Array/prototype/*` accounts for 418 strict / 427 non-strict test262 failures — 58% of which form a single sub-cohort whose fixtures are the legacy ES5.1-numbered tests (`15.4.4.X-N-N-N-XX.js`, `S15.4.4.X_A*`). 242 strict / 253 non-strict failures.

Sampled fixtures (`reduce/15.4.4.21-8-b-iii-1-10.js`, `forEach/15.4.4.18-7-b-11.js`, `indexOf/15.4.4.14-9-a-10.js`) confirm three failure scenarios:

1. **Own accessor on an Array index** — `Object.defineProperty(arr, "0", {get: ...})`. Iteration reads `data.elements[0]` directly, bypassing the getter.
2. **Mid-iteration mutation of `Array.prototype`** — `Object.defineProperty(Array.prototype, "1", {get: ...})` or `delete Array.prototype[1]` invoked from a getter callback. Iteration reads `data.elements[i]` and never consults the prototype chain.
3. **Holes that fall through to the prototype** — sparse literal `[0, , 2]` with `Array.prototype[1] = X`. `arr[1]` should resolve to `X`. The engine sees `data.elements[1] === Undefined` and returns `undefined`.

All three are downstream of three call sites that read `data.elements[i]` directly without consulting `data.holes`, `data.bag.descriptors`, or the Array's prototype chain (resolved via `get_array_prototype_override(data)` / `lookup_builtin_proto`).

## Root cause (verified)

Three sites bypass ordinary `[[Get]]` / `[[HasProperty]]` semantics for Array-exotic receivers:

| Site | File:lines | Symptom |
|---|---|---|
| `get_array_like_element_interp` | `interpreter/runtime/array_like.mbt:196-210` | `Array(data)` branch returns `data.elements[i]` for any in-range `i` |
| `has_array_like_element` | `interpreter/runtime/array_like.mbt:214-251` | `Array(data)` branch returns `i >= 0 && i < data.elements.length()` |
| `Interpreter::get_property` numeric-index path | `interpreter/runtime/property.mbt:11-31` | Checks `data.bag.descriptors` for accessor on numeric index in-range, but doesn't consult `data.holes`; out-of-range falls to named-property branch which doesn't walk Array.prototype for indices |

ES2024 §10.4.2 specifies that Array exotic objects override `[[DefineOwnProperty]]` and `[[Set]]` only — `[[Get]]` and `[[HasProperty]]` fall through to ordinary behavior per §10.1.1 (OrdinaryGet) and §10.1.7 (OrdinaryHasProperty). Confirmed by Codex review against ES2024 indexed-collections spec.

## Foundation already in place

- `ArrayData` (`value.mbt:133`) carries `elements`, `bag : PropertyBag` (with `properties`, `descriptors`), `holes : Map[Int, Unit]`, `length_writable`, `extensible`. **Note:** `ArrayData` has *no* `prototype` field, unlike `ObjectData`. The primitive `get_array_prototype(env : Environment, arr : ArrayData) -> Value` (`eval_expr.mbt:1488`) resolves the array's prototype: it returns the override if set, otherwise the env's `%Array.prototype%` via `get_constructor_prototype(env, "Array")`. **Important:** `lookup_builtin_proto(self, obj, "Array", prop, loc)` does *not* return `%Array.prototype%` — it returns the *property value* `Array.prototype[prop]`. Use `get_array_prototype` to get the prototype object, then `get_property_from_prototype` to walk it.
- Stage C `bag` field ✅ PR #72 / commit `7177d9f`; `holes` ✅ PR #91 (2026-05-09)
- Array-literal evaluation populates `holes` for sparse literals (`eval_expr.mbt:566`)
- `holes` is consumed by `delete`, `for-in`, `Object.keys`, `Object.assign`, and 30+ other call sites — but **not** by the three iteration sites above
- `Interpreter::get_property_from_prototype` (`property.mbt:173`) is the receiver-preserving prototype walker, already used internally; needed for spec-correct accessor invocation on inherited getters
- `builtins_array.mbt:116, 370-373` explicitly returns `Undefined` for `forEach|map|filter|reduce|reduceRight|every|some|indexOf|lastIndexOf` with comment "Delegated to Array.prototype". The fast-path interception flagged in `feedback_fast_path_duplicates.md` does NOT apply to this cohort.

## Design

### Shared subroutine

Introduce a private helper in `interpreter/runtime/array_like.mbt`:

```moonbit
priv enum ArrayIndexHit {
  Present(Value)         // dense element OR own data descriptor — value lives in data.elements[i]
  Hole                   // index in range, in data.holes, no own descriptor
  OutOfRange             // i < 0 or i >= elements.length(), and no own descriptor at str(i)
  OwnAccessor(Value?)    // own accessor descriptor at str(i); payload is the getter (None ⇒ write-only)
}

fn array_index_lookup_result(data : ArrayData, i : Int) -> ArrayIndexHit
```

Lookup order (verified against ES2024 §10.1.5 OrdinaryGetOwnProperty and the existing `array_define_own_property` behavior at `property_own.mbt:880-922`):

1. Inspect `data.bag.descriptors[str(i)]`. If accessor descriptor (`is_accessor == true`) → `OwnAccessor(desc.getter)`. If data descriptor (`is_accessor == false`) AND `i >= 0 && i < elements.length()` → `Present(data.elements[i])`.
2. No own descriptor + `i < 0` → `OutOfRange`.
3. No own descriptor + `i in data.holes` → `Hole`.
4. No own descriptor + `i >= 0 && i < data.elements.length()` → `Present(data.elements[i])`.
5. Otherwise → `OutOfRange`.

**Why no separate `OwnDataDescriptor(Value)` variant** (verified by `moon test` 2026-05-16): `PropDescriptor` (`value.mbt:90-99`) has no `value` field — the value of a data property always lives in `data.elements[idx]` (`array_define_own_property` line 920: `arr.elements[idx] = v` after extending elements to cover `idx`). So `defineProperty(arr=[10], "0", {value: 99})` writes 99 to `data.elements[0]`, and a subsequent `arr[0]` read returns 99 via the `Present` path. An own data descriptor only contributes attribute metadata (writable/enumerable/configurable), which `[[Get]]` and `[[HasProperty]]` ignore. The accessor case still needs its own variant because the getter lives in the descriptor, not `data.elements`.

No interpreter argument needed in `array_index_lookup_result`.

### Caller behavior

Per ES2024 §10.1.1 OrdinaryGet / §10.1.7 OrdinaryHasProperty. Let `R` be the original Array (receiver preserved through the chain). Resolve the prototype with `proto_of(data) = get_array_prototype(self.global, data)`:

| Hit | `[[Get]]` (receiver R) | `[[HasProperty]]` |
|---|---|---|
| `Present(v)` | return `v` | true |
| `OwnAccessor(Some(g))` | return `Call(g, R, [])` — **R is the original Array, not the prototype** | true |
| `OwnAccessor(None)` | return `Undefined` — write-only accessor does NOT fall through to prototype | true |
| `Hole` | walk `proto_of(data)` via `get_property_from_prototype(R, proto, str(i), loc)` — receiver preserved | walk prototype chain, returning bool |
| `OutOfRange` | same as `Hole` | same as `Hole` |

### Three site patches

For all three sites: when prototype walk is needed, resolve via `let proto = get_array_prototype(env_or_global, data)`, then dispatch via `get_property_from_prototype(Array(data), proto, str(i), loc)` so getter `this` binds to the original Array.

**1. `get_array_like_element_interp` (`array_like.mbt:196-210`).** Already has `interp` in scope so prototype resolution is `get_array_prototype(interp.global, data)`. Array branch dispatches via `array_index_lookup_result` and handles all five cases. `Hole`/`OutOfRange` walk the resolved prototype as above. `OwnDataDescriptor(v)` returns `v`. `OwnAccessor(Some(g))` calls `interp.call_value(g, Array(data), [], loc)`. `OwnAccessor(None)` returns `Undefined`. `Present(v)` returns `v`.

**2. `has_array_like_element` — introduce an interp-aware variant (Codex v3 finding).** The current signature `(val : Value, index : Int) -> Bool` cannot resolve `%Array.prototype%`. Two options:
- **2a.** Add `interp : Interpreter` parameter, retiring the non-interp variant. All callers in `builtins_array_init.mbt` already have `interp` in scope.
- **2b.** Add a parallel `has_array_like_element_interp(interp, val, index) -> Bool` and migrate callers method-by-method.
Choose 2a — fewer functions, no half-migrated state. New signature: `has_array_like_element(interp : Interpreter, val : Value, index : Int) -> Bool`. Dispatch via `array_index_lookup_result`. `Present`/`OwnAccessor(_)` → true. `Hole`/`OutOfRange` → walk prototype via `get_array_prototype(interp.global, data)` then traverse non-raising (extract `proto_has_index_property` helper shared with the Object branch's existing logic). Proxy-as-prototype still out of scope — Proxy `has` traps can throw, and this remains a `Bool` return.

**3. `Interpreter::get_property` numeric-index path (`property.mbt:11-61`).** Replace lines 17-31 with a dispatch through `array_index_lookup_result`. Resolve prototype via `get_array_prototype(self.global, data)`. Cases:
- `Present(v)` → return v
- `OwnAccessor(Some(g))` → `self.call_value(g, obj, [], loc)`
- `OwnAccessor(None)` → return `Undefined`
- `Hole` / `OutOfRange` → `self.get_property_from_prototype(obj, proto, prop, loc)`

Length-property branch (lines 12-16) and named-property branch (lines 32-61) unchanged.

### Hole-lifecycle foundation fixes

Without these fixes the iteration-model fix recovers fewer tests because the engine cannot distinguish a hole from a real `undefined`. Codex v1 caught the marking gaps; Codex v2 caught the clearing gaps. Both flavors must ship together to keep the invariant **"index `i` is in `data.holes` iff there is no own property at `str(i)`"** intact.

**Mark-on-create (currently missing):**

| Site | File:lines | Change |
|---|---|---|
| `Array(n)` constructor | `interpreter/stdlib/builtins_array_init.mbt:1893-1897` | When materializing `elements = Array::make(len, Undefined)`, also mark indices `0..len` in `holes` |
| `set_array_like_length` (extend) | `interpreter/runtime/array_like.mbt:269-278` | When padding with `Undefined`, mark each new index in `holes` |
| `create_data_property_or_throw` sparse case | `interpreter/runtime/array_like.mbt:294-312` | When padding indices below the target with `Undefined`, mark each padding index in `holes` (the target index itself is real and must be cleared from holes — see below) |
| `array_define_own_property` indexed growth | `interpreter/runtime/property_own.mbt` (audit the site that handles `Object.defineProperty(arr, "5", …)` on shorter array per §10.4.2.1) | When raising length to `idx+1`, mark indices `old_length..idx` in `holes`; `idx` itself gets the descriptor and stays absent from `holes` |

**Clear-on-mutation (currently missing — Codex v2 P0-B):**

| Site | File:lines | Change |
|---|---|---|
| `set_array_like_element` | `interpreter/runtime/array_like.mbt:255-265` | On Array write to `index` in range, call `data.holes.remove(index)` |
| `create_data_property_or_throw` (all branches) | `interpreter/runtime/array_like.mbt:294-312` | Target index is real after write — `data.holes.remove(index)` in all three branches (append, in-range overwrite, sparse-pad-then-set) |
| Length-shrink in property_set | `interpreter/runtime/property_set.mbt:202-204, 1230-1232` | After `data.elements.pop()` loop reduces length to `n64`, remove any `holes` entries with key `>= n64`. Also clear descriptors above new length (already handled by `array_set_length` at one site but not the other — audit both) |

Pre-implementation audit: grep `Array::make(`, `\.push(Undefined)`, `\.pop()` against `data.elements`, and ad-hoc length extension in `stdlib/` and `runtime/`. If additional sites surface, decide per-site (fix vs defer) by whether they affect cluster recovery.

### Pre-existing reader bugs that become more visible (risk register)

Codex v2 flagged additional direct `arr.elements` readers that don't consult `holes` or `bag.descriptors`: non-interp `get_array_like_element`, `to_array_like_elements`, array iterators, sort/shift/reverse/splice fast paths, JSON paths. These are pre-existing bugs. With `Array(n)` now marking holes, tests that exercise these paths via `Array(n)` may newly fail. **Mitigation:** run the per-mode baseline diff after each commit and inspect any newly-failing test individually — if it lands in one of these paths, decide per case: (a) fix the path in this PR if cheap, (b) defer to a follow-up and document, (c) revert the foundation change for that specific creation site if no other recovery is gated on it. **Do not** ship the foundation fix on a path that produces a net regression.

### Out of scope (deferred follow-ups)

- **Splice fast-path** (`builtins_array_init.mbt:~1195`) directly manipulates `arr.elements` — bypasses Get/Set/Delete/HasProperty on iteration. Spec-correct splice is a separate refactor. Test impact: the splice method has 22 strict fails total in this triage cluster; how many recover from the iteration-model fix versus how many are gated on the splice rewrite is not predictable from triage shape — trust the CI baseline diff (Codex flagged "~8 strict" as not defensible).
- **Proxy-as-Array-prototype HasProperty** — would require a raising variant of `has_array_like_element`. ~0-3 tests estimated (Codex P1-3).
- **Sub-cohorts B/C/D/E/G/H** (~176 tests) per parent triage report.

## Testing

### Whitebox unit tests (`array_like_wbtest.mbt`)

For `array_index_lookup_result`, assert per spec for each case:

| Setup | Expected |
|---|---|
| `arr = [10, 20, 30]`, `i=1` | `Present(Number(20))` |
| `arr = [0, , 2]` (hole at 1), `i=1` | `Hole` |
| `arr = [10]`, `i=5` | `OutOfRange` |
| `arr = [10]; defineProperty(arr, "0", {value: 99})`, `i=0` | `Present(Number(99))` — defineProperty writes 99 into `data.elements[0]`; data descriptor only carries attribute metadata |
| `arr = [10]; defineProperty(arr, "0", {get: f, configurable: true})`, `i=0` | `OwnAccessor(Some(f))` |
| `arr = [10]; defineProperty(arr, "0", {set: f})`, `i=0` | `OwnAccessor(None)` (write-only) |
| `arr = [10, 20, 30]; defineProperty(arr, "5", {value: 7})` then `i=5` | `Present(Number(7))` — defineProperty grows `elements` to length 6 and writes 7 at index 5; indices 3 and 4 become `Hole` (after mark-on-create fix) |
| `arr = [10]`, `i=-1` | `OutOfRange` |
| `arr = Array(5)`, `i=2` (after foundation fix) | `Hole` |

For caller integration (`has_array_like_element`, `get_array_like_element_interp`, `Interpreter::get_property`):
- Dense read returns value
- Own accessor with getter calls getter, `this` = the original Array
- Own accessor without getter returns `Undefined` and does NOT walk prototype
- Own data descriptor wins over dense element
- Hole reads inherited property from `Array.prototype` (when set via `Array.prototype[i] = v`)
- Out-of-range reads inherited property
- Inherited getter on `Array.prototype` receives the original Array as `this` (receiver-preservation regression test)
- `arr["0"]` equals `arr[0]` — numeric-string coercion path
- `arr["-0"]` stays a named property (does not collide with index 0)
- Own data property with value `undefined` suppresses inherited `Array.prototype[i]` (per OrdinaryGet stopping at the own descriptor)
- `Array(1).fill(7)` produces no holes — fill clears the hole flag (regression test for `set_array_like_element` / `create_data_property_or_throw` clear-on-write)
- Shrink-then-push (Codex v3 P1 phrasing): `var a = Array(3); a.length = 1; a.push(9); assert(a.length === 2); assert(1 in a); assert(a[1] === 9)` — verifies the length-shrink fix clears stale holes at index 1 so the subsequent push lands cleanly without inheriting a phantom hole
- `Object.defineProperty(arr=[10,20,30], "5", {value: 7}); assert(arr.length === 6); assert(!(3 in arr) && !(4 in arr)); assert(arr[5] === 7)` — verifies `array_define_own_property` indexed-growth hole marking

### test262 baseline diff

1. Pre-fix: capture per-mode pass/fail map for `built-ins/Array/prototype/{reduce,reduceRight,map,filter,forEach,some,every,indexOf,lastIndexOf,slice,concat,fill,flat,flatMap}/*` (excluding splice as deferred).
2. Run after each commit. Required output: per-mode `(newly_pass, newly_fail)` counts.
3. Sanity check: net recovery should be in the +150 to +240 strict range in targeted directories; substantially below that signals missed sites; substantially above that signals foundational cascade (verify with full-suite CI run before claiming the figure per `feedback_reason_cluster_undercounts.md`).
4. Watch for regressions in the full suite (not just the cluster) — foundational helpers cascade; CI is authoritative for the published recovery figure.

## Risk register

| Risk | Mitigation |
|---|---|
| Receiver-preservation bug in prototype walk | Use existing `get_property_from_prototype`; add a regression test that asserts the receiver in an inherited getter |
| Hole-marking site enumeration incomplete | Pre-implementation grep audit; decide per missed site whether to fix |
| Tests passing "by accident" via dense-Undefined now fail because prototype property exists | Per-mode baseline diff after each commit; investigate regressions individually |
| Performance regression on tight loops | Adds one `Map.contains` per dense read; O(1) hashmap lookup; acceptable. Worth one benchmark spot-check on `reduce`/`map` over a large dense array |
| Wide-catch swallows raised errors from getters | Audit per `feedback_wide_catch_around_raise.md` — `get_array_like_element` (non-interp) deliberately catches getter errors; new `array_index_lookup_result` is non-raising and avoids the issue |

## Implementation order

**Phase 1 — clear-on-mutation foundation (lands first; restores the "i in data.holes iff no own property at str(i)" invariant for the holes that *already* get marked today by sparse literals and length-extension paths):**
1. `set_array_like_element` clears `holes[i]` on Array write + tests
2. `create_data_property_or_throw` clears target hole in all branches + tests
3. Length-shrink in `property_set.mbt` removes `holes` entries above new length (both sites) + tests
4. Targeted baseline diff after this phase — neutral or slightly positive expected. Sparse-literal-then-mutate cases (`[,,,].fill(7)`, sparse shrink-then-push) may produce visible recovery; if zero recovery shows up, that's also fine — Phase 1 is invariant-restoring and primarily de-risks Phase 3.

**Phase 2 — `array_index_lookup_result` + read-site rewrites (the core fix):**
5. Implement `array_index_lookup_result` + whitebox tests (TDD)
6. Patch `has_array_like_element` Array branch + tests
7. Patch `get_array_like_element_interp` Array branch + tests
8. Patch `Interpreter::get_property` numeric-index path + tests
9. Baseline diff — most cluster recovery lands here

**Phase 3 — mark-on-create foundation (lands last because it makes the pre-existing reader bugs more visible; per-step diff catches them):**
10. Fix `Array(n)` constructor hole-marking — diff, decide keep vs revert based on net effect
11. Fix `set_array_like_length` hole-marking — diff
12. Fix `create_data_property_or_throw` sparse-pad hole-marking — diff
13. Fix `array_define_own_property` indexed-growth hole-marking — diff

**Honest reversibility note (Codex v3):** if any Phase 3 site is reverted (because it surfaces pre-existing reader bugs the PR can't cheaply absorb), the corresponding test262 recovery is **forfeited**, not deferred for free. The bug stays: `Array(5)[2]` continues to read as `Present(Undefined)` and skip the prototype chain. Document the reverted site as a follow-up issue with the test fixtures it would unlock, so the cost is tracked.

**Wrap:**
14. Cumulative `.mbti` review; `moon info && moon fmt`
15. Codex code review of full diff
16. PR

Phase order is chosen so that each phase can be evaluated independently in the baseline diff: clear-on-mutation is invariant-restoring and should never regress; read-site rewrites should produce most of the recovery; mark-on-create may surface pre-existing reader bugs and is reversible per site.

## Codex design review findings addressed

**v1 (first-pass):**
- **P0-1** write-only accessor must not walk prototype → `OwnAccessor(None)` returns `Undefined`, doesn't walk
- **P0-2** receiver preservation through prototype → use `get_property_from_prototype` (receiver-preserving) not `get_property` (which re-binds to prototype)
- **P1-3** HasProperty + Proxy-prototype → deferred, documented
- **P1-4** hole-marking gaps → expanded scope to three additional sites
- **P1-5** splice fast-path bypass → deferred follow-up, recovery projection widened
- **P2-6** §10.4.2 confirmation → no change needed

**v2 (second-pass on the v2 spec):**
- **P0-A** `ArrayData` has no `prototype` field → spec now resolves via `get_array_prototype(env, data)` (v3 corrected this further — see below)
- **P0-B** hole-clearing gaps in `set_array_like_element`, `create_data_property_or_throw`, and length-shrink → expanded scope to three clear-on-mutation fixes
- **P1-C** enum needed `OwnDataDescriptor` variant for non-accessor descriptors at array indices (own descriptors win over dense element) → added
- **P1-D** `OutOfRange` did not account for `defineProperty(arr, "5", {value})` on shorter array → definition tightened; OOB-index with own descriptor lands in `OwnDataDescriptor`/`OwnAccessor`, raising length per §10.4.2.1
- **Reader-audit fragility** → added pre-existing reader bugs to risk register with mitigation strategy
- **Splice "~8 strict" not defensible** → projection figure dropped, sanity range substituted

**v4 (real-code verification via `moon test` 2026-05-16):**
- **Enum collapse** — `OwnDataDescriptor(Value)` removed; verified that `PropDescriptor` (`value.mbt:90-99`) has no `value` field and that `array_define_own_property` (`property_own.mbt:920`) writes data-descriptor values to `data.elements[idx]`, so the dense path subsumes the data-descriptor path. The 4-case enum (`Present`/`Hole`/`OutOfRange`/`OwnAccessor`) is sufficient and was confirmed compilable with 3 passing test stubs in `array_like_wbtest.mbt` (since deleted)
- **API surface verified compilable** — `get_array_prototype(env, data)`, `Interpreter::call_value(getter, receiver, [], loc)`, `Interpreter::get_property_from_prototype(arr, proto, key, loc)`, and `ArrayData` struct-literal construction all type-check from `array_like.mbt`'s module context

**v3 (third-pass on the v3 spec):**
- **P0** `lookup_builtin_proto` returns the *property value*, not the prototype object → spec now uses `get_array_prototype(env, data)` (which already does override-vs-default resolution); also `has_array_like_element` signature gains an `interp` parameter so it can resolve `%Array.prototype%` (Codex v3 P0)
- **P1** Phase 1 not strictly no-op — sparse-literal-then-mutate cases (`[,,,].fill(7)`, sparse shrink-then-push) may produce visible recovery; spec wording corrected (Codex v3 P1)
- **P1** Phase 3 reversibility honesty — per-site revert *forfeits* the corresponding test262 recovery; spec now documents this as a follow-up cost, not a free skip (Codex v3 P1)
- **P1** `Object.freeze` test case removed — `make_freeze_func` (`builtins_object_integrity.mbt:10-14`) only handles `Object(data)`, not `Array(data)`, so the test would have exercised a no-op
- **Added** `array_define_own_property` indexed-growth hole-marking as a fourth mark-on-create site — `Object.defineProperty(arr, "5", {value: 7})` on length-3 array must mark 3..4 as holes per §10.4.2.1
- **Test phrasing** for shrink-then-push tightened from "undefined-or-hole?" to a concrete `length === 2; 1 in a; a[1] === 9` assertion

## References

- ES2024 §10.1.1 OrdinaryGet, §10.1.7 OrdinaryHasProperty, §10.4.2 Array Exotic Objects
- Parent triage: this session's Array/prototype/* triage report
- Memory: `project_landscape_2026_05_16.md`, `feedback_spec_verification.md`, `feedback_fast_path_duplicates.md`, `project_array_test262_analysis.md`, `feedback_reason_cluster_undercounts.md`
- Prior related work: PR #72 (Stage B.2 dispatchers), PR #91 (`ArrayData.holes`), PR #82 (foundational-helper cascade pattern)
