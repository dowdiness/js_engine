///|
fn bounded_call_policy(
  step_budget : Int64,
  stack_depth_limit : Int64,
  interruption : @js_engine.InterruptionHandle,
) -> @js_engine.ExecutionPolicy raise Error {
  match
    @js_engine.ExecutionPolicy::new(
      step_budget, stack_depth_limit, interruption,
    ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded call policy")
  }
}

///|
fn expect_call_guardrail(
  result : Result[Json, @js_engine.EngineDiagnostic],
  kind : String,
  phase : String,
  pending : @js_engine.PendingJobs,
) -> @js_engine.EngineDiagnostic raise Error {
  match result {
    Ok(_) => fail("expected bounded JSON call to reject")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content=kind)
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content=phase)
      assert_true(
        diagnostic.engine_integrity() is @js_engine.EngineIntegrity::Unknown,
      )
      assert_true(
        diagnostic.retained_effects() is @js_engine.RetainedEffects::MayRemain,
      )
      assert_true(
        match (diagnostic.pending_jobs(), pending) {
          (@js_engine.PendingJobs::None, @js_engine.PendingJobs::None) => true
          (@js_engine.PendingJobs::Present, @js_engine.PendingJobs::Present) =>
            true
          (@js_engine.PendingJobs::Unknown, @js_engine.PendingJobs::Unknown) =>
            true
          _ => false
        },
      )
      diagnostic
    }
  }
}

///|
test "external consumer can call the bounded JSON facade" {
  let engine = @js_engine.Engine()
  engine.eval("function add(left, right) { return left + right; }")
  let result = engine.call_json_bounded(
    "add",
    [Json::number(20.0), Json::number(22.0)],
    bounded_call_policy(1000L, 10L, @js_engine.InterruptionHandle()),
  )
  match result {
    Ok(value) => json_inspect(value, content=42)
    Err(diagnostic) => fail(diagnostic.message())
  }
}

///|
test "bounded JSON call resolves an own globalThis getter" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|Object.defineProperty(globalThis, "target", {
      #|  get() { events.push("getter"); return function() {
      #|    events.push("target"); return 42;
      #|  }; }
      #|});
      #|function readEvents() { return events; }
    ),
  )
  match
    engine.call_json_bounded(
      "target",
      [],
      bounded_call_policy(1000L, 10L, @js_engine.InterruptionHandle()),
    ) {
    Ok(value) => json_inspect(value, content=42)
    Err(diagnostic) => fail(diagnostic.message())
  }
  json_inspect(engine.call_json("readEvents", []), content=["getter", "target"])
}

///|
test "zero bounded JSON budget rejects a lookup getter before its first effect" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|Object.defineProperty(globalThis, "target", {
      #|  get() { events.push("getter"); return function() { return 42; }; }
      #|});
      #|function readEvents() { return events; }
    ),
  )
  ignore(
    expect_call_guardrail(
      engine.call_json_bounded(
        "target",
        [],
        bounded_call_policy(0L, 10L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      "lookup",
      @js_engine.PendingJobs::None,
    ),
  )
  json_inspect(engine.call_json("readEvents", []), content=[])
}

///|
test "zero bounded JSON budget rejects the target before its first effect" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|function target() { events.push("target"); return 42; }
      #|function readEvents() { return events; }
    ),
  )
  ignore(
    expect_call_guardrail(
      engine.call_json_bounded(
        "target",
        [],
        bounded_call_policy(0L, 10L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      "execute",
      @js_engine.PendingJobs::None,
    ),
  )
  json_inspect(engine.call_json("readEvents", []), content=[])
}

///|
test "pre-requested interruption wins before a lookup getter" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|Object.defineProperty(globalThis, "target", {
      #|  get() { events.push("getter"); return function() { return 42; }; }
      #|});
      #|function readEvents() { return events; }
    ),
  )
  let interruption = @js_engine.InterruptionHandle()
  interruption.request()
  ignore(
    expect_call_guardrail(
      engine.call_json_bounded(
        "target",
        [],
        bounded_call_policy(0L, 0L, interruption),
      ),
      "interrupted",
      "lookup",
      @js_engine.PendingJobs::None,
    ),
  )
  json_inspect(engine.call_json("readEvents", []), content=[])
}

///|
test "bounded JSON call retains target mutation before later budget failure" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|function target() { events.push("started"); return 42; }
      #|function readEvents() { return events; }
    ),
  )
  ignore(
    expect_call_guardrail(
      engine.call_json_bounded(
        "target",
        [],
        bounded_call_policy(4L, 10L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      "execute",
      @js_engine.PendingJobs::None,
    ),
  )
  json_inspect(engine.call_json("readEvents", []), content=["started"])
}

///|
test "one bounded call budget continues from getter into target" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let events = [];
      #|Object.defineProperty(globalThis, "target", {
      #|  get() { events.push("getter"); return function() {
      #|    events.push("target"); return 42;
      #|  }; }
      #|});
      #|function readEvents() { return events; }
    ),
  )
  ignore(
    expect_call_guardrail(
      engine.call_json_bounded(
        "target",
        [],
        bounded_call_policy(6L, 10L, @js_engine.InterruptionHandle()),
      ),
      "execution-limit",
      "execute",
      @js_engine.PendingJobs::None,
    ),
  )
  json_inspect(engine.call_json("readEvents", []), content=["getter"])
}

///|
fn same_integrity(
  left : @js_engine.EngineIntegrity,
  right : @js_engine.EngineIntegrity,
) -> Bool {
  match (left, right) {
    (@js_engine.EngineIntegrity::Reusable, @js_engine.EngineIntegrity::Reusable) =>
      true
    (@js_engine.EngineIntegrity::Discard, @js_engine.EngineIntegrity::Discard) =>
      true
    (@js_engine.EngineIntegrity::Unknown, @js_engine.EngineIntegrity::Unknown) =>
      true
    (
      @js_engine.EngineIntegrity::NotApplicable,
      @js_engine.EngineIntegrity::NotApplicable,
    ) => true
    _ => false
  }
}

///|
fn same_effects(
  left : @js_engine.RetainedEffects,
  right : @js_engine.RetainedEffects,
) -> Bool {
  match (left, right) {
    (@js_engine.RetainedEffects::None, @js_engine.RetainedEffects::None) => true
    (
      @js_engine.RetainedEffects::MayRemain,
      @js_engine.RetainedEffects::MayRemain,
    ) => true
    (@js_engine.RetainedEffects::Unknown, @js_engine.RetainedEffects::Unknown) =>
      true
    _ => false
  }
}

///|
fn same_pending(
  left : @js_engine.PendingJobs,
  right : @js_engine.PendingJobs,
) -> Bool {
  match (left, right) {
    (@js_engine.PendingJobs::None, @js_engine.PendingJobs::None) => true
    (@js_engine.PendingJobs::Present, @js_engine.PendingJobs::Present) => true
    (@js_engine.PendingJobs::Unknown, @js_engine.PendingJobs::Unknown) => true
    _ => false
  }
}

///|
fn assert_call_diagnostic(
  result : Result[Json, @js_engine.EngineDiagnostic],
  kind : String,
  phase : String,
  integrity : @js_engine.EngineIntegrity,
  effects : @js_engine.RetainedEffects,
  pending : @js_engine.PendingJobs,
  source : String?,
) -> Unit raise Error {
  match result {
    Ok(_) => fail("expected bounded JSON call diagnostic")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content=kind)
      inspect(diagnostic.operation_code(), content="call-json")
      inspect(diagnostic.phase_code(), content=phase)
      assert_true(same_integrity(diagnostic.engine_integrity(), integrity))
      assert_true(same_effects(diagnostic.retained_effects(), effects))
      assert_true(same_pending(diagnostic.pending_jobs(), pending))
      assert_true(diagnostic.source_identity() == source)
    }
  }
}

///|
test "bounded JSON call preserves failure taxonomy and source identity" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic(
      (
        #|let answer = 42;
        #|Object.defineProperty(globalThis, "throwingLookup", {
        #|  get() { throw new Error("lookup failed"); }
        #|});
        #|function throwTarget() { throw new Error("target failed"); }
        #|function identity(value) { return value; }
        #|function undefinedResult() { return undefined; }
      ),
      source_id="loaded.js",
    )
    is Ok(_),
  )
  let reusable = @js_engine.EngineIntegrity::Reusable
  let may_remain = @js_engine.RetainedEffects::MayRemain
  let none = @js_engine.PendingJobs::None
  assert_call_diagnostic(
    engine.call_json_bounded(
      "absent",
      [],
      bounded_call_policy(1000L, 10L, @js_engine.InterruptionHandle()),
    ),
    "missing-global",
    "lookup",
    reusable,
    @js_engine.RetainedEffects::None,
    none,
    None,
  )
  assert_call_diagnostic(
    engine.call_json_bounded(
      "answer",
      [],
      bounded_call_policy(1000L, 10L, @js_engine.InterruptionHandle()),
    ),
    "not-callable",
    "lookup",
    reusable,
    may_remain,
    none,
    None,
  )
  assert_call_diagnostic(
    engine.call_json_bounded(
      "throwingLookup",
      [],
      bounded_call_policy(1000L, 10L, @js_engine.InterruptionHandle()),
    ),
    "javascript-exception",
    "lookup",
    reusable,
    may_remain,
    none,
    Some("loaded.js"),
  )
  assert_call_diagnostic(
    engine.call_json_bounded(
      "identity",
      [Json::number(1.0 / 0.0)],
      bounded_call_policy(1000L, 10L, @js_engine.InterruptionHandle()),
    ),
    "json-conversion-error",
    "argument-conversion",
    reusable,
    may_remain,
    none,
    None,
  )
  assert_call_diagnostic(
    engine.call_json_bounded(
      "throwTarget",
      [],
      bounded_call_policy(1000L, 10L, @js_engine.InterruptionHandle()),
    ),
    "javascript-exception",
    "execute",
    reusable,
    may_remain,
    none,
    Some("loaded.js"),
  )
  assert_call_diagnostic(
    engine.call_json_bounded(
      "undefinedResult",
      [],
      bounded_call_policy(1000L, 10L, @js_engine.InterruptionHandle()),
    ),
    "json-conversion-error",
    "result-conversion",
    reusable,
    may_remain,
    none,
    None,
  )
}

///|
test "bounded JSON call reports stack-depth guardrail parity" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic(
      "function recurse(n) { if (n === 0) return 0; return 1 + recurse(n - 1); }",
      source_id="recurse.js",
    )
    is Ok(_),
  )
  let diagnostic = expect_call_guardrail(
    engine.call_json_bounded(
      "recurse",
      [Json::number(256.0)],
      bounded_call_policy(100000L, 1L, @js_engine.InterruptionHandle()),
    ),
    "stack-depth-limit",
    "execute",
    @js_engine.PendingJobs::None,
  )
  inspect(diagnostic.message(), content="Maximum call stack size exceeded")
  assert_true(diagnostic.source_identity() == Some("recurse.js"))
}

///|
const LEGACY_WRAPPER_RECURSIVE_ISLAND_SOURCE =
  #|let entries = 0;
  #|function recurse(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + recurse(n - 1);
  #|}
  #|function legacyEntry(n) {
  #|  entries = entries + 1;
  #|  return recurse(n);
  #|}
  #|function leaf(n) { return n + 1; }
  #|function legacyLeaf(n) {
  #|  entries = entries + 1;
  #|  return leaf(n);
  #|}
  #|function readEntries() { return entries; }

///|
fn legacy_wrapper_recursive_island_engine() -> @js_engine.Engine raise Error {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic(
      LEGACY_WRAPPER_RECURSIVE_ISLAND_SOURCE,
      source_id="legacy-island.js",
    )
    is Ok(_),
  )
  engine
}

///|
test "legacy wrapper preserves one pre-call effect at child depth guardrail" {
  let engine = legacy_wrapper_recursive_island_engine()
  let diagnostic = expect_call_guardrail(
    engine.call_json_bounded(
      "legacyEntry",
      [Json::number(256.0)],
      bounded_call_policy(100000L, 1L, @js_engine.InterruptionHandle()),
    ),
    "stack-depth-limit",
    "execute",
    @js_engine.PendingJobs::None,
  )
  assert_true(diagnostic.source_identity() == Some("legacy-island.js"))
  json_inspect(engine.call_json("readEntries", []), content=1)
}

///|
test "legacy wrapper observes an admitted leaf activation at depth zero" {
  let engine = legacy_wrapper_recursive_island_engine()
  let diagnostic = expect_call_guardrail(
    engine.call_json_bounded(
      "legacyLeaf",
      [Json::number(1.0)],
      bounded_call_policy(100000L, 0L, @js_engine.InterruptionHandle()),
    ),
    "stack-depth-limit",
    "execute",
    @js_engine.PendingJobs::None,
  )
  assert_true(diagnostic.source_identity() == Some("legacy-island.js"))
  json_inspect(engine.call_json("readEntries", []), content=1)
}

///|
test "legacy wrapper calls admitted recursion at depth 4096 without host recursion" {
  let engine = legacy_wrapper_recursive_island_engine()
  match
    engine.call_json_bounded(
      "legacyEntry",
      [Json::number(4096.0)],
      bounded_call_policy(1000000L, 5000L, @js_engine.InterruptionHandle()),
    ) {
    Ok(value) => json_inspect(value, content=4096)
    Err(diagnostic) => fail(diagnostic.message())
  }
  json_inspect(engine.call_json("readEntries", []), content=1)
}

///|
test "direct JSON conversion remains outside the bounded execution budget" {
  let engine = @js_engine.Engine()
  engine.eval("function identity(value) { return value; }")
  assert_call_diagnostic(
    engine.call_json_bounded(
      "identity",
      [Json::number(1.0 / 0.0)],
      bounded_call_policy(0L, 0L, @js_engine.InterruptionHandle()),
    ),
    "json-conversion-error",
    "argument-conversion",
    @js_engine.EngineIntegrity::Reusable,
    @js_engine.RetainedEffects::MayRemain,
    @js_engine.PendingJobs::None,
    None,
  )
}

///|
test "direct JSON bridge does not invoke mutable global JSON hooks" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|let jsonCalls = 0;
      #|globalThis.JSON = { stringify(value) { jsonCalls += 1; return "hook"; } };
      #|function identity(value) { return value; }
      #|function readJsonCalls() { return jsonCalls; }
    ),
  )
  match
    engine.call_json_bounded(
      "identity",
      [Json::object({ "value": Json::string("direct") })],
      bounded_call_policy(1000L, 10L, @js_engine.InterruptionHandle()),
    ) {
    Ok(value) => json_inspect(value, content={ "value": "direct" })
    Err(diagnostic) => fail(diagnostic.message())
  }
  json_inspect(engine.call_json("readJsonCalls", []), content=0)
}

///|
test "bounded JSON guardrail retains source identity from prior eval diagnostic" {
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_diagnostic(
      "function target() { return 42; }",
      source_id="target.js",
    )
    is Ok(_),
  )
  let diagnostic = expect_call_guardrail(
    engine.call_json_bounded(
      "target",
      [],
      bounded_call_policy(0L, 10L, @js_engine.InterruptionHandle()),
    ),
    "execution-limit",
    "execute",
    @js_engine.PendingJobs::None,
  )
  assert_true(diagnostic.source_identity() == Some("target.js"))
}

///|
test "bounded call guardrail diagnostics snapshot pending jobs after unwind" {
  let engine = @js_engine.Engine()
  engine.eval("queueMicrotask(() => {}); function target() { return 42; }")
  let diagnostic = expect_call_guardrail(
    engine.call_json_bounded(
      "target",
      [],
      bounded_call_policy(0L, 10L, @js_engine.InterruptionHandle()),
    ),
    "execution-limit",
    "execute",
    @js_engine.PendingJobs::Present,
  )
  assert_true(engine.has_pending_microtasks())
  ignore(diagnostic)
}
