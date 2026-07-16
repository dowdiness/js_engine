# Stable embedding guide

This guide is the supported starting point for embedding trusted JavaScript in
a MoonBit application. It uses only the root `@js_engine` facade and does not
require `Interpreter`, runtime `Value`, parser, AST, or realm internals.

Trusted scripts receive the JavaScript runtime and built-ins configured by
`js_engine`. This API is **not a security sandbox**: it does not provide an
execution budget, interruption, process or address-space isolation, or
capability filtering.

## Choose one-shot or persistent execution

Use `run` when each source string is independent:

```moonbit
let (output, result) = @js_engine.run("console.log(1 + 2); 6 * 7")
// output == ["3"]
// result == "42"
```

`run` creates a fresh interpreter, evaluates one script, drains all queued
microtasks, then runs the timer queue with a microtask checkpoint after each
timer. It returns captured console output and the JavaScript result converted
to the runtime's display string. The result string is not a JSON bridge.

Use `Engine` when calls must share JavaScript state or when the host must choose
when queued work advances:

```moonbit
let engine = @js_engine.Engine()
engine.eval(
  #|let evaluations = 0;
  #|function allow(request) {
  #|  evaluations += 1;
  #|  return { allowed: request.role === "admin", evaluations };
  #|}
)
let request = Json::object({ "role": Json::string("admin") })
let decision = engine.call_json("allow", [request])
```

One `Engine` owns one realm. Repeated `eval` and `call_json` calls observe the
same globals and lexical bindings. Separate engines do not share those
bindings. `eval` and `call_json` do not run pending microtasks or timers.

## Root public-surface classification

The generated root interface is classified as follows. Stable embedding APIs
are the model for new application integrations. Compatibility and
advanced/internal APIs remain public today but expose runtime representations
or experimental execution paths and are not used by this guide.

| Classification | Root entry points |
|---|---|
| **Stable embedding** | `run`; `EngineError`; `Engine`, `Engine::Engine`, `Engine::eval`, `Engine::call_json`, `Engine::take_output`, `Engine::has_pending_microtasks`, `Engine::has_pending_timers`, `Engine::run_microtask_checkpoint`, `Engine::run_timer_checkpoint` |
| **Compatibility** | `run_module`, `run_modules` |
| **Advanced/internal** | `run_compiled`, `run_with_event_loop`, `has_pending_microtasks`, `has_pending_timers`, `run_microtask_checkpoint`, `run_timer_checkpoint` |

`run_module` and `run_modules` are compatibility APIs because their export maps
contain raw runtime `Value`s. The module-level event-loop helpers are
advanced/internal because they accept or return a raw `Interpreter`.
`run_compiled` is an opt-in closure-conversion prototype.

## Strict JSON boundary

`Engine::call_json(name, args)` copies MoonBit `Json` arguments into the engine,
calls a synchronous JavaScript function, and copies its return value back to
MoonBit `Json`. The argument and result conversion itself does not consult the
mutable global `JSON` object, call getters or `toJSON`, or execute Proxy traps.

| Direction | Accepted |
|---|---|
| MoonBit to JavaScript | JSON `null`, booleans, strings, finite numbers, arrays, and string-keyed objects, recursively |
| JavaScript to MoonBit | `null`, booleans, strings, finite numbers, dense ordinary arrays without custom properties, and plain non-callable objects whose prototype is `Object.prototype` or `null`, recursively |

The JavaScript result is rejected with `JsonConversionError` if it contains or
is `undefined`, a non-finite number, `Symbol`, function, Promise, Proxy, Map,
Set, sparse or customized array, cycle, accessor, non-enumerable or symbol
property, object with internal/host state, or non-plain object. A non-finite
MoonBit JSON number is also rejected. Conversion is deliberately stricter than
`JSON.stringify`; unsupported values are errors rather than omitted or coerced.

Promises are not awaited. Run an explicit microtask checkpoint and call a
synchronous JSON-returning function afterward when a script uses promises.

## `call_json` name lookup

Lookup uses the following order:

1. the Engine's global environment bindings, including top-level declarations;
2. an **own** property of the Engine's `globalThis` object.

A binding wins over a same-named `globalThis` property. Inherited properties of
the global object are not exports. Missing names raise `MissingGlobal`; values
that exist but are not callable raise `NotCallable`. The host supplies
`undefined` as the call's `this` argument; normal JavaScript call semantics
still apply, including non-strict `this` normalization.

An own accessor property on `globalThis` is resolved with normal JavaScript
property access, so its getter runs before the callable check. The getter's
return value becomes the candidate function; a non-callable result raises
`NotCallable`, and a thrown value raises `JavaScriptException`. Getter side
effects are retained. This lookup behavior is separate from the strict JSON
conversion above, which does not execute getters or other conversion hooks.

## Explicit queue checkpoints

Persistent calls leave queued jobs pending until the host advances them:

- `has_pending_microtasks()` and `has_pending_timers()` report queue presence.
- `run_microtask_checkpoint()` drains microtasks until the queue is empty,
  including microtasks queued by other microtasks. Its `Bool` result says
  whether microtasks remain after a successful checkpoint; the normal complete
  drain returns `false`.
- `run_timer_checkpoint()` runs the pending timer queue. Timers run by delay and
  insertion order, and each timer is followed by a complete microtask
  checkpoint before the next timer. It returns `Unit`.

Neither `eval` nor `call_json` performs any of these steps implicitly. This
lets the MoonBit host decide when queued JavaScript receives execution time.

## Failures, retained state, and reuse

An `Engine` is not transactional. JavaScript-visible mutations completed before
an exception or result-conversion failure are retained; they are not rolled
back.

Current characterization tests establish the following reuse behavior:

| Failure | Confirmed state after failure |
|---|---|
| `ParseError` from `eval` | No script body ran; the Engine remains usable. |
| `JavaScriptException` from `eval` or `call_json` | Mutations completed before the throw remain; later calls can reuse the Engine. |
| `MissingGlobal` | No JavaScript lookup code or target function runs; later lookups can reuse the Engine. |
| `NotCallable` | No target function runs. An own `globalThis` accessor getter may already have run and mutated state; later calls can reuse the Engine. |
| `JsonConversionError` while converting a result | The JavaScript call already ran, its mutations remain, and later calls can reuse the Engine. |

Do not infer a broader guarantee from this table. Reuse and pending-job state
after `InternalError` or a failure raised while running a microtask/timer
checkpoint are not yet characterized as a stable contract. Discard the Engine
after those failures. Interruption and execution-budget failures are not part
of the current API.

`take_output()` returns a copy of accumulated console output and clears the
Engine's output buffer.

## Four-target support

The repository's adoption workflow checks and tests the Engine scenario from a
standalone [external-consumer module](../integration/external_consumer/) on
MoonBit's `native`, `js`, `wasm`, and `wasm-gc` targets. Its workspace resolves
`dowdiness/js_engine` to the checkout under review, and the architecture audit
rejects direct imports of internal packages. Four-target support means the
stable facade and the behaviors documented here are expected to have equivalent
data, failure categories, state retention, and queue ordering on all four
targets.

It does not promise browser APIs, a DOM, browser compatibility, identical
diagnostic formatting, or target-specific platform services.

## Advanced integrations

Hosts that intentionally need custom native functions, host objects, raw
runtime values, or direct interpreter wiring should use the
[advanced embedding cookbook](advanced-embedding.md). Those APIs are outside
the stable embedding surface and may evolve with runtime internals.

See also the runnable [Rule Engine example](../example/rule_engine/) and the
[embedded runtime vision](design/embedded-runtime-vision.md).
