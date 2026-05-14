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
  let prev_interpreter = current_interpreter.val
  current_interpreter.val = Some(self)
  let strict = has_use_strict(stmts)
  let ctx : ExecContext = { strict, current_generator: None }
  try {
    self.validate_block_early_errors(stmts, strict)
    self.hoist_declarations(stmts, self.global, strict~)
    let result = eval(ctx, self.global)
    current_interpreter.val = prev_interpreter
    result
  } catch {
    e => {
      current_interpreter.val = prev_interpreter
      if is_js_catchable_error(e) {
        raise JsException(js_error_to_value_with_env(e, Some(self.global)))
      } else {
        raise e
      }
    }
  }
}
