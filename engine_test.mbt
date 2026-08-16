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
  has_location? : Bool = false,
) -> Unit raise {
  inspect(diagnostic.failure_kind_code(), content=kind)
  inspect(diagnostic.operation_code(), content=operation)
  inspect(diagnostic.phase_code(), content=phase)
  assert_true(diagnostic.source_identity() == source_identity)
  assert_true((diagnostic.source_location() is Some(_)) == has_location)
  inspect(
    engine_integrity_code(diagnostic.engine_integrity()),
    content=integrity,
  )
  inspect(retained_effects_code(diagnostic.retained_effects()), content=effects)
  inspect(pending_jobs_code(diagnostic.pending_jobs()), content=jobs)
  assert_true(diagnostic.message().length() > 0)
}

///|
fn assert_source_range(
  diagnostic : @js_engine.EngineDiagnostic,
  start_line : Int,
  start_column : Int,
  start_offset : Int,
  end_line : Int,
  end_column : Int,
  end_offset : Int,
) -> Unit raise {
  guard diagnostic.source_location() is Some(location) else {
    fail("expected parser source location")
  }
  let start = location.start()
  json_inspect([start.line(), start.column(), start.offset()], content=[
    start_line, start_column, start_offset,
  ])
  guard location.end() is Some(end) else {
    fail("expected parser source range end")
  }
  json_inspect([end.line(), end.column(), end.offset()], content=[
    end_line, end_column, end_offset,
  ])
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
test "Engine plain addition coercion remains reusable after abrupt completion" {
  let engine = @js_engine.Engine()
  engine.eval("function add(left, right) { return left + right; }")
  json_inspect(
    engine.call_json("add", [Json::number(2.0), Json::number(3.0)]),
    content=5,
  )
  engine.eval(
    "var hintSeen = ''; " +
    "var box = {}; " +
    "box[Symbol.toPrimitive] = function(hint) { " +
    "console.log(hint); queueMicrotask(() => console.log('micro')); " +
    "hintSeen = hint; return 4; }; " +
    "function addBox() { return box + 2; }",
  )
  json_inspect(engine.call_json("addBox", []), content=6)
  json_inspect(engine.take_output(), content=["default"])
  assert_true(engine.has_pending_microtasks())
  assert_false(engine.run_microtask_checkpoint())
  json_inspect(engine.take_output(), content=["micro"])
  let failure : @js_engine.EngineError? = try {
    engine.eval(
      "var bad = {}; " +
      "bad[Symbol.toPrimitive] = function() { throw new Error('boom'); }; " +
      "function failAdd() { return bad + 1; }",
    )
    let _ = engine.call_json("failAdd", [])
    None
  } catch {
    error => Some(error)
  }
  match failure {
    Some(@js_engine.JavaScriptException(_)) => ()
    Some(error) =>
      fail("expected JavaScriptException, got " + error.to_string())
    None => fail("abrupt addition unexpectedly completed")
  }
  engine.eval("function afterFailure() { return 9 + 1; }")
  json_inspect(engine.call_json("afterFailure", []), content=10)
}

///|
// Stable default-vs-candidate Array coercion parity seam.
test "Engine Array valueOf participates in addition" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var a = [1]; " +
    "a.valueOf = function() { return 2; }; " +
    "function arrayValueOfAdd() { return a + 1; }",
  )
  json_inspect(engine.call_json("arrayValueOfAdd", []), content=3)
}

///|
test "Engine iterable spread preserves order and reuse" {
  let engine = @js_engine.Engine()
  engine.eval(
    "function arraySpread() { return [0, ...[1, 2], 3].join(','); } " +
    "function callSpread(left, right) { " +
    "return (function(a, b, c, d) { return [a, b, c, d].join(','); })(" +
    "0, ...left, 2, ...right); }",
  )
  json_inspect(engine.call_json("arraySpread", []), content="0,1,2,3")
  json_inspect(
    engine.call_json("callSpread", [
      Json::array([Json::number(1.0)]),
      Json::array([Json::number(3.0)]),
    ]),
    content="0,1,2,3",
  )
  json_inspect(engine.call_json("arraySpread", []), content="0,1,2,3")
}

///|
test "Engine Array Symbol.toPrimitive keeps hint and receiver" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var a = [1]; " +
    "var seen = ''; " +
    "a[Symbol.toPrimitive] = function(hint) { " +
    "seen = hint + (this === a); return 40; }; " +
    "function arraySymbolAdd() { return [a + 1, seen]; }",
  )
  json_inspect(engine.call_json("arraySymbolAdd", []), content=[
    41, "defaulttrue",
  ])
}

///|
test "Engine Array toString participates in addition" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var a = [1]; " +
    "a.toString = function() { return 'custom'; }; " +
    "function arrayToStringAdd() { return a + 1; }",
  )
  json_inspect(engine.call_json("arrayToStringAdd", []), content="custom1")
}

///|
test "Engine Array coercion hook matrix preserves parity" {
  let engine = @js_engine.Engine()
  engine.eval(
    "var events = ''; " +
    "var symbolArray = [1]; " +
    "symbolArray[Symbol.toPrimitive] = function(hint) { " +
    "events = events + 'symbol:' + hint + ':' + (this === symbolArray) + ';'; " +
    "return 4; }; " +
    "var valueOfArray = [1]; " +
    "valueOfArray.valueOf = function() { " +
    "events = events + 'valueOf:' + (this === valueOfArray) + ';'; " +
    "return 5; }; " +
    "var toStringArray = [1]; " +
    "toStringArray.toString = function() { " +
    "events = events + 'toString:' + (this === toStringArray) + ';'; " +
    "return 'string'; }; " +
    "var accessorArray = [1]; " +
    "Object.defineProperty(accessorArray, Symbol.toPrimitive, { get: function() { " +
    "events = events + 'getter;'; " +
    "return function(hint) { events = events + 'accessor:' + hint + ':' + (this === accessorArray) + ';'; return 6; }; " +
    "} }); " +
    "var throwArray = [1]; " +
    "throwArray.valueOf = function() { events = events + 'throw;'; throw 'guest'; }; " +
    "var objectResultArray = [1]; " +
    "objectResultArray.valueOf = function() { events = events + 'object;'; return {}; }; " +
    "objectResultArray.toString = function() { events = events + 'objectString;'; return {}; }; " +
    "function arrayCoercionMatrix() { " +
    "var thrown = 'none'; try { throwArray + 1; } catch (error) { thrown = error; } " +
    "var typeError = false; try { objectResultArray + 1; } catch (error) { typeError = error instanceof TypeError; } " +
    "return { results: [symbolArray + 1, valueOfArray + 1, toStringArray + 1, accessorArray + 1], thrown: thrown, typeError: typeError, events: events }; }",
  )
  json_inspect(engine.call_json("arrayCoercionMatrix", []), content={
    "results": [5, 6, "string1", 7],
    "thrown": "guest",
    "typeError": true,
    "events": "throw;object;objectString;symbol:default:true;valueOf:true;toString:true;getter;accessor:default:true;",
  })
}

///|
test "Engine inject_json exposes immutable host-owned data" {
  let engine = @js_engine.Engine()
  let config = Json::object({
    "environment": Json::string("production"),
    "limits": Json::object({ "retries": Json::number(3.0) }),
  })
  match engine.inject_json("hostConfig", config) {
    Ok(_) => ()
    Err(_) => fail("expected host-owned JSON injection to succeed")
  }
  engine.eval(
    (
      #|function injectedSnapshot() {
      #|  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "hostConfig");
      #|  return {
      #|    identifier: hostConfig,
      #|    property: globalThis.hostConfig,
      #|    descriptor: {
      #|      writable: descriptor.writable,
      #|      enumerable: descriptor.enumerable,
      #|      configurable: descriptor.configurable
      #|    }
      #|  };
      #|}
    ),
  )
  json_inspect(engine.call_json("injectedSnapshot", []), content={
    "identifier": { "environment": "production", "limits": { "retries": 3 } },
    "property": { "environment": "production", "limits": { "retries": 3 } },
    "descriptor": {
      "writable": false,
      "enumerable": true,
      "configurable": false,
    },
  })
}

///|
test "Engine inject_json rejects collisions without changing state or queues" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let occupiedBinding = 1;
      #|Object.defineProperty(globalThis, "occupiedProperty", {
      #|  value: 2,
      #|  configurable: true
      #|});
      #|queueMicrotask(() => {});
      #|function collisionSnapshot() {
      #|  return [occupiedBinding, globalThis.occupiedProperty];
      #|}
    ),
  )
  for name in ["occupiedBinding", "occupiedProperty"] {
    let diagnostic = expect_engine_diagnostic(
      engine.inject_json(name, Json::number(9.0)),
    )
    assert_engine_diagnostic(
      diagnostic,
      "injection-conflict",
      "inject-json",
      "define",
      None,
      "reusable",
      "none",
      "present",
    )
  }
  json_inspect(engine.call_json("collisionSnapshot", []), content=[1, 2])
}

///|
test "Engine inject_json conversion failure is atomic and reusable" {
  let engine = @js_engine.Engine()
  engine.eval("queueMicrotask(() => {});")
  let diagnostic = expect_engine_diagnostic(
    engine.inject_json("retryableConfig", Json::number(1.0 / 0.0)),
  )
  assert_engine_diagnostic(
    diagnostic,
    "json-conversion-error",
    "inject-json",
    "conversion",
    None,
    "reusable",
    "none",
    "present",
  )
  assert_true(
    engine.inject_json("retryableConfig", Json::string("valid")) is Ok(_),
  )
  engine.eval("function readRetryableConfig() { return retryableConfig; }")
  json_inspect(engine.call_json("readRetryableConfig", []), content="valid")
}

///|
test "Engine inject_json does not execute mutable JavaScript hooks" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let injectionHooksTouched = 0;
      #|JSON.parse = function() { injectionHooksTouched += 10; throw new Error("parse"); };
      #|JSON.stringify = function() { injectionHooksTouched += 100; throw new Error("stringify"); };
      #|const injectionProto = Object.create(Object.getPrototypeOf(globalThis));
      #|Object.defineProperty(injectionProto, "hostPayload", {
      #|  set(_) { injectionHooksTouched += 1000; }
      #|});
      #|Object.setPrototypeOf(globalThis, injectionProto);
      #|function injectedHookSnapshot() {
      #|  return { injectionHooksTouched, hostPayload };
      #|}
    ),
  )
  let payload = Json::object({
    "null": Json::null(),
    "bool": Json::boolean(true),
    "string": Json::string("plain"),
    "number": Json::number(4.5),
    "array": Json::array([Json::number(1.0), Json::number(2.0)]),
  })
  assert_true(engine.inject_json("hostPayload", payload) is Ok(_))
  json_inspect(engine.call_json("injectedHookSnapshot", []), content={
    "injectionHooksTouched": 0,
    "hostPayload": {
      "null": null,
      "bool": true,
      "string": "plain",
      "number": 4.5,
      "array": [1, 2],
    },
  })
}

///|
test "Engine inject_json copies values and prevents global replacement" {
  let input = Json::object({
    "nested": Json::object({ "value": Json::number(1.0) }),
  })
  let first = @js_engine.Engine()
  let second = @js_engine.Engine()
  assert_true(first.inject_json("sharedConfig", input) is Ok(_))
  assert_true(second.inject_json("sharedConfig", input) is Ok(_))
  first.eval(
    (
      #|function mutateInjectedConfig() {
      #|  try { sharedConfig = { nested: { value: 100 } }; }
      #|  catch (_) {}
      #|  globalThis.sharedConfig = { nested: { value: 200 } };
      #|  sharedConfig.nested.value = 9;
      #|  return sharedConfig.nested.value;
      #|}
    ),
  )
  second.eval(
    "function readInjectedConfig() { return sharedConfig.nested.value; }",
  )
  json_inspect(first.call_json("mutateInjectedConfig", []), content=9)
  json_inspect(second.call_json("readInjectedConfig", []), content=1)
  inspect(input.stringify(), content="{\"nested\":{\"value\":1}}")
}

///|
test "Engine inject_json rejects a non-extensible global before mutation" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function existingGlobalStillWorks() { return 7; }
      #|Object.preventExtensions(globalThis);
    ),
  )
  let diagnostic = expect_engine_diagnostic(
    engine.inject_json("blockedConfig", Json::number(1.0)),
  )
  assert_engine_diagnostic(
    diagnostic,
    "injection-conflict",
    "inject-json",
    "define",
    None,
    "reusable",
    "none",
    "none",
  )
  json_inspect(engine.call_json("existingGlobalStillWorks", []), content=7)
}

///|
test "Engine inject_json accepts property names that are not identifiers" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.inject_json("feature.flags", Json::string("enabled")) is Ok(_),
  )
  engine.eval(
    "function readFeatureFlags() { return globalThis[\"feature.flags\"]; }",
  )
  json_inspect(engine.call_json("readFeatureFlags", []), content="enabled")
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
    has_location=true,
  )
  assert_source_range(diagnostic, 1, 5, 4, 1, 6, 5)
}

///|
test "Engine detailed eval keeps UTF-16 offsets after astral input" {
  let engine = @js_engine.Engine()
  let diagnostic = expect_engine_diagnostic(
    engine.eval_diagnostic("𝒜;\nlet =", source_id="unicode.js"),
  )
  assert_engine_diagnostic(
    diagnostic,
    "parse-error",
    "eval",
    "parse",
    Some("unicode.js"),
    "reusable",
    "none",
    "none",
    has_location=true,
  )
  assert_source_range(diagnostic, 2, 5, 8, 2, 6, 9)
}

///|
test "Engine detailed eval keeps UTF-16 offsets after astral private names" {
  let engine = @js_engine.Engine()
  let diagnostic = expect_engine_diagnostic(
    engine.eval_diagnostic(
      "class C { #𝒜; }\nlet =",
      source_id="private-unicode.js",
    ),
  )
  assert_source_range(diagnostic, 2, 5, 21, 2, 6, 22)
}

///|
test "Engine detailed eval computes multiline token range ends" {
  let engine = @js_engine.Engine()
  let crlf = expect_engine_diagnostic(
    engine.eval_diagnostic("let `a\r\nb`", source_id="crlf.js"),
  )
  assert_source_range(crlf, 1, 5, 4, 2, 3, 10)
  let line_separator = expect_engine_diagnostic(
    engine.eval_diagnostic("let `a\u2028b`", source_id="line-separator.js"),
  )
  assert_source_range(line_separator, 1, 5, 4, 2, 3, 9)
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
    "none",
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("answer", [])),
    "not-callable",
    "call-json",
    "lookup",
    None,
    "reusable",
    "may-remain",
    "none",
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
test "Engine missing-global diagnostic snapshots an empty queue and remains reusable" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic("function stillUsable() { return 'ok'; }") is Ok(_),
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("absent", [])),
    "missing-global",
    "call-json",
    "lookup",
    None,
    "reusable",
    "none",
    "none",
  )
  json_inspect(engine.call_json("stillUsable", []), content="ok")
}

///|
test "Engine missing-global diagnostic preserves a pending microtask" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|queueMicrotask(() => { events.push("pending"); });
      #|function snapshot() { return events; }
    ),
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("absent", [])),
    "missing-global",
    "call-json",
    "lookup",
    None,
    "reusable",
    "none",
    "present",
  )
  assert_true(engine.has_pending_microtasks())
  json_inspect(engine.call_json("snapshot", []), content=[])
  assert_false(engine.run_microtask_checkpoint())
  json_inspect(engine.call_json("snapshot", []), content=["pending"])
}

///|
test "Engine direct not-callable diagnostic snapshots an empty queue and remains reusable" {
  let engine = @js_engine.Engine()
  engine.eval("let answer = 42; function stillUsable() { return true; }")
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("answer", [])),
    "not-callable",
    "call-json",
    "lookup",
    None,
    "reusable",
    "may-remain",
    "none",
  )
  json_inspect(engine.call_json("stillUsable", []), content=true)
}

///|
test "Engine direct not-callable diagnostic preserves a pending microtask" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let answer = 42;
      #|let events = [];
      #|queueMicrotask(() => { events.push("pending"); });
      #|function snapshot() { return events; }
    ),
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("answer", [])),
    "not-callable",
    "call-json",
    "lookup",
    None,
    "reusable",
    "may-remain",
    "present",
  )
  assert_true(engine.has_pending_microtasks())
  json_inspect(engine.call_json("snapshot", []), content=[])
  assert_false(engine.run_microtask_checkpoint())
  json_inspect(engine.call_json("snapshot", []), content=["pending"])
}

///|
test "Engine accessor not-callable diagnostic preserves the microtask it queues" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|Object.defineProperty(globalThis, "accessorValue", {
      #|  get() {
      #|    events.push("getter");
      #|    queueMicrotask(() => { events.push("accessor microtask"); });
      #|    return 42;
      #|  }
      #|});
      #|function snapshot() { return events; }
    ),
  )
  assert_engine_diagnostic(
    expect_engine_diagnostic(engine.call_json_diagnostic("accessorValue", [])),
    "not-callable",
    "call-json",
    "lookup",
    None,
    "reusable",
    "may-remain",
    "present",
  )
  assert_true(engine.has_pending_microtasks())
  json_inspect(engine.call_json("snapshot", []), content=["getter"])
  assert_false(engine.run_microtask_checkpoint())
  json_inspect(engine.call_json("snapshot", []), content=[
    "getter", "accessor microtask",
  ])
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
test "Engine detailed eval reports the deepest cross-source failure" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic(
      "function failFromLoadedSource() { throw new Error('loaded'); }",
      source_id="loaded.js",
    )
    is Ok(_),
  )
  let diagnostic = expect_engine_diagnostic(
    engine.eval_diagnostic("failFromLoadedSource();", source_id="entry.js"),
  )
  assert_true(diagnostic.source_identity() == Some("loaded.js"))
  engine.eval("var boundLoadedFailure = failFromLoadedSource.bind(null);")
  let bound_diagnostic = expect_engine_diagnostic(
    engine.eval_diagnostic("boundLoadedFailure();", source_id="bound-entry.js"),
  )
  assert_true(bound_diagnostic.source_identity() == Some("loaded.js"))
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
  let parse_diagnostic = expect_engine_diagnostic(
    @js_engine.run_diagnostic("let =", source_id="run.js"),
  )
  assert_engine_diagnostic(
    parse_diagnostic,
    "parse-error",
    "run",
    "parse",
    Some("run.js"),
    "not-applicable",
    "none",
    "unknown",
    has_location=true,
  )
  assert_source_range(parse_diagnostic, 1, 5, 4, 1, 6, 5)
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
