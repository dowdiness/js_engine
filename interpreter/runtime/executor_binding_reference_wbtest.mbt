///|
test "issue 933 retains one lexical binding reference across read and write" {
  let interp = Interpreter::new()
  let env = Environment::new(parent=Some(interp.global))
  env.def("value", Number(1.0), VarBinding)
  let ctx : ExecContext = { strict: false, current_generator: None }
  let reference = match
    begin_executor_binding_reference(
      interp,
      ctx,
      env,
      "value",
      @token.Loc::default(),
    ) {
    ExecutorBindingReferenceCompleted(reference) => reference
    ExecutorBindingReferenceSuspended(_) =>
      fail("ordinary lexical reference resolution must be synchronous")
  }
  let old_value = match
    begin_executor_binding_reference_get(interp, reference) {
    ExecutorBindingReferenceGetCompleted(value) => value
    ExecutorBindingReferenceGetSuspended(_) =>
      fail("ordinary lexical reference read must be synchronous")
  }
  assert_eq(old_value.to_string(), "1")
  let put_value = match
    begin_executor_binding_reference_put(interp, reference, Number(2.0)) {
    ExecutorBindingReferencePutCompleted(value) => value
    ExecutorBindingReferencePutSuspended(_) =>
      fail("ordinary lexical reference write must be synchronous")
  }
  assert_eq(put_value.to_string(), "2")
  assert_eq(env.get("value").to_string(), "2")
}

///|
test "issue 933 strict reference reads allow eval and arguments" {
  let interp = Interpreter::new()
  let env = Environment::new(parent=Some(interp.global))
  env.def("eval", Number(1.0), VarBinding)
  env.def("arguments", Number(2.0), VarBinding)
  let ctx : ExecContext = { strict: true, current_generator: None }
  for item in [("eval", "1"), ("arguments", "2")] {
    let name = item.0
    let expected = item.1
    let reference = match
      begin_executor_binding_reference(
        interp,
        ctx,
        env,
        name,
        @token.Loc::default(),
      ) {
      ExecutorBindingReferenceCompleted(reference) => reference
      ExecutorBindingReferenceSuspended(_) =>
        fail("strict lexical reference resolution must be synchronous")
    }
    match begin_executor_binding_reference_get(interp, reference) {
      ExecutorBindingReferenceGetCompleted(value) =>
        assert_eq(value.to_string(), expected)
      ExecutorBindingReferenceGetSuspended(_) =>
        fail("strict lexical reference read must be synchronous")
    }
    let put : Result[ExecutorBindingReferencePutStart, Error] = Ok(
      begin_executor_binding_reference_put(interp, reference, Number(3.0)),
    ) catch {
      error => Err(error)
    }
    match put {
      Err(error) =>
        match @errors.name_message_if_js_error(error) {
          Some((name, _)) => assert_eq(name, "SyntaxError")
          None => fail("strict eval/arguments write must raise SyntaxError")
        }
      Ok(_) => fail("strict eval/arguments write must be rejected")
    }
  }
}

///|
test "issue 933 lexical references retain parent cells and runtime errors" {
  let interp = Interpreter::new()
  let parent = Environment::new(parent=Some(interp.global))
  parent.def("parent_value", Number(3.0), LetBinding)
  let child = Environment::new(parent=Some(parent))
  let ctx : ExecContext = { strict: false, current_generator: None }
  let reference = match
    begin_executor_binding_reference(
      interp,
      ctx,
      child,
      "parent_value",
      @token.Loc::default(),
    ) {
    ExecutorBindingReferenceCompleted(reference) => reference
    ExecutorBindingReferenceSuspended(_) =>
      fail("parent lexical reference resolution must be synchronous")
  }
  parent.bindings["parent_value"].value = Number(4.0)
  match begin_executor_binding_reference_get(interp, reference) {
    ExecutorBindingReferenceGetCompleted(value) =>
      assert_eq(value.to_string(), "4")
    ExecutorBindingReferenceGetSuspended(_) =>
      fail("parent lexical reference read must be synchronous")
  }

  let tdz = Environment::new(parent=Some(interp.global))
  tdz.def_tdz("tdz", LetBinding)
  let tdz_reference = match
    begin_executor_binding_reference(
      interp,
      ctx,
      tdz,
      "tdz",
      @token.Loc::default(),
    ) {
    ExecutorBindingReferenceCompleted(reference) => reference
    ExecutorBindingReferenceSuspended(_) =>
      fail("TDZ reference resolution must be synchronous")
  }
  let tdz_read : Result[ExecutorBindingReferenceGetStart, Error] = Ok(
    begin_executor_binding_reference_get(interp, tdz_reference),
  ) catch {
    error => Err(error)
  }
  match tdz_read {
    Err(error) =>
      match @errors.name_message_if_js_error(error) {
        Some((name, _)) => assert_eq(name, "ReferenceError")
        None => fail("TDZ read must raise a JavaScript ReferenceError")
      }
    Ok(_) => fail("TDZ read must raise ReferenceError")
  }

  let const_env = Environment::new(parent=Some(interp.global))
  const_env.def("constant", Number(5.0), ConstBinding)
  let const_reference = match
    begin_executor_binding_reference(
      interp,
      ctx,
      const_env,
      "constant",
      @token.Loc::default(),
    ) {
    ExecutorBindingReferenceCompleted(reference) => reference
    ExecutorBindingReferenceSuspended(_) =>
      fail("const reference resolution must be synchronous")
  }
  let const_write : Result[ExecutorBindingReferencePutStart, Error] = Ok(
    begin_executor_binding_reference_put(interp, const_reference, Number(6.0)),
  ) catch {
    error => Err(error)
  }
  match const_write {
    Err(error) =>
      match @errors.name_message_if_js_error(error) {
        Some((name, _)) => assert_eq(name, "TypeError")
        None => fail("const write must raise a JavaScript TypeError")
      }
    Ok(_) => fail("const write must raise TypeError")
  }
  assert_eq(const_env.get("constant").to_string(), "5")
}

///|
test "issue 933 global and unresolved references preserve current assignment rules" {
  let interp = Interpreter::new()
  let env = Environment::new(parent=Some(interp.global))
  let ctx : ExecContext = { strict: false, current_generator: None }
  match interp.global_this {
    Object(data) => data.bag.properties["global_value"] = Number(7.0)
    _ => fail("Interpreter::new must provide a global object")
  }
  let global_reference = match
    begin_executor_binding_reference(
      interp,
      ctx,
      env,
      "global_value",
      @token.Loc::default(),
    ) {
    ExecutorBindingReferenceCompleted(reference) => reference
    ExecutorBindingReferenceSuspended(_) =>
      fail("global reference resolution must be synchronous")
  }
  match begin_executor_binding_reference_get(interp, global_reference) {
    ExecutorBindingReferenceGetCompleted(value) =>
      assert_eq(value.to_string(), "7")
    ExecutorBindingReferenceGetSuspended(_) =>
      fail("global reference read must be synchronous")
  }
  let global_write = match
    begin_executor_binding_reference_put(interp, global_reference, Number(8.0)) {
    ExecutorBindingReferencePutCompleted(value) => value
    ExecutorBindingReferencePutSuspended(_) =>
      fail("global reference write must be synchronous")
  }
  assert_eq(global_write.to_string(), "8")
  match interp.global_this {
    Object(data) =>
      assert_eq(data.bag.properties["global_value"].to_string(), "8")
    _ => fail("global object must remain available")
  }

  let unresolved_reference = match
    begin_executor_binding_reference(
      interp,
      ctx,
      env,
      "implicit_value",
      @token.Loc::default(),
    ) {
    ExecutorBindingReferenceCompleted(reference) => reference
    ExecutorBindingReferenceSuspended(_) =>
      fail("unresolved reference resolution must be synchronous")
  }
  let implicit_write = match
    begin_executor_binding_reference_put(
      interp,
      unresolved_reference,
      Number(9.0),
    ) {
    ExecutorBindingReferencePutCompleted(value) => value
    ExecutorBindingReferencePutSuspended(_) =>
      fail("unresolved write must be synchronous")
  }
  assert_eq(implicit_write.to_string(), "9")
  let unresolved_read : Result[ExecutorBindingReferenceGetStart, Error] = Ok(
    begin_executor_binding_reference_get(interp, unresolved_reference),
  ) catch {
    error => Err(error)
  }
  match unresolved_read {
    Err(error) =>
      match @errors.name_message_if_js_error(error) {
        Some((name, _)) => assert_eq(name, "ReferenceError")
        None => fail("unresolved read must raise a JavaScript ReferenceError")
      }
    Ok(_) => fail("an unresolved reference must remain unresolved")
  }

  let strict_ctx : ExecContext = { strict: true, current_generator: None }
  let strict_unresolved = match
    begin_executor_binding_reference(
      interp,
      strict_ctx,
      env,
      "strict_missing",
      @token.Loc::default(),
    ) {
    ExecutorBindingReferenceCompleted(reference) => reference
    ExecutorBindingReferenceSuspended(_) =>
      fail("strict unresolved reference resolution must be synchronous")
  }
  let strict_write : Result[ExecutorBindingReferencePutStart, Error] = Ok(
    begin_executor_binding_reference_put(
      interp,
      strict_unresolved,
      Number(10.0),
    ),
  ) catch {
    error => Err(error)
  }
  match strict_write {
    Err(error) =>
      match @errors.name_message_if_js_error(error) {
        Some((name, _)) => assert_eq(name, "ReferenceError")
        None => fail("strict unresolved write must raise ReferenceError")
      }
    Ok(_) => fail("strict unresolved write must not complete normally")
  }

  match interp.global_this {
    Object(data) => {
      data.bag.properties["immutable_value"] = Number(1.0)
      data.bag.descriptors["immutable_value"] = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
        is_accessor: false,
      }
    }
    _ => fail("global object must remain available")
  }
  let immutable_reference = match
    begin_executor_binding_reference(
      interp,
      ctx,
      env,
      "immutable_value",
      @token.Loc::default(),
    ) {
    ExecutorBindingReferenceCompleted(reference) => reference
    ExecutorBindingReferenceSuspended(_) =>
      fail("immutable global reference resolution must be synchronous")
  }
  let immutable_sloppy = match
    begin_executor_binding_reference_put(
      interp,
      immutable_reference,
      Number(2.0),
    ) {
    ExecutorBindingReferencePutCompleted(value) => value
    ExecutorBindingReferencePutSuspended(_) =>
      fail("immutable global write must be synchronous")
  }
  assert_eq(immutable_sloppy.to_string(), "2")
  match interp.global_this {
    Object(data) =>
      assert_eq(data.bag.properties["immutable_value"].to_string(), "1")
    _ => fail("global object must remain available")
  }
  let immutable_strict_reference = match
    begin_executor_binding_reference(
      interp,
      strict_ctx,
      env,
      "immutable_value",
      @token.Loc::default(),
    ) {
    ExecutorBindingReferenceCompleted(reference) => reference
    ExecutorBindingReferenceSuspended(_) =>
      fail("strict immutable global resolution must be synchronous")
  }
  let immutable_strict : Result[ExecutorBindingReferencePutStart, Error] = Ok(
    begin_executor_binding_reference_put(
      interp,
      immutable_strict_reference,
      Number(3.0),
    ),
  ) catch {
    error => Err(error)
  }
  match immutable_strict {
    Err(error) =>
      match @errors.name_message_if_js_error(error) {
        Some((name, _)) => assert_eq(name, "TypeError")
        None => fail("strict immutable global write must raise TypeError")
      }
    Ok(_) => fail("strict immutable global write must not complete normally")
  }
}

///|
priv enum Issue933ReferenceProbePhase {
  Issue933ReferenceProbeNeedResolve
  Issue933ReferenceProbeAwaitResolve
  Issue933ReferenceProbeNeedGet
  Issue933ReferenceProbeAwaitGet
  Issue933ReferenceProbeNeedInterveningGet
  Issue933ReferenceProbeAwaitInterveningGet
  Issue933ReferenceProbeNeedPut
  Issue933ReferenceProbeAwaitPut(ExecutorBindingReferencePutOperation)
  Issue933ReferenceProbeComplete(Value)
  Issue933ReferenceProbeDone
}

///|
priv struct Issue933ReferenceProbe {
  ctx : ExecContext
  env : Environment
  name : String
  value : Value
  loc : @token.Loc
  before_put : () -> Unit raise Error
  intervening : Value?
  mut reference : ResolvedBindingReference?
  mut read_value : Value?
  mut phase : Issue933ReferenceProbePhase
}

///|
fn Issue933ReferenceProbe::Issue933ReferenceProbe(
  ctx~ : ExecContext,
  env~ : Environment,
  name~ : String,
  value~ : Value,
  loc~ : @token.Loc,
  before_put~ : () -> Unit raise Error,
  intervening? : Value? = None,
) -> Issue933ReferenceProbe {
  {
    ctx,
    env,
    name,
    value,
    loc,
    before_put,
    intervening,
    reference: None,
    read_value: None,
    phase: Issue933ReferenceProbeNeedResolve,
  }
}

///|
impl ExecutorActivationFrame for Issue933ReferenceProbe with fn step(
  self,
  interp,
) {
  match self.phase {
    Issue933ReferenceProbeNeedResolve =>
      match
        begin_executor_binding_reference(
          interp,
          self.ctx,
          self.env,
          self.name,
          self.loc,
        ) {
        ExecutorBindingReferenceCompleted(reference) => {
          self.reference = Some(reference)
          self.phase = Issue933ReferenceProbeNeedGet
          ExecutorActivationContinue
        }
        ExecutorBindingReferenceSuspended(request) => {
          self.phase = Issue933ReferenceProbeAwaitResolve
          executor_activation_binding_reference_request(request)
        }
      }
    Issue933ReferenceProbeAwaitResolve =>
      raise @errors.InternalError(
        message="reference probe stepped while awaiting resolution",
      )
    Issue933ReferenceProbeNeedGet => {
      let reference = self.reference.unwrap()
      match begin_executor_binding_reference_get(interp, reference) {
        ExecutorBindingReferenceGetCompleted(value) => {
          self.read_value = Some(value)
          self.phase = Issue933ReferenceProbeNeedInterveningGet
          ExecutorActivationContinue
        }
        ExecutorBindingReferenceGetSuspended(step) => {
          self.phase = Issue933ReferenceProbeAwaitGet
          step
        }
      }
    }
    Issue933ReferenceProbeAwaitGet =>
      raise @errors.InternalError(
        message="reference probe stepped while awaiting get",
      )
    Issue933ReferenceProbeNeedInterveningGet =>
      match self.intervening {
        Some(target) => {
          self.phase = Issue933ReferenceProbeAwaitInterveningGet
          executor_activation_managed_property_get(target, "trigger", self.loc)
        }
        None => {
          self.phase = Issue933ReferenceProbeNeedPut
          ExecutorActivationContinue
        }
      }
    Issue933ReferenceProbeAwaitInterveningGet =>
      raise @errors.InternalError(
        message="reference probe stepped while awaiting intervening get",
      )
    Issue933ReferenceProbeNeedPut => {
      (self.before_put)()
      let reference = self.reference.unwrap()
      match
        begin_executor_binding_reference_put(interp, reference, self.value) {
        ExecutorBindingReferencePutCompleted(value) => {
          self.phase = Issue933ReferenceProbeComplete(value)
          ExecutorActivationContinue
        }
        ExecutorBindingReferencePutSuspended(operation) => {
          self.phase = Issue933ReferenceProbeAwaitPut(operation)
          operation.step(interp)
        }
      }
    }
    Issue933ReferenceProbeAwaitPut(operation) =>
      match operation.step(interp) {
        ExecutorActivationNormal(value) => {
          self.phase = Issue933ReferenceProbeComplete(value)
          ExecutorActivationContinue
        }
        step => {
          self.phase = Issue933ReferenceProbeAwaitPut(operation)
          step
        }
      }
    Issue933ReferenceProbeComplete(value) => {
      self.phase = Issue933ReferenceProbeDone
      ExecutorActivationNormal(value)
    }
    Issue933ReferenceProbeDone =>
      raise @errors.InternalError(
        message="reference probe stepped after completion",
      )
  }
}

///|
impl ExecutorActivationFrame for Issue933ReferenceProbe with fn deliver_activation_completion(
  self,
  completion,
) {
  match completion {
    ExecutorActivationCompletionAbrupt(error) => raise error
    ExecutorActivationCompletionReference(reference) =>
      match self.phase {
        Issue933ReferenceProbeAwaitResolve => {
          self.reference = Some(reference)
          self.phase = Issue933ReferenceProbeNeedGet
        }
        _ =>
          raise @errors.InternalError(
            message="reference probe received a reference at the wrong phase",
          )
      }
    ExecutorActivationCompletionNormal(value) =>
      match self.phase {
        Issue933ReferenceProbeAwaitGet => {
          self.read_value = Some(value)
          self.phase = Issue933ReferenceProbeNeedInterveningGet
        }
        Issue933ReferenceProbeAwaitInterveningGet =>
          self.phase = Issue933ReferenceProbeNeedPut
        Issue933ReferenceProbeAwaitPut(operation) =>
          operation.deliver_activation_completion(
            ExecutorActivationCompletionNormal(value),
          )
        _ =>
          raise @errors.InternalError(
            message="reference probe received a value at the wrong phase",
          )
      }
  }
}

///|
fn issue933_run_reference_probe(
  interp : Interpreter,
  probe : Issue933ReferenceProbe,
) -> Value raise Error {
  match
    interp.run_executor_activation_coordinator(
      probe as &ExecutorActivationFrame,
    ) {
    ExecutorActivationNormal(value) => value
    ExecutorActivationReturn(value) => value
    _ =>
      raise @errors.InternalError(
        message="reference probe returned a pending activation",
      )
  }
}

///|
test "issue 933 retains with reference across a real managed suspension" {
  let interp = Interpreter::new()
  let events : Ref[Array[String]] = { val: [] }
  let selected_target = make_object(
    Map([]),
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let has_trap = make_native_func(
    name="has",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      events.val.push("has")
      Bool(true)
    },
  )
  let get_trap = make_native_func(
    name="get",
    realm_state=Some(interp.realm_state),
    fn(args) raise {
      match args {
        [_, Symbol(_), _] => {
          events.val.push("get-unscopables")
          Undefined
        }
        [_, String_(name), _] => {
          events.val.push("get-" + name)
          Number(42.0)
        }
        _ => fail("selected Proxy get trap received unexpected arguments")
      }
    },
  )
  let set_trap = make_native_func(
    name="set",
    realm_state=Some(interp.realm_state),
    fn(args) raise {
      events.val.push("set")
      match args {
        [Object(target), String_(name), value, _] => {
          target.bag.properties[name] = value
          Bool(true)
        }
        _ => fail("selected Proxy set trap received unexpected arguments")
      }
    },
  )
  let selected_handler = make_object(
    { "has": has_trap, "get": get_trap, "set": set_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let selected = Proxy({
    target: Some(selected_target),
    handler: Some(selected_handler),
    is_callable: false,
    is_constructor: false,
  })
  let outer = Environment::new(parent=Some(interp.global))
  outer.interpreter_context = Some(interp)
  outer.def("name", Number(9.0), VarBinding)
  let with_env = Environment::new(parent=Some(outer))
  with_env.interpreter_context = Some(interp)
  with_env.with_object = Some(selected)
  let replacement = make_object(
    { "name": Number(88.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let replacement_proto = make_object(
    { "name": Number(89.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let trigger_get = make_native_func(
    name="triggerGet",
    realm_state=Some(interp.realm_state),
    fn(_args) raise {
      events.val.push("intervening-get")
      with_env.with_object = Some(replacement)
      outer.bindings["name"].value = Number(99.0)
      match selected_target {
        Object(target) => target.prototype = replacement_proto
        _ => fail("selected Proxy target must remain an object")
      }
      Number(0.0)
    },
  )
  let trigger_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let trigger_handler = make_object(
    { "get": trigger_get },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let trigger = Proxy({
    target: Some(trigger_target),
    handler: Some(trigger_handler),
    is_callable: false,
    is_constructor: false,
  })
  let probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=with_env,
    name="name",
    value=Number(77.0),
    loc=@token.Loc::default(),
    before_put=() => (),
    intervening=Some(trigger),
  )
  let control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=32,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = interp.with_execution_control(control, fn() raise {
    issue933_run_reference_probe(interp, probe)
  })
  assert_eq(result.to_string(), "77")
  assert_eq(probe.read_value.unwrap().to_string(), "42")
  assert_eq(control.active_depth(), 0L)
  json_inspect(events.val, content=[
    "has", "get-unscopables", "has", "get-name", "intervening-get", "has", "set",
  ])
  match selected_target {
    Object(target) => assert_eq(target.bag.properties["name"].to_string(), "77")
    _ => fail("selected Proxy target must remain an object")
  }
  match replacement {
    Object(target) => assert_eq(target.bag.properties["name"].to_string(), "88")
    _ => fail("replacement scope object must remain an object")
  }
  assert_eq(outer.get("name").to_string(), "99")
}

///|
test "issue 933 retains lexical cell across a real managed suspension" {
  let interp = Interpreter::new()
  let parent = Environment::new(parent=Some(interp.global))
  parent.interpreter_context = Some(interp)
  parent.def("name", Number(1.0), VarBinding)
  let child = Environment::new(parent=Some(parent))
  child.interpreter_context = Some(interp)
  let replacement_parent = Environment::new(parent=Some(interp.global))
  replacement_parent.interpreter_context = Some(interp)
  replacement_parent.def("name", Number(99.0), VarBinding)
  let events : Ref[Array[String]] = { val: [] }
  let trigger_get = make_native_func(
    name="lexicalTriggerGet",
    realm_state=Some(interp.realm_state),
    fn(_args) raise {
      events.val.push("intervening-get")
      child.def("name", Number(88.0), VarBinding)
      parent.bindings["name"].value = Number(7.0)
      Number(0.0)
    },
  )
  let trigger_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let trigger_handler = make_object(
    { "get": trigger_get },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let trigger = Proxy({
    target: Some(trigger_target),
    handler: Some(trigger_handler),
    is_callable: false,
    is_constructor: false,
  })
  let probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=child,
    name="name",
    value=Number(77.0),
    loc=@token.Loc::default(),
    before_put=() => (),
    intervening=Some(trigger),
  )
  let control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=32,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = interp.with_execution_control(control, fn() raise {
    issue933_run_reference_probe(interp, probe)
  })
  assert_eq(result.to_string(), "77")
  assert_eq(probe.read_value.unwrap().to_string(), "1")
  assert_eq(control.active_depth(), 0L)
  json_inspect(events.val, content=["intervening-get"])
  assert_eq(parent.get("name").to_string(), "77")
  assert_eq(replacement_parent.get("name").to_string(), "99")
  assert_eq(child.get("name").to_string(), "88")
}

///|
test "issue 933 suspended abrupt cleanup permits same-engine reuse" {
  let interp = Interpreter::new()
  let parent = Environment::new(parent=Some(interp.global))
  parent.interpreter_context = Some(interp)
  parent.def("name", Number(1.0), VarBinding)
  let child = Environment::new(parent=Some(parent))
  child.interpreter_context = Some(interp)
  let sentinel : Error = @errors.TypeError(message="intervening sentinel")
  let throwing_get = make_native_func(
    name="throwingTriggerGet",
    realm_state=Some(interp.realm_state),
    fn(_args) raise { raise sentinel },
  )
  let trigger_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let trigger_handler = make_object(
    { "get": throwing_get },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let trigger = Proxy({
    target: Some(trigger_target),
    handler: Some(trigger_handler),
    is_callable: false,
    is_constructor: false,
  })
  let first_probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=child,
    name="name",
    value=Number(5.0),
    loc=@token.Loc::default(),
    before_put=() => (),
    intervening=Some(trigger),
  )
  let first_control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=32,
    interruption=ExecutionInterruptionRequest(),
  )
  let first : Result[Value, Error] = Ok(
    interp.with_execution_control(first_control, fn() raise {
      issue933_run_reference_probe(interp, first_probe)
    }),
  ) catch {
    error => Err(error)
  }
  match first {
    Err(error) => assert_true(physical_equal(error, sentinel))
    Ok(_) => fail("intervening guest throw must abort the reference probe")
  }
  assert_eq(first_control.active_depth(), 0L)
  assert_eq(parent.get("name").to_string(), "1")

  let successful_get = make_native_func(
    name="successfulTriggerGet",
    realm_state=Some(interp.realm_state),
    fn(_args) { Number(0.0) },
  )
  match trigger_handler {
    Object(handler) => handler.bag.properties["get"] = successful_get
    _ => fail("trigger handler must remain an object")
  }
  let second_probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=child,
    name="name",
    value=Number(6.0),
    loc=@token.Loc::default(),
    before_put=() => (),
    intervening=Some(trigger),
  )
  let second_control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=32,
    interruption=ExecutionInterruptionRequest(),
  )
  let second = interp.with_execution_control(second_control, fn() raise {
    issue933_run_reference_probe(interp, second_probe)
  })
  assert_eq(second.to_string(), "6")
  assert_eq(parent.get("name").to_string(), "6")
  assert_eq(second_control.active_depth(), 0L)
}

///|
test "issue 933 suspended interruption cleans up and permits reuse" {
  let interp = Interpreter::new()
  let parent = Environment::new(parent=Some(interp.global))
  parent.interpreter_context = Some(interp)
  parent.def("name", Number(1.0), VarBinding)
  let child = Environment::new(parent=Some(parent))
  child.interpreter_context = Some(interp)
  let interruption = ExecutionInterruptionRequest()
  let interrupting_get = make_native_func(
    name="interruptingTriggerGet",
    realm_state=Some(interp.realm_state),
    fn(_args) raise {
      interruption.requested.val = true
      interp.observe_execution_step()
      Number(0.0)
    },
  )
  let trigger_target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let trigger_handler = make_object(
    { "get": interrupting_get },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let trigger = Proxy({
    target: Some(trigger_target),
    handler: Some(trigger_handler),
    is_callable: false,
    is_constructor: false,
  })
  let first_probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=child,
    name="name",
    value=Number(5.0),
    loc=@token.Loc::default(),
    before_put=() => (),
    intervening=Some(trigger),
  )
  let control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=32,
    interruption~,
  )
  let first : Result[Value, Error] = Ok(
    interp.with_execution_control(control, fn() raise {
      issue933_run_reference_probe(interp, first_probe)
    }),
  ) catch {
    error => Err(error)
  }
  match first {
    Err(ExecutionControlError(Interrupted)) => ()
    Err(_) => fail("intervening interruption must preserve its error kind")
    Ok(_) => fail("intervening interruption must abort the reference probe")
  }
  assert_eq(control.active_depth(), 0L)
  assert_eq(parent.get("name").to_string(), "1")

  let successful_get = make_native_func(
    name="reusedTriggerGet",
    realm_state=Some(interp.realm_state),
    fn(_args) { Number(0.0) },
  )
  match trigger_handler {
    Object(handler) => handler.bag.properties["get"] = successful_get
    _ => fail("trigger handler must remain an object")
  }
  interruption.requested.val = false
  let second_probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=child,
    name="name",
    value=Number(6.0),
    loc=@token.Loc::default(),
    before_put=() => (),
    intervening=Some(trigger),
  )
  let second_control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=32,
    interruption~,
  )
  let second = interp.with_execution_control(second_control, fn() raise {
    issue933_run_reference_probe(interp, second_probe)
  })
  assert_eq(second.to_string(), "6")
  assert_eq(parent.get("name").to_string(), "6")
  assert_eq(second_control.active_depth(), 0L)
}

///|
test "issue 933 with Proxy resolves once and retains the selected base" {
  let interp = Interpreter::new()
  let events : Ref[Array[String]] = { val: [] }
  let has_trap = make_native_func(
    name="has",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      events.val.push("has")
      Bool(true)
    },
  )
  let get_trap = make_native_func(
    name="get",
    realm_state=Some(interp.realm_state),
    fn(args) raise {
      match args {
        [_, Symbol(_), _] => {
          events.val.push("get-unscopables")
          Undefined
        }
        [_, String_(name), _] => {
          events.val.push("get-" + name)
          Number(42.0)
        }
        _ => fail("Proxy get trap received an unexpected argument list")
      }
    },
  )
  let set_trap = make_native_func(
    name="set",
    realm_state=Some(interp.realm_state),
    fn(args) raise {
      events.val.push("set")
      match args {
        [Object(target), String_(name), value, _] => {
          target.bag.properties[name] = value
          Bool(true)
        }
        _ => fail("Proxy set trap received an unexpected argument list")
      }
    },
  )
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let handler = make_object(
    { "has": has_trap, "get": get_trap, "set": set_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let proxy = Proxy({
    target: Some(target),
    handler: Some(handler),
    is_callable: false,
    is_constructor: false,
  })
  let outer = Environment::new(parent=Some(interp.global))
  outer.interpreter_context = Some(interp)
  outer.def("name", Number(9.0), VarBinding)
  let with_env = Environment::new(parent=Some(outer))
  with_env.interpreter_context = Some(interp)
  with_env.with_object = Some(proxy)
  let replacement = make_object(Map([]), Null, None, "Object", Map([]), true)
  let false_has_trap = make_native_func(name="falseHas", fn(_args) {
    events.val.push("put-has")
    Bool(false)
  })
  let probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=with_env,
    name="name",
    value=Number(77.0),
    loc=@token.Loc::default(),
    before_put=fn() raise {
      with_env.with_object = Some(replacement)
      outer.bindings["name"].value = Number(99.0)
      match proxy {
        Proxy(data) =>
          match data.handler {
            Some(Object(handler_data)) =>
              handler_data.bag.properties["has"] = false_has_trap
            _ => fail("Proxy handler must remain available")
          }
        _ => fail("with binding must retain its Proxy")
      }
    },
  )
  let result = issue933_run_reference_probe(interp, probe)
  assert_eq(result.to_string(), "77")
  assert_eq(probe.read_value.unwrap().to_string(), "42")
  json_inspect(events.val, content=[
    "has", "get-unscopables", "has", "get-name", "put-has", "set",
  ])
  match target {
    Object(data) => assert_eq(data.bag.properties["name"].to_string(), "77")
    _ => fail("Proxy target must remain an object")
  }
  match replacement {
    Object(data) => assert_true(!data.bag.properties.contains("name"))
    _ => fail("replacement scope object must remain an object")
  }
  assert_eq(outer.get("name").to_string(), "99")
}

///|
test "issue 933 absent and unscopables-blocked names continue the environment chain" {
  let interp = Interpreter::new()
  let outer = Environment::new(parent=Some(interp.global))
  outer.interpreter_context = Some(interp)
  outer.def("blocked", Number(11.0), LetBinding)
  outer.def("absent_in_with", Number(12.0), LetBinding)
  let with_object = make_object(
    { "blocked": Number(2.0) },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let unscopables = make_object(Map([]), Null, None, "Object", Map([]), true)
  let unscopables_symbol = interp.realm_state.well_known_symbols.unscopables
  match unscopables {
    Object(data) => data.bag.properties["blocked"] = Bool(true)
    _ => fail("unscopables value must be an object")
  }
  match with_object {
    Object(data) =>
      data.bag.symbol_properties[unscopables_symbol.id] = unscopables
    _ => fail("with object must be an object")
  }
  let with_env = Environment::new(parent=Some(outer))
  with_env.interpreter_context = Some(interp)
  with_env.with_object = Some(with_object)
  let probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=with_env,
    name="blocked",
    value=Number(21.0),
    loc=@token.Loc::default(),
    before_put=() => (),
  )
  let result = issue933_run_reference_probe(interp, probe)
  assert_eq(result.to_string(), "21")
  assert_eq(probe.read_value.unwrap().to_string(), "11")
  assert_eq(outer.get("blocked").to_string(), "21")

  let absent_probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=with_env,
    name="absent_in_with",
    value=Number(22.0),
    loc=@token.Loc::default(),
    before_put=() => (),
  )
  let absent_result = issue933_run_reference_probe(interp, absent_probe)
  assert_eq(absent_result.to_string(), "22")
  assert_eq(absent_probe.read_value.unwrap().to_string(), "12")
  assert_eq(outer.get("absent_in_with").to_string(), "22")

  let missing_probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=with_env,
    name="not_present",
    value=Number(23.0),
    loc=@token.Loc::default(),
    before_put=() => (),
  )
  let missing_read : Result[Value, Error] = Ok(
    issue933_run_reference_probe(interp, missing_probe),
  ) catch {
    error => Err(error)
  }
  match missing_read {
    Err(error) =>
      match @errors.name_message_if_js_error(error) {
        Some((name, _)) => assert_eq(name, "ReferenceError")
        None => fail("missing read must raise a JavaScript ReferenceError")
      }
    Ok(_) => fail("missing read must not complete normally")
  }
}

///|
fn issue933_proxy_scope(
  interp : Interpreter,
  has_trap : Value,
  get_trap : Value,
  set_trap : Value,
) -> (Value, Environment) {
  let target = make_object(Map([]), Null, None, "Object", Map([]), true)
  let handler = make_object(
    { "has": has_trap, "get": get_trap, "set": set_trap },
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  let proxy = Proxy({
    target: Some(target),
    handler: Some(handler),
    is_callable: false,
    is_constructor: false,
  })
  let env = Environment::new(parent=Some(interp.global))
  env.interpreter_context = Some(interp)
  env.with_object = Some(proxy)
  (proxy, env)
}

///|
test "issue 933 managed resolution preserves has get set and revoked errors" {
  let interp = Interpreter::new()
  let has_error : Error = @errors.TypeError(message="has sentinel")
  let has_throw = make_native_func(
    name="hasThrow",
    realm_state=Some(interp.realm_state),
    fn(_args) raise { raise has_error },
  )
  let get_undefined = make_native_func(
    name="getUndefined",
    realm_state=Some(interp.realm_state),
    fn(_args) { Undefined },
  )
  let set_true = make_native_func(
    name="setTrue",
    realm_state=Some(interp.realm_state),
    fn(_args) { Bool(true) },
  )
  let (_, has_scope) = issue933_proxy_scope(
    interp, has_throw, get_undefined, set_true,
  )
  let has_result : Result[Value, Error] = Ok(
    issue933_run_reference_probe(
      interp,
      Issue933ReferenceProbe(
        ctx={ strict: false, current_generator: None },
        env=has_scope,
        name="name",
        value=Number(1.0),
        loc=@token.Loc::default(),
        before_put=() => (),
      ),
    ),
  ) catch {
    error => Err(error)
  }
  match has_result {
    Err(error) => assert_true(physical_equal(error, has_error))
    Ok(_) => fail("Proxy has trap error must be retained")
  }

  let get_error : Error = @errors.TypeError(message="get sentinel")
  let get_throw = make_native_func(
    name="getThrow",
    realm_state=Some(interp.realm_state),
    fn(args) raise {
      match args {
        [_, Symbol(_), _] => Undefined
        [_, String_(_), _] => raise get_error
        _ => fail("get trap received an unexpected argument list")
      }
    },
  )
  let has_true = make_native_func(
    name="hasTrue",
    realm_state=Some(interp.realm_state),
    fn(_args) { Bool(true) },
  )
  let (_, get_scope) = issue933_proxy_scope(
    interp, has_true, get_throw, set_true,
  )
  let get_result : Result[Value, Error] = Ok(
    issue933_run_reference_probe(
      interp,
      Issue933ReferenceProbe(
        ctx={ strict: false, current_generator: None },
        env=get_scope,
        name="name",
        value=Number(2.0),
        loc=@token.Loc::default(),
        before_put=() => (),
      ),
    ),
  ) catch {
    error => Err(error)
  }
  match get_result {
    Err(error) => assert_true(physical_equal(error, get_error))
    Ok(_) => fail("Proxy get trap error must be retained")
  }

  let set_error : Error = @errors.TypeError(message="set sentinel")
  let set_throw = make_native_func(
    name="setThrow",
    realm_state=Some(interp.realm_state),
    fn(_args) raise { raise set_error },
  )
  let get_value = make_native_func(
    name="getValue",
    realm_state=Some(interp.realm_state),
    fn(args) raise {
      match args {
        [_, Symbol(_), _] => Undefined
        [_, String_(_), _] => Number(3.0)
        _ => fail("get trap received an unexpected argument list")
      }
    },
  )
  let (_, set_scope) = issue933_proxy_scope(
    interp, has_true, get_value, set_throw,
  )
  let set_result : Result[Value, Error] = Ok(
    issue933_run_reference_probe(
      interp,
      Issue933ReferenceProbe(
        ctx={ strict: false, current_generator: None },
        env=set_scope,
        name="name",
        value=Number(3.0),
        loc=@token.Loc::default(),
        before_put=() => (),
      ),
    ),
  ) catch {
    error => Err(error)
  }
  match set_result {
    Err(error) => assert_true(physical_equal(error, set_error))
    Ok(_) => fail("Proxy set trap error must be retained")
  }

  let revoked = Proxy({
    target: None,
    handler: None,
    is_callable: false,
    is_constructor: false,
  })
  let revoked_env = Environment::new(parent=Some(interp.global))
  revoked_env.interpreter_context = Some(interp)
  revoked_env.with_object = Some(revoked)
  let revoked_result : Result[Value, Error] = Ok(
    issue933_run_reference_probe(
      interp,
      Issue933ReferenceProbe(
        ctx={ strict: false, current_generator: None },
        env=revoked_env,
        name="name",
        value=Number(4.0),
        loc=@token.Loc::default(),
        before_put=() => (),
      ),
    ),
  ) catch {
    error => Err(error)
  }
  match revoked_result {
    Err(error) =>
      match @errors.name_message_if_js_error(error) {
        Some((name, _)) => assert_eq(name, "TypeError")
        None => fail("revoked Proxy must raise a JavaScript TypeError")
      }
    Ok(_) => fail("revoked Proxy resolution must not complete normally")
  }
}

///|
test "issue 933 preserves the selected with base when the recheck disappears" {
  let interp = Interpreter::new()
  let has_count : Ref[Int] = { val: 0 }
  let has_toggle = make_native_func(
    name="hasToggle",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      has_count.val += 1
      Bool(has_count.val == 1)
    },
  )
  let get_trap = make_native_func(
    name="get",
    realm_state=Some(interp.realm_state),
    fn(args) raise {
      match args {
        [_, Symbol(_), _] => Undefined
        [_, String_(_), _] => Number(30.0)
        _ => fail("get trap received an unexpected argument list")
      }
    },
  )
  let set_count : Ref[Int] = { val: 0 }
  let set_trap = make_native_func(
    name="set",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      set_count.val += 1
      Bool(true)
    },
  )
  let (proxy, scope) = issue933_proxy_scope(
    interp, has_toggle, get_trap, set_trap,
  )
  let probe = Issue933ReferenceProbe(
    ctx={ strict: false, current_generator: None },
    env=scope,
    name="vanishing",
    value=Number(31.0),
    loc=@token.Loc::default(),
    before_put=() => (),
  )
  let result = issue933_run_reference_probe(interp, probe)
  assert_eq(result.to_string(), "31")
  assert_eq(probe.read_value.unwrap().to_string(), "undefined")
  assert_eq(has_count.val, 3)
  assert_eq(set_count.val, 1)
  match proxy {
    Proxy(data) =>
      match data.target {
        Some(Object(target)) =>
          assert_true(!target.bag.properties.contains("vanishing"))
        _ => fail("Proxy target must remain available")
      }
    _ => fail("with binding must remain a Proxy")
  }

  let strict_count : Ref[Int] = { val: 0 }
  let strict_has = make_native_func(
    name="strictHasToggle",
    realm_state=Some(interp.realm_state),
    fn(_args) {
      strict_count.val += 1
      Bool(strict_count.val == 1)
    },
  )
  let (_, strict_scope) = issue933_proxy_scope(
    interp, strict_has, get_trap, set_trap,
  )
  let strict_result : Result[Value, Error] = Ok(
    issue933_run_reference_probe(
      interp,
      Issue933ReferenceProbe(
        ctx={ strict: true, current_generator: None },
        env=strict_scope,
        name="vanishing",
        value=Number(32.0),
        loc=@token.Loc::default(),
        before_put=() => (),
      ),
    ),
  ) catch {
    error => Err(error)
  }
  match strict_result {
    Err(error) =>
      match @errors.name_message_if_js_error(error) {
        Some((name, _)) => assert_eq(name, "ReferenceError")
        None => fail("strict disappearing binding must raise ReferenceError")
      }
    Ok(_) => fail("strict disappearing binding must not complete normally")
  }
  assert_eq(strict_count.val, 2)
}
