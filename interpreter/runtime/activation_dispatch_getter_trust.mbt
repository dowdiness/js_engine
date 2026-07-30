// Callback-free preflight and provenance sealing for the exact ordinary
// getter recursion slice. Root declarations run once before sealing; managed
// execution never falls back after the registry has been created.

///|
priv struct GetterRecursionPreflight {
  plan : GetterRecursionPlan
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
  expected_object_prototype : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn GetterRecursionPreflight::GetterRecursionPreflight(
  plan~ : GetterRecursionPlan,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
  expected_object_prototype~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> GetterRecursionPreflight {
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
priv struct TrustedGetterRecursionFunction {
  plan : GetterRecursionPlan
  target : Value
  getter : Value
  closure : Environment
  expected_source_text : String?
  expected_object_prototype : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn TrustedGetterRecursionFunction::TrustedGetterRecursionFunction(
  plan~ : GetterRecursionPlan,
  target~ : Value,
  getter~ : Value,
  closure~ : Environment,
  expected_source_text~ : String?,
  expected_object_prototype~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedGetterRecursionFunction {
  {
    plan,
    target,
    getter,
    closure,
    expected_source_text,
    expected_object_prototype,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
#warnings("-unused_field")
priv struct TrustedGetterRecursionRegistry {
  plan : GetterRecursionPlan
  trusted : TrustedGetterRecursionFunction
  throw_type_error : Value?
  expected_global_object : ObjectData
}

///|
fn TrustedGetterRecursionRegistry::TrustedGetterRecursionRegistry(
  plan~ : GetterRecursionPlan,
  trusted~ : TrustedGetterRecursionFunction,
  throw_type_error~ : Value?,
  expected_global_object~ : ObjectData,
) -> TrustedGetterRecursionRegistry {
  { plan, trusted, throw_type_error, expected_global_object }
}

///|
fn getter_recursion_direct_object_prototype(
  interp : Interpreter,
  realm_protos : FunctionRealmProtos,
) -> Value? {
  match
    (
      interp.global.bindings.get("[[ObjectPrototype]]"),
      realm_protos.object_proto,
    ) {
    (None, None) => Some(Null)
    (Some(binding), Some(realm_object_prototype)) if binding.initialized &&
      binding.value is Object(_) &&
      same_value(binding.value, realm_object_prototype) => Some(binding.value)
    _ => None
  }
}

///|
#warnings("-unused_value")
fn Interpreter::preflight_getter_recursion_program(
  self : Interpreter,
  plan : GetterRecursionPlan,
) -> GetterRecursionPreflight? {
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) &&
    !self.global.bindings.contains(plan.counter_name) &&
    !self.global.bindings.contains(plan.object_name) else {
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
    GetterRecursionPreflight(
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
fn Interpreter::preflight_dispatchable_getter_recursion_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> GetterRecursionPreflight? {
  match classify_getter_recursion_program(stmts) {
    Some(plan) if getter_recursion_plan_is_dispatchable(plan) =>
      self.preflight_getter_recursion_program(plan)
    Some(_) | None => None
  }
}

///|
fn getter_recursion_plans_match(
  expected : GetterRecursionPlan,
  actual : GetterRecursionPlan,
) -> Bool {
  expected.counter_name == actual.counter_name &&
  expected.object_name == actual.object_name &&
  expected.property_name == actual.property_name &&
  same_value(Number(expected.initial_count), Number(actual.initial_count))
}

///|
fn getter_recursion_binding_value(
  interp : Interpreter,
  name : String,
) -> Value? {
  match interp.global.bindings.get(name) {
    Some(binding) if binding.initialized &&
      binding.kind == LetBinding &&
      !binding.is_parameter => Some(binding.value)
    _ => None
  }
}

///|
fn getter_recursion_getter_identity_matches(
  expected : Value,
  actual : Value,
) -> Bool {
  match (expected, actual) {
    (Object(expected_data), Object(actual_data)) =>
      physical_equal(expected_data, actual_data)
    _ => false
  }
}

///|
fn getter_recursion_target_identity_matches(
  expected : Value,
  actual : Value,
) -> Bool {
  match (expected, actual) {
    (Object(expected_data), Object(actual_data)) =>
      physical_equal(expected_data, actual_data)
    _ => false
  }
}

///|
fn getter_recursion_descriptor_matches(
  descriptor : PropDescriptor,
  getter : Value,
) -> Bool {
  !descriptor.writable &&
  descriptor.enumerable &&
  descriptor.configurable &&
  descriptor.is_accessor &&
  descriptor.setter is None &&
  (match descriptor.getter {
    Some(actual) => getter_recursion_getter_identity_matches(getter, actual)
    None => false
  })
}

///|
fn getter_recursion_user_func_matches_syntax(
  interp : Interpreter,
  trusted : TrustedGetterRecursionFunction,
  data : FuncData,
) -> Bool {
  let plan = trusted.plan
  guard data.name == Some(plan.property_name) &&
    data.params.is_empty() &&
    data.body.length() == 3 &&
    !data.strict &&
    !data.has_name_binding &&
    data.is_method &&
    physical_equal(data.closure, trusted.closure) &&
    data.source_text == trusted.expected_source_text &&
    data.closure.parent is Some(parent) &&
    physical_equal(parent, interp.global) &&
    data.closure.with_object is None &&
    !data.closure.is_var_scope &&
    data.closure.bindings.get("[[HomeObject]]") is Some(home_binding) &&
    home_binding.initialized &&
    getter_recursion_target_identity_matches(trusted.target, home_binding.value) else {
    return false
  }
  classify_getter_recursion_body(
    data.body,
    plan.counter_name,
    plan.object_name,
    plan.property_name,
    plan.recipe.root_member_loc,
  )
  is Some(_)
}

///|
fn getter_recursion_revalidate_trusted(
  interp : Interpreter,
  trusted : TrustedGetterRecursionFunction,
  expected_global_object : ObjectData,
) -> Unit raise InvalidActivationDispatchShell {
  guard interp.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, expected_global_object) else {
    invalid_activation_dispatch_shell(
      "getter recursion global changed after callback-free preflight",
    )
  }
  let target = match
    getter_recursion_binding_value(interp, trusted.plan.object_name) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "getter recursion object binding lost its trusted provenance",
      )
  }
  guard getter_recursion_target_identity_matches(trusted.target, target) &&
    target is Object(target_data) &&
    target_data.class_name == "Object" &&
    target_data.callable is None &&
    same_value(target_data.prototype, trusted.expected_object_prototype) &&
    target_data.bag.properties.get(trusted.plan.property_name)
    is Some(Undefined) &&
    target_data.bag.descriptors.get(trusted.plan.property_name)
    is Some(descriptor) &&
    getter_recursion_descriptor_matches(descriptor, trusted.getter) else {
    invalid_activation_dispatch_shell(
      "getter recursion target no longer has its exact own accessor",
    )
  }
  guard trusted.getter is Object(getter_data) &&
    getter_data.class_name == "Function" &&
    getter_data.callable is Some(UserFunc(data)) &&
    getter_recursion_user_func_matches_syntax(interp, trusted, data) else {
    invalid_activation_dispatch_shell(
      "getter recursion candidate no longer has exact UserFunc provenance",
    )
  }
  guard function_source_identity(trusted.getter) ==
    trusted.expected_source_identity else {
    invalid_activation_dispatch_shell(
      "getter recursion candidate source identity changed after sealing",
    )
  }
  guard numeric_recursion_realm_protos_match(
    trusted.expected_realm_protos,
    callee_realm_protos(trusted.getter),
  ) else {
    invalid_activation_dispatch_shell(
      "getter recursion candidate realm provenance changed after sealing",
    )
  }
}

///|
fn getter_recursion_trusted_function(
  interp : Interpreter,
  preflight : GetterRecursionPreflight,
) -> TrustedGetterRecursionFunction raise InvalidActivationDispatchShell {
  let target = match
    getter_recursion_binding_value(interp, preflight.plan.object_name) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "getter recursion object binding was not initialized exactly once",
      )
  }
  guard getter_recursion_binding_value(interp, preflight.plan.counter_name)
    is Some(Number(count)) &&
    same_value(Number(count), Number(preflight.plan.initial_count)) else {
    invalid_activation_dispatch_shell(
      "getter recursion counter binding was not initialized exactly once",
    )
  }
  guard target is Object(target_data) &&
    target_data.class_name == "Object" &&
    target_data.callable is None &&
    same_value(target_data.prototype, preflight.expected_object_prototype) &&
    target_data.bag.properties.get(preflight.plan.property_name)
    is Some(Undefined) &&
    target_data.bag.descriptors.get(preflight.plan.property_name)
    is Some(descriptor) &&
    descriptor.getter is Some(getter) else {
    invalid_activation_dispatch_shell(
      "getter recursion root did not create its exact own accessor",
    )
  }
  guard getter is Object(getter_data) &&
    getter_data.class_name == "Function" &&
    getter_data.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "getter recursion root did not create a UserFunc getter",
    )
  }
  let trusted = TrustedGetterRecursionFunction(
    plan=preflight.plan,
    target~,
    getter~,
    closure=data.closure,
    expected_source_text=data.source_text,
    expected_object_prototype=preflight.expected_object_prototype,
    expected_realm_protos=preflight.expected_realm_protos,
    expected_source_identity=preflight.expected_source_identity,
  )
  guard getter_recursion_descriptor_matches(descriptor, getter) &&
    getter_recursion_user_func_matches_syntax(interp, trusted, data) else {
    invalid_activation_dispatch_shell(
      "getter recursion root getter no longer matches its admitted syntax",
    )
  }
  guard function_source_identity(getter) == preflight.expected_source_identity &&
    numeric_recursion_realm_protos_match(
      preflight.expected_realm_protos,
      callee_realm_protos(getter),
    ) else {
    invalid_activation_dispatch_shell(
      "getter recursion UserFunc realm or source provenance changed during root setup",
    )
  }
  trusted
}

///|
#warnings("-unused_value")
fn Interpreter::seal_getter_recursion_registry(
  self : Interpreter,
  preflight : GetterRecursionPreflight,
  stmts : Array[@ast.Stmt],
) -> TrustedGetterRecursionRegistry raise InvalidActivationDispatchShell {
  guard self.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, preflight.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "getter recursion global changed after callback-free preflight",
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
      "getter recursion ThrowTypeError binding changed after callback-free preflight",
    )
  }
  let actual_plan = match classify_getter_recursion_program(stmts) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "getter recursion program no longer satisfies exact admission",
      )
  }
  guard getter_recursion_plans_match(preflight.plan, actual_plan) else {
    invalid_activation_dispatch_shell(
      "getter recursion program no longer matches its preflight plan",
    )
  }
  let trusted = getter_recursion_trusted_function(self, preflight)
  let registry = TrustedGetterRecursionRegistry(
    plan=actual_plan,
    trusted~,
    throw_type_error=numeric_recursion_throw_type_error_value(
      actual_throw_type_error,
    ),
    expected_global_object=preflight.expected_global_object,
  )
  getter_recursion_revalidate_trusted(
    self,
    registry.trusted,
    registry.expected_global_object,
  )
  registry
}

///|
#warnings("-unused_value")
fn TrustedGetterRecursionRegistry::require_target(
  self : TrustedGetterRecursionRegistry,
  interp : Interpreter,
) -> Value raise InvalidActivationDispatchShell {
  getter_recursion_revalidate_trusted(
    interp,
    self.trusted,
    self.expected_global_object,
  )
  self.trusted.target
}

///|
#warnings("-unused_value")
fn TrustedGetterRecursionRegistry::require_getter(
  self : TrustedGetterRecursionRegistry,
  interp : Interpreter,
  candidate : Value,
  receiver : Value,
) -> GetterRecursionPlan raise InvalidActivationDispatchShell {
  let target = self.require_target(interp)
  guard getter_recursion_target_identity_matches(target, receiver) else {
    invalid_activation_dispatch_shell(
      "getter recursion receiver is outside the trusted target",
    )
  }
  guard getter_recursion_getter_identity_matches(self.trusted.getter, candidate) else {
    invalid_activation_dispatch_shell(
      "getter recursion callee identity is outside the trusted accessor",
    )
  }
  self.plan
}
