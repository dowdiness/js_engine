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

///|
// Postfix keeps arbitrary left-associated depth in owned data instead of
// adding a continuation variant for each call count.
priv enum DispatchExpressionPlanStep {
  DispatchExpressionCall(DispatchExpressionCallStep)
  DispatchExpressionNumericAdd(@token.Loc)
}

///|
priv struct DispatchExpressionCallStep {
  request : DispatchCallRequest
  adapter : DispatchManagedUserFuncAdapterToken
  name : String
}

///|
fn DispatchExpressionCallStep::DispatchExpressionCallStep(
  request~ : DispatchCallRequest,
  adapter~ : DispatchManagedUserFuncAdapterToken,
  name~ : String,
) -> DispatchExpressionCallStep {
  {
    request: DispatchCallRequest(
      callee=request.callee,
      this_value=request.this_value,
      args=request.args,
      loc=request.loc,
    ),
    adapter,
    name,
  }
}

///|
priv struct DispatchExpressionPlan {
  steps : Array[DispatchExpressionPlanStep]
}

///|
fn DispatchExpressionPlan::DispatchExpressionPlan(
  steps~ : Array[DispatchExpressionPlanStep],
) -> DispatchExpressionPlan {
  { steps: steps.map(snapshot_dispatch_expression_plan_step) }
}

///|
priv struct DispatchExpressionPlanResume {
  plan : DispatchExpressionPlan
  next_index : Int
  values : Array[Value]
}

///|
fn DispatchExpressionPlanResume::DispatchExpressionPlanResume(
  plan~ : DispatchExpressionPlan,
  next_index~ : Int,
  values~ : Array[Value],
) -> DispatchExpressionPlanResume {
  {
    plan: snapshot_dispatch_expression_plan(plan),
    next_index,
    values: values.copy(),
  }
}

///|
priv struct DispatchExpressionCallSource {
  name : String
  argument : Double
  call_loc : @token.Loc
  argument_loc : @token.Loc
}

///|
priv enum DispatchExpressionSourceStep {
  DispatchExpressionCallSourceStep(DispatchExpressionCallSource)
  DispatchExpressionAddSourceStep(@token.Loc)
}

///|
priv struct NumericMapExpressionSource {
  numeric_stmts : Array[@ast.Stmt]
  array_map_stmts : Array[@ast.Stmt]
  steps : Array[DispatchExpressionSourceStep]
}

///|
priv struct NumericMapExpressionPreflight {
  numeric : NumericRecursionPreflight
  array_map : ArrayMapRecursionPreflight
  source : NumericMapExpressionSource
}

///|
fn snapshot_dispatch_expression_call_step(
  step : DispatchExpressionCallStep,
) -> DispatchExpressionCallStep {
  DispatchExpressionCallStep(
    request=step.request,
    adapter=step.adapter,
    name=step.name,
  )
}

///|
fn snapshot_dispatch_expression_plan_step(
  step : DispatchExpressionPlanStep,
) -> DispatchExpressionPlanStep {
  match step {
    DispatchExpressionCall(call) =>
      DispatchExpressionCall(snapshot_dispatch_expression_call_step(call))
    DispatchExpressionNumericAdd(loc) => DispatchExpressionNumericAdd(loc)
  }
}

///|
fn snapshot_dispatch_expression_plan(
  plan : DispatchExpressionPlan,
) -> DispatchExpressionPlan {
  DispatchExpressionPlan(steps=plan.steps)
}

///|
fn snapshot_dispatch_expression_plan_resume(
  plan_resume : DispatchExpressionPlanResume,
) -> DispatchExpressionPlanResume {
  DispatchExpressionPlanResume(
    plan=plan_resume.plan,
    next_index=plan_resume.next_index,
    values=plan_resume.values,
  )
}

///|
fn dispatch_expression_plan_root_call_locs(
  plan : DispatchExpressionPlan,
) -> Array[@token.Loc] {
  let locations : Array[@token.Loc] = []
  for step in plan.steps {
    match step {
      DispatchExpressionCall(call) =>
        match call.adapter {
          DispatchArrayMapUserFuncAdapterToken(_) =>
            locations.push(call.request.loc)
          DispatchNumericUserFuncAdapterToken(_) => ()
        }
      DispatchExpressionNumericAdd(_) => ()
    }
  }
  locations
}

///|
fn expression_call_source(expr : @ast.Expr) -> DispatchExpressionCallSource? {
  match expr {
    @ast.Call(
      @ast.Ident(name, _),
      [@ast.NumberLit(argument, lex_form, argument_loc)],
      call_loc
    ) if (name == "step" || name == "u") &&
      lex_form == @token.LexForm::LexNormal &&
      argument == NUMERIC_RECURSION_INITIAL_ARGUMENT =>
      Some({ name, argument, call_loc, argument_loc })
    _ => None
  }
}

///|
priv enum DispatchExpressionVisit {
  DispatchExpressionVisitExpr(@ast.Expr)
  DispatchExpressionVisitAdd(@token.Loc)
}

///|
// Walk the exact left-associated shape with an explicit worklist. A binary
// right child must be a call leaf; right-nested trees remain legacy.
fn classify_expression_source_steps(
  expr : @ast.Expr,
) -> Array[DispatchExpressionSourceStep]? {
  let work : Array[DispatchExpressionVisit] = [
    DispatchExpressionVisitExpr(expr),
  ]
  let steps : Array[DispatchExpressionSourceStep] = []
  while work.pop() is Some(item) {
    match item {
      DispatchExpressionVisitExpr(@ast.Binary(@ast.Add, left, right, loc)) => {
        guard expression_call_source(right) is Some(_) else { return None }
        work.push(DispatchExpressionVisitAdd(loc))
        work.push(DispatchExpressionVisitExpr(right))
        work.push(DispatchExpressionVisitExpr(left))
      }
      DispatchExpressionVisitExpr(expr) =>
        match expression_call_source(expr) {
          Some(source) => steps.push(DispatchExpressionCallSourceStep(source))
          None => return None
        }
      DispatchExpressionVisitAdd(loc) =>
        steps.push(DispatchExpressionAddSourceStep(loc))
    }
  }
  Some(steps)
}

///|
fn expression_source_step_is_call_named(
  steps : Array[DispatchExpressionSourceStep],
  index : Int,
  name : String,
) -> Bool {
  match steps[index] {
    DispatchExpressionCallSourceStep({ name: actual, .. }) => actual == name
    _ => false
  }
}

///|
fn expression_source_step_is_add(
  steps : Array[DispatchExpressionSourceStep],
  index : Int,
) -> Bool {
  match steps[index] {
    DispatchExpressionAddSourceStep(_) => true
    _ => false
  }
}

///|
// The common postfix plan is deliberately closed to the three-call,
// four-call, and five-call sources already proven at the public boundary. A
// longer or reordered call sequence remains on the legacy evaluator.
fn expression_source_shape_is_admissible(
  steps : Array[DispatchExpressionSourceStep],
) -> Bool {
  match steps.length() {
    5 =>
      expression_source_step_is_call_named(steps, 0, "step") &&
      expression_source_step_is_call_named(steps, 1, "u") &&
      expression_source_step_is_add(steps, 2) &&
      expression_source_step_is_call_named(steps, 3, "step") &&
      expression_source_step_is_add(steps, 4)
    7 =>
      expression_source_step_is_call_named(steps, 0, "step") &&
      expression_source_step_is_call_named(steps, 1, "u") &&
      expression_source_step_is_add(steps, 2) &&
      expression_source_step_is_call_named(steps, 3, "step") &&
      expression_source_step_is_add(steps, 4) &&
      expression_source_step_is_call_named(steps, 5, "u") &&
      expression_source_step_is_add(steps, 6)
    9 =>
      expression_source_step_is_call_named(steps, 0, "step") &&
      expression_source_step_is_call_named(steps, 1, "u") &&
      expression_source_step_is_add(steps, 2) &&
      expression_source_step_is_call_named(steps, 3, "step") &&
      expression_source_step_is_add(steps, 4) &&
      expression_source_step_is_call_named(steps, 5, "u") &&
      expression_source_step_is_add(steps, 6) &&
      expression_source_step_is_call_named(steps, 7, "step") &&
      expression_source_step_is_add(steps, 8)
    _ => false
  }
}

///|
fn numeric_map_expression_source(
  stmts : Array[@ast.Stmt],
) -> NumericMapExpressionSource? {
  guard stmts.length() == 4 else { return None }
  let (expr, stmt_loc) = match stmts[3] {
    @ast.ExprStmt(expr, stmt_loc) => (expr, stmt_loc)
    _ => return None
  }
  let steps = match classify_expression_source_steps(expr) {
    Some(steps) => steps
    None => return None
  }
  guard expression_source_shape_is_admissible(steps) else { return None }
  let mut first_step_expr : @ast.Expr? = None
  let mut first_u_expr : @ast.Expr? = None
  for step in steps {
    match step {
      DispatchExpressionCallSourceStep(source) => {
        if source.name == "step" && first_step_expr is None {
          first_step_expr = Some(
            @ast.Call(
              @ast.Ident(source.name, @token.Loc::default()),
              [
                @ast.NumberLit(
                  source.argument,
                  @token.LexForm::LexNormal,
                  source.argument_loc,
                ),
              ],
              source.call_loc,
            ),
          )
        }
        if source.name == "u" && first_u_expr is None {
          first_u_expr = Some(
            @ast.Call(
              @ast.Ident(source.name, @token.Loc::default()),
              [
                @ast.NumberLit(
                  source.argument,
                  @token.LexForm::LexNormal,
                  source.argument_loc,
                ),
              ],
              source.call_loc,
            ),
          )
        }
      }
      DispatchExpressionAddSourceStep(loc) => ignore(loc)
    }
  }
  guard first_step_expr is Some(step_expr) && first_u_expr is Some(u_expr) else {
    return None
  }
  let numeric_stmts = [stmts[0], @ast.ExprStmt(step_expr, stmt_loc)]
  let array_map_stmts = [stmts[1], stmts[2], @ast.ExprStmt(u_expr, stmt_loc)]
  Some({ numeric_stmts, array_map_stmts, steps })
}

///|
fn Interpreter::preflight_dispatchable_numeric_map_expression_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> NumericMapExpressionPreflight? {
  let source = match numeric_map_expression_source(stmts) {
    Some(source) => source
    None => return None
  }
  let numeric_plan = match
    classify_numeric_recursion_program(source.numeric_stmts) {
    Some(plan) if numeric_recursion_plan_is_dispatchable(plan) => plan
    _ => return None
  }
  let array_map_plan = match
    classify_array_map_recursion_program(source.array_map_stmts) {
    Some(plan) if array_map_plan_is_dispatchable(plan) => plan
    _ => return None
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
  Some({ numeric, array_map, source })
}

///|
fn source_steps_match(
  expected : Array[DispatchExpressionSourceStep],
  actual : Array[DispatchExpressionSourceStep],
) -> Bool {
  guard expected.length() == actual.length() else { return false }
  for i in 0..<expected.length() {
    let matches = match (expected[i], actual[i]) {
      (
        DispatchExpressionCallSourceStep(expected_call),
        DispatchExpressionCallSourceStep(actual_call),
      ) =>
        expected_call.name == actual_call.name &&
        expected_call.argument == actual_call.argument &&
        expected_call.call_loc == actual_call.call_loc &&
        expected_call.argument_loc == actual_call.argument_loc
      (
        DispatchExpressionAddSourceStep(expected_loc),
        DispatchExpressionAddSourceStep(actual_loc),
      ) => expected_loc == actual_loc
      _ => false
    }
    guard matches else { return false }
  }
  true
}

///|
fn dispatch_expression_adapter_matches_name(
  adapter : DispatchManagedUserFuncAdapterToken,
  name : String,
) -> Bool {
  match (adapter, name) {
    (DispatchNumericUserFuncAdapterToken(_), "step") => true
    (DispatchArrayMapUserFuncAdapterToken(_), "u") => true
    _ => false
  }
}

///|
fn Interpreter::seal_numeric_map_expression_catalog(
  self : Interpreter,
  preflight : NumericMapExpressionPreflight,
  stmts : Array[@ast.Stmt],
) -> (DispatchManagedUserFuncCatalog, DispatchExpressionPlan) raise InvalidActivationDispatchShell {
  let source = match numeric_map_expression_source(stmts) {
    Some(source) => source
    None =>
      invalid_activation_dispatch_shell(
        "numeric/map expression no longer satisfies exact admission",
      )
  }
  guard source_steps_match(preflight.source.steps, source.steps) else {
    invalid_activation_dispatch_shell(
      "numeric/map expression tree or source locations changed after preflight",
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
  let catalog = DispatchManagedUserFuncCatalog(numeric~, array_map~)
  let plan_steps : Array[DispatchExpressionPlanStep] = []
  for source_step in source.steps {
    match source_step {
      DispatchExpressionCallSourceStep(call) => {
        let callee = if call.name == "step" {
          catalog.numeric.entry.callee
        } else {
          catalog.array_map.step_function
        }
        let adapter = match catalog.select(callee, None, Undefined) {
          Some(adapter) => adapter
          None =>
            invalid_activation_dispatch_shell(
              "numeric/map expression adapter selection was not unique",
            )
        }
        guard dispatch_expression_adapter_matches_name(adapter, call.name) else {
          invalid_activation_dispatch_shell(
            "numeric/map expression adapter family drifted",
          )
        }
        plan_steps.push(
          DispatchExpressionCall(
            DispatchExpressionCallStep(
              request=DispatchCallRequest(
                callee~,
                this_value=Undefined,
                args=[Number(call.argument)],
                loc=call.call_loc,
              ),
              adapter~,
              name=call.name,
            ),
          ),
        )
      }
      DispatchExpressionAddSourceStep(loc) =>
        plan_steps.push(DispatchExpressionNumericAdd(loc))
    }
  }
  (catalog, DispatchExpressionPlan(steps=plan_steps))
}

///|
fn resume_dispatch_expression_plan(
  state : ActivationDispatchState,
  plan_resume : DispatchExpressionPlanResume,
  value : Value,
) -> DispatchCompletionResume raise InvalidDispatchTransition {
  guard state.phase is DispatchReady else {
    invalid_dispatch_transition("expression plan resume requires Ready")
  }
  guard plan_resume.next_index >= 0 &&
    plan_resume.next_index <= plan_resume.plan.steps.length() else {
    invalid_dispatch_transition("expression plan cursor is outside its steps")
  }
  let values = plan_resume.values.copy()
  values.push(value)
  let mut index = plan_resume.next_index
  while index < plan_resume.plan.steps.length() {
    match plan_resume.plan.steps[index] {
      DispatchExpressionCall(call) => {
        guard dispatch_managed_user_func_adapter_token_matches(
            call.adapter,
            call.request.callee,
          ) &&
          dispatch_expression_adapter_matches_name(call.adapter, call.name) else {
          invalid_dispatch_transition("expression plan call adapter drifted")
        }
        let next = DispatchExpressionPlanResume(
          plan=plan_resume.plan,
          next_index=index + 1,
          values~,
        )
        return dispatch_resume_decision(
          suspend_dispatch_work(
            state,
            DispatchSuspendCall(
              call.request,
              DispatchContinueExpressionPlan(next),
            ),
          ),
        )
      }
      DispatchExpressionNumericAdd(loc) => {
        guard values.length() >= 2 else {
          invalid_dispatch_transition(
            "expression plan binary node lacks two operands",
          )
        }
        let right = match values.pop() {
          Some(right) => right
          None =>
            invalid_dispatch_transition("expression plan right operand missing")
        }
        let left = match values.pop() {
          Some(left) => left
          None =>
            invalid_dispatch_transition("expression plan left operand missing")
        }
        let next = DispatchExpressionPlanResume(
          plan=plan_resume.plan,
          next_index=index + 1,
          values~,
        )
        return dispatch_resume_decision(
          suspend_dispatch_work(
            state,
            DispatchSuspendContinueProduction(
              DispatchContinueExpressionPlan(next),
              DispatchNumericApplyBinaryRight(
                DispatchBinaryResume(op=@ast.Add, left~, loc~),
                right,
              ),
            ),
          ),
        )
      }
    }
    index += 1
  }
  guard values.length() == 1 else {
    invalid_dispatch_transition("expression plan did not produce one value")
  }
  DispatchResumeCompletion(DispatchNormal(values[0]))
}
