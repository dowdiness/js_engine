// Callback-free provenance sealing for the exact two-node receiver recipe.
// The registry owns one receiver and two distinct trusted UserFunc records;
// no general graph or post-admission property lookup is introduced.

///|
priv struct MutualReceiverRecursionPreflight {
  plan : MutualReceiverRecursionPlan
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
  expected_object_prototype : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn MutualReceiverRecursionPreflight::MutualReceiverRecursionPreflight(
  plan~ : MutualReceiverRecursionPlan,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
  expected_object_prototype~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> MutualReceiverRecursionPreflight {
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
priv struct TrustedMutualReceiverRecursionFunction {
  node : MutualReceiverNode
  full_plan : MutualReceiverRecursionPlan
  plan : MutualReceiverNodePlan
  receiver : Value
  callee : Value
  closure : Environment
  params : Array[String]
  body : Array[@ast.Stmt]
  first_body_statement : @ast.Stmt
  second_body_statement : @ast.Stmt
  source_text : String?
  expected_object_prototype : Value
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn TrustedMutualReceiverRecursionFunction::TrustedMutualReceiverRecursionFunction(
  node~ : MutualReceiverNode,
  full_plan~ : MutualReceiverRecursionPlan,
  plan~ : MutualReceiverNodePlan,
  receiver~ : Value,
  callee~ : Value,
  closure~ : Environment,
  params~ : Array[String],
  body~ : Array[@ast.Stmt],
  first_body_statement~ : @ast.Stmt,
  second_body_statement~ : @ast.Stmt,
  source_text~ : String?,
  expected_object_prototype~ : Value,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedMutualReceiverRecursionFunction {
  {
    node,
    full_plan,
    plan,
    receiver,
    callee,
    closure,
    params,
    body,
    first_body_statement,
    second_body_statement,
    source_text,
    expected_object_prototype,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
#warnings("-unused_field")
priv struct TrustedMutualReceiverRecursionRegistry {
  plan : MutualReceiverRecursionPlan
  receiver : Value
  left : TrustedMutualReceiverRecursionFunction
  right : TrustedMutualReceiverRecursionFunction
  throw_type_error : Value?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
}

///|
fn TrustedMutualReceiverRecursionRegistry::TrustedMutualReceiverRecursionRegistry(
  plan~ : MutualReceiverRecursionPlan,
  receiver~ : Value,
  left~ : TrustedMutualReceiverRecursionFunction,
  right~ : TrustedMutualReceiverRecursionFunction,
  throw_type_error~ : Value?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
) -> TrustedMutualReceiverRecursionRegistry {
  {
    plan,
    receiver,
    left,
    right,
    throw_type_error,
    throw_type_error_snapshot,
    expected_global_object,
  }
}

///|
fn mutual_receiver_value_identity(expected : Value, actual : Value) -> Bool {
  match (expected, actual) {
    (Object(expected_data), Object(actual_data)) =>
      physical_equal(expected_data, actual_data)
    _ => false
  }
}

///|
fn mutual_receiver_binding_value(
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
fn mutual_receiver_registry_function(
  registry : TrustedMutualReceiverRecursionRegistry,
  node : MutualReceiverNode,
) -> TrustedMutualReceiverRecursionFunction {
  match node {
    MutualReceiverLeft => registry.left
    MutualReceiverRight => registry.right
  }
}

///|
fn mutual_receiver_object_shape_matches(
  receiver : Value,
  left_callee : Value,
  right_callee : Value,
  expected_object_prototype : Value,
  plan : MutualReceiverRecursionPlan,
) -> Bool {
  match receiver {
    Object(data) => {
      guard data.class_name == "Object" &&
        data.callable is None &&
        same_value(data.prototype, expected_object_prototype) &&
        data.extensible &&
        data.arraybuffer_state is None &&
        data.bag.properties.length() == 3 &&
        data.bag.descriptors.is_empty() &&
        data.bag.symbol_properties.is_empty() &&
        data.bag.symbol_descriptors.is_empty() &&
        data.bag.internal_slots.is_empty() &&
        data.bag.host_slots.is_empty() else {
        return false
      }
      guard data.bag.properties.get(plan.marker_name) is Some(Number(marker)) &&
        marker == NUMERIC_RECURSION_BASE &&
        data.bag.properties.get(plan.left.property_name) is Some(actual_left) &&
        mutual_receiver_value_identity(left_callee, actual_left) &&
        data.bag.properties.get(plan.right.property_name) is Some(actual_right) &&
        mutual_receiver_value_identity(right_callee, actual_right) else {
        return false
      }
      true
    }
    _ => false
  }
}

///|
fn mutual_receiver_user_func_matches_syntax(
  interp : Interpreter,
  trusted : TrustedMutualReceiverRecursionFunction,
  data : FuncData,
) -> Bool {
  data.name == Some(trusted.plan.function_name) &&
  data.params.length() == 1 &&
  data.params[0] == trusted.plan.parameter &&
  data.body.length() == 2 &&
  physical_equal(data.closure, trusted.closure) &&
  physical_equal(data.closure, interp.global) &&
  !data.strict &&
  !data.has_name_binding &&
  !data.is_method &&
  data.source_text == trusted.source_text &&
  physical_equal(data.body[0], trusted.body[0]) &&
  physical_equal(data.body[1], trusted.body[1]) &&
  physical_equal(data.body[0], trusted.first_body_statement) &&
  physical_equal(data.body[1], trusted.second_body_statement) &&
  mutual_receiver_body_statement_matches(
    trusted.full_plan,
    trusted.node,
    0,
    data.body[0],
  ) &&
  mutual_receiver_body_statement_matches(
    trusted.full_plan,
    trusted.node,
    1,
    data.body[1],
  ) &&
  interp.global.parent is None
}

///|
fn mutual_receiver_global_function_matches(
  interp : Interpreter,
  trusted : TrustedMutualReceiverRecursionFunction,
  candidate : Value,
) -> Bool {
  guard candidate is Object(actual) &&
    actual.class_name == "Function" &&
    actual.callable is Some(UserFunc(data)) &&
    mutual_receiver_value_identity(trusted.callee, candidate) &&
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
    mutual_receiver_user_func_matches_syntax(interp, trusted, data) else {
    return false
  }
  function_source_identity(candidate) == trusted.expected_source_identity &&
  numeric_recursion_realm_protos_match(
    trusted.expected_realm_protos,
    callee_realm_protos(candidate),
  )
}

///|
fn mutual_receiver_revalidate_function(
  interp : Interpreter,
  trusted : TrustedMutualReceiverRecursionFunction,
  expected_global_object : ObjectData,
) -> Unit raise InvalidActivationDispatchShell {
  guard interp.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, expected_global_object) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion global changed after callback-free preflight",
    )
  }
  let candidate = match
    mutual_receiver_binding_value(
      interp,
      trusted.plan.function_name,
      VarBinding,
    ) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "mutual receiver recursion function binding lost its provenance",
      )
  }
  guard mutual_receiver_value_identity(trusted.callee, candidate) &&
    mutual_receiver_global_function_matches(interp, trusted, candidate) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion function graph drifted after sealing",
    )
  }
}

///|
fn mutual_receiver_revalidate_registry(
  interp : Interpreter,
  registry : TrustedMutualReceiverRecursionRegistry,
) -> Unit raise InvalidActivationDispatchShell {
  guard numeric_recursion_callback_free_binding_snapshots_match(
    registry.throw_type_error_snapshot,
    numeric_recursion_callback_free_throw_type_error(interp.global),
  ) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion ThrowTypeError binding changed after sealing",
    )
  }
  mutual_receiver_revalidate_function(
    interp,
    registry.left,
    registry.expected_global_object,
  )
  mutual_receiver_revalidate_function(
    interp,
    registry.right,
    registry.expected_global_object,
  )
  let receiver = match
    mutual_receiver_binding_value(
      interp,
      registry.plan.receiver_name,
      LetBinding,
    ) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "mutual receiver recursion object binding lost its provenance",
      )
  }
  guard mutual_receiver_value_identity(registry.receiver, receiver) &&
    mutual_receiver_object_shape_matches(
      receiver,
      registry.left.callee,
      registry.right.callee,
      registry.left.expected_object_prototype,
      registry.plan,
    ) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion object graph drifted after sealing",
    )
  }
}

///|
fn Interpreter::preflight_mutual_receiver_recursion_program(
  self : Interpreter,
  plan : MutualReceiverRecursionPlan,
) -> MutualReceiverRecursionPreflight? {
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) &&
    !self.global.bindings.contains(plan.receiver_name) &&
    !self.global.bindings.contains(plan.left.function_name) &&
    !self.global.bindings.contains(plan.right.function_name) &&
    expected_global_object.bag.properties.get(plan.receiver_name) is None &&
    expected_global_object.bag.properties.get(plan.left.function_name) is None &&
    expected_global_object.bag.properties.get(plan.right.function_name) is None else {
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
    MutualReceiverRecursionPreflight(
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
fn Interpreter::preflight_dispatchable_mutual_receiver_recursion_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> MutualReceiverRecursionPreflight? {
  match classify_mutual_receiver_recursion_program(stmts) {
    Some(plan) if mutual_receiver_recursion_plan_is_dispatchable(plan) =>
      self.preflight_mutual_receiver_recursion_program(plan)
    _ => None
  }
}

///|
fn mutual_receiver_trusted_function(
  interp : Interpreter,
  preflight : MutualReceiverRecursionPreflight,
  node : MutualReceiverNode,
  receiver : Value,
) -> TrustedMutualReceiverRecursionFunction raise InvalidActivationDispatchShell {
  let plan = match node {
    MutualReceiverLeft => preflight.plan.left
    MutualReceiverRight => preflight.plan.right
  }
  let callee = match
    mutual_receiver_binding_value(interp, plan.function_name, VarBinding) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "mutual receiver recursion function binding was not initialized exactly once",
      )
  }
  guard callee is Object(callee_data) &&
    callee_data.class_name == "Function" &&
    callee_data.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion root did not create an ordinary UserFunc",
    )
  }
  TrustedMutualReceiverRecursionFunction(
    node~,
    full_plan=preflight.plan,
    plan~,
    receiver~,
    callee~,
    closure=data.closure,
    params=data.params,
    body=data.body,
    first_body_statement=data.body[0],
    second_body_statement=data.body[1],
    source_text=data.source_text,
    expected_object_prototype=preflight.expected_object_prototype,
    expected_realm_protos=preflight.expected_realm_protos,
    expected_source_identity=preflight.expected_source_identity,
  )
}

///|
#warnings("-unused_value")
fn Interpreter::seal_mutual_receiver_recursion_registry(
  self : Interpreter,
  preflight : MutualReceiverRecursionPreflight,
  stmts : Array[@ast.Stmt],
) -> TrustedMutualReceiverRecursionRegistry raise InvalidActivationDispatchShell {
  guard self.numeric_recursion_canonical_global_object()
    is Some(actual_global_object) &&
    physical_equal(actual_global_object, preflight.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion global changed during root setup",
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
      "mutual receiver recursion ThrowTypeError binding changed during root setup",
    )
  }
  let actual_plan = match classify_mutual_receiver_recursion_program(stmts) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "mutual receiver recursion program no longer satisfies exact admission",
      )
  }
  guard mutual_receiver_recursion_plans_match(preflight.plan, actual_plan) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion program no longer matches its preflight plan",
    )
  }
  let receiver = match
    mutual_receiver_binding_value(self, actual_plan.receiver_name, LetBinding) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "mutual receiver recursion object binding was not initialized exactly once",
      )
  }
  let left = mutual_receiver_trusted_function(
    self,
    preflight,
    MutualReceiverLeft,
    receiver,
  )
  let right = mutual_receiver_trusted_function(
    self,
    preflight,
    MutualReceiverRight,
    receiver,
  )
  guard !mutual_receiver_value_identity(left.callee, right.callee) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion functions must remain distinct",
    )
  }
  guard mutual_receiver_object_shape_matches(
    receiver,
    left.callee,
    right.callee,
    preflight.expected_object_prototype,
    actual_plan,
  ) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion root object graph is not exact",
    )
  }
  guard mutual_receiver_global_function_matches(self, left, left.callee) &&
    mutual_receiver_global_function_matches(self, right, right.callee) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion functions no longer match their sealed syntax",
    )
  }
  let registry = TrustedMutualReceiverRecursionRegistry(
    plan=actual_plan,
    receiver~,
    left~,
    right~,
    throw_type_error=numeric_recursion_throw_type_error_value(
      actual_throw_type_error,
    ),
    throw_type_error_snapshot=preflight.throw_type_error_snapshot,
    expected_global_object=preflight.expected_global_object,
  )
  mutual_receiver_revalidate_registry(self, registry)
  registry
}

///|
fn TrustedMutualReceiverRecursionRegistry::require_receiver(
  self : TrustedMutualReceiverRecursionRegistry,
  interp : Interpreter,
) -> Value raise InvalidActivationDispatchShell {
  mutual_receiver_revalidate_registry(interp, self)
  self.receiver
}

///|
fn TrustedMutualReceiverRecursionRegistry::require_function(
  self : TrustedMutualReceiverRecursionRegistry,
  interp : Interpreter,
  node : MutualReceiverNode,
) -> Value raise InvalidActivationDispatchShell {
  mutual_receiver_revalidate_registry(interp, self)
  mutual_receiver_registry_function(self, node).callee
}

///|
fn TrustedMutualReceiverRecursionRegistry::require_call(
  self : TrustedMutualReceiverRecursionRegistry,
  interp : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> MutualReceiverNode raise InvalidActivationDispatchShell {
  mutual_receiver_revalidate_registry(interp, self)
  guard mutual_receiver_value_identity(self.receiver, this_value) &&
    args.length() == 1 &&
    args[0] is Number(_) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion call escaped the sealed receiver/argument envelope",
    )
  }
  let expected_node = if loc == self.plan.root_member_loc {
    self.plan.root_node
  } else if loc == self.plan.left.recipe.recursive_call_loc {
    MutualReceiverRight
  } else if loc == self.plan.right.recipe.recursive_call_loc {
    MutualReceiverLeft
  } else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion call location escaped the sealed syntax recipe",
    )
  }
  let expected = mutual_receiver_registry_function(self, expected_node)
  guard mutual_receiver_value_identity(expected.callee, callee) else {
    invalid_activation_dispatch_shell(
      "mutual receiver recursion callee/location pairing escaped the sealed graph",
    )
  }
  expected_node
}

///|
fn TrustedMutualReceiverRecursionRegistry::require_body_statement(
  self : TrustedMutualReceiverRecursionRegistry,
  interp : Interpreter,
  index : Int,
  stmt : @ast.Stmt,
) -> MutualReceiverNode raise InvalidActivationDispatchShell {
  mutual_receiver_revalidate_registry(interp, self)
  guard index == 0 || index == 1 else {
    invalid_activation_dispatch_shell(
      "mutual receiver body statement index is outside exact admission",
    )
  }
  let left_statement = if index == 0 {
    self.left.first_body_statement
  } else {
    self.left.second_body_statement
  }
  let right_statement = if index == 0 {
    self.right.first_body_statement
  } else {
    self.right.second_body_statement
  }
  let left_matches = physical_equal(left_statement, stmt) &&
    mutual_receiver_body_statement_matches(
      self.plan,
      MutualReceiverLeft,
      index,
      stmt,
    )
  let right_matches = physical_equal(right_statement, stmt) &&
    mutual_receiver_body_statement_matches(
      self.plan,
      MutualReceiverRight,
      index,
      stmt,
    )
  match (left_matches, right_matches) {
    (true, false) => MutualReceiverLeft
    (false, true) => MutualReceiverRight
    _ =>
      invalid_activation_dispatch_shell(
        "mutual receiver body statement lost its trusted physical identity",
      )
  }
}
