// Callback-free provenance sealing for the closed constructor recipe.  The
// shell may use this registry only after every global/function/prototype check
// below has succeeded; recursive edges never perform name or property lookup.

///|
priv struct ConstructorRecursionPreflight {
  plan : ConstructorRecursionPlan
  expected_global_object : ObjectData
  expected_object_prototype : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
}

///|
fn ConstructorRecursionPreflight::ConstructorRecursionPreflight(
  plan~ : ConstructorRecursionPlan,
  expected_global_object~ : ObjectData,
  expected_object_prototype~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
) -> ConstructorRecursionPreflight {
  {
    plan,
    expected_global_object,
    expected_object_prototype,
    expected_realm_protos,
    expected_source_identity,
    throw_type_error_snapshot,
  }
}

///|
#warnings("-unused_field")
priv struct TrustedConstructorRecursionFunction {
  plan : ConstructorRecursionFunctionPlan
  callee : Value
  closure : Environment
  params : Array[String]
  body : Array[@ast.Stmt]
  strict : Bool
  source_text : String?
  prototype : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn TrustedConstructorRecursionFunction::TrustedConstructorRecursionFunction(
  plan~ : ConstructorRecursionFunctionPlan,
  callee~ : Value,
  closure~ : Environment,
  params~ : Array[String],
  body~ : Array[@ast.Stmt],
  strict~ : Bool,
  source_text~ : String?,
  prototype~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedConstructorRecursionFunction {
  {
    plan,
    callee,
    closure,
    params,
    body,
    strict,
    source_text,
    prototype,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
#warnings("-unused_field")
priv struct TrustedConstructorRecursionRegistry {
  plan : ConstructorRecursionPlan
  functions : Array[TrustedConstructorRecursionFunction]
  expected_global_object : ObjectData
  expected_object_prototype : Value
  throw_type_error : Value?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
}

///|
fn TrustedConstructorRecursionRegistry::TrustedConstructorRecursionRegistry(
  plan~ : ConstructorRecursionPlan,
  functions~ : Array[TrustedConstructorRecursionFunction],
  expected_global_object~ : ObjectData,
  expected_object_prototype~ : Value,
  throw_type_error~ : Value?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
) -> TrustedConstructorRecursionRegistry {
  {
    plan,
    functions: functions.copy(),
    expected_global_object,
    expected_object_prototype,
    throw_type_error,
    throw_type_error_snapshot,
  }
}

///|
fn constructor_recursion_global_binding(
  interp : Interpreter,
  name : String,
) -> Value? {
  match interp.global.bindings.get(name) {
    Some(binding) if binding.initialized && binding.kind == VarBinding =>
      Some(binding.value)
    _ => None
  }
}

///|
fn constructor_recursion_value_identity(
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
fn constructor_recursion_own_prototype(
  callee : Value,
) -> (Value, PropDescriptor)? {
  match callee {
    Object({ callable: Some(UserFunc(_)), bag, .. }) =>
      match
        (bag.properties.get("prototype"), bag.descriptors.get("prototype")) {
        (Some(value), Some(descriptor)) if !descriptor.is_accessor &&
          descriptor.getter is None &&
          descriptor.setter is None => Some((value, descriptor))
        _ => None
      }
    _ => None
  }
}

///|
fn constructor_recursion_instance_prototype(
  callee : Value,
  expected_object_prototype : Value,
) -> Value raise Error {
  let (prototype, _) = match constructor_recursion_own_prototype(callee) {
    Some(found) => found
    None =>
      raise @errors.TypeError(
        message="constructor prototype provenance changed",
      )
  }
  match prototype {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => prototype
    _ =>
      constructor_realm_intrinsic_prototype(
        callee, "Object", expected_object_prototype,
      )
  }
}

///|
fn constructor_recursion_function_matches(
  interp : Interpreter,
  trusted : TrustedConstructorRecursionFunction,
  candidate : Value,
) -> Bool {
  guard candidate is Object(actual_object) &&
    actual_object.class_name == "Function" &&
    actual_object.callable is Some(UserFunc(actual_data)) &&
    constructor_recursion_value_identity(trusted.callee, candidate) &&
    physical_equal(actual_data.params, trusted.params) &&
    physical_equal(actual_data.body, trusted.body) &&
    physical_equal(actual_data.closure, trusted.closure) &&
    actual_data.strict == trusted.strict &&
    actual_data.is_method == false &&
    actual_data.name == Some(trusted.plan.name) &&
    actual_data.source_text == trusted.source_text &&
    interp.global.parent is None else {
    return false
  }
  guard constructor_recursion_own_prototype(candidate)
    is Some((prototype, descriptor)) else {
    return false
  }
  guard constructor_recursion_value_identity(trusted.prototype, prototype) &&
    !descriptor.is_accessor &&
    descriptor.getter is None &&
    descriptor.setter is None else {
    return false
  }
  function_source_identity(candidate) == trusted.expected_source_identity &&
  numeric_recursion_realm_protos_match(
    trusted.expected_realm_protos,
    callee_realm_protos(candidate),
  )
}

///|
fn constructor_recursion_revalidate(
  interp : Interpreter,
  registry : TrustedConstructorRecursionRegistry,
) -> Unit raise InvalidActivationDispatchShell {
  guard interp.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, registry.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "constructor recursion global changed after callback-free admission",
    )
  }
  let actual_throw_type_error = numeric_recursion_callback_free_throw_type_error(
    interp.global,
  )
  guard numeric_recursion_callback_free_binding_snapshots_match(
    registry.throw_type_error_snapshot,
    actual_throw_type_error,
  ) else {
    invalid_activation_dispatch_shell(
      "constructor recursion ThrowTypeError binding changed after admission",
    )
  }
  for trusted in registry.functions {
    let candidate = match
      constructor_recursion_global_binding(interp, trusted.plan.name) {
      Some(value) => value
      None =>
        invalid_activation_dispatch_shell(
          "constructor recursion function binding was lost",
        )
    }
    guard constructor_recursion_function_matches(interp, trusted, candidate) else {
      invalid_activation_dispatch_shell(
        "constructor recursion function provenance changed",
      )
    }
  }
}

///|
fn Interpreter::preflight_constructor_recursion_program(
  self : Interpreter,
  plan : ConstructorRecursionPlan,
) -> ConstructorRecursionPreflight? {
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) else {
    return None
  }
  for function in plan.functions {
    guard !self.global.bindings.contains(function.name) &&
      expected_global_object.bag.properties.get(function.name) is None else {
      return None
    }
  }
  let expected_realm_protos = function_realm_protos_from_realm_state(
    self.realm_state,
  )
  let expected_object_prototype = match expected_realm_protos.object_proto {
    Some(value) => value
    None => get_obj_proto(realm_state=Some(self.realm_state))
  }
  let throw_type_error_snapshot = numeric_recursion_callback_free_throw_type_error(
    self.global,
  )
  match throw_type_error_snapshot {
    CallbackFreeBindingUnsafe => None
    _ =>
      Some(
        ConstructorRecursionPreflight(
          plan~,
          expected_global_object~,
          expected_object_prototype~,
          expected_realm_protos~,
          expected_source_identity=self.realm_state.active_source_identity.val,
          throw_type_error_snapshot~,
        ),
      )
  }
}

///|
#warnings("-unused_value")
fn Interpreter::preflight_dispatchable_constructor_recursion_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> ConstructorRecursionPreflight? {
  match classify_constructor_recursion_program(stmts) {
    Some(plan) => self.preflight_constructor_recursion_program(plan)
    None => None
  }
}

///|
fn Interpreter::seal_constructor_recursion_registry(
  self : Interpreter,
  preflight : ConstructorRecursionPreflight,
  stmts : Array[@ast.Stmt],
) -> TrustedConstructorRecursionRegistry raise InvalidActivationDispatchShell {
  guard self.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, preflight.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "constructor recursion global changed during root setup",
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
      "constructor recursion ThrowTypeError binding changed during root setup",
    )
  }
  let actual_plan = match classify_constructor_recursion_program(stmts) {
    Some(plan) => plan
    None =>
      invalid_activation_dispatch_shell(
        "constructor recursion program no longer satisfies exact admission",
      )
  }
  guard actual_plan.root_name == preflight.plan.root_name &&
    actual_plan.initial_argument == preflight.plan.initial_argument &&
    actual_plan.functions.length() == preflight.plan.functions.length() else {
    invalid_activation_dispatch_shell(
      "constructor recursion plan changed during root setup",
    )
  }
  let functions : Array[TrustedConstructorRecursionFunction] = []
  for index, function_plan in actual_plan.functions {
    guard constructor_recursion_root_statement_matches(
      actual_plan,
      index,
      stmts[index],
    ) else {
      invalid_activation_dispatch_shell(
        "constructor recursion declaration changed during root setup",
      )
    }
    let callee = match
      constructor_recursion_global_binding(self, function_plan.name) {
      Some(value) => value
      None =>
        invalid_activation_dispatch_shell(
          "constructor recursion declaration was not initialized",
        )
    }
    let (data, _) = match callee {
      Object({ callable: Some(UserFunc(data)), .. }) => (data, callee)
      _ =>
        invalid_activation_dispatch_shell(
          "constructor recursion declaration is not an ordinary UserFunc",
        )
    }
    let prototype_result : Result[Value, Error] = Ok(
      constructor_recursion_instance_prototype(
        callee,
        preflight.expected_object_prototype,
      ),
    ) catch {
      error => Err(error)
    }
    let prototype = match prototype_result {
      Ok(value) => value
      Err(_) =>
        invalid_activation_dispatch_shell(
          "constructor recursion prototype provenance could not be sealed",
        )
    }
    let trusted = TrustedConstructorRecursionFunction(
      plan=function_plan,
      callee~,
      closure=data.closure,
      params=data.params,
      body=data.body,
      strict=data.strict,
      source_text=data.source_text,
      prototype~,
      expected_realm_protos=preflight.expected_realm_protos,
      expected_source_identity=preflight.expected_source_identity,
    )
    guard constructor_recursion_function_matches(self, trusted, callee) else {
      invalid_activation_dispatch_shell(
        "constructor recursion declaration failed provenance sealing",
      )
    }
    functions.push(trusted)
  }
  let registry = TrustedConstructorRecursionRegistry(
    plan=actual_plan,
    functions~,
    expected_global_object=preflight.expected_global_object,
    expected_object_prototype=preflight.expected_object_prototype,
    throw_type_error=numeric_recursion_throw_type_error_value(
      actual_throw_type_error,
    ),
    throw_type_error_snapshot=preflight.throw_type_error_snapshot,
  )
  constructor_recursion_revalidate(self, registry)
  registry
}

///|
fn TrustedConstructorRecursionRegistry::require_function(
  self : TrustedConstructorRecursionRegistry,
  interp : Interpreter,
  name : String,
) -> TrustedConstructorRecursionFunction raise InvalidActivationDispatchShell {
  constructor_recursion_revalidate(interp, self)
  for function in self.functions {
    if function.plan.name == name {
      return function
    }
  }
  invalid_activation_dispatch_shell(
    "constructor recursion requested an unsealed function",
  )
}

///|
fn TrustedConstructorRecursionRegistry::require_root_function(
  self : TrustedConstructorRecursionRegistry,
  interp : Interpreter,
) -> TrustedConstructorRecursionFunction raise InvalidActivationDispatchShell {
  self.require_function(interp, self.plan.root_name)
}
