# Embedding js_engine

How to run JavaScript with custom host objects (DOM-style globals, native
methods, private host state). This guide is for embedders that go beyond the
`@js_engine.run` facade.

Code is the source of truth. If this document and the API disagree, trust the
code and open a docs fix.

## Quick path (recommended)

Create a fully wired interpreter, inject host values on the global environment,
then parse, run, and drain the event loop. This is the pattern crater uses.

```moonbit
// Import aliases are up to the host; crater-style names shown below.
//   dowdiness/js_engine/interpreter          → @interpreter
//   dowdiness/js_engine/interpreter/runtime  → @runtime
//   dowdiness/js_engine/parser               → @parser
//   dowdiness/js_engine/errors               → @errors

fn run_with_document(code : String) -> @runtime.Value raise {
  let interp = @interpreter.new_interpreter()
  let object_proto = @runtime.get_obj_proto(
    realm_state=Some(interp.realm_state),
  )

  // Pass realm_state so the method gets %Function.prototype%.
  // def_builtin does NOT stamp callables nested under host objects.
  let query_selector = @runtime.make_method_func(
    name="querySelector",
    length=1,
    realm_state=Some(interp.realm_state),
    fn(_this, args) {
      match args {
        [@runtime.Value::String_(sel), ..] =>
          @runtime.Value::String_("matched:" + sel)
        _ => raise @errors.TypeError(message="querySelector expects a string")
      }
    },
  )

  let document = @runtime.make_host_object(
    name="Document",
    proto=object_proto,
    methods={ "querySelector": query_selector },
  )
  // Global binding only — does not set globalThis.document (see below).
  interp.global.def_builtin("document", document)

  let prog = @parser.parse(code) // parse failures are MoonBit Error, not JS
  let result = interp.run(prog.stmts)
  // Unlike @js_engine.run, Interpreter::run does not drain queues.
  interp.run_microtasks()
  interp.run_timers()
  result
}

// JS: document.querySelector("h1")  →  "matched:h1"
```

**Why this works:** `new_interpreter()` wires the standard library
(`setup_builtins_with_realm_state`), the test harness (`print`, `$262`), and
`stdlib_hooks` method dispatch. You only add host bindings afterward. You do
**not** need a custom `setup_builtins` callback for ordinary embedding.

**Footguns covered in the example:**

1. **`realm_state=` on every host callable** — omitting it leaves
   `[[Prototype]] == Null` (no `.call` / `.apply` / `instanceof Function`).
2. **Drain microtasks/timers** after `run` if the script (or host) schedules
   async work.
3. **`def_builtin` ≠ `globalThis` property** — see below.

## Packages you will import

Import the concrete packages (aliases are yours to choose):

| Package path | Typical alias | Typical use |
|---|---|---|
| `dowdiness/js_engine/interpreter` | `@interpreter` | `new_interpreter()` |
| `dowdiness/js_engine/interpreter/runtime` | `@runtime` | `Value`, factories, `make_host_object`, host slots, `raise_js_exception`, `get_obj_proto` |
| `dowdiness/js_engine/parser` | `@parser` | `parse` |
| `dowdiness/js_engine/errors` | `@errors` | `TypeError`, `RangeError`, … for native callbacks |
| `dowdiness/js_engine/interpreter/stdlib` | `@stdlib` | Only for the `Interpreter::new` escape hatch |

The root `@js_engine` facade (`run`, `run_module`, event-loop helpers) is enough
for script evaluation without host objects. Embedding usually drops to the
packages above.

## Choosing a native function factory

All of these return a callable `Value`. Prefer the smallest signature that fits.

| Factory | Callback shape | `realm_state?` | Use when |
|---|---|---|---|
| `make_native_func` | `(Array[Value]) -> Value raise` | yes | Free function / static method; no `this` |
| `make_method_func` | `(Value, Array[Value]) -> Value raise` | yes | Method; needs `this`, not the interpreter |
| `make_interp_method_func` | `(Interpreter, Value, Array[Value]) -> Value raise` | yes | Method that must call back into the engine |
| `make_interp_static_func` | `(Interpreter, Array[Value]) -> Value raise` | **no** | Free/static that needs the interpreter; stamp via top-level `def_builtin` or accept `Null` proto until stamped |
| `make_interp_method_func_with_context` | `(Interpreter, CallContext, Value, Array[Value]) -> Value raise` | **no** | Rare; needs call/construct context |

Optional labelled params where present: `name~`, `length?`, `realm_state?`.

**Rule of thumb:** start with `make_method_func(..., realm_state=Some(interp.realm_state))`
for host methods. Reach for `make_interp_*` only when the callback must use
`Interpreter` APIs.

## Building host objects

### `make_host_object` (preferred)

One call returns a `Value` — no `ObjectData` match. Installs methods, paired
accessors, intent-shaped data props, and embedder host slots.

```moonbit
let nid_slot = @runtime.HostSlotKey::reserve() // once per slot kind, module init

let slots : Map[@runtime.HostSlotKey, @runtime.Value] = {}
slots[nid_slot] = @runtime.Value::Number(nid.to_double())

let object_proto = @runtime.get_obj_proto(
  realm_state=Some(interp.realm_state),
)
let set_attr = @runtime.make_method_func(
  name="setAttribute",
  length=2,
  realm_state=Some(interp.realm_state),
  fn(_this, _args) { @runtime.Value::Undefined },
)

let el = @runtime.make_host_object(
  name="Element",
  proto=object_proto, // Null = no Object.prototype methods
  methods={ "setAttribute": set_attr },
  accessors={
    "textContent": (Some(text_get), Some(text_set)),
    "nodeType": (Some(node_type_get), None),
  },
  host_slots=slots,
)
```

Notes:

- Default `proto` is `Null`, **not** `%Object.prototype%`. Use
  `@runtime.get_obj_proto(realm_state=Some(interp.realm_state))` when the
  object should inherit ordinary Object methods.
- Accessors are paired `(getter?, setter?)`. Use `None` for an absent side.
  `(None, None)` aborts.
- There is no catch-all writable `properties` map — use `non_writable` /
  `frozen` for rare constant data, or host slots for private identity.
- Same string key across install maps: later step wins (documented stomping).
  Do not dual-define the same name.
- `HostSlotKey` map literals like `{key: value}` do not work for custom keys;
  build with `slots[key] = value`.

See also: issue [#517](https://github.com/dowdiness/js_engine/issues/517).

### Host slots (private state)

Do **not** stash host bookkeeping in ordinary JS properties
(e.g. `__crater_nid`). Prefer `host_slots=` at `make_host_object` time.

Post-hoc access takes `ObjectData`, not `Value`:

```moonbit
match el {
  @runtime.Value::Object(data) => {
    @runtime.set_host_slot(data, nid_slot, @runtime.Value::Number(1.0))
    let _ = @runtime.get_host_slot(data, nid_slot)
  }
  _ => ()
}
```

Slots are invisible to `Object.keys`, `for…in`, and `JSON.stringify`.
`HostSlotKey::reserve` IDs are unique within one loaded runtime package
instance (not per-interpreter isolation).

See also: issue [#518](https://github.com/dowdiness/js_engine/issues/518).

### Lower-level install helpers

If you already hold `ObjectData`, the same descriptor policies are available as
`install_builtin_method`, `install_builtin_accessor`,
`install_builtin_non_writable`, and `install_builtin_frozen_data`. Prefer
`make_host_object` for new code.

## Errors from native callbacks

Native callbacks use MoonBit `raise`.

### Inside JavaScript

1. **Preferred for typed errors:** `raise @errors.TypeError(message="...")`
   (also `RangeError`, `ReferenceError`, …). At JS `try` / `catch` boundaries
   (and if still uncaught when `Interpreter::run` finishes), these become
   proper JS Error objects (with realm prototypes when available).

2. **Throw an arbitrary JS value:** `@runtime.raise_js_exception(value)`.

3. **`abort` / non-JsError:** not a JS exception — engine defect. Do not use
   `abort` for expected host validation failures.

### On the MoonBit side

`interp.run(...)` does **not** return a thrown JS value. Uncaught JS errors
surface as `@runtime.JsException(Value)`. Catch that at the host boundary;
do not expect a bare `@errors.TypeError` to propagate out of `run`.

Example:

```moonbit
@runtime.make_method_func(
  name="querySelector",
  length=1,
  realm_state=Some(interp.realm_state),
  fn(_this, args) {
    guard args is [@runtime.Value::String_(_), ..] else {
      raise @errors.TypeError(message="Failed to execute 'querySelector'")
    }
    // ...
  },
)
```

## `def_builtin` vs `globalThis`

`interp.global.def_builtin(name, value)` installs a global `var`-style binding
and stamps function realm metadata **only when `value` itself is callable**.
It does **not**:

- stamp callables nested under a host object (pass `realm_state=` when building
  those methods instead)
- mirror the binding onto `globalThis` / the global object

`Interpreter::new` mirrors a fixed list of standard builtins onto
`globalThis` once at construction. Post-hoc host globals like `document` are
visible as bare identifiers (`document.querySelector(...)`) but
`globalThis.document` stays `undefined` unless you also write the property on
`interp.global_this` yourself.

Ordinary property writes on the global object are a different path; for
embedder-provided globals, start with `def_builtin`, then mirror if DOM-style
`globalThis.X` access is required.

## Event loop

`@js_engine.run` drains microtasks and timers before returning.
`Interpreter::run` does **not**. After `run`, call:

```moonbit
interp.run_microtasks()
interp.run_timers()
```

Or drive checkpoints with the facade helpers `run_with_event_loop`,
`run_microtask_checkpoint`, `run_timer_checkpoint`,
`has_pending_microtasks`, and `has_pending_timers`. See the README
“As a Library” section.

## Custom `setup_builtins` (escape hatch)

Use only when you must alter builtin installation itself (replace a builtin,
omit Annex B wiring, omit the test harness, etc.).

Do **not** confuse `Interpreter::new`’s `setup_builtins` callback with the
separately named `@stdlib.setup_builtins` function (different arity and
return type). Prefer `@stdlib.setup_builtins_with_realm_state`.

`Interpreter::new` accepts:

```moonbit
setup_builtins? : (Environment, Array[String], RealmState, Bool) -> Unit
setup_harness? : (Environment, Array[String], Value) -> Unit
stdlib_hooks? : StdlibHooks
```

`new_interpreter()` already supplies all three. If you pass your own
`setup_builtins`, **you** must install the standard library (or consciously
omit it). Forgetting that call yields an interpreter with almost no builtins.

`new_interpreter()` also installs the **test harness** (`print`, `$262`) via
`setup_harness`. For a production host using `Interpreter::new` directly, pass
`setup_harness=fn(_, _, _) { () }` unless you want those bindings.

`stdlib_hooks` must match the wiring in `interpreter/wiring.mbt`
(`make_stdlib_hooks`). That helper is package-private; copying it wrong
breaks String/Array/… method dispatch. Prefer the **quick path** unless you
have a concrete reason to open `Interpreter::new`.

## Checklist for a new host binding

1. `let interp = @interpreter.new_interpreter()`
2. Build callables with `realm_state=Some(interp.realm_state)` (where the
   factory supports it)
3. Assemble objects with `make_host_object` + realm `proto` + host slots
4. `interp.global.def_builtin("name", value)` (and mirror onto
   `global_this` if needed)
5. `@parser.parse` (MoonBit `Error` on syntax failure) + `interp.run`
6. `interp.run_microtasks()` / `interp.run_timers()` (or facade checkpoints)
7. Raise `@errors.TypeError` (etc.) from callbacks; catch `@runtime.JsException`
   around `run` on the MoonBit side

## Related docs

- [architecture.md](design/architecture.md) — host environment principles
- [development.md](development.md) — maintainer workflow
- [../README.mbt.md](../README.mbt.md) — facade quick start
