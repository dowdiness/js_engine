// Callback-free runtime admission and provenance sealing for the exact numeric
// recursion slice. This module reads environment storage directly; it never
// performs JavaScript identifier resolution or invokes a guest callback.
//
// Safety contract: the imperative shell owns preflight -> root realm clear ->
// exact root prepare -> seal synchronously, without guest-visible interleaving.
// Once managed execution starts, a violated seal is a typed invariant; fallback
// is forbidden. The shell restores the borrowed realm only after managed exit.

///|
priv struct NumericRecursionPreflight {
  plan : NumericRecursionPlan
  previous_entry_object : ObjectData?
  previous_peer_object : ObjectData?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
priv struct TrustedNumericRecursionFunction {
  syntax : NumericRecursionFunctionSyntax
  callee : Value
  params : Array[String]
  body : Array[@ast.Stmt]
  source_text : String?
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn TrustedNumericRecursionFunction::TrustedNumericRecursionFunction(
  syntax~ : NumericRecursionFunctionSyntax,
  callee~ : Value,
  params~ : Array[String],
  body~ : Array[@ast.Stmt],
  source_text~ : String?,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedNumericRecursionFunction {
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
#warnings("-unused_field")
priv struct TrustedNumericRecursionRegistry {
  program_plan : NumericRecursionPlan?
  entry : TrustedNumericRecursionFunction
  peer : TrustedNumericRecursionFunction?
  throw_type_error : Value?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
}

///|
fn TrustedNumericRecursionRegistry::TrustedNumericRecursionRegistry(
  program_plan? : NumericRecursionPlan? = None,
  entry~ : TrustedNumericRecursionFunction,
  peer~ : TrustedNumericRecursionFunction?,
  throw_type_error~ : Value?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
) -> TrustedNumericRecursionRegistry {
  {
    program_plan,
    entry,
    peer,
    throw_type_error,
    throw_type_error_snapshot,
    expected_global_object,
  }
}

///|
fn NumericRecursionPreflight::NumericRecursionPreflight(
  plan~ : NumericRecursionPlan,
  previous_entry_object~ : ObjectData?,
  previous_peer_object~ : ObjectData?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> NumericRecursionPreflight {
  {
    plan,
    previous_entry_object,
    previous_peer_object,
    throw_type_error_snapshot,
    expected_global_object,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
fn numeric_recursion_existing_binding_snapshot(
  env : Environment,
  name : String,
) -> (Bool, ObjectData?) {
  match env.bindings.get(name) {
    None => (true, None)
    Some(binding) if binding.initialized && binding.kind == VarBinding => {
      let previous_object = match binding.value {
        Object(data) => Some(data)
        _ => None
      }
      (true, previous_object)
    }
    Some(_) => (false, None)
  }
}

///|
fn numeric_recursion_callback_free_throw_type_error(
  env : Environment,
) -> CallbackFreeBindingSnapshot {
  callback_free_binding_snapshot(env, "[[ThrowTypeError]]")
}

///|
fn Interpreter::numeric_recursion_canonical_global_object(
  self : Interpreter,
) -> ObjectData? {
  guard self.global.parent is None &&
    self.global.with_object is None &&
    self.global.is_var_scope &&
    self.global_this is Object(global_object) else {
    return None
  }
  guard self.global.realm_state is Some(global_realm) &&
    physical_equal(global_realm, self.realm_state) else {
    return None
  }
  guard self.global.interpreter_context is Some(global_interp) &&
    physical_equal(global_interp, self) else {
    return None
  }
  Some(global_object)
}

///|
fn numeric_recursion_global_property_is_canonical(
  global_object : ObjectData,
  name : String,
) -> Bool {
  match ordinary_get_own_string_desc(global_object.bag, name) {
    Some(desc) =>
      !desc.is_accessor &&
      desc.writable &&
      desc.enumerable &&
      !desc.configurable
    None => false
  }
}

///|
fn numeric_recursion_global_declaration_is_sealable(
  global_object : ObjectData,
  name : String,
) -> Bool {
  match ordinary_get_own_string_desc(global_object.bag, name) {
    None => true
    Some(_) =>
      numeric_recursion_global_property_is_canonical(global_object, name)
  }
}

///|
fn numeric_recursion_plan_requires_intrinsic_apply(
  plan : NumericRecursionPlan,
) -> Bool {
  let entry_requires = numeric_recursion_apply_recipe_is_intrinsic(
    plan.entry.syntax.invocation_recipe,
  )
  let peer_requires = match plan.peer {
    Some(peer) =>
      numeric_recursion_apply_recipe_is_intrinsic(peer.syntax.invocation_recipe)
    None => false
  }
  entry_requires || peer_requires
}

///|
#warnings("-unused_value")
fn Interpreter::preflight_numeric_recursion_program(
  self : Interpreter,
  plan : NumericRecursionPlan,
) -> NumericRecursionPreflight? {
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) else {
    return None
  }
  guard !numeric_recursion_plan_requires_intrinsic_apply(plan) ||
    self.numeric_recursion_apply_globals_are_canonical() else {
    return None
  }
  let peer_declaration_is_sealable = match plan.peer {
    Some(peer) =>
      numeric_recursion_global_declaration_is_sealable(
        expected_global_object,
        peer.syntax.name,
      )
    None => true
  }
  guard numeric_recursion_global_declaration_is_sealable(
      expected_global_object,
      plan.entry.syntax.name,
    ) &&
    peer_declaration_is_sealable else {
    return None
  }
  let (entry_ok, previous_entry_object) = numeric_recursion_existing_binding_snapshot(
    self.global,
    plan.entry.syntax.name,
  )
  guard entry_ok else { return None }
  let (peer_ok, previous_peer_object) = match plan.peer {
    Some(peer) =>
      numeric_recursion_existing_binding_snapshot(self.global, peer.syntax.name)
    None => (true, None)
  }
  guard peer_ok else { return None }
  let throw_type_error_snapshot = numeric_recursion_callback_free_throw_type_error(
    self.global,
  )
  match throw_type_error_snapshot {
    CallbackFreeBindingUnsafe => return None
    _ => ()
  }
  Some(
    NumericRecursionPreflight(
      plan~,
      previous_entry_object~,
      previous_peer_object~,
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
#warnings("-unused_value")
fn Interpreter::preflight_dispatchable_numeric_recursion_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> NumericRecursionPreflight? {
  match classify_numeric_recursion_program(stmts) {
    Some(plan) if numeric_recursion_plan_is_dispatchable(plan) =>
      self.preflight_numeric_recursion_program(plan)
    None => None
    Some(_) => None
  }
}

///|
fn numeric_recursion_callback_free_binding_snapshots_match(
  expected : CallbackFreeBindingSnapshot,
  actual : CallbackFreeBindingSnapshot,
) -> Bool {
  match (expected, actual) {
    (CallbackFreeBindingMissing, CallbackFreeBindingMissing) => true
    (
      CallbackFreeBindingPresent(expected_value),
      CallbackFreeBindingPresent(actual_value),
    ) => same_value(expected_value, actual_value)
    _ => false
  }
}

///|
fn numeric_recursion_throw_type_error_value(
  snapshot : CallbackFreeBindingSnapshot,
) -> Value? raise InvalidActivationDispatchShell {
  match snapshot {
    CallbackFreeBindingMissing => None
    CallbackFreeBindingPresent(value) => Some(value)
    CallbackFreeBindingUnsafe =>
      invalid_activation_dispatch_shell(
        "numeric recursion ThrowTypeError binding became callback-capable",
      )
  }
}

///|
fn numeric_recursion_optional_values_match(
  expected : Value?,
  actual : Value?,
) -> Bool {
  match (expected, actual) {
    (None, None) => true
    (Some(expected_value), Some(actual_value)) =>
      same_value(expected_value, actual_value)
    _ => false
  }
}

///|
fn numeric_recursion_realm_protos_match(
  expected : FunctionRealmProtos,
  actual : FunctionRealmProtos,
) -> Bool {
  let {
    function_proto: expected_function_proto,
    object_proto: expected_object_proto,
    string_proto: expected_string_proto,
    number_proto: expected_number_proto,
    boolean_proto: expected_boolean_proto,
    symbol_proto: expected_symbol_proto,
    array_proto: expected_array_proto,
    map_proto: expected_map_proto,
    set_proto: expected_set_proto,
    promise_proto: expected_promise_proto,
    constructor_prototype_registry: expected_constructor_prototype_registry,
  } = expected
  let {
    function_proto: actual_function_proto,
    object_proto: actual_object_proto,
    string_proto: actual_string_proto,
    number_proto: actual_number_proto,
    boolean_proto: actual_boolean_proto,
    symbol_proto: actual_symbol_proto,
    array_proto: actual_array_proto,
    map_proto: actual_map_proto,
    set_proto: actual_set_proto,
    promise_proto: actual_promise_proto,
    constructor_prototype_registry: actual_constructor_prototype_registry,
  } = actual
  numeric_recursion_optional_values_match(
    expected_function_proto, actual_function_proto,
  ) &&
  numeric_recursion_optional_values_match(
    expected_object_proto, actual_object_proto,
  ) &&
  numeric_recursion_optional_values_match(
    expected_string_proto, actual_string_proto,
  ) &&
  numeric_recursion_optional_values_match(
    expected_number_proto, actual_number_proto,
  ) &&
  numeric_recursion_optional_values_match(
    expected_boolean_proto, actual_boolean_proto,
  ) &&
  numeric_recursion_optional_values_match(
    expected_symbol_proto, actual_symbol_proto,
  ) &&
  numeric_recursion_optional_values_match(
    expected_array_proto, actual_array_proto,
  ) &&
  numeric_recursion_optional_values_match(expected_map_proto, actual_map_proto) &&
  numeric_recursion_optional_values_match(expected_set_proto, actual_set_proto) &&
  numeric_recursion_optional_values_match(
    expected_promise_proto, actual_promise_proto,
  ) &&
  numeric_recursion_optional_values_match(
    expected_constructor_prototype_registry, actual_constructor_prototype_registry,
  )
}

///|
fn numeric_recursion_trusted_declaration(
  interp : Interpreter,
  plan : NumericRecursionFunctionPlan,
  previous_object~ : ObjectData?,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
  stmts~ : Array[@ast.Stmt],
) -> TrustedNumericRecursionFunction raise InvalidActivationDispatchShell {
  guard plan.declaration_index >= 0 && plan.declaration_index < stmts.length() else {
    invalid_activation_dispatch_shell(
      "numeric recursion declaration index is outside the admitted program",
    )
  }
  guard stmts[plan.declaration_index]
    is @ast.FuncDecl(ast_name, ast_params, ast_body, _, ast_source_text) else {
    invalid_activation_dispatch_shell(
      "numeric recursion declaration no longer matches its admitted syntax",
    )
  }
  let syntax = plan.syntax
  guard interp.global.bindings.get(syntax.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding else {
    invalid_activation_dispatch_shell(
      "numeric recursion declaration binding was not created by root hoisting",
    )
  }
  let callee = binding.value
  guard callee is Object(object_identity) &&
    object_identity.class_name == "Function" else {
    invalid_activation_dispatch_shell(
      "numeric recursion declaration did not hoist a function object",
    )
  }
  guard interp.global_this is Object(global_object) &&
    global_object.bag.properties.get(syntax.name) is Some(Object(mirrored)) &&
    physical_equal(mirrored, object_identity) else {
    invalid_activation_dispatch_shell(
      "numeric recursion declaration binding diverged from its global mirror",
    )
  }
  match previous_object {
    Some(previous) if physical_equal(previous, object_identity) =>
      invalid_activation_dispatch_shell(
        "numeric recursion declaration reused its pre-hoist object identity",
      )
    _ => ()
  }
  guard object_identity.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "numeric recursion declaration did not hoist a simple UserFunc",
    )
  }
  guard interp.numeric_recursion_apply_intrinsic_is_canonical(syntax, callee) else {
    invalid_activation_dispatch_shell(
      "numeric recursion intrinsic apply provenance changed before sealing",
    )
  }
  let params_match = match syntax.retained_parameter {
    None => data.params.length() == 1 && data.params[0] == syntax.parameter
    Some(retained) =>
      data.params.length() == 2 &&
      data.params[0] == syntax.parameter &&
      data.params[1] == retained
  }
  guard ast_name == syntax.name &&
    data.name == Some(syntax.name) &&
    params_match &&
    physical_equal(data.params, ast_params) &&
    physical_equal(data.body, ast_body) &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method &&
    data.source_text == ast_source_text else {
    invalid_activation_dispatch_shell(
      "numeric recursion UserFunc provenance did not match the admitted declaration",
    )
  }
  let source_identity = function_source_identity(callee)
  guard source_identity == expected_source_identity else {
    invalid_activation_dispatch_shell(
      "numeric recursion UserFunc source identity changed during root hoisting",
    )
  }
  let realm_protos = callee_realm_protos(callee)
  guard numeric_recursion_realm_protos_match(
    expected_realm_protos, realm_protos,
  ) else {
    invalid_activation_dispatch_shell(
      "numeric recursion UserFunc realm provenance changed during root hoisting",
    )
  }
  TrustedNumericRecursionFunction(
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
fn numeric_recursion_function_plans_match(
  expected : NumericRecursionFunctionPlan,
  actual : NumericRecursionFunctionPlan,
) -> Bool {
  numeric_recursion_function_syntaxes_match(expected.syntax, actual.syntax) &&
  expected.declaration_index == actual.declaration_index
}

///|
fn numeric_recursion_function_syntaxes_match(
  expected : NumericRecursionFunctionSyntax,
  actual : NumericRecursionFunctionSyntax,
) -> Bool {
  expected.name == actual.name &&
  expected.parameter == actual.parameter &&
  expected.retained_parameter == actual.retained_parameter &&
  expected.recursive_callee == actual.recursive_callee &&
  expected.invocation_recipe == actual.invocation_recipe &&
  numeric_recursion_function_return_recipes_match(
    expected.return_recipe,
    actual.return_recipe,
  )
}

///|
fn numeric_recursion_closed_body_recipes_match(
  expected : NumericRecursionClosedBodyRecipe,
  actual : NumericRecursionClosedBodyRecipe,
) -> Bool {
  match (expected, actual) {
    (NumericRecursionClosedBodyEmpty, NumericRecursionClosedBodyEmpty)
    | (NumericRecursionClosedBindingValue, NumericRecursionClosedBindingValue)
    | (NumericRecursionClosedBindingThrow, NumericRecursionClosedBindingThrow) =>
      true
    (
      NumericRecursionClosedNumberValue(expected),
      NumericRecursionClosedNumberValue(actual),
    )
    | (
      NumericRecursionClosedNumberThrow(expected),
      NumericRecursionClosedNumberThrow(actual),
    ) => same_value(Number(expected), Number(actual))
    _ => false
  }
}

///|
fn numeric_recursion_function_return_recipes_match(
  expected : NumericRecursionFunctionReturnRecipe,
  actual : NumericRecursionFunctionReturnRecipe,
) -> Bool {
  match (expected, actual) {
    (NumericRecursionDirectReturn, NumericRecursionDirectReturn) => true
    (
      NumericRecursionProtectedReturn(expected_finalizer),
      NumericRecursionProtectedReturn(actual_finalizer),
    ) =>
      numeric_recursion_closed_body_recipes_match(
        expected_finalizer, actual_finalizer,
      )
    _ => false
  }
}

///|
fn numeric_recursion_catch_recipes_match(
  expected : NumericRecursionCatchRecipe,
  actual : NumericRecursionCatchRecipe,
) -> Bool {
  match (expected, actual) {
    (NumericRecursionNoCatch, NumericRecursionNoCatch) => true
    (
      NumericRecursionCatch(expected_parameter, expected_body),
      NumericRecursionCatch(actual_parameter, actual_body),
    ) => {
      let parameters_match = match (expected_parameter, actual_parameter) {
        (None, None) => true
        (Some(expected), Some(actual)) => expected == actual
        _ => false
      }
      parameters_match &&
      numeric_recursion_closed_body_recipes_match(expected_body, actual_body)
    }
    _ => false
  }
}

///|
fn numeric_recursion_finalizer_recipes_match(
  expected : NumericRecursionFinalizerRecipe,
  actual : NumericRecursionFinalizerRecipe,
) -> Bool {
  match (expected, actual) {
    (NumericRecursionNoFinalizer, NumericRecursionNoFinalizer) => true
    (NumericRecursionFinalizer(expected), NumericRecursionFinalizer(actual)) =>
      numeric_recursion_closed_body_recipes_match(expected, actual)
    _ => false
  }
}

///|
fn numeric_recursion_root_controls_match(
  expected : NumericRecursionRootControlRecipe,
  actual : NumericRecursionRootControlRecipe,
) -> Bool {
  match (expected, actual) {
    (NumericRecursionDirectRoot, NumericRecursionDirectRoot) => true
    (
      NumericRecursionProtectedRoot(expected),
      NumericRecursionProtectedRoot(actual),
    ) => {
      let try_completion_matches = match
        (expected.try_completion, actual.try_completion) {
        (NumericRecursionRootCallValue, NumericRecursionRootCallValue)
        | (NumericRecursionRootCallThrow, NumericRecursionRootCallThrow) => true
        _ => false
      }
      try_completion_matches &&
      numeric_recursion_catch_recipes_match(
        expected.catch_recipe,
        actual.catch_recipe,
      ) &&
      numeric_recursion_finalizer_recipes_match(
        expected.finalizer_recipe,
        actual.finalizer_recipe,
      )
    }
    _ => false
  }
}

///|
fn numeric_recursion_closed_argument_recipes_match(
  expected : NumericRecursionClosedArgumentRecipe?,
  actual : NumericRecursionClosedArgumentRecipe?,
) -> Bool {
  match (expected, actual) {
    (None, None) => true
    (Some(expected), Some(actual)) =>
      expected.value == actual.value &&
      expected.observation_count == actual.observation_count
    _ => false
  }
}

///|
// Compare only normalized admission semantics. The registry deliberately keeps
// `actual`, so diagnostics and execution retain all sealed expression locations.
fn numeric_recursion_plans_match(
  expected : NumericRecursionPlan,
  actual : NumericRecursionPlan,
) -> Bool {
  let {
    entry: expected_entry,
    peer: expected_peer,
    initial_argument: expected_initial_argument,
    retained_argument: expected_retained_argument,
    root_call_loc: _expected_root_call_loc,
    root_control: expected_root_control,
  } = expected
  let {
    entry: actual_entry,
    peer: actual_peer,
    initial_argument: actual_initial_argument,
    retained_argument: actual_retained_argument,
    root_call_loc: _actual_root_call_loc,
    root_control: actual_root_control,
  } = actual
  let peer_matches = match (expected_peer, actual_peer) {
    (None, None) => true
    (Some(expected_peer), Some(actual_peer)) =>
      numeric_recursion_function_plans_match(expected_peer, actual_peer)
    _ => false
  }
  numeric_recursion_function_plans_match(expected_entry, actual_entry) &&
  peer_matches &&
  expected_initial_argument == actual_initial_argument &&
  numeric_recursion_closed_argument_recipes_match(
    expected_retained_argument, actual_retained_argument,
  ) &&
  numeric_recursion_root_controls_match(
    expected_root_control, actual_root_control,
  )
}

///|
#warnings("-unused_value")
fn Interpreter::seal_numeric_recursion_registry(
  self : Interpreter,
  preflight : NumericRecursionPreflight,
  stmts : Array[@ast.Stmt],
) -> TrustedNumericRecursionRegistry raise InvalidActivationDispatchShell {
  // Revalidate the synchronous shell contract before trusting any hoisted
  // identity. Any drift is an invariant failure; managed execution must not
  // fall back into callback-capable routing after this seam.
  guard self.numeric_recursion_canonical_global_object()
    is Some(sealed_global_object) &&
    physical_equal(sealed_global_object, preflight.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "numeric recursion global changed after callback-free preflight",
    )
  }
  let throw_type_error_snapshot = numeric_recursion_callback_free_throw_type_error(
    self.global,
  )
  guard numeric_recursion_callback_free_binding_snapshots_match(
    preflight.throw_type_error_snapshot,
    throw_type_error_snapshot,
  ) else {
    invalid_activation_dispatch_shell(
      "numeric recursion ThrowTypeError binding changed after callback-free preflight",
    )
  }
  let throw_type_error = numeric_recursion_throw_type_error_value(
    throw_type_error_snapshot,
  )
  let sealed_plan = match classify_numeric_recursion_program(stmts) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "numeric recursion program no longer satisfies exact admission",
      )
  }
  guard numeric_recursion_plans_match(preflight.plan, sealed_plan) else {
    invalid_activation_dispatch_shell(
      "numeric recursion program no longer matches its preflight plan",
    )
  }
  let entry = numeric_recursion_trusted_declaration(
    self,
    sealed_plan.entry,
    previous_object=preflight.previous_entry_object,
    expected_realm_protos=preflight.expected_realm_protos,
    expected_source_identity=preflight.expected_source_identity,
    stmts~,
  )
  let peer = match sealed_plan.peer {
    Some(peer_syntax) =>
      Some(
        numeric_recursion_trusted_declaration(
          self,
          peer_syntax,
          previous_object=preflight.previous_peer_object,
          expected_realm_protos=preflight.expected_realm_protos,
          expected_source_identity=preflight.expected_source_identity,
          stmts~,
        ),
      )
    None => None
  }
  TrustedNumericRecursionRegistry(
    program_plan=Some(sealed_plan),
    entry~,
    peer~,
    throw_type_error~,
    throw_type_error_snapshot~,
    expected_global_object=preflight.expected_global_object,
  )
}

///|
fn numeric_recursion_user_func_matches_syntax(
  interp : Interpreter,
  syntax : NumericRecursionFunctionSyntax,
  data : FuncData,
) -> Bool {
  let params_match = match syntax.retained_parameter {
    None => data.params.length() == 1 && data.params[0] == syntax.parameter
    Some(retained) =>
      data.params.length() == 2 &&
      data.params[0] == syntax.parameter &&
      data.params[1] == retained
  }
  guard data.name == Some(syntax.name) &&
    params_match &&
    (data.body.length() == 2 || data.body.length() == 3) &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method else {
    return false
  }
  match
    classify_numeric_recursion_function_syntax(
      syntax.name,
      data.params,
      data.body,
    ) {
    Some(actual) => direct_numeric_recursion_syntax_matches(syntax, actual)
    None => false
  }
}

///|
fn TrustedNumericRecursionRegistry::revalidate_metadata(
  self : TrustedNumericRecursionRegistry,
  interp : Interpreter,
) -> Unit raise InvalidActivationDispatchShell {
  guard interp.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, self.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "numeric recursion trusted global changed after sealing",
    )
  }
  guard numeric_recursion_callback_free_binding_snapshots_match(
    self.throw_type_error_snapshot,
    numeric_recursion_callback_free_throw_type_error(interp.global),
  ) else {
    invalid_activation_dispatch_shell(
      "numeric recursion ThrowTypeError binding changed after sealing",
    )
  }
}

///|
#warnings("-unused_value")
fn TrustedNumericRecursionRegistry::require_program_plan(
  self : TrustedNumericRecursionRegistry,
) -> NumericRecursionPlan raise InvalidActivationDispatchShell {
  match self.program_plan {
    Some(plan) => plan
    None =>
      invalid_activation_dispatch_shell(
        "direct numeric call registry has no program plan",
      )
  }
}

///|
fn numeric_recursion_trusted_callee_has_identity(
  trusted : TrustedNumericRecursionFunction,
  actual : ObjectData,
) -> Bool {
  match trusted.callee {
    Object(expected) => physical_equal(expected, actual)
    _ => false
  }
}

///|
fn numeric_recursion_revalidate_trusted_function(
  interp : Interpreter,
  trusted : TrustedNumericRecursionFunction,
  candidate : Value,
  expected_global_object : ObjectData,
) -> Unit raise InvalidActivationDispatchShell {
  guard interp.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, expected_global_object) else {
    invalid_activation_dispatch_shell(
      "numeric recursion trusted global changed after sealing",
    )
  }
  guard candidate is Object(actual) &&
    actual.class_name == "Function" &&
    numeric_recursion_trusted_callee_has_identity(trusted, actual) else {
    invalid_activation_dispatch_shell(
      "numeric recursion candidate identity is outside its trusted record",
    )
  }
  guard interp.global.bindings.get(trusted.syntax.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding &&
    binding.value is Object(bound) &&
    physical_equal(bound, actual) else {
    invalid_activation_dispatch_shell(
      "numeric recursion candidate diverged from its global binding",
    )
  }
  guard actual_global_object.bag.properties.get(trusted.syntax.name)
    is Some(Object(mirrored)) &&
    physical_equal(mirrored, actual) &&
    numeric_recursion_global_property_is_canonical(
      actual_global_object,
      trusted.syntax.name,
    ) else {
    invalid_activation_dispatch_shell(
      "numeric recursion candidate diverged from its global mirror",
    )
  }
  guard actual.callable is Some(UserFunc(data)) &&
    physical_equal(data.params, trusted.params) &&
    physical_equal(data.body, trusted.body) &&
    data.source_text == trusted.source_text &&
    numeric_recursion_user_func_matches_syntax(interp, trusted.syntax, data) else {
    invalid_activation_dispatch_shell(
      "numeric recursion candidate no longer has exact UserFunc provenance",
    )
  }
  guard interp.numeric_recursion_apply_intrinsic_is_canonical(
    trusted.syntax,
    candidate,
  ) else {
    invalid_activation_dispatch_shell(
      "numeric recursion intrinsic apply provenance changed after sealing",
    )
  }
  guard function_source_identity(candidate) == trusted.expected_source_identity else {
    invalid_activation_dispatch_shell(
      "numeric recursion candidate source identity changed after sealing",
    )
  }
  guard numeric_recursion_realm_protos_match(
    trusted.expected_realm_protos,
    callee_realm_protos(candidate),
  ) else {
    invalid_activation_dispatch_shell(
      "numeric recursion candidate realm provenance changed after sealing",
    )
  }
}

///|
#warnings("-unused_value")
fn TrustedNumericRecursionRegistry::require_named(
  self : TrustedNumericRecursionRegistry,
  interp : Interpreter,
  name : String,
) -> Value raise InvalidActivationDispatchShell {
  self.revalidate_metadata(interp)
  let trusted = if name == self.entry.syntax.name {
    self.entry
  } else {
    match self.peer {
      Some(peer) if name == peer.syntax.name => peer
      _ =>
        invalid_activation_dispatch_shell(
          "numeric recursion callee name is outside the trusted registry",
        )
    }
  }
  numeric_recursion_revalidate_trusted_function(
    interp,
    trusted,
    trusted.callee,
    self.expected_global_object,
  )
  trusted.callee
}

///|
#warnings("-unused_value")
fn TrustedNumericRecursionRegistry::require_callee(
  self : TrustedNumericRecursionRegistry,
  interp : Interpreter,
  callee : Value,
) -> NumericRecursionFunctionSyntax raise InvalidActivationDispatchShell {
  self.revalidate_metadata(interp)
  guard callee is Object(actual) else {
    invalid_activation_dispatch_shell(
      "numeric recursion call target is not a trusted function object",
    )
  }
  let trusted = if numeric_recursion_trusted_callee_has_identity(
      self.entry,
      actual,
    ) {
    self.entry
  } else {
    match self.peer {
      Some(peer) if numeric_recursion_trusted_callee_has_identity(peer, actual) =>
        peer
      _ =>
        invalid_activation_dispatch_shell(
          "numeric recursion call target identity is outside the trusted registry",
        )
    }
  }
  numeric_recursion_revalidate_trusted_function(
    interp,
    trusted,
    callee,
    self.expected_global_object,
  )
  trusted.syntax
}
