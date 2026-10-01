///|
test "configured hosted depth bypasses guest catch finally and checkpoint" {
  let policy = @runtime.ExecutionPolicy::new(
    100000L,
    16L,
    @runtime.InterruptionHandle(),
  ).unwrap()
  let probe = HostedProbe(policy)
  probe.register("invoke", (call, args) => call.call(args[0], []))
  let marker = probe.evaluate(
    "var marker = { caught: 0, finalized: 0, job: 0 }; marker",
  )
  assert_true(
    probe
    .evaluate(
      "try { throw new RangeError('ordinary'); } catch (e) { e instanceof RangeError; }",
    )
    .expect_bool(),
  )
  let stopped = try {
    let source =
      #|queueMicrotask(() => { marker.job++; });
      #|try { invoke(function f() { return f(); }); }
      #|catch (e) { marker.caught++; }
      #|finally { marker.finalized++; }
    ignore(probe.evaluate(source))
    false
  } catch {
    HostedTerminal(cause) => {
      assert_eq(
        @runtime.execution_control_failure_code(cause),
        Some("stack-depth-limit"),
      )
      true
    }
    error => raise error
  }
  assert_true(stopped)
  assert_eq(probe.state(), "faulted")
  // Public inspection is rejected after terminal. Read only the retained plain
  // data object's own slots; do not execute getters or another guest turn.
  guard marker.value is @runtime.Object(data) else {
    fail("expected retained marker object")
  }
  for name in ["caught", "finalized", "job"] {
    guard data.bag.properties.get(name) is Some(@runtime.Number(value)) else {
      fail("expected numeric marker")
    }
    assert_eq(value, 0.0, msg=name)
  }
}

///|
test "unexpected host failure stops guest catch finally and checkpoint immediately" {
  let probe = host_failure_probe()
  probe.register("explode", (_call, _args) => fail("private host failure"))
  let marker = probe.evaluate(
    "var marker = { caught: 0, finalized: 0, after: 0, job: 0 }; marker",
  )
  let source =
    #|queueMicrotask(() => { marker.job++; });
    #|try { explode(); }
    #|catch (e) { marker.caught++; }
    #|finally { marker.finalized++; }
    #|marker.after++;
  let failed = try {
    ignore(probe.evaluate(source))
    false
  } catch {
    HostedHostFailure(_) => true
    error => raise error
  }
  assert_true(failed)
  assert_eq(probe.state(), "faulted")
  assert_no_host_failure_guest_effects(marker)
}

///|
fn host_failure_probe() -> HostedProbe raise {
  HostedProbe(
    @runtime.ExecutionPolicy::new(100000L, 64L, @runtime.InterruptionHandle()).unwrap(),
  )
}

///|
fn assert_no_host_failure_guest_effects(marker : HostedValue) -> Unit raise {
  guard marker.value is @runtime.Object(data) else {
    fail("expected retained marker object")
  }
  for name in ["caught", "finalized", "after", "job"] {
    guard data.bag.properties.get(name) is Some(@runtime.Number(value)) else {
      fail("expected numeric marker")
    }
    assert_eq(value, 0.0, msg=name)
  }
}

///|
test "foreign host return terminates but handled foreign argument stays available" {
  let donor = host_failure_probe()
  let foreign = donor.number(7)
  let probe = host_failure_probe()
  probe.register("validate", (call, args) => {
    let rejected = try {
      ignore(call.call(args[0], [foreign]))
      false
    } catch {
      HostedForeignValue => true
      error => raise error
    }
    assert_true(rejected)
    args[0]
  })
  assert_eq(
    probe
    .evaluate("var calls = 0; validate(() => { calls++; }); calls")
    .expect_number(),
    0.0,
  )
  assert_eq(probe.state(), "available")
  probe.register("foreignReturn", (_call, _args) => foreign)
  let failed = try {
    ignore(probe.evaluate("foreignReturn()"))
    false
  } catch {
    HostedHostFailure(_) => true
    error => raise error
  }
  assert_true(failed)
  assert_eq(probe.state(), "faulted")
  assert_eq(donor.evaluate("6 * 7").expect_number(), 42.0)
}

///|
test "host catching nested failure cannot resume guest execution or clear terminal" {
  let probe = host_failure_probe()
  let seen : Ref[Error?] = Ref(None)
  let blocked = Ref(false)
  let reentry_blocked = Ref(false)
  probe.register("explode", (_call, _args) => fail("original host failure"))
  probe.register("recover", (call, args) => {
    let _ = call.call(args[0], []) catch {
      error => {
        seen.val = @runtime.hosted_execution_failure_cause(error)
        args[0]
      }
    }
    guard seen.val is Some(primary) else { return args[0] }
    blocked.val = try {
      call.record_effect()
      false
    } catch {
      error =>
        match @runtime.hosted_execution_failure_cause(error) {
          Some(cause) => physical_equal(cause, primary)
          None => false
        }
    }
    reentry_blocked.val = try {
      ignore(call.call(args[1], []))
      false
    } catch {
      error =>
        match @runtime.hosted_execution_failure_cause(error) {
          Some(cause) => physical_equal(cause, primary)
          None => false
        }
    }
    args[0]
  })
  let marker = probe.evaluate(
    "var marker = { caught: 0, finalized: 0, after: 0, job: 0 }; marker",
  )
  let source =
    #|queueMicrotask(() => { marker.job++; });
    #|try { recover(() => explode(), () => { marker.after++; }); }
    #|catch (e) { marker.caught++; }
    #|finally { marker.finalized++; }
    #|marker.after++;
  let failed = try {
    ignore(probe.evaluate(source))
    false
  } catch {
    HostedHostFailure(_) => true
    error => raise error
  }
  assert_true(failed)
  assert_true(seen.val is Some(_))
  assert_true(blocked.val)
  assert_true(reentry_blocked.val)
  assert_eq(probe.effect_count(), 0)
  assert_eq(probe.state(), "faulted")
  assert_no_host_failure_guest_effects(marker)
  let rejected = try {
    ignore(probe.evaluate("42"))
    false
  } catch {
    HostedSessionFaulted => true
    error => raise error
  }
  assert_true(rejected)
}

///|
test "host cleanup failure cannot replace earlier control termination" {
  let probe = host_failure_probe()
  probe.register("cleanup", (call, _args) => {
    let _ = call.terminate(HostedExpectedNumber) catch { _ => () }
    fail("later cleanup failure")
  })
  let stopped = try {
    ignore(probe.evaluate("cleanup()"))
    false
  } catch {
    HostedTerminal(HostedExpectedNumber) => true
    error => raise error
  }
  assert_true(stopped)
  assert_eq(probe.state(), "faulted")
}

///|
test "nested host failure stays primary over later host cleanup failure" {
  let probe = host_failure_probe()
  let original : Error = @errors.InternalError(message="original host defect")
  let caught = Ref(false)
  probe.register("explode", (_call, _args) => raise original)
  probe.register("cleanup", (call, args) => {
    let _ = call.call(args[0], []) catch {
      _ => {
        caught.val = true
        args[0]
      }
    }
    raise @errors.InternalError(message="later cleanup failure")
  })
  let failed = try {
    ignore(probe.evaluate("cleanup(() => explode())"))
    false
  } catch {
    HostedHostFailure(detail) => {
      assert_eq(detail, original.to_string())
      true
    }
    error => raise error
  }
  assert_true(caught.val)
  assert_true(failed)
  assert_eq(probe.state(), "faulted")
}

///|
test "intentional and rethrown guest values retain identity and availability" {
  let probe = host_failure_probe()
  probe.register("throwToken", (call, args) => {
    call.throw_value(args[0])
    args[0]
  })
  probe.register("rethrow", (call, args) => call.call(args[0], []))
  let source =
    #|var token = { secret: 42 };
    #|var direct = false, nested = false;
    #|try { throwToken(token); } catch (e) { direct = e === token; }
    #|try { rethrow(() => { throw token; }); } catch (e) { nested = e === token; }
    #|direct && nested;
  assert_true(probe.evaluate(source).expect_bool())
  assert_eq(probe.state(), "available")
  let token = probe.global("token")
  let same = try {
    ignore(probe.evaluate("rethrow(() => { throw token; })"))
    false
  } catch {
    HostedGuestThrow(thrown) => @runtime.strict_equal(thrown.value, token.value)
    error => raise error
  }
  assert_true(same)
  assert_eq(probe.evaluate("token.secret").expect_number(), 42.0)
}
