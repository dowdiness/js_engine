///|
fn is_hoisted_default_export_expr(expr : @ast.Expr) -> Bool {
  match expr {
    FuncExpr(_, _, _, _, _) | FuncExprExt(_, _, _, _, _, _) => true
    GeneratorExpr(_, _, _, _, _) | GeneratorExprExt(_, _, _, _, _, _) => true
    AsyncFuncExpr(_, _, _, _, _) | AsyncFuncExprExt(_, _, _, _, _, _) => true
    AsyncGeneratorExpr(_, _, _, _, _)
    | AsyncGeneratorExprExt(_, _, _, _, _, _) => true
    _ => false
  }
}

///|
fn Environment::bind_module_default_function_name(
  self : Environment,
  name : String,
  value : Value,
) -> Unit raise Error {
  if self.bindings.contains(name) {
    self.assign(name, value)
  } else {
    self.def(name, value, VarBinding)
  }
}

///|
fn Interpreter::predeclare_named_default_generator_export(
  self : Interpreter,
  name : String,
  params : Array[String],
  body : Array[@ast.Stmt],
  env : Environment,
  source_text : String?,
) -> Unit raise Error {
  validate_function_signature(true, Some(name), params, body)
  let value = self.make_generator_function(
    Some(name),
    params,
    None,
    body,
    is_function_strict(true, body),
    env,
    source_text~,
  )
  env.bind_module_default_function_name(name, value)
  self.predeclare_module_export_cell("default", name, env)
}

///|
fn Interpreter::predeclare_named_default_generator_export_ext(
  self : Interpreter,
  name : String,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  env : Environment,
  source_text : String?,
) -> Unit raise Error {
  validate_function_signature_ext(true, Some(name), params, rest_param, body)
  let value = self.make_generator_function_ext(
    Some(name),
    params,
    rest_param,
    body,
    is_function_strict(true, body),
    env,
    source_text~,
  )
  env.bind_module_default_function_name(name, value)
  self.predeclare_module_export_cell("default", name, env)
}

///|
fn Interpreter::predeclare_named_default_async_export(
  self : Interpreter,
  name : String,
  params : Array[String],
  body : Array[@ast.Stmt],
  env : Environment,
  source_text : String?,
) -> Unit raise Error {
  validate_function_signature(true, Some(name), params, body)
  let value = self.make_async_function(
    Some(name),
    params,
    None,
    body,
    is_function_strict(true, body),
    env,
    source_text~,
  )
  env.bind_module_default_function_name(name, value)
  self.predeclare_module_export_cell("default", name, env)
}

///|
fn Interpreter::predeclare_named_default_async_export_ext(
  self : Interpreter,
  name : String,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  env : Environment,
  source_text : String?,
) -> Unit raise Error {
  validate_function_signature_ext(true, Some(name), params, rest_param, body)
  let value = self.make_async_function_ext(
    Some(name),
    params,
    rest_param,
    body,
    is_function_strict(true, body),
    env,
    source_text~,
  )
  env.bind_module_default_function_name(name, value)
  self.predeclare_module_export_cell("default", name, env)
}

///|
fn Interpreter::predeclare_named_default_async_generator_export(
  self : Interpreter,
  name : String,
  params : Array[String],
  body : Array[@ast.Stmt],
  env : Environment,
  source_text : String?,
) -> Unit raise Error {
  validate_function_signature(true, Some(name), params, body)
  let value = self.make_async_generator_function(
    Some(name),
    params,
    None,
    body,
    is_function_strict(true, body),
    env,
    source_text~,
  )
  env.bind_module_default_function_name(name, value)
  self.predeclare_module_export_cell("default", name, env)
}

///|
fn Interpreter::predeclare_named_default_async_generator_export_ext(
  self : Interpreter,
  name : String,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  env : Environment,
  source_text : String?,
) -> Unit raise Error {
  validate_function_signature_ext(true, Some(name), params, rest_param, body)
  let value = self.make_async_generator_function_ext(
    Some(name),
    params,
    rest_param,
    body,
    is_function_strict(true, body),
    env,
    source_text~,
  )
  env.bind_module_default_function_name(name, value)
  self.predeclare_module_export_cell("default", name, env)
}

///|
fn Interpreter::predeclare_anonymous_default_function_export(
  self : Interpreter,
  params : Array[String],
  body : Array[@ast.Stmt],
  env : Environment,
  source_text : String?,
) -> Unit raise Error {
  validate_function_signature(true, None, params, body)
  let value = make_func({
    name: None,
    params,
    body,
    closure: env,
    strict: is_function_strict(true, body),
    has_name_binding: false,
    is_method: false,
    source_text,
  })
  set_function_name(value, "default")
  self.module_exports["default"] = value
}

///|
fn Interpreter::predeclare_anonymous_default_function_export_ext(
  self : Interpreter,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  env : Environment,
  source_text : String?,
) -> Unit raise Error {
  validate_function_signature_ext(true, None, params, rest_param, body)
  let value = make_func_ext({
    name: None,
    params,
    rest_param,
    body,
    closure: env,
    strict: is_function_strict(true, body),
    has_name_binding: false,
    is_method: false,
    source_text,
  })
  set_function_name(value, "default")
  self.module_exports["default"] = value
}

///|
fn Interpreter::predeclare_default_function_export(
  self : Interpreter,
  expr : @ast.Expr,
  env : Environment,
) -> Bool raise Error {
  match expr {
    FuncExpr(Some(name), _, _, _, _) | FuncExprExt(Some(name), _, _, _, _, _) => {
      self.predeclare_module_export_cell("default", name, env)
      true
    }
    GeneratorExpr(Some(name), params, body, _, source_text) => {
      self.predeclare_named_default_generator_export(
        name, params, body, env, source_text,
      )
      true
    }
    GeneratorExprExt(Some(name), params, rest_param, body, _, source_text) => {
      self.predeclare_named_default_generator_export_ext(
        name, params, rest_param, body, env, source_text,
      )
      true
    }
    AsyncFuncExpr(Some(name), params, body, _, source_text) => {
      self.predeclare_named_default_async_export(
        name, params, body, env, source_text,
      )
      true
    }
    AsyncFuncExprExt(Some(name), params, rest_param, body, _, source_text) => {
      self.predeclare_named_default_async_export_ext(
        name, params, rest_param, body, env, source_text,
      )
      true
    }
    AsyncGeneratorExpr(Some(name), params, body, _, source_text) => {
      self.predeclare_named_default_async_generator_export(
        name, params, body, env, source_text,
      )
      true
    }
    AsyncGeneratorExprExt(Some(name), params, rest_param, body, _, source_text) => {
      self.predeclare_named_default_async_generator_export_ext(
        name, params, rest_param, body, env, source_text,
      )
      true
    }
    FuncExpr(None, params, body, _, source_text) => {
      self.predeclare_anonymous_default_function_export(
        params, body, env, source_text,
      )
      true
    }
    FuncExprExt(None, params, rest_param, body, _, source_text) => {
      self.predeclare_anonymous_default_function_export_ext(
        params, rest_param, body, env, source_text,
      )
      true
    }
    GeneratorExpr(None, params, body, _, source_text) => {
      validate_function_signature(true, None, params, body)
      let value = self.make_generator_function(
        None,
        params,
        None,
        body,
        is_function_strict(true, body),
        env,
        source_text~,
      )
      set_function_name(value, "default")
      self.module_exports["default"] = value
      true
    }
    GeneratorExprExt(None, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(true, None, params, rest_param, body)
      let value = self.make_generator_function_ext(
        None,
        params,
        rest_param,
        body,
        is_function_strict(true, body),
        env,
        source_text~,
      )
      set_function_name(value, "default")
      self.module_exports["default"] = value
      true
    }
    AsyncFuncExpr(None, params, body, _, source_text) => {
      validate_function_signature(true, None, params, body)
      let value = self.make_async_function(
        None,
        params,
        None,
        body,
        is_function_strict(true, body),
        env,
        source_text~,
      )
      set_function_name(value, "default")
      self.module_exports["default"] = value
      true
    }
    AsyncFuncExprExt(None, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(true, None, params, rest_param, body)
      let value = self.make_async_function_ext(
        None,
        params,
        rest_param,
        body,
        is_function_strict(true, body),
        env,
        source_text~,
      )
      set_function_name(value, "default")
      self.module_exports["default"] = value
      true
    }
    AsyncGeneratorExpr(None, params, body, _, source_text) => {
      validate_function_signature(true, None, params, body)
      let value = self.make_async_generator_function(
        None,
        params,
        None,
        body,
        is_function_strict(true, body),
        env,
        source_text~,
      )
      set_function_name(value, "default")
      self.module_exports["default"] = value
      true
    }
    AsyncGeneratorExprExt(None, params, rest_param, body, _, source_text) => {
      validate_function_signature_ext(true, None, params, rest_param, body)
      let value = self.make_async_generator_function_ext(
        None,
        params,
        rest_param,
        body,
        is_function_strict(true, body),
        env,
        source_text~,
      )
      set_function_name(value, "default")
      self.module_exports["default"] = value
      true
    }
    _ => false
  }
}
