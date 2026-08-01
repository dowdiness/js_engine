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
fn receiver_recursion_computed_sealed_fixture(
  source_identity? : String? = None,
) -> (Interpreter, Array[@ast.Stmt], TrustedReceiverRecursionRegistry) raise {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = source_identity
  let stmts = @parser.parse(
      "function step(n){if(n===0)return this[\"marker\"];return 1+this[\"step\"](n-1);}" +
      "let receiver={[\"marker\"]:0,[\"step\"]:step};receiver[\"step\"](256);",
    ).stmts
  let preflight = match
    interp.preflight_dispatchable_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected callback-free computed receiver preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let ctx : ExecContext = { strict: false, current_generator: None }
  let _ = interp.exec_stmt(ctx, stmts[0], interp.global)
  let _ = interp.exec_stmt(ctx, stmts[1], interp.global)
  let registry = interp.seal_receiver_recursion_registry(preflight, stmts)
  (interp, stmts, registry)
}

///|
fn receiver_recursion_escaped_computed_sealed_fixture(
  source_identity? : String? = None,
) -> (Interpreter, Array[@ast.Stmt], TrustedReceiverRecursionRegistry) raise {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = source_identity
  let stmts = @parser.parse(
      "function step(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x73tep\"](n-1);}" +
      "let receiver={[\"\\x6darker\"]:0,[\"\\x73tep\"]:step};receiver[\"\\x73tep\"](256);",
    ).stmts
  let preflight = match
    interp.preflight_dispatchable_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected callback-free escaped computed receiver preflight")
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
fn receiver_recursion_recipe_with_access(
  original : ReceiverRecursionExpressionRecipe,
  drift_index : Int,
) -> ReceiverRecursionExpressionRecipe {
  let static_access = ReceiverRecursionStatic
  ReceiverRecursionExpressionRecipe(
    base_condition_loc=original.base_condition_loc,
    marker_property_access=if drift_index == 0 {
      static_access
    } else {
      original.marker_property_access
    },
    marker_member_loc=original.marker_member_loc,
    marker_access=if drift_index == 1 {
      static_access
    } else {
      original.marker_access
    },
    recursive_add_loc=original.recursive_add_loc,
    property_access=if drift_index == 2 {
      static_access
    } else {
      original.property_access
    },
    recursive_member_loc=original.recursive_member_loc,
    recursive_access=if drift_index == 3 {
      static_access
    } else {
      original.recursive_access
    },
    recursive_call_loc=original.recursive_call_loc,
    recursive_subtract_loc=original.recursive_subtract_loc,
    root_access=if drift_index == 4 {
      static_access
    } else {
      original.root_access
    },
    root_member_loc=original.root_member_loc,
  )
}

///|
fn receiver_recursion_access_with_escape(
  access : ReceiverRecursionAccessKind,
  has_escape : Bool,
) -> ReceiverRecursionAccessKind {
  match access {
    ReceiverRecursionStatic => ReceiverRecursionStatic
    ReceiverRecursionComputedLiteral(loc, _) =>
      ReceiverRecursionComputedLiteral(loc, has_escape)
  }
}

///|
fn receiver_recursion_recipe_with_escape(
  original : ReceiverRecursionExpressionRecipe,
  drift_index : Int,
) -> ReceiverRecursionExpressionRecipe {
  let drifted = (access : ReceiverRecursionAccessKind) =>
    receiver_recursion_access_with_escape(access, false)
  ReceiverRecursionExpressionRecipe(
    base_condition_loc=original.base_condition_loc,
    marker_property_access=if drift_index == 0 {
      drifted(original.marker_property_access)
    } else {
      original.marker_property_access
    },
    marker_member_loc=original.marker_member_loc,
    marker_access=if drift_index == 1 {
      drifted(original.marker_access)
    } else {
      original.marker_access
    },
    recursive_add_loc=original.recursive_add_loc,
    property_access=if drift_index == 2 {
      drifted(original.property_access)
    } else {
      original.property_access
    },
    recursive_member_loc=original.recursive_member_loc,
    recursive_access=if drift_index == 3 {
      drifted(original.recursive_access)
    } else {
      original.recursive_access
    },
    recursive_call_loc=original.recursive_call_loc,
    recursive_subtract_loc=original.recursive_subtract_loc,
    root_access=if drift_index == 4 {
      drifted(original.root_access)
    } else {
      original.root_access
    },
    root_member_loc=original.root_member_loc,
  )
}

///|
fn receiver_recursion_drift_computed_property_key(
  stmts : Array[@ast.Stmt],
  key_loc : @token.Loc,
) -> Unit raise {
  guard stmts[1] is @ast.VarDecl(_, _, Some(@ast.ObjectLit(properties, _)), _) else {
    fail("expected the receiver object declaration")
  }
  let property = properties[1]
  properties[1] = {
    ..property,
    key: @ast.StringLit("step", false, @token.LexForm::LexNormal, key_loc),
  }
}

///|
fn receiver_recursion_toggle_escaped_access(
  stmts : Array[@ast.Stmt],
  drift_index : Int,
) -> Unit raise {
  fn toggle_key(key : @ast.Expr) -> @ast.Expr raise {
    match key {
      @ast.StringLit(name, _, lex_form, key_loc) =>
        @ast.StringLit(name, false, lex_form, key_loc)
      _ => fail("expected an escaped string key")
    }
  }
  if drift_index == 0 || drift_index == 2 {
    guard stmts[1] is @ast.VarDecl(_, _, Some(@ast.ObjectLit(properties, _)), _) else {
      fail("expected the receiver object declaration")
    }
    let property_index = if drift_index == 0 { 0 } else { 1 }
    let property = properties[property_index]
    properties[property_index] = { ..property, key: toggle_key(property.key) }
  } else if drift_index == 1 || drift_index == 3 {
    guard stmts[0] is @ast.FuncDecl(_, _, body, _, _) else {
      fail("expected the receiver function declaration")
    }
    if drift_index == 1 {
      match body[0] {
        @ast.IfStmt(
          condition,
          @ast.ReturnStmt(
            Some(@ast.ComputedMember(base, key, member_loc)),
            return_loc,
          ),
          alternate,
          stmt_loc
        ) => {
          body[0] = @ast.IfStmt(
            condition,
            @ast.ReturnStmt(
              Some(@ast.ComputedMember(base, toggle_key(key), member_loc)),
              return_loc,
            ),
            alternate,
            stmt_loc,
          )
        }
        _ => fail("expected the escaped marker member")
      }
    } else {
      match body[1] {
        @ast.ReturnStmt(
          Some(
            @ast.Binary(
              op,
              increment,
              @ast.Call(
                @ast.ComputedMember(base, key, member_loc),
                args,
                call_loc,
              ),
              add_loc,
            ),
          ),
          return_loc,
        ) => {
          body[1] = @ast.ReturnStmt(
            Some(
              @ast.Binary(
                op,
                increment,
                @ast.Call(
                  @ast.ComputedMember(base, toggle_key(key), member_loc),
                  args,
                  call_loc,
                ),
                add_loc,
              ),
            ),
            return_loc,
          )
        }
        _ => fail("expected the escaped recursive member")
      }
    }
  } else {
    guard stmts[2] is @ast.ExprStmt(
      @ast.Call(
        @ast.ComputedMember(base, key, member_loc),
        args,
        call_loc,
      ),
      stmt_loc,
    ) else {
      fail("expected the escaped root member call")
    }
    stmts[2] = @ast.ExprStmt(
      @ast.Call(
        @ast.ComputedMember(base, toggle_key(key), member_loc),
        args,
        call_loc,
      ),
      stmt_loc,
    )
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
test "receiver recursion trust seals computed-literal key locations" {
  let (interp, _, registry) = receiver_recursion_computed_sealed_fixture()
  match registry.plan.recipe.marker_property_access {
    ReceiverRecursionComputedLiteral(_, _) => ()
    ReceiverRecursionStatic =>
      fail("expected computed marker property provenance")
  }
  match registry.plan.recipe.property_access {
    ReceiverRecursionComputedLiteral(_, _) => ()
    ReceiverRecursionStatic => fail("expected computed property provenance")
  }
  match registry.plan.recipe.marker_access {
    ReceiverRecursionComputedLiteral(_, _) => ()
    ReceiverRecursionStatic =>
      fail("expected computed marker access provenance")
  }
  match registry.plan.recipe.recursive_access {
    ReceiverRecursionComputedLiteral(_, _) => ()
    ReceiverRecursionStatic =>
      fail("expected computed recursive access provenance")
  }
  match registry.plan.recipe.root_access {
    ReceiverRecursionComputedLiteral(_, _) => ()
    ReceiverRecursionStatic => fail("expected computed root access provenance")
  }
  ignore(registry.require_receiver(interp))
}

///|
test "receiver recursion trust seals escaped computed provenance" {
  let (interp, _, registry) = receiver_recursion_escaped_computed_sealed_fixture()
  let accesses = [
    registry.plan.recipe.marker_property_access,
    registry.plan.recipe.property_access,
    registry.plan.recipe.marker_access,
    registry.plan.recipe.recursive_access,
    registry.plan.recipe.root_access,
  ]
  for access in accesses {
    match access {
      ReceiverRecursionComputedLiteral(_, has_escape) =>
        inspect(has_escape, content="true")
      ReceiverRecursionStatic => fail("expected escaped computed provenance")
    }
  }
  ignore(registry.require_receiver(interp))
}

///|
test "receiver recursion trust rejects same-location escaped-mode drift" {
  let (_, _, registry) = receiver_recursion_escaped_computed_sealed_fixture()
  let recipe = registry.plan.recipe
  for drift_index in 0..<5 {
    let candidate = receiver_recursion_recipe_with_escape(recipe, drift_index)
    inspect(
      receiver_recursion_recipe_matches(recipe, candidate),
      content="false",
    )
  }
}

///|
test "receiver recursion trust rejects preflight access provenance drift" {
  let (_, _, registry) = receiver_recursion_computed_sealed_fixture()
  let recipe = registry.plan.recipe
  for drift_index in 0..<5 {
    let candidate = receiver_recursion_recipe_with_access(recipe, drift_index)
    inspect(
      receiver_recursion_recipe_matches(recipe, candidate),
      content="false",
    )
  }
}

///|
test "receiver recursion trust rejects computed key drift at seal" {
  let interp = Interpreter::new()
  let stmts = @parser.parse(
      "function step(n){if(n===0)return this[\"marker\"];return 1+this[\"step\"](n-1);}" +
      "let receiver={[\"marker\"]:0,[\"step\"]:step};receiver[\"step\"](256);",
    ).stmts
  let preflight = match
    interp.preflight_dispatchable_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected callback-free computed receiver preflight")
  }
  let drift_loc : @token.Loc = { line: 99, col: 7, offset: 9999 }
  receiver_recursion_drift_computed_property_key(stmts, drift_loc)
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let ctx : ExecContext = { strict: false, current_generator: None }
  let _ = interp.exec_stmt(ctx, stmts[0], interp.global)
  let _ = interp.exec_stmt(ctx, stmts[1], interp.global)
  inspect(
    receiver_recursion_rejection(() => {
      ignore(interp.seal_receiver_recursion_registry(preflight, stmts))
    }),
    content="rejected",
  )
}

///|
test "receiver recursion trust rejects escaped-mode drift at every access site" {
  for drift_index in 0..<5 {
    let interp = Interpreter::new()
    let stmts = @parser.parse(
        "function step(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x73tep\"](n-1);}" +
        "let receiver={[\"\\x6darker\"]:0,[\"\\x73tep\"]:step};receiver[\"\\x73tep\"](256);",
      ).stmts
    let preflight = match
      interp.preflight_dispatchable_receiver_recursion_program(stmts) {
      Some(found) => found
      None => fail("expected escaped computed receiver preflight")
    }
    receiver_recursion_toggle_escaped_access(stmts, drift_index)
    interp.prepare_root_program_execution(stmts, interp.global, false)
    let ctx : ExecContext = { strict: false, current_generator: None }
    let _ = interp.exec_stmt(ctx, stmts[0], interp.global)
    let _ = interp.exec_stmt(ctx, stmts[1], interp.global)
    inspect(
      receiver_recursion_rejection(() => {
        ignore(interp.seal_receiver_recursion_registry(preflight, stmts))
      }),
      content="rejected",
    )
  }
}

///|
test "receiver recursion trust rejects computed body key location drift" {
  let (body_interp, _, body_registry) = receiver_recursion_computed_sealed_fixture()
  guard body_registry.trusted.callee
    is Object({ callable: Some(UserFunc(body_data)), .. }) else {
    fail("expected the sealed computed UserFunc")
  }
  let shifted_body = match
    @parser.parse(
      "function step(n){\n\nif(n===0)return this[\"marker\"];return 1+this[\"step\"](n-1);}",
    ).stmts[0] {
    @ast.FuncDecl(_, _, body, _, _) => body
    _ => fail("expected an equivalent computed function declaration")
  }
  body_data.body[0] = shifted_body[0]
  inspect(
    receiver_recursion_rejection(() => {
      ignore(body_registry.require_receiver(body_interp))
    }),
    content="rejected",
  )
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
test "receiver recursion trust rejects equivalent body at a different source location" {
  let (body_interp, _, body_registry) = receiver_recursion_sealed_fixture()
  guard body_registry.trusted.callee
    is Object({ callable: Some(UserFunc(body_data)), .. }) else {
    fail("expected the sealed UserFunc")
  }
  let shifted_body = match
    @parser.parse(
      "function step(n){\n\nif(n===0)return this.marker;return 1+this.step(n-1);}",
    ).stmts[0] {
    @ast.FuncDecl(_, _, body, _, _) => body
    _ => fail("expected an equivalent function declaration")
  }
  body_data.body[0] = shifted_body[0]
  inspect(
    receiver_recursion_rejection(() => {
      ignore(body_registry.require_receiver(body_interp))
    }),
    content="rejected",
  )
}

///|
test "receiver recursion trust rejects equivalent recursive body at a different source location" {
  let (body_interp, _, body_registry) = receiver_recursion_sealed_fixture()
  guard body_registry.trusted.callee
    is Object({ callable: Some(UserFunc(body_data)), .. }) else {
    fail("expected the sealed UserFunc")
  }
  let shifted_body = match
    @parser.parse(
      "function step(n){if(n===0)return this.marker;\n\nreturn 1+this.step(n-1);}",
    ).stmts[0] {
    @ast.FuncDecl(_, _, body, _, _) => body
    _ => fail("expected an equivalent function declaration")
  }
  body_data.body[1] = shifted_body[1]
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
