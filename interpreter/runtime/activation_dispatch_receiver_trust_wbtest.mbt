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
  let drifted = (access : ReceiverRecursionAccessKind) => {
    receiver_recursion_access_with_escape(access, false)
  }
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
            return_loc
          ),
          alternate,
          stmt_loc
        ) =>
          body[0] = @ast.IfStmt(
            condition,
            @ast.ReturnStmt(
              Some(@ast.ComputedMember(base, toggle_key(key), member_loc)),
              return_loc,
            ),
            alternate,
            stmt_loc,
          )
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
                call_loc
              ),
              add_loc
            )
          ),
          return_loc
        ) =>
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
        _ => fail("expected the escaped recursive member")
      }
    }
  } else {
    guard stmts[2]
      is @ast.ExprStmt(
        @ast.Call(@ast.ComputedMember(base, key, member_loc), args, call_loc),
        stmt_loc
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

///|
test "mutual receiver recursion preflight seals both function identities" {
  let interp = Interpreter::new()
  let stmts = @parser.parse(MUTUAL_RECEIVER_RECURSION_SOURCE).stmts
  let preflight = match
    interp.preflight_dispatchable_mutual_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact mutual receiver preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let ctx : ExecContext = { strict: false, current_generator: None }
  let _ = interp.exec_stmt(ctx, stmts[0], interp.global)
  let _ = interp.exec_stmt(ctx, stmts[1], interp.global)
  let _ = interp.exec_stmt(ctx, stmts[2], interp.global)
  let registry : TrustedMutualReceiverRecursionRegistry = interp.seal_mutual_receiver_recursion_registry(
    preflight, stmts,
  ) catch {
    InvalidActivationDispatchShell(message) =>
      fail("mutual receiver seal failed: " + message)
  }
  guard !mutual_receiver_value_identity(
    registry.left.callee,
    registry.right.callee,
  ) else {
    fail("expected distinct mutual receiver functions")
  }
}

///|
fn mutual_receiver_sealed_fixture(
  source_identity? : String? = None,
) -> (Interpreter, Array[@ast.Stmt], TrustedMutualReceiverRecursionRegistry) raise {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = source_identity
  let stmts = @parser.parse(MUTUAL_RECEIVER_RECURSION_SOURCE).stmts
  let preflight = match
    interp.preflight_dispatchable_mutual_receiver_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact mutual receiver preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let ctx : ExecContext = { strict: false, current_generator: None }
  for index in 0..<3 {
    let _ = interp.exec_stmt(ctx, stmts[index], interp.global)
  }
  let registry = interp.seal_mutual_receiver_recursion_registry(
    preflight, stmts,
  )
  (interp, stmts, registry)
}

///|
test "mutual receiver recursion trust seals every escaped access recipe" {
  let (interp, _, registry) = mutual_receiver_sealed_fixture()
  let accesses = [
    registry.plan.marker_property_access,
    registry.plan.left_property_access,
    registry.plan.right_property_access,
    registry.plan.root_access,
    registry.left.plan.recipe.marker_access,
    registry.left.plan.recipe.recursive_access,
    registry.right.plan.recipe.marker_access,
    registry.right.plan.recipe.recursive_access,
  ]
  for access in accesses {
    match access {
      MutualReceiverComputedLiteral(_, has_escape) =>
        inspect(has_escape, content="true")
      MutualReceiverStatic => fail("expected escaped computed provenance")
    }
  }
  ignore(registry.require_receiver(interp))
}

///|
test "mutual receiver recursion trust rejects swapped and aliased properties" {
  for swap in [true, false] {
    let (interp, _, registry) = mutual_receiver_sealed_fixture()
    guard registry.receiver is Object(receiver_data) else {
      fail("expected the sealed receiver object")
    }
    if swap {
      receiver_data.bag.properties[registry.plan.left.property_name] = registry.right.callee
      receiver_data.bag.properties[registry.plan.right.property_name] = registry.left.callee
    } else {
      receiver_data.bag.properties[registry.plan.right.property_name] = registry.left.callee
    }
    inspect(
      receiver_recursion_rejection(() => {
        ignore(registry.require_receiver(interp))
      }),
      content="rejected",
    )
  }
}

///|
test "mutual receiver recursion trust rejects descriptor and value drift" {
  let (descriptor_interp, _, descriptor_registry) = mutual_receiver_sealed_fixture()
  guard descriptor_registry.receiver is Object(descriptor_receiver) else {
    fail("expected the sealed receiver object")
  }
  descriptor_receiver.bag.descriptors[descriptor_registry.plan.marker_name] = {
    writable: false,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  inspect(
    receiver_recursion_rejection(() => {
      ignore(descriptor_registry.require_receiver(descriptor_interp))
    }),
    content="rejected",
  )

  let (value_interp, _, value_registry) = mutual_receiver_sealed_fixture()
  guard value_registry.receiver is Object(value_receiver) else {
    fail("expected the sealed receiver object")
  }
  value_receiver.bag.properties[value_registry.plan.marker_name] = Number(1.0)
  inspect(
    receiver_recursion_rejection(() => {
      ignore(value_registry.require_receiver(value_interp))
    }),
    content="rejected",
  )
}

///|
test "mutual receiver recursion trust rejects both function body identities" {
  for node in [MutualReceiverLeft, MutualReceiverRight] {
    let (interp, _, registry) = mutual_receiver_sealed_fixture()
    let trusted = mutual_receiver_registry_function(registry, node)
    guard trusted.callee is Object({ callable: Some(UserFunc(data)), .. }) else {
      fail("expected the sealed mutual UserFunc")
    }
    let source = match node {
      MutualReceiverLeft =>
        "function left(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x72ight\"](n-1);}"
      MutualReceiverRight =>
        "function right(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x6ceft\"](n-1);}"
    }
    let shifted_body = match @parser.parse(source).stmts[0] {
      @ast.FuncDecl(_, _, body, _, _) => body
      _ => fail("expected a mutual function declaration")
    }
    data.body[0] = shifted_body[0]
    inspect(
      receiver_recursion_rejection(() => {
        ignore(registry.require_function(interp, node))
      }),
      content="rejected",
    )
  }
}

///|
test "mutual receiver recursion trust rejects body statements without physical identity" {
  let (interp, _, registry) = mutual_receiver_sealed_fixture()
  let left_stmt = match
    @parser.parse(
      "function left(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x72ight\"](n-1);}",
    ).stmts[0] {
    @ast.FuncDecl(_, _, body, _, _) => body[0]
    _ => fail("expected a left mutual function declaration")
  }
  let right_stmt = match
    @parser.parse(
      "function right(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x6ceft\"](n-1);}",
    ).stmts[0] {
    @ast.FuncDecl(_, _, body, _, _) => body[0]
    _ => fail("expected a right mutual function declaration")
  }
  for statement in [left_stmt, right_stmt] {
    inspect(
      receiver_recursion_rejection(() => {
        ignore(registry.require_body_statement(interp, 0, statement))
      }),
      content="rejected",
    )
  }
}

///|
test "mutual receiver recursion trust seals location-callee pairings" {
  let (interp, _, registry) = mutual_receiver_sealed_fixture()
  let receiver = registry.require_receiver(interp)
  let root = registry.require_function(interp, registry.plan.root_node)
  ignore(
    registry.require_call(
      interp,
      root,
      receiver,
      [Number(registry.plan.initial_argument)],
      registry.plan.root_member_loc,
    ),
  )
  let wrong_root = match registry.plan.root_node {
    MutualReceiverLeft => registry.right.callee
    MutualReceiverRight => registry.left.callee
  }
  inspect(
    receiver_recursion_rejection(() => {
      ignore(
        registry.require_call(
          interp,
          wrong_root,
          receiver,
          [Number(registry.plan.initial_argument)],
          registry.plan.root_member_loc,
        ),
      )
    }),
    content="rejected",
  )
  inspect(
    receiver_recursion_rejection(() => {
      ignore(
        registry.require_call(
          interp,
          registry.left.callee,
          receiver,
          [Number(1.0)],
          registry.left.plan.recipe.recursive_call_loc,
        ),
      )
    }),
    content="rejected",
  )
  inspect(
    receiver_recursion_rejection(() => {
      ignore(
        registry.require_call(
          interp,
          registry.right.callee,
          receiver,
          [Number(1.0)],
          registry.right.plan.recipe.recursive_call_loc,
        ),
      )
    }),
    content="rejected",
  )
}

///|
test "mutual receiver recursion trust revalidates ThrowTypeError identity" {
  let (interp, _, registry) = mutual_receiver_sealed_fixture()
  interp.global.def_builtin(
    "[[ThrowTypeError]]",
    make_native_func(name="replacement ThrowTypeError", _args => Undefined),
  )
  let outcome = try {
    ignore(registry.require_receiver(interp))
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    outcome,
    content="mutual receiver recursion ThrowTypeError binding changed after sealing",
  )
}

///|
test "mutual receiver recursion trust rejects parameter, binding, and mirror drift" {
  let (parameter_interp, _, parameter_registry) = mutual_receiver_sealed_fixture()
  guard parameter_registry.left.callee
    is Object({ callable: Some(UserFunc(parameter_data)), .. }) else {
    fail("expected the sealed left UserFunc")
  }
  parameter_data.params[0] = "drifted"
  inspect(
    receiver_recursion_rejection(() => {
      ignore(
        parameter_registry.require_function(
          parameter_interp,
          MutualReceiverLeft,
        ),
      )
    }),
    content="rejected",
  )

  let (binding_interp, _, binding_registry) = mutual_receiver_sealed_fixture()
  guard binding_interp.global.bindings.get("left") is Some(binding) else {
    fail("expected the sealed left global binding")
  }
  binding.value = binding_registry.right.callee
  inspect(
    receiver_recursion_rejection(() => {
      ignore(
        binding_registry.require_function(binding_interp, MutualReceiverLeft),
      )
    }),
    content="rejected",
  )

  let (mirror_interp, _, mirror_registry) = mutual_receiver_sealed_fixture()
  guard mirror_interp.global_this is Object(mirror_global) else {
    fail("expected the canonical global object")
  }
  mirror_global.bag.properties[mirror_registry.left.plan.function_name] = Number(
    0.0,
  )
  inspect(
    receiver_recursion_rejection(() => {
      ignore(
        mirror_registry.require_function(mirror_interp, MutualReceiverLeft),
      )
    }),
    content="rejected",
  )
}

///|
test "mutual receiver recursion trust rejects source and realm metadata drift" {
  let (source_interp, _, source_registry) = mutual_receiver_sealed_fixture(
    source_identity=Some("sealed source"),
  )
  guard source_registry.left.callee is Object(source_data) &&
    source_data.bag.symbol_properties.get(
      FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID,
    )
    is Some(Array(source_metadata)) &&
    source_metadata.elements.length() > FUNCTION_SOURCE_IDENTITY_IDX else {
    fail("expected packed source metadata on the left function")
  }
  source_metadata.elements[FUNCTION_SOURCE_IDENTITY_IDX] = String_("drifted")
  inspect(
    receiver_recursion_rejection(() => {
      ignore(
        source_registry.require_function(source_interp, MutualReceiverLeft),
      )
    }),
    content="rejected",
  )

  let (realm_interp, _, realm_registry) = mutual_receiver_sealed_fixture()
  guard realm_registry.right.callee is Object(realm_data) &&
    realm_data.bag.symbol_properties.get(FUNCTION_REALM_PROTOS_PACKED_SYMBOL_ID)
    is Some(Array(realm_metadata)) &&
    realm_metadata.elements.length() > REALM_PROTO_IDX_OBJECT else {
    fail("expected packed realm metadata on the right function")
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

///|
test "mutual receiver recursion trust rejects pre-seal key and body location drift" {
  let key_interp = Interpreter::new()
  let key_stmts = @parser.parse(MUTUAL_RECEIVER_RECURSION_SOURCE).stmts
  let key_preflight = match
    key_interp.preflight_dispatchable_mutual_receiver_recursion_program(
      key_stmts,
    ) {
    Some(found) => found
    None => fail("expected the exact mutual receiver preflight")
  }
  guard key_stmts[2]
    is @ast.VarDecl(_, _, Some(@ast.ObjectLit(properties, _)), _) else {
    fail("expected the mutual receiver object declaration")
  }
  let key_property = properties[1]
  properties[1] = {
    ..key_property,
    key: @ast.StringLit("left", true, @token.LexForm::LexNormal, {
      line: 91,
      col: 4,
      offset: 9104,
    }),
  }
  key_interp.prepare_root_program_execution(key_stmts, key_interp.global, false)
  let key_ctx : ExecContext = { strict: false, current_generator: None }
  for index in 0..<3 {
    let _ = key_interp.exec_stmt(key_ctx, key_stmts[index], key_interp.global)
  }
  inspect(
    receiver_recursion_rejection(() => {
      ignore(
        key_interp.seal_mutual_receiver_recursion_registry(
          key_preflight, key_stmts,
        ),
      )
    }),
    content="rejected",
  )

  let body_interp = Interpreter::new()
  let body_stmts = @parser.parse(MUTUAL_RECEIVER_RECURSION_SOURCE).stmts
  let body_preflight = match
    body_interp.preflight_dispatchable_mutual_receiver_recursion_program(
      body_stmts,
    ) {
    Some(found) => found
    None => fail("expected the exact mutual receiver preflight")
  }
  guard body_stmts[0] is @ast.FuncDecl(_, _, body, _, _) else {
    fail("expected the left mutual function declaration")
  }
  let shifted = match
    @parser.parse(
      "function left(n){\n\nif(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x72ight\"](n-1);}",
    ).stmts[0] {
    @ast.FuncDecl(_, _, shifted_body, _, _) => shifted_body[0]
    _ => fail("expected the shifted left function body")
  }
  body[0] = shifted
  body_interp.prepare_root_program_execution(
    body_stmts,
    body_interp.global,
    false,
  )
  let body_ctx : ExecContext = { strict: false, current_generator: None }
  for index in 0..<3 {
    let _ = body_interp.exec_stmt(
      body_ctx,
      body_stmts[index],
      body_interp.global,
    )
  }
  inspect(
    receiver_recursion_rejection(() => {
      ignore(
        body_interp.seal_mutual_receiver_recursion_registry(
          body_preflight, body_stmts,
        ),
      )
    }),
    content="rejected",
  )
}
