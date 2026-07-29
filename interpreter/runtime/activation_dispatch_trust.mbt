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
  syntax : NumericRecursionFunctionPlan
  callee : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn TrustedNumericRecursionFunction::TrustedNumericRecursionFunction(
  syntax~ : NumericRecursionFunctionPlan,
  callee~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedNumericRecursionFunction {
  { syntax, callee, expected_realm_protos, expected_source_identity }
}

///|
#warnings("-unused_field")
priv struct TrustedNumericRecursionRegistry {
  plan : NumericRecursionPlan
  entry : TrustedNumericRecursionFunction
  peer : TrustedNumericRecursionFunction?
  throw_type_error : Value?
  expected_global_object : ObjectData
}

///|
fn TrustedNumericRecursionRegistry::TrustedNumericRecursionRegistry(
  plan~ : NumericRecursionPlan,
  entry~ : TrustedNumericRecursionFunction,
  peer~ : TrustedNumericRecursionFunction?,
  throw_type_error~ : Value?,
  expected_global_object~ : ObjectData,
) -> TrustedNumericRecursionRegistry {
  { plan, entry, peer, throw_type_error, expected_global_object }
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
priv enum CallbackFreeBindingSnapshot {
  CallbackFreeBindingMissing
  CallbackFreeBindingPresent(Value)
  CallbackFreeBindingUnsafe
}

///|
fn numeric_recursion_callback_free_throw_type_error(
  env : Environment,
) -> CallbackFreeBindingSnapshot {
  match env.bindings.get("[[ThrowTypeError]]") {
    None => CallbackFreeBindingMissing
    Some(binding) if binding.initialized =>
      match binding.value {
        Object(data) if data.class_name == "ModuleNamespaceCache" ||
          data.class_name == "ModuleTDZ" ||
          data.class_name == "ModuleExportCell" => CallbackFreeBindingUnsafe
        value => CallbackFreeBindingPresent(value)
      }
    Some(_) => CallbackFreeBindingUnsafe
  }
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
#warnings("-unused_value")
fn Interpreter::preflight_numeric_recursion_program(
  self : Interpreter,
  plan : NumericRecursionPlan,
) -> NumericRecursionPreflight? {
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) else {
    return None
  }
  let (entry_ok, previous_entry_object) = numeric_recursion_existing_binding_snapshot(
    self.global,
    plan.entry.name,
  )
  guard entry_ok else { return None }
  let (peer_ok, previous_peer_object) = match plan.peer {
    Some(peer) =>
      numeric_recursion_existing_binding_snapshot(self.global, peer.name)
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
  syntax : NumericRecursionFunctionPlan,
  previous_object~ : ObjectData?,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
  stmts~ : Array[@ast.Stmt],
) -> TrustedNumericRecursionFunction raise InvalidActivationDispatchShell {
  guard syntax.declaration_index >= 0 &&
    syntax.declaration_index < stmts.length() else {
    invalid_activation_dispatch_shell(
      "numeric recursion declaration index is outside the admitted program",
    )
  }
  guard stmts[syntax.declaration_index]
    is @ast.FuncDecl(ast_name, ast_params, ast_body, _, ast_source_text) else {
    invalid_activation_dispatch_shell(
      "numeric recursion declaration no longer matches its admitted syntax",
    )
  }
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
  guard ast_name == syntax.name &&
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
    expected_realm_protos=realm_protos,
    expected_source_identity=source_identity,
  )
}

///|
fn numeric_recursion_function_plans_match(
  expected : NumericRecursionFunctionPlan,
  actual : NumericRecursionFunctionPlan,
) -> Bool {
  let {
    name: expected_name,
    parameter: expected_parameter,
    recursive_callee: expected_recursive_callee,
    declaration_index: expected_declaration_index,
    expression_recipe: expected_expression_recipe,
  } = expected
  let {
    name: actual_name,
    parameter: actual_parameter,
    recursive_callee: actual_recursive_callee,
    declaration_index: actual_declaration_index,
    expression_recipe: actual_expression_recipe,
  } = actual
  let {
    base_condition_loc: _expected_base_condition_loc,
    recursive_add_loc: _expected_recursive_add_loc,
    recursive_call_loc: _expected_recursive_call_loc,
    recursive_subtract_loc: _expected_recursive_subtract_loc,
  } = expected_expression_recipe
  let {
    base_condition_loc: _actual_base_condition_loc,
    recursive_add_loc: _actual_recursive_add_loc,
    recursive_call_loc: _actual_recursive_call_loc,
    recursive_subtract_loc: _actual_recursive_subtract_loc,
  } = actual_expression_recipe
  expected_name == actual_name &&
  expected_parameter == actual_parameter &&
  expected_recursive_callee == actual_recursive_callee &&
  expected_declaration_index == actual_declaration_index
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
    root_call_loc: _expected_root_call_loc,
  } = expected
  let {
    entry: actual_entry,
    peer: actual_peer,
    initial_argument: actual_initial_argument,
    root_call_loc: _actual_root_call_loc,
  } = actual
  let peer_matches = match (expected_peer, actual_peer) {
    (None, None) => true
    (Some(expected_peer), Some(actual_peer)) =>
      numeric_recursion_function_plans_match(expected_peer, actual_peer)
    _ => false
  }
  numeric_recursion_function_plans_match(expected_entry, actual_entry) &&
  peer_matches &&
  expected_initial_argument == actual_initial_argument
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
    plan=sealed_plan,
    entry~,
    peer~,
    throw_type_error~,
    expected_global_object=preflight.expected_global_object,
  )
}

///|
fn numeric_recursion_user_func_matches_syntax(
  interp : Interpreter,
  syntax : NumericRecursionFunctionPlan,
  data : FuncData,
) -> Bool {
  guard data.name == Some(syntax.name) &&
    data.params.length() == 1 &&
    data.params[0] == syntax.parameter &&
    data.body.length() == 2 &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method else {
    return false
  }
  exact_numeric_recursion_base_case(data.body[0], syntax.parameter) &&
  classify_numeric_recursion_step(data.body[1], syntax.parameter) ==
  Some(syntax.recursive_callee)
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
  guard interp.global_this is Object(global_object) &&
    global_object.bag.properties.get(trusted.syntax.name)
    is Some(Object(mirrored)) &&
    physical_equal(mirrored, actual) else {
    invalid_activation_dispatch_shell(
      "numeric recursion candidate diverged from its global mirror",
    )
  }
  guard actual.callable is Some(UserFunc(data)) &&
    numeric_recursion_user_func_matches_syntax(interp, trusted.syntax, data) else {
    invalid_activation_dispatch_shell(
      "numeric recursion candidate no longer has exact UserFunc provenance",
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
) -> NumericRecursionFunctionPlan raise InvalidActivationDispatchShell {
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
