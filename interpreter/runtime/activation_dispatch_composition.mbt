// Closed composition admission for the exact numeric-plus-Array.map root. The
// catalog is deliberately private: only the two sealed UserFunc adapters can
// be selected, and no arbitrary callback or closure enters the production
// driver through this seam.

///|
priv enum DispatchManagedUserFuncAdapterToken {
  DispatchNumericUserFuncAdapterToken(Value)
  DispatchArrayMapUserFuncAdapterToken(Value)
}

///|
priv struct DispatchManagedUserFuncCatalog {
  numeric : TrustedNumericRecursionRegistry
  array_map : TrustedArrayMapRecursionRegistry
}

///|
fn DispatchManagedUserFuncCatalog::DispatchManagedUserFuncCatalog(
  numeric~ : TrustedNumericRecursionRegistry,
  array_map~ : TrustedArrayMapRecursionRegistry,
) -> DispatchManagedUserFuncCatalog {
  { numeric, array_map }
}

///|
fn numeric_map_composition_call_plan(
  preflight : NumericMapCompositionPreflight,
  catalog : DispatchManagedUserFuncCatalog,
) -> DispatchBinaryRightCallResume? {
  let left_request = DispatchCallRequest(
    callee=catalog.numeric.entry.callee,
    this_value=Undefined,
    args=[Number(NUMERIC_RECURSION_INITIAL_ARGUMENT)],
    loc=preflight.left_call_loc,
  )
  let right_request = DispatchCallRequest(
    callee=catalog.array_map.step_function,
    this_value=Undefined,
    args=[Number(preflight.array_map.plan.initial_count)],
    loc=preflight.right_call_loc,
  )
  let left_adapter = match
    catalog.select(left_request.callee, None, left_request.this_value) {
    Some(token) => token
    None => return None
  }
  guard left_adapter is DispatchNumericUserFuncAdapterToken(_) else {
    return None
  }
  let right_adapter = match
    catalog.select(right_request.callee, None, right_request.this_value) {
    Some(token) => token
    None => return None
  }
  guard right_adapter is DispatchArrayMapUserFuncAdapterToken(_) else {
    return None
  }
  Some(
    DispatchBinaryRightCallResume(
      left_request~,
      right_request~,
      left_value=None,
      op=@ast.Add,
      loc=preflight.binary_loc,
      left_adapter~,
      right_adapter~,
    ),
  )
}

///|
priv struct NumericMapCompositionPreflight {
  numeric : NumericRecursionPreflight
  array_map : ArrayMapRecursionPreflight
  left_call_loc : @token.Loc
  right_call_loc : @token.Loc
  binary_loc : @token.Loc
}

///|
priv struct NumericMapCompositionSource {
  numeric_stmts : Array[@ast.Stmt]
  array_map_stmts : Array[@ast.Stmt]
  left_call_loc : @token.Loc
  right_call_loc : @token.Loc
  binary_loc : @token.Loc
}

///|
fn dispatch_managed_user_func_adapter_token_matches(
  token : DispatchManagedUserFuncAdapterToken,
  callee : Value,
) -> Bool {
  match token {
    DispatchNumericUserFuncAdapterToken(expected)
    | DispatchArrayMapUserFuncAdapterToken(expected) =>
      array_map_value_identity_matches(expected, callee)
  }
}

///|
fn dispatch_numeric_catalog_callee_matches(
  registry : TrustedNumericRecursionRegistry,
  callee : Value,
) -> Bool {
  let entry_matches = match callee {
    Object(actual) =>
      numeric_recursion_trusted_callee_has_identity(registry.entry, actual)
    _ => false
  }
  if entry_matches {
    return true
  }
  match registry.peer {
    Some(peer) =>
      match callee {
        Object(actual) =>
          numeric_recursion_trusted_callee_has_identity(peer, actual)
        _ => false
      }
    None => false
  }
}

///|
fn dispatch_array_map_catalog_callee_matches(
  registry : TrustedArrayMapRecursionRegistry,
  callee : Value,
  map_state : MapState?,
  receiver : Value,
) -> Bool {
  if array_map_value_identity_matches(registry.step_function, callee) {
    return true
  }
  match registry.forward_function {
    Some(forward) if array_map_value_identity_matches(forward, callee) =>
      return true
    _ => ()
  }
  match map_state {
    Some(state) if array_map_value_identity_matches(state.callback, callee) =>
      true
    Some(_) if registry.plan.callback_family is ArrayMapMemberCallback =>
      array_map_member_receiver_matches(
        receiver,
        callee,
        registry.plan.member_property_name,
      )
    _ => false
  }
}

///|
// Selection is a pure exhaustive choice over the sealed adapter catalog. A
// collision is rejected as None rather than silently preferring one family.
fn DispatchManagedUserFuncCatalog::select(
  self : DispatchManagedUserFuncCatalog,
  callee : Value,
  map_state : MapState?,
  receiver : Value,
) -> DispatchManagedUserFuncAdapterToken? {
  let numeric = dispatch_numeric_catalog_callee_matches(self.numeric, callee)
  let array_map = dispatch_array_map_catalog_callee_matches(
    self.array_map,
    callee,
    map_state,
    receiver,
  )
  match (numeric, array_map) {
    (true, false) => Some(DispatchNumericUserFuncAdapterToken(callee))
    (false, true) => Some(DispatchArrayMapUserFuncAdapterToken(callee))
    (false, false) | (true, true) => None
  }
}

///|
fn composition_call_expression(
  expr : @ast.Expr,
  expected_name : String,
) -> (@token.Loc, @token.Loc)? {
  match expr {
    @ast.Call(
      @ast.Ident(actual_name, _),
      [@ast.NumberLit(value, lex_form, argument_loc)],
      call_loc
    ) if actual_name == expected_name &&
      lex_form == @token.LexForm::LexNormal &&
      exact_numeric_recursion_number(
        @ast.NumberLit(value, lex_form, argument_loc),
        NUMERIC_RECURSION_INITIAL_ARGUMENT,
      ) => Some((call_loc, argument_loc))
    _ => None
  }
}

///|
fn classify_numeric_map_composition_source(
  stmts : Array[@ast.Stmt],
) -> NumericMapCompositionSource? {
  guard stmts.length() == 4 else { return None }
  let (left_expr, right_expr, binary_loc, stmt_loc) = match stmts[3] {
    @ast.ExprStmt(@ast.Binary(@ast.Add, left, right, binary_loc), stmt_loc) =>
      (left, right, binary_loc, stmt_loc)
    _ => return None
  }
  guard composition_call_expression(left_expr, "step") is Some((left_loc, _)) else {
    return None
  }
  guard composition_call_expression(right_expr, "u") is Some((right_loc, _)) else {
    return None
  }
  let numeric_stmts = [stmts[0], @ast.ExprStmt(left_expr, stmt_loc)]
  let array_map_stmts = [
    stmts[1],
    stmts[2],
    @ast.ExprStmt(right_expr, stmt_loc),
  ]
  guard classify_numeric_recursion_program(numeric_stmts) is Some(numeric) else {
    return None
  }
  guard numeric_recursion_plan_is_dispatchable(numeric) else { return None }
  guard classify_array_map_recursion_program(array_map_stmts) is Some(array_map) else {
    return None
  }
  guard array_map_plan_is_dispatchable(array_map) else { return None }
  Some({
    numeric_stmts,
    array_map_stmts,
    left_call_loc: left_loc,
    right_call_loc: right_loc,
    binary_loc,
  })
}

///|
fn Interpreter::preflight_dispatchable_numeric_map_composition_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> NumericMapCompositionPreflight? {
  let source = match classify_numeric_map_composition_source(stmts) {
    Some(source) => source
    None => return None
  }
  let numeric_plan = match
    classify_numeric_recursion_program(source.numeric_stmts) {
    Some(plan) => plan
    None => return None
  }
  let array_map_plan = match
    classify_array_map_recursion_program(source.array_map_stmts) {
    Some(plan) => plan
    None => return None
  }
  let numeric = match self.preflight_numeric_recursion_program(numeric_plan) {
    Some(preflight) => preflight
    None => return None
  }
  let array_map = match
    self.preflight_array_map_recursion_program(array_map_plan) {
    Some(preflight) => preflight
    None => return None
  }
  Some({
    numeric,
    array_map,
    left_call_loc: source.left_call_loc,
    right_call_loc: source.right_call_loc,
    binary_loc: source.binary_loc,
  })
}

///|
fn Interpreter::seal_numeric_map_composition_catalog(
  self : Interpreter,
  preflight : NumericMapCompositionPreflight,
  stmts : Array[@ast.Stmt],
) -> DispatchManagedUserFuncCatalog raise InvalidActivationDispatchShell {
  let source = match classify_numeric_map_composition_source(stmts) {
    Some(source) => source
    None =>
      invalid_activation_dispatch_shell(
        "numeric/map composition no longer satisfies exact admission",
      )
  }
  guard source.left_call_loc == preflight.left_call_loc &&
    source.right_call_loc == preflight.right_call_loc &&
    source.binary_loc == preflight.binary_loc else {
    invalid_activation_dispatch_shell(
      "numeric/map composition source locations changed after preflight",
    )
  }
  let numeric = self.seal_numeric_recursion_registry(
    preflight.numeric,
    source.numeric_stmts,
  )
  let array_map = self.seal_array_map_recursion_registry(
    preflight.array_map,
    source.array_map_stmts,
  )
  DispatchManagedUserFuncCatalog(numeric~, array_map~)
}
