///|
test "Engine preserves state and isolates realms" {
  let first = @js_engine.Engine()
  let second = @js_engine.Engine()
  let first_source =
    #|let count = 0;
    #|function next(delta) { count += delta; return count; }
  let second_source =
    #|let count = 100;
    #|function next(delta) { count += delta; return count; }
  first.eval(first_source)
  second.eval(second_source)
  json_inspect(first.call_json("next", [Json::number(2.0)]), content=2)
  json_inspect(first.call_json("next", [Json::number(3.0)]), content=5)
  json_inspect(second.call_json("next", [Json::number(1.0)]), content=101)
}

///|
test "Engine distinguishes missing and non-callable globals" {
  let engine = @js_engine.Engine()
  engine.eval("let answer = 42; function ok() { return true; }")
  let missing = try {
    let _ = engine.call_json("absent", [])
    "no error"
  } catch {
    @js_engine.MissingGlobal(name) => "missing:" + name
    err => "wrong:" + err.to_string()
  }
  let non_callable = try {
    let _ = engine.call_json("answer", [])
    "no error"
  } catch {
    @js_engine.NotCallable(name) => "not-callable:" + name
    err => "wrong:" + err.to_string()
  }
  inspect(missing, content="missing:absent")
  inspect(non_callable, content="not-callable:answer")
  json_inspect(engine.call_json("ok", []), content=true)
}

///|
test "Engine calls functions exported on the global object" {
  let engine = @js_engine.Engine()
  let source =
    #|globalThis.fromGlobalThis = function(value) { return value + 1; };
    #|this.fromThis = function(value) { return value + 2; };
    #|globalThis.globalValue = 42;
    #|let shadowed = function() { return "binding"; };
    #|globalThis.shadowed = function() { return "globalThis"; };
  engine.eval(source)
  json_inspect(
    engine.call_json("fromGlobalThis", [Json::number(1.0)]),
    content=2,
  )
  json_inspect(engine.call_json("fromThis", [Json::number(1.0)]), content=3)
  json_inspect(engine.call_json("shadowed", []), content="binding")
  let not_callable = try {
    let _ = engine.call_json("globalValue", [])
    "no error"
  } catch {
    @js_engine.NotCallable(name) => "not-callable:" + name
    err => "wrong:" + err.to_string()
  }
  inspect(not_callable, content="not-callable:globalValue")
}

///|
test "Engine global-object lookup executes own accessor getters" {
  let engine = @js_engine.Engine()
  let source =
    #|let lookupCount = 0;
    #|Object.defineProperty(globalThis, "callableGetter", {
    #|  get() {
    #|    lookupCount += 1;
    #|    return function() { return lookupCount; };
    #|  }
    #|});
    #|Object.defineProperty(globalThis, "nonCallableGetter", {
    #|  get() { lookupCount += 1; return 42; }
    #|});
    #|Object.defineProperty(globalThis, "throwingGetter", {
    #|  get() { lookupCount += 1; throw new Error("lookup failed"); }
    #|});
    #|function currentLookupCount() { return lookupCount; }
  engine.eval(source)
  json_inspect(engine.call_json("callableGetter", []), content=1)
  let non_callable = try {
    let _ = engine.call_json("nonCallableGetter", [])
    "no error"
  } catch {
    @js_engine.NotCallable(_) => "not-callable"
    err => "wrong:" + err.to_string()
  }
  let thrown = try {
    let _ = engine.call_json("throwingGetter", [])
    "no error"
  } catch {
    @js_engine.JavaScriptException(_) => "javascript"
    err => "wrong:" + err.to_string()
  }
  inspect(non_callable, content="not-callable")
  inspect(thrown, content="javascript")
  json_inspect(engine.call_json("currentLookupCount", []), content=3)
}

///|
test "Engine take_output consumes a copied buffer" {
  let engine = @js_engine.Engine()
  engine.eval("console.log('once')")
  let first = engine.take_output()
  let second = engine.take_output()
  json_inspect(first, content=["once"])
  json_inspect(second, content=[])
}

///|
test "Engine JSON boundary copies every JSON data kind" {
  let engine = @js_engine.Engine()
  engine.eval("function identity(value) { return value; }")
  let nested : Map[String, Json] = {
    "null": Json::null(),
    "bool": Json::boolean(true),
    "number": Json::number(3.5),
    "string": Json::string("moon"),
    "array": Json::array([Json::number(1.0), Json::boolean(false), Json::null()]),
  }
  let input = Json::object(nested)
  json_inspect(engine.call_json("identity", [input]), content={
    "null": null,
    "bool": true,
    "number": 3.5,
    "string": "moon",
    "array": [1, false, null],
  })
}

///|
test "Engine JSON boundary ignores a poisoned global JSON object" {
  let engine = @js_engine.Engine()
  let source =
    #|JSON.parse = function() { throw new Error("poisoned parse"); };
    #|JSON.stringify = function() { throw new Error("poisoned stringify"); };
    #|function identity(value) { return value; }
  engine.eval(source)
  json_inspect(
    engine.call_json("identity", [Json::object({ "ok": Json::boolean(true) })]),
    content={ "ok": true },
  )
}

///|
test "Engine rejects non-data results without executing user conversion hooks" {
  let engine = @js_engine.Engine()
  let source =
    #|let touched = 0;
    #|function withAccessor() {
    #|  const value = {};
    #|  Object.defineProperty(value, "secret", {
    #|    enumerable: true,
    #|    get() { touched += 1; return 1; }
    #|  });
    #|  return value;
    #|}
    #|function withToJSON() {
    #|  return { value: 1, toJSON() { touched += 10; return { value: 2 }; } };
    #|}
    #|function withProxy() {
    #|  return new Proxy({ value: 1 }, {
    #|    ownKeys() { touched += 100; return ["value"]; }
    #|  });
    #|}
    #|function touchedCount() { return touched; }
  engine.eval(source)
  let accessor_error = try {
    let _ = engine.call_json("withAccessor", [])
    "no error"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  let to_json_error = try {
    let _ = engine.call_json("withToJSON", [])
    "no error"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  let proxy_error = try {
    let _ = engine.call_json("withProxy", [])
    "no error"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  inspect(accessor_error, content="conversion")
  inspect(to_json_error, content="conversion")
  inspect(proxy_error, content="conversion")
  json_inspect(engine.call_json("touchedCount", []), content=0)
}

///|
test "Engine only accepts plain-object prototypes at the JSON boundary" {
  let engine = @js_engine.Engine()
  let source =
    #|function Custom() { this.value = 1; }
    #|function customInstance() { return new Custom(); }
    #|function customPrototype() {
    #|  return Object.create({ inherited: true }, {
    #|    value: { value: 2, enumerable: true }
    #|  });
    #|}
    #|function nullPrototype() {
    #|  const value = Object.create(null);
    #|  value.ok = true;
    #|  return value;
    #|}
  engine.eval(source)
  let constructor_error = try {
    let _ = engine.call_json("customInstance", [])
    "no error"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  let prototype_error = try {
    let _ = engine.call_json("customPrototype", [])
    "no error"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  inspect(constructor_error, content="conversion")
  inspect(prototype_error, content="conversion")
  json_inspect(engine.call_json("nullPrototype", []), content={ "ok": true })
}

///|
test "Engine rejects Promise undefined and cyclic results" {
  let engine = @js_engine.Engine()
  let source =
    #|function asyncResult() { return Promise.resolve(1); }
    #|function undefinedResult() { return undefined; }
    #|function cyclicResult() { const value = {}; value.self = value; return value; }
  engine.eval(source)
  let promise = try {
    let _ = engine.call_json("asyncResult", [])
    "no error"
  } catch {
    @js_engine.JsonConversionError(message) => message
    err => "wrong:" + err.to_string()
  }
  let undefined = try {
    let _ = engine.call_json("undefinedResult", [])
    "no error"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  let cyclic = try {
    let _ = engine.call_json("cyclicResult", [])
    "no error"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  inspect(
    promise,
    content="Promise results are asynchronous; call_json only accepts synchronous JSON results",
  )
  inspect(undefined, content="conversion")
  inspect(cyclic, content="conversion")
}

///|
test "Engine rejects remaining non-JSON result categories" {
  let engine = @js_engine.Engine()
  let source =
    #|function nonFiniteResult() { return NaN; }
    #|function symbolResult() { return Symbol("value"); }
    #|function functionResult() { return function() {}; }
    #|function mapResult() { return new Map(); }
    #|function setResult() { return new Set(); }
    #|function sparseArrayResult() { const value = []; value.length = 1; return value; }
    #|function customArrayResult() { const value = []; value.extra = 1; return value; }
    #|function nonEnumerableResult() {
    #|  return Object.defineProperty({}, "hidden", { value: 1, enumerable: false });
    #|}
    #|function symbolPropertyResult() {
    #|  const value = {};
    #|  value[Symbol("hidden")] = 1;
    #|  return value;
    #|}
  engine.eval(source)
  let classifications : Array[String] = []
  for
    name in [
      "nonFiniteResult", "symbolResult", "functionResult", "mapResult", "setResult",
      "sparseArrayResult", "customArrayResult", "nonEnumerableResult", "symbolPropertyResult",
    ] {
    let classification = try {
      let _ = engine.call_json(name, [])
      "accepted"
    } catch {
      @js_engine.JsonConversionError(_) => "conversion"
      err => "wrong:" + err.to_string()
    }
    classifications.push(classification)
  }
  json_inspect(classifications, content=[
    "conversion", "conversion", "conversion", "conversion", "conversion", "conversion",
    "conversion", "conversion", "conversion",
  ])
  engine.eval("function identity(value) { return value; }")
  let non_finite_input = try {
    let _ = engine.call_json("identity", [Json::number(1.0 / 0.0)])
    "accepted"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  inspect(non_finite_input, content="conversion")
}

///|
test "Engine classifies errors by phase and remains reusable without rollback" {
  let engine = @js_engine.Engine()
  engine.eval("var marker = 0; function markerValue() { return marker; }")
  let parse = try {
    engine.eval("let =")
    "no error"
  } catch {
    @js_engine.ParseError(_) => "parse"
    err => "wrong:" + err.to_string()
  }
  let runtime_syntax = try {
    engine.eval("eval('let =')")
    "no error"
  } catch {
    @js_engine.JavaScriptException(_) => "javascript"
    err => "wrong:" + err.to_string()
  }
  let thrown = try {
    engine.eval("marker = 7; throw new Error('boom')")
    "no error"
  } catch {
    @js_engine.JavaScriptException(_) => "javascript"
    err => "wrong:" + err.to_string()
  }
  inspect(parse, content="parse")
  inspect(runtime_syntax, content="javascript")
  inspect(thrown, content="javascript")
  json_inspect(engine.call_json("markerValue", []), content=7)
}

///|
test "Engine call_json failures retain mutations and remain reusable" {
  let engine = @js_engine.Engine()
  let source =
    #|let calls = 0;
    #|function throwAfterMutation() {
    #|  calls += 1;
    #|  throw new Error("boom");
    #|}
    #|function rejectAfterMutation() {
    #|  calls += 1;
    #|  return undefined;
    #|}
    #|function callCount() { return calls; }
  engine.eval(source)
  let thrown = try {
    let _ = engine.call_json("throwAfterMutation", [])
    "no error"
  } catch {
    @js_engine.JavaScriptException(_) => "javascript"
    err => "wrong:" + err.to_string()
  }
  inspect(thrown, content="javascript")
  json_inspect(engine.call_json("callCount", []), content=1)
  let rejected = try {
    let _ = engine.call_json("rejectAfterMutation", [])
    "no error"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  inspect(rejected, content="conversion")
  json_inspect(engine.call_json("callCount", []), content=2)
}

///|
test "Engine leaves jobs pending until explicit checkpoints" {
  let engine = @js_engine.Engine()
  let source =
    #|let events = [];
    #|Promise.resolve().then(() => { events.push("initial microtask"); });
    #|setTimeout(() => {
    #|  events.push("timer 1");
    #|  Promise.resolve().then(() => { events.push("timer 1 microtask"); });
    #|}, 0);
    #|setTimeout(() => { events.push("timer 2"); }, 0);
    #|function jobState() { return events; }
  engine.eval(source)
  json_inspect(engine.call_json("jobState", []), content=[])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="true")
  inspect(engine.run_microtask_checkpoint(), content="false")
  json_inspect(engine.call_json("jobState", []), content=["initial microtask"])
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("jobState", []), content=[
    "initial microtask", "timer 1", "timer 1 microtask", "timer 2",
  ])
  inspect(engine.has_pending_microtasks(), content="false")
  inspect(engine.has_pending_timers(), content="false")
}
