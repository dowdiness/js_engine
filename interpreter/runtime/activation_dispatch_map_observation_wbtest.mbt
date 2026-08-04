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
const MAP_FORWARDING_OBSERVATION_SOURCE =
  #|function f(t) {
  #|  if (t === 0) return 0;
  #|  return u(t);
  #|}
  #|function u(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + [n - 1, 0].map(function(t) { return f(t); })[0];
  #|}
  #|u(256);

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
test "array map forwarding observations resume both indices and release LIFO" {
  let (interp, stmts, preflight) = map_observation_test_fixture_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
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
    _ => fail("expected the forwarding map fixture to complete normally")
  }
  // 256 step activations, plus two callback and two forwarding activations
  // for each step.
  inspect(probe.attempts, content="1280")
  inspect(probe.acquired, content="1280")
  inspect(probe.accepted, content="1280")
  inspect(probe.released, content="1280")
  inspect(probe.rejected, content="0")
  inspect(probe.denied, content="0")
  inspect(probe.active, content="0")
  inspect(probe.maximum_active, content="768")
  inspect(probe.lifo_violations, content="0")
  inspect(probe.active_ordinals.length(), content="0")
  inspect(probe.release_ordinals.length(), content="1280")
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
test "array map forwarding function body drift rejects before executing" {
  let (interp, stmts, preflight) = map_observation_test_fixture_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
  )
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
  )
  match
    shell.drive_root_program(stmts, { strict: false, current_generator: None }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the exact forwarding map setup run to complete")
  }
  let registry = interp.seal_array_map_recursion_registry(preflight, stmts)
  shell.array_map_registry = Some(registry)
  match registry.forward_function {
    Some(Object({ callable: Some(UserFunc(data)), .. })) => {
      let original = data.body[1]
      data.body[1] = @parser.parse("return u(0);").stmts[0]
      let request = DispatchCallRequest(
        callee=registry.forward_function.unwrap(),
        this_value=Undefined,
        args=[Number(1.0)],
        loc=preflight.plan.forward_callback_call_loc,
      )
      let result = try {
        let _ = shell.enter_array_map_call(request)
        "accepted"
      } catch {
        InvalidActivationDispatchShell(message) => message
      }
      data.body[1] = original
      inspect(
        result,
        content="array map forwarding activation changed after sealing",
      )
      inspect(shell.cleanup_stack.length(), content="0")
    }
    _ => fail("expected the forwarding function to retain UserFunc data")
  }
}

///|
test "array map forwarding function closure drift rejects before executing" {
  let (interp, stmts, preflight) = map_observation_test_fixture_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
  )
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
  )
  match
    shell.drive_root_program(stmts, { strict: false, current_generator: None }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the exact forwarding map setup run to complete")
  }
  let registry = interp.seal_array_map_recursion_registry(preflight, stmts)
  shell.array_map_registry = Some(registry)
  match registry.forward_function {
    Some(original) => {
      let lookalike = match original {
        Object(object_data) =>
          match object_data.callable {
            Some(UserFunc(data)) =>
              Object({
                ..object_data,
                callable: Some(
                  UserFunc({ ..data, closure: Environment::new() }),
                ),
              })
            _ => fail("expected a forwarding UserFunc callable")
          }
        _ => fail("expected an object forwarding function")
      }
      let mutated_registry = { ..registry, forward_function: Some(lookalike) }
      shell.array_map_registry = Some(mutated_registry)
      match interp.global.bindings.get("f") {
        Some(binding) => binding.value = lookalike
        None => fail("expected the forwarding global binding")
      }
      let request = DispatchCallRequest(
        callee=lookalike,
        this_value=Undefined,
        args=[Number(1.0)],
        loc=preflight.plan.forward_callback_call_loc,
      )
      let result = try {
        let _ = shell.enter_array_map_call(request)
        "accepted"
      } catch {
        InvalidActivationDispatchShell(message) => message
      }
      match interp.global.bindings.get("f") {
        Some(binding) => binding.value = original
        None => fail("expected the forwarding global binding")
      }
      inspect(
        result,
        content="array map forwarding UserFunc provenance changed after sealing",
      )
      inspect(shell.cleanup_stack.length(), content="0")
    }
    None => fail("expected the forwarding function to remain retained")
  }
}

///|
test "array map forwarding requests own arguments in source order" {
  let (interp, stmts, preflight) = map_observation_test_fixture_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
  )
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
  )
  match
    shell.drive_root_program(stmts, { strict: false, current_generator: None }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the exact forwarding map setup run to complete")
  }
  let registry = interp.seal_array_map_recursion_registry(preflight, stmts)
  shell.array_map_registry = Some(registry)
  let callback_stmt = match stmts[1] {
    @ast.FuncDecl(
      _,
      _,
      [
        _,
        @ast.ReturnStmt(
          Some(
            @ast.Binary(
              @ast.Add,
              _,
              @ast.ComputedMember(
                @ast.Call(
                  @ast.Member(@ast.ArrayLit(_, _), _, _),
                  [@ast.FuncExpr(_, _, [stmt], _, _)],
                  _
                ),
                _,
                _
              ),
              _
            )
          ),
          _
        ),
      ],
      _,
      _
    ) => stmt
    _ => fail("expected the forwarding callback body statement")
  }
  let callback_env = Environment::new(parent=Some(interp.global))
  callback_env.is_var_scope = true
  ignore(callback_env.def_parameter("t", Number(7.0)))
  let callback_result = Ok(
    shell.execute_array_map_body_statement(
      {
        ctx: { strict: false, current_generator: None },
        stmt: callback_stmt,
        env: callback_env,
        index: 0,
      },
      registry,
    ),
  ) catch {
    InvalidActivationDispatchShell(message) => Err(message)
  }
  let callback_result = match callback_result {
    Ok(result) => result
    Err(message) => fail("forwarding callback request setup failed: " + message)
  }
  let callback_request = match callback_result {
    DispatchWorkSuspended(DispatchSuspendCall(request, DispatchCompleteReturn)) =>
      request
    _ => fail("forwarding callback must suspend at its f(t) call")
  }
  guard callback_request.this_value is Undefined else {
    fail("forwarding callback must call f with undefined this")
  }
  guard callback_request.args.length() == 1 else {
    fail("forwarding callback must own one argument")
  }
  match callback_request.args[0] {
    Number(value) => inspect(value, content="7")
    _ => fail("forwarding callback argument must preserve t")
  }
  guard callback_request.loc == preflight.plan.forward_callback_call_loc else {
    fail("forwarding callback request changed source order location")
  }
  guard registry.forward_function is Some(forward_function) &&
    array_map_value_identity_matches(callback_request.callee, forward_function) else {
    fail("forwarding callback request changed its retained f callee")
  }

  let forward_stmt = match registry.forward_function {
    Some(Object({ callable: Some(UserFunc(data)), .. })) => data.body[1]
    _ => fail("expected the retained forwarding function body")
  }
  let forward_env = Environment::new(parent=Some(interp.global))
  forward_env.is_var_scope = true
  ignore(forward_env.def_parameter("t", Number(7.0)))
  let forward_result = Ok(
    shell.execute_array_map_body_statement(
      {
        ctx: { strict: false, current_generator: None },
        stmt: forward_stmt,
        env: forward_env,
        index: 1,
      },
      registry,
    ),
  ) catch {
    InvalidActivationDispatchShell(message) => Err(message)
  }
  let forward_result = match forward_result {
    Ok(result) => result
    Err(message) => fail("forwarding function request setup failed: " + message)
  }
  let forward_request = match forward_result {
    DispatchWorkSuspended(DispatchSuspendCall(request, DispatchCompleteReturn)) =>
      request
    _ => fail("forwarding function must suspend at its u(t) call")
  }
  guard forward_request.this_value is Undefined else {
    fail("forwarding function must call u with undefined this")
  }
  guard forward_request.args.length() == 1 else {
    fail("forwarding function must own one argument")
  }
  match forward_request.args[0] {
    Number(value) => inspect(value, content="7")
    _ => fail("forwarding function argument must preserve t")
  }
  guard forward_request.loc == preflight.plan.forward_call_loc else {
    fail("forwarding function request changed source order location")
  }
  guard array_map_value_identity_matches(
    forward_request.callee,
    registry.step_function,
  ) else {
    fail("forwarding function request changed its retained u callee")
  }
  guard !physical_equal(callback_request.args, forward_request.args) else {
    fail("forwarding requests must own distinct argument arrays")
  }
}

///|
test "array map forwarding step body drift rejects before executing" {
  let (interp, stmts, preflight) = map_observation_test_fixture_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
  )
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
  )
  match
    shell.drive_root_program(stmts, { strict: false, current_generator: None }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the exact forwarding map setup run to complete")
  }
  let registry = interp.seal_array_map_recursion_registry(preflight, stmts)
  shell.array_map_registry = Some(registry)
  match registry.step_function {
    Object({ callable: Some(UserFunc(data)), .. }) => {
      let original = data.body[0]
      data.body[0] = @parser.parse("if(n===1)return 9;").stmts[0]
      let request = DispatchCallRequest(
        callee=registry.step_function,
        this_value=Undefined,
        args=[Number(256.0)],
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
        content="array map forwarding step activation body changed after sealing",
      )
      inspect(shell.cleanup_stack.length(), content="0")
    }
    _ => fail("expected the forwarding step function to retain UserFunc data")
  }
}

///|
test "array map forwarding callback body drift rejects before executing" {
  let (interp, stmts, preflight) = map_observation_test_fixture_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
  )
  let shell = PrimitiveProgramDispatchShell(
    interp,
    array_map_root_preflight=Some(preflight),
    array_map_root_stmts=Some(stmts),
  )
  match
    shell.drive_root_program(stmts, { strict: false, current_generator: None }) {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("expected the exact forwarding map setup run to complete")
  }
  let registry = interp.seal_array_map_recursion_registry(preflight, stmts)
  shell.array_map_registry = Some(registry)
  let callback_expr = match
    @parser.parse("(function(t){return f(t);});").stmts[0] {
    @ast.ExprStmt(expr, _) => expr
    _ => fail("expected a callback function expression")
  }
  let callback = interp.eval_expr(
    { strict: false, current_generator: None },
    callback_expr,
    interp.global,
  )
  let receiver = make_array([Number(1.0), Number(0.0)])
  let state = MapState(
    length=2L,
    receiver~,
    result=make_array([]),
    callback~,
    this_arg=Undefined,
    pending_result_consumer=DispatchCompleteReturn,
  )
  shell.array_map_states.push(state)
  shell.array_map_activation_envs.push(interp.global)
  match callback {
    Object({ callable: Some(UserFunc(data)), .. }) => {
      let original = data.body[0]
      data.body[0] = @parser.parse("return f(0);").stmts[0]
      let request = DispatchCallRequest(
        callee=callback,
        this_value=Undefined,
        args=[Number(1.0), Number(0.0), receiver],
        loc=preflight.plan.callback_call_loc,
      )
      let result = try {
        let _ = shell.enter_array_map_call(request)
        "accepted"
      } catch {
        InvalidActivationDispatchShell(message) => message
      }
      data.body[0] = original
      let _ = shell.array_map_states.pop()
      let _ = shell.array_map_activation_envs.pop()
      inspect(
        result,
        content="array map forwarding callback body changed after sealing",
      )
      inspect(shell.cleanup_stack.length(), content="0")
    }
    _ => fail("expected the forwarding callback to retain UserFunc data")
  }
}

///|
test "array map forwarding receiver admission rejects data drift" {
  let (interp, _stmts, preflight) = map_observation_test_fixture_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
  )
  let good = make_array([Number(1.0), Number(0.0)])
  inspect(
    array_map_receiver_is_exact_for_plan(
      interp,
      good,
      preflight.expected_array_prototype,
      preflight.plan,
    ),
    content="true",
  )
  let wrong_length = make_array([Number(1.0)])
  inspect(
    array_map_receiver_is_exact_for_plan(
      interp,
      wrong_length,
      preflight.expected_array_prototype,
      preflight.plan,
    ),
    content="false",
  )
  let with_hole = make_array([Number(1.0), Number(0.0)])
  match with_hole {
    Array(data) => data.holes[1] = ()
    _ => fail("expected forwarding receiver array")
  }
  inspect(
    array_map_receiver_is_exact_for_plan(
      interp,
      with_hole,
      preflight.expected_array_prototype,
      preflight.plan,
    ),
    content="false",
  )
  let with_property = make_array([Number(1.0), Number(0.0)])
  match with_property {
    Array(data) => data.bag.properties["extra"] = Number(1.0)
    _ => fail("expected forwarding receiver array")
  }
  inspect(
    array_map_receiver_is_exact_for_plan(
      interp,
      with_property,
      preflight.expected_array_prototype,
      preflight.plan,
    ),
    content="false",
  )
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

///|
test "array map forwarding execution-control budget charges each observation once" {
  let (normal, remaining, cleanup, states, envs) = map_observation_control_run_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
    10242L,
  )
  match normal {
    DispatchNormal(Number(value)) => inspect(value, content="256")
    _ => fail("forwarding map budget must complete normally")
  }
  inspect(remaining, content="0")
  inspect(cleanup, content="0")
  inspect(states, content="0")
  inspect(envs, content="0")
  let (short, remaining, cleanup, states, envs) = map_observation_control_run_for_source(
    MAP_FORWARDING_OBSERVATION_SOURCE,
    10241L,
  )
  match short {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ =>
      fail("one-short forwarding budget must stop at the observation boundary")
  }
  inspect(remaining, content="0")
  inspect(cleanup, content="0")
  inspect(states, content="0")
  inspect(envs, content="0")
}
