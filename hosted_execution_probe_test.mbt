///|
using @js_engine {type HostedProbe, type HostedCall, type HostedProbeError}

///|
fn hosted_policy(
  step_budget : Int64,
  stack_depth_limit : Int64,
) -> @runtime.ExecutionPolicy raise {
  let interruption = @runtime.InterruptionHandle()
  match
    @runtime.ExecutionPolicy::new(step_budget, stack_depth_limit, interruption) {
    Ok(policy) => policy
    Err(error) => fail(error.message())
  }
}

///|
test "hosted terminal remains terminal after host catches it" {
  let interruption = @runtime.InterruptionHandle()
  let policy = match @runtime.ExecutionPolicy::new(64L, 32L, interruption) {
    Ok(policy) => policy
    Err(error) => fail(error.message())
  }
  let probe = HostedProbe(policy)
  probe.register("stop", (call, args) => {
    interruption.request()
    let _ = call.record_effect() catch { _ => () }
    args[0]
  })
  let result = try {
    ignore(probe.evaluate("stop(1)"))
    None
  } catch {
    error => Some(error)
  }
  match result {
    Some(HostedProbeError::HostedTerminal(_)) => ()
    Some(_) => fail("expected HostedTerminal")
    None => fail("interruption was swallowed")
  }
  assert_eq(probe.state(), "faulted")
  assert_eq(probe.effect_count(), 0)
}

///|
test "hosted nested JavaScript shares finite execution budget" {
  let probe = HostedProbe(hosted_policy(16L, 64L))
  probe.register("invoke", (call, args) => call.call(args[0], []))
  let result = try {
    ignore(probe.evaluate("invoke(function f() { return f(); })"))
    None
  } catch {
    error => Some(error)
  }
  match result {
    Some(HostedProbeError::HostedTerminal(_)) => ()
    Some(_) => fail("expected nested terminal")
    None => fail("nested recursive execution returned")
  }
  assert_eq(probe.state(), "faulted")
}

///|
test "ancestor host call is rejected before nested getter" {
  let probe = HostedProbe(hosted_policy(256L, 64L))
  let saved : Ref[HostedCall?] = Ref(None)
  probe.register("inner", (_call, args) => {
    match saved.val {
      Some(parent) => parent.get(args[0], "x")
      None => fail("missing ancestor token")
    }
  })
  probe.register("outer", (call, args) => {
    saved.val = Some(call)
    call.call(args[0], [])
  })
  let result = try {
    ignore(
      probe.evaluate(
        "outer(() => inner({ get x() { throw new Error('getter ran') } }))",
      ),
    )
    None
  } catch {
    error => Some(error)
  }
  match result {
    Some(HostedProbeError::HostedHostFailure(_)) => ()
    Some(_) => fail("expected HostFailure")
    None => fail("ancestor token unexpectedly authorized getter")
  }
  assert_eq(probe.effect_count(), 0)
  assert_eq(probe.state(), "faulted")
}

///|
test "body guest throw remains primary over checkpoint guest throw" {
  let probe = HostedProbe(hosted_policy(256L, 64L))
  let result = try {
    ignore(
      probe.evaluate(
        "queueMicrotask(() => { throw { kind: 'job' } }); throw { kind: 'body' }",
      ),
    )
    None
  } catch {
    error => Some(error)
  }
  match result {
    Some(
      HostedProbeError::HostedGuestThrowWithSecondary(
        primary~,
        secondary~,
        primary_diagnostic~,
        secondary_diagnostic~
      )
    ) => {
      assert_eq(primary_diagnostic.phase_code(), "body")
      assert_eq(secondary_diagnostic.phase_code(), "checkpoint")
      assert_eq(primary.get("kind").expect_string(), "body")
      assert_eq(secondary.get("kind").expect_string(), "job")
    }
    Some(_) => fail("expected dual guest throw")
    None => fail("guest throw unexpectedly returned")
  }
  assert_eq(probe.state(), "available")
}

///|
test "host callback authority restores and expires" {
  let probe = HostedProbe(hosted_policy(256L, 64L))
  let saved : Ref[HostedCall?] = Ref(None)
  probe.register("inner", (call, args) => {
    saved.val = Some(call)
    call.record_effect()
    args[0]
  })
  probe.register("outer", (call, args) => {
    let result = call.call(args[0], [])
    call.record_effect()
    result
  })
  let value = probe.evaluate("outer(() => inner(7))")
  assert_eq(value.expect_number(), 7.0)
  assert_eq(probe.effect_count(), 2)
  let expired = try {
    ignore(saved.val.unwrap().get(value, "x"))
    None
  } catch {
    error => Some(error)
  }
  match expired {
    Some(HostedProbeError::HostedExpiredHostCall) => ()
    Some(_) => fail("expected expired callback authority")
    None => fail("callback authority survived callback return")
  }
  probe.register("busy", (_call, args) => {
    let nested = try {
      ignore(probe.global("Math"))
      None
    } catch {
      error => Some(error)
    }
    match nested {
      Some(HostedProbeError::HostedSessionBusy) => args[0]
      Some(_) => fail("expected busy entry rejection")
      None => fail("public entry reentered while callback was running")
    }
  })
  assert_eq(probe.evaluate("busy(9)").expect_number(), 9.0)
}

///|
test "hosted configured depth terminates nested calls independently of steps" {
  let probe = HostedProbe(hosted_policy(100000L, 1L))
  probe.register("invoke", (call, args) => call.call(args[0], []))
  let stopped = try {
    ignore(
      probe.evaluate(
        "invoke(function() { return (function() { return 42; })(); })",
      ),
    )
    false
  } catch {
    HostedProbeError::HostedTerminal(cause, _, _) => {
      assert_eq(
        @runtime.execution_control_failure_code(cause),
        Some("stack-depth-limit"),
      )
      true
    }
    error => raise error
  }
  assert_true(stopped, msg="nested guest calls bypassed configured depth")
  assert_eq(probe.state(), "faulted")
  let rejected = try {
    ignore(probe.evaluate("42"))
    false
  } catch {
    HostedProbeError::HostedSessionFaulted => true
    error => raise error
  }
  assert_true(rejected)
}

///|
fn expect_hosted_depth_failure(action : () -> Unit raise Error) -> Unit raise {
  let stopped = try {
    action()
    false
  } catch {
    HostedProbeError::HostedTerminal(cause, _, _) => {
      assert_eq(
        @runtime.execution_control_failure_code(cause),
        Some("stack-depth-limit"),
      )
      true
    }
    error => raise error
  }
  assert_true(stopped, msg="expected configured depth termination")
}

///|
test "hosted depth retains outer activation across host and releases siblings" {
  // Anonymous candidate bytecode and named tree functions take distinct entries.
  for
    source in [
      "(function() { return invoke(() => 42); })", "(function outer() { return invoke(() => 42); })",
    ] {
    let allowed = HostedProbe(hosted_policy(100000L, 2L))
    allowed.register("invoke", (call, args) => {
      ignore(call.call(args[0], []))
      let result = call.call(args[0], [])
      call.record_effect()
      result
    })
    let outer = allowed.evaluate(source)
    assert_eq(outer.call([]).expect_number(), 42.0)
    assert_eq(outer.call([]).expect_number(), 42.0)
    assert_eq(allowed.effect_count(), 2)
    assert_eq(allowed.state(), "available")
    let limited = HostedProbe(hosted_policy(100000L, 1L))
    limited.register("invoke", (call, args) => call.call(args[0], []))
    let outer = limited.evaluate(source)
    expect_hosted_depth_failure(() => ignore(outer.call([])))
    assert_eq(limited.state(), "faulted")
  }
}

///|
test "hosted guest throw releases depth and restores parent authority" {
  let probe = HostedProbe(hosted_policy(100000L, 2L))
  probe.register("recover", (call, args) => {
    let caught = try {
      ignore(call.call(args[0], []))
      false
    } catch {
      HostedProbeError::HostedGuestThrow(value, diagnostic) => {
        assert_eq(value.expect_number(), 7.0)
        assert_eq(diagnostic.phase_code(), "nested")
        true
      }
      error => raise error
    }
    assert_true(caught)
    call.record_effect()
    call.call(args[1], [])
  })
  let outer = probe.evaluate(
    "(function outer() { return recover(function failer() { throw 7; }, () => 42); })",
  )
  assert_eq(outer.call([]).expect_number(), 42.0)
  assert_eq(probe.effect_count(), 1)
  assert_eq(probe.state(), "available")
}

///|
test "hosted recursion hits configured depth before backend stack exhaustion" {
  for
    source in [
      "invoke(function f() { return f(); })", "invoke(function f() { return invoke(f); })",
    ] {
    let probe = HostedProbe(hosted_policy(100000L, 16L))
    probe.register("invoke", (call, args) => call.call(args[0], []))
    expect_hosted_depth_failure(() => ignore(probe.evaluate(source)))
    assert_eq(probe.state(), "faulted")
  }
}

///|
test "host caught depth termination stays primary and blocks further effects" {
  let probe = HostedProbe(hosted_policy(100000L, 2L))
  probe.register("recover", (call, args) => {
    let caught = try {
      ignore(call.call(args[0], []))
      false
    } catch {
      HostedProbeError::HostedTerminal(cause, _, _) => {
        assert_eq(
          @runtime.execution_control_failure_code(cause),
          Some("stack-depth-limit"),
        )
        true
      }
      error => raise error
    }
    assert_true(caught)
    let blocked = try {
      call.record_effect()
      false
    } catch {
      HostedProbeError::HostedTerminal(cause, _, _) => {
        assert_eq(
          @runtime.execution_control_failure_code(cause),
          Some("stack-depth-limit"),
        )
        true
      }
      error => raise error
    }
    assert_true(blocked)
    args[0]
  })
  let outer = probe.evaluate(
    "(function outer() { return recover(function inner() { return (() => 42)(); }); })",
  )
  expect_hosted_depth_failure(() => ignore(outer.call([])))
  assert_eq(probe.effect_count(), 0)
  assert_eq(probe.state(), "faulted")
}

///|
test "R1 foreign property arguments reject before getters or pending jobs" {
  let donor = HostedProbe(hosted_policy(100000L, 64L))
  for
    source in [
      "7", "true", "'foreign'", "({})", "new Map()", "new Set()", "Promise.resolve(7)",
    ] {
    let foreign = donor.evaluate(source)
    let probe = HostedProbe(hosted_policy(100000L, 64L))
    let events : Array[String] = []
    probe.register("mark", (_call, args) => {
      events.push(args[0].expect_string())
      args[0]
    })
    probe.register("invoke", (call, args) => {
      let rejected = try {
        ignore(call.call_property(args[0], "method", [args[1], foreign]))
        false
      } catch {
        HostedProbeError::HostedForeignValue => true
        error => raise error
      }
      assert_true(rejected, msg=source)
      events.push("rejected")
      assert_eq(probe.state(), "running")
      call.record_effect()
      call.call_property(args[0], "method", [args[1]])
    })
    let script =
      #|queueMicrotask(() => mark('job'));
      #|invoke({
      #|  base: 2,
      #|  get method() {
      #|    mark('getter');
      #|    return function(x) { mark('callee'); return this.base + x; };
      #|  }
      #|}, 40);
    assert_eq(probe.evaluate(script).expect_number(), 42.0)
    json_inspect(events, content=["rejected", "getter", "callee", "job"])
    assert_eq(probe.effect_count(), 1)
    assert_eq(probe.state(), "available")
  }
}

///|
test "R1 foreign property receiver rejects without entering its getter" {
  let donor = HostedProbe(hosted_policy(100000L, 64L))
  let getter_calls = Ref(0)
  donor.register("mark", (_call, args) => {
    getter_calls.val += 1
    args[0]
  })
  let foreign = donor.evaluate(
    "({ get method() { mark(1); return function(x) { return x; }; } })",
  )
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  probe.register("invoke", (call, args) => {
    let rejected = try {
      ignore(call.call_property(foreign, "method", [args[0]]))
      false
    } catch {
      HostedProbeError::HostedForeignValue => true
      error => raise error
    }
    assert_true(rejected)
    call.record_effect()
    args[0]
  })
  assert_eq(probe.evaluate("invoke(42)").expect_number(), 42.0)
  assert_eq(getter_calls.val, 0)
  assert_eq(probe.effect_count(), 1)
  assert_eq(probe.state(), "available")
  assert_eq(donor.state(), "available")
}

///|
test "R1 pure extraction rejects closed and faulted retained primitives" {
  let outcomes : Array[String] = []
  for close in [true, false] {
    let probe = HostedProbe(hosted_policy(100000L, 64L))
    let number = probe.number(42)
    let boolean = probe.bool(true)
    let string = probe.string("retained")
    let jobs = Ref(0)
    probe.register("job", (_call, args) => {
      jobs.val += 1
      args[0]
    })
    if close {
      probe.close()
    } else {
      probe.register("explode", (_call, _args) => fail("host failure"))
      let faulted = try {
        ignore(probe.evaluate("queueMicrotask(() => job(1)); explode();"))
        false
      } catch {
        HostedProbeError::HostedHostFailure(_) => true
        error => raise error
      }
      assert_true(faulted)
    }
    let extractions : Array[() -> Unit raise HostedProbeError] = [
      () => ignore(number.expect_number()),
      () => ignore(boolean.expect_bool()),
      () => ignore(string.expect_string()),
    ]
    for extract in extractions {
      outcomes.push(
        try {
          extract()
          "accepted"
        } catch {
          HostedProbeError::HostedSessionClosed => "closed"
          HostedProbeError::HostedSessionFaulted => "faulted"
          error => raise error
        },
      )
    }
    assert_eq(probe.state(), if close { "closed" } else { "faulted" })
    assert_eq(jobs.val, 0)
  }
  json_inspect(outcomes, content=[
    "closed", "closed", "closed", "faulted", "faulted", "faulted",
  ])
}

///|
test "R1 live pure extraction and conversion rejection preserve pending jobs" {
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  let number = probe.number(42)
  let boolean = probe.bool(true)
  let string = probe.string("retained")
  assert_eq(number.expect_number(), 42.0)
  assert_true(boolean.expect_bool())
  assert_eq(string.expect_string(), "retained")
  let events : Array[String] = []
  probe.register("mark", (_call, args) => {
    events.push(args[0].expect_string())
    args[0]
  })
  probe.register("inspectValues", (_call, args) => {
    assert_eq(probe.state(), "running")
    assert_eq(number.expect_number(), 42.0)
    assert_true(boolean.expect_bool())
    assert_eq(string.expect_string(), "retained")
    let extractions : Array[() -> Unit raise HostedProbeError] = [
      () => ignore(args[0].expect_number()),
      () => ignore(args[0].expect_bool()),
      () => ignore(args[0].expect_string()),
    ]
    let outcomes = extractions.map(extract => {
      try {
        extract()
        "accepted"
      } catch {
        HostedProbeError::HostedExpectedNumber => "number"
        HostedProbeError::HostedExpectedBool => "bool"
        HostedProbeError::HostedExpectedString => "string"
        error => raise error
      }
    })
    json_inspect(outcomes, content=["number", "bool", "string"])
    json_inspect(events, content=[])
    assert_eq(probe.state(), "running")
    number
  })
  let script =
    #|queueMicrotask(() => mark('job'));
    #|inspectValues({
    #|  valueOf() { mark('coercion'); return 42; },
    #|  toString() { mark('coercion'); return 'retained'; }
    #|});
  assert_eq(probe.evaluate(script).expect_number(), 42.0)
  json_inspect(events, content=["job"])
  assert_eq(probe.state(), "available")
}

///|
test "R1 public property call rejects arguments replaced by its getter" {
  let donor = HostedProbe(hosted_policy(100000L, 64L))
  let foreign = donor.evaluate("({ secret: 42 })")
  donor.close()
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  let args = [probe.number(1)]
  let events : Array[String] = []
  probe.register("swap", (_call, inputs) => {
    events.push("getter")
    args[0] = foreign
    inputs[0]
  })
  probe.register("mark", (_call, inputs) => {
    events.push("callee")
    inputs[0]
  })
  let target = probe.evaluate(
    "({ get method() { swap(0); return function(x) { mark(0); return x.secret; }; } })",
  )
  let rejected = try {
    ignore(target.call_property("method", args))
    false
  } catch {
    HostedProbeError::HostedForeignValue => true
    error => raise error
  }
  assert_true(
    rejected,
    msg="getter passed a closed foreign value to the callee",
  )
  json_inspect(events, content=["getter"])
  assert_eq(probe.state(), "available")
  assert_eq(probe.evaluate("42").expect_number(), 42.0)
}

///|
test "hosted evaluate counts function depth without counting script roots" {
  for source in ["(function f() { return 42; })()", "(() => 42)()"] {
    let probe = HostedProbe(hosted_policy(100000L, 1L))
    assert_eq(probe.evaluate(source).expect_number(), 42.0)
    assert_eq(probe.state(), "available")
    let limited = HostedProbe(hosted_policy(100000L, 0L))
    expect_hosted_depth_failure(() => ignore(limited.evaluate(source)))
    assert_eq(limited.state(), "faulted")
  }
  let root_only = HostedProbe(hosted_policy(100000L, 0L))
  let function = root_only.evaluate("(function f() { return 42; })")
  assert_eq(root_only.state(), "available")
  expect_hosted_depth_failure(() => ignore(function.call([])))
  assert_eq(root_only.state(), "faulted")
}

///|
test "hosted synchronous generators consume depth on call and resume" {
  for
    source in ["(function*(){ yield 1 })()", "(function*(x = 1){ yield x })()"] {
    let limited = HostedProbe(hosted_policy(100000L, 0L))
    expect_hosted_depth_failure(() => ignore(limited.evaluate(source)))
    assert_eq(limited.state(), "faulted")
  }
  let limited = HostedProbe(hosted_policy(100000L, 1L))
  ignore(limited.evaluate("var g = (function*(){ yield 42 })();"))
  expect_hosted_depth_failure(() => {
    ignore(limited.evaluate("(function outer(){ return g.next(); })()"))
  })
  assert_eq(limited.state(), "faulted")
}

///|
test "hosted synchronous generator depth releases on yield and guest unwind" {
  let probe = HostedProbe(hosted_policy(100000L, 1L))
  assert_eq(
    probe
    .evaluate(
      "var g = (function*(){ yield 1; yield 42; })(); g.next(); g.next().value",
    )
    .expect_number(),
    42.0,
  )
  assert_eq(
    probe
    .evaluate(
      "var h = (function*(){ yield 1; throw 7; })(); h.next(); try { h.next(); } catch(e) {} (function*(){ return 42; })().next().value",
    )
    .expect_number(),
    42.0,
  )
  assert_eq(probe.state(), "available")
  for depth in [1L, 2L] {
    let delegated = HostedProbe(hosted_policy(100000L, depth))
    // Precreate both instances: only delegated body resumption can exceed depth.
    ignore(
      delegated.evaluate(
        "var inner = (function*(){ yield 1; yield 42; })(); var outer = (function*(){ yield* inner; })();",
      ),
    )
    if depth == 1L {
      expect_hosted_depth_failure(() => {
        ignore(delegated.evaluate("outer.next()"))
      })
      assert_eq(delegated.state(), "faulted")
    } else {
      assert_eq(delegated.evaluate("outer.next().value").expect_number(), 1.0)
      assert_eq(delegated.evaluate("outer.next().value").expect_number(), 42.0)
      assert_eq(delegated.state(), "available")
    }
  }
}

///|
test "R2 public guest operations checkpoint normal and guest throw outcomes" {
  for entry in ["get", "call", "property"] {
    for throws in [false, true] {
      let probe = HostedProbe(hosted_policy(100000L, 64L))
      let events : Array[String] = []
      probe.register("mark", (call, args) => {
        assert_eq(probe.state(), "running")
        call.record_effect()
        events.push(args[0].expect_string())
        args[0]
      })
      let finish = if throws {
        "throw 7;"
      } else if entry == "property" {
        "return this.base;"
      } else {
        "return 42;"
      }
      let body = "mark('body'); queueMicrotask(() => { mark('job-1'); queueMicrotask(() => mark('job-3')); }); queueMicrotask(() => mark('job-2')); " +
        finish
      let source = match entry {
        "get" => "({ get x() { " + body + " } })"
        "call" => "(function() { " + body + " })"
        _ => "({ base: 42, method() { " + body + " } })"
      }
      let target = probe.evaluate(source)
      let outcome = try {
        let result = match entry {
          "get" => target.get("x")
          "call" => target.call([])
          _ => target.call_property("method", [])
        }
        assert_eq(result.expect_number(), 42.0)
        "normal"
      } catch {
        HostedProbeError::HostedGuestThrow(value, diagnostic) => {
          assert_eq(diagnostic.phase_code(), "body")
          assert_eq(value.expect_number(), 7.0)
          "guest"
        }
        error => raise error
      }
      assert_eq(outcome, if throws { "guest" } else { "normal" })
      json_inspect(events, content=["body", "job-1", "job-2", "job-3"])
      assert_eq(probe.effect_count(), 4)
      assert_eq(probe.state(), "available")
    }
  }
}

///|
test "R2 public completion preserves throws and retains unselected jobs" {
  for entry in ["get", "call", "property"] {
    for body_throws in [false, true] {
      let probe = HostedProbe(hosted_policy(100000L, 64L))
      let events : Array[String] = []
      probe.register("mark", (_call, args) => {
        events.push(args[0].expect_string())
        args[0]
      })
      let finish = if body_throws { "throw 7;" } else { "return 1;" }
      let body = "mark('body'); queueMicrotask(() => { mark('failing'); throw 42; }); queueMicrotask(() => mark('retained')); " +
        finish
      let source = match entry {
        "get" => "({ get x() { " + body + " } })"
        "call" => "(function() { " + body + " })"
        _ => "({ method() { " + body + " } })"
      }
      let target = probe.evaluate(source)
      let outcome = try {
        ignore(
          match entry {
            "get" => target.get("x")
            "call" => target.call([])
            _ => target.call_property("method", [])
          },
        )
        "accepted"
      } catch {
        HostedProbeError::HostedGuestThrow(value, diagnostic) => {
          assert_eq(diagnostic.phase_code(), "checkpoint")
          assert_eq(value.expect_number(), 42.0)
          "checkpoint"
        }
        HostedProbeError::HostedGuestThrowWithSecondary(
          primary~,
          secondary~,
          primary_diagnostic~,
          secondary_diagnostic~
        ) => {
          assert_eq(primary_diagnostic.phase_code(), "body")
          assert_eq(secondary_diagnostic.phase_code(), "checkpoint")
          assert_eq(primary.expect_number(), 7.0)
          assert_eq(secondary.expect_number(), 42.0)
          "both"
        }
        error => raise error
      }
      assert_eq(outcome, if body_throws { "both" } else { "checkpoint" })
      json_inspect(events, content=["body", "failing"])
      assert_eq(probe.state(), "available")
      assert_eq(probe.evaluate("1").expect_number(), 1.0)
      json_inspect(events, content=["body", "failing", "retained"])
    }
  }
}

///|
test "R2 nested returns never recursively checkpoint including checkpoint Host calls" {
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  let events : Array[String] = []
  probe.register("mark", (_call, args) => {
    events.push(args[0].expect_string())
    args[0]
  })
  probe.register("invoke", (call, args) => {
    let value = call.call(args[0], [])
    json_inspect(events, content=["nested"])
    events.push("host-return")
    value
  })
  probe.register("checkpointInvoke", (call, args) => {
    let value = call.call(args[0], [])
    json_inspect(events, content=[
      "nested", "host-return", "outer", "job", "checkpoint-nested",
    ])
    call.record_effect()
    events.push("checkpoint-return")
    value
  })
  let outer = probe.evaluate(
    "(function(callback) { invoke(callback); mark('outer'); return 42; })",
  )
  let callback = probe.evaluate(
    "(function() { mark('nested'); queueMicrotask(() => { mark('job'); checkpointInvoke(() => { mark('checkpoint-nested'); queueMicrotask(() => mark('new-job')); }); }); return 7; })",
  )
  assert_eq(outer.call([callback]).expect_number(), 42.0)
  json_inspect(events, content=[
    "nested", "host-return", "outer", "job", "checkpoint-nested", "checkpoint-return",
    "new-job",
  ])
  assert_eq(probe.effect_count(), 1)
  assert_eq(probe.state(), "available")
}

///|
test "R2 retained jobs wait through pure inspection parse failure and rejection" {
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  let events : Array[String] = []
  probe.register("mark", (_call, args) => {
    events.push(args[0].expect_string())
    args[0]
  })
  let target = probe.evaluate(
    "({ get x() { mark('getter'); return 42; }, method(x) { mark('callee'); return x; } })",
  )
  let value = probe.number(7)
  let queued_failure = try {
    ignore(
      probe.evaluate(
        "queueMicrotask(() => { throw 1; }); queueMicrotask(() => mark('retained'));",
      ),
    )
    false
  } catch {
    HostedProbeError::HostedGuestThrow(thrown, _) => {
      assert_eq(thrown.expect_number(), 1.0)
      true
    }
    error => raise error
  }
  assert_true(queued_failure)
  assert_eq(value.expect_number(), 7.0)
  ignore(probe.global("Math"))
  let parse_failed = try {
    ignore(probe.evaluate("var ="))
    false
  } catch {
    HostedProbeError::HostedParse(_) => true
    error => raise error
  }
  assert_true(parse_failed)
  let donor = HostedProbe(hosted_policy(100000L, 64L))
  let foreign = donor.number(1)
  let rejected = try {
    ignore(target.call_property("method", [foreign]))
    false
  } catch {
    HostedProbeError::HostedForeignValue => true
    error => raise error
  }
  assert_true(rejected)
  json_inspect(events, content=[])
  assert_eq(probe.state(), "available")
  assert_eq(target.get("x").expect_number(), 42.0)
  json_inspect(events, content=["getter", "retained"])
}

///|
test "R2 terminal body skips checkpoint and terminal checkpoint overrides guest throw" {
  for phase in ["body", "checkpoint"] {
    for body_throws in [false, true] {
      let interruption = @runtime.InterruptionHandle()
      let policy = @runtime.ExecutionPolicy::new(100000L, 64L, interruption).unwrap()
      let probe = HostedProbe(policy)
      let events : Array[String] = []
      probe.register("mark", (_call, args) => {
        events.push(args[0].expect_string())
        args[0]
      })
      probe.register("stop", (_call, args) => {
        interruption.request()
        args[0]
      })
      let finish = if body_throws { "throw 7;" } else { "return 42;" }
      let body = if phase == "body" {
        "mark('body'); queueMicrotask(() => mark('queued')); stop(1); mark('unreachable'); " +
        finish
      } else {
        "mark('body'); queueMicrotask(() => { mark('checkpoint'); stop(1); mark('unreachable'); }); queueMicrotask(() => mark('queued')); " +
        finish
      }
      let target = probe.evaluate("(function() { " + body + " })")
      let terminated = try {
        ignore(target.call([]))
        false
      } catch {
        HostedProbeError::HostedTerminal(cause, _, _) => {
          assert_eq(
            @runtime.execution_control_failure_code(cause),
            Some("interrupted"),
          )
          true
        }
        error => raise error
      }
      assert_true(terminated)
      if phase == "body" {
        json_inspect(events, content=["body"])
      } else {
        json_inspect(events, content=["body", "checkpoint"])
      }
      assert_eq(probe.state(), "faulted")
    }
  }
}

///|
test "R3 Busy close uses the facade category without cancelling the active turn" {
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  let busy = Ref(false)
  probe.register("closeBusy", (_call, args) => {
    busy.val = try {
      probe.close()
      false
    } catch {
      HostedProbeError::HostedSessionBusy => true
      _ => false
    }
    assert_eq(probe.state(), "running")
    args[0]
  })
  assert_eq(probe.evaluate("closeBusy(40) + 2").expect_number(), 42.0)
  assert_true(busy.val, msg="Session Busy escaped the Hosted facade category")
  assert_eq(probe.state(), "available")
  probe.close()
  let closed = try {
    probe.close()
    false
  } catch {
    HostedProbeError::HostedSessionClosed => true
    _ => false
  }
  assert_true(closed)
  assert_eq(probe.state(), "closed")
}

///|
test "R3 parse diagnostics retain source positions independently of later failures" {
  let probe = HostedProbe(hosted_policy(0L, 0L))
  let first = try {
    ignore(probe.evaluate("\nvar ="))
    fail("expected parse failure")
  } catch {
    HostedProbeError::HostedParse(diagnostic) => diagnostic
    error => raise error
  }
  assert_eq(first.failure_kind_code(), "parse-error")
  assert_eq(first.operation_code(), "evaluate")
  assert_eq(first.phase_code(), "parse")
  assert_true(first.engine_integrity() is @js_engine.EngineIntegrity::Reusable)
  assert_true(first.retained_effects() is @js_engine.RetainedEffects::None)
  guard first.source_location() is Some(location) else {
    fail("expected parser source location")
  }
  assert_eq(location.start().line(), 2)
  assert_eq(location.start().column(), 5)
  assert_eq(location.start().offset(), 5)
  let second = try {
    ignore(probe.evaluate("\n\nvar ="))
    fail("expected second parse failure")
  } catch {
    HostedProbeError::HostedParse(diagnostic) => diagnostic
    error => raise error
  }
  guard second.source_location() is Some(later) else {
    fail("expected second parser source location")
  }
  assert_eq(later.start().line(), 3)
  assert_eq(later.start().offset(), 6)
  assert_eq(location.start().line(), 2)
  assert_eq(location.start().offset(), 5)
  assert_eq(probe.state(), "available")
}

///|
priv suberror HostedFormattingProbeError {
  HostedFormattingProbeError(() -> Unit)
}

///|
impl Show for HostedFormattingProbeError with fn output(self, logger) {
  let HostedFormattingProbeError(render) = self
  render()
  logger.write_string("Host diagnostic formatting probe")
}

///|
test "R3 Host diagnostic capture never invokes a formatter that executes guest getters" {
  let donor = HostedProbe(hosted_policy(100000L, 64L))
  let getters = Ref(0)
  donor.register("getterRan", (_call, args) => {
    getters.val += 1
    args[0]
  })
  let object = donor.evaluate(
    "({ get x() { getterRan(1); return 'rendered'; } })",
  )
  let formatted = Ref(0)
  let original : Error = HostedFormattingProbeError(() => {
    formatted.val += 1
    ignore(object.get("x")) catch {
      _ => ()
    }
  })
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  probe.register("explode", (_call, _args) => raise original)
  let failed = try {
    ignore(probe.evaluate("explode()"))
    false
  } catch {
    HostedProbeError::HostedHostFailure(cause, diagnostic, _) => {
      assert_true(physical_equal(cause, original))
      assert_true(
        diagnostic.engine_integrity() is @js_engine.EngineIntegrity::Discard,
      )
      true
    }
    error => raise error
  }
  assert_true(failed)
  assert_eq(formatted.val, 0)
  assert_eq(getters.val, 0)
  assert_eq(probe.state(), "faulted")
  assert_eq(donor.state(), "available")
}

///|
test "R3 guest diagnostic capture does not read thrown Proxy properties" {
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  let thrown = try {
    ignore(
      probe.evaluate(
        "var reads = 0; var token = new Proxy({}, { get: function() { reads++; throw 99; } }); throw token",
      ),
    )
    None
  } catch {
    HostedProbeError::HostedGuestThrow(value, diagnostic) => {
      assert_eq(diagnostic.phase_code(), "body")
      assert_eq(diagnostic.failure_kind_code(), "javascript-exception")
      Some(value)
    }
    error => raise error
  }
  let token = thrown.unwrap()
  probe.register("throwSame", (call, _args) => {
    call.throw_value(token)
    token
  })
  assert_true(
    probe
    .evaluate(
      "var same = false; try { throwSame(); } catch (e) { same = e === token; } same",
    )
    .expect_bool(),
  )
  assert_eq(probe.evaluate("reads").expect_number(), 0.0)
  assert_eq(probe.state(), "available")
}

///|
test "R3 checkpoint Host failure retains earlier guest failure as safe secondary data" {
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  let formatted = Ref(0)
  let original : Error = HostedFormattingProbeError(() => formatted.val += 1)
  probe.register("failHost", (_call, _args) => raise original)
  let failed = try {
    ignore(
      probe.evaluate(
        "queueMicrotask(() => failHost()); throw { get toString() { throw 99; } }",
      ),
    )
    false
  } catch {
    HostedProbeError::HostedHostFailure(cause, diagnostic, secondary) => {
      assert_true(physical_equal(cause, original))
      assert_eq(diagnostic.phase_code(), "checkpoint")
      assert_eq(diagnostic.operation_code(), "evaluate")
      match secondary {
        Some([prior]) => {
          assert_eq(prior.failure_kind_code(), "javascript-exception")
          assert_eq(prior.phase_code(), "body")
          assert_eq(prior.operation_code(), "evaluate")
        }
        _ =>
          fail("expected only the earlier guest failure as safe secondary data")
      }
      true
    }
    error => raise error
  }
  assert_true(failed)
  assert_eq(formatted.val, 0)
  assert_eq(probe.state(), "faulted")
}

///|
test "R3 checkpoint control termination retains an earlier guest diagnostic" {
  let probe = HostedProbe(hosted_policy(32L, 64L))
  let failed = try {
    ignore(
      probe.evaluate(
        "queueMicrotask(() => { while (true) {} }); throw { get toString() { throw 99; } }",
      ),
    )
    false
  } catch {
    HostedProbeError::HostedTerminal(cause, diagnostic, secondary) => {
      assert_eq(
        @runtime.execution_control_failure_code(cause),
        Some("execution-limit"),
      )
      assert_eq(diagnostic.phase_code(), "checkpoint")
      match secondary {
        Some([prior]) => {
          assert_eq(prior.failure_kind_code(), "javascript-exception")
          assert_eq(prior.phase_code(), "body")
        }
        _ =>
          fail(
            "expected the earlier guest diagnostic after control termination",
          )
      }
      true
    }
    error => raise error
  }
  assert_true(failed)
  assert_eq(probe.state(), "faulted")
}

///|
test "R3 Faulted cleanup closes without reopening admission or dispatching jobs" {
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  let retained = probe.number(7)
  let jobs = Ref(0)
  probe.register("mark", (_call, args) => {
    jobs.val += 1
    args[0]
  })
  probe.register("explode", (_call, _args) => fail("unexpected Host failure"))
  let faulted = try {
    ignore(probe.evaluate("queueMicrotask(() => mark(1)); explode()"))
    false
  } catch {
    HostedProbeError::HostedHostFailure(_) => true
    error => raise error
  }
  assert_true(faulted)
  assert_eq(probe.state(), "faulted")
  let denied = try {
    ignore(probe.evaluate("42"))
    false
  } catch {
    HostedProbeError::HostedSessionFaulted => true
    error => raise error
  }
  assert_true(denied)
  probe.close()
  assert_eq(probe.state(), "closed")
  let closed = try {
    ignore(probe.evaluate("42"))
    false
  } catch {
    HostedProbeError::HostedSessionClosed => true
    error => raise error
  }
  let expired = try {
    ignore(retained.expect_number())
    false
  } catch {
    HostedProbeError::HostedSessionClosed => true
    error => raise error
  }
  assert_true(closed)
  assert_true(expired)
  assert_eq(jobs.val, 0)
}

///|
test "R3 malformed source cannot bypass unavailable admission" {
  let probe = HostedProbe(hosted_policy(100000L, 64L))
  let jobs = Ref(0)
  probe.register("mark", (_call, args) => {
    jobs.val += 1
    args[0]
  })
  probe.register("rejectMalformed", (_call, args) => {
    let busy = try {
      ignore(probe.evaluate("var ="))
      false
    } catch {
      HostedProbeError::HostedSessionBusy => true
      error => raise error
    }
    assert_true(busy)
    assert_eq(probe.state(), "running")
    assert_eq(jobs.val, 0)
    args[0]
  })
  assert_eq(
    probe
    .evaluate("queueMicrotask(() => mark(1)); rejectMalformed(7)")
    .expect_number(),
    7.0,
  )
  assert_eq(jobs.val, 1)
  assert_eq(probe.state(), "available")
  probe.close()
  let closed = try {
    ignore(probe.evaluate("var ="))
    false
  } catch {
    HostedProbeError::HostedSessionClosed => true
    error => raise error
  }
  assert_true(closed)
  assert_eq(probe.state(), "closed")
  let faulted = HostedProbe(hosted_policy(100000L, 64L))
  faulted.register("explode", (_call, _args) => fail("unmapped Host failure"))
  let host_failure = try {
    ignore(faulted.evaluate("explode()"))
    false
  } catch {
    HostedProbeError::HostedHostFailure(_) => true
    error => raise error
  }
  assert_true(host_failure)
  let denied = try {
    ignore(faulted.evaluate("var ="))
    false
  } catch {
    HostedProbeError::HostedSessionFaulted => true
    error => raise error
  }
  assert_true(denied)
  assert_eq(faulted.state(), "faulted")
}
