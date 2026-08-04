///|
const MAP_OBSERVATION_SOURCE =
  #|function step(n) {
  #|  if (n === 0) return 0;
  #|  var items = [{next: function() { return step(n - 1); }}];
  #|  return 1 + items.map(function(t) { return t.next(); })[0];
  #|}
  #|step(256);

///|
fn map_observation_test_fixture() -> (
  Interpreter,
  Array[@ast.Stmt],
  ArrayMapRecursionPreflight,
) raise Error {
  let interp = Interpreter::new()
  let map_method = make_native_func(
    name="map",
    realm_state=Some(interp.realm_state),
    _args => Undefined,
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
  let array_constructor = make_native_func(
    name="Array",
    realm_state=Some(interp.realm_state),
    _args => make_array([]),
  )
  interp.global.def_builtin("Array", array_constructor)
  let stmts = @parser.parse(MAP_OBSERVATION_SOURCE).stmts
  let preflight = match
    interp.preflight_dispatchable_array_map_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the map observation fixture to preflight")
  }
  (interp, stmts, preflight)
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
fn map_observation_control_run(
  remaining_steps : Int64,
) -> (DispatchCompletion, Int64, Int, Int, Int) raise Error {
  let (interp, stmts, preflight) = map_observation_test_fixture()
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
