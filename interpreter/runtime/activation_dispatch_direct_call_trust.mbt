// Runtime provenance sealing for the exact public numeric call root. All
// reads are direct environment/object storage reads; no identifier lookup or
// guest callback is performed before admission has completed.

///|
priv struct DirectNumericRecursionFunctionSnapshot {
  syntax : NumericRecursionFunctionSyntax
  callee : Value
  params : Array[String]
  body : Array[@ast.Stmt]
  source_text : String?
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
fn DirectNumericRecursionFunctionSnapshot::DirectNumericRecursionFunctionSnapshot(
  syntax~ : NumericRecursionFunctionSyntax,
  callee~ : Value,
  params~ : Array[String],
  body~ : Array[@ast.Stmt],
  source_text~ : String?,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> DirectNumericRecursionFunctionSnapshot {
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
priv struct DirectNumericRecursionPreflight {
  plan : DirectNumericRecursionCallPlan
  entry : DirectNumericRecursionFunctionSnapshot
  peer : DirectNumericRecursionFunctionSnapshot?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
}

///|
fn DirectNumericRecursionPreflight::DirectNumericRecursionPreflight(
  plan~ : DirectNumericRecursionCallPlan,
  entry~ : DirectNumericRecursionFunctionSnapshot,
  peer~ : DirectNumericRecursionFunctionSnapshot?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
) -> DirectNumericRecursionPreflight {
  { plan, entry, peer, throw_type_error_snapshot, expected_global_object }
}

///|
fn direct_numeric_recursion_recipe_matches(
  expected : NumericRecursionExpressionRecipe,
  actual : NumericRecursionExpressionRecipe,
) -> Bool {
  expected.base_condition_loc == actual.base_condition_loc &&
  expected.recursive_add_loc == actual.recursive_add_loc &&
  expected.recursive_call_loc == actual.recursive_call_loc &&
  expected.recursive_subtract_loc == actual.recursive_subtract_loc
}

///|
fn direct_numeric_recursion_syntax_matches(
  expected : NumericRecursionFunctionSyntax,
  actual : NumericRecursionFunctionSyntax,
) -> Bool {
  expected.name == actual.name &&
  expected.parameter == actual.parameter &&
  expected.recursive_callee == actual.recursive_callee &&
  direct_numeric_recursion_recipe_matches(
    expected.expression_recipe,
    actual.expression_recipe,
  )
}

///|
fn direct_numeric_recursion_cycles_match(
  expected : DirectNumericRecursionCycle,
  actual : DirectNumericRecursionCycle,
) -> Bool {
  match (expected, actual) {
    (DirectNumericSelf, DirectNumericSelf) => true
    (
      DirectNumericMutualPeer(expected_name),
      DirectNumericMutualPeer(actual_name),
    ) => expected_name == actual_name
    _ => false
  }
}

///|
fn direct_numeric_recursion_plans_match(
  expected : DirectNumericRecursionCallPlan,
  actual : DirectNumericRecursionCallPlan,
) -> Bool {
  direct_numeric_recursion_syntax_matches(expected.entry, actual.entry) &&
  direct_numeric_recursion_cycles_match(expected.cycle, actual.cycle) &&
  expected.initial_argument == actual.initial_argument &&
  expected.root_call_loc == actual.root_call_loc
}

///|
fn direct_numeric_recursion_global_property_is_canonical(
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
fn Interpreter::snapshot_direct_numeric_recursion_function(
  self : Interpreter,
  syntax : NumericRecursionFunctionSyntax,
  candidate : Value,
  expected_global_object : ObjectData,
  expected_realm_protos : FunctionRealmProtos,
  expected_source_identity : String?,
) -> DirectNumericRecursionFunctionSnapshot? {
  guard self.numeric_recursion_canonical_global_object() is Some(global_object) &&
    physical_equal(global_object, expected_global_object) else {
    return None
  }
  guard candidate is Object(actual) &&
    actual.class_name == "Function" &&
    self.global.bindings.get(syntax.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding &&
    binding.value is Object(bound) &&
    physical_equal(bound, actual) else {
    return None
  }
  guard global_object.bag.properties.get(syntax.name) is Some(Object(mirrored)) &&
    physical_equal(mirrored, actual) &&
    direct_numeric_recursion_global_property_is_canonical(
      global_object,
      syntax.name,
    ) else {
    return None
  }
  guard actual.callable is Some(UserFunc(data)) &&
    numeric_recursion_user_func_matches_syntax(self, syntax, data) else {
    return None
  }
  guard function_source_identity(candidate) == expected_source_identity &&
    numeric_recursion_realm_protos_match(
      expected_realm_protos,
      callee_realm_protos(candidate),
    ) else {
    return None
  }
  Some(
    DirectNumericRecursionFunctionSnapshot(
      syntax~,
      callee=candidate,
      params=data.params,
      body=data.body,
      source_text=data.source_text,
      expected_realm_protos~,
      expected_source_identity~,
    ),
  )
}

///|
fn direct_numeric_recursion_global_candidate(
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
#warnings("-unused_value")
fn Interpreter::preflight_direct_numeric_recursion_call(
  self : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
  root_call_loc : @token.Loc,
) -> DirectNumericRecursionPreflight? {
  guard classify_direct_numeric_recursion_call(
      callee, this_value, args, root_call_loc,
    )
    is Some(plan) else {
    return None
  }
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) else {
    return None
  }
  let throw_type_error_snapshot = numeric_recursion_callback_free_throw_type_error(
    self.global,
  )
  match throw_type_error_snapshot {
    CallbackFreeBindingUnsafe => return None
    _ => ()
  }
  let expected_realm_protos = function_realm_protos_from_realm_state(
    self.realm_state,
  )
  let expected_source_identity = self.realm_state.active_source_identity.val
  guard self.snapshot_direct_numeric_recursion_function(
      plan.entry,
      callee,
      expected_global_object,
      expected_realm_protos,
      expected_source_identity,
    )
    is Some(entry) else {
    return None
  }
  let peer = match plan.cycle {
    DirectNumericSelf => None
    DirectNumericMutualPeer(peer_name) => {
      guard peer_name != plan.entry.name &&
        plan.entry.parameter != peer_name &&
        direct_numeric_recursion_global_candidate(self, peer_name)
        is Some(peer_candidate) &&
        peer_candidate is Object(peer_object) &&
        peer_object.callable is Some(UserFunc(peer_data)) &&
        classify_direct_numeric_recursion_user_func(peer_data)
        is Some((peer_syntax, peer_cycle)) else {
        return None
      }
      guard peer_syntax.name == peer_name &&
        peer_syntax.parameter != plan.entry.name &&
        peer_syntax.recursive_callee == plan.entry.name &&
        peer_cycle is DirectNumericMutualPeer(reverse_name) &&
        reverse_name == plan.entry.name else {
        return None
      }
      guard self.snapshot_direct_numeric_recursion_function(
          peer_syntax, peer_candidate, expected_global_object, expected_realm_protos,
          expected_source_identity,
        )
        is Some(peer_snapshot) else {
        return None
      }
      guard peer_candidate is Object(peer_identity) &&
        callee is Object(entry_identity) &&
        !physical_equal(peer_identity, entry_identity) else {
        return None
      }
      Some(peer_snapshot)
    }
  }
  Some(
    DirectNumericRecursionPreflight(
      plan~,
      entry~,
      peer~,
      throw_type_error_snapshot~,
      expected_global_object~,
    ),
  )
}

///|
fn Interpreter::seal_direct_numeric_recursion_function(
  self : Interpreter,
  snapshot : DirectNumericRecursionFunctionSnapshot,
  expected_global_object : ObjectData,
) -> TrustedNumericRecursionFunction raise InvalidActivationDispatchShell {
  let actual = match
    self.snapshot_direct_numeric_recursion_function(
      snapshot.syntax,
      snapshot.callee,
      expected_global_object,
      snapshot.expected_realm_protos,
      snapshot.expected_source_identity,
    ) {
    Some(found) => found
    None =>
      invalid_activation_dispatch_shell(
        "direct numeric recursion function provenance changed before sealing",
      )
  }
  guard physical_equal(snapshot.params, actual.params) &&
    physical_equal(snapshot.body, actual.body) &&
    snapshot.source_text == actual.source_text &&
    direct_numeric_recursion_syntax_matches(snapshot.syntax, actual.syntax) else {
    invalid_activation_dispatch_shell(
      "direct numeric recursion function recipe changed before sealing",
    )
  }
  TrustedNumericRecursionFunction(
    syntax=actual.syntax,
    callee=actual.callee,
    params=actual.params,
    body=actual.body,
    source_text=actual.source_text,
    expected_realm_protos=actual.expected_realm_protos,
    expected_source_identity=actual.expected_source_identity,
  )
}

///|
#warnings("-unused_value")
fn Interpreter::seal_direct_numeric_recursion_registry(
  self : Interpreter,
  preflight : DirectNumericRecursionPreflight,
  callee : Value,
  this_value : Value,
  args : Array[Value],
  root_call_loc : @token.Loc,
) -> TrustedNumericRecursionRegistry raise InvalidActivationDispatchShell {
  guard self.numeric_recursion_canonical_global_object() is Some(global_object) &&
    physical_equal(global_object, preflight.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "direct numeric recursion global changed before sealing",
    )
  }
  guard classify_direct_numeric_recursion_call(
      callee, this_value, args, root_call_loc,
    )
    is Some(sealed_plan) &&
    direct_numeric_recursion_plans_match(preflight.plan, sealed_plan) else {
    invalid_activation_dispatch_shell(
      "direct numeric recursion call no longer matches exact admission",
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
      "direct numeric recursion ThrowTypeError binding changed before sealing",
    )
  }
  let entry = self.seal_direct_numeric_recursion_function(
    preflight.entry,
    preflight.expected_global_object,
  )
  let peer = match preflight.peer {
    Some(snapshot) =>
      Some(
        self.seal_direct_numeric_recursion_function(
          snapshot,
          preflight.expected_global_object,
        ),
      )
    None => None
  }
  TrustedNumericRecursionRegistry(
    entry~,
    peer~,
    throw_type_error=numeric_recursion_throw_type_error_value(
      throw_type_error_snapshot,
    ),
    throw_type_error_snapshot~,
    expected_global_object=preflight.expected_global_object,
  )
}
