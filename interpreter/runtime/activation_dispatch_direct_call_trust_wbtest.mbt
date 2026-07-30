///|
fn direct_numeric_recursion_trust_fixture(
  source : String,
  entry_name : String,
) -> (Interpreter, Value) raise {
  let interp = Interpreter::new()
  let stmts = @parser.parse(source).stmts
  interp.prepare_root_program_execution(stmts, interp.global, false)
  (interp, interp.global.get(entry_name))
}

///|
fn direct_numeric_recursion_preflight_or_fail(
  interp : Interpreter,
  callee : Value,
) -> DirectNumericRecursionPreflight raise {
  match
    interp.preflight_direct_numeric_recursion_call(
      callee,
      Undefined,
      [Number(256.0)],
      @token.Loc::default(),
    ) {
    Some(preflight) => preflight
    None => fail("expected exact direct numeric recursion preflight")
  }
}

///|
fn direct_numeric_recursion_registry_or_fail(
  interp : Interpreter,
  callee : Value,
) -> TrustedNumericRecursionRegistry raise {
  interp.seal_direct_numeric_recursion_registry(
    direct_numeric_recursion_preflight_or_fail(interp, callee),
    callee,
    Undefined,
    [Number(256.0)],
    @token.Loc::default(),
  )
}

///|
test "direct numeric recursion trust seals canonical self and mutual identities" {
  let (self_interp, self_callee) = direct_numeric_recursion_trust_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}", "f",
  )
  let self_registry = direct_numeric_recursion_registry_or_fail(
    self_interp, self_callee,
  )
  inspect(self_registry.program_plan is None, content="true")
  let self_syntax = self_registry.require_callee(self_interp, self_callee)
  inspect(self_syntax.name, content="f")
  inspect(self_syntax.recursive_callee, content="f")

  let (mutual_interp, mutual_callee) = direct_numeric_recursion_trust_fixture(
    "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
    "function g(m){if(m===0)return 0;return 1+f(m-1);}",
    "f",
  )
  let mutual_registry = direct_numeric_recursion_registry_or_fail(
    mutual_interp, mutual_callee,
  )
  let peer = mutual_registry.require_named(mutual_interp, "g")
  let peer_syntax = mutual_registry.require_callee(mutual_interp, peer)
  inspect(peer_syntax.name, content="g")
  inspect(peer_syntax.parameter, content="m")
  inspect(peer_syntax.recursive_callee, content="f")
}

///|
test "direct numeric recursion trust rejects noncanonical global representations" {
  let (mirror_interp, mirror_callee) = direct_numeric_recursion_trust_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}", "f",
  )
  guard mirror_interp.global_this is Object(mirror_global) else {
    fail("expected the canonical global object")
  }
  mirror_global.bag.properties["f"] = Number(0.0)
  inspect(
    mirror_interp.preflight_direct_numeric_recursion_call(
      mirror_callee,
      Undefined,
      [Number(256.0)],
      @token.Loc::default(),
    )
    is None,
    content="true",
  )

  let (descriptor_interp, descriptor_callee) = direct_numeric_recursion_trust_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}", "f",
  )
  guard descriptor_interp.global_this is Object(descriptor_global) &&
    descriptor_global.bag.descriptors.get("f") is Some(descriptor) else {
    fail("expected the canonical global function descriptor")
  }
  descriptor.configurable = true
  inspect(
    descriptor_interp.preflight_direct_numeric_recursion_call(
      descriptor_callee,
      Undefined,
      [Number(256.0)],
      @token.Loc::default(),
    )
    is None,
    content="true",
  )
}

///|
test "direct numeric recursion trust rejects closure lookalikes and incomplete mutual cycles" {
  let (interp, callee) = direct_numeric_recursion_trust_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}", "f",
  )
  let lookalike = match callee {
    Object(object_data) =>
      match object_data.callable {
        Some(UserFunc(data)) =>
          Object({
            ..object_data,
            callable: Some(UserFunc({ ..data, closure: Environment::new() })),
          })
        _ => fail("expected a simple UserFunc")
      }
    _ => fail("expected a function object")
  }
  guard interp.global.bindings.get("f") is Some(binding) &&
    interp.global_this is Object(global_object) else {
    fail("expected canonical global storage")
  }
  binding.value = lookalike
  global_object.bag.properties["f"] = lookalike
  inspect(
    interp.preflight_direct_numeric_recursion_call(
      lookalike,
      Undefined,
      [Number(256.0)],
      @token.Loc::default(),
    )
    is None,
    content="true",
  )

  let (one_way_interp, one_way_callee) = direct_numeric_recursion_trust_fixture(
    "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
    "function g(m){if(m===0)return 0;return 1+g(m-1);}",
    "f",
  )
  inspect(
    one_way_interp.preflight_direct_numeric_recursion_call(
      one_way_callee,
      Undefined,
      [Number(256.0)],
      @token.Loc::default(),
    )
    is None,
    content="true",
  )
}

///|
test "direct numeric recursion trust seals source and exact recipe metadata" {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("direct.js")
  let stmts = @parser.parse("function f(n){if(n===0)return 0;return 1+f(n-1);}").stmts
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let callee = interp.global.get("f")
  let preflight = direct_numeric_recursion_preflight_or_fail(interp, callee)
  guard callee is Object(object_data) &&
    object_data.callable is Some(UserFunc(data)) else {
    fail("expected a simple UserFunc")
  }
  data.body[0] = @parser.parse("\n\nif(n===0)return 0;").stmts[0]
  let recipe_drift = try {
    let _ = interp.seal_direct_numeric_recursion_registry(
      preflight,
      callee,
      Undefined,
      [Number(256.0)],
      @token.Loc::default(),
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    recipe_drift,
    content="direct numeric recursion call no longer matches exact admission",
  )

  let (source_interp, source_callee) = direct_numeric_recursion_trust_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}", "f",
  )
  source_interp.realm_state.active_source_identity.val = Some("other.js")
  inspect(
    source_interp.preflight_direct_numeric_recursion_call(
      source_callee,
      Undefined,
      [Number(256.0)],
      @token.Loc::default(),
    )
    is None,
    content="true",
  )
}

///|
test "direct numeric recursion trust revalidates ThrowTypeError identity" {
  let (interp, callee) = direct_numeric_recursion_trust_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}", "f",
  )
  let registry = direct_numeric_recursion_registry_or_fail(interp, callee)
  interp.global.def_builtin(
    "[[ThrowTypeError]]",
    make_native_func(name="replacement ThrowTypeError", _args => Undefined),
  )
  let outcome = try {
    let _ = registry.require_named(interp, "f")
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    outcome,
    content="numeric recursion ThrowTypeError binding changed after sealing",
  )
}

///|
test "direct numeric recursion trust revalidates canonical global descriptors" {
  let (configurable_interp, configurable_callee) = direct_numeric_recursion_trust_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}", "f",
  )
  let configurable_registry = direct_numeric_recursion_registry_or_fail(
    configurable_interp, configurable_callee,
  )
  guard configurable_interp.global_this is Object(configurable_global) &&
    configurable_global.bag.descriptors.get("f")
    is Some(configurable_descriptor) else {
    fail("expected the sealed global function descriptor")
  }
  configurable_descriptor.configurable = true
  let configurable_result = try {
    let _ = configurable_registry.require_named(configurable_interp, "f")
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }

  let (accessor_interp, accessor_callee) = direct_numeric_recursion_trust_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}", "f",
  )
  let accessor_registry = direct_numeric_recursion_registry_or_fail(
    accessor_interp, accessor_callee,
  )
  guard accessor_interp.global_this is Object(accessor_global) &&
    accessor_global.bag.descriptors.get("f") is Some(accessor_descriptor) else {
    fail("expected the sealed global function descriptor")
  }
  accessor_descriptor.is_accessor = true
  accessor_descriptor.getter = Some(accessor_callee)
  let accessor_result = try {
    let _ = accessor_registry.require_callee(accessor_interp, accessor_callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }

  inspect(
    configurable_result,
    content="numeric recursion candidate diverged from its global mirror",
  )
  inspect(
    accessor_result,
    content="numeric recursion candidate diverged from its global mirror",
  )
}

///|
test "direct numeric recursion abrupt exit restores activation lifecycle state" {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("direct.js")
  let stmts = @parser.parse("function f(n){if(n===0)return 0;return 1+f(n-1);}").stmts
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let callee = interp.global.get("f")
  let caller_object_proto = make_object(
    Map([]),
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  apply_active_realm_protos(
    interp.realm_state,
    FunctionRealmProtos(object_proto=Some(caller_object_proto)),
  )
  inspect(
    interp.preflight_direct_numeric_recursion_call(
      callee,
      Undefined,
      [Number(256.0)],
      @token.Loc::default(),
    )
    is Some(_),
    content="true",
  )
  interp.in_nonarrow_param_default_eval = true
  let conflicts : @set.Set[String] = @set.Set::default()
  conflicts.add("outer") |> ignore
  interp.param_default_eval_var_conflicts = Some(conflicts)
  let control = ExecutionControl(
    remaining_steps=1,
    maximum_active_depth=1024,
    interruption=ExecutionInterruptionRequest(),
  )
  let outcome = try {
    let _ : Value = interp.with_execution_control(control, fn() raise {
      interp.call_value(
        callee,
        Undefined,
        [Number(256.0)],
        @token.Loc::default(),
      )
    })
    "completed"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "other-error"
  }
  inspect(outcome, content="execution-limit")
  inspect(interp.in_nonarrow_param_default_eval, content="true")
  match interp.param_default_eval_var_conflicts {
    Some(restored) =>
      inspect(physical_equal(restored, conflicts), content="true")
    None => fail("expected parameter-default conflict state restoration")
  }
  match
    (active_realm_protos(interp.realm_state).object_proto, caller_object_proto) {
    (Some(Object(actual)), Object(expected)) =>
      inspect(physical_equal(actual, expected), content="true")
    _ => fail("expected caller realm restoration")
  }
  inspect(
    interp.realm_state.active_source_identity.val == Some("direct.js"),
    content="true",
  )
}
