// Imperative adapter for the first production activation-dispatch slice.
// Admission proves that every statement is a synchronous leaf before any
// JavaScript-visible effect. Once admitted, execution stays inside this loop;
// unsupported effects are invariant failures, never legacy fallbacks.

///|
priv suberror InvalidActivationDispatchShell {
  InvalidActivationDispatchShell(String)
}

///|
fn[T] invalid_activation_dispatch_shell(
  message : String,
) -> T raise InvalidActivationDispatchShell {
  raise InvalidActivationDispatchShell(message)
}

///|
priv enum ProgramCleanupOwner {
  AcceptedProgram
  RejectedProgram
}

///|
const MAX_DISPATCH_CLEANUP_ID = 2147483647

///|
priv struct ProgramRealmCleanup {
  id : Int
  owner : ProgramCleanupOwner
  previous_realm_protos : FunctionRealmProtos
}

///|
priv struct PrimitiveProgramDispatchShell {
  interp : Interpreter
  cleanup_stack : Array[ProgramRealmCleanup]
  mut next_cleanup_id : Int
}

///|
fn PrimitiveProgramDispatchShell::PrimitiveProgramDispatchShell(
  interp : Interpreter,
) -> PrimitiveProgramDispatchShell {
  { interp, cleanup_stack: [], next_cleanup_id: 0 }
}

///|
fn activation_dispatch_leaf_expression_is_admissible(expr : @ast.Expr) -> Bool {
  match expr {
    @ast.NumberLit(_, _, _)
    | @ast.StringLit(_, _, _, _)
    | @ast.BoolLit(_, _)
    | @ast.NullLit(_)
    | @ast.UndefinedLit(_) => true
    _ => false
  }
}

///|
fn activation_dispatch_leaf_statement_is_admissible(stmt : @ast.Stmt) -> Bool {
  match stmt {
    @ast.ExprStmt(expr, _) | @ast.ThrowStmt(expr, _) =>
      activation_dispatch_leaf_expression_is_admissible(expr)
    _ => false
  }
}

///|
fn activation_dispatch_leaf_program_is_admissible(
  stmts : Array[@ast.Stmt],
) -> Bool {
  for stmt in stmts {
    guard activation_dispatch_leaf_statement_is_admissible(stmt) else {
      return false
    }
  }
  true
}

///|
fn Interpreter::prepare_root_program_execution(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
  strict : Bool,
) -> Unit raise Error {
  self.validate_block_early_errors(stmts, strict)
  self.hoist_declarations(stmts, env, strict~)
  hoist_block_tdz(stmts, env)
}

///|
fn dispatch_entry_rejection(error : Error) -> DispatchEntryRejection {
  if is_js_catchable_error(error) {
    DispatchEntryGuestThrow(error)
  } else {
    DispatchEntryRuntimeAbrupt(error)
  }
}

///|
fn dispatch_work_error_completion(error : Error) -> DispatchCompletion {
  if is_js_catchable_error(error) {
    DispatchThrow(error)
  } else {
    DispatchRuntimeAbrupt(error)
  }
}

///|
fn dispatch_signal_completion(signal : Signal) -> DispatchCompletion {
  match signal {
    Normal(value) => DispatchNormal(value)
    ReturnSignal(value) => DispatchReturn(value)
    BreakSignal(value, label) => DispatchBreak(value, label)
    ContinueSignal(value, label) => DispatchContinue(value, label)
  }
}

///|
fn program_cleanup_owner_matches(
  actual : ProgramCleanupOwner,
  expected : ProgramCleanupOwner,
) -> Bool {
  match (actual, expected) {
    (AcceptedProgram, AcceptedProgram) | (RejectedProgram, RejectedProgram) =>
      true
    _ => false
  }
}

///|
fn PrimitiveProgramDispatchShell::reserve_program_cleanup_id(
  self : PrimitiveProgramDispatchShell,
) -> Int raise InvalidActivationDispatchShell {
  guard self.next_cleanup_id >= 0 &&
    self.next_cleanup_id < MAX_DISPATCH_CLEANUP_ID else {
    invalid_activation_dispatch_shell("cleanup generation is exhausted")
  }
  let id = self.next_cleanup_id
  self.next_cleanup_id += 1
  id
}

///|
fn PrimitiveProgramDispatchShell::push_program_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  owner : ProgramCleanupOwner,
  previous_realm_protos : FunctionRealmProtos,
) -> Unit {
  self.cleanup_stack.push({ id, owner, previous_realm_protos })
}

///|
fn PrimitiveProgramDispatchShell::consume_program_cleanup(
  self : PrimitiveProgramDispatchShell,
  id : Int,
  expected_owner : ProgramCleanupOwner,
) -> Unit raise InvalidActivationDispatchShell {
  guard !self.cleanup_stack.is_empty() else {
    invalid_activation_dispatch_shell(
      "cleanup is stale, duplicated, or outside LIFO order",
    )
  }
  let cleanup = self.cleanup_stack[self.cleanup_stack.length() - 1]
  guard id == cleanup.id else {
    invalid_activation_dispatch_shell(
      "cleanup is stale, duplicated, or outside LIFO order",
    )
  }
  guard program_cleanup_owner_matches(cleanup.owner, expected_owner) else {
    invalid_activation_dispatch_shell("cleanup owner does not match its exit")
  }
  let _ = self.cleanup_stack.pop()
  apply_active_realm_protos(
    self.interp.realm_state,
    cleanup.previous_realm_protos,
  )
}

///|
fn PrimitiveProgramDispatchShell::restore_all_cleanup(
  self : PrimitiveProgramDispatchShell,
) -> Unit {
  while !self.cleanup_stack.is_empty() {
    match self.cleanup_stack.pop() {
      Some(cleanup) =>
        apply_active_realm_protos(
          self.interp.realm_state,
          cleanup.previous_realm_protos,
        )
      None => ()
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::enter_program(
  self : PrimitiveProgramDispatchShell,
  cursor : DispatchStatementCursor,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let id = self.reserve_program_cleanup_id()
  let previous_realm_protos = active_realm_protos(self.interp.realm_state)
  apply_active_realm_protos(
    self.interp.realm_state,
    empty_function_realm_protos(),
  )
  let setup : Result[Unit, Error] = Ok(
    self.interp.prepare_root_program_execution(
      cursor.stmts,
      cursor.env,
      cursor.ctx.strict,
    ),
  ) catch {
    error => Err(error)
  }
  match setup {
    Ok(_) => {
      self.push_program_cleanup(id, AcceptedProgram, previous_realm_protos)
      DispatchProgramAccepted(DispatchActivationCleanup(id))
    }
    Err(error) => {
      self.push_program_cleanup(id, RejectedProgram, previous_realm_protos)
      DispatchActivationRejected(
        DispatchRejectedEntryCleanup(id),
        dispatch_entry_rejection(error),
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_leaf_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  guard activation_dispatch_leaf_statement_is_admissible(step.stmt) else {
    invalid_activation_dispatch_shell(
      "managed leaf execution received an unsupported statement",
    )
  }
  let result : Result[Signal, Error] = Ok(
    self.interp.exec_stmt(step.ctx, step.stmt, step.env),
  ) catch {
    error => Err(error)
  }
  match result {
    Ok(signal) => DispatchWorkCompleted(dispatch_signal_completion(signal))
    Err(error) => DispatchWorkCompleted(dispatch_work_error_completion(error))
  }
}

///|
fn PrimitiveProgramDispatchShell::perform_effect(
  self : PrimitiveProgramDispatchShell,
  effect : DispatchEffect,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  match effect {
    DispatchEnterActivation(DispatchProgramActivation(cursor)) =>
      self.enter_program(cursor)
    DispatchEnterActivation(DispatchCallActivation(_)) =>
      invalid_activation_dispatch_shell(
        "leaf program shell cannot enter a call activation",
      )
    DispatchRun(DispatchExecuteStatement(step)) =>
      self.execute_leaf_statement(step)
    DispatchRun(_) =>
      invalid_activation_dispatch_shell(
        "leaf program shell received unsupported managed work",
      )
    DispatchReleaseActivation(cleanup, _) => {
      self.consume_program_cleanup(cleanup.id, AcceptedProgram)
      DispatchCleanupCompleted
    }
    DispatchRollbackRejectedEntry(cleanup, _) => {
      self.consume_program_cleanup(cleanup.id, RejectedProgram)
      DispatchCleanupCompleted
    }
    DispatchRestorePropertyScope(_, _) =>
      invalid_activation_dispatch_shell(
        "leaf program shell cannot restore a property scope",
      )
    DispatchNormalizeEscapedControl(_) =>
      invalid_activation_dispatch_shell(
        "leaf program shell cannot normalize function control",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::drive(
  self : PrimitiveProgramDispatchShell,
  request : DispatchActivationRequest,
) -> DispatchCompletion raise Error {
  let mut state = ActivationDispatchState::ActivationDispatchState()
  let mut event = DispatchStart(request)
  for ;; {
    let (next_state, decision) = reduce_activation_dispatch(state, event)
    state = next_state
    match decision {
      DispatchFinish(completion) => return completion
      DispatchPerform(ticket, effect) => {
        let result = self.perform_effect(effect)
        event = DispatchEffectCompleted(ticket, result)
      }
    }
  }
}

///|
fn Interpreter::run_activation_dispatch_leaf_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  ctx : ExecContext,
) -> DispatchCompletion raise Error {
  guard activation_dispatch_leaf_program_is_admissible(stmts) else {
    invalid_activation_dispatch_shell(
      "program admission must succeed before managed execution starts",
    )
  }
  let shell = PrimitiveProgramDispatchShell(self)
  try {
    let completion = shell.drive(
      DispatchProgramActivation(
        DispatchStatementCursor(ctx~, stmts~, env=self.global),
      ),
    )
    guard shell.cleanup_stack.is_empty() else {
      invalid_activation_dispatch_shell(
        "dispatch finished while cleanup ownership remained",
      )
    }
    completion
  } catch {
    error => {
      shell.restore_all_cleanup()
      raise error
    }
  }
}

///|
fn activation_dispatch_root_value(
  completion : DispatchCompletion,
) -> Value raise Error {
  match completion {
    DispatchNormal(value) => value
    DispatchReturn(_) =>
      raise @errors.SyntaxError(message="return statement outside of function")
    DispatchBreak(value, label) => {
      raise_if_break_continue(BreakSignal(value, label))
      Undefined
    }
    DispatchContinue(value, label) => {
      raise_if_break_continue(ContinueSignal(value, label))
      Undefined
    }
    DispatchThrow(error) | DispatchRuntimeAbrupt(error) => raise error
  }
}
