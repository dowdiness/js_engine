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
  engine.eval("let answer = 42")
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
}

///|
test "Engine calls functions exported on the global object" {
  let engine = @js_engine.Engine()
  let source =
    #|globalThis.fromGlobalThis = function(value) { return value + 1; };
    #|this.fromThis = function(value) { return value + 2; };
    #|globalThis.globalValue = 42;
  engine.eval(source)
  json_inspect(
    engine.call_json("fromGlobalThis", [Json::number(1.0)]),
    content=2,
  )
  json_inspect(engine.call_json("fromThis", [Json::number(1.0)]), content=3)
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
test "Engine leaves jobs pending until explicit checkpoints" {
  let engine = @js_engine.Engine()
  let source =
    #|let microtaskDone = false;
    #|let timerDone = false;
    #|Promise.resolve().then(() => { microtaskDone = true; });
    #|setTimeout(() => { timerDone = true; }, 0);
    #|function jobState() { return [microtaskDone, timerDone]; }
  engine.eval(source)
  json_inspect(engine.call_json("jobState", []), content=[false, false])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="true")
  ignore(engine.run_microtask_checkpoint())
  json_inspect(engine.call_json("jobState", []), content=[true, false])
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("jobState", []), content=[true, true])
  inspect(engine.has_pending_microtasks(), content="false")
  inspect(engine.has_pending_timers(), content="false")
}
