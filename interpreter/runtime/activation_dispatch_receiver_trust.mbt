// Callback-free preflight and provenance sealing for the exact ordinary
// own-data receiver-call recipe. Once the registry is sealed, every managed
// activation revalidates the object, descriptor, callee, source, and realm.

///|
priv struct ReceiverRecursionPreflight {
  plan : ReceiverRecursionPlan
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
  expected_object_prototype : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn ReceiverRecursionPreflight::ReceiverRecursionPreflight(
  plan~ : ReceiverRecursionPlan,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
  expected_object_prototype~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> ReceiverRecursionPreflight {
  {
    plan,
    throw_type_error_snapshot,
    expected_global_object,
    expected_object_prototype,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
#warnings("-unused_field")
priv struct TrustedReceiverRecursionFunction {
  plan : ReceiverRecursionPlan
  receiver : Value
  callee : Value
  closure : Environment
  params : Array[String]
  body : Array[@ast.Stmt]
  source_text : String?
  expected_object_prototype : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn TrustedReceiverRecursionFunction::TrustedReceiverRecursionFunction(
  plan~ : ReceiverRecursionPlan,
  receiver~ : Value,
  callee~ : Value,
  closure~ : Environment,
  params~ : Array[String],
  body~ : Array[@ast.Stmt],
  source_text~ : String?,
  expected_object_prototype~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedReceiverRecursionFunction {
  {
    plan,
    receiver,
    callee,
    closure,
    params,
    body,
    source_text,
    expected_object_prototype,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
#warnings("-unused_field")
priv struct TrustedReceiverRecursionRegistry {
  plan : ReceiverRecursionPlan
  trusted : TrustedReceiverRecursionFunction
  throw_type_error : Value?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
}

///|
fn TrustedReceiverRecursionRegistry::TrustedReceiverRecursionRegistry(
  plan~ : ReceiverRecursionPlan,
  trusted~ : TrustedReceiverRecursionFunction,
  throw_type_error~ : Value?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
) -> TrustedReceiverRecursionRegistry {
  {
    plan,
    trusted,
    throw_type_error,
    throw_type_error_snapshot,
    expected_global_object,
  }
}

///|
fn receiver_recursion_value_identity(expected : Value, actual : Value) -> Bool {
  match (expected, actual) {
    (Object(expected_data), Object(actual_data)) =>
      physical_equal(expected_data, actual_data)
    _ => false
  }
}

///|
fn receiver_recursion_binding_value(
  interp : Interpreter,
  name : String,
  expected_kind : BindingKind,
) -> Value? {
  match interp.global.bindings.get(name) {
    Some(binding) if binding.initialized &&
      !binding.is_parameter &&
      binding.kind == expected_kind => Some(binding.value)
    _ => None
  }
}

///|
fn receiver_recursion_object_shape_matches(
  receiver : Value,
  callee : Value,
  expected_object_prototype : Value,
  plan : ReceiverRecursionPlan,
) -> Bool {
  match receiver {
    Object(data) => {
      guard data.class_name == "Object" &&
        data.callable is None &&
        same_value(data.prototype, expected_object_prototype) &&
        data.extensible &&
        data.arraybuffer_state is None &&
        data.bag.properties.length() == 2 &&
        data.bag.descriptors.is_empty() &&
        data.bag.symbol_properties.is_empty() &&
        data.bag.symbol_descriptors.is_empty() &&
        data.bag.internal_slots.is_empty() &&
        data.bag.host_slots.is_empty() else {
        return false
      }
      guard data.bag.properties.get(plan.marker_name) is Some(Number(marker)) &&
        marker == NUMERIC_RECURSION_BASE &&
        data.bag.properties.get(plan.property_name) is Some(actual_callee) &&
        receiver_recursion_value_identity(callee, actual_callee) else {
        return false
      }
      true
    }
    _ => false
  }
}

///|
fn receiver_recursion_user_func_matches_syntax(
  interp : Interpreter,
  trusted : TrustedReceiverRecursionFunction,
  data : FuncData,
) -> Bool {
  let plan = trusted.plan
  data.name == Some(plan.function_name) &&
  data.params.length() == 1 &&
  data.params[0] == plan.parameter &&
  data.body.length() == 2 &&
  physical_equal(data.closure, trusted.closure) &&
  physical_equal(data.closure, interp.global) &&
  !data.strict &&
  !data.has_name_binding &&
  !data.is_method &&
  data.source_text == trusted.source_text &&
  receiver_recursion_body_statement_matches(plan, 0, data.body[0]) &&
  receiver_recursion_body_statement_matches(plan, 1, data.body[1]) &&
  interp.global.parent is None
}

///|
fn receiver_recursion_function_identity_matches(
  expected : Value,
  actual : Value,
) -> Bool {
  receiver_recursion_value_identity(expected, actual)
}

///|
fn receiver_recursion_global_function_matches(
  interp : Interpreter,
  trusted : TrustedReceiverRecursionFunction,
  candidate : Value,
) -> Bool {
  guard candidate is Object(actual) &&
    actual.class_name == "Function" &&
    actual.callable is Some(UserFunc(data)) &&
    receiver_recursion_function_identity_matches(trusted.callee, candidate) &&
    physical_equal(data.params, trusted.params) &&
    physical_equal(data.body, trusted.body) &&
    interp.global.bindings.get(trusted.plan.function_name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding &&
    binding.value is Object(bound) &&
    physical_equal(bound, actual) &&
    interp.global_this is Object(global_object) &&
    global_object.bag.properties.get(trusted.plan.function_name)
    is Some(Object(mirrored)) &&
    physical_equal(mirrored, actual) &&
    numeric_recursion_global_property_is_canonical(
      global_object,
      trusted.plan.function_name,
    ) &&
    receiver_recursion_user_func_matches_syntax(interp, trusted, data) else {
    return false
  }
  function_source_identity(candidate) == trusted.expected_source_identity &&
  numeric_recursion_realm_protos_match(
    trusted.expected_realm_protos,
    callee_realm_protos(candidate),
  )
}

///|
fn receiver_recursion_revalidate_trusted(
  interp : Interpreter,
  trusted : TrustedReceiverRecursionFunction,
  expected_global_object : ObjectData,
) -> Unit raise InvalidActivationDispatchShell {
  guard interp.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, expected_global_object) else {
    invalid_activation_dispatch_shell(
      "receiver recursion global changed after callback-free preflight",
    )
  }
  let receiver = match
    receiver_recursion_binding_value(
      interp,
      trusted.plan.receiver_name,
      LetBinding,
    ) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "receiver recursion object binding lost its trusted provenance",
      )
  }
  let callee = match
    receiver_recursion_binding_value(
      interp,
      trusted.plan.function_name,
      VarBinding,
    ) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "receiver recursion function binding lost its trusted provenance",
      )
  }
  guard receiver_recursion_value_identity(trusted.receiver, receiver) &&
    receiver_recursion_value_identity(trusted.callee, callee) &&
    receiver_recursion_object_shape_matches(
      receiver,
      callee,
      trusted.expected_object_prototype,
      trusted.plan,
    ) &&
    receiver_recursion_global_function_matches(interp, trusted, callee) else {
    invalid_activation_dispatch_shell(
      "receiver recursion object graph no longer matches sealed provenance",
    )
  }
}

///|
fn Interpreter::preflight_receiver_recursion_program(
  self : Interpreter,
  plan : ReceiverRecursionPlan,
) -> ReceiverRecursionPreflight? {
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) &&
    !self.global.bindings.contains(plan.receiver_name) &&
    !self.global.bindings.contains(plan.function_name) &&
    expected_global_object.bag.properties.get(plan.receiver_name) is None &&
    expected_global_object.bag.properties.get(plan.function_name) is None else {
    return None
  }
  let expected_realm_protos = function_realm_protos_from_realm_state(
    self.realm_state,
  )
  let expected_object_prototype = match
    getter_recursion_direct_object_prototype(self, expected_realm_protos) {
    Some(found) => found
    None => return None
  }
  let throw_type_error_snapshot = numeric_recursion_callback_free_throw_type_error(
    self.global,
  )
  match throw_type_error_snapshot {
    CallbackFreeBindingUnsafe => return None
    _ => ()
  }
  Some(
    ReceiverRecursionPreflight(
      plan~,
      throw_type_error_snapshot~,
      expected_global_object~,
      expected_object_prototype~,
      expected_realm_protos~,
      expected_source_identity=self.realm_state.active_source_identity.val,
    ),
  )
}

///|
#warnings("-unused_value")
fn Interpreter::preflight_dispatchable_receiver_recursion_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> ReceiverRecursionPreflight? {
  match classify_receiver_recursion_program(stmts) {
    Some(plan) if receiver_recursion_plan_is_dispatchable(plan) =>
      self.preflight_receiver_recursion_program(plan)
    _ => None
  }
}

///|
fn receiver_recursion_recipe_matches(
  expected : ReceiverRecursionExpressionRecipe,
  actual : ReceiverRecursionExpressionRecipe,
) -> Bool {
  expected.base_condition_loc == actual.base_condition_loc &&
  receiver_recursion_access_matches(
    expected.marker_property_access,
    actual.marker_property_access,
  ) &&
  expected.marker_member_loc == actual.marker_member_loc &&
  receiver_recursion_access_matches(
    expected.property_access,
    actual.property_access,
  ) &&
  receiver_recursion_access_matches(
    expected.marker_access,
    actual.marker_access,
  ) &&
  expected.recursive_add_loc == actual.recursive_add_loc &&
  receiver_recursion_access_matches(
    expected.recursive_access,
    actual.recursive_access,
  ) &&
  expected.recursive_member_loc == actual.recursive_member_loc &&
  expected.recursive_call_loc == actual.recursive_call_loc &&
  expected.recursive_subtract_loc == actual.recursive_subtract_loc &&
  receiver_recursion_access_matches(expected.root_access, actual.root_access) &&
  expected.root_member_loc == actual.root_member_loc
}

///|
fn receiver_recursion_plans_match(
  expected : ReceiverRecursionPlan,
  actual : ReceiverRecursionPlan,
) -> Bool {
  expected.function_name == actual.function_name &&
  expected.receiver_name == actual.receiver_name &&
  expected.parameter == actual.parameter &&
  expected.property_name == actual.property_name &&
  expected.marker_name == actual.marker_name &&
  expected.initial_argument == actual.initial_argument &&
  receiver_recursion_recipe_matches(expected.recipe, actual.recipe)
}

///|
fn receiver_recursion_trusted_function(
  interp : Interpreter,
  preflight : ReceiverRecursionPreflight,
) -> TrustedReceiverRecursionFunction raise InvalidActivationDispatchShell {
  let receiver = match
    receiver_recursion_binding_value(
      interp,
      preflight.plan.receiver_name,
      LetBinding,
    ) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "receiver recursion object binding was not initialized exactly once",
      )
  }
  let callee = match
    receiver_recursion_binding_value(
      interp,
      preflight.plan.function_name,
      VarBinding,
    ) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "receiver recursion function binding was not initialized exactly once",
      )
  }
  guard receiver is Object(_) &&
    callee is Object(callee_data) &&
    callee_data.class_name == "Function" &&
    callee_data.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "receiver recursion root did not create an ordinary receiver and UserFunc",
    )
  }
  guard receiver_recursion_object_shape_matches(
    receiver,
    callee,
    preflight.expected_object_prototype,
    preflight.plan,
  ) else {
    invalid_activation_dispatch_shell(
      "receiver recursion root object graph is not the exact own-data recipe",
    )
  }
  let trusted = TrustedReceiverRecursionFunction(
    plan=preflight.plan,
    receiver~,
    callee~,
    closure=data.closure,
    params=data.params,
    body=data.body,
    source_text=data.source_text,
    expected_object_prototype=preflight.expected_object_prototype,
    expected_realm_protos=preflight.expected_realm_protos,
    expected_source_identity=preflight.expected_source_identity,
  )
  guard receiver_recursion_global_function_matches(interp, trusted, callee) else {
    invalid_activation_dispatch_shell(
      "receiver recursion root function no longer matches its admitted syntax",
    )
  }
  receiver_recursion_revalidate_trusted(
    interp,
    trusted,
    preflight.expected_global_object,
  )
  trusted
}

///|
#warnings("-unused_value")
fn Interpreter::seal_receiver_recursion_registry(
  self : Interpreter,
  preflight : ReceiverRecursionPreflight,
  stmts : Array[@ast.Stmt],
) -> TrustedReceiverRecursionRegistry raise InvalidActivationDispatchShell {
  guard self.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, preflight.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "receiver recursion global changed during root setup",
    )
  }
  let actual_throw_type_error = numeric_recursion_callback_free_throw_type_error(
    self.global,
  )
  guard numeric_recursion_callback_free_binding_snapshots_match(
    preflight.throw_type_error_snapshot,
    actual_throw_type_error,
  ) else {
    invalid_activation_dispatch_shell(
      "receiver recursion ThrowTypeError binding changed during root setup",
    )
  }
  let actual_plan = match classify_receiver_recursion_program(stmts) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "receiver recursion program no longer satisfies exact admission",
      )
  }
  guard receiver_recursion_plans_match(preflight.plan, actual_plan) else {
    invalid_activation_dispatch_shell(
      "receiver recursion program no longer matches its preflight plan",
    )
  }
  let trusted = receiver_recursion_trusted_function(self, preflight)
  let registry = TrustedReceiverRecursionRegistry(
    plan=actual_plan,
    trusted~,
    throw_type_error=numeric_recursion_throw_type_error_value(
      actual_throw_type_error,
    ),
    throw_type_error_snapshot=preflight.throw_type_error_snapshot,
    expected_global_object=preflight.expected_global_object,
  )
  receiver_recursion_revalidate_trusted(
    self,
    registry.trusted,
    registry.expected_global_object,
  )
  registry
}

///|
fn TrustedReceiverRecursionRegistry::require_receiver(
  self : TrustedReceiverRecursionRegistry,
  interp : Interpreter,
) -> Value raise InvalidActivationDispatchShell {
  receiver_recursion_revalidate_trusted(
    interp,
    self.trusted,
    self.expected_global_object,
  )
  self.trusted.receiver
}

///|
fn TrustedReceiverRecursionRegistry::require_callee(
  self : TrustedReceiverRecursionRegistry,
  interp : Interpreter,
  candidate : Value,
) -> Value raise InvalidActivationDispatchShell {
  receiver_recursion_revalidate_trusted(
    interp,
    self.trusted,
    self.expected_global_object,
  )
  guard receiver_recursion_function_identity_matches(
    self.trusted.callee,
    candidate,
  ) else {
    invalid_activation_dispatch_shell(
      "receiver recursion callee identity is outside the sealed own data property",
    )
  }
  candidate
}

///|
#warnings("-unused_value")
fn TrustedReceiverRecursionRegistry::require_call(
  self : TrustedReceiverRecursionRegistry,
  interp : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
) -> Value raise InvalidActivationDispatchShell {
  let receiver = self.require_receiver(interp)
  let trusted_callee = self.require_callee(interp, callee)
  guard receiver_recursion_value_identity(receiver, this_value) &&
    args.length() == 1 &&
    args[0] is Number(_) else {
    invalid_activation_dispatch_shell(
      "receiver recursion call escaped the sealed receiver/argument envelope",
    )
  }
  trusted_callee
}
