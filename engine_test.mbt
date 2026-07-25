///|
fn[T] expect_engine_diagnostic(
  result : Result[T, @js_engine.EngineDiagnostic],
) -> @js_engine.EngineDiagnostic raise {
  match result {
    Ok(_) => fail("expected an Engine diagnostic")
    Err(diagnostic) => diagnostic
  }
}

///|
fn engine_integrity_code(value : @js_engine.EngineIntegrity) -> String {
  match value {
    @js_engine.EngineIntegrity::Reusable => "reusable"
    @js_engine.EngineIntegrity::Discard => "discard"
    @js_engine.EngineIntegrity::Unknown => "unknown"
    @js_engine.EngineIntegrity::NotApplicable => "not-applicable"
  }
}

///|
fn retained_effects_code(value : @js_engine.RetainedEffects) -> String {
  match value {
    @js_engine.RetainedEffects::None => "none"
    @js_engine.RetainedEffects::MayRemain => "may-remain"
    @js_engine.RetainedEffects::Unknown => "unknown"
  }
}

///|
fn pending_jobs_code(value : @js_engine.PendingJobs) -> String {
  match value {
    @js_engine.PendingJobs::None => "none"
    @js_engine.PendingJobs::Present => "present"
    @js_engine.PendingJobs::Unknown => "unknown"
  }
}

///|
fn assert_engine_diagnostic(
  diagnostic : @js_engine.EngineDiagnostic,
  kind : String,
  operation : String,
  phase : String,
  source_identity : String?,
  integrity : String,
  effects : String,
  jobs : String,
) -> Unit raise {
  inspect(diagnostic.failure_kind_code(), content=kind)
  inspect(diagnostic.operation_code(), content=operation)
  inspect(diagnostic.phase_code(), content=phase)
  assert_true(diagnostic.source_identity() == source_identity)
  assert_true(diagnostic.source_location() is None)
  inspect(
    engine_integrity_code(diagnostic.engine_integrity()),
    content=integrity,
  )
  inspect(retained_effects_code(diagnostic.retained_effects()), content=effects)
  inspect(pending_jobs_code(diagnostic.pending_jobs()), content=jobs)
  assert_true(diagnostic.message().length() > 0)
}

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
test "Engine detailed eval reports a portable parse diagnostic" {
  let engine = @js_engine.Engine()
  engine.eval("queueMicrotask(() => {}); setTimeout(() => {}, 0);")
  let diagnostic = expect_engine_diagnostic(
    engine.eval_diagnostic("let =", source_id="rules.js"),
  )
  assert_engine_diagnostic(
    diagnostic,
    "parse-error",
    "eval",
    "parse",
    Some("rules.js"),
    "reusable",
    "none",
    "present",
  )
}

///|
test "Engine detailed operations preserve success values" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic("function echo(value) { return value; }") is Ok(_),
  )
  match engine.call_json_diagnostic("echo", [Json::string("portable")]) {
    Ok(value) => json_inspect(value, content="portable")
    Err(_) => fail("expected call_json success")
  }
  match engine.run_microtask_checkpoint_diagnostic() {
    Ok(has_more) => assert_false(has_more)
    Err(_) => fail("expected microtask checkpoint success")
  }
  assert_true(engine.run_timer_checkpoint_diagnostic() is Ok(_))
  match @js_engine.run_diagnostic("7", source_id="success.js") {
    Ok((output, value)) => {
      json_inspect(output, content=[])
      inspect(value, content="7")
    }
    Err(_) => fail("expected one-shot run success")
  }
}

///|
test "Engine detailed eval reports retained effects and pending jobs" {
  let engine = @js_engine.Engine()
  let diagnostic = expect_engine_diagnostic(
    engine.eval_diagnostic(
      (
        #|queueMicrotask(() => {});
        #|throw new Error("boom");
      ),
      source_id="eval.js",
    ),
  )
  assert_engine_diagnostic(
    diagnostic,
    "javascript-exception",
    "eval",
    "execute",
    Some("eval.js"),
    "reusable",
    "may-remain",
    "present",
  )
}

///|
test "Engine detailed call_json classifies every current phase" {
  let engine = @js_engine.Engine()
  let loaded = engine.eval_diagnostic(
    (
      #|let answer = 42;
      #|Object.defineProperty(globalThis, "throwingLookup", {
      #|  get() { throw new Error("lookup failed"); }
      #|});
      #|function throwDuringCall() { throw new Error("call failed"); }
      #|function identity(value) { return value; }
      #|function undefinedResult() { return undefined; }
    ),
    source_id="library.js",
  )
  assert_true(loaded is Ok(_))
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("absent", [])),
    "missing-global",
    "call-json",
    "lookup",
    None,
    "reusable",
    "none",
    "unknown",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("answer", [])),
    "not-callable",
    "call-json",
    "lookup",
    None,
    "reusable",
    "may-remain",
    "unknown",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("throwingLookup", [])),
    "javascript-exception",
    "call-json",
    "lookup",
    Some("library.js"),
    "reusable",
    "may-remain",
    "none",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("throwDuringCall", [])),
    "javascript-exception",
    "call-json",
    "execute",
    Some("library.js"),
    "reusable",
    "may-remain",
    "none",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(
      engine.call_json_diagnostic("identity", [Json::number(1.0 / 0.0)]),
    ),
    "json-conversion-error",
    "call-json",
    "argument-conversion",
    None,
    "reusable",
    "may-remain",
    "none",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("undefinedResult", [])),
    "json-conversion-error",
    "call-json",
    "result-conversion",
    None,
    "reusable",
    "may-remain",
    "none",
  )
}

///|
test "Engine detailed operations preserve per-origin source identity" {
  let call_engine = @js_engine.Engine()
  assert_true(
    call_engine.eval_diagnostic(
      "function failFromA() { throw new Error('A'); }",
      source_id="a.js",
    )
    is Ok(_),
  )
  assert_true(
    call_engine.eval_diagnostic(
      "function failFromB() { throw new Error('B'); }",
      source_id="b.js",
    )
    is Ok(_),
  )
  call_engine.eval(
    "function failWithoutIdentity() { throw new Error('legacy'); }",
  )
  assert_true(
    expect_engine_diagnostic(call_engine.call_json_diagnostic("failFromA", [])).source_identity() ==
    Some("a.js"),
  )
  assert_true(
    expect_engine_diagnostic(call_engine.call_json_diagnostic("failFromB", [])).source_identity() ==
    Some("b.js"),
  )
  assert_true(
    expect_engine_diagnostic(
      call_engine.call_json_diagnostic("failWithoutIdentity", []),
    ).source_identity()
    is None,
  )
  assert_true(
    call_engine.eval_diagnostic(
      "function nestedFailureFromB() { throw new Error('nested B'); }",
      source_id="nested-b.js",
    )
    is Ok(_),
  )
  assert_true(
    call_engine.eval_diagnostic(
      "function entryFromA() { nestedFailureFromB(); }",
      source_id="entry-a.js",
    )
    is Ok(_),
  )
  assert_true(
    expect_engine_diagnostic(call_engine.call_json_diagnostic("entryFromA", [])).source_identity() ==
    Some("nested-b.js"),
  )
  assert_true(
    call_engine.eval_diagnostic(
      (
        #|function catchBThenThrowA() {
        #|  try { nestedFailureFromB(); } catch (_) {}
        #|  throw new Error("new A");
        #|}
      ),
      source_id="catch-a.js",
    )
    is Ok(_),
  )
  assert_true(
    expect_engine_diagnostic(
      call_engine.call_json_diagnostic("catchBThenThrowA", []),
    ).source_identity() ==
    Some("catch-a.js"),
  )
  assert_true(
    call_engine.eval_diagnostic(
      "function lookupFailureFromB() { throw new Error('lookup B'); }",
      source_id="lookup-b.js",
    )
    is Ok(_),
  )
  assert_true(
    call_engine.eval_diagnostic(
      (
        #|Object.defineProperty(globalThis, "nestedThrowingLookup", {
        #|  get() { lookupFailureFromB(); }
        #|});
      ),
      source_id="getter-a.js",
    )
    is Ok(_),
  )
  assert_true(
    expect_engine_diagnostic(
      call_engine.call_json_diagnostic("nestedThrowingLookup", []),
    ).source_identity() ==
    Some("lookup-b.js"),
  )

  let microtask_engine = @js_engine.Engine()
  assert_true(
    microtask_engine.eval_diagnostic(
      "queueMicrotask(() => { throw new Error('microtask A'); });",
      source_id="microtask-a.js",
    )
    is Ok(_),
  )
  assert_true(
    microtask_engine.eval_diagnostic("0", source_id="later-b.js") is Ok(_),
  )
  assert_true(
    expect_engine_diagnostic(
      microtask_engine.run_microtask_checkpoint_diagnostic(),
    ).source_identity() ==
    Some("microtask-a.js"),
  )

  let timer_engine = @js_engine.Engine()
  assert_true(
    timer_engine.eval_diagnostic(
      "setTimeout(() => { throw new Error('timer A'); }, 0);",
      source_id="timer-a.js",
    )
    is Ok(_),
  )
  assert_true(
    timer_engine.eval_diagnostic("0", source_id="later-b.js") is Ok(_),
  )
  assert_true(
    expect_engine_diagnostic(timer_engine.run_timer_checkpoint_diagnostic()).source_identity() ==
    Some("timer-a.js"),
  )
}

///|
test "checkpoint diagnostics preserve deepest source identity" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic(
      "function asyncFailureFromB() { throw new Error('async B'); }",
      source_id="async-b.js",
    )
    is Ok(_),
  )
  assert_true(
    engine.eval_diagnostic(
      "queueMicrotask(() => { asyncFailureFromB(); });",
      source_id="microtask-a.js",
    )
    is Ok(_),
  )
  assert_true(
    expect_engine_diagnostic(engine.run_microtask_checkpoint_diagnostic()).source_identity() ==
    Some("async-b.js"),
  )

  let timer_engine = @js_engine.Engine()
  assert_true(
    timer_engine.eval_diagnostic(
      "function timerFailureFromB() { throw new Error('timer B'); }",
      source_id="timer-b.js",
    )
    is Ok(_),
  )
  assert_true(
    timer_engine.eval_diagnostic(
      "setTimeout(() => { timerFailureFromB(); }, 0);",
      source_id="timer-a.js",
    )
    is Ok(_),
  )
  assert_true(
    expect_engine_diagnostic(timer_engine.run_timer_checkpoint_diagnostic()).source_identity() ==
    Some("timer-b.js"),
  )
}

///|
test "identity-free nested code never inherits its caller source" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function scheduleLegacyFailure() {
      #|  queueMicrotask(() => { throw new Error("legacy failure"); });
      #|}
    ),
  )
  assert_true(
    engine.eval_diagnostic(
      "function identifiedEntry() { scheduleLegacyFailure(); return null; }",
      source_id="identified-entry.js",
    )
    is Ok(_),
  )
  assert_true(engine.call_json_diagnostic("identifiedEntry", []) is Ok(_))
  assert_true(
    expect_engine_diagnostic(engine.run_microtask_checkpoint_diagnostic()).source_identity()
    is None,
  )
}

///|
test "Engine detailed microtask checkpoint reports discard" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|queueMicrotask(() => {
      #|  queueMicrotask(() => {});
      #|  throw new Error("microtask failed");
      #|});
    ),
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.run_microtask_checkpoint_diagnostic()),
    "javascript-exception",
    "microtask-checkpoint",
    "microtask-dispatch",
    None,
    "discard",
    "may-remain",
    "present",
  )
}

///|
test "Engine detailed timer checkpoint preserves callback phases" {
  let callback_engine = @js_engine.Engine()
  callback_engine.eval(
    (
      #|setTimeout(() => { throw new Error("timer failed"); }, 0);
      #|setTimeout(() => {}, 0);
    ),
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(callback_engine.run_timer_checkpoint_diagnostic()),
    "javascript-exception",
    "timer-checkpoint",
    "timer-callback",
    None,
    "discard",
    "may-remain",
    "present",
  )
  let checkpoint_engine = @js_engine.Engine()
  checkpoint_engine.eval(
    (
      #|setTimeout(() => {
      #|  queueMicrotask(() => {
      #|    queueMicrotask(() => {});
      #|    throw new Error("timer microtask failed");
      #|  });
      #|}, 0);
    ),
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(
      checkpoint_engine.run_timer_checkpoint_diagnostic(),
    ),
    "javascript-exception",
    "timer-checkpoint",
    "timer-microtask-checkpoint",
    None,
    "discard",
    "may-remain",
    "present",
  )
  let interval_engine = @js_engine.Engine()
  interval_engine.eval(
    "setInterval(() => { throw new Error('interval failed'); }, 0);",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(interval_engine.run_timer_checkpoint_diagnostic()),
    "javascript-exception",
    "timer-checkpoint",
    "interval-callback",
    None,
    "discard",
    "may-remain",
    "none",
  )
}

///|
test "one-shot detailed run preserves every public phase" {
  assert_engine_diagnostic(
    expect_engine_diagnostic(
      @js_engine.run_diagnostic("let =", source_id="run.js"),
    ),
    "parse-error",
    "run",
    "parse",
    Some("run.js"),
    "not-applicable",
    "none",
    "unknown",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(
      @js_engine.run_diagnostic(
        "throw new Error('run failed');",
        source_id="run.js",
      ),
    ),
    "javascript-exception",
    "run",
    "execute",
    Some("run.js"),
    "not-applicable",
    "may-remain",
    "unknown",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(
      @js_engine.run_diagnostic(
        "queueMicrotask(() => { throw new Error('microtask failed'); });",
        source_id="run.js",
      ),
    ),
    "javascript-exception",
    "run",
    "microtask-dispatch",
    Some("run.js"),
    "not-applicable",
    "unknown",
    "unknown",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(
      @js_engine.run_diagnostic(
        "setTimeout(() => { throw new Error('timer failed'); }, 0);",
        source_id="run.js",
      ),
    ),
    "javascript-exception",
    "run",
    "timer-callback",
    Some("run.js"),
    "not-applicable",
    "unknown",
    "unknown",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(
      @js_engine.run_diagnostic(
        (
          #|setTimeout(() => {
          #|  queueMicrotask(() => { throw new Error("timer microtask failed"); });
          #|}, 0);
        ),
        source_id="run.js",
      ),
    ),
    "javascript-exception",
    "run",
    "timer-microtask-checkpoint",
    Some("run.js"),
    "not-applicable",
    "unknown",
    "unknown",
  )
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
test "EngineError variants, payloads, and Show output remain stable" {
  let errors : Array[@js_engine.EngineError] = [
    @js_engine.ParseError("parse"),
    @js_engine.JavaScriptException("javascript"),
    @js_engine.MissingGlobal("missing"),
    @js_engine.NotCallable("callable"),
    @js_engine.JsonConversionError("json"),
    @js_engine.InternalError("internal"),
  ]
  json_inspect(errors.map(error => error.to_string()), content=[
    "ParseError: parse", "JavaScriptException: javascript", "MissingGlobal: missing",
    "NotCallable: callable", "JsonConversionError: json", "InternalError: internal",
  ])
  json_inspect(
    errors.map(error => {
      match error {
        @js_engine.ParseError(message) => "parse:" + message
        @js_engine.JavaScriptException(message) => "javascript:" + message
        @js_engine.MissingGlobal(message) => "missing:" + message
        @js_engine.NotCallable(message) => "not-callable:" + message
        @js_engine.JsonConversionError(message) => "json:" + message
        @js_engine.InternalError(message) => "internal:" + message
      }
    }),
    content=[
      "parse:parse", "javascript:javascript", "missing:missing", "not-callable:callable",
      "json:json", "internal:internal",
    ],
  )
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

///|
test "Engine failure reuse matrix: parse failure keeps prior state and queues" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = ["seed"];
      #|Promise.resolve().then(() => { events.push("microtask"); });
      #|setTimeout(() => { events.push("timer"); }, 0);
      #|function snapshot() { return events; }
    ),
  )
  let failure = try {
    engine.eval("let =")
    "no error"
  } catch {
    @js_engine.ParseError(_) => "parse"
    err => "wrong:" + err.to_string()
  }
  inspect(failure, content="parse")
  json_inspect(engine.call_json("snapshot", []), content=["seed"])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="true")
  inspect(engine.run_microtask_checkpoint(), content="false")
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("snapshot", []), content=[
    "seed", "microtask", "timer",
  ])
}

///|
test "Engine failure reuse matrix: eval throw retains state and queues" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|function snapshot() { return events; }
    ),
  )
  let failure = try {
    engine.eval(
      (
        #|events.push("before throw");
        #|Promise.resolve().then(() => { events.push("microtask"); });
        #|setTimeout(() => { events.push("timer"); }, 0);
        #|throw new Error("boom");
      ),
    )
    "no error"
  } catch {
    @js_engine.JavaScriptException(_) => "javascript"
    err => "wrong:" + err.to_string()
  }
  inspect(failure, content="javascript")
  json_inspect(engine.call_json("snapshot", []), content=["before throw"])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="true")
  inspect(engine.run_microtask_checkpoint(), content="false")
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("snapshot", []), content=[
    "before throw", "microtask", "timer",
  ])
}

///|
test "Engine failure reuse matrix: JavaScript throw retains state and queues" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|function snapshot() { return events; }
      #|function throwAfterQueueing() {
      #|  events.push("before throw");
      #|  Promise.resolve().then(() => { events.push("microtask"); });
      #|  setTimeout(() => { events.push("timer"); }, 0);
      #|  throw new Error("boom");
      #|}
    ),
  )
  let failure = try {
    let _ = engine.call_json("throwAfterQueueing", [])
    "no error"
  } catch {
    @js_engine.JavaScriptException(_) => "javascript"
    err => "wrong:" + err.to_string()
  }
  inspect(failure, content="javascript")
  json_inspect(engine.call_json("snapshot", []), content=["before throw"])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="true")
  inspect(engine.run_microtask_checkpoint(), content="false")
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("snapshot", []), content=[
    "before throw", "microtask", "timer",
  ])
}

///|
test "Engine failure reuse matrix: lookup throw retains state and queues" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|Object.defineProperty(globalThis, "throwDuringLookup", {
      #|  get() {
      #|    events.push("getter");
      #|    Promise.resolve().then(() => { events.push("microtask"); });
      #|    setTimeout(() => { events.push("timer"); }, 0);
      #|    throw new Error("lookup failed");
      #|  }
      #|});
      #|function snapshot() { return events; }
    ),
  )
  let failure = try {
    let _ = engine.call_json("throwDuringLookup", [])
    "no error"
  } catch {
    @js_engine.JavaScriptException(_) => "javascript"
    err => "wrong:" + err.to_string()
  }
  inspect(failure, content="javascript")
  json_inspect(engine.call_json("snapshot", []), content=["getter"])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="true")
  inspect(engine.run_microtask_checkpoint(), content="false")
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("snapshot", []), content=[
    "getter", "microtask", "timer",
  ])
}

///|
test "Engine failure reuse matrix: JSON argument conversion failure skips call" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = ["seed"];
      #|Promise.resolve().then(() => { events.push("existing microtask"); });
      #|setTimeout(() => { events.push("existing timer"); }, 0);
      #|Object.defineProperty(globalThis, "mutate", {
      #|  get() {
      #|    events.push("getter");
      #|    Promise.resolve().then(() => { events.push("getter microtask"); });
      #|    setTimeout(() => { events.push("getter timer"); }, 0);
      #|    return function(_) { events.push("called"); return events; };
      #|  }
      #|});
      #|function snapshot() { return events; }
    ),
  )
  let failure = try {
    let _ = engine.call_json("mutate", [Json::number(1.0 / 0.0)])
    "no error"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  inspect(failure, content="conversion")
  json_inspect(engine.call_json("snapshot", []), content=["seed", "getter"])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="true")
  inspect(engine.run_microtask_checkpoint(), content="false")
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("snapshot", []), content=[
    "seed", "getter", "existing microtask", "getter microtask", "existing timer",
    "getter timer",
  ])
}

///|
test "Engine failure reuse matrix: JSON result conversion failure retains state and queues" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|function rejectResultAfterQueueing() {
      #|  events.push("called");
      #|  Promise.resolve().then(() => { events.push("microtask"); });
      #|  setTimeout(() => { events.push("timer"); }, 0);
      #|  return undefined;
      #|}
      #|function snapshot() { return events; }
    ),
  )
  let failure = try {
    let _ = engine.call_json("rejectResultAfterQueueing", [])
    "no error"
  } catch {
    @js_engine.JsonConversionError(_) => "conversion"
    err => "wrong:" + err.to_string()
  }
  inspect(failure, content="conversion")
  json_inspect(engine.call_json("snapshot", []), content=["called"])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="true")
  inspect(engine.run_microtask_checkpoint(), content="false")
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("snapshot", []), content=[
    "called", "microtask", "timer",
  ])
}

///|
fn assert_javascript_exception(
  action : () -> Unit raise @js_engine.EngineError,
) -> Unit raise {
  let failure = try {
    action()
    "no error"
  } catch {
    @js_engine.JavaScriptException(_) => "javascript"
    err => "wrong:" + err.to_string()
  }
  inspect(failure, content="javascript")
}

///|
test "Engine checkpoint failure matrix: microtask throw consumes dispatched jobs" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|let attempts = 0;
      #|queueMicrotask(() => { events.push("prefix"); });
      #|queueMicrotask(() => {
      #|  attempts += 1;
      #|  const current = attempts;
      #|  events.push("job:" + current);
      #|  queueMicrotask(() => { events.push("nested:" + current); });
      #|  if (current === 1) { throw new Error("microtask failed"); }
      #|});
      #|function snapshot() { return events; }
    ),
  )
  assert_javascript_exception(() => {
    let _ = engine.run_microtask_checkpoint()
  })
  json_inspect(engine.call_json("snapshot", []), content=["prefix", "job:1"])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="false")
  inspect(engine.run_microtask_checkpoint(), content="false")
  // A failed drain consumes the completed prefix and throwing job. Diagnostic
  // retry runs only the nested job appended before the throw.
  json_inspect(engine.call_json("snapshot", []), content=[
    "prefix", "job:1", "nested:1",
  ])
}

///|
test "Engine checkpoint failure matrix: timer callback throw consumes the timer" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|setTimeout(() => {
      #|  events.push("throwing timer");
      #|  queueMicrotask(() => { events.push("queued microtask"); });
      #|  setTimeout(() => { events.push("new timer"); }, 0);
      #|  throw new Error("timer failed");
      #|}, 0);
      #|setTimeout(() => { events.push("later timer"); }, 0);
      #|function snapshot() { return events; }
    ),
  )
  assert_javascript_exception(() => engine.run_timer_checkpoint())
  json_inspect(engine.call_json("snapshot", []), content=["throwing timer"])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="true")
  inspect(engine.run_microtask_checkpoint(), content="false")
  json_inspect(engine.call_json("snapshot", []), content=[
    "throwing timer", "queued microtask",
  ])
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("snapshot", []), content=[
    "throwing timer", "queued microtask", "later timer", "new timer",
  ])
  inspect(engine.has_pending_microtasks(), content="false")
  inspect(engine.has_pending_timers(), content="false")
}

///|
test "Engine checkpoint failure matrix: timer microtask throw consumes dispatched job" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|let attempts = 0;
      #|setTimeout(() => {
      #|  events.push("timer 1");
      #|  queueMicrotask(() => {
      #|    attempts += 1;
      #|    const current = attempts;
      #|    events.push("microtask:" + current);
      #|    queueMicrotask(() => { events.push("nested:" + current); });
      #|    if (current === 1) { throw new Error("microtask failed"); }
      #|  });
      #|}, 0);
      #|setTimeout(() => { events.push("timer 2"); }, 0);
      #|function snapshot() { return events; }
    ),
  )
  assert_javascript_exception(() => engine.run_timer_checkpoint())
  json_inspect(engine.call_json("snapshot", []), content=[
    "timer 1", "microtask:1",
  ])
  inspect(engine.has_pending_microtasks(), content="true")
  inspect(engine.has_pending_timers(), content="true")
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("snapshot", []), content=[
    "timer 1", "microtask:1", "timer 2", "nested:1",
  ])
  inspect(engine.has_pending_microtasks(), content="false")
  inspect(engine.has_pending_timers(), content="false")
}

///|
test "Engine checkpoint failure matrix: interval callback throw drops the interval" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|setInterval(() => {
      #|  events.push("interval");
      #|  throw new Error("interval failed");
      #|}, 0);
      #|function snapshot() { return events; }
    ),
  )
  assert_javascript_exception(() => engine.run_timer_checkpoint())
  json_inspect(engine.call_json("snapshot", []), content=["interval"])
  inspect(engine.has_pending_microtasks(), content="false")
  inspect(engine.has_pending_timers(), content="false")
  engine.run_timer_checkpoint()
  json_inspect(engine.call_json("snapshot", []), content=["interval"])
  inspect(engine.has_pending_microtasks(), content="false")
  inspect(engine.has_pending_timers(), content="false")
}
