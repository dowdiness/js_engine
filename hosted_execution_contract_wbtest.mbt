///|
test "R5 body nested calls and checkpoint retain one control instance" {
  let probe = host_failure_probe()
  let original : Ref[@runtime.ExecutionControl?] = Ref(None)
  let events : Array[String] = []
  probe.define_function("observeCarrier", (_call, args) => {
    let current = probe.session.engine.interp.hosted_execution_control.unwrap()
    match original.val {
      None => original.val = Some(current)
      Some(first) => assert_true(physical_equal(first, current))
    }
    events.push(args[0].expect_string())
    args[0]
  })
  probe.define_function("invokeCarrier", (call, args) => {
    let current = probe.session.engine.interp.hosted_execution_control.unwrap()
    assert_true(physical_equal(original.val.unwrap(), current))
    let result = call.call(args[0], [])
    assert_true(
      physical_equal(
        current,
        probe.session.engine.interp.hosted_execution_control.unwrap(),
      ),
    )
    result
  })
  assert_eq(
    probe
    .evaluate(
      "observeCarrier('body'); invokeCarrier(() => { observeCarrier('nested'); queueMicrotask(() => observeCarrier('checkpoint')); }); 42",
    )
    .expect_number(),
    42.0,
  )
  json_inspect(events, content=["body", "nested", "checkpoint"])
  assert_true(probe.session.engine.interp.hosted_execution_control is None)
  assert_eq(probe.state(), "available")
}

///|
test "R5 nested receiver and callee realms restore on every unwind" {
  for entry in ["get", "call", "property"] {
    for outcome in ["normal", "guest", "host", "terminal"] {
      let probe = host_failure_probe()
      let donor = host_failure_probe()
      let realm = probe.session.engine.interp.realm_state
      let donor_realm = donor.session.engine.interp.realm_state
      let parent = host_failure_probe()
      let parent_realm = parent.session.engine.interp.realm_state
      let expected_parent = @runtime.FunctionRealmProtos(
        function_proto=parent_realm.function_prototype.val,
        object_proto=parent_realm.object_prototype.val,
        string_proto=parent_realm.string_prototype.val,
        number_proto=parent_realm.number_prototype.val,
        boolean_proto=parent_realm.boolean_prototype.val,
        symbol_proto=parent_realm.symbol_prototype.val,
        array_proto=parent_realm.array_prototype.val,
        map_proto=parent_realm.map_prototype.val,
        set_proto=parent_realm.set_prototype.val,
        promise_proto=parent_realm.promise_prototype.val,
        constructor_prototype_registry=Some(
          parent_realm.constructor_prototype_registry,
        ),
      )
      let target = probe.evaluate(
        "var realmTarget = { get x() { return realmExit(function() {}); }, method() { if (this !== realmTarget) throw 'wrong receiver'; return realmExit(function() {}); } }; realmTarget",
      )
      let callee = match entry {
        "get" =>
          probe.evaluate(
            "Object.getOwnPropertyDescriptor(realmTarget, 'x').get",
          )
        "property" => target.get("method")
        _ => probe.evaluate("(function() { return realmExit(function() {}); })")
      }
      ignore(
        @runtime.stamp_function_realm(
          callee.value,
          realm_state=Some(donor_realm),
        ),
      )
      let restored = Ref(false)
      let intrinsic_in_callee : Ref[@runtime.Value?] = Ref(None)
      // The argument is computed before entering the Host callback's realm.
      probe.define_function("realmExit", (call, args) => {
        intrinsic_in_callee.val = Some(
          @runtime.object_get_prototype_of(
            probe.session.engine.interp,
            args[0].value,
          ),
        )
        match outcome {
          "guest" => call.throw_value(args[0])
          "host" => fail("realm unwind Host sentinel")
          "terminal" => call.terminate(HostedExpectedNumber)
          _ => ()
        }
        args[0]
      })
      probe.define_function("invokeRealm", (call, _args) => {
        let before = realm.active_overrides.val
        let before_source = realm.active_source_identity.val
        assert_true(before is Some(_))
        assert_eq(before_source, Some("parent-hosted.js"))
        assert_hosted_realm_restored(Some(expected_parent), before)
        let result : Result[HostedValue, Error] = Ok(
          match entry {
            "get" => call.get(target, "x")
            "property" => call.call_property(target, "method", [])
            _ => call.call(callee, [])
          },
        ) catch {
          error => Err(error)
        }
        let after = realm.active_overrides.val
        assert_hosted_realm_restored(before, after)
        assert_eq(realm.active_source_identity.val, before_source)
        restored.val = true
        match result {
          Ok(value) => value
          Err(error) => raise error
        }
      })
      let invocation = probe.global("invokeRealm")
      @runtime.with_source_identity(parent_realm, Some("parent-hosted.js"), () => {
        ignore(
          @runtime.stamp_function_realm(
            invocation.value,
            realm_state=Some(parent_realm),
          ),
        )
      })
      let observed = try {
        ignore(probe.evaluate("invokeRealm()"))
        "normal"
      } catch {
        HostedGuestThrow(_) => "guest"
        HostedHostFailure(_) => "host"
        HostedTerminal(_) => "terminal"
        error => raise error
      }
      assert_eq(observed, outcome)
      assert_true(restored.val)
      assert_true(
        @runtime.strict_equal(
          intrinsic_in_callee.val.unwrap(),
          donor_realm.get_func_proto(),
        ),
      )
      assert_true(realm.active_overrides.val is None)
      if outcome == "normal" || outcome == "guest" {
        let later = probe.evaluate("(function() {})")
        assert_true(
          @runtime.strict_equal(
            @runtime.object_get_prototype_of(
              probe.session.engine.interp,
              later.value,
            ),
            realm.get_func_proto(),
          ),
        )
        assert_eq(probe.state(), "available")
      } else {
        assert_eq(probe.state(), "faulted")
      }
    }
  }
}

///|
test "R5 interruption at commit cannot publish a successful outcome" {
  let interruption = @runtime.InterruptionHandle()
  let probe = HostedSession(
    @runtime.ExecutionPolicy::new(100000L, 64L, interruption).unwrap(),
  )
  let stopped = try {
    ignore(
      probe.public_turn(
        () => {
          interruption.request()
          42
        },
        operation="commit-boundary",
      ),
    )
    false
  } catch {
    HostedTerminal(cause, diagnostic, _) => {
      assert_eq(
        @runtime.execution_control_failure_code(cause),
        Some("interrupted"),
      )
      assert_eq(diagnostic.phase_code(), "commit")
      true
    }
    error => raise error
  }
  assert_true(stopped)
  assert_eq(probe.state(), "faulted")
}

///|
fn assert_hosted_realm_restored(
  before : @runtime.FunctionRealmProtos?,
  after : @runtime.FunctionRealmProtos?,
) -> Unit raise {
  match (before, after) {
    (None, None) => ()
    (Some(before), Some(after)) => {
      let original = [
        before.function_proto,
        before.object_proto,
        before.array_proto,
        before.number_proto,
        before.boolean_proto,
        before.string_proto,
        before.symbol_proto,
        before.map_proto,
        before.set_proto,
        before.promise_proto,
        before.constructor_prototype_registry,
      ]
      let restored = [
        after.function_proto,
        after.object_proto,
        after.array_proto,
        after.number_proto,
        after.boolean_proto,
        after.string_proto,
        after.symbol_proto,
        after.map_proto,
        after.set_proto,
        after.promise_proto,
        after.constructor_prototype_registry,
      ]
      for i in 0..<original.length() {
        match (original[i], restored[i]) {
          (None, None) => ()
          (Some(a), Some(b)) => assert_true(@runtime.strict_equal(a, b))
          _ => fail("realm override slot was not restored")
        }
      }
    }
    _ => fail("realm override presence was not restored")
  }
}
