# Host Internal Slots Design

**Date:** 2026-07-11  
**Status:** Approved — ready for implementation plan  
**Issue:** [#518](https://github.com/dowdiness/js_engine/issues/518)  
**Motivation:** crater (and other embedders) need object-attached host bookkeeping that is invisible to user JavaScript.

## Problem

Embedders currently stash host data in ordinary properties:

```moonbit
data.bag.properties["__crater_nid"] = Value::Number(nid.to_double())
```

That is visible to `Object.keys`, `for…in`, `JSON.stringify`, and accidental user overwrite.

The engine already has `PropertyBag.internal_slots : Map[InternalSlotKey, Value]`, which is correctly invisible to property enumeration. But `InternalSlotKey` is a **closed** engine enum (`StringData`, `DateValue`, …). There is no way for a host to allocate a new key or to read/write host-owned slots through a public API.

## Decision (first principles)

**Use a separate host-slot map, not a shared `InternalSlotKey` namespace.**

| | Engine `internal_slots` | Host `host_slots` |
|---|---|---|
| Key space | Closed, spec-shaped enum | Open-ended, embedder-owned |
| Invariants | Engine correctness | Host bookkeeping only |
| Supported API | Runtime / stdlib typed accessors | Embedder `HostSlotKey` + get/set/delete/has |

Engine slots and host slots are both “invisible object state,” but they differ in ownership, growth model, and invariant strength. Unifying them under `InternalSlotKey::Host(Int)` couples two concerns and invites accidental namespace mixing through a shared key type.

**Boundary strength:** Separate maps are an **API convention and accident-prevention boundary**, not a hard capability firewall. `PropertyBag` remains `pub(all)`, so a determined embedder can still write `bag.host_slots[forged_id]`, mutate another host’s entries, or touch `internal_slots` directly — the same openness that already exists for engine slots today. What separation *does* buy:

1. Official accessors never mix host ids with `InternalSlotKey` variants.
2. Well-behaved embedders using only `HostSlotKey::reserve` + get/set cannot accidentally overwrite `StringData` / `ArrayBufferID` through the supported API.
3. Engine code continues to ignore `host_slots` for JS semantics.

True structural enforcement would require opaque `PropertyBag` fields (or a facade that does not expose the bag). That is explicitly out of scope; see Non-goals.

Prior art aligns with separation at the embedding boundary: V8 internal fields and QuickJS opaque pointers are host channels distinct from the engine’s own hidden slots. WebIDL host slots are conceptually ES internal slots, but engines still keep them off the core builtin-slot tables.

## Architecture

```
PropertyBag
├── properties / symbol_properties / descriptors…   ← JS-visible
├── internal_slots : Map[InternalSlotKey, Value]     ← engine only (unchanged)
└── host_slots     : Map[Int, Value]                 ← embedder only (new)
                     ▲
                     └── keyed by opaque HostSlotKey.id
```

Property ops (`[[OwnPropertyKeys]]`, freeze/seal enumeration, `for…in`, etc.) already ignore `internal_slots`. They must likewise never consult `host_slots`. No change to JS-observable semantics for existing programs.

## Public API

All new symbols live in `@js_engine/interpreter/runtime` (same package as `InternalSlotKey` / `PropertyBag`).

### Opaque key

```moonbit
/// Embedder-owned slot identity. Construct only via `HostSlotKey::reserve`.
pub(all) struct HostSlotKey {
  priv id : Int
} derive(Eq, Hash, Debug)

/// Allocate a unique host slot key within this loaded runtime package instance.
/// Call once at module init (or once per host-data kind) and reuse.
/// Aborts (or fails) if the allocator is exhausted — never wraps silently.
pub fn HostSlotKey::reserve() -> HostSlotKey
```

- Allocation uses a package-private monotonic counter (`Ref[Int]`), starting at `0`.
- **Uniqueness contract:** unique among keys returned by `reserve()` in **one loaded `@…/interpreter/runtime` package instance**, until the counter would overflow. This is *not* a stronger “process-wide forever” guarantee: a second independently loaded copy of the module has its own counter; wrapping must not reuse ids silently.
- **Overflow:** if the next id would exceed `Int`’s positive range (or a documented max), `reserve()` aborts via `fail`/`abort` (implementation picks the project-conventional defect path). Do not wrap to `0`.
- Keys are comparable / hashable so hosts can store them in their own tables if needed.
- No debug-name parameter in v1 (keeps the type a pure id). Revisit if crater debugging needs it.
- Constructing `HostSlotKey` from a raw `Int` via the public type is impossible (`priv id`). Embedders can still forge map keys by writing `bag.host_slots[n]` directly because `PropertyBag` is `pub(all)` — see Decision § Boundary strength. The opaque key protects the supported API path only.

### ObjectData accessors

Match the existing Pattern B style in `internal_slots.mbt`:

```moonbit
pub fn get_host_slot(data : ObjectData, key : HostSlotKey) -> Value?
pub fn set_host_slot(data : ObjectData, key : HostSlotKey, value : Value) -> Unit
pub fn delete_host_slot(data : ObjectData, key : HostSlotKey) -> Unit
pub fn has_host_slot(data : ObjectData, key : HostSlotKey) -> Bool
```

Semantics:

| Op | Behavior |
|---|---|
| `get_host_slot` | `Some(v)` if present; `None` if absent (not `Some(Undefined)` unless the host stored `Undefined`) |
| `set_host_slot` | Insert or overwrite |
| `delete_host_slot` | Remove key if present; no-op if absent |
| `has_host_slot` | Presence check (true even when stored value is `Undefined`) |

### PropertyBag helpers (for non-ObjectData bags)

`ArrayData`, callables, and other bag-bearing variants also need host attachment. Expose thin bag-level ops so callers with a `PropertyBag` do not have to go through `ObjectData`:

```moonbit
pub fn PropertyBag::get_host_slot(self : PropertyBag, key : HostSlotKey) -> Value?
pub fn PropertyBag::set_host_slot(self : PropertyBag, key : HostSlotKey, value : Value) -> Unit
pub fn PropertyBag::delete_host_slot(self : PropertyBag, key : HostSlotKey) -> Unit
pub fn PropertyBag::has_host_slot(self : PropertyBag, key : HostSlotKey) -> Bool
```

`ObjectData` helpers are one-liners over `data.bag.*`.

### Embedder usage (crater)

```moonbit
let CRATER_NID : HostSlotKey = HostSlotKey::reserve()

// attach
set_host_slot(data, CRATER_NID, Value::Number(nid.to_double()))

// read
match get_host_slot(data, CRATER_NID) {
  Some(Value::Number(n)) => … // host nid
  _ => … // missing
}
```

User JS cannot see, enumerate, or overwrite this slot via ordinary property operations.

## Storage & construction changes

1. Add `host_slots : Map[Int, Value]` to `PropertyBag`.
2. Initialize to `{}` in `PropertyBag::PropertyBag()`.
3. Update every struct-literal `PropertyBag { …, internal_slots: … }` construction site to include `host_slots: {}` (or copy existing `host_slots` when cloning a bag). Prefer routing new empty bags through `PropertyBag()` to minimize literal churn where practical.
4. Engine code must not read or write `host_slots` for JS semantics.

**Map key representation:** store `Int` (the opaque id) in the map, not `HostSlotKey`, so the bag field type stays simple and does not force `HostSlotKey` into every bag literal. Accessors unwrap/wrap the opaque key at the API boundary.

## Copy / identity semantics

| Operation | `host_slots` |
|---|---|
| Property get/set/define/delete/enumerate | Ignored (not properties) |
| Same-object identity (`ObjectData` moved/aliased) | Shared bag → slots preserved |
| Any future deep `PropertyBag` clone | **Copy** `host_slots` with the bag (same rule as `internal_slots`: part of object state, not JS properties) |
| Structured clone / serialization to JS | Out of scope; host must re-attach after revive |

## Facade / re-exports

- Primary surface: `@js_engine/interpreter/runtime` (`HostSlotKey`, get/set/delete/has).
- Do **not** re-export through the root `@js_engine` facade in this slice unless an embedder already depends only on the facade for `ObjectData`/`Value`. crater’s integration path uses runtime types directly today; confirm at implementation time and add `pub using` only if needed.
- Do **not** expose raw `host_slots` mutation helpers beyond the four ops above. The `pub(all)` field remains visible (consistent with `internal_slots`) but the supported contract is the accessor API.

## Tests

### `interpreter/runtime` (unit / whitebox)

Runtime cannot initialize `Object.keys` / `JSON.stringify` without importing `interpreter/stdlib`, which already depends on runtime — that would be a cycle. Keep accessor tests here only:

1. **Round-trip** — `set` then `get` returns the value; `has` is true; `delete` then `get` is `None` / `has` false.
2. **Undefined is storable** — `set(…, Undefined)` → `get` is `Some(Undefined)` and `has` is true (presence ≠ undefined-as-absent).
3. **Key uniqueness** — two `reserve()` calls yield unequal keys; writing one does not affect the other.
4. **Isolation from engine slots (API path)** — setting a host slot via `set_host_slot` does not change `internal_slots` contents for a known engine key (e.g. after installing `StringData`).

### `interpreter` or `interpreter/stdlib` (eval-based)

Place the JS-observability test where builtins are available (prefer `interpreter` blackbox tests that already spin up a full interpreter):

5. **Invisible to JS** — set a host slot on an object exposed to script; `Object.keys` / `for…in` / `JSON.stringify` do not surface it; ordinary property get of a colliding string name is unaffected.

No test262 changes expected (host API is outside the ES surface).

## Non-goals

- Extending `InternalSlotKey` with a `Host` variant or sharing one map
- Host slots on primitive values (no bag)
- Per-realm or per-interpreter key namespaces (one counter per loaded runtime package instance is enough)
- Process-wide / cross-module-instance uniqueness stronger than the loaded-package counter
- Debug names / string labels on keys (v1)
- Automatic migration of crater’s `__crater_nid` property (crater follow-up after this lands)
- Weak host slots / GC-aware host references (values are ordinary `Value`s; host must not create cycles it cannot break)
- Making `PropertyBag` / `host_slots` / `internal_slots` field-opaque (would be a real capability boundary; larger refactor, not this slice)

## Rejected alternative: shared map + `InternalSlotKey::Host(Int)`

Rejected because:

1. Closed enum + open host allocation are opposing growth models.
2. A shared key type makes accidental mixing through the supported API easy (`Host(n)` next to `StringData`).
3. Engine and host *intended* invariant domains should not share one table even when `pub(all)` bags already allow raw field access.

The only advantage (one field / one lookup path) does not justify the coupling. Note: separate maps do not by themselves stop raw `bag.*` mutation; opacity of bag fields would be a different, larger change.

## Implementation sketch

1. Add `HostSlotKey` + counter + bag field + accessors (new file `interpreter/runtime/host_slots.mbt` or extend `internal_slots.mbt` — prefer **new file** to keep engine Pattern B helpers separate from embedder API).
2. Update `PropertyBag` + constructor + literal sites; `moon check`.
3. Add tests; `moon test -p interpreter/runtime`.
4. `moon info && moon fmt`; verify `.mbti` exports.
5. Close #518 with API summary pointing at this spec.

## Success criteria

- Embedder can attach host data with `HostSlotKey::reserve` + `set_host_slot` / `get_host_slot`.
- User JS cannot observe host slots via ordinary property operations.
- Engine `InternalSlotKey` / `internal_slots` unchanged in semantics.
- No test262 regression attributable to the bag-shape change.
