///|
/// Run an already-compiled script body through the same script setup envelope
/// used by `Interpreter::run`.
///
/// Closure conversion lives outside the runtime package, but script execution
/// setup owns private runtime state: the active interpreter ref, static early
/// errors, declaration hoisting, and conversion of engine errors into JS
/// exceptions. Keeping that envelope here lets compiled execution share the
/// same boundary without exposing those internals.
pub fn Interpreter::run_compiled_script(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  eval : (ExecContext, Environment) -> Value raise Error,
) -> Value raise Error {
  let strict = has_use_strict(stmts)
  let ctx : ExecContext = { strict, current_generator: None }
  try {
    let result = with_cleared_active_callee_realm(self.realm_state, fn() raise {
      self.validate_block_early_errors(stmts, strict)
      self.hoist_declarations(stmts, self.global, strict~)
      eval(ctx, self.global)
    })
    result
  } catch {
    e =>
      if is_js_catchable_error(e) {
        raise JsException(js_error_to_value_with_env(e, Some(self.global)))
      } else {
        raise e
      }
  }
}

///|
/// Run a public runtime entry point with this interpreter installed as the
/// active realm for compatibility factory lookups.
pub fn Interpreter::with_active_value(
  self : Interpreter,
  eval : () -> Value raise Error,
) -> Value raise Error {
  with_cleared_active_callee_realm(self.realm_state, fn() raise { eval() })
}
