// Callback-free preflight and runtime provenance sealing for the exact Proxy
// `get` recursion slice. Root setup runs before sealing; each managed property
// access captures target and handler once before handler.[[Get]].

///|
priv struct ProxyGetRecursionPreflight {
  plan : ProxyGetRecursionPlan
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
  expected_object_prototype : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
  expected_proxy_constructor : Value
}

///|
fn ProxyGetRecursionPreflight::ProxyGetRecursionPreflight(
  plan~ : ProxyGetRecursionPlan,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
  expected_object_prototype~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
  expected_proxy_constructor~ : Value,
) -> ProxyGetRecursionPreflight {
  {
    plan,
    throw_type_error_snapshot,
    expected_global_object,
    expected_object_prototype,
    expected_realm_protos,
    expected_source_identity,
    expected_proxy_constructor,
  }
}

///|
priv struct TrustedProxyGetRecursionFunction {
  plan : ProxyGetRecursionPlan
  proxy : Value
  target : Value
  handler : Value
  trap : Value
  closure : Environment
  expected_source_text : String?
  expected_object_prototype : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn TrustedProxyGetRecursionFunction::TrustedProxyGetRecursionFunction(
  plan~ : ProxyGetRecursionPlan,
  proxy~ : Value,
  target~ : Value,
  handler~ : Value,
  trap~ : Value,
  closure~ : Environment,
  expected_source_text~ : String?,
  expected_object_prototype~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedProxyGetRecursionFunction {
  {
    plan,
    proxy,
    target,
    handler,
    trap,
    closure,
    expected_source_text,
    expected_object_prototype,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
#warnings("-unused_field")
priv struct TrustedProxyGetRecursionRegistry {
  plan : ProxyGetRecursionPlan
  trusted : TrustedProxyGetRecursionFunction
  throw_type_error : Value?
  expected_global_object : ObjectData
  expected_proxy_constructor : Value
}

///|
fn TrustedProxyGetRecursionRegistry::TrustedProxyGetRecursionRegistry(
  plan~ : ProxyGetRecursionPlan,
  trusted~ : TrustedProxyGetRecursionFunction,
  throw_type_error~ : Value?,
  expected_global_object~ : ObjectData,
  expected_proxy_constructor~ : Value,
) -> TrustedProxyGetRecursionRegistry {
  {
    plan,
    trusted,
    throw_type_error,
    expected_global_object,
    expected_proxy_constructor,
  }
}

///|
#warnings("-unused_field")
priv struct TrustedProxyGetCapture {
  proxy : Value
  target : Value
  handler : Value
  property_key : Value
  receiver : Value
}

///|
fn TrustedProxyGetCapture::TrustedProxyGetCapture(
  proxy~ : Value,
  target~ : Value,
  handler~ : Value,
  property_key~ : Value,
  receiver~ : Value,
) -> TrustedProxyGetCapture {
  { proxy, target, handler, property_key, receiver }
}

///|
fn proxy_get_recursion_object_identity_matches(
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
fn proxy_get_recursion_proxy_identity_matches(
  expected : Value,
  actual : Value,
) -> Bool {
  match (expected, actual) {
    (Proxy(expected_data), Proxy(actual_data)) =>
      physical_equal(expected_data, actual_data)
    _ => false
  }
}

///|
fn proxy_get_recursion_constructor_provenance(interp : Interpreter) -> Value? {
  match interp.global.bindings.get(PROXY_GET_RECURSION_CONSTRUCTOR_NAME) {
    Some(binding) if binding.initialized &&
      binding.kind == VarBinding &&
      !binding.is_parameter =>
      match (binding.value, interp.global_this) {
        (Object(data), Object(global_object)) if data.class_name == "Function" &&
          data.callable is Some(ConstructorOnlyCallable(name, _)) &&
          name == PROXY_GET_RECURSION_CONSTRUCTOR_NAME &&
          interp.realm_state.canonical_proxy_constructor_matches(binding.value) &&
          global_object.bag.properties.get(PROXY_GET_RECURSION_CONSTRUCTOR_NAME)
          is Some(Object(mirrored)) &&
          physical_equal(data, mirrored) => Some(binding.value)
        _ => None
      }
    _ => None
  }
}

///|
fn proxy_get_recursion_binding_value(
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
#warnings("-unused_value")
fn Interpreter::preflight_proxy_get_recursion_program(
  self : Interpreter,
  plan : ProxyGetRecursionPlan,
) -> ProxyGetRecursionPreflight? {
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) &&
    !self.global.bindings.contains(plan.counter_name) &&
    !self.global.bindings.contains(plan.proxy_name) &&
    proxy_get_recursion_constructor_provenance(self)
    is Some(expected_proxy_constructor) else {
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
    ProxyGetRecursionPreflight(
      plan~,
      throw_type_error_snapshot~,
      expected_global_object~,
      expected_object_prototype~,
      expected_realm_protos~,
      expected_source_identity=self.realm_state.active_source_identity.val,
      expected_proxy_constructor~,
    ),
  )
}

///|
#warnings("-unused_value")
fn Interpreter::preflight_dispatchable_proxy_get_recursion_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> ProxyGetRecursionPreflight? {
  match classify_proxy_get_recursion_program(stmts) {
    Some(plan) if proxy_get_recursion_plan_is_dispatchable(plan) =>
      self.preflight_proxy_get_recursion_program(plan)
    Some(_) | None => None
  }
}

///|
fn proxy_get_recursion_plans_match(
  expected : ProxyGetRecursionPlan,
  actual : ProxyGetRecursionPlan,
) -> Bool {
  expected.counter_name == actual.counter_name &&
  expected.proxy_name == actual.proxy_name &&
  expected.property_name == actual.property_name &&
  expected.target_parameter == actual.target_parameter &&
  expected.key_parameter == actual.key_parameter &&
  expected.receiver_parameter == actual.receiver_parameter &&
  same_value(Number(expected.initial_count), Number(actual.initial_count))
}

///|
fn proxy_get_recursion_empty_target_matches(
  target : Value,
  expected_object_prototype : Value,
) -> Bool {
  match target {
    Object(data) =>
      data.class_name == "Object" &&
      data.callable is None &&
      same_value(data.prototype, expected_object_prototype) &&
      data.extensible &&
      data.arraybuffer_state is None &&
      data.bag.properties.is_empty() &&
      data.bag.descriptors.is_empty() &&
      data.bag.symbol_properties.is_empty() &&
      data.bag.symbol_descriptors.is_empty() &&
      data.bag.internal_slots.is_empty() &&
      data.bag.host_slots.is_empty()
    _ => false
  }
}

///|
fn proxy_get_recursion_handler_matches(
  handler : Value,
  trap : Value,
  expected_object_prototype : Value,
) -> Bool {
  match handler {
    Object(data) =>
      data.class_name == "Object" &&
      data.callable is None &&
      same_value(data.prototype, expected_object_prototype) &&
      data.extensible &&
      data.arraybuffer_state is None &&
      data.bag.properties.length() == 1 &&
      data.bag.properties.get(PROXY_GET_RECURSION_TRAP_NAME)
      is Some(actual_trap) &&
      proxy_get_recursion_object_identity_matches(trap, actual_trap) &&
      data.bag.descriptors.is_empty() &&
      data.bag.symbol_properties.is_empty() &&
      data.bag.symbol_descriptors.is_empty() &&
      data.bag.internal_slots.is_empty() &&
      data.bag.host_slots.is_empty()
    _ => false
  }
}

///|
fn proxy_get_recursion_params_match(
  plan : ProxyGetRecursionPlan,
  params : Array[String],
) -> Bool {
  params.length() == 3 &&
  params[0] == plan.target_parameter &&
  params[1] == plan.key_parameter &&
  params[2] == plan.receiver_parameter
}

///|
fn proxy_get_recursion_trap_matches_syntax(
  interp : Interpreter,
  trusted : TrustedProxyGetRecursionFunction,
  data : FuncData,
) -> Bool {
  let plan = trusted.plan
  guard data.name == Some(PROXY_GET_RECURSION_TRAP_NAME) &&
    proxy_get_recursion_params_match(plan, data.params) &&
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
    proxy_get_recursion_object_identity_matches(
      trusted.handler,
      home_binding.value,
    ) else {
    return false
  }
  classify_proxy_get_recursion_body(
    data.body,
    plan.counter_name,
    plan.proxy_name,
    plan.property_name,
    plan.recipe.root_member_loc,
  )
  is Some(_)
}

///|
fn proxy_get_recursion_trap_provenance_matches(
  interp : Interpreter,
  trusted : TrustedProxyGetRecursionFunction,
  candidate : Value,
) -> Bool {
  guard proxy_get_recursion_object_identity_matches(trusted.trap, candidate) &&
    candidate is Object(trap_data) &&
    trap_data.class_name == "Function" &&
    trap_data.callable is Some(UserFunc(data)) &&
    proxy_get_recursion_trap_matches_syntax(interp, trusted, data) &&
    function_source_identity(candidate) == trusted.expected_source_identity &&
    numeric_recursion_realm_protos_match(
      trusted.expected_realm_protos,
      callee_realm_protos(candidate),
    ) else {
    return false
  }
  true
}

///|
fn proxy_get_recursion_revalidate_trusted(
  interp : Interpreter,
  registry : TrustedProxyGetRecursionRegistry,
) -> Unit raise InvalidActivationDispatchShell {
  let trusted = registry.trusted
  guard interp.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, registry.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "Proxy get recursion global changed after callback-free preflight",
    )
  }
  guard proxy_get_recursion_constructor_provenance(interp)
    is Some(actual_constructor) &&
    proxy_get_recursion_object_identity_matches(
      registry.expected_proxy_constructor,
      actual_constructor,
    ) else {
    invalid_activation_dispatch_shell(
      "Proxy get recursion constructor provenance changed after sealing",
    )
  }
  let proxy = match
    proxy_get_recursion_binding_value(interp, trusted.plan.proxy_name) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "Proxy get recursion binding lost its sealed provenance",
      )
  }
  guard proxy_get_recursion_proxy_identity_matches(trusted.proxy, proxy) &&
    proxy is Proxy(proxy_data) &&
    !proxy_data.is_callable &&
    !proxy_data.is_constructor &&
    proxy_data.target is Some(actual_target) &&
    proxy_data.handler is Some(actual_handler) &&
    proxy_get_recursion_object_identity_matches(trusted.target, actual_target) &&
    proxy_get_recursion_object_identity_matches(trusted.handler, actual_handler) &&
    proxy_get_recursion_empty_target_matches(
      actual_target,
      trusted.expected_object_prototype,
    ) &&
    proxy_get_recursion_handler_matches(
      actual_handler,
      trusted.trap,
      trusted.expected_object_prototype,
    ) &&
    proxy_get_recursion_trap_provenance_matches(interp, trusted, trusted.trap) else {
    invalid_activation_dispatch_shell(
      "Proxy get recursion object graph no longer matches sealed provenance",
    )
  }
}

///|
fn proxy_get_recursion_trusted_function(
  interp : Interpreter,
  preflight : ProxyGetRecursionPreflight,
) -> TrustedProxyGetRecursionFunction raise InvalidActivationDispatchShell {
  guard proxy_get_recursion_binding_value(interp, preflight.plan.counter_name)
    is Some(Number(count)) &&
    same_value(Number(count), Number(preflight.plan.initial_count)) else {
    invalid_activation_dispatch_shell(
      "Proxy get recursion counter was not initialized exactly once",
    )
  }
  let proxy = match
    proxy_get_recursion_binding_value(interp, preflight.plan.proxy_name) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "Proxy get recursion root did not initialize its Proxy binding",
      )
  }
  guard proxy is Proxy(proxy_data) &&
    !proxy_data.is_callable &&
    !proxy_data.is_constructor &&
    proxy_data.target is Some(target) &&
    proxy_data.handler is Some(handler) &&
    proxy_get_recursion_empty_target_matches(
      target,
      preflight.expected_object_prototype,
    ) &&
    handler is Object(handler_data) &&
    handler_data.bag.properties.get(PROXY_GET_RECURSION_TRAP_NAME) is Some(trap) &&
    proxy_get_recursion_handler_matches(
      handler,
      trap,
      preflight.expected_object_prototype,
    ) &&
    trap is Object(trap_data) &&
    trap_data.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "Proxy get recursion root did not create its exact object graph",
    )
  }
  let trusted = TrustedProxyGetRecursionFunction(
    plan=preflight.plan,
    proxy~,
    target~,
    handler~,
    trap~,
    closure=data.closure,
    expected_source_text=data.source_text,
    expected_object_prototype=preflight.expected_object_prototype,
    expected_realm_protos=preflight.expected_realm_protos,
    expected_source_identity=preflight.expected_source_identity,
  )
  guard proxy_get_recursion_trap_provenance_matches(interp, trusted, trap) else {
    invalid_activation_dispatch_shell(
      "Proxy get recursion trap no longer matches its admitted syntax",
    )
  }
  trusted
}

///|
#warnings("-unused_value")
fn Interpreter::seal_proxy_get_recursion_registry(
  self : Interpreter,
  preflight : ProxyGetRecursionPreflight,
  stmts : Array[@ast.Stmt],
) -> TrustedProxyGetRecursionRegistry raise InvalidActivationDispatchShell {
  guard self.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, preflight.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "Proxy get recursion global changed after callback-free preflight",
    )
  }
  guard proxy_get_recursion_constructor_provenance(self)
    is Some(actual_constructor) &&
    proxy_get_recursion_object_identity_matches(
      preflight.expected_proxy_constructor,
      actual_constructor,
    ) else {
    invalid_activation_dispatch_shell(
      "Proxy get recursion constructor changed during root setup",
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
      "Proxy get recursion ThrowTypeError binding changed during root setup",
    )
  }
  let actual_plan = match classify_proxy_get_recursion_program(stmts) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "Proxy get recursion program no longer satisfies exact admission",
      )
  }
  guard proxy_get_recursion_plans_match(preflight.plan, actual_plan) else {
    invalid_activation_dispatch_shell(
      "Proxy get recursion program no longer matches its preflight plan",
    )
  }
  let trusted = proxy_get_recursion_trusted_function(self, preflight)
  let registry = TrustedProxyGetRecursionRegistry(
    plan=actual_plan,
    trusted~,
    throw_type_error=numeric_recursion_throw_type_error_value(
      actual_throw_type_error,
    ),
    expected_global_object=preflight.expected_global_object,
    expected_proxy_constructor=preflight.expected_proxy_constructor,
  )
  proxy_get_recursion_revalidate_trusted(self, registry)
  registry
}

///|
#warnings("-unused_value")
fn TrustedProxyGetRecursionRegistry::require_proxy(
  self : TrustedProxyGetRecursionRegistry,
  interp : Interpreter,
) -> Value raise InvalidActivationDispatchShell {
  proxy_get_recursion_revalidate_trusted(interp, self)
  self.trusted.proxy
}

///|
#warnings("-unused_value")
fn TrustedProxyGetRecursionRegistry::capture_get(
  self : TrustedProxyGetRecursionRegistry,
  interp : Interpreter,
  proxy : Value,
  property_key : Value,
  receiver : Value,
) -> TrustedProxyGetCapture raise InvalidActivationDispatchShell {
  let trusted_proxy = self.require_proxy(interp)
  guard proxy_get_recursion_proxy_identity_matches(trusted_proxy, proxy) &&
    proxy_get_recursion_proxy_identity_matches(trusted_proxy, receiver) &&
    property_key is String_(property_name) &&
    property_name == self.plan.property_name else {
    invalid_activation_dispatch_shell(
      "Proxy get request is outside the sealed exact property envelope",
    )
  }
  TrustedProxyGetCapture(
    proxy~,
    target=self.trusted.target,
    handler=self.trusted.handler,
    property_key~,
    receiver~,
  )
}

///|
#warnings("-unused_value")
fn TrustedProxyGetRecursionRegistry::require_resolved_trap(
  self : TrustedProxyGetRecursionRegistry,
  interp : Interpreter,
  capture : TrustedProxyGetCapture,
  candidate : Value,
) -> ProxyGetRecursionPlan raise InvalidActivationDispatchShell {
  let trusted = self.trusted
  // Deliberately do not call `require_proxy` here. Proxy [[Target]] and
  // [[Handler]] were captured before handler.[[Get]] and must not be reread.
  guard proxy_get_recursion_proxy_identity_matches(trusted.proxy, capture.proxy) &&
    proxy_get_recursion_object_identity_matches(trusted.target, capture.target) &&
    proxy_get_recursion_object_identity_matches(
      trusted.handler,
      capture.handler,
    ) &&
    proxy_get_recursion_proxy_identity_matches(trusted.proxy, capture.receiver) &&
    capture.property_key is String_(property_name) &&
    property_name == self.plan.property_name &&
    proxy_get_recursion_trap_provenance_matches(interp, trusted, candidate) else {
    invalid_activation_dispatch_shell(
      "resolved Proxy get trap is outside the captured exact envelope",
    )
  }
  self.plan
}

///|
#warnings("-unused_value")
fn TrustedProxyGetRecursionRegistry::require_trap_call(
  self : TrustedProxyGetRecursionRegistry,
  interp : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
) -> ProxyGetRecursionPlan raise InvalidActivationDispatchShell {
  let trusted = self.trusted
  guard args.length() == 3 &&
    proxy_get_recursion_object_identity_matches(trusted.handler, this_value) &&
    proxy_get_recursion_object_identity_matches(trusted.target, args[0]) &&
    args[1] is String_(property_name) &&
    property_name == self.plan.property_name &&
    proxy_get_recursion_proxy_identity_matches(trusted.proxy, args[2]) &&
    proxy_get_recursion_trap_provenance_matches(interp, trusted, callee) else {
    invalid_activation_dispatch_shell(
      "Proxy get trap call is outside the captured exact envelope",
    )
  }
  self.plan
}
