///|
/// Resolve an identifier for compiled execution using the same runtime
/// fallback as the tree-walking interpreter.
pub fn Interpreter::get_compiled_name(
  self : Interpreter,
  env : Environment,
  name : String,
) -> Value raise Error {
  env.get(name) catch {
    @errors.ReferenceError(message~) =>
      if message == "\{name} is not defined" {
        match self.global_this {
          Value::Object(data) =>
            match data.bag.properties.get(name) {
              Some(value) => value
              None =>
                raise @errors.ReferenceError(message="\{name} is not defined")
            }
          _ => raise @errors.ReferenceError(message="\{name} is not defined")
        }
      } else {
        raise @errors.ReferenceError(message~)
      }
    other => raise other
  }
}

///|
/// Resolve `typeof name` for compiled execution using the same identifier
/// reference special case as the tree-walking interpreter: unresolved names
/// produce "undefined", while TDZ bindings still raise.
pub fn Interpreter::typeof_compiled_name(
  self : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
) -> Value raise Error {
  validate_strict_identifier_reference(ctx.strict, name)
  if env.has(name) {
    String_(type_of(env.get(name)))
  } else {
    match self.global_this {
      Value::Object(data) =>
        match data.bag.properties.get(name) {
          Some(value) => String_(type_of(value))
          None => String_("undefined")
        }
      _ => String_("undefined")
    }
  }
}

///|
/// Assign an identifier for compiled execution without duplicating global
/// object, strict-mode, or implicit-global assignment rules in the compiler.
pub fn Interpreter::assign_compiled_name(
  self : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
  value : Value,
) -> Value raise Error {
  validate_strict_assignment_target_name(ctx.strict, name)
  if self.is_immutable_global(name) {
    if ctx.strict {
      raise @errors.TypeError(
        message="Cannot assign to read only property '\{name}' of object '[object global]'",
      )
    }
    return value
  }
  env.assign(name, value) catch {
    @errors.ReferenceError(_) =>
      if !ctx.strict {
        self.global.def(name, value, VarBinding)
        self.mirror_to_global(name, value, configurable=true)
      } else {
        raise @errors.ReferenceError(message="\{name} is not defined")
      }
    e => raise e
  }
  value
}

///|
/// Update an identifier for compiled execution while keeping strict-mode and
/// immutable-global behavior owned by the runtime.
pub fn Interpreter::update_compiled_name(
  self : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
  op : @ast.UpdateOp,
  prefix : Bool,
  _loc : @token.Loc,
) -> Value raise Error {
  validate_strict_assignment_target_name(ctx.strict, name)
  let old_value = env.get(name)
  let old_number = to_number(old_value, interp=Some(self))
  let next_value = match op {
    Increment => Value::Number(old_number + 1.0)
    Decrement => Value::Number(old_number - 1.0)
  }
  if self.is_immutable_global(name) {
    if ctx.strict {
      raise @errors.TypeError(
        message="Cannot assign to read only property '\{name}' of object '[object global]'",
      )
    }
  } else {
    env.assign(name, next_value)
  }
  if prefix {
    next_value
  } else {
    Value::Number(old_number)
  }
}

///|
pub fn Interpreter::define_compiled_binding(
  self : Interpreter,
  env : Environment,
  kind : @ast.VarKind,
  name : String,
  value : Value,
  has_initializer : Bool,
) -> Unit raise Error {
  let binding_kind : BindingKind = match kind {
    LetKind => LetBinding
    ConstKind => ConstBinding
    VarKind => VarBinding
  }
  if binding_kind == VarBinding &&
    (env.bindings.contains(name) || env.has_var(name)) {
    if has_initializer {
      env.assign_var(name, value)
      if physical_equal(env.find_var_env(), self.global) {
        self.mirror_to_global(name, value)
      }
    }
  } else if (binding_kind == LetBinding || binding_kind == ConstBinding) &&
    env.bindings.contains(name) {
    env.initialize(name, value)
  } else {
    env.def(name, value, binding_kind)
    if binding_kind == VarBinding &&
      physical_equal(env.find_var_env(), self.global) {
      self.mirror_to_global(name, value)
    }
  }
}

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
  let strict = @static_semantics.has_use_strict(stmts)
  let ctx : ExecContext = { strict, current_generator: None }
  try {
    let result = with_cleared_active_callee_realm(self.realm_state, fn() raise {
      self.validate_block_early_errors(stmts, strict)
      self.hoist_declarations(stmts, self.global, strict~)
      hoist_block_tdz(stmts, self.global)
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
