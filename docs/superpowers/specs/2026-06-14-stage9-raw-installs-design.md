# Stage 9 Raw Installs Design

**Date:** 2026-06-14  
**Status:** Design (not yet implemented)  
**Builds on:** Stage 8 static-attach PR #345 (`539fc41`)

## Scope clarification

The formal Stage 9 in `docs/architecture-execution-plan-2026-06-12.md` covers *calls and direct-eval routing*. This document describes a **pre-Stage-9 raw-installs slice**: migrating the remaining raw `bag.properties`/`bag.descriptors` writes for `"constructor"` and `"prototype"` in 9 stdlib files that Stage 8 deferred. Calls/direct-eval is a separate concern and is explicitly excluded here.

## What was deferred from Stage 8

Stage 8 (PRs #344 + #345) created `interpreter/runtime/builtin_install.mbt` with string-keyed and symbol-keyed install helpers, and migrated 5 stdlib files (builtins_error, builtins_arraybuffer, builtins_map_set, builtins.mbt, builtins_typedarray). It left 9 stdlib files with raw writes for `"constructor"` and `"prototype"` keys.

## Complete inventory

Name-agnostic grep (searching `.bag.(properties|descriptors)["constructor"|"prototype"]` across all 9 files at HEAD `539fc41`):

| # | File | Line(s) | Property | Descriptor shape | Classification | Replacement |
|---|------|---------|----------|-----------------|---------------|-------------|
| 1 | builtins_weakmap_set.mbt | 606/607 | `"prototype"` | `{w:f,e:f,c:f}` frozen | **in-scope** | `install_builtin_frozen_data` |
| 2 | builtins_weakmap_set.mbt | 623/624 | `"constructor"` | `{w:t,e:f,c:t}` method | **in-scope** | `install_builtin_method` |
| 3 | builtins_weakmap_set.mbt | 882/883 | `"prototype"` | `{w:f,e:f,c:f}` frozen | **in-scope** | `install_builtin_frozen_data` |
| 4 | builtins_weakmap_set.mbt | 899/900 | `"constructor"` | `{w:t,e:f,c:t}` method | **in-scope** | `install_builtin_method` |
| 5 | builtins_array_init.mbt | 1440/1441 | `"constructor"` | `{w:t,e:f,c:t}` method | **in-scope** | `install_builtin_method` |
| 6 | builtins_dataview.mbt | 1035/1036 | `"constructor"` | `{w:t,e:f,c:t}` method | **in-scope** | `install_builtin_method` |
| 7 | builtins_date.mbt | 1948/1949 | `"constructor"` | `{w:t,e:f,c:t}` method | **in-scope** | `install_builtin_method` |
| 8 | builtins_function.mbt | 492/493 | `"constructor"` | `{w:t,e:f,c:t}` method | **in-scope** | `install_builtin_method` |
| 9 | builtins_number.mbt | 611/612 | `"constructor"` | `{w:t,e:f,c:t}` method | **in-scope** | `install_builtin_method` |
| 10 | builtins_object.mbt | 1297/1298 | `"constructor"` | `{w:t,e:f,c:t}` method | **in-scope** | `install_builtin_method` |
| 11 | builtins_promise.mbt | 1339/1340 | `"constructor"` | `{w:t,e:f,c:t}` method | **in-scope** | `install_builtin_method` |
| 12 | builtins_symbol.mbt | 330/331 | `"constructor"` | `{w:t,e:f,c:t}` method | **in-scope** | `install_builtin_method` |
| — | builtins_promise.mbt | 277/278 | `"constructor"` | `{w:t,e:f,c:t}` | **out-of-scope** (A) | see below |
| — | builtins_promise.mbt | 1332 | `"prototype"` | *no descriptor* | **out-of-scope** (B) | see below |

**Total: 12 in-scope sites** (10 `install_builtin_method`, 2 `install_builtin_frozen_data`) across 9 files.

### Note on the memory count (11 vs 12)

The architecture redesign memory file (`project_architecture_redesign_2026_06_12.md`) says "11 raw ctor/proto installs." The actual source count at `539fc41` is 12 in-scope sites. The discrepancy of 1 likely reflects a prior estimation; the grep is authoritative.

## Out-of-scope exclusions

### (A) promise:277 — PromiseData instance-level write

```moonbit
// builtins_promise.mbt:277
Object(od) => {
  promise_data.bag.properties["constructor"] = ctor
  promise_data.bag.descriptors["constructor"] = { writable: true, ... }
}
```

`promise_data` is a `PromiseData` value (not `ObjectData`). The existing `install_builtin_method` helper takes `data : ObjectData`. More critically, this write is **per-construction**, not realm-init: it sets `constructor` on each freshly-created Promise instance so that `SpeciesConstructor` lookups can find the right constructor during `then`/`catch`/`finally` chaining. A source comment says exactly this. There is no realm-init parallel and no applicable helper.

### (B) promise:1332 — property-only write, no descriptor

```moonbit
// builtins_promise.mbt:1332
Object(od) => od.bag.properties["prototype"] = promise_proto
```

`od` is an `ObjectData`, but there is no paired `bag.descriptors["prototype"]` write. Every other in-scope site has a matched pair. Migrating this site with `install_builtin_frozen_data` would add a descriptor that does not currently exist, which is a behavior change, not a refactor. This anomaly (the ES2024 spec mandates `Promise.prototype` = `{w:f,e:f,c:f}` per §27.2.4) is a pre-existing issue to investigate separately.

### (C) builtins_string.mbt alias/erasure writes

Stage 8 also excluded the string-key alias/erasure writes in builtins_string.mbt. Those remain out of scope here.

## Why no new helper is needed

All 12 in-scope sites map directly to existing helpers in `interpreter/runtime/builtin_install.mbt`:

| Descriptor shape | Existing helper | Sites |
|-----------------|-----------------|-------|
| `{w:t,e:f,c:t}` (method/constructor backref) | `install_builtin_method` | 10 |
| `{w:f,e:f,c:f}` (frozen) | `install_builtin_frozen_data` | 2 |

The `"constructor"` sites use `install_builtin_method` even though the stored value is a constructor, not a method. This is not a naming mismatch — `install_builtin_method` encodes the `{w:t,e:f,c:t}` descriptor shape; the ES spec mandates this exact shape for `.prototype.constructor` in each built-in's individual section (e.g., ES2024 §20.1.3.1 for Number, §27.2.5.1 for Promise). The `builtins_map_set.mbt` migration (Stage 8) set this precedent and should be followed here without inventing a new helper name.

## Construction path asymmetry

Only WeakMap/WeakSet and Promise have raw `bag.properties["prototype"]` writes for the constructor's `.prototype` property. Array, DataView, Date, Function, Number, Object, Symbol use a different construction path: they build the constructor's property map as a plain `Map[String, Value]` (e.g., `array_props["prototype"] = array_proto` at builtins_array_init.mbt:1158) and then assemble the `ObjectData`. Those writes are not bag-field accesses and are not in scope.

## Migration pattern

Reference: `builtins_map_set.mbt` (already migrated in Stage 8).

**Before (in-scope sites):**
```moonbit
match some_proto {
  Object(data) => {
    data.bag.properties["constructor"] = ctor
    data.bag.descriptors["constructor"] = {
      writable: true,
      enumerable: false,
      configurable: true,
      getter: None,
      setter: None,
      is_accessor: false,
    }
  }
  _ => ()
}
```

**After:**
```moonbit
match some_proto {
  Object(data) => @runtime.install_builtin_method(data, "constructor", ctor)
  _ => ()
}
```

**Before (prototype sites, weakmap_set):**
```moonbit
match ctor_val {
  Object(data) => {
    data.bag.properties["prototype"] = proto
    data.bag.descriptors["prototype"] = {
      writable: false,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
      is_accessor: false,
    }
  }
  _ => ()
}
```

**After:**
```moonbit
match ctor_val {
  Object(data) => @runtime.install_builtin_frozen_data(data, "prototype", proto)
  _ => ()
}
```

Each site is a mechanical substitution; no semantic change.

## Verification plan

### 1. Architecture audit

**Current audit state:** `make architecture-audit` is currently failing on stale `runtime-prop-descriptor-type` entries in several files (`builtins.mbt`, `builtins_number.mbt`, `builtins_object.mbt`, `builtins_map_set.mbt`, `builtins_reflect.mbt`, `builtins_weakmap_set.mbt`). These mismatches are a Stage-8 leftover — Stage 8 PR #345 reduced inline `PropDescriptor` literals but the allowlist fingerprints were not updated. Stage 9 must repair the allowlist for those stale entries as well as update the 9 target files' entries.

**Expected delta for Stage 9 (per file, `representation-bag-field` category):**

| File | Current count | Sites removed | New count |
|------|--------------|---------------|-----------|
| builtins_array_init.mbt | 5 | 1 × 2 | 3 |
| builtins_dataview.mbt | 8 | 1 × 2 | 6 |
| builtins_date.mbt | 9 | 1 × 2 | 7 |
| builtins_function.mbt | 2 | 1 × 2 | 0 (entry deleted) |
| builtins_number.mbt | 3 | 1 × 2 | 1 |
| builtins_object.mbt | 60 | 1 × 2 | 58 |
| builtins_promise.mbt | 9 | 1 × 2 | 7 |
| builtins_symbol.mbt | 6 | 1 × 2 | 4 |
| builtins_weakmap_set.mbt | 10 | 4 × 2 | 2 |

Total `representation-bag-field` delta: **−24** across the 9 files. Additionally, 12 inline `PropDescriptor` literals (`{ writable: ..., enumerable: false, ... }` bodies) are removed from the 9 target files, reducing each file's `runtime-prop-descriptor-type` count by 1.

Each in-scope site is accounted as:
- 1 `representation-bag-field` access per `data.bag.properties[key] = value` write
- 1 `representation-bag-field` access per `data.bag.descriptors[key] = { ... }` write
- 1 `runtime-prop-descriptor-type` access per inline descriptor literal

The `@runtime.install_builtin_method(data, "key", value)` call is NOT a new representation access — `interpreter/runtime/` is inside the allowed ownership boundary, not in the scan roots.

After migration, update the allowlist fingerprints in `scripts/architecture_representation_access.json`: run `make architecture-audit` to see the "found" fingerprint for each failing entry, then update the `allowed_count` and `fingerprint` fields in the JSON to match. This must fix both the Stage-8 stale entries (listed above) and the Stage-9 migration entries. Confirm `make architecture-audit` passes with no remaining mismatches.

To enumerate representation accesses by line before editing: `./_build/native/debug/build/cmd/architecture_boundary_audit/architecture_boundary_audit.exe --root . --list-representation`

### 2. Symmetric failing-SET diff (behavior-preserving proof)

Same protocol as Stage 8 slices. Run the test262 suite on both base and branch, extract the failing-test set for each mode, and verify zero diff in both directions:

```bash
# Both commands must produce no output
comm -23 <(sort failing_base.txt) <(sort failing_branch.txt)   # no regressions
comm -13 <(sort failing_base.txt) <(sort failing_branch.txt)   # no accidental fixes
```

If any test moves from failing to passing (or vice versa), that is a scope error — this migration must be behavior-transparent.

**Worktree note:** If implementation runs in an isolated worktree, the `test262/` directory is absent. Run the test262 steps against the main tree, not the worktree.

### 3. Unit tests

```bash
moon test
```

Must pass with zero failures before and after.

## Scope of this PR

- **In:** The 12 in-scope raw `bag.properties`/`bag.descriptors` write pairs
- **Out:** promise:277 (instance-level PromiseData write)
- **Out:** promise:1332 (property-only anomaly, missing descriptor)
- **Out:** builtins_string.mbt alias/erasure writes
- **Out:** Calls and direct-eval routing (formal Stage 9 per execution plan)
- **Out:** Any other descriptor-literal inline cleanup (`PropDescriptor` shape literals in method installs were addressed in Stage 8 PR #345 commit `2427026`)
