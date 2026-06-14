# Stage 8 Static-Attach Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Stage 8 static built-in attachment and selected internal-slot access out of `interpreter/stdlib` raw property-bag access and into typed `interpreter/runtime` helpers without changing observable JavaScript behavior.
**Architecture:** Add `interpreter/runtime/builtin_install.mbt` for setup-time raw bag writes and `interpreter/runtime/internal_slots.mbt` for typed internal-slot reads/writes. Stdlib remains responsible for built-in construction and algorithms, but static property installation and the targeted internal-slot representation details live behind runtime APIs.
**Tech Stack:** MoonBit, moon CLI

---

### Task 1: Create Runtime Static-Attach APIs

**Files:**
- Create: `interpreter/runtime/builtin_install.mbt`
- Create: `interpreter/runtime/internal_slots.mbt`

- [ ] Step 1: Create `interpreter/runtime/builtin_install.mbt` with the complete Pattern A API:

```moonbit
///|
/// Standard descriptor metadata for built-in prototype methods installed as
/// ordinary data properties.
fn builtin_method_desc() -> PropDescriptor {
  {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn builtin_accessor_desc(getter : Value, setter : Value?) -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(getter),
    setter,
    is_accessor: true,
  }
}

///|
fn builtin_non_writable_desc() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn builtin_frozen_data_desc() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
/// Install a built-in string-keyed method and its standard method descriptor.
pub fn install_builtin_method(
  data : ObjectData,
  name : String,
  func : Value,
) -> Unit {
  data.bag.properties[name] = func
  data.bag.descriptors[name] = builtin_method_desc()
}

///|
/// Install a built-in string-keyed accessor property.
pub fn install_builtin_accessor(
  data : ObjectData,
  name : String,
  getter : Value,
  setter : Value?,
) -> Unit {
  data.bag.properties[name] = Undefined
  data.bag.descriptors[name] = builtin_accessor_desc(getter, setter)
}

///|
/// Install a built-in string-keyed non-writable configurable data property.
pub fn install_builtin_non_writable(
  data : ObjectData,
  name : String,
  value : Value,
) -> Unit {
  data.bag.properties[name] = value
  data.bag.descriptors[name] = builtin_non_writable_desc()
}

///|
/// Install a built-in string-keyed non-writable non-configurable data property.
pub fn install_builtin_frozen_data(
  data : ObjectData,
  name : String,
  value : Value,
) -> Unit {
  data.bag.properties[name] = value
  data.bag.descriptors[name] = builtin_frozen_data_desc()
}

///|
/// Install a built-in symbol-keyed method and its standard method descriptor.
pub fn install_builtin_symbol_method(
  data : ObjectData,
  sym_id : Int,
  func : Value,
) -> Unit {
  data.bag.symbol_properties[sym_id] = func
  data.bag.symbol_descriptors[sym_id] = builtin_method_desc()
}

///|
/// Install a built-in symbol-keyed accessor property with no setter.
pub fn install_builtin_symbol_accessor(
  data : ObjectData,
  sym_id : Int,
  getter : Value,
) -> Unit {
  data.bag.symbol_properties[sym_id] = Undefined
  data.bag.symbol_descriptors[sym_id] = builtin_accessor_desc(getter, None)
}

///|
/// Install a built-in symbol-keyed non-writable configurable string data property.
pub fn install_builtin_symbol_string(
  data : ObjectData,
  sym_id : Int,
  tag : String,
) -> Unit {
  data.bag.symbol_properties[sym_id] = Value::String_(tag)
  data.bag.symbol_descriptors[sym_id] = builtin_non_writable_desc()
}
```

- [ ] Step 2: Create `interpreter/runtime/internal_slots.mbt` with the complete Pattern B API:

```moonbit
///|
pub fn get_typedarray_viewed_buffer(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ViewedArrayBuffer]]")
}

///|
pub fn get_typedarray_array_length(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ArrayLength]]")
}

///|
pub fn get_typedarray_byte_length(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ByteLength]]")
}

///|
pub fn get_typedarray_byte_offset(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ByteOffset]]")
}

///|
pub fn get_typedarray_buffer_id(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ArrayBufferID]]")
}

///|
pub fn get_arraybuffer_byte_length(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ArrayBufferByteLength]]")
}

///|
pub fn get_arraybuffer_id(data : ObjectData) -> Value? {
  data.bag.properties.get("[[ArrayBufferID]]")
}

///|
pub fn get_boolean_data(data : ObjectData) -> Value? {
  data.bag.properties.get("[[BooleanData]]")
}

///|
pub fn get_map_iterator_target(data : ObjectData, sym_id : Int) -> Value? {
  data.bag.symbol_properties.get(sym_id)
}

///|
pub fn get_map_iterator_next_index(data : ObjectData, sym_id : Int) -> Value? {
  data.bag.symbol_properties.get(sym_id)
}

///|
pub fn get_map_iterator_kind(data : ObjectData, sym_id : Int) -> Value? {
  data.bag.symbol_properties.get(sym_id)
}

///|
pub fn set_map_iterator_next_index(
  data : ObjectData,
  sym_id : Int,
  value : Value,
) -> Unit {
  data.bag.symbol_properties[sym_id] = value
}

///|
pub fn detach_map_iterator_target(data : ObjectData, sym_id : Int) -> Unit {
  data.bag.symbol_properties[sym_id] = Undefined
}
```

- [ ] Step 3: Check whether `interpreter/runtime/moon.pkg` needs an explicit source list.

```bash
sed -n '1,80p' interpreter/runtime/moon.pkg
```

Expected output:

```text
import {
  "dowdiness/js_engine/ast",
  "dowdiness/js_engine/token",
  "dowdiness/js_engine/errors",
  "dowdiness/js_engine/parser",
  "dowdiness/js_engine/static_semantics",
  "moonbitlang/core/string",
  "moonbitlang/core/math",
  "moonbitlang/core/env",
}
```

- [ ] Step 4: Because `moon.pkg` has imports only and no explicit source list, do not edit it.

```bash
moon check
```

Expected output:

```text
moon check exits 0 with no diagnostics.
```

- [ ] Step 5: Run tests and regenerate interfaces for the new public runtime APIs.

```bash
moon test
moon info
moon fmt
git diff -- interpreter/runtime/builtin_install.mbt interpreter/runtime/internal_slots.mbt interpreter/runtime/pkg.generated.mbti
```

Expected output:

```text
moon test exits 0.
moon info exits 0 and updates interpreter/runtime/pkg.generated.mbti with the new public functions.
moon fmt exits 0.
git diff shows only the two new runtime source files and runtime interface additions.
```

- [ ] Step 6: Commit Task 1.

```bash
git add interpreter/runtime/builtin_install.mbt interpreter/runtime/internal_slots.mbt interpreter/runtime/pkg.generated.mbti
git commit -m "Add runtime static attach helpers"
```

Expected output:

```text
git commit exits 0 and prints a commit summary for "Add runtime static attach helpers".
```

---

### Task 2: Delete Old Stdlib Helper and Fix Descriptor Callers

**Files:**
- Modify: `interpreter/stdlib/builtins_string.mbt`
- Modify: `interpreter/stdlib/builtins_array_init.mbt`
- Modify: `interpreter/stdlib/builtins_arraybuffer.mbt`
- Modify: `interpreter/stdlib/builtins.mbt`
- Modify: `interpreter/stdlib/builtins_number.mbt`
- Modify: `interpreter/stdlib/builtins_function.mbt`
- Modify: `interpreter/stdlib/builtins_json.mbt`
- Modify: `interpreter/stdlib/builtins_promise.mbt`
- Modify: `interpreter/stdlib/builtins_proxy.mbt`
- Modify: `interpreter/stdlib/builtins_map_set.mbt`
- Modify: `interpreter/stdlib/builtins_object.mbt`
- Modify: `interpreter/stdlib/builtins_iterator.mbt`
- Modify: `interpreter/stdlib/builtins_reflect.mbt`
- Modify: `interpreter/stdlib/builtins_symbol.mbt`
- Modify: `interpreter/stdlib/builtins_math.mbt`
- Modify: `interpreter/stdlib/builtins_dataview.mbt`
- Modify: `interpreter/stdlib/builtins_date.mbt`
- Modify: `interpreter/stdlib/builtins_weakmap_set.mbt`
- Modify: `interpreter/stdlib/builtins_regex.mbt`
- Modify: `interpreter/stdlib/builtins_typedarray.mbt`
- Delete: `interpreter/stdlib/builtin_install_helpers.mbt`

- [ ] Step 1: Delete the old stdlib helper file.

```bash
rm interpreter/stdlib/builtin_install_helpers.mbt
```

Expected output:

```text
No output.
```

- [ ] Step 2: Replace the direct `install_builtin_method(` call in `interpreter/stdlib/builtins_string.mbt` with the runtime-qualified helper:

```moonbit
@runtime.install_builtin_method(
  data,
  name,
  func,
)
```

- [ ] Step 3: Replace every remaining `builtin_method_desc()` call with this exact descriptor literal, preserving each existing assignment target:

```moonbit
{
  writable: true,
  enumerable: false,
  configurable: true,
  getter: None,
  setter: None,
  is_accessor: false,
}
```

- [ ] Step 4: Use this command to find every replacement target before editing:

```bash
rg -n "install_builtin_method|builtin_method_desc" interpreter/stdlib interpreter/runtime
```

Expected output before edits:

```text
interpreter/stdlib/builtins_regex.mbt:4156:      proto_descs["next"] = builtin_method_desc()
interpreter/stdlib/builtins_typedarray.mbt:2638:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins_number.mbt:422:  let num_method_desc = builtin_method_desc()
interpreter/stdlib/builtins_number.mbt:552:  let num_method_desc = builtin_method_desc()
interpreter/stdlib/builtins.mbt:697:          "fromCharCode": builtin_method_desc(),
interpreter/stdlib/builtins.mbt:698:          "fromCodePoint": builtin_method_desc(),
interpreter/stdlib/builtins.mbt:699:          "raw": builtin_method_desc(),
interpreter/stdlib/builtins.mbt:866:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins.mbt:999:      error_data.bag.descriptors["isError"] = builtin_method_desc()
interpreter/stdlib/builtins.mbt:1199:      let re_method_desc2 = builtin_method_desc()
interpreter/stdlib/builtins.mbt:1208:      let sym_method_desc = builtin_method_desc()
interpreter/stdlib/builtins_function.mbt:263:  func_proto_descs["toString"] = builtin_method_desc()
interpreter/stdlib/builtins_function.mbt:264:  func_proto_descs["call"] = builtin_method_desc()
interpreter/stdlib/builtins_function.mbt:265:  func_proto_descs["apply"] = builtin_method_desc()
interpreter/stdlib/builtins_function.mbt:266:  func_proto_descs["bind"] = builtin_method_desc()
interpreter/stdlib/builtins_json.mbt:8:  let ne_desc = builtin_method_desc()
interpreter/stdlib/builtins_promise.mbt:586:  promise_proto_descs["then"] = builtin_method_desc()
interpreter/stdlib/builtins_promise.mbt:587:  promise_proto_descs["catch"] = builtin_method_desc()
interpreter/stdlib/builtins_promise.mbt:588:  promise_proto_descs["finally"] = builtin_method_desc()
interpreter/stdlib/builtins_promise.mbt:1236:        "resolve": builtin_method_desc(),
interpreter/stdlib/builtins_promise.mbt:1237:        "reject": builtin_method_desc(),
interpreter/stdlib/builtins_promise.mbt:1238:        "all": builtin_method_desc(),
interpreter/stdlib/builtins_promise.mbt:1239:        "race": builtin_method_desc(),
interpreter/stdlib/builtins_promise.mbt:1240:        "allSettled": builtin_method_desc(),
interpreter/stdlib/builtins_promise.mbt:1241:        "any": builtin_method_desc(),
interpreter/stdlib/builtins_promise.mbt:1242:        "withResolvers": builtin_method_desc(),
interpreter/stdlib/builtins_promise.mbt:1243:        "try": builtin_method_desc(),
interpreter/stdlib/builtins_proxy.mbt:130:      data.bag.descriptors["revocable"] = builtin_method_desc()
interpreter/stdlib/builtins_map_set.mbt:538:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins_map_set.mbt:1025:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins_string.mbt:1957:        install_builtin_method(
interpreter/stdlib/builtins_array_init.mbt:12:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins_object.mbt:560:  let obj_method_desc = builtin_method_desc()
interpreter/stdlib/builtins_iterator.mbt:150:      let iter_method_desc = builtin_method_desc()
interpreter/stdlib/builtins_reflect.mbt:358:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins_symbol.mbt:24:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins_arraybuffer.mbt:435:  ab_proto_descs["slice"] = builtin_method_desc()
interpreter/stdlib/builtins_arraybuffer.mbt:515:  ab_ctor_descs["isView"] = builtin_method_desc()
interpreter/stdlib/builtins_math.mbt:456:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins_dataview.mbt:819:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins_date.mbt:1678:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins_weakmap_set.mbt:472:  let method_desc = builtin_method_desc()
interpreter/stdlib/builtins_weakmap_set.mbt:762:  let ws_method_desc = builtin_method_desc()
```

- [ ] Step 5: Verify no stdlib caller remains.

```bash
rg -n "install_builtin_method\\(|builtin_method_desc\\(" interpreter/stdlib
```

Expected output:

```text
No matches.
```

- [ ] Step 6: Run validation after the edit.

```bash
moon check
moon test
moon info
moon fmt
git diff --stat
```

Expected output:

```text
moon check exits 0 with no diagnostics.
moon test exits 0.
moon info exits 0.
moon fmt exits 0.
git diff --stat includes deletion of interpreter/stdlib/builtin_install_helpers.mbt and descriptor-literal updates only.
```

- [ ] Step 7: Commit Task 2.

```bash
git add interpreter/stdlib interpreter/stdlib/pkg.generated.mbti
git commit -m "Remove stdlib builtin install helper"
```

Expected output:

```text
git commit exits 0 and prints a commit summary for "Remove stdlib builtin install helper".
```

---

### Task 3: Pilot Migrate Error Constructor Back-Links

**Files:**
- Modify: `interpreter/stdlib/builtins_error.mbt`
- Modify: `scripts/architecture_representation_access.json`

- [ ] Step 1: Capture the pre-migration Error proof output.

```bash
make test262-filter FILTER=Error
cp test262-results.json /tmp/stage8-error-before.json
```

Expected output:

```text
make test262-filter FILTER=Error exits 0 or exits with the repository's expected filtered Test262 failure status.
/tmp/stage8-error-before.json contains the pre-migration Error filtered result set.
```

- [ ] Step 2: Replace the `register_error_ctor` constructor back-link block with this code:

```moonbit
  // Set ErrorType.prototype.constructor = ErrorType
  match proto_obj {
    Object(data) => {
      let ctor = env.get(name) catch { _ => Undefined }
      @runtime.install_builtin_method(data, "constructor", ctor)
    }
    _ => ()
  }
```

- [ ] Step 3: Replace the `register_aggregate_error_ctor` constructor back-link block with this code:

```moonbit
  match proto_obj {
    Object(data) => {
      let ctor = env.get(name) catch { _ => Undefined }
      @runtime.install_builtin_method(data, "constructor", ctor)
    }
    _ => ()
  }
```

- [ ] Step 4: Run the edit checkpoint.

```bash
moon check
```

Expected output:

```text
moon check exits 0 with no diagnostics.
```

- [ ] Step 5: Update `scripts/architecture_representation_access.json` for `interpreter/stdlib/builtins_error.mbt` by running this command. It parses the stale allowlist line from the audit output and writes the found count/fingerprint back into the JSON inventory.

```bash
make architecture-audit 2> /tmp/stage8-audit.txt || true
python3 - <<'PY'
import json
import re

inventory = "scripts/architecture_representation_access.json"
path = "interpreter/stdlib/builtins_error.mbt"
pattern = "representation-bag-field"
key = f"{path}:{pattern}"
text = open("/tmp/stage8-audit.txt").read()
match = re.search(rf"- {re.escape(key)} expected \d+/[^,]+, found (\d+)/(\S+)", text)
if not match:
    raise SystemExit(f"missing stale allowlist line for {key}")
count = int(match.group(1))
fingerprint = match.group(2)
data = json.load(open(inventory))
entries = data["allowlisted_access"]
for index, entry in enumerate(entries):
    if entry["path"] == path and entry["pattern_id"] == pattern:
        if count == 0:
            del entries[index]
        else:
            entry["allowed_count"] = count
            entry["fingerprint"] = fingerprint
        break
else:
    raise SystemExit(f"missing inventory entry for {key}")
with open(inventory, "w") as out:
    json.dump(data, out, indent=2)
    out.write("\n")
PY
```

- [ ] Step 6: Verify the architecture audit.

```bash
make architecture-audit
```

Expected output:

```text
Architecture representation access audit passed.
```

- [ ] Step 7: Run Error proof and compare failing sets in both directions.

```bash
make test262-filter FILTER=Error
cp test262-results.json /tmp/stage8-error-after.json
python3 - /tmp/stage8-error-before.json /tmp/stage8-error-after.json <<'PY'
import json
import sys

def failing(path):
    data = json.load(open(path))
    return {
        (item["path"], item.get("mode", ""))
        for item in data["results"]
        if item["status"] == "fail"
    }

before = failing(sys.argv[1])
after = failing(sys.argv[2])
newly_failing = sorted(after - before)
newly_passing = sorted(before - after)
if newly_failing or newly_passing:
    print("newly_failing:", newly_failing)
    print("newly_passing:", newly_passing)
    raise SystemExit(1)
print("failing sets identical")
PY
```

Expected output:

```text
failing sets identical
```

- [ ] Step 8: Run final task validation.

```bash
moon test
moon info
moon fmt
```

Expected output:

```text
moon test exits 0.
moon info exits 0.
moon fmt exits 0.
```

- [ ] Step 9: Commit Task 3.

```bash
git add interpreter/stdlib/builtins_error.mbt scripts/architecture_representation_access.json interpreter/stdlib/pkg.generated.mbti
git commit -m "Migrate error constructor static attach"
```

Expected output:

```text
git commit exits 0 and prints a commit summary for "Migrate error constructor static attach".
```

---

### Task 4: Fan-Out ArrayBuffer Static Attach

**Files:**
- Modify: `interpreter/stdlib/builtins_arraybuffer.mbt`
- Modify: `scripts/architecture_representation_access.json`

- [ ] Step 1: Capture the pre-migration ArrayBuffer proof output.

```bash
make test262-filter FILTER=ArrayBuffer
cp test262-results.json /tmp/stage8-arraybuffer-before.json
```

Expected output:

```text
make test262-filter FILTER=ArrayBuffer exits 0 or exits with the repository's expected filtered Test262 failure status.
/tmp/stage8-arraybuffer-before.json contains the pre-migration ArrayBuffer filtered result set.
```

- [ ] Step 2: Replace the `ArrayBuffer.prototype.constructor` link with this code:

```moonbit
  // Link constructor
  match ab_proto {
    Object(data) => {
      @runtime.install_builtin_method(data, "constructor", ab_ctor)
    }
    _ => ()
  }
```

- [ ] Step 3: Replace the `ArrayBuffer[@@species]` raw symbol accessor write with this code:

```moonbit
  let species_symbol_val = well_known_symbols.species
  match ab_ctor {
    Object(ab_ctor_data) => {
      @runtime.install_builtin_symbol_accessor(
        ab_ctor_data,
        species_symbol_val.id,
        species_getter,
      )
    }
    _ => ()
  }
```

- [ ] Step 4: Run the edit checkpoint.

```bash
moon check
```

Expected output:

```text
moon check exits 0 with no diagnostics.
```

- [ ] Step 5: Update `scripts/architecture_representation_access.json` for `interpreter/stdlib/builtins_arraybuffer.mbt` by running this command, then verify the audit.

```bash
make architecture-audit 2> /tmp/stage8-audit.txt || true
python3 - <<'PY'
import json
import re

inventory = "scripts/architecture_representation_access.json"
path = "interpreter/stdlib/builtins_arraybuffer.mbt"
pattern = "representation-bag-field"
key = f"{path}:{pattern}"
text = open("/tmp/stage8-audit.txt").read()
match = re.search(rf"- {re.escape(key)} expected \d+/[^,]+, found (\d+)/(\S+)", text)
if not match:
    raise SystemExit(f"missing stale allowlist line for {key}")
count = int(match.group(1))
fingerprint = match.group(2)
data = json.load(open(inventory))
entries = data["allowlisted_access"]
for index, entry in enumerate(entries):
    if entry["path"] == path and entry["pattern_id"] == pattern:
        if count == 0:
            del entries[index]
        else:
            entry["allowed_count"] = count
            entry["fingerprint"] = fingerprint
        break
else:
    raise SystemExit(f"missing inventory entry for {key}")
with open(inventory, "w") as out:
    json.dump(data, out, indent=2)
    out.write("\n")
PY
make architecture-audit
```

Expected output:

```text
Architecture representation access audit passed.
```

- [ ] Step 6: Run ArrayBuffer proof and compare failing sets in both directions.

```bash
make test262-filter FILTER=ArrayBuffer
cp test262-results.json /tmp/stage8-arraybuffer-after.json
python3 - /tmp/stage8-arraybuffer-before.json /tmp/stage8-arraybuffer-after.json <<'PY'
import json
import sys

def failing(path):
    data = json.load(open(path))
    return {
        (item["path"], item.get("mode", ""))
        for item in data["results"]
        if item["status"] == "fail"
    }

before = failing(sys.argv[1])
after = failing(sys.argv[2])
newly_failing = sorted(after - before)
newly_passing = sorted(before - after)
if newly_failing or newly_passing:
    print("newly_failing:", newly_failing)
    print("newly_passing:", newly_passing)
    raise SystemExit(1)
print("failing sets identical")
PY
```

Expected output:

```text
failing sets identical
```

- [ ] Step 7: Run final task validation.

```bash
moon test
moon info
moon fmt
```

Expected output:

```text
moon test exits 0.
moon info exits 0.
moon fmt exits 0.
```

- [ ] Step 8: Commit Task 4.

```bash
git add interpreter/stdlib/builtins_arraybuffer.mbt scripts/architecture_representation_access.json interpreter/stdlib/pkg.generated.mbti
git commit -m "Migrate ArrayBuffer static attach"
```

Expected output:

```text
git commit exits 0 and prints a commit summary for "Migrate ArrayBuffer static attach".
```

---

### Task 5: Fan-Out Map and Set Static Attach and Iterator Slots

**Files:**
- Modify: `interpreter/stdlib/builtins_map_set.mbt`
- Modify: `scripts/architecture_representation_access.json`

- [ ] Step 1: Capture pre-migration Map and Set proof output.

```bash
make test262-filter FILTER=Map
cp test262-results.json /tmp/stage8-map-before.json
make test262-filter FILTER=Set
cp test262-results.json /tmp/stage8-set-before.json
```

Expected output:

```text
Both filtered Test262 commands exit 0 or exit with the repository's expected filtered Test262 failure status.
/tmp/stage8-map-before.json and /tmp/stage8-set-before.json contain the pre-migration filtered result sets.
```

- [ ] Step 2: Replace `map_iterator_next` slot reads and writes with this function body:

```moonbit
fn map_iterator_next(this_val : Value) -> Value raise Error {
  match this_val {
    Object(data) => {
      guard data.class_name == "Map Iterator" else {
        return map_iterator_type_error()
      }
      let (current, iterated_map, kind) = match
        (
          @runtime.get_map_iterator_next_index(
            data,
            MAP_ITERATOR_NEXT_INDEX_SYMBOL_ID,
          ),
          @runtime.get_map_iterator_target(data, MAP_ITERATOR_TARGET_SYMBOL_ID),
          @runtime.get_map_iterator_kind(data, MAP_ITERATOR_KIND_SYMBOL_ID),
        ) {
        (Some(Number(index)), Some(target), Some(Number(kind))) =>
          (index.to_int(), target, kind.to_int())
        _ => return map_iterator_type_error()
      }
      match iterated_map {
        Undefined => @runtime.create_iter_result(Undefined, true)
        Map(map_data) => {
          guard current < map_data.entries.length() else {
            @runtime.detach_map_iterator_target(
              data,
              MAP_ITERATOR_TARGET_SYMBOL_ID,
            )
            return @runtime.create_iter_result(Undefined, true)
          }
          let (key, value) = map_data.entries[current]
          @runtime.set_map_iterator_next_index(
            data,
            MAP_ITERATOR_NEXT_INDEX_SYMBOL_ID,
            Number((current + 1).to_double()),
          )
          let result_value = map_iterator_result_value(kind, key, value)
          @runtime.create_iter_result(result_value, false)
        }
        _ => map_iterator_type_error()
      }
    }
    _ => map_iterator_type_error()
  }
}
```

- [ ] Step 3: Replace Map prototype symbol writes with this code:

```moonbit
  // Add Map.prototype[Symbol.iterator] = Map.prototype.entries
  match map_proto {
    Object(data) => {
      @runtime.install_builtin_symbol_method(
        data,
        iterator_sym.id,
        map_proto_props["entries"],
      )
      let tostringtag_sym = well_known_symbols.to_string_tag
      @runtime.install_builtin_symbol_string(data, tostringtag_sym.id, "Map")
    }
    _ => ()
  }
```

- [ ] Step 4: Replace the Map constructor prototype property link with this code:

```moonbit
  // Add prototype property to Map constructor
  match map_ctor {
    Object(data) => {
      @runtime.install_builtin_frozen_data(data, "prototype", map_proto)
    }
    _ => ()
  }
```

- [ ] Step 5: Replace the `Map.prototype.constructor` link with this code:

```moonbit
  // Set Map.prototype.constructor = Map
  match map_proto {
    Object(data) => {
      @runtime.install_builtin_method(data, "constructor", map_ctor)
    }
    _ => ()
  }
```

- [ ] Step 6: Replace Set prototype symbol writes with this code:

```moonbit
  // Add Set.prototype[Symbol.iterator] = Set.prototype.values
  match set_proto {
    Object(data) => {
      @runtime.install_builtin_symbol_method(
        data,
        iterator_sym.id,
        set_proto_props["values"],
      )
      let tostringtag_sym = well_known_symbols.to_string_tag
      @runtime.install_builtin_symbol_string(data, tostringtag_sym.id, "Set")
    }
    _ => ()
  }
```

- [ ] Step 7: Replace the Set constructor prototype property link with this code:

```moonbit
  // Add prototype property to Set constructor
  match set_ctor {
    Object(data) => {
      @runtime.install_builtin_frozen_data(data, "prototype", set_proto)
    }
    _ => ()
  }
```

- [ ] Step 8: Replace the `Set.prototype.constructor` link with this code:

```moonbit
  // Set Set.prototype.constructor = Set
  match set_proto {
    Object(data) => {
      @runtime.install_builtin_method(data, "constructor", set_ctor)
    }
    _ => ()
  }
```

- [ ] Step 9: Run the edit checkpoint.

```bash
moon check
```

Expected output:

```text
moon check exits 0 with no diagnostics.
```

- [ ] Step 10: Update `scripts/architecture_representation_access.json` for `interpreter/stdlib/builtins_map_set.mbt` by running this command, then verify the audit.

```bash
make architecture-audit 2> /tmp/stage8-audit.txt || true
python3 - <<'PY'
import json
import re

inventory = "scripts/architecture_representation_access.json"
path = "interpreter/stdlib/builtins_map_set.mbt"
pattern = "representation-bag-field"
key = f"{path}:{pattern}"
text = open("/tmp/stage8-audit.txt").read()
match = re.search(rf"- {re.escape(key)} expected \d+/[^,]+, found (\d+)/(\S+)", text)
if not match:
    raise SystemExit(f"missing stale allowlist line for {key}")
count = int(match.group(1))
fingerprint = match.group(2)
data = json.load(open(inventory))
entries = data["allowlisted_access"]
for index, entry in enumerate(entries):
    if entry["path"] == path and entry["pattern_id"] == pattern:
        if count == 0:
            del entries[index]
        else:
            entry["allowed_count"] = count
            entry["fingerprint"] = fingerprint
        break
else:
    raise SystemExit(f"missing inventory entry for {key}")
with open(inventory, "w") as out:
    json.dump(data, out, indent=2)
    out.write("\n")
PY
make architecture-audit
```

Expected output:

```text
Architecture representation access audit passed.
```

- [ ] Step 11: Run Map and Set proof and compare failing sets in both directions.

```bash
make test262-filter FILTER=Map
cp test262-results.json /tmp/stage8-map-after.json
make test262-filter FILTER=Set
cp test262-results.json /tmp/stage8-set-after.json
python3 - /tmp/stage8-map-before.json /tmp/stage8-map-after.json /tmp/stage8-set-before.json /tmp/stage8-set-after.json <<'PY'
import json
import sys

def failing(path):
    data = json.load(open(path))
    return {
        (item["path"], item.get("mode", ""))
        for item in data["results"]
        if item["status"] == "fail"
    }

for before_path, after_path in [(sys.argv[1], sys.argv[2]), (sys.argv[3], sys.argv[4])]:
    before = failing(before_path)
    after = failing(after_path)
    newly_failing = sorted(after - before)
    newly_passing = sorted(before - after)
    if newly_failing or newly_passing:
        print(before_path, "->", after_path)
        print("newly_failing:", newly_failing)
        print("newly_passing:", newly_passing)
        raise SystemExit(1)
print("failing sets identical")
PY
```

Expected output:

```text
failing sets identical
```

- [ ] Step 12: Run final task validation.

```bash
moon test
moon info
moon fmt
```

Expected output:

```text
moon test exits 0.
moon info exits 0.
moon fmt exits 0.
```

- [ ] Step 13: Commit Task 5.

```bash
git add interpreter/stdlib/builtins_map_set.mbt scripts/architecture_representation_access.json interpreter/stdlib/pkg.generated.mbti
git commit -m "Migrate Map and Set static attach"
```

Expected output:

```text
git commit exits 0 and prints a commit summary for "Migrate Map and Set static attach".
```

---

### Task 6: Fan-Out Core Builtins Static Attach and Boolean Slot Reads

**Files:**
- Modify: `interpreter/stdlib/builtins.mbt`
- Modify: `scripts/architecture_representation_access.json`

- [ ] Step 1: Capture pre-migration proof output for affected core builtins.

```bash
make test262-filter FILTER=Boolean
cp test262-results.json /tmp/stage8-boolean-before.json
make test262-filter FILTER=Function
cp test262-results.json /tmp/stage8-function-before.json
make test262-filter FILTER=RegExp
cp test262-results.json /tmp/stage8-regexp-before.json
```

Expected output:

```text
All filtered Test262 commands exit 0 or exit with the repository's expected filtered Test262 failure status.
The three /tmp/stage8-*-before.json files contain the pre-migration filtered result sets.
```

- [ ] Step 2: Replace `Boolean.prototype.toString` BooleanData read with this code:

```moonbit
            match @runtime.get_boolean_data(data) {
              Some(Value::Bool(b)) => Value::String_(b.to_string())
              _ =>
                raise @errors.TypeError(
                  message="Boolean.prototype.toString requires a Boolean",
                )
            }
```

- [ ] Step 3: Replace `Boolean.prototype.valueOf` BooleanData read with this code:

```moonbit
            match @runtime.get_boolean_data(data) {
              Some(Value::Bool(b)) => Value::Bool(b)
              _ =>
                raise @errors.TypeError(
                  message="Boolean.prototype.valueOf requires a Boolean",
                )
            }
```

- [ ] Step 4: Replace the `String.prototype.constructor` link with this code:

```moonbit
  // Set String.prototype.constructor = String
  match string_proto {
    Object(data) => {
      let ctor = env.get("String") catch { _ => Undefined }
      @runtime.install_builtin_method(data, "constructor", ctor)
    }
    _ => ()
  }
```

- [ ] Step 5: Replace the `Boolean.prototype.constructor` link with this code:

```moonbit
  // Set Boolean.prototype.constructor = Boolean
  match boolean_proto {
    Object(data) => {
      let ctor = env.get("Boolean") catch { _ => Undefined }
      @runtime.install_builtin_method(data, "constructor", ctor)
    }
    _ => ()
  }
```

- [ ] Step 6: Replace the `Error.isError` static method raw write with this code:

```moonbit
  // Add Error.isError static method
  let error_ctor = env.get("Error") catch { _ => Undefined }
  match error_ctor {
    Object(error_data) => {
      let is_error = @runtime.make_native_func(
        name="isError",
        length=1,
        fn(args) {
          let arg = if args.length() > 0 { args[0] } else { Undefined }
          match arg {
            Object(data) =>
              // ES §21.5.2.1: return true iff arg has [[ErrorData]] slot.
              // The registry is populated at constructor registration time,
              // so new error types are automatically recognised without
              // requiring any change here.
              Bool(env.error_class_names.contains(data.class_name))
            _ => Value::Bool(false)
          }
        },
      )
      @runtime.install_builtin_method(error_data, "isError", is_error)
    }
    _ => ()
  }
```

- [ ] Step 7: Replace the RegExp constructor prototype link with this code:

```moonbit
            Object(ctor_data) => {
              @runtime.install_builtin_frozen_data(
                ctor_data,
                "prototype",
                regexp_proto,
              )
            }
```

- [ ] Step 8: Replace constructor `@@species` attachment loop with this code:

```moonbit
  let ctors_to_add_species = ["Array", "RegExp", "Map", "Set"]
  for ctor_name in ctors_to_add_species {
    let ctor_val = env.get(ctor_name) catch { _ => Undefined }
    match ctor_val {
      Object(ctor_data) => {
        let sp_sym = well_known_symbols.species
        @runtime.install_builtin_symbol_accessor(
          ctor_data,
          sp_sym.id,
          species_getter,
        )
      }
      _ => ()
    }
  }
```

- [ ] Step 9: Replace Function.prototype `@@hasInstance` attachment with this code:

```moonbit
        Object(fp_data) => {
          @runtime.install_builtin_symbol_method(
            fp_data,
            has_instance_sym.id,
            has_instance_fn,
          )
        }
```

- [ ] Step 10: Run the edit checkpoint.

```bash
moon check
```

Expected output:

```text
moon check exits 0 with no diagnostics.
```

- [ ] Step 11: Update `scripts/architecture_representation_access.json` for `interpreter/stdlib/builtins.mbt` by running this command, then verify the audit.

```bash
make architecture-audit 2> /tmp/stage8-audit.txt || true
python3 - <<'PY'
import json
import re

inventory = "scripts/architecture_representation_access.json"
path = "interpreter/stdlib/builtins.mbt"
pattern = "representation-bag-field"
key = f"{path}:{pattern}"
text = open("/tmp/stage8-audit.txt").read()
match = re.search(rf"- {re.escape(key)} expected \d+/[^,]+, found (\d+)/(\S+)", text)
if not match:
    raise SystemExit(f"missing stale allowlist line for {key}")
count = int(match.group(1))
fingerprint = match.group(2)
data = json.load(open(inventory))
entries = data["allowlisted_access"]
for index, entry in enumerate(entries):
    if entry["path"] == path and entry["pattern_id"] == pattern:
        if count == 0:
            del entries[index]
        else:
            entry["allowed_count"] = count
            entry["fingerprint"] = fingerprint
        break
else:
    raise SystemExit(f"missing inventory entry for {key}")
with open(inventory, "w") as out:
    json.dump(data, out, indent=2)
    out.write("\n")
PY
make architecture-audit
```

Expected output:

```text
Architecture representation access audit passed.
```

- [ ] Step 12: Run proof and compare failing sets in both directions.

```bash
make test262-filter FILTER=Boolean
cp test262-results.json /tmp/stage8-boolean-after.json
make test262-filter FILTER=Function
cp test262-results.json /tmp/stage8-function-after.json
make test262-filter FILTER=RegExp
cp test262-results.json /tmp/stage8-regexp-after.json
python3 - /tmp/stage8-boolean-before.json /tmp/stage8-boolean-after.json /tmp/stage8-function-before.json /tmp/stage8-function-after.json /tmp/stage8-regexp-before.json /tmp/stage8-regexp-after.json <<'PY'
import json
import sys

def failing(path):
    data = json.load(open(path))
    return {
        (item["path"], item.get("mode", ""))
        for item in data["results"]
        if item["status"] == "fail"
    }

pairs = [(sys.argv[1], sys.argv[2]), (sys.argv[3], sys.argv[4]), (sys.argv[5], sys.argv[6])]
for before_path, after_path in pairs:
    before = failing(before_path)
    after = failing(after_path)
    newly_failing = sorted(after - before)
    newly_passing = sorted(before - after)
    if newly_failing or newly_passing:
        print(before_path, "->", after_path)
        print("newly_failing:", newly_failing)
        print("newly_passing:", newly_passing)
        raise SystemExit(1)
print("failing sets identical")
PY
```

Expected output:

```text
failing sets identical
```

- [ ] Step 13: Run final task validation.

```bash
moon test
moon info
moon fmt
```

Expected output:

```text
moon test exits 0.
moon info exits 0.
moon fmt exits 0.
```

- [ ] Step 14: Commit Task 6.

```bash
git add interpreter/stdlib/builtins.mbt scripts/architecture_representation_access.json interpreter/stdlib/pkg.generated.mbti
git commit -m "Migrate core builtin static attach"
```

Expected output:

```text
git commit exits 0 and prints a commit summary for "Migrate core builtin static attach".
```

---

### Task 7: Fan-Out TypedArray Static Attach and Slot Reads

**Files:**
- Modify: `interpreter/stdlib/builtins_typedarray.mbt`
- Modify: `scripts/architecture_representation_access.json`

- [ ] Step 1: Capture pre-migration TypedArray proof output.

```bash
make test262-filter FILTER=TypedArray
cp test262-results.json /tmp/stage8-typedarray-before.json
```

Expected output:

```text
make test262-filter FILTER=TypedArray exits 0 or exits with the repository's expected filtered Test262 failure status.
/tmp/stage8-typedarray-before.json contains the pre-migration TypedArray filtered result set.
```

- [ ] Step 2: Replace per-constructor prototype back-link in `register_typedarray_constructor` with this code:

```moonbit
  match per_proto {
    Object(proto_data) => {
      @runtime.install_builtin_method(proto_data, "constructor", ctor)
    }
    _ => ()
  }
```

- [ ] Step 3: Replace `typedarray_arraybuffer_state` with this function body:

```moonbit
fn typedarray_arraybuffer_state(
  data : ObjectData,
  fallback_realm_state : @runtime.RealmState,
) -> @runtime.ArrayBufferState {
  match data.arraybuffer_state {
    Some(state) => state
    None =>
      match @runtime.get_typedarray_viewed_buffer(data) {
        Some(buffer) =>
          arraybuffer_state_from_value(
            buffer,
            fallback_realm_state.arraybuffer_state,
          )
        None => fallback_realm_state.arraybuffer_state
      }
  }
}
```

- [ ] Step 4: Replace `typedarray_is_valid_index` slot reads with this code:

```moonbit
  let length = match @runtime.get_typedarray_array_length(data) {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
  if index < 0 || index >= length {
    return false
  }
  let buf_id = match @runtime.get_typedarray_buffer_id(data) {
    Some(Value::Number(n)) => n.to_int()
    _ => return false
  }
```

- [ ] Step 5: Replace `validate_typed_array` buffer-id read with this code:

```moonbit
  let buf_id = match @runtime.get_typedarray_buffer_id(data) {
    Some(Value::Number(n)) => n.to_int()
    _ =>
      raise @errors.TypeError(message="\{method_name} called on non-TypedArray")
  }
```

- [ ] Step 6: Replace `typedarray_length` with this function body:

```moonbit
fn typedarray_length(data : ObjectData) -> Int {
  match @runtime.get_typedarray_array_length(data) {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
}
```

- [ ] Step 7: Replace `typedarray_get_index` slot reads with this code:

```moonbit
  let length = match @runtime.get_typedarray_array_length(data) {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
  if index < 0 || index >= length {
    return Undefined
  }
  let buf_id = match @runtime.get_typedarray_buffer_id(data) {
    Some(Value::Number(n)) => n.to_int()
    _ => return Undefined
  }
  let storage_state = typedarray_arraybuffer_state(data, realm_state)
  if is_arraybuffer_state_detached(storage_state, buf_id) {
    return Undefined
  }
  let byte_offset = match @runtime.get_typedarray_byte_offset(data) {
    Some(Value::Number(n)) => n.to_int()
    _ => 0
  }
```

- [ ] Step 8: Replace `typedarray_is_detached` with this function body:

```moonbit
fn typedarray_is_detached(
  data : ObjectData,
  realm_state : @runtime.RealmState,
) -> Bool {
  match @runtime.get_typedarray_buffer_id(data) {
    Some(Value::Number(n)) => {
      let storage_state = typedarray_arraybuffer_state(data, realm_state)
      is_arraybuffer_state_detached(storage_state, n.to_int())
    }
    _ => false
  }
}
```

- [ ] Step 9: Replace `typedarray_get_view_slot` with this function body:

```moonbit
fn typedarray_get_view_slot(
  data : ObjectData,
  internal_slot : String,
  realm_state : @runtime.RealmState,
) -> Value {
  if typedarray_is_detached(data, realm_state) {
    Value::Number(0.0)
  } else {
    let value = match internal_slot {
      "[[ArrayLength]]" => @runtime.get_typedarray_array_length(data)
      "[[ByteLength]]" => @runtime.get_typedarray_byte_length(data)
      "[[ByteOffset]]" => @runtime.get_typedarray_byte_offset(data)
      _ => None
    }
    match value {
      Some(n) => n
      None => Value::Number(0.0)
    }
  }
}
```

- [ ] Step 10: Replace `%TypedArray%.prototype.constructor` link with this code:

```moonbit
  // Set ta_proto.constructor = %TypedArray%
  match ta_proto {
    Object(proto_data) => {
      @runtime.install_builtin_method(proto_data, "constructor", ta_ctor)
    }
    _ => ()
  }
```

- [ ] Step 11: Replace `%TypedArray%[@@species]` attachment with this code:

```moonbit
  match ta_ctor {
    Object(ctor_data) => {
      let sp_sym = well_known_symbols.species
      @runtime.install_builtin_symbol_accessor(
        ctor_data,
        sp_sym.id,
        ta_species_getter,
      )
    }
    _ => ()
  }
```

- [ ] Step 12: Replace concrete TypedArray constructor back-link with this code:

```moonbit
    // Link constructor
    match per_proto {
      Object(proto_data) => {
        @runtime.install_builtin_method(proto_data, "constructor", ctor)
      }
      _ => ()
    }
```

- [ ] Step 13: Replace ArrayBuffer constructor path byte-length read with this code:

```moonbit
              let buf_byte_length = match
                @runtime.get_arraybuffer_byte_length(buf_data) {
                Some(Value::Number(n)) => n.to_int()
                _ => 0
              }
```

- [ ] Step 14: Replace ArrayBuffer constructor path buffer-id read with this code:

```moonbit
              let buf_id = match @runtime.get_arraybuffer_id(buf_data) {
                Some(Value::Number(n)) => n.to_int()
                _ => -1
              }
```

- [ ] Step 15: Replace remaining typed-array internal slot reads in this file using the exact helper mapping below:

```moonbit
@runtime.get_typedarray_viewed_buffer(data)
@runtime.get_typedarray_array_length(data)
@runtime.get_typedarray_byte_length(data)
@runtime.get_typedarray_byte_offset(data)
@runtime.get_typedarray_buffer_id(data)
@runtime.get_arraybuffer_byte_length(buf_data)
@runtime.get_arraybuffer_id(buf_data)
```

- [ ] Step 16: Use this search command to verify no targeted internal-slot raw reads remain:

```bash
rg -n 'bag\\.properties\\.get\\("\\[\\[(ViewedArrayBuffer|ArrayLength|ByteLength|ByteOffset|ArrayBufferID|ArrayBufferByteLength)\\]\\]"\\)' interpreter/stdlib/builtins_typedarray.mbt
```

Expected output:

```text
No matches.
```

- [ ] Step 17: Run the edit checkpoint.

```bash
moon check
```

Expected output:

```text
moon check exits 0 with no diagnostics.
```

- [ ] Step 18: Update `scripts/architecture_representation_access.json` for `interpreter/stdlib/builtins_typedarray.mbt` by running this command, then verify the audit.

```bash
make architecture-audit 2> /tmp/stage8-audit.txt || true
python3 - <<'PY'
import json
import re

inventory = "scripts/architecture_representation_access.json"
path = "interpreter/stdlib/builtins_typedarray.mbt"
pattern = "representation-bag-field"
key = f"{path}:{pattern}"
text = open("/tmp/stage8-audit.txt").read()
match = re.search(rf"- {re.escape(key)} expected \d+/[^,]+, found (\d+)/(\S+)", text)
if not match:
    raise SystemExit(f"missing stale allowlist line for {key}")
count = int(match.group(1))
fingerprint = match.group(2)
data = json.load(open(inventory))
entries = data["allowlisted_access"]
for index, entry in enumerate(entries):
    if entry["path"] == path and entry["pattern_id"] == pattern:
        if count == 0:
            del entries[index]
        else:
            entry["allowed_count"] = count
            entry["fingerprint"] = fingerprint
        break
else:
    raise SystemExit(f"missing inventory entry for {key}")
with open(inventory, "w") as out:
    json.dump(data, out, indent=2)
    out.write("\n")
PY
make architecture-audit
```

Expected output:

```text
Architecture representation access audit passed.
```

- [ ] Step 19: Run TypedArray proof and compare failing sets in both directions.

```bash
make test262-filter FILTER=TypedArray
cp test262-results.json /tmp/stage8-typedarray-after.json
python3 - /tmp/stage8-typedarray-before.json /tmp/stage8-typedarray-after.json <<'PY'
import json
import sys

def failing(path):
    data = json.load(open(path))
    return {
        (item["path"], item.get("mode", ""))
        for item in data["results"]
        if item["status"] == "fail"
    }

before = failing(sys.argv[1])
after = failing(sys.argv[2])
newly_failing = sorted(after - before)
newly_passing = sorted(before - after)
if newly_failing or newly_passing:
    print("newly_failing:", newly_failing)
    print("newly_passing:", newly_passing)
    raise SystemExit(1)
print("failing sets identical")
PY
```

Expected output:

```text
failing sets identical
```

- [ ] Step 20: Run final task validation.

```bash
moon test
moon info
moon fmt
```

Expected output:

```text
moon test exits 0.
moon info exits 0.
moon fmt exits 0.
```

- [ ] Step 21: Commit Task 7.

```bash
git add interpreter/stdlib/builtins_typedarray.mbt scripts/architecture_representation_access.json interpreter/stdlib/pkg.generated.mbti
git commit -m "Migrate TypedArray static attach"
```

Expected output:

```text
git commit exits 0 and prints a commit summary for "Migrate TypedArray static attach".
```

---

### Task 8: Final Audit and Full Test262 Baseline

**Files:**
- Modify: `scripts/architecture_representation_access.json`
- Modify: `docs/ROADMAP.md`

- [ ] Step 1: Verify targeted raw bag accesses are gone from migrated areas.

```bash
rg -n 'bag\\.(properties|descriptors|symbol_properties|symbol_descriptors)' interpreter/stdlib/builtins_error.mbt interpreter/stdlib/builtins_arraybuffer.mbt interpreter/stdlib/builtins_map_set.mbt interpreter/stdlib/builtins.mbt interpreter/stdlib/builtins_typedarray.mbt
```

Expected output:

```text
Only out-of-scope raw accesses remain: runtime Object.defineProperty behavior, builtins_string alias/erasure patterns, non-targeted realm stamping, non-targeted object/prototype reads, and non-targeted collection backing storage reads.
```

- [ ] Step 2: Run final architecture audit.

```bash
make architecture-audit
```

Expected output:

```text
Architecture representation access audit passed.
```

- [ ] Step 3: Run the full test suite.

```bash
moon check
moon test
```

Expected output:

```text
moon check exits 0 with no diagnostics.
moon test exits 0.
```

- [ ] Step 4: Run full Test262 locally when practical.

```bash
make test262
cp test262-results.json /tmp/stage8-full-test262-after.json
```

Expected output:

```text
make test262 exits 0 or exits with the repository's expected Test262 failure status.
/tmp/stage8-full-test262-after.json contains the full post-migration result set.
```

- [ ] Step 5: If local full Test262 is too slow, push the branch and use CI artifacts instead.

```bash
git push -u origin HEAD
make test262-report ARGS="--format=table"
```

Expected output:

```text
git push exits 0.
make test262-report emits per-mode Passed / Executed and Passed / Discovered counts from CI artifacts.
```

- [ ] Step 6: Update `docs/ROADMAP.md` only by pasting the generated table from this command:

```bash
make test262-report ARGS="--format=table"
```

Expected output:

```text
The generated table includes per-mode Passed / Executed and Passed / Discovered values and does not hand-edit Test262 numbers.
```

- [ ] Step 7: Run final formatting and interface regeneration.

```bash
moon info
moon fmt
git diff --stat
```

Expected output:

```text
moon info exits 0.
moon fmt exits 0.
git diff --stat shows only runtime source, stdlib source, generated interface, audit JSON, and generated roadmap-number changes for this migration.
```

- [ ] Step 8: Commit Task 8.

```bash
git add interpreter/runtime interpreter/stdlib scripts/architecture_representation_access.json docs/ROADMAP.md
git commit -m "Complete Stage 8 static attach migration"
```

Expected output:

```text
git commit exits 0 and prints a commit summary for "Complete Stage 8 static attach migration".
```
