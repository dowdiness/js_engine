# make_host_object Design

**Date:** 2026-07-11  
**Status:** Approved — ready for implementation plan  
**Issue:** [#517](https://github.com/dowdiness/js_engine/issues/517)  
**Depends on:** [#518](https://github.com/dowdiness/js_engine/issues/518) / PR [#522](https://github.com/dowdiness/js_engine/pull/522) (host slots — landed)  
**Motivation:** Embedders (crater) create many host wrappers with methods, accessors, and private identity. Today that requires `make_object` → match `ObjectData` → repeated `install_builtin_*` / bag writes.

## Problem

Current crater-style pattern:

```moonbit
let el = make_object(props, Null, None, "Element", descs, true)
match el {
  Value::Object(data) => {
    install_builtin_method(data, "setAttribute", set_attr)
    install_builtin_method(data, "appendChild", append_child)
    data.bag.properties["__crater_nid"] = Value::Number(nid.to_double())
  }
  _ => ()
}
```

Problems:

1. Ceremony — allocate, match, install one-by-one
2. Easy to forget descriptors when writing the bag directly
3. Host bookkeeping was incorrectly modeled as a JS-visible property (fixed as a concept by #518; this helper must use host slots, not `~properties`)

## Decision (first principles)

A host object is one unit of work: **JS-visible surface + host-private state**.

| Concern | Channel |
|---|---|
| Methods | `install_builtin_method` descriptors |
| Attributes | paired accessors (one ES property, optional get/set) |
| Rare constant data | intent-shaped `non_writable` / `frozen` maps |
| Private identity / nid | `HostSlotKey` + `set_host_slot` (#518) |

Therefore:

- Provide a **labelled factory** that returns `Value` (no caller-side `ObjectData` match)
- Compose existing install helpers — do not invent a parallel descriptor policy
- **No** catch-all `~properties: Map[String, Value]` (hides descriptor choice; recreates the `__crater_nid` footgun)
- Accessors are **paired**, not separate getter/setter maps (matches ES descriptors and `install_builtin_accessor`)
- Include optional `~host_slots` so private state does not force a second match
- No typestate builder — there is no stage/XOR invariant to enforce; all inputs are optional and order-independent for validity

## Public API

Lives in `@js_engine/interpreter/runtime` beside `make_object`:

```moonbit
pub fn make_host_object(
  name~ : String,
  proto~ : Value = Null,
  methods~ : Map[String, Value] = {},
  accessors~ : Map[String, (Value?, Value?)] = {},
  non_writable~ : Map[String, Value] = {},
  frozen~ : Map[String, Value] = {},
  host_slots~ : Map[HostSlotKey, Value] = {},
  extensible~ : Bool = true,
) -> Value
```

### Call-site shape (crater)

```moonbit
let el = make_host_object(
  name="Element",
  proto=element_proto,
  methods={"setAttribute": set_attr, "appendChild": append_child},
  accessors={
    "textContent": (Some(text_get), Some(text_set)),
    "nodeType": (Some(node_type_get), None),
  },
  host_slots={NID_SLOT: Value::Number(nid.to_double())},
)
```

## Behavior

1. Allocate with `make_object({}, proto, None, name, {}, extensible)`.
2. Match once internally to `ObjectData`; if not an object, `abort` (invariant).
3. Install in this order:
   1. `non_writable` → `install_builtin_non_writable`
   2. `frozen` → `install_builtin_frozen_data`
   3. `methods` → `install_builtin_method`
   4. `accessors` → `install_builtin_accessor`
   5. `host_slots` → `set_host_slot`
4. Return the `Value`.

**Same-key across JS maps:** later step wins (documented). Embedders should not dual-define the same string key across maps.

**Accessor pairs:** `(Some, Some)` / `(Some, None)` / `(None, Some)` are valid. `(None, None)` is a defect → `abort` in `install_builtin_accessor` (single-sourced; `make_host_object` relies on that helper).

Use `None` for an absent accessor side, not `Some(Undefined)`, unless intentionally mimicking `{ get: undefined }` / `{ set: undefined }`.

Note: today’s `install_builtin_accessor` takes `getter : Value?` and `setter : Value?`. Do not pass a dummy `Undefined` getter — that would make `[[Get]]` invoke a non-callable.

**Defaults:** empty maps + `proto=Null` + `extensible=true` yield a named empty host shell. `proto=Null` is intentional — not `%Object.prototype%`; callers pass a realm prototype when needed.

## Placement

- Implementation: `interpreter/runtime/factories.mbt` (creation API), calling `builtin_install.mbt` + `host_slots.mbt`
- Tests: whitebox under `interpreter/runtime/` (`factories_wbtest.mbt` or dedicated `host_object_wbtest.mbt`)
- Do **not** re-export through the root `@js_engine` facade in this slice unless implementation discovers a hard facade-only dependency (same stance as #518)

## Testing

1. Methods + accessors land with correct builtin descriptors
2. `non_writable` / `frozen` flags are correct
3. Host slots round-trip via `get_host_slot` and stay invisible to ordinary property enumeration
4. Name-only call: extensible object with expected `class_name`
5. Panic test: `(None, None)` accessor
6. One same-key overwrite case across maps (later step wins)

## Non-goals

- Builder / typestate API
- Symbol-keyed install maps (existing `install_builtin_symbol_*` remain manual)
- Custom `PropDescriptor` escape hatch inside this helper
- Catch-all writable `~properties` map
- crater adoption / migration in the same PR
- Root facade re-export (unless forced at implement time)

## Alternatives rejected

| Option | Why not |
|---|---|
| Surface-only factory (no `host_slots`) | Callers still match `ObjectData` for private state — incomplete vs #517 goal |
| Separate `~getters` / `~setters` | Fights ES one-property accessor model and `install_builtin_accessor` |
| Catch-all `~properties` | Silent descriptor policy; invites visible “private” data |
| Fatten `make_object` | Mixes ordinary construction with host/builtin install policy |
| Typestate builder | No stage invariant; optional fields already valid in any order |

## Rollout

1. Branch from `main` that includes #522 host-slot API
2. Land `make_host_object` + wbtests + `moon info`
3. crater adopts in a follow-up
