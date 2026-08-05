// Runtime provenance sealing for the closed direct-return ordinary-function
// slice. No guest lookup or callback is performed after the root is sealed.

///|
priv struct DirectReturnRecursionPreflight {
  plan : DirectReturnRecursionPlan
  previous_entry_object : ObjectData?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
priv struct TrustedDirectReturnRecursionFunction {
  syntax : DirectReturnFunctionSyntax
  callee : Value
  params : Array[String]
  body : Array[@ast.Stmt]
  source_text : String?
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
priv struct TrustedDirectReturnRecursionRegistry {
  plan : DirectReturnRecursionPlan
  entry : TrustedDirectReturnRecursionFunction
  throw_type_error : Value?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
}

///|
fn DirectReturnRecursionPreflight::DirectReturnRecursionPreflight(
  plan~ : DirectReturnRecursionPlan,
  previous_entry_object~ : ObjectData?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> DirectReturnRecursionPreflight {
  {
    plan,
    previous_entry_object,
    throw_type_error_snapshot,
    expected_global_object,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
fn TrustedDirectReturnRecursionFunction::TrustedDirectReturnRecursionFunction(
  syntax~ : DirectReturnFunctionSyntax,
  callee~ : Value,
  params~ : Array[String],
  body~ : Array[@ast.Stmt],
  source_text~ : String?,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedDirectReturnRecursionFunction {
  {
    syntax,
    callee,
    params,
    body,
    source_text,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
fn TrustedDirectReturnRecursionRegistry::TrustedDirectReturnRecursionRegistry(
  plan~ : DirectReturnRecursionPlan,
  entry~ : TrustedDirectReturnRecursionFunction,
  throw_type_error~ : Value?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
) -> TrustedDirectReturnRecursionRegistry {
  {
    plan,
    entry,
    throw_type_error,
    throw_type_error_snapshot,
    expected_global_object,
  }
}

///|
fn direct_return_closed_literals_match(
  expected : DirectReturnClosedLiteral,
  actual : DirectReturnClosedLiteral,
) -> Bool {
  match (expected, actual) {
    (DirectReturnClosedNull, DirectReturnClosedNull)
    | (DirectReturnClosedUndefined, DirectReturnClosedUndefined) => true
    (DirectReturnClosedNumber(expected), DirectReturnClosedNumber(actual)) =>
      expected == actual
    (DirectReturnClosedString(expected), DirectReturnClosedString(actual)) =>
      expected == actual
    (DirectReturnClosedBool(expected), DirectReturnClosedBool(actual)) =>
      expected == actual
    _ => false
  }
}

///|
fn direct_return_base_completions_match(
  expected : DirectReturnBaseCompletion,
  actual : DirectReturnBaseCompletion,
) -> Bool {
  match (expected, actual) {
    (DirectReturnBaseValue(expected), DirectReturnBaseValue(actual))
    | (DirectReturnBaseThrow(expected), DirectReturnBaseThrow(actual)) =>
      direct_return_closed_literals_match(expected, actual)
    _ => false
  }
}

///|
fn direct_return_function_syntaxes_match(
  expected : DirectReturnFunctionSyntax,
  actual : DirectReturnFunctionSyntax,
) -> Bool {
  expected.name == actual.name &&
  expected.parameter == actual.parameter &&
  expected.recursive_callee == actual.recursive_callee &&
  expected.base_condition_loc == actual.base_condition_loc &&
  expected.base_literal_loc == actual.base_literal_loc &&
  expected.recursive_call_loc == actual.recursive_call_loc &&
  expected.recursive_subtract_loc == actual.recursive_subtract_loc &&
  direct_return_base_completions_match(
    expected.base_completion,
    actual.base_completion,
  )
}

///|
fn direct_return_function_plans_match(
  expected : DirectReturnFunctionPlan,
  actual : DirectReturnFunctionPlan,
) -> Bool {
  expected.declaration_index == actual.declaration_index &&
  direct_return_function_syntaxes_match(expected.syntax, actual.syntax)
}

///|
fn direct_return_recursion_plans_match(
  expected : DirectReturnRecursionPlan,
  actual : DirectReturnRecursionPlan,
) -> Bool {
  expected.initial_argument == actual.initial_argument &&
  expected.root_call_loc == actual.root_call_loc &&
  direct_return_function_plans_match(expected.entry, actual.entry)
}

///|
fn direct_return_throw_type_error_value(
  snapshot : CallbackFreeBindingSnapshot,
) -> Value? raise InvalidActivationDispatchShell {
  match snapshot {
    CallbackFreeBindingMissing => None
    CallbackFreeBindingPresent(value) => Some(value)
    CallbackFreeBindingUnsafe =>
      invalid_activation_dispatch_shell(
        "direct-return ThrowTypeError binding became callback-capable",
      )
  }
}

///|
fn direct_return_throw_type_error_snapshot_matches(
  expected : CallbackFreeBindingSnapshot,
  actual : CallbackFreeBindingSnapshot,
) -> Bool {
  numeric_recursion_callback_free_binding_snapshots_match(expected, actual)
}

///|
fn Interpreter::preflight_direct_return_recursion_program(
  self : Interpreter,
  plan : DirectReturnRecursionPlan,
) -> DirectReturnRecursionPreflight? {
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) else {
    return None
  }
  guard numeric_recursion_global_declaration_is_sealable(
    expected_global_object,
    plan.entry.syntax.name,
  ) else {
    return None
  }
  let (entry_ok, previous_entry_object) = numeric_recursion_existing_binding_snapshot(
    self.global,
    plan.entry.syntax.name,
  )
  guard entry_ok else { return None }
  let throw_type_error_snapshot = numeric_recursion_callback_free_throw_type_error(
    self.global,
  )
  match throw_type_error_snapshot {
    CallbackFreeBindingUnsafe => return None
    _ => ()
  }
  Some(
    DirectReturnRecursionPreflight(
      plan~,
      previous_entry_object~,
      throw_type_error_snapshot~,
      expected_global_object~,
      expected_realm_protos=function_realm_protos_from_realm_state(
        self.realm_state,
      ),
      expected_source_identity=self.realm_state.active_source_identity.val,
    ),
  )
}

///|
fn Interpreter::preflight_dispatchable_direct_return_recursion_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> DirectReturnRecursionPreflight? {
  match classify_direct_return_recursion_program(stmts) {
    Some(plan) => self.preflight_direct_return_recursion_program(plan)
    None => None
  }
}

///|
fn direct_return_recursion_trusted_declaration(
  interp : Interpreter,
  plan : DirectReturnFunctionPlan,
  previous_object~ : ObjectData?,
  expected_global_object~ : ObjectData,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
  stmts~ : Array[@ast.Stmt],
) -> TrustedDirectReturnRecursionFunction raise InvalidActivationDispatchShell {
  guard plan.declaration_index >= 0 && plan.declaration_index < stmts.length() else {
    invalid_activation_dispatch_shell(
      "direct-return declaration index is outside the admitted program",
    )
  }
  guard stmts[plan.declaration_index]
    is @ast.FuncDecl(ast_name, ast_params, ast_body, _, ast_source_text) else {
    invalid_activation_dispatch_shell(
      "direct-return declaration no longer matches its admitted syntax",
    )
  }
  let syntax = plan.syntax
  guard interp.global.bindings.get(syntax.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding else {
    invalid_activation_dispatch_shell(
      "direct-return declaration binding was not created by root hoisting",
    )
  }
  let callee = binding.value
  guard callee is Object(object_identity) &&
    object_identity.class_name == "Function" else {
    invalid_activation_dispatch_shell(
      "direct-return declaration did not hoist a function object",
    )
  }
  guard interp.global_this is Object(global_object) &&
    physical_equal(global_object, expected_global_object) &&
    global_object.bag.properties.get(syntax.name) is Some(Object(mirrored)) &&
    physical_equal(mirrored, object_identity) &&
    numeric_recursion_global_property_is_canonical(global_object, syntax.name) else {
    invalid_activation_dispatch_shell(
      "direct-return declaration diverged from its global mirror",
    )
  }
  match previous_object {
    Some(previous) if physical_equal(previous, object_identity) =>
      invalid_activation_dispatch_shell(
        "direct-return declaration reused its pre-hoist object identity",
      )
    _ => ()
  }
  guard object_identity.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "direct-return declaration did not hoist an ordinary UserFunc",
    )
  }
  guard classify_direct_return_function_syntax(ast_name, ast_params, ast_body)
    is Some(actual_syntax) &&
    direct_return_function_syntaxes_match(syntax, actual_syntax) &&
    data.name == Some(syntax.name) &&
    data.params.length() == 1 &&
    data.params[0] == syntax.parameter &&
    physical_equal(data.params, ast_params) &&
    physical_equal(data.body, ast_body) &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method &&
    data.source_text == ast_source_text else {
    invalid_activation_dispatch_shell(
      "direct-return UserFunc provenance did not match the admitted declaration",
    )
  }
  let source_identity = function_source_identity(callee)
  guard source_identity == expected_source_identity else {
    invalid_activation_dispatch_shell(
      "direct-return UserFunc source identity changed during root hoisting",
    )
  }
  let realm_protos = callee_realm_protos(callee)
  guard numeric_recursion_realm_protos_match(
    expected_realm_protos, realm_protos,
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return UserFunc realm provenance changed during root hoisting",
    )
  }
  TrustedDirectReturnRecursionFunction(
    syntax~,
    callee~,
    params=data.params,
    body=data.body,
    source_text=data.source_text,
    expected_realm_protos=realm_protos,
    expected_source_identity=source_identity,
  )
}

///|
fn Interpreter::seal_direct_return_recursion_registry(
  self : Interpreter,
  preflight : DirectReturnRecursionPreflight,
  stmts : Array[@ast.Stmt],
) -> TrustedDirectReturnRecursionRegistry raise InvalidActivationDispatchShell {
  guard self.numeric_recursion_canonical_global_object() is Some(global_object) &&
    physical_equal(global_object, preflight.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "direct-return canonical global object changed before sealing",
    )
  }
  guard classify_direct_return_recursion_program(stmts) is Some(actual_plan) &&
    direct_return_recursion_plans_match(preflight.plan, actual_plan) else {
    invalid_activation_dispatch_shell(
      "direct-return program no longer matches exact admission",
    )
  }
  let throw_type_error_snapshot = numeric_recursion_callback_free_throw_type_error(
    self.global,
  )
  guard direct_return_throw_type_error_snapshot_matches(
    preflight.throw_type_error_snapshot,
    throw_type_error_snapshot,
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return ThrowTypeError binding changed before sealing",
    )
  }
  let entry = direct_return_recursion_trusted_declaration(
    self,
    preflight.plan.entry,
    previous_object=preflight.previous_entry_object,
    expected_global_object=preflight.expected_global_object,
    expected_realm_protos=preflight.expected_realm_protos,
    expected_source_identity=preflight.expected_source_identity,
    stmts~,
  )
  TrustedDirectReturnRecursionRegistry(
    plan=preflight.plan,
    entry~,
    throw_type_error=direct_return_throw_type_error_value(
      throw_type_error_snapshot,
    ),
    throw_type_error_snapshot~,
    expected_global_object=preflight.expected_global_object,
  )
}

///|
fn TrustedDirectReturnRecursionRegistry::require_callee(
  self : TrustedDirectReturnRecursionRegistry,
  interp : Interpreter,
  callee : Value,
) -> DirectReturnFunctionSyntax raise InvalidActivationDispatchShell {
  guard self.plan.entry.syntax.name == self.entry.syntax.name else {
    invalid_activation_dispatch_shell(
      "direct-return registry lost its entry syntax identity",
    )
  }
  guard interp.numeric_recursion_canonical_global_object()
    is Some(global_object) &&
    physical_equal(global_object, self.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "direct-return canonical global object changed after sealing",
    )
  }
  guard numeric_recursion_callback_free_binding_snapshots_match(
    self.throw_type_error_snapshot,
    numeric_recursion_callback_free_throw_type_error(interp.global),
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return ThrowTypeError binding changed after sealing",
    )
  }
  guard callee is Object(actual) else {
    invalid_activation_dispatch_shell(
      "direct-return call requested an unsealed callee",
    )
  }
  guard (match self.entry.callee {
    Object(expected) => physical_equal(actual, expected)
    _ => false
  }) else {
    invalid_activation_dispatch_shell(
      "direct-return registry lost its function object",
    )
  }
  guard actual.class_name == "Function" &&
    actual.callable is Some(UserFunc(data)) &&
    data.name == Some(self.entry.syntax.name) &&
    data.params.length() == 1 &&
    data.params[0] == self.entry.syntax.parameter &&
    physical_equal(data.params, self.entry.params) &&
    physical_equal(data.body, self.entry.body) &&
    classify_direct_return_function_syntax(
      self.entry.syntax.name,
      self.entry.params,
      self.entry.body,
    )
    is Some(actual_syntax) &&
    direct_return_function_syntaxes_match(self.entry.syntax, actual_syntax) &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method &&
    data.source_text == self.entry.source_text &&
    function_source_identity(callee) == self.entry.expected_source_identity &&
    numeric_recursion_realm_protos_match(
      self.entry.expected_realm_protos,
      callee_realm_protos(callee),
    ) else {
    invalid_activation_dispatch_shell(
      "direct-return callee provenance changed after sealing",
    )
  }
  self.entry.syntax
}

///|
fn TrustedDirectReturnRecursionRegistry::require_call(
  self : TrustedDirectReturnRecursionRegistry,
  interp : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> DirectReturnFunctionSyntax raise InvalidActivationDispatchShell {
  guard this_value is Undefined && args.length() == 1 else {
    invalid_activation_dispatch_shell(
      "direct-return activation requires undefined this and one argument",
    )
  }
  guard args[0] is Number(_) else {
    invalid_activation_dispatch_shell(
      "direct-return activation requires a Number argument",
    )
  }
  guard loc == self.plan.root_call_loc ||
    loc == self.entry.syntax.recursive_call_loc else {
    invalid_activation_dispatch_shell(
      "direct-return call location escaped the sealed source recipe",
    )
  }
  self.require_callee(interp, callee)
}
