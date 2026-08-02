///|
const DIRECT_RECURSION_SOURCE =
  #|function f(n){if(n===0)return 0;return 1+f(n-1);}
  #|f(256);

///|
const FINITE_RECURSION_SOURCE =
  #|function f(n){if(n===0)return 0;return 1+f(n-1);}
  #|globalThis.answer = f(256);

///|
const BOUNDED_GETTER_REENTRY_SOURCE =
  #|let n=256;
  #|let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};
  #|o.x;

///|
const PROTECTED_RECURSION_SOURCE =
  #|function f(n){if(n===0)return 0;return 1+f(n-1);}
  #|try{throw f(256);}catch(e){e;}

///|
fn policy(
  step_budget : Int64,
  stack_depth_limit : Int64,
  interruption : @js_engine.InterruptionHandle,
) -> @js_engine.ExecutionPolicy raise Error {
  match @js_engine.ExecutionPolicy::new(
    step_budget,
    stack_depth_limit,
    interruption,
  ) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
}

///|
fn expect_guardrail(
  result : Result[Unit, @js_engine.EngineDiagnostic],
  kind : String,
  source_id : String,
) -> @js_engine.EngineDiagnostic raise Error {
  match result {
    Ok(_) => fail("expected bounded evaluation to reject")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content=kind)
      inspect(diagnostic.operation_code(), content="eval")
      inspect(diagnostic.phase_code(), content="execute")
      assert_true(diagnostic.source_identity() == Some(source_id))
      assert_true(diagnostic.retained_effects() is @js_engine.RetainedEffects::MayRemain)
      assert_true(diagnostic.engine_integrity() is @js_engine.EngineIntegrity::Unknown)
      diagnostic
    }
  }
}

///|
test "external consumer can call the bounded eval facade" {
  let interruption = @js_engine.InterruptionHandle()
  let policy = policy(256L, 1L, interruption)
  let engine = @js_engine.Engine()
  assert_true(
    engine.eval_bounded("1;", policy, source_id="bounded.js") is Ok(_),
  )
}

///|
test "bounded eval preserves parser source ranges" {
  let engine = @js_engine.Engine()
  let result = engine.eval_bounded(
    "let =",
    policy(256L, 8L, @js_engine.InterruptionHandle()),
    source_id="bounded-parse.js",
  )
  match result {
    Ok(_) => fail("expected bounded parse failure")
    Err(diagnostic) => {
      inspect(diagnostic.failure_kind_code(), content="parse-error")
      inspect(diagnostic.phase_code(), content="parse")
      guard diagnostic.source_location() is Some(location) else {
        fail("expected bounded parser source location")
      }
      let start = location.start()
      json_inspect([start.line(), start.column(), start.offset()], content=[
        1, 5, 4,
      ])
      guard location.end() is Some(end) else {
        fail("expected bounded parser source range end")
      }
      json_inspect([end.line(), end.column(), end.offset()], content=[1, 6, 5])
    }
  }
}

///|
test "bounded eval preserves a finite exact result below the depth limit" {
  let engine = @js_engine.Engine()
  let interruption = @js_engine.InterruptionHandle()
  assert_true(
    engine.eval_bounded(
      FINITE_RECURSION_SOURCE,
      policy(100000L, 257L, interruption),
      source_id="finite.js",
    ) is Ok(_),
  )
  engine.eval("function readAnswer(){return globalThis.answer;}")
  json_inspect(engine.call_json("readAnswer", []), content=256)
}

///|
test "bounded eval reports direct depth exhaustion with source identity" {
  let engine = @js_engine.Engine()
  let diagnostic = expect_guardrail(
    engine.eval_bounded(
      DIRECT_RECURSION_SOURCE,
      policy(100000L, 1L, @js_engine.InterruptionHandle()),
      source_id="direct.js",
    ),
    "stack-depth-limit",
    "direct.js",
  )
  inspect(diagnostic.message(), content="Maximum call stack size exceeded")
}

///|
test "bounded getter rejection leaves the child body unstarted" {
  let engine = @js_engine.Engine()
  let diagnostic = expect_guardrail(
    engine.eval_bounded(
      BOUNDED_GETTER_REENTRY_SOURCE,
      policy(100000L, 1L, @js_engine.InterruptionHandle()),
      source_id="getter.js",
    ),
    "stack-depth-limit",
    "getter.js",
  )
  inspect(diagnostic.message(), content="Maximum call stack size exceeded")
  engine.eval("function readN(){return n;}")
  json_inspect(engine.call_json("readN", []), content=255)
}

///|
test "zero budget rejects before the first guest effect" {
  let engine = @js_engine.Engine()
  engine.eval("let touched=0;function readTouched(){return touched;}")
  let diagnostic = expect_guardrail(
    engine.eval_bounded(
      "touched=1;",
      policy(0L, 10L, @js_engine.InterruptionHandle()),
      source_id="budget.js",
    ),
    "execution-limit",
    "budget.js",
  )
  json_inspect(engine.call_json("readTouched", []), content=0)
  engine.eval("touched=2;")
  json_inspect(engine.call_json("readTouched", []), content=2)
  ignore(diagnostic)
}

///|
test "pre-requested interruption wins over budget and depth" {
  let engine = @js_engine.Engine()
  engine.eval("let touched=0;function readTouched(){return touched;}")
  let interruption = @js_engine.InterruptionHandle()
  interruption.request()
  ignore(
    expect_guardrail(
      engine.eval_bounded(
        "touched=1;",
        policy(0L, 0L, interruption),
        source_id="interrupt.js",
      ),
      "interrupted",
      "interrupt.js",
    ),
  )
  json_inspect(engine.call_json("readTouched", []), content=0)
}

///|
test "bounded rejection preserves pending jobs in its diagnostic" {
  let engine = @js_engine.Engine()
  engine.eval("queueMicrotask(() => {});")
  let diagnostic = expect_guardrail(
    engine.eval_bounded(
      "globalThis.touched=1;",
      policy(0L, 10L, @js_engine.InterruptionHandle()),
      source_id="pending.js",
    ),
    "execution-limit",
    "pending.js",
  )
  assert_true(diagnostic.pending_jobs() is @js_engine.PendingJobs::Present)
}

///|
test "guest lookalike remains a JavaScript exception while caught depth succeeds" {
  let engine = @js_engine.Engine()
  match
    engine.eval_bounded(
      "throw new RangeError(\"Maximum call stack size exceeded\");",
      policy(1000L, 10L, @js_engine.InterruptionHandle()),
      source_id="lookalike.js",
    ) {
    Ok(_) => fail("guest RangeError must remain a JavaScript exception")
    Err(lookalike) => {
      inspect(lookalike.failure_kind_code(), content="javascript-exception")
      assert_true(lookalike.source_identity() == Some("lookalike.js"))
      assert_true(lookalike.message().length() > 0)
    }
  }
  assert_true(
    engine.eval_bounded(
      PROTECTED_RECURSION_SOURCE,
      policy(100000L, 1L, @js_engine.InterruptionHandle()),
      source_id="caught.js",
    ) is Ok(_),
  )
}

///|
test "invalid policy values fail before source execution" {
  let handle = @js_engine.InterruptionHandle()
  match @js_engine.ExecutionPolicy::new(-1L, 1L, handle) {
    Ok(_) => fail("negative step budget must be rejected")
    Err(error) => {
      inspect(error.parameter_code(), content="step-budget")
      assert_true(error.message().length() > 0)
    }
  }
  match @js_engine.ExecutionPolicy::new(2147483648L, 1L, handle) {
    Ok(_) => fail("oversized step budget must be rejected")
    Err(error) => {
      inspect(error.parameter_code(), content="step-budget")
      assert_true(error.message().length() > 0)
    }
  }
  match @js_engine.ExecutionPolicy::new(1L, -1L, handle) {
    Ok(_) => fail("negative stack depth must be rejected")
    Err(error) => {
      inspect(error.parameter_code(), content="stack-depth")
      assert_true(error.message().length() > 0)
    }
  }
  match @js_engine.ExecutionPolicy::new(1L, 2147483648L, handle) {
    Ok(_) => fail("oversized stack depth must be rejected")
    Err(error) => {
      inspect(error.parameter_code(), content="stack-depth")
      assert_true(error.message().length() > 0)
    }
  }
}
