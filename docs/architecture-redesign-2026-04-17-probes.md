# Architecture Redesign Probes — 2026-04-17

> **Status:** exploratory — analysis, not yet executed. Supplements
> [archive/architecture-redesign-2026-04-15.md](archive/architecture-redesign-2026-04-15.md)
> (complete and shipped). This document records the next-phase
> pressures identified after April-15 and the sizing evidence gathered
> from four uncertainty probes.

---

## 1. Post-April-15 Change Pressures

**CP-1. Proxy transparency is not a property of the value model; it is implemented per-call-site.**
170 of 536 `built-ins/Proxy` tests still fail (168 at the 2026-04-17 run).
`Proxy(` variant match appears in 12 runtime files. Every access path
(member access, `in`, `instanceof`, `for-in`, `Reflect.construct`,
`create_list_from_array_like`, set-receiver forwarding) re-implements
proxy semantics independently.

**CP-2. `ArrayData` is not a first-class object.**
`runtime/value.mbt:90–92` defines `ArrayData { elements }`. Named/symbol/
accessor properties live in module-level mutable side tables
(`array_named_props`, `array_symbol_props`, `array_length_overrides`,
`array_iterator_overrides`) with O(n) `physical_equal` scans. Causes
~700+ test262 Array failures and Issue #1 (descriptors invisible).

**CP-3. Property-bag quartet duplicated across exotic variants.**
`ObjectData`, `MapData`, `SetData`, `PromiseData` each redeclare
`properties / symbol_properties / descriptors / symbol_descriptors`.
Any descriptor invariant fix must be applied per type.

**CP-4. Realm hermeticity.** DEMOTED after probe — see §3.

---

## 2. Target Architecture

Two structural changes + one convention:

1. Introduce `PropertyBag` struct; embed in every exotic `Value` variant.
2. Make `runtime/property.mbt` the sole `[[Get]]/[[Set]]/[[Has]]/
   [[OwnKeys]]/[[Delete]]` dispatcher. Proxy branch lives inside.
3. Forbid module-level mutable `let` in `runtime/` (enforced by grep).

---

## 3. Uncertainty Probes

### Probe 1 — `ArrayData` destructure audit

**Question:** does `pub(all) struct ArrayData` mean callers destructure
fields? If yes, adding a `bag` field is a widespread rewrite.

**Result:** No. Counted patterns across all `.mbt` files:

| Pattern | Count | Impact |
|---|---|---|
| `Array({ elements: ... })` construction literal | 74 | migrate |
| `Array(name) =>` match binding | 85 | safe |
| `.elements` field access | 190 | safe |
| `Array({ elements: ... }) =>` pattern destructure | **0** | — |

Migration surface is bounded to 74 construction sites. Zero
destructures. Stage A risk moves **Medium → Low**.

### Probe 2 — CP-4 causal link

**Question:** do `language/eval-code` (62.6%) and `language/module-code`
(61.9%) low pass rates trace to module-level array side tables?

**Result:** No. Classified 508 failures by reason substring. Zero
reference `Array`, `realm`, `prototype chain`, or `side table`.

| Category | Fails | Actual root cause |
|---|---|---|
| eval-code | 389 | ~346 are Annex B §B.3.3 block-level function hoisting in eval scope (`runtime/hoisting.mbt`) |
| module-code | 119 | 91 are `Cannot find module './*_FIXTURE.js'` — `test262-runner.py` path resolver |

**CP-4 disproved.** The side-table ownership smell is real but does not
explain these pass rates. Stage D (realm hermeticity) demoted to
"architectural cleanup, ship when convenient."

Two high-ROI non-architectural items surface as byproducts:
- Annex B eval-scope hoisting fix in `hoisting.mbt` — ~346 tests.
- `_FIXTURE.js` path resolver in `test262-runner.py` — ~91 tests.

### Probe 3 — Stage B ordering

**Question:** which access path should the dispatcher migrate first?

**Result:** 168 Proxy failures classified by trap directory and root
cause. Ordering decision:

| Stage | Migration target | Proxy tests unlocked (est.) | Why this order |
|---|---|---|---|
| B.1 | `[[Set]]` via dispatcher in `property.mbt` | ~22 | smallest blast radius; monotonic signal; documented CP-1 issue |
| B.2 | `[[GetOwnProperty]]` + `[[DefineOwnProperty]]` | ~35–45 | larger win, needs nested-proxy unwrap complexity — deserves B.1 confidence first |
| B.3 | `[[HasProperty]]` (`in`, `with`, proto walk) | ~15 | widest surface; shares site with Stage C |

**Independent of Stage B** (parallel PRs):
- `construct` NewTarget threading (~12 tests) — fix in `construct.mbt`.
- `revocable` `typeof` post-revoke (~8 tests) — `ProxyData.is_callable`
  + `conversions.mbt` typeof branch.

Expected Proxy pass rate after Stages B + independents: ~86% (≈460/534).

### Probe 4 — Array side-table caller catalogue

**Question:** can side tables be fully expressed as `PropertyBag` entries,
or do they encode semantics the bag can't absorb?

**Result:** All 14 write sites + 12 read sites are mechanically migratable.

| Side table | Write sites | Read sites | Bag equivalent |
|---|---|---|---|
| `array_length_overrides` | 3 (`builtins_array_init.mbt:1846`, `property.mbt:1408/1410`) | 1 | `bag.properties["length"]` |
| `array_named_props` | 2 | 6 | `bag.properties` + `bag.descriptors` (→ unlocks Issue #1) |
| `array_symbol_props` | 1 | 6 | `bag.symbol_properties` |
| `array_iterator_overrides` | 2 | 1 | `bag.symbol_descriptors` (Symbol.iterator accessor) |

The 10M dense-allocation cap in `builtins_array_init.mbt:1840` is an
engineering OOM guard, not a spec artifact — preserve unchanged.

**Stage C risk: Medium-High → Low-Medium.** Regex match-result
`index`/`input`/`groups` become bag entries with descriptors, unlocking
Issue #1 automatically.

### Bonus audit — Map/Set/Promise destructure patterns

| Type | Construction literals | Pattern destructures | Existing factory |
|---|---|---|---|
| `MapData` | 2 (`builtins_map_set.mbt:412, 557`) | 0 | No |
| `SetData` | 1 (`builtins_map_set.mbt:847`) | 0 | No |
| `PromiseData` | 5 (1 factory `new_promise_data()` + 4 inline duplicates in `async.mbt`) | 0 | Yes (underused) |

The 4 duplicated `PromiseData` literals in `async.mbt:134, 556, 571, 585`
are pre-existing DRY debt — fold into `new_promise_data()` during
Stage A.

---

## 4. Migration Stages — Final Sizing

| Stage | LoC changed | Risk | Test delta (est.) |
|---|---|---|---|
| A — PropertyBag extraction + 4 factories + ~85 construction-site migrations | +type, +6 factories, ~85 call-site edits, 4 async.mbt cleanups | **Low** | 0 (pure refactor) |
| B.1 — `[[Set]]` dispatcher | ~50 call sites routed through `property.mbt` | Low-Medium | +~22 Proxy |
| B.2 — `[[GetOwnProperty]]` + `[[DefineOwnProperty]]` | ~70 call sites + nested-unwrap | Medium | +~35–45 Proxy |
| **C — ArrayData.bag** | 14 write + 12 read migrations, 1 file deletion (139 LoC) | Low-Medium | +~700 Array + ~6 regex + Issue #1 |
| B.3 — `[[HasProperty]]` dispatcher | 3 call sites (`in`, `with`, proto walk) | Low-Medium | +~15 Proxy |
| D — Realm hermeticity | Move `StdlibHooks` onto `Interpreter`; grep-assert no module-level mut | Low | 0 (cleanup) |

**Ship order:** A → B.1 → B.2 → **C** (before B.3, they share a site) → B.3 → D. Independents (`construct`, `revocable`) in parallel when convenient.

---

## 5. Verification Plan

| Stage | Gate |
|---|---|
| A | `moon check && moon test`; test262 delta = 0 |
| B.1 | `--filter "built-ins/Proxy" --summary` shows ≥15-test rise; stop and re-examine if not |
| B.2 | Proxy rise ≥35; Object filter also positive |
| C | `--filter "built-ins/Array"` rises; regex match-result descriptor visibility smoke test passes (Issue #1) |
| B.3 | Proxy rise ≥10; no `has` regression |
| D | New unit test: two `Interpreter` instances run independently with Array mutations; no cross-contamination |

All stages: 881 unit tests pass; overall test262 pass rate monotonic.

---

## 6. Scope

**Included:** PropertyBag + dispatcher + Array bag migration + realm
hermeticity cleanup.

**Excluded:** parser/AST changes, new JS features (for-await, class
fields), bytecode, TypedArray internals, `cmd/main` public interface,
`eval_expr.mbt`/`exec_stmt.mbt` further splitting (not motivated).

**Deferred (Stage D):** realm hermeticity shipping. Architectural
completion; low urgency after CP-4 disproved. Ship when multi-interpreter
use case emerges or Stage C surfaces cross-contamination bugs.

---

## 7. Non-architectural items surfaced

Track separately in `docs/agent-todo.md`:

1. **Annex B eval-scope hoisting** — `runtime/hoisting.mbt`, ~346 tests.
2. **test262 runner `_FIXTURE.js` path resolver** — `test262-runner.py`, ~91 tests.
3. **`async.mbt` PromiseData literal cleanup** — fold 4 inline literals into `new_promise_data()` (bundled with Stage A).

---

## 8. Unknowns Remaining

- MoonBit embedded-struct allocation behavior — verify `PropertyBag` is
  stack-allocated before Stage A merge (reuse ExecContext benchmark from
  April-15 Stage 1).
- Whether `built-ins/Object` pass rate rises during Stage B.2 — likely
  but unverified.
