# Stage 8 Static-Attach Design

**Date:** 2026-06-14
**Status:** Approved — ready for implementation plan

## Problem

The `make architecture-audit` scanner tracks representation access (bag-field reads/writes) in `interpreter/stdlib`. Two categories of access remain:

- **Pattern A — assembly-time static-attach writes:** stdlib setup functions write directly into `bag.properties`/`bag.descriptors` to install methods and accessors onto prototype objects at startup.
- **Pattern B — internal-slot reads:** stdlib method implementations read internal state (TypedArray buffer, length, offset; Map/Set iterator state; Boolean data) directly from `bag.properties`/`bag.symbol_properties`.

Pattern C (runtime `Object.defineProperty` writes in `builtins_object.mbt`) is out of scope — those already implement correct spec semantics and routing through another layer would be wrong.

## Architecture

Two new files in `interpreter/runtime/`:

```
interpreter/runtime/builtin_install.mbt   ← Pattern A: typed install helpers
interpreter/runtime/internal_slots.mbt    ← Pattern B: typed slot accessors
```

`interpreter/stdlib/builtin_install_helpers.mbt` is **deleted** — its contents move into `builtin_install.mbt`. `builtin_method_desc` becomes private to the new file. All stdlib callers import install ops from `@runtime`.

**Semantics:** All ops use raw bag writes/reads — NOT routed through `ordinary_define_own_property`. Assembly-time setup always works on fresh extensible objects where both approaches are equivalent; the pilot discipline (PR #247) establishes that install helpers are setup-time metadata shims, not property-semantics operations.

**Proof:** Symmetric failing-SET diff (both comm directions) as used in #340/#341/#343 — applies to both patterns since raw reads/writes cannot change observable behavior relative to current code.

## Pattern A — Typed Install Helpers

All ops live in `interpreter/runtime/builtin_install.mbt`.

### String-keyed ops

| Op | Descriptor shape | Covers |
|---|---|---|
| `install_builtin_method(data, name, func)` | `{w:t, e:f, c:t}` | Methods, constructor back-links |
| `install_builtin_accessor(data, name, getter, setter: Value?)` | `{is_accessor:true}` | @@species getter, length getters |
| `install_builtin_non_writable(data, name, value)` | `{w:f, e:f, c:t}` | name/length data props, @@toStringTag value |
| `install_builtin_frozen_data(data, name, value)` | `{w:f, e:f, c:f}` | Constructor's "prototype" property |

### Symbol-keyed ops (write into `bag.symbol_properties`/`bag.symbol_descriptors`)

| Op | Descriptor shape | Covers |
|---|---|---|
| `install_builtin_symbol_method(data, sym_id, func)` | `{w:t, e:f, c:t}` | @@iterator, @@hasInstance |
| `install_builtin_symbol_accessor(data, sym_id, getter)` | `{is_accessor:true}` | @@species |
| `install_builtin_symbol_string(data, sym_id, tag)` | `{w:f, e:f, c:t}` | @@toStringTag string value |

### Scope exclusion

`builtins_string.mbt` is excluded from Pattern A. Two writes do not fit the typed-helper model:
- `builtins_string.mbt:1987-1988`: property alias copies (`trimLeft = trimStart`, `trimRight = trimEnd`) with no descriptor — adding a descriptor here would be a behavior change for `Object.getOwnPropertyDescriptor`.
- `builtins_string.mbt:1990`: `data.bag.properties["constructor"] = Undefined` with no descriptor — intentional erasure pattern.

These are filed as a follow-up slice.

## Pattern B — Typed Slot Accessors

All ops live in `interpreter/runtime/internal_slots.mbt`. Each is a thin wrapper over `bag.properties.get`/`bag.symbol_properties.get` (or the write equivalent). The architecture win is that `interpreter/stdlib` no longer accesses the bag field directly for internal-state reads.

### TypedArray slots

| Op | Slot key |
|---|---|
| `get_typedarray_viewed_buffer(data) -> Value?` | `"[[ViewedArrayBuffer]]"` |
| `get_typedarray_array_length(data) -> Value?` | `"[[ArrayLength]]"` |
| `get_typedarray_byte_length(data) -> Value?` | `"[[ByteLength]]"` |
| `get_typedarray_byte_offset(data) -> Value?` | `"[[ByteOffset]]"` |
| `get_typedarray_buffer_id(data) -> Value?` | `"[[ArrayBufferID]]"` |

### ArrayBuffer slots (read from buffer object during TypedArray construction)

| Op | Slot key |
|---|---|
| `get_arraybuffer_byte_length(data) -> Value?` | `"[[ArrayBufferByteLength]]"` |
| `get_arraybuffer_id(data) -> Value?` | `"[[ArrayBufferID]]"` |

### Other object slots

| Op | Key | Used in |
|---|---|---|
| `get_boolean_data(data) -> Value?` | `"[[BooleanData]]"` | `builtins.mbt` |
| `get_map_iterator_target(data) -> Value?` | symbol `MAP_ITERATOR_TARGET_SYMBOL_ID` | `builtins_map_set.mbt` |
| `get_map_iterator_next_index(data) -> Value?` | symbol `MAP_ITERATOR_NEXT_INDEX_SYMBOL_ID` | `builtins_map_set.mbt` |
| `get_map_iterator_kind(data) -> Value?` | symbol `MAP_ITERATOR_KIND_SYMBOL_ID` | `builtins_map_set.mbt` |
| `set_map_iterator_next_index(data, value)` | write to same symbol | `builtins_map_set.mbt:195` |
| `detach_map_iterator_target(data)` | write `Undefined` to target symbol | `builtins_map_set.mbt:191` |

## Pilot Scope and Fan-Out Order

**Pilot: `builtins_error.mbt`** (390 lines)

Exercises only `install_builtin_method` (constructor back-link at lines 183–192, 377–386). No Pattern B slots. Symmetric-diff proof on `FILTER=Error`. Establishes the runtime import pattern before touching large files.

**Fan-out after pilot:**

1. `builtins_arraybuffer.mbt` — Pattern A only (constructor back-link)
2. `builtins_map_set.mbt` — Pattern A (prototype, constructor, symbol ops) + Pattern B (iterator slots)
3. `builtins.mbt` — Pattern A (constructor back-link, prototype, symbol @@species/@@hasInstance) + Pattern B (boolean slot)
4. `builtins_typedarray.mbt` — Pattern A (constructor back-links) + Pattern B (TypedArray + ArrayBuffer slots)
5. Remaining files (`builtins_dataview.mbt`, others) — Pattern A where applicable

Full per-mode test262 baseline at fan-out completion (not per step). Per-step proof is symmetric-diff only.

## Non-Goals

- Routing through `ordinary_define_own_property` — not this slice
- Covering `builtins_string.mbt` alias/erasure patterns — follow-up
- Covering runtime `Object.defineProperty` writes in `builtins_object.mbt` — Pattern C, separate future slice
- Covering Promise, WeakMap/WeakSet, or Date internal slots — discovered during fan-out, handled then
- Stage 9 (calls/direct-eval) — deferred
