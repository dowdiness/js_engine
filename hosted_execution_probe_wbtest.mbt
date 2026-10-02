///|
test "configured hosted depth bypasses guest catch finally and checkpoint" {
  let policy = @runtime.ExecutionPolicy::new(
    100000L,
    16L,
    @runtime.InterruptionHandle(),
  ).unwrap()
  let probe = HostedSession(policy)
  probe.define_function("invoke", (call, args) => call.call(args[0], []))
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
    HostedTerminal(cause, _, _) => {
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
  probe.define_function("explode", (_call, _args) => {
    fail("private host failure")
  })
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
fn host_failure_probe() -> HostedSession raise {
  HostedSession(
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
  probe.define_function("validate", (call, args) => {
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
  probe.define_function("foreignReturn", (_call, _args) => foreign)
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
  probe.define_function("explode", (_call, _args) => {
    fail("original host failure")
  })
  probe.define_function("recover", (call, args) => {
    let _ = call.call(args[0], []) catch {
      HostedHostFailure(cause, _, _) => {
        seen.val = Some(cause)
        args[0]
      }
      error => raise error
    }
    guard seen.val is Some(primary) else { return args[0] }
    blocked.val = try {
      call.record_effect()
      false
    } catch {
      HostedHostFailure(cause, _, _) => physical_equal(cause, primary)
      _ => false
    }
    reentry_blocked.val = try {
      ignore(call.call(args[1], []))
      false
    } catch {
      HostedHostFailure(cause, _, _) => physical_equal(cause, primary)
      _ => false
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
  probe.define_function("cleanup", (call, _args) => {
    let _ = call.terminate(HostedExpectedNumber) catch { _ => () }
    fail("later cleanup failure")
  })
  let stopped = try {
    ignore(probe.evaluate("cleanup()"))
    false
  } catch {
    HostedTerminal(HostedExpectedNumber, diagnostic, secondary) => {
      assert_eq(diagnostic.phase_code(), "body")
      match secondary {
        Some([cleanup]) =>
          assert_eq(cleanup.failure_kind_code(), "host-failure")
        _ => fail("expected the cleanup failure as secondary data")
      }
      true
    }
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
  probe.define_function("explode", (_call, _args) => raise original)
  probe.define_function("cleanup", (call, args) => {
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
    HostedHostFailure(cause, _, secondary) => {
      assert_true(physical_equal(cause, original))
      match secondary {
        Some([cleanup]) =>
          assert_eq(cleanup.failure_kind_code(), "host-failure")
        _ => fail("expected the cleanup failure as secondary data")
      }
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
  probe.define_function("throwToken", (call, args) => {
    call.throw_value(args[0])
    args[0]
  })
  probe.define_function("rethrow", (call, args) => call.call(args[0], []))
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
    HostedGuestThrow(thrown, diagnostic) => {
      assert_eq(diagnostic.phase_code(), "nested")
      @runtime.strict_equal(thrown.value, token.value)
    }
    error => raise error
  }
  assert_true(same)
  assert_eq(probe.evaluate("token.secret").expect_number(), 42.0)
}

///|
test "R3 nested guest provenance survives suspended declarations and dynamic scope" {
  for
    source in [
      "function* declared() { yield 1; } rethrow(() => { throw token; })", "with ({}) { rethrow(() => { throw token; }); }",
    ] {
    let probe = host_failure_probe()
    probe.define_function("rethrow", (call, args) => call.call(args[0], []))
    let token = probe.evaluate("var token = { secret: 42 }; token")
    let same = try {
      ignore(probe.evaluate(source))
      false
    } catch {
      HostedGuestThrow(thrown, diagnostic) => {
        assert_eq(diagnostic.phase_code(), "nested")
        @runtime.strict_equal(thrown.value, token.value)
      }
      error => raise error
    }
    assert_true(same)
    assert_eq(probe.state(), "available")
    assert_eq(probe.evaluate("token.secret").expect_number(), 42.0)
  }
}

///|
fn tagged_hosted_function(
  probe : HostedSession,
  identity : String,
  source : String,
) -> HostedValue raise Error {
  let callee = probe.evaluate(source)
  let realm = probe.session.engine.interp.realm_state
  @runtime.with_source_identity(realm, Some(identity), () => {
    ignore(@runtime.stamp_function_realm(callee.value, realm_state=Some(realm)))
  })
  callee
}

///|
test "R3 guest phases retain trusted function origins through nested and checkpoint execution" {
  for phase in ["body", "nested", "checkpoint", "checkpoint-nested"] {
    let probe = host_failure_probe()
    let token = probe.evaluate("var token = {}; token")
    let origin = "origin-" + phase + ".js"
    let callee = tagged_hosted_function(
      probe, origin, "(function() { throw token; })",
    )
    probe.define_function("invoke", (call, args) => call.call(args[0], []))
    probe.define_function("saved", (_call, _args) => callee)
    let outer = probe.evaluate("(function(fn) { return invoke(fn); })")
    let job = probe.evaluate("(function() { invoke(saved()); })")
    probe.define_function("job", (_call, _args) => job)
    let same = try {
      match phase {
        "body" => ignore(callee.call([]))
        "nested" => ignore(outer.call([callee]))
        "checkpoint" => ignore(probe.evaluate("queueMicrotask(saved())"))
        _ => ignore(probe.evaluate("queueMicrotask(job())"))
      }
      false
    } catch {
      HostedGuestThrow(thrown, diagnostic) => {
        assert_eq(diagnostic.phase_code(), phase)
        assert_eq(diagnostic.source_identity(), Some(origin))
        assert_eq(
          diagnostic.operation_code(),
          if phase == "body" || phase == "nested" {
            "call"
          } else {
            "evaluate"
          },
        )
        @runtime.strict_equal(thrown.value, token.value)
      }
      error => raise error
    }
    assert_true(same)
    assert_eq(probe.state(), "available")
    assert_eq(probe.evaluate("42").expect_number(), 42.0)
  }
}

///|
test "R3 a fresh throw of the same value does not inherit a caught nested origin" {
  let probe = host_failure_probe()
  let token = probe.evaluate("var token = {}; token")
  let saved : Ref[EngineDiagnostic?] = Ref(None)
  probe.define_function("invoke", (call, args) => {
    call.call(args[0], []) catch {
      HostedGuestThrow(_, diagnostic) as error => {
        saved.val = Some(diagnostic)
        raise error
      }
      error => raise error
    }
  })
  let inner = tagged_hosted_function(
    probe, "inner-A.js", "(function() { throw token; })",
  )
  let outer = tagged_hosted_function(
    probe, "outer-B.js", "(function(fn) { try { invoke(fn); } catch (e) {} throw token; })",
  )
  let current : EngineDiagnostic? = try {
    ignore(outer.call([inner]))
    None
  } catch {
    HostedGuestThrow(thrown, diagnostic) => {
      assert_true(@runtime.strict_equal(thrown.value, token.value))
      Some(diagnostic)
    }
    error => raise error
  }
  let current = current.unwrap()
  let retained = saved.val.unwrap()
  assert_eq(current.phase_code(), "body")
  assert_eq(current.source_identity(), Some("outer-B.js"))
  assert_eq(retained.phase_code(), "nested")
  assert_eq(retained.source_identity(), Some("inner-A.js"))
  let later = tagged_hosted_function(
    probe, "later-C.js", "(function() { throw 7; })",
  )
  let caught = try {
    ignore(later.call([]))
    false
  } catch {
    HostedGuestThrow(value, diagnostic) => {
      assert_eq(value.expect_number(), 7.0)
      assert_eq(diagnostic.source_identity(), Some("later-C.js"))
      true
    }
    error => raise error
  }
  assert_true(caught)
  assert_eq(current.source_identity(), Some("outer-B.js"))
  assert_eq(retained.source_identity(), Some("inner-A.js"))
  assert_eq(probe.state(), "available")
}

///|
test "R3 intentional Host throw gains trusted source without replacing its nested phase" {
  let probe = host_failure_probe()
  probe.define_function("throwToken", (call, args) => {
    call.throw_value(args[0])
    args[0]
  })
  let token = probe.evaluate("var token = {}; token")
  let callee = tagged_hosted_function(
    probe, "intentional.js", "(function() { throwToken(token); })",
  )
  let same = try {
    ignore(callee.call([]))
    false
  } catch {
    HostedGuestThrow(thrown, diagnostic) => {
      assert_eq(diagnostic.phase_code(), "nested")
      assert_eq(diagnostic.source_identity(), Some("intentional.js"))
      @runtime.strict_equal(thrown.value, token.value)
    }
    error => raise error
  }
  assert_true(same)
  assert_eq(probe.state(), "available")
}

///|
test "R3 terminal origin and retained nested snapshot survive later cleanup information" {
  let probe = host_failure_probe()
  let primary : Error = HostedExpectedNumber
  let retained : Ref[HostedError?] = Ref(None)
  probe.define_function("stop", (call, args) => {
    call.terminate(primary)
    args[0]
  })
  probe.define_function("cleanup", (call, args) => {
    ignore(call.call(args[0], [])) catch {
      HostedTerminal(_, _, _) as error => retained.val = Some(error)
      error => raise error
    }
    raise @errors.InternalError(message="later Host cleanup")
  })
  let inner = tagged_hosted_function(
    probe, "terminal-inner.js", "(function() { stop(0); })",
  )
  let outer = tagged_hosted_function(
    probe, "cleanup-outer.js", "(function(fn) { cleanup(fn); })",
  )
  let failed = try {
    ignore(outer.call([inner]))
    false
  } catch {
    HostedTerminal(cause, diagnostic, secondary) => {
      assert_true(physical_equal(cause, primary))
      assert_eq(diagnostic.phase_code(), "nested")
      assert_eq(diagnostic.source_identity(), Some("terminal-inner.js"))
      match secondary {
        Some([cleanup]) =>
          assert_eq(cleanup.failure_kind_code(), "host-failure")
        _ => fail("expected later cleanup as safe secondary data")
      }
      true
    }
    error => raise error
  }
  assert_true(failed)
  match retained.val {
    Some(HostedTerminal(cause, diagnostic, None)) => {
      assert_true(physical_equal(cause, primary))
      assert_eq(diagnostic.source_identity(), Some("terminal-inner.js"))
    }
    _ => fail("the retained nested error changed after cleanup")
  }
  assert_eq(probe.state(), "faulted")
}
