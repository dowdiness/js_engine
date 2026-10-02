///|
using @js_engine {
  type HostedSession,
  type HostCallbackContext,
  type HostedError,
  type HostedValue,
  host_number_unary,
  host_number_binary,
  js_number_unary,
}

///|
fn research_hosted_probe() -> HostedSession raise {
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 64L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(error) => fail(error.message())
  }
  HostedSession(policy)
}

///|
test "R4 numeric Host adapters reject before user code with catchable TypeError and no coercion" {
  let probe = research_hosted_probe()
  let entered = Ref(0)
  probe.define_function(
    "double",
    host_number_unary((n : Double) => {
      entered.val += 1
      n * 2
    }),
  )
  probe.define_function(
    "sum",
    host_number_binary((a : Double, b : Double) => {
      entered.val += 1
      a + b
    }),
  )
  let source =
    #|var coercions = 0, caught = 0;
    #|var object = { get valueOf() { coercions++; return () => 21; }, get toString() { coercions++; return () => '21'; } };
    #|var proxy = new Proxy({}, { get() { coercions++; return () => 21; } });
    #|var valid = [double(21), sum(20, 22), double(21, 99)];
    #|var rejected = [() => double(), () => double(undefined), () => double('21'), () => double(object), () => double(proxy), () => sum(), () => sum(20), () => sum('20', 22), () => sum(20, object)];
    #|for (var invoke of rejected) { try { invoke(); } catch (e) { if (!(e instanceof TypeError)) throw e; caught++; } }
  ignore(probe.evaluate(source))
  assert_eq(entered.val, 3)
  assert_eq(probe.global("valid").get("0").expect_number(), 42.0)
  assert_eq(probe.global("valid").get("1").expect_number(), 42.0)
  assert_eq(probe.global("valid").get("2").expect_number(), 42.0)
  assert_eq(probe.global("caught").expect_number(), 9.0)
  assert_eq(probe.global("coercions").expect_number(), 0.0)
  assert_eq(probe.state(), "available")
}

///|
test "R4 uncaught typed mismatch retains a real TypeError and leaves Available" {
  let probe = research_hosted_probe()
  let entered = Ref(0)
  probe.define_function(
    "double",
    host_number_unary((n : Double) => {
      entered.val += 1
      n * 2
    }),
  )
  let thrown : HostedValue? = try {
    ignore(probe.evaluate("double('21')"))
    None
  } catch {
    HostedError::HostedGuestThrow(value, _) => Some(value)
    error => raise error
  }
  let value = match thrown {
    Some(value) => value
    None => fail("expected guest TypeError")
  }
  assert_eq(value.get("name").expect_string(), "TypeError")
  let is_type_error = probe.evaluate("(e) => e instanceof TypeError")
  assert_true(is_type_error.call([value]).expect_bool())
  assert_eq(entered.val, 0)
  assert_eq(probe.state(), "available")
}

///|
test "R4 user function errors remain original noncatchable Host Failures" {
  let probe = research_hosted_probe()
  let original : Error = @errors.TypeError(
    message="application error, not adapter mismatch",
  )
  let guest_cleanup = Ref(0)
  probe.define_function(
    "explode",
    host_number_unary((n : Double) => {
      if n == 1 {
        raise original
      }
      n
    }),
  )
  probe.define_function("mark", (_call, args) => {
    guest_cleanup.val += 1
    args[0]
  })
  let faulted = try {
    ignore(
      probe.evaluate(
        "try { explode(1); } catch (e) { mark(1); } finally { mark(2); }",
      ),
    )
    false
  } catch {
    HostedError::HostedHostFailure(cause, _, _) => {
      assert_true(physical_equal(cause, original))
      true
    }
    error => raise error
  }
  assert_true(faulted)
  assert_eq(guest_cleanup.val, 0)
  assert_eq(probe.state(), "faulted")
}

///|
test "R4 retained numeric closure preserves identity and rejects implicit Running reentry" {
  let probe = research_hosted_probe()
  let entered = Ref(0)
  probe.define_function("touch", (_call, args) => {
    entered.val += 1
    args[0]
  })
  ignore(probe.evaluate("function saved(n) { touch(0); return n + 1; }"))
  let saved : (Double) -> Double raise HostedError = js_number_unary(
    probe.global("saved"),
  )
  assert_eq(saved(41), 42.0)
  ignore(probe.evaluate("saved = function(n) { return n + 1000; };"))
  probe.define_function("busySaved", (_call, args) => {
    let busy = try {
      ignore(saved(41))
      false
    } catch {
      HostedError::HostedSessionBusy => true
      error => raise error
    }
    assert_true(busy)
    assert_eq(entered.val, 1)
    args[0]
  })
  assert_eq(probe.evaluate("busySaved(7)").expect_number(), 7.0)
  assert_eq(probe.state(), "available")
  assert_eq(saved(40), 41.0)
  assert_eq(entered.val, 2)
}

///|
test "R4 retained numeric result mismatch does not coerce or fault" {
  let probe = research_hosted_probe()
  let source =
    #|var coercions = 0;
    #|function saved(n) { return { get valueOf() { coercions++; return () => n; }, get toString() { coercions++; return () => '' + n; } }; }
  ignore(probe.evaluate(source))
  let saved : (Double) -> Double raise HostedError = js_number_unary(
    probe.global("saved"),
  )
  let rejected = try {
    ignore(saved(21))
    false
  } catch {
    HostedError::HostedExpectedNumber => true
    error => raise error
  }
  assert_true(rejected)
  assert_eq(probe.global("coercions").expect_number(), 0.0)
  assert_eq(probe.state(), "available")
}

///|
test "R4 exposed Host adapter validates owner and live authority before user code" {
  let probe = research_hosted_probe()
  let donor = research_hosted_probe()
  let foreign = donor.number(21)
  let owned = probe.number(21)
  let entered = Ref(0)
  let escaped : Ref[HostCallbackContext?] = Ref(None)
  let typed = host_number_unary(n => {
    entered.val += 1
    n * 2
  })
  donor.close()
  probe.define_function("checkForeign", (call, args) => {
    escaped.val = Some(call)
    let rejected = try {
      ignore(typed(call, [foreign]))
      false
    } catch {
      HostedError::HostedForeignValue => true
      error => raise error
    }
    assert_true(rejected)
    assert_eq(entered.val, 0)
    args[0]
  })
  assert_eq(probe.evaluate("checkForeign(7)").expect_number(), 7.0)
  let expired = try {
    ignore(typed(escaped.val.unwrap(), [owned]))
    false
  } catch {
    HostedError::HostedExpiredHostCall => true
    error => raise error
  }
  assert_true(expired)
  assert_eq(entered.val, 0)
  assert_eq(probe.state(), "available")
}

///|
test "R4 mapped TypeError keeps intrinsic identity after guest constructor rebinding" {
  let probe = research_hosted_probe()
  let entered = Ref(0)
  probe.define_function(
    "double",
    host_number_unary(n => {
      entered.val += 1
      n * 2
    }),
  )
  let source =
    #|var NativeTypeError = TypeError;
    #|TypeError = function ReboundTypeError() {};
    #|var intrinsic = false;
    #|try { double('21'); } catch (e) { intrinsic = e instanceof NativeTypeError; }
    #|intrinsic;
  assert_true(probe.evaluate(source).expect_bool())
  assert_eq(entered.val, 0)
  assert_eq(probe.state(), "available")
}
