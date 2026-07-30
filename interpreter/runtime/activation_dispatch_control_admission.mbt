// Exact, callback-free admission for the two structural lifecycle roots owned
// by #630. The plan contains no AST arrays: mutable syntax remains at the
// imperative shell boundary and is reclassified before managed execution.

///|
priv enum ControlLifecyclePlan {
  ControlLabelledBreak(String)
  ControlBoundedContinue
}

///|
priv struct ControlLifecyclePreflight {
  plan : ControlLifecyclePlan
}

///|
fn ControlLifecyclePreflight::ControlLifecyclePreflight(
  plan~ : ControlLifecyclePlan,
) -> ControlLifecyclePreflight {
  { plan, }
}

///|
priv struct TrustedControlLifecycleProgram {
  plan : ControlLifecyclePlan
  root_env : Environment
}

///|
fn TrustedControlLifecycleProgram::TrustedControlLifecycleProgram(
  plan~ : ControlLifecyclePlan,
  root_env~ : Environment,
) -> TrustedControlLifecycleProgram {
  { plan, root_env }
}

///|
priv enum ControlLifecyclePhase {
  ControlAwaitRoot
  ControlAwaitProtected
  ControlAwaitAbrupt
  ControlAwaitFinalizer
  ControlAwaitLoopAdvance
  ControlAwaitTerminal
  ControlFinished
}

///|
priv enum ControlLifecycleRole {
  ControlRootRole
  ControlProtectedRole
  ControlAbruptRole
  ControlFinalizerRole
  ControlLoopAdvanceRole
  ControlTerminalRole
}

///|
fn exact_control_number_statement(stmt : @ast.Stmt, expected : Double) -> Bool {
  match stmt {
    @ast.ExprStmt(@ast.NumberLit(value, lex_form, _), _) =>
      value == expected && lex_form == @token.LexForm::LexNormal
    _ => false
  }
}

///|
fn control_lifecycle_try_matches(
  plan : ControlLifecyclePlan,
  stmt : @ast.Stmt,
) -> Bool {
  guard stmt is @ast.TryCatchStmt(try_body, None, None, Some(finalizer_body), _) &&
    try_body.length() == 1 &&
    finalizer_body.length() == 1 else {
    return false
  }
  match plan {
    ControlLabelledBreak(label) =>
      try_body[0] is @ast.BreakStmt(Some(actual), _) &&
      actual == label &&
      exact_control_number_statement(finalizer_body[0], 1.0)
    ControlBoundedContinue =>
      try_body[0] is @ast.ContinueStmt(None, _) &&
      exact_control_number_statement(finalizer_body[0], 2.0)
  }
}

///|
fn control_lifecycle_root_matches(
  plan : ControlLifecyclePlan,
  stmt : @ast.Stmt,
) -> Bool {
  match (plan, stmt) {
    (ControlLabelledBreak(expected), @ast.LabeledStmt(actual, body, _)) =>
      actual == expected && control_lifecycle_try_matches(plan, body)
    (ControlBoundedContinue, @ast.DoWhileStmt(body, @ast.BoolLit(false, _), _)) =>
      control_lifecycle_try_matches(plan, body)
    _ => false
  }
}

///|
fn control_lifecycle_abrupt_matches(
  plan : ControlLifecyclePlan,
  stmt : @ast.Stmt,
) -> Bool {
  match (plan, stmt) {
    (ControlLabelledBreak(expected), @ast.BreakStmt(Some(actual), _)) =>
      actual == expected
    (ControlBoundedContinue, @ast.ContinueStmt(None, _)) => true
    _ => false
  }
}

///|
fn control_lifecycle_finalizer_matches(
  plan : ControlLifecyclePlan,
  stmt : @ast.Stmt,
) -> Bool {
  match plan {
    ControlLabelledBreak(_) => exact_control_number_statement(stmt, 1.0)
    ControlBoundedContinue => exact_control_number_statement(stmt, 2.0)
  }
}

///|
fn control_lifecycle_terminal_matches(
  plan : ControlLifecyclePlan,
  stmt : @ast.Stmt,
) -> Bool {
  match plan {
    ControlLabelledBreak(_) => exact_control_number_statement(stmt, 9.0)
    ControlBoundedContinue => exact_control_number_statement(stmt, 8.0)
  }
}

///|
fn control_lifecycle_plans_match(
  expected : ControlLifecyclePlan,
  actual : ControlLifecyclePlan,
) -> Bool {
  match (expected, actual) {
    (ControlLabelledBreak(expected), ControlLabelledBreak(actual)) =>
      expected == actual
    (ControlBoundedContinue, ControlBoundedContinue) => true
    _ => false
  }
}

///|
fn classify_control_lifecycle_program(
  stmts : Array[@ast.Stmt],
) -> ControlLifecyclePlan? {
  guard stmts.length() == 2 else { return None }
  match stmts[0] {
    @ast.LabeledStmt(label, _, _) => {
      let plan = ControlLabelledBreak(label)
      guard control_lifecycle_root_matches(plan, stmts[0]) &&
        control_lifecycle_terminal_matches(plan, stmts[1]) else {
        return None
      }
      Some(plan)
    }
    @ast.DoWhileStmt(_, _, _) => {
      let plan = ControlBoundedContinue
      guard control_lifecycle_root_matches(plan, stmts[0]) &&
        control_lifecycle_terminal_matches(plan, stmts[1]) else {
        return None
      }
      Some(plan)
    }
    _ => None
  }
}

///|
fn preflight_control_lifecycle_program(
  stmts : Array[@ast.Stmt],
) -> ControlLifecyclePreflight? {
  classify_control_lifecycle_program(stmts).map(plan => {
    ControlLifecyclePreflight(plan~)
  })
}

///|
fn seal_control_lifecycle_program(
  preflight : ControlLifecyclePreflight,
  stmts : Array[@ast.Stmt],
  root_env : Environment,
) -> TrustedControlLifecycleProgram raise InvalidActivationDispatchShell {
  guard classify_control_lifecycle_program(stmts) is Some(actual) &&
    control_lifecycle_plans_match(preflight.plan, actual) else {
    invalid_activation_dispatch_shell(
      "control lifecycle program no longer matches exact admission",
    )
  }
  TrustedControlLifecycleProgram(plan=preflight.plan, root_env~)
}

///|
fn advance_control_lifecycle_phase(
  plan : ControlLifecyclePlan,
  phase : ControlLifecyclePhase,
  role : ControlLifecycleRole,
) -> ControlLifecyclePhase? {
  match (plan, phase, role) {
    (_, ControlAwaitRoot, ControlRootRole) => Some(ControlAwaitProtected)
    (_, ControlAwaitProtected, ControlProtectedRole) => Some(ControlAwaitAbrupt)
    (_, ControlAwaitAbrupt, ControlAbruptRole) => Some(ControlAwaitFinalizer)
    (ControlLabelledBreak(_), ControlAwaitFinalizer, ControlFinalizerRole) =>
      Some(ControlAwaitTerminal)
    (ControlBoundedContinue, ControlAwaitFinalizer, ControlFinalizerRole) =>
      Some(ControlAwaitLoopAdvance)
    (ControlBoundedContinue, ControlAwaitLoopAdvance, ControlLoopAdvanceRole) =>
      Some(ControlAwaitTerminal)
    (_, ControlAwaitTerminal, ControlTerminalRole) => Some(ControlFinished)
    _ => None
  }
}
