///|
const MAP_OBSERVATION_SOURCE =
  #|function step(n) {
  #|  if (n === 0) return 0;
  #|  var items = [{next: function() { return step(n - 1); }}];
  #|  return 1 + items.map(function(t) { return t.next(); })[0];
  #|}
  #|step(256);

///|
const MAP_DIRECT_OBSERVATION_SOURCE =
  #|function u(t,e,f){
  #|  if (t === 0) return 0;
  #|  return 1 + [e].map(function(e) { return u(t - 1, e, !f); })[0];
  #|}
  #|u(256,0,false);

///|
fn map_observation_array_construct(
  _interp : Interpreter,
  args : Array[Value],
) -> Value raise Error {
  if args.length() < 0 {
    raise @errors.TypeError(message="unreachable map observation constructor")
  }
  make_array([])
}

///|
fn map_observation_species_getter(
  this_val : Value,
  _args : Array[Value],
) -> Value {
  this_val
}

///|
fn map_observation_test_fixture_for_source(
  source : String,
) -> (Interpreter, Array[@ast.Stmt], ArrayMapRecursionPreflight) raise Error {
  let interp = Interpreter::new()
  let map_method = make_interp_method_func(
    name="map",
    realm_state=Some(interp.realm_state),
    fn(_interp, _this_val, _args) { Undefined },
  )
  let array_proto = make_object(
    { "map": map_method },
    Null,
    None,
    "Array",
    Map([]),
    true,
  )
  interp.realm_state.array_prototype.val = Some(array_proto)
  let species_getter = make_method_func(
    name="get [Symbol.species]",
    realm_state=Some(interp.realm_state),
    fn(this_val, args) { map_observation_species_getter(this_val, args) },
  )
  let array_constructor = Object({
    bag: PropertyBag(),
    prototype: Null,
    callable: Some(
      ConstructorOnlyCallable("Array", map_observation_array_construct),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  match array_constructor {
    Object(ctor_data) => {
      install_builtin_symbol_accessor(
        ctor_data,
        interp.realm_state.well_known_symbols.species.id,
        species_getter,
      )
      match array_proto {
        Object(proto_data) => {
          install_builtin_method(proto_data, "map", map_method)
          install_builtin_method(proto_data, "constructor", array_constructor)
        }
        _ => ()
      }
    }
    _ => ()
  }
  interp.global.def_builtin("Array", array_constructor)
  let stmts = @parser.parse(source).stmts
  let preflight = match
    interp.preflight_dispatchable_array_map_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the map observation fixture to preflight")
  }
  (interp, stmts, preflight)
}

///|
fn map_observation_test_fixture() -> (
  Interpreter,
  Array[@ast.Stmt],
  ArrayMapRecursionPreflight,
) raise Error {
  map_observation_test_fixture_for_source(MAP_OBSERVATION_SOURCE)
}

///|
test "array map observations accept and release each managed activation once" {
  let (interp, stmts, preflight) = map_observation_test_fixture()
  let probe = DispatchObservationProbe()
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
    activation_observation_port=probe.port(),
  )
  let ctx : ExecContext = { strict: false, current_generator: None }
  match shell.drive_root_program(stmts, ctx) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the exact map fixture to complete normally")
  }
  // 257 step activations (256..0), plus one callback and one member
  // activation for each non-base step.
  inspect(probe.attempts, content="769")
  inspect(probe.acquired, content="769")
  inspect(probe.accepted, content="769")
  inspect(probe.released, content="769")
  inspect(probe.rejected, content="0")
  inspect(probe.denied, content="0")
  inspect(probe.active, content="0")
  inspect(probe.maximum_active, content="769")
  inspect(probe.release_ordinals.length(), content="769")
  for i in 0..<probe.release_ordinals.length() {
    if probe.release_ordinals[i] != 769 - i {
      fail("map activation cleanup was not strict LIFO")
    }
  }
  inspect(shell.cleanup_stack.length(), content="0")
  inspect(shell.array_map_registry is None, content="true")
  inspect(shell.array_map_states.is_empty(), content="true")
  inspect(shell.array_map_activation_envs.is_empty(), content="true")
}

///|
test "array map direct observations accept and release each activation once" {
  let (interp, stmts, preflight) = map_observation_test_fixture_for_source(
    MAP_DIRECT_OBSERVATION_SOURCE,
  )
  let probe = DispatchObservationProbe()
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
    activation_observation_port=probe.port(),
  )
  match
    shell.drive_root_program(stmts, { strict: false, current_generator: None }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the exact direct map fixture to complete normally")
  }
  // 257 direct callee activations (256..0) and one callback for each
  // non-base step.
  inspect(probe.attempts, content="513")
  inspect(probe.acquired, content="513")
  inspect(probe.accepted, content="513")
  inspect(probe.released, content="513")
  inspect(probe.rejected, content="0")
  inspect(probe.denied, content="0")
  inspect(probe.active, content="0")
  inspect(probe.maximum_active, content="513")
  inspect(probe.release_ordinals.length(), content="513")
  for i in 0..<probe.release_ordinals.length() {
    if probe.release_ordinals[i] != 513 - i {
      fail("direct map activation cleanup was not strict LIFO")
    }
  }
  inspect(shell.cleanup_stack.length(), content="0")
  inspect(shell.array_map_registry is None, content="true")
  inspect(shell.array_map_states.is_empty(), content="true")
  inspect(shell.array_map_activation_envs.is_empty(), content="true")
}

///|
test "array map direct post-seal body drift rejects before executing" {
  let (interp, stmts, preflight) = map_observation_test_fixture_for_source(
    MAP_DIRECT_OBSERVATION_SOURCE,
  )
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
  )
  match
    shell.drive_root_program(stmts, { strict: false, current_generator: None }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the exact direct map setup run to complete")
  }
  let registry = interp.seal_array_map_recursion_registry(preflight, stmts)
  shell.array_map_registry = Some(registry)
  let replacement = @parser.parse("if(t===1)return 9;").stmts[0]
  match registry.step_function {
    Object({ callable: Some(UserFunc(data)), .. }) => {
      let original = data.body[0]
      data.body[0] = replacement
      let request = DispatchCallRequest(
        callee=registry.step_function,
        this_value=Undefined,
        args=[Number(256.0), Number(0.0), Bool(false)],
        loc=preflight.plan.root_call_loc,
      )
      let result = try {
        let _ = shell.enter_array_map_call(request)
        "accepted"
      } catch {
        InvalidActivationDispatchShell(message) => message
      }
      data.body[0] = original
      inspect(
        result,
        content="array map direct step activation body changed after sealing",
      )
      inspect(shell.cleanup_stack.length(), content="0")
      inspect(shell.array_map_states.is_empty(), content="true")
      inspect(shell.array_map_activation_envs.is_empty(), content="true")
    }
    _ => fail("expected the direct step function to retain UserFunc data")
  }
}

///|
test "array map admission rejects prior constructor and species drift" {
  let (interp, stmts, preflight) = map_observation_test_fixture()
  let probe = DispatchObservationProbe()
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
    activation_observation_port=probe.port(),
  )
  match
    shell.drive_root_program(stmts, { strict: false, current_generator: None }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the prior exact map run to complete")
  }
  match interp.realm_state.get_array_proto() {
    Object(proto_data) =>
      match proto_data.bag.descriptors.get("constructor") {
        Some(desc) =>
          proto_data.bag.descriptors["constructor"] = {
            ..desc,
            configurable: false,
          }
        None => fail("expected the canonical constructor descriptor")
      }
    _ => fail("expected the canonical Array prototype object")
  }
  inspect(
    interp.preflight_dispatchable_array_map_recursion_program(stmts) is None,
    content="true",
  )

  let (species_interp, species_stmts, species_preflight) = map_observation_test_fixture()
  let species_shell = PrimitiveProgramDispatchShell(
    species_interp,
    array_map_root_preflight=Some(species_preflight),
    array_map_root_stmts=Some(species_stmts),
  )
  match
    species_shell.drive_root_program(species_stmts, {
      strict: false,
      current_generator: None,
    }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the prior exact species run to complete")
  }
  match species_interp.global.bindings.get("Array") {
    Some(binding) =>
      match binding.value {
        Object(ctor_data) => {
          let species_sym = species_interp.realm_state.well_known_symbols.species
          match ctor_data.bag.symbol_descriptors.get(species_sym.id) {
            Some(desc) =>
              ctor_data.bag.symbol_descriptors[species_sym.id] = {
                ..desc,
                configurable: false,
              }
            None => fail("expected the canonical species descriptor")
          }
        }
        _ => fail("expected the canonical Array constructor object")
      }
    None => fail("expected the canonical Array constructor binding")
  }
  inspect(
    species_interp.preflight_dispatchable_array_map_recursion_program(
      species_stmts,
    )
    is None,
    content="true",
  )
}

///|
test "array map shell abort preserves guest identity and pops state" {
  let (interp, stmts, preflight) = map_observation_test_fixture()
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
  )
  match
    shell.drive_root_program(stmts, { strict: false, current_generator: None }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the exact map setup run to complete")
  }
  let registry = interp.seal_array_map_recursion_registry(preflight, stmts)
  shell.array_map_registry = Some(registry)
  let length = 1L
  let initial_state = MapState(
    length~,
    receiver=make_array([Number(1.0)]),
    result=make_array([]),
    callback=registry.step_function,
    this_arg=Undefined,
    pending_result_consumer=DispatchCompleteReturn,
  )
  let (awaiting, _) = reduce_array_map(initial_state, MapStart)
  shell.array_map_states.push(awaiting)
  shell.array_map_activation_envs.push(interp.global)
  let marker = make_array([String_("shell abort marker")])
  let completion = shell.perform_array_map_event(
    awaiting,
    MapAbrupt(JsException(marker)),
  )
  match completion {
    DispatchWorkCompleted(DispatchThrow(JsException(actual))) =>
      match (marker, actual) {
        (Array(expected_data), Array(actual_data)) =>
          if !physical_equal(expected_data, actual_data) {
            fail("shell map abort changed the guest throw identity")
          }
        _ => fail("shell map abort lost the guest throw value")
      }
    _ => fail("shell map abort must return the guest throw completion")
  }
  inspect(shell.cleanup_stack.length(), content="0")
  inspect(shell.array_map_states.is_empty(), content="true")
  inspect(shell.array_map_activation_envs.is_empty(), content="true")
  let recovery_preflight = match
    interp.preflight_dispatchable_array_map_recursion_program(stmts) {
    Some(value) => value
    None => fail("same-Interpreter map recovery lost exact admission")
  }
  let recovery_shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(recovery_preflight),
    array_map_root_stmts=Some(stmts),
  )
  match
    recovery_shell.drive_root_program(stmts, {
      strict: false,
      current_generator: None,
    }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("same-Interpreter map recovery did not complete")
  }
}

///|
test "array map accessor drift invokes getter on renewed exact run" {
  let (interp, stmts, preflight) = map_observation_test_fixture()
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
  )
  match
    shell.drive_root_program(stmts, { strict: false, current_generator: None }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the first exact map run to complete")
  }
  let marker = make_array([String_("map accessor marker")])
  let map_getter = make_method_func(
    name="get map",
    realm_state=Some(interp.realm_state),
    fn(_this_val, _args) raise { raise JsException(marker) },
  )
  match interp.realm_state.get_array_proto() {
    Object(proto_data) =>
      match proto_data.bag.descriptors.get("map") {
        Some(desc) =>
          proto_data.bag.descriptors["map"] = {
            ..desc,
            writable: false,
            getter: Some(map_getter),
            setter: None,
            is_accessor: true,
          }
        None => fail("expected the canonical map descriptor")
      }
    _ => fail("expected the canonical Array prototype object")
  }
  let thrown = try {
    ignore(interp.run(stmts))
    fail("expected the drifted Array.prototype.map getter to throw")
  } catch {
    JsException(value) => value
    error =>
      fail(
        "expected the drifted map getter to throw a guest value: " +
        error.to_string(),
      )
  }
  match (marker, thrown) {
    (Array(expected_data), Array(actual_data)) =>
      if !physical_equal(expected_data, actual_data) {
        fail("drifted map getter changed the guest throw identity")
      }
    _ => fail("drifted map getter did not preserve the marker object")
  }
}

///|
test "array map direct accessor drift preserves guest abrupt identity" {
  let (interp, stmts, _) = map_observation_test_fixture_for_source(
    MAP_DIRECT_OBSERVATION_SOURCE,
  )
  match interp.realm_state.get_array_proto() {
    Object(proto_data) =>
      match proto_data.bag.descriptors.get("map") {
        Some(original_desc) => {
          let marker = make_array([String_("direct map accessor marker")])
          let map_getter = make_method_func(
            name="get map",
            realm_state=Some(interp.realm_state),
            fn(_this_val, _args) raise { raise JsException(marker) },
          )
          proto_data.bag.descriptors["map"] = {
            ..original_desc,
            writable: false,
            getter: Some(map_getter),
            setter: None,
            is_accessor: true,
          }
          let thrown = try {
            ignore(interp.run(stmts))
            fail("expected the drifted direct map getter to throw")
          } catch {
            JsException(value) => value
            error =>
              fail("expected a direct map guest throw: " + error.to_string())
          }
          match (marker, thrown) {
            (Array(expected_data), Array(actual_data)) =>
              if !physical_equal(expected_data, actual_data) {
                fail("direct map getter changed the guest throw identity")
              }
            _ => fail("direct map getter lost the marker object")
          }
          proto_data.bag.descriptors["map"] = original_desc
        }
        None => fail("expected the canonical map descriptor")
      }
    _ => fail("expected the canonical Array prototype object")
  }
  let recovery_preflight = match
    interp.preflight_dispatchable_array_map_recursion_program(stmts) {
    Some(value) => value
    None => fail("direct map recovery lost exact admission")
  }
  let recovery_shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(recovery_preflight),
    array_map_root_stmts=Some(stmts),
  )
  match
    recovery_shell.drive_root_program(stmts, {
      strict: false,
      current_generator: None,
    }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("direct map recovery did not complete")
  }
}

///|
fn map_observation_control_run_for_source(
  source : String,
  remaining_steps : Int64,
) -> (DispatchCompletion, Int64, Int, Int, Int) raise Error {
  let (interp, stmts, preflight) = map_observation_test_fixture_for_source(
    source,
  )
  let control = ExecutionControl(
    remaining_steps~,
    maximum_active_depth=1024,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = interp.with_execution_control(control, () => {
    let shell = PrimitiveProgramDispatchShell(
      interp,
      array_map_root_preflight=Some(preflight),
      array_map_root_stmts=Some(stmts),
      activation_observation_port=interp.execution_control_activation_observation_port(),
    )
    let ctx : ExecContext = { strict: false, current_generator: None }
    let completion = shell.drive_root_program(stmts, ctx)
    (
      completion,
      shell.cleanup_stack.length(),
      shell.array_map_states.length(),
      shell.array_map_activation_envs.length(),
    )
  })
  let (completion, cleanup_length, state_length, env_length) = result
  (
    completion,
    control.remaining_steps(),
    cleanup_length,
    state_length,
    env_length,
  )
}

///|
fn map_observation_control_run(
  remaining_steps : Int64,
) -> (DispatchCompletion, Int64, Int, Int, Int) raise Error {
  map_observation_control_run_for_source(
    MAP_OBSERVATION_SOURCE,
    remaining_steps,
  )
}

///|
test "array map execution-control budget charges each observation once" {
  let (normal, remaining, cleanup, states, envs) = map_observation_control_run(
    5643L,
  )
  match normal {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("exact map budget must complete normally")
  }
  inspect(remaining, content="0")
  inspect(cleanup, content="0")
  inspect(states, content="0")
  inspect(envs, content="0")
  let (short, remaining, cleanup, states, envs) = map_observation_control_run(
    5642L,
  )
  match short {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ =>
      fail("one-short map budget must stop at the exact observation boundary")
  }
  inspect(remaining, content="0")
  inspect(cleanup, content="0")
  inspect(states, content="0")
  inspect(envs, content="0")
}

///|
test "array map direct execution-control budget charges each observation once" {
  let (normal, remaining, cleanup, states, envs) = map_observation_control_run_for_source(
    MAP_DIRECT_OBSERVATION_SOURCE,
    4363L,
  )
  match normal {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("direct map budget must complete normally")
  }
  inspect(remaining, content="0")
  inspect(cleanup, content="0")
  inspect(states, content="0")
  inspect(envs, content="0")
  let (short, remaining, cleanup, states, envs) = map_observation_control_run_for_source(
    MAP_DIRECT_OBSERVATION_SOURCE,
    4362L,
  )
  match short {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ =>
      fail("one-short direct map budget must stop at the observation boundary")
  }
  inspect(remaining, content="0")
  inspect(cleanup, content="0")
  inspect(states, content="0")
  inspect(envs, content="0")
}
