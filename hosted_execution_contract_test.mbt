///|
test "R5 self-extending Promise jobs terminate within the outer budget" {
  let probe = HostedSession(hosted_policy(512L, 64L))
  let entered = Ref(0)
  probe.define_function("mark", (_call, args) => {
    entered.val += 1
    args[0]
  })
  let stopped = try {
    ignore(
      probe.evaluate(
        "Promise.resolve().then(function spin() { mark(1); Promise.resolve().then(spin); }); 42",
      ),
    )
    false
  } catch {
    HostedError::HostedTerminal(cause, diagnostic, _) => {
      assert_eq(
        @runtime.execution_control_failure_code(cause),
        Some("execution-limit"),
      )
      assert_eq(diagnostic.phase_code(), "checkpoint")
      true
    }
    error => raise error
  }
  assert_true(stopped)
  assert_true(entered.val > 0 && entered.val < 512)
  let completed = entered.val
  let denied = try {
    ignore(probe.evaluate("mark(99)"))
    false
  } catch {
    HostedError::HostedSessionFaulted => true
    error => raise error
  }
  assert_true(denied)
  assert_eq(entered.val, completed)
  assert_eq(probe.state(), "faulted")
}

///|
test "R5 ordinary Promise rejection does not escape the checkpoint" {
  let probe = HostedSession(hosted_policy(100000L, 64L))
  let events : Array[Double] = []
  probe.define_function("mark", (_call, args) => {
    events.push(args[0].expect_number())
    args[0]
  })
  assert_eq(
    probe
    .evaluate(
      "Promise.resolve().then(() => { throw 7; }); queueMicrotask(() => mark(42)); 9",
    )
    .expect_number(),
    9.0,
  )
  json_inspect(events, content=[42])
  assert_eq(probe.state(), "available")
}

///|
test "R5 exceptional callback authority expires and never revives" {
  for mode in ["guest", "host", "terminal"] {
    let interruption = @runtime.InterruptionHandle()
    let probe = HostedSession(
      @runtime.ExecutionPolicy::new(100000L, 64L, interruption).unwrap(),
    )
    let saved : Ref[HostCallbackContext?] = Ref(None)
    let entered = Ref(0)
    probe.define_function("mark", (_call, args) => {
      entered.val += 1
      args[0]
    })
    let callback = probe.evaluate("(function() { mark(1); return 42; })")
    probe.define_function("captureUnwind", (call, args) => {
      saved.val = Some(call)
      match mode {
        "guest" => call.throw_value(args[0])
        "host" => fail("unmapped authority unwind")
        _ => interruption.request()
      }
      args[0]
    })
    let outcome = try {
      ignore(probe.evaluate("captureUnwind(7)"))
      "normal"
    } catch {
      HostedError::HostedGuestThrow(value, _) => {
        assert_eq(value.expect_number(), 7.0)
        "guest"
      }
      HostedError::HostedHostFailure(_) => "host"
      HostedError::HostedTerminal(cause, _, _) => {
        assert_eq(
          @runtime.execution_control_failure_code(cause),
          Some("interrupted"),
        )
        "terminal"
      }
      error => raise error
    }
    assert_eq(outcome, mode)
    let expired = try {
      ignore(saved.val.unwrap().call(callback, []))
      false
    } catch {
      HostedError::HostedExpiredHostCall => true
      error => raise error
    }
    assert_true(expired)
    assert_eq(entered.val, 0)
    if mode == "guest" {
      probe.define_function("later", (_call, args) => {
        let expired = try {
          ignore(saved.val.unwrap().call(callback, []))
          false
        } catch {
          HostedError::HostedExpiredHostCall => true
          error => raise error
        }
        assert_true(expired)
        args[0]
      })
      assert_eq(probe.evaluate("later(42)").expect_number(), 42.0)
      assert_eq(probe.state(), "available")
      assert_eq(entered.val, 0)
    } else {
      assert_eq(probe.state(), "faulted")
    }
  }
}

///|
test "R5 every public admission rejects Running without guest effects" {
  let probe = HostedSession(hosted_policy(100000L, 64L))
  let entered = Ref(0)
  probe.define_function("mark", (_call, args) => {
    entered.val += 1
    args[0]
  })
  let object = probe.evaluate(
    "({ get x() { mark(1); return 42; }, method() { mark(2); return 42; } })",
  )
  let function = probe.evaluate("(function(n) { mark(3); return n; })")
  let number = probe.number(42)
  let typed = @js_engine.js_number_unary(function)
  let denied = Ref(0)
  probe.define_function("check", (_call, args) => {
    let actions : Array[() -> Unit raise Error] = [
      () => ignore(probe.evaluate("mark(4)")),
      () => ignore(probe.evaluate("var =")),
      () => ignore(probe.global("Math")),
      () => ignore(object.get("x")),
      () => ignore(function.call([number])),
      () => ignore(object.call_property("method", [])),
      () => probe.define_function("unreachable", (_call, args) => args[0]),
      () => ignore(probe.number(1)),
      () => ignore(probe.bool(true)),
      () => ignore(probe.string("x")),
      () => probe.close(),
      () => ignore(typed(1)),
    ]
    for action in actions {
      let busy = try {
        action()
        false
      } catch {
        HostedError::HostedSessionBusy => true
        error => raise error
      }
      assert_true(busy)
      denied.val += 1
    }
    assert_eq(number.expect_number(), 42.0)
    assert_eq(entered.val, 0)
    assert_eq(probe.state(), "running")
    args[0]
  })
  assert_eq(probe.evaluate("check(40) + 2").expect_number(), 42.0)
  assert_eq(denied.val, 12)
  assert_eq(entered.val, 0)
  assert_eq(probe.state(), "available")
  assert_eq(function.call([number]).expect_number(), 42.0)
  assert_eq(entered.val, 1)
}

///|
test "R5 interruption gates admission Host return and reentry" {
  for boundary in ["admission", "return", "reentry", "checkpoint"] {
    let interruption = @runtime.InterruptionHandle()
    let probe = HostedSession(
      @runtime.ExecutionPolicy::new(100000L, 64L, interruption).unwrap(),
    )
    let events : Array[String] = []
    probe.define_function("mark", (_call, args) => {
      events.push(args[0].expect_string())
      args[0]
    })
    let blocked = Ref(false)
    probe.define_function("stop", (call, args) => {
      events.push("host")
      interruption.request()
      if boundary == "reentry" {
        blocked.val = try {
          ignore(call.call(args[0], []))
          false
        } catch {
          HostedError::HostedTerminal(cause, _, _) => {
            assert_eq(
              @runtime.execution_control_failure_code(cause),
              Some("interrupted"),
            )
            true
          }
          error => raise error
        }
      }
      args[0]
    })
    let source = match boundary {
      "admission" => {
        interruption.request()
        "mark('unreachable'); queueMicrotask(() => mark('job'))"
      }
      "checkpoint" =>
        "queueMicrotask(() => stop(1)); queueMicrotask(() => mark('job')); 42"
      "reentry" =>
        "queueMicrotask(() => mark('job')); stop(() => mark('nested')); mark('unreachable')"
      _ => "queueMicrotask(() => mark('job')); stop(1); mark('unreachable')"
    }
    let stopped = try {
      ignore(probe.evaluate(source))
      false
    } catch {
      HostedError::HostedTerminal(cause, _, _) => {
        assert_eq(
          @runtime.execution_control_failure_code(cause),
          Some("interrupted"),
        )
        true
      }
      error => raise error
    }
    assert_true(stopped)
    if boundary == "admission" {
      json_inspect(events, content=[])
    } else {
      json_inspect(events, content=["host"])
    }
    assert_eq(blocked.val, boundary == "reentry")
    assert_eq(probe.state(), "faulted")
  }
}

///|
test "R5 unobserved native progress is a noncatchable terminal" {
  let probe = HostedSession(hosted_policy(100000L, 64L))
  let entered = Ref(0)
  probe.define_function("mark", (_call, args) => {
    entered.val += 1
    args[0]
  })
  let stopped = try {
    ignore(
      probe.evaluate(
        "queueMicrotask(() => mark(1)); try { JSON.parse('{}'); } catch(e) { mark(2); } finally { mark(3); }",
      ),
    )
    false
  } catch {
    HostedError::HostedTerminal(cause, _, _) => {
      assert_eq(
        @runtime.execution_control_failure_code(cause),
        Some("execution-limit"),
      )
      true
    }
    error => raise error
  }
  assert_true(stopped)
  assert_eq(entered.val, 0)
  assert_eq(probe.state(), "faulted")
}

///|
test "R5 HostCall owner rejection precedes getter and callee effects" {
  let donor = HostedSession(hosted_policy(100000L, 64L))
  let donor_effects = Ref(0)
  donor.define_function("donorMark", (_call, args) => {
    donor_effects.val += 1
    args[0]
  })
  let foreign = donor.evaluate(
    "({ get x() { donorMark(1); return 42; }, method() { donorMark(2); return 42; } })",
  )
  let foreign_function = donor.evaluate(
    "(function() { donorMark(3); return 42; })",
  )
  let probe = HostedSession(hosted_policy(100000L, 64L))
  let effects = Ref(0)
  probe.define_function("localMark", (_call, args) => {
    effects.val += 1
    args[0]
  })
  let target = probe.evaluate(
    "({ get method() { localMark(1); return function() { localMark(2); return 42; }; } })",
  )
  let function = probe.evaluate("(function() { localMark(3); return 42; })")
  probe.define_function("checkOwners", (call, args) => {
    let actions : Array[() -> Unit raise Error] = [
      () => ignore(call.get(foreign, "x")),
      () => ignore(call.call(foreign_function, [])),
      () => ignore(call.call(function, [foreign])),
      () => ignore(call.call_property(foreign, "method", [])),
      () => ignore(call.call_property(target, "method", [foreign])),
    ]
    for action in actions {
      let rejected = try {
        action()
        false
      } catch {
        HostedError::HostedForeignValue => true
        error => raise error
      }
      assert_true(rejected)
    }
    assert_eq(effects.val, 0)
    assert_eq(donor_effects.val, 0)
    args[0]
  })
  assert_eq(probe.evaluate("checkOwners(42)").expect_number(), 42.0)
  assert_eq(effects.val, 0)
  assert_eq(donor_effects.val, 0)
  assert_eq(probe.state(), "available")
  assert_eq(donor.state(), "available")
}

///|
test "R5 normal body cannot succeed after checkpoint Host failure" {
  let probe = HostedSession(hosted_policy(100000L, 64L))
  let events : Array[String] = []
  let formatted = Ref(0)
  let original : Error = HostedFormattingProbeError(() => formatted.val += 1)
  probe.define_function("failCheckpoint", (_call, _args) => {
    events.push("failed-job")
    raise original
  })
  probe.define_function("mark", (_call, args) => {
    events.push(args[0].expect_string())
    args[0]
  })
  let failed = try {
    ignore(
      probe.evaluate(
        "mark('body'); queueMicrotask(() => failCheckpoint()); queueMicrotask(() => mark('unselected')); 42",
      ),
    )
    false
  } catch {
    HostedError::HostedHostFailure(cause, diagnostic, secondary) => {
      assert_true(physical_equal(cause, original))
      assert_eq(diagnostic.phase_code(), "checkpoint")
      assert_true(secondary is None)
      true
    }
    error => raise error
  }
  assert_true(failed)
  assert_eq(formatted.val, 0)
  json_inspect(events, content=["body", "failed-job"])
  let denied = try {
    ignore(probe.evaluate("mark('later')"))
    false
  } catch {
    HostedError::HostedSessionFaulted => true
    error => raise error
  }
  assert_true(denied)
  json_inspect(events, content=["body", "failed-job"])
  assert_eq(probe.state(), "faulted")
}

///|
test "R5 public policy validation rejects invalid portable limits" {
  for
    (steps, depth, parameter) in [
      (-1L, 1L, "step-budget"),
      (2147483648L, 1L, "step-budget"),
      (1L, -1L, "stack-depth"),
      (1L, 2147483648L, "stack-depth"),
    ] {
    match
      @runtime.ExecutionPolicy::new(steps, depth, @runtime.InterruptionHandle()) {
      Err(error) => assert_eq(error.parameter_code(), parameter)
      Ok(_) => fail("invalid configuration became an admissible policy")
    }
  }
  for limit in [0L, 2147483647L] {
    match
      @runtime.ExecutionPolicy::new(limit, limit, @runtime.InterruptionHandle()) {
      Ok(_) => ()
      Err(_) => fail("valid portable boundary was rejected")
    }
  }
}
