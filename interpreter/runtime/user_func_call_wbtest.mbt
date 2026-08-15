///| Whitebox tests for simple UserFunc call preparation and gate ownership.

///|
fn user_func_call_test_fixture(
  closure : Environment,
  body : Array[@ast.Stmt],
) -> (FuncData, Value) {
  let data : FuncData = {
    name: Some("fixture"),
    params: ["value"],
    body,
    closure,
    strict: true,
    has_name_binding: false,
    is_method: false,
    source_text: None,
    materializer: None,
  }
  (data, make_func(data))
}

///|
fn user_func_call_test_counting_probe(
  interp : Interpreter,
  name : String,
  calls : Ref[Int],
) -> Value {
  make_native_func(name~, realm_state=Some(interp.realm_state), fn(_args) {
    calls.val += 1
    Undefined
  })
}

///|
fn user_func_call_test_raising_probe(
  interp : Interpreter,
  name : String,
  calls : Ref[Int],
  sentinel : Error,
) -> Value {
  make_native_func(name~, realm_state=Some(interp.realm_state), fn(
    _args,
  ) raise {
    calls.val += 1
    raise sentinel
  })
}

///|
fn user_func_call_test_proxy_closure(
  interp : Interpreter,
  has_trap : Value,
  get_trap : Value,
) -> Environment {
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let handler = make_object(
    { "has": has_trap, "get": get_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let closure = Environment::new(parent=Some(interp.global))
  closure.with_object = Some(
    Value::Proxy({
      target: Some(target),
      handler: Some(handler),
      is_callable: false,
      is_constructor: false,
    }),
  )
  closure
}

///|
fn assert_user_func_call_test_gate_restored(
  interp : Interpreter,
  expected : @set.Set[String],
) -> Unit raise {
  inspect(interp.in_nonarrow_param_default_eval, content="true")
  match interp.param_default_eval_var_conflicts {
    Some(found) => inspect(physical_equal(found, expected), content="true")
    None => fail("expected the saved parameter-default conflict set")
  }
}

///|
test "simple UserFunc parameter gate scopes restore nested state in LIFO order" {
  let interp = Interpreter::new()
  let outer_conflicts : @set.Set[String] = @set.Set::default()
  outer_conflicts.add("outer")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(outer_conflicts)

  let outer_scope = interp.begin_simple_user_func_parameter_gate()
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  inspect(interp.param_default_eval_var_conflicts is None, content="true")

  let inner_conflicts : @set.Set[String] = @set.Set::default()
  inner_conflicts.add("inner")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(inner_conflicts)
  let inner_scope = interp.begin_simple_user_func_parameter_gate()
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  inspect(interp.param_default_eval_var_conflicts is None, content="true")

  interp.finish_simple_user_func_parameter_gate(inner_scope)
  assert_user_func_call_test_gate_restored(interp, inner_conflicts)
  interp.finish_simple_user_func_parameter_gate(outer_scope)
  assert_user_func_call_test_gate_restored(interp, outer_conflicts)
}

///|
test "simple UserFunc preparation binds parameters without executing its body" {
  let interp = Interpreter::new()
  let body_calls : Ref[Int] = { val: 0 }
  interp.global.def(
    "body_probe",
    user_func_call_test_counting_probe(interp, "body_probe", body_calls),
    VarBinding,
  )
  let body = @parser.parse("body_probe();").stmts
  let (data, callee) = user_func_call_test_fixture(interp.global, body)
  let saved_conflicts : @set.Set[String] = @set.Set::default()
  saved_conflicts.add("saved")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)

  let gate_scope = interp.begin_simple_user_func_parameter_gate()
  let prepared = interp.prepare_user_func_activation(
    callee,
    Undefined,
    [Number(41.0)],
    data,
  )
  inspect(body_calls.val, content="0")
  inspect(prepared.ctx.strict, content="true")
  match prepared.env.get("value") {
    Number(value) => inspect(value, content="41")
    _ => fail("expected the prepared parameter binding")
  }
  interp.finish_simple_user_func_parameter_gate(gate_scope)
  assert_user_func_call_test_gate_restored(interp, saved_conflicts)
}

///|
test "simple UserFunc preparation uses pre-resolved ThrowTypeError without routing" {
  let interp = Interpreter::new()
  let has_calls : Ref[Int] = { val: 0 }
  let get_calls : Ref[Int] = { val: 0 }
  let has_trap = user_func_call_test_counting_probe(
    interp, "has trap", has_calls,
  )
  let get_trap = user_func_call_test_counting_probe(
    interp, "get trap", get_calls,
  )
  let closure = user_func_call_test_proxy_closure(interp, has_trap, get_trap)
  let (data, callee) = user_func_call_test_fixture(closure, [])
  let throw_type_error = make_native_func(
    name="pre-resolved ThrowTypeError",
    realm_state=Some(interp.realm_state),
    _args => Undefined,
  )

  let prepared = interp.prepare_user_func_activation(
    callee,
    Undefined,
    [Number(1.0)],
    data,
    throw_type_error_source=UsePreResolvedThrowTypeError(Some(throw_type_error)),
  )
  let _ = interp.prepare_user_func_activation(
    callee,
    Undefined,
    [],
    data,
    throw_type_error_source=UsePreResolvedThrowTypeError(None),
  )

  inspect(has_calls.val, content="0")
  inspect(get_calls.val, content="0")
  match prepared.env.bindings.get("arguments") {
    Some({ value: Object(arguments_data), .. }) =>
      match arguments_data.bag.descriptors.get("callee") {
        Some(descriptor) => {
          match descriptor.getter {
            Some(getter) =>
              inspect(physical_equal(getter, throw_type_error), content="true")
            None => fail("expected the pre-resolved ThrowTypeError getter")
          }
          match descriptor.setter {
            Some(setter) =>
              inspect(physical_equal(setter, throw_type_error), content="true")
            None => fail("expected the pre-resolved ThrowTypeError setter")
          }
        }
        None => fail("expected the arguments callee descriptor")
      }
    _ => fail("expected the prepared arguments object")
  }
}

///|
test "simple UserFunc successful call restores parameter gate" {
  let interp = Interpreter::new()
  let body_calls : Ref[Int] = { val: 0 }
  interp.global.def(
    "body_probe",
    user_func_call_test_counting_probe(interp, "body_probe", body_calls),
    VarBinding,
  )
  let (_data, callee) = user_func_call_test_fixture(
    interp.global,
    @parser.parse("body_probe(); return value;").stmts,
  )
  let saved_conflicts : @set.Set[String] = @set.Set::default()
  saved_conflicts.add("saved")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)

  let result = interp.call_value(
    callee,
    Undefined,
    [Number(42.0)],
    @token.Loc::default(),
  )
  match result {
    Number(value) => inspect(value, content="42")
    _ => fail("expected the simple UserFunc return value")
  }
  inspect(body_calls.val, content="1")
  assert_user_func_call_test_gate_restored(interp, saved_conflicts)
}

///|
test "simple UserFunc setup failure preserves error and restores parameter gate" {
  let interp = Interpreter::new()
  let has_calls : Ref[Int] = { val: 0 }
  let get_calls : Ref[Int] = { val: 0 }
  let body_calls : Ref[Int] = { val: 0 }
  let sentinel : Error = @errors.TypeError(message="setup sentinel")
  let has_trap = make_native_func(
    name="has trap",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      has_calls.val += 1
      Bool(true)
    },
  )
  let get_trap = make_native_func(
    name="get trap",
    realm_state=Some(interp.realm_state),
    fn(args) raise {
      match args[1] {
        String_("[[ThrowTypeError]]") => {
          get_calls.val += 1
          raise sentinel
        }
        _ => Undefined
      }
    },
  )
  let closure = user_func_call_test_proxy_closure(interp, has_trap, get_trap)
  interp.global.def(
    "body_probe",
    user_func_call_test_counting_probe(interp, "body_probe", body_calls),
    VarBinding,
  )
  let (_data, callee) = user_func_call_test_fixture(
    closure,
    @parser.parse("body_probe();").stmts,
  )
  let saved_conflicts : @set.Set[String] = @set.Set::default()
  saved_conflicts.add("saved")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)

  let caught : Error? = try {
    let _ = interp.call_value(
      callee,
      Undefined,
      [Number(1.0)],
      @token.Loc::default(),
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => inspect(physical_equal(error, sentinel), content="true")
    None => fail("expected setup to raise")
  }
  inspect(has_calls.val, content="2")
  inspect(get_calls.val, content="1")
  inspect(body_calls.val, content="0")
  assert_user_func_call_test_gate_restored(interp, saved_conflicts)
}

///|
test "simple UserFunc body failure preserves error and restores parameter gate" {
  let interp = Interpreter::new()
  let body_calls : Ref[Int] = { val: 0 }
  let sentinel : Error = @errors.RangeError(message="body sentinel")
  interp.global.def(
    "body_probe",
    user_func_call_test_raising_probe(
      interp, "body_probe", body_calls, sentinel,
    ),
    VarBinding,
  )
  let (_data, callee) = user_func_call_test_fixture(
    interp.global,
    @parser.parse("body_probe();").stmts,
  )
  let saved_conflicts : @set.Set[String] = @set.Set::default()
  saved_conflicts.add("saved")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)

  let caught : Error? = try {
    let _ = interp.call_value(
      callee,
      Undefined,
      [Number(1.0)],
      @token.Loc::default(),
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => inspect(physical_equal(error, sentinel), content="true")
    None => fail("expected the body to raise")
  }
  inspect(body_calls.val, content="1")
  assert_user_func_call_test_gate_restored(interp, saved_conflicts)
}
