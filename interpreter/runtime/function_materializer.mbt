///|
// Executor-neutral function creation capability.  The runtime owns the
// request shape and callable shell; compiler code may provide a materializer
// without importing compiler representations into this package.
pub(all) enum FunctionMaterializationForm {
  FunctionDeclaration
  FunctionExpression
  NamedFunctionExpression
  MethodFunction
  ComputedMethodFunction
  ArrowFunction
} derive(Eq)

///|
pub(all) enum FunctionMaterializationParameters {
  SimpleFunctionParameters(Array[String])
  ExtendedFunctionParameters(Array[@ast.Param], String?)
}

///|
pub(all) struct FunctionMaterializationRequest {
  form : FunctionMaterializationForm
  name : String?
  parameters : FunctionMaterializationParameters
  body : Array[@ast.Stmt]
  closure : Environment
  strict : Bool
  source_text : String?
}

///| 
// Runtime-owned lifecycle hooks let a compiler-provided capability record
// the actual activation boundary without exposing compiler representations to
// this package.
pub(all) struct FunctionExecutionHooks {
  start : () -> Unit raise Error
  complete : (Bool) -> Unit raise Error
}

///|
pub fn FunctionExecutionHooks::FunctionExecutionHooks(
  start~ : () -> Unit raise Error,
  complete~ : (Bool) -> Unit raise Error,
) -> FunctionExecutionHooks {
  { start, complete }
}

///|
pub fn FunctionMaterializationRequest::FunctionMaterializationRequest(
  form~ : FunctionMaterializationForm,
  name~ : String?,
  parameters~ : FunctionMaterializationParameters,
  body~ : Array[@ast.Stmt],
  closure~ : Environment,
  strict~ : Bool,
  source_text~ : String?,
) -> FunctionMaterializationRequest {
  { form, name, parameters, body, closure, strict, source_text }
}

///|
pub(all) struct FunctionMaterializer {
  begin : () -> FunctionMaterializer
  materialize : (Interpreter, FunctionMaterializationRequest) -> Value raise Error
  hooks : FunctionExecutionHooks?
}

///|
pub fn FunctionMaterializer::FunctionMaterializer(
  begin~ : () -> FunctionMaterializer,
  materialize~ : (Interpreter, FunctionMaterializationRequest) -> Value raise Error,
  hooks? : FunctionExecutionHooks? = None,
) -> FunctionMaterializer {
  { begin, materialize, hooks }
}

///|
fn function_materialization_name(
  form : FunctionMaterializationForm,
  name : String?,
) -> String {
  match form {
    ArrowFunction => ""
    _ => name.unwrap_or("")
  }
}

///|
fn function_materialization_is_method(form : FunctionMaterializationForm) -> Bool {
  match form {
    MethodFunction | ComputedMethodFunction => true
    _ => false
  }
}

///|
fn function_materialization_has_name_binding(
  form : FunctionMaterializationForm,
) -> Bool {
  form is NamedFunctionExpression
}

///|
// Materialize a normal tree-walker callable from an executor-neutral request.
// The optional child capability is retained by the resulting function value,
// so later activations do not consult an Engine-global candidate program.
pub fn make_materialized_tree_function(
  request : FunctionMaterializationRequest,
  child_materializer : FunctionMaterializer?,
) -> Value {
  let name = function_materialization_name(request.form, request.name)
  let is_method = function_materialization_is_method(request.form)
  let has_name_binding = function_materialization_has_name_binding(request.form)
  match request.parameters {
    SimpleFunctionParameters(params) => {
      let data : FuncData = {
        name: request.name,
        params,
        body: request.body,
        closure: request.closure,
        strict: request.strict,
        has_name_binding,
        is_method,
        source_text: request.source_text,
        materializer: child_materializer,
      }
      match request.form {
        ArrowFunction => {
          build_func_object(
            name,
            data.params.length(),
            ArrowFunc(data),
            realm_state=request.closure.realm_state,
          )
        }
        _ => make_func(data)
      }
    }
    ExtendedFunctionParameters(params, rest_param) => {
      let data : FuncDataExt = {
        name: request.name,
        params,
        rest_param,
        body: request.body,
        closure: request.closure,
        strict: request.strict,
        has_name_binding,
        is_method,
        source_text: request.source_text,
        materializer: child_materializer,
      }
      match request.form {
        ArrowFunction => {
          build_func_object(
            name,
            expected_argument_count_ext(data.params),
            ArrowFuncExt(data),
            realm_state=request.closure.realm_state,
          )
        }
        _ => make_func_ext(data)
      }
    }
  }
}

///|
// Select the candidate capability for a newly evaluated function definition.
// With no active capability this is exactly the legacy tree-walker factory.
fn Interpreter::materialize_function(
  self : Interpreter,
  request : FunctionMaterializationRequest,
) -> Value raise Error {
  match self.active_function_materializer {
    Some(materializer) => (materializer.materialize)(self, request)
    None => make_materialized_tree_function(request, None)
  }
}

///|
// Install a capability only for the dynamic extent of one root/function
// activation. Restoration is performed on both normal and abrupt exits.
pub fn[T] Interpreter::with_function_materializer(
  self : Interpreter,
  materializer : FunctionMaterializer?,
  thunk : () -> T raise Error,
) -> T raise Error {
  let previous = self.active_function_materializer
  self.active_function_materializer = materializer
  let result : T = thunk() catch {
    error => {
      self.active_function_materializer = previous
      raise error
    }
  }
  self.active_function_materializer = previous
  result
}

///|
// Run one UserFunc/ArrowFunc activation with its own immutable child cursor.
// The capability's lifecycle hooks mark the actual start/completion boundary;
// no caller can transition a started activation to another executor.
pub fn[T] Interpreter::run_materialized_function(
  self : Interpreter,
  materializer : FunctionMaterializer?,
  thunk : () -> T raise Error,
) -> T raise Error {
  let active = materializer.map(capability => (capability.begin)())
  let hooks : FunctionExecutionHooks? = match active {
    Some(capability) => capability.hooks
    None => None
  }
  match hooks {
    Some(h) => (h.start)()
    None => ()
  }
  let previous = self.active_function_materializer
  self.active_function_materializer = active
  let result : T = thunk() catch {
    error => {
      self.active_function_materializer = previous
      match hooks {
        Some(h) => (h.complete)(false)
        None => ()
      }
      raise error
    }
  }
  self.active_function_materializer = previous
  match hooks {
    Some(h) => (h.complete)(true)
    None => ()
  }
  result
}

///|
fn callable_has_function_materializer(value : Value) -> Bool {
  match value {
    Object(data) => match data.callable {
      Some(UserFunc(func_data)) => func_data.materializer is Some(_)
      Some(UserFuncExt(func_data)) => func_data.materializer is Some(_)
      Some(ArrowFunc(func_data)) => func_data.materializer is Some(_)
      Some(ArrowFuncExt(func_data)) => func_data.materializer is Some(_)
      _ => false
    }
    _ => false
  }
}

///|
// Candidate tree roots intentionally bypass the legacy activation-dispatch
// admission gate. Their selected tree route is already settled by the
// compiler, and this method only supplies the ordinary root shell plus the
// capability that materializes independent child functions.
pub fn Interpreter::run_with_function_materializer(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  materializer : FunctionMaterializer,
) -> Value raise Error {
  let strict = @static_semantics.has_use_strict(stmts)
  let ctx : ExecContext = { strict, current_generator: None }
  try {
    self.run_materialized_function(Some(materializer), fn() raise {
      with_cleared_active_callee_realm(self.realm_state, () => {
        self.prepare_root_program_execution(stmts, self.global, strict)
        let mut last : Value = Undefined
        for stmt in stmts {
          match self.exec_stmt(ctx, stmt, self.global) {
            Normal(v) => last = v
            ReturnSignal(_) =>
              raise @errors.SyntaxError(
                message="return statement outside of function",
              )
            sig => raise_if_break_continue(sig)
          }
        }
        last
      })
    })
  } catch {
    error =>
      if is_js_catchable_error(error) {
        let translated = JsException(
          js_error_to_value_with_env(error, Some(self.global)),
        )
        remap_observed_source_failure(self.realm_state, error, translated)
        raise translated
      } else {
        raise error
      }
  }
}
