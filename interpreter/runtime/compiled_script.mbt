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
/// Resolve `typeof name` for compiled and tree-walking execution using the
/// same identifier-reference semantics: unresolved names produce
/// "undefined", while TDZ bindings and a selected dynamic binding that
/// disappears during resolution still raise.
pub fn Interpreter::typeof_compiled_name(
  self : Interpreter,
  ctx : ExecContext,
  env : Environment,
  name : String,
) -> Value raise Error {
  @static_semantics.validate_strict_identifier_reference(ctx.strict, name)
  let value = env.get_with_strict(name, ctx.strict) catch {
    @errors.ReferenceError(message~) =>
      if message == with_object_binding_missing_message(name) {
        raise @errors.ReferenceError(message="\{name} is not defined")
      } else if message == "\{name} is not defined" {
        match self.global_this {
          Value::Object(data) =>
            match data.bag.properties.get(name) {
              Some(value) => value
              None => Undefined
            }
          _ => Undefined
        }
      } else {
        raise @errors.ReferenceError(message~)
      }
    other => raise other
  }
  String_(type_of(value))
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
  @static_semantics.validate_strict_assignment_target_name(ctx.strict, name)
  if self.is_immutable_global(name) {
    if ctx.strict {
      raise @errors.TypeError(
        message="Cannot assign to read only property '\{name}' of object '[object global]'",
      )
    }
    return value
  }
  env.assign_with_strict(name, value, ctx.strict) catch {
    @errors.ReferenceError(_) =>
      if self.has_property_key(self.global_this, String_(name)) {
        let _ = self.set_property(
          self.global_this,
          name,
          value,
          @token.Loc::default(),
          strict=ctx.strict,
        )
      } else if !ctx.strict {
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
  loc : @token.Loc,
) -> Value raise Error {
  self.run_binding_update_to_completion(ctx, env, name, op, prefix, loc)
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
  match binding_kind {
    VarBinding => {
      // A var declaration belongs to this activation's nearest variable
      // environment. A same-named var in an enclosing activation must not
      // suppress creation of the local cell: captured bytecode slots retain
      // that cell before function declarations initialize it.
      let var_env = env.find_var_env()
      let binding_existed = var_env.bindings.contains(name)
      if binding_existed {
        if has_initializer {
          var_env.assign_var(name, value)
        }
      } else {
        var_env.def(name, value, VarBinding)
      }
      if physical_equal(var_env, self.global) &&
        (has_initializer || !binding_existed) {
        self.mirror_to_global(name, value)
      }
    }
    LetBinding | ConstBinding =>
      if env.bindings.contains(name) {
        env.initialize(name, value)
      } else {
        env.def(name, value, binding_kind)
      }
    FunctionNameBinding =>
      raise @errors.InternalError(
        message="compiled declaration cannot define a function-name binding",
      )
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
pub fn Interpreter::run_prepared_compiled_script(
  self : Interpreter,
  preparation : CompiledScriptPreparation,
  eval : (ExecContext, Environment) -> Value raise Error,
) -> Value raise Error {
  let strict = preparation.strict
  let ctx : ExecContext = { strict, current_generator: None }
  try {
    let result = with_cleared_active_callee_realm(self.realm_state, fn() raise {
      self.apply_compiled_script_preparation(preparation)
      eval(ctx, self.global)
    })
    result
  } catch {
    e =>
      if is_js_catchable_error(e) {
        let translated = JsException(
          js_error_to_value_with_env(e, Some(self.global)),
        )
        remap_observed_source_failure(self.realm_state, e, translated)
        raise translated
      } else {
        raise e
      }
  }
}

///|
// Compatibility adapter for direct dependents of the historical AST entry.
// This path remains AST-consuming and runtime-owned; finalized bytecode uses
// run_prepared_compiled_script instead.
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
        let translated = JsException(
          js_error_to_value_with_env(e, Some(self.global)),
        )
        remap_observed_source_failure(self.realm_state, e, translated)
        raise translated
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
