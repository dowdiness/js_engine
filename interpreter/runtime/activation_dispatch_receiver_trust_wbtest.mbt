///|
fn receiver_recursion_sealed_fixture(
  source_identity? : String? = None,
) -> (Interpreter, Array[@ast.Stmt], TrustedReceiverRecursionRegistry) raise {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = source_identity
  let stmts = @parser.parse(
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(256);",
    ).stmts
  let preflight = match
    interp.preflight_dispatchable_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected callback-free receiver preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let ctx : ExecContext = { strict: false, current_generator: None }
  let _ = interp.exec_stmt(ctx, stmts[0], interp.global)
  let _ = interp.exec_stmt(ctx, stmts[1], interp.global)
  let registry = interp.seal_receiver_recursion_registry(preflight, stmts)
  (interp, stmts, registry)
}

///|
fn receiver_recursion_rejection(
  action : () -> Unit raise InvalidActivationDispatchShell,
) -> String {
  try {
    action()
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
}

///|
test "receiver recursion trust preflight rejects existing names without effects" {
  let interp = Interpreter::new()
  interp.global.def("receiver", Number(0.0), LetBinding)
  let stmts = @parser.parse(
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(256);",
    ).stmts
  inspect(
    interp.preflight_dispatchable_receiver_recursion_program(stmts) is None,
    content="true",
  )
}

///|
test "receiver recursion trust seals the exact object and UserFunc identities" {
  let (interp, _, registry) = receiver_recursion_sealed_fixture()
  let receiver = registry.require_receiver(interp)
  let callee = registry.require_callee(interp, registry.trusted.callee)
  let _ = registry.require_call(interp, callee, receiver, [Number(256.0)])
  guard receiver is Object(receiver_data) else {
    fail("trusted receiver must remain an Object")
  }
  guard callee is Object(callee_data) else {
    fail("trusted callee must remain an Object")
  }
  inspect(receiver_data.class_name, content="Object")
  inspect(receiver_data.callable is None, content="true")
  inspect(callee_data.class_name, content="Function")
  match callee_data.callable {
    Some(UserFunc(data)) => {
      match data.name {
        Some(name) => inspect(name, content="step")
        None => fail("trusted UserFunc must retain its name")
      }
      inspect(data.params[0], content="n")
      inspect(data.body.length(), content="2")
    }
    _ => fail("trusted callee must retain its UserFunc capability")
  }
}

///|
test "receiver recursion trust rejects call envelope drift" {
  let (interp, _, registry) = receiver_recursion_sealed_fixture()
  for
    candidate_input in [
      (registry.trusted.callee, Undefined, [Number(256.0)]),
      (registry.trusted.callee, registry.trusted.receiver, []),
      (registry.trusted.callee, registry.trusted.receiver, [String_("256")]),
      (
        registry.trusted.callee,
        registry.trusted.receiver,
        [Number(256.0), Number(0.0)],
      ),
      (Undefined, registry.trusted.receiver, [Number(256.0)]),
    ] {
    let (candidate, this_value, args) = candidate_input
    inspect(
      receiver_recursion_rejection(() => {
        ignore(registry.require_call(interp, candidate, this_value, args))
      }),
      content="rejected",
    )
  }
}

///|
test "receiver recursion trust rejects receiver descriptor and value drift" {
  let (interp, _, registry) = receiver_recursion_sealed_fixture()
  guard registry.trusted.receiver is Object(receiver_data) else {
    fail("expected the sealed receiver object")
  }
  receiver_data.bag.descriptors[registry.plan.marker_name] = {
    writable: false,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  inspect(
    receiver_recursion_rejection(() => ignore(registry.require_receiver(interp))),
    content="rejected",
  )

  let (value_interp, _, value_registry) = receiver_recursion_sealed_fixture()
  guard value_registry.trusted.receiver is Object(value_receiver) else {
    fail("expected the sealed receiver object")
  }
  value_receiver.bag.properties[value_registry.plan.marker_name] = Number(1.0)
  inspect(
    receiver_recursion_rejection(() => {
      ignore(value_registry.require_receiver(value_interp))
    }),
    content="rejected",
  )

  let (callee_interp, _, callee_registry) = receiver_recursion_sealed_fixture()
  guard callee_registry.trusted.receiver is Object(callee_receiver) else {
    fail("expected the sealed receiver object")
  }
  callee_receiver.bag.properties[callee_registry.plan.property_name] = Number(
    0.0,
  )
  inspect(
    receiver_recursion_rejection(() => {
      ignore(callee_registry.require_receiver(callee_interp))
    }),
    content="rejected",
  )
}

///|
test "receiver recursion trust rejects function body drift" {
  let (body_interp, _, body_registry) = receiver_recursion_sealed_fixture()
  guard body_registry.trusted.callee
    is Object({ callable: Some(UserFunc(body_data)), .. }) else {
    fail("expected the sealed UserFunc")
  }
  body_data.body[0] = @parser.parse("return 0;").stmts[0]
  inspect(
    receiver_recursion_rejection(() => {
      ignore(body_registry.require_receiver(body_interp))
    }),
    content="rejected",
  )
}

///|
test "receiver recursion trust rejects source and realm metadata drift" {
  let (source_interp, _, source_registry) = receiver_recursion_sealed_fixture(
    source_identity=Some("sealed source"),
  )
  guard source_registry.trusted.callee is Object(source_data) &&
    source_data.bag.symbol_properties.get(
      FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID,
    )
    is Some(Array(source_metadata)) &&
    source_metadata.elements.length() > FUNCTION_SOURCE_IDENTITY_IDX else {
    fail("expected packed source metadata on the trusted function")
  }
  source_metadata.elements[FUNCTION_SOURCE_IDENTITY_IDX] = String_(
    "drifted source",
  )
  inspect(
    receiver_recursion_rejection(() => {
      ignore(
        source_registry.require_callee(
          source_interp,
          source_registry.trusted.callee,
        ),
      )
    }),
    content="rejected",
  )

  let (realm_interp, _, realm_registry) = receiver_recursion_sealed_fixture()
  guard realm_registry.trusted.callee is Object(realm_data) &&
    realm_data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID)
    is Some(Array(realm_metadata)) &&
    realm_metadata.elements.length() > REALM_PROTO_IDX_OBJECT else {
    fail("expected packed realm metadata on the trusted function")
  }
  realm_metadata.elements[REALM_PROTO_IDX_OBJECT] = make_object(
    Map([]),
    Null,
    None,
    "Object",
    Map([]),
    true,
  )
  inspect(
    receiver_recursion_rejection(() => {
      ignore(realm_registry.require_receiver(realm_interp))
    }),
    content="rejected",
  )
}
