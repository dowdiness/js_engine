// Closed admission for ordinary prototype-data member calls whose receiver
// changes at every activation. The AST is lowered by meaning; source text,
// identifier spellings, and fixture names are not admission inputs.

///|
const CHANGING_RECEIVER_MAX_DEPTH = 4096.0

///|
priv struct ChangingReceiverActivationPlan {
  parameter : String
  next_property : String
  method_property : String
  base_condition_loc : @token.Loc
  recursive_add_loc : @token.Loc
  next_member_loc : @token.Loc
  method_member_loc : @token.Loc
  recursive_call_loc : @token.Loc
  recursive_subtract_loc : @token.Loc
}

///|
fn ChangingReceiverActivationPlan::ChangingReceiverActivationPlan(
  parameter~ : String,
  next_property~ : String,
  method_property~ : String,
  base_condition_loc~ : @token.Loc,
  recursive_add_loc~ : @token.Loc,
  next_member_loc~ : @token.Loc,
  method_member_loc~ : @token.Loc,
  recursive_call_loc~ : @token.Loc,
  recursive_subtract_loc~ : @token.Loc,
) -> ChangingReceiverActivationPlan {
  {
    parameter,
    next_property,
    method_property,
    base_condition_loc,
    recursive_add_loc,
    next_member_loc,
    method_member_loc,
    recursive_call_loc,
    recursive_subtract_loc,
  }
}

///|
fn lower_changing_receiver_activation(
  data : FuncData,
) -> ChangingReceiverActivationPlan? {
  guard data.params.length() == 1 && data.body.length() == 2 else {
    return None
  }
  let parameter = data.params[0]
  guard numeric_recursion_identifier_is_safe(parameter) else { return None }
  let base_condition_loc = match data.body[0] {
    @ast.IfStmt(
      @ast.Binary(
        @ast.EqEqEq,
        @ast.Ident(condition_parameter, _),
        base_value,
        condition_loc
      ),
      @ast.ReturnStmt(Some(return_value), _),
      None,
      _
    ) if condition_parameter == parameter &&
      exact_numeric_recursion_number(base_value, NUMERIC_RECURSION_BASE) &&
      exact_numeric_recursion_number(return_value, NUMERIC_RECURSION_BASE) =>
      condition_loc
    _ => return None
  }
  match data.body[1] {
    @ast.ReturnStmt(
      Some(
        @ast.Binary(
          @ast.Add,
          increment,
          @ast.Call(
            @ast.Member(
              @ast.Member(@ast.ThisExpr(_), next_property, next_member_loc),
              method_property,
              method_member_loc
            ),
            [
              @ast.Binary(
                @ast.Sub,
                @ast.Ident(argument_parameter, _),
                decrement,
                recursive_subtract_loc
              ),
            ],
            recursive_call_loc
          ),
          recursive_add_loc
        )
      ),
      _
    ) if argument_parameter == parameter &&
      next_property != "__proto__" &&
      method_property != "__proto__" &&
      exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) &&
      exact_numeric_recursion_number(decrement, NUMERIC_RECURSION_STEP) =>
      Some(
        ChangingReceiverActivationPlan(
          parameter~,
          next_property~,
          method_property~,
          base_condition_loc~,
          recursive_add_loc~,
          next_member_loc~,
          method_member_loc~,
          recursive_call_loc~,
          recursive_subtract_loc~,
        ),
      )
    _ => None
  }
}

///|
fn changing_receiver_plan_matches(
  expected : ChangingReceiverActivationPlan,
  actual : ChangingReceiverActivationPlan,
) -> Bool {
  expected.parameter == actual.parameter &&
  expected.next_property == actual.next_property &&
  expected.method_property == actual.method_property &&
  expected.base_condition_loc == actual.base_condition_loc &&
  expected.recursive_add_loc == actual.recursive_add_loc &&
  expected.next_member_loc == actual.next_member_loc &&
  expected.method_member_loc == actual.method_member_loc &&
  expected.recursive_call_loc == actual.recursive_call_loc &&
  expected.recursive_subtract_loc == actual.recursive_subtract_loc
}

///|
fn changing_receiver_value_identity(expected : Value, actual : Value) -> Bool {
  match (expected, actual) {
    (Object(expected_data), Object(actual_data)) =>
      physical_equal(expected_data, actual_data)
    _ => false
  }
}

///|
fn changing_receiver_is_ordinary(value : Value) -> Bool {
  match value {
    Object(data) =>
      data.class_name == "Object" &&
      data.callable is None &&
      data.arraybuffer_state is None &&
      data.bag.symbol_properties.is_empty() &&
      data.bag.symbol_descriptors.is_empty() &&
      data.bag.internal_slots.is_empty() &&
      data.bag.host_slots.is_empty()
    _ => false
  }
}

///|
fn changing_receiver_own_data_property(
  receiver : Value,
  property : String,
) -> Value? {
  guard changing_receiver_is_ordinary(receiver) && receiver is Object(data) else {
    return None
  }
  match
    (
      ordinary_get_own_string_desc(data.bag, property),
      data.bag.properties.get(property),
    ) {
    (Some(desc), Some(value)) if !desc.is_accessor => Some(value)
    _ => None
  }
}

///|
fn changing_receiver_resolves_prototype_data_method(
  receiver : Value,
  property : String,
  expected : Value,
) -> Bool {
  guard changing_receiver_is_ordinary(receiver) && receiver is Object(data) else {
    return false
  }
  guard ordinary_get_own_string_desc(data.bag, property) is None else {
    return false
  }
  let seen : Array[ObjectData] = []
  let mut current = data.prototype
  for _ in 0..<1024 {
    match current {
      Null => return false
      Object(prototype) => {
        guard prototype.class_name == "Object" &&
          prototype.callable is None &&
          prototype.arraybuffer_state is None else {
          return false
        }
        for prior in seen {
          guard !physical_equal(prior, prototype) else { return false }
        }
        seen.push(prototype)
        match
          (
            ordinary_get_own_string_desc(prototype.bag, property),
            prototype.bag.properties.get(property),
          ) {
          (Some(desc), Some(value)) if !desc.is_accessor =>
            return changing_receiver_value_identity(expected, value)
          (None, None) => current = prototype.prototype
          _ => return false
        }
      }
      _ => return false
    }
  }
  false
}

///|
priv struct ChangingReceiverFunctionSnapshot {
  plan : ChangingReceiverActivationPlan
  callee : Value
  name : String?
  params : Array[String]
  body : Array[@ast.Stmt]
  closure : Environment
  strict : Bool
  has_name_binding : Bool
  is_method : Bool
  source_text : String?
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
priv struct ChangingReceiverCallPreflight {
  function : ChangingReceiverFunctionSnapshot
  receivers : Array[Value]
  initial_depth : Int
  root_call_loc : @token.Loc
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
}

///|
priv struct TrustedChangingReceiverRegistry {
  function : ChangingReceiverFunctionSnapshot
  receivers : Array[Value]
  initial_depth : Int
  root_call_loc : @token.Loc
  throw_type_error : Value?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
}

///|
fn changing_receiver_depth(args : Array[Value]) -> Int? {
  guard args.length() == 1 && args[0] is Number(value) else { return None }
  guard value >= 0.0 &&
    value <= CHANGING_RECEIVER_MAX_DEPTH &&
    value == value.floor() else {
    return None
  }
  Some(value.to_int())
}

///|
fn Interpreter::snapshot_changing_receiver_function(
  self : Interpreter,
  callee : Value,
) -> ChangingReceiverFunctionSnapshot? {
  ignore(self)
  guard callee is Object(object) &&
    object.class_name == "Function" &&
    object.callable is Some(UserFunc(data)) &&
    lower_changing_receiver_activation(data) is Some(plan) else {
    return None
  }
  let expected_realm_protos = callee_realm_protos(callee)
  let expected_source_identity = function_source_identity(callee)
  guard numeric_recursion_realm_protos_match(
      expected_realm_protos,
      callee_realm_protos(callee),
    ) &&
    function_source_identity(callee) == expected_source_identity else {
    return None
  }
  Some({
    plan,
    callee,
    name: data.name,
    params: data.params,
    body: data.body,
    closure: data.closure,
    strict: data.strict,
    has_name_binding: data.has_name_binding,
    is_method: data.is_method,
    source_text: data.source_text,
    expected_realm_protos,
    expected_source_identity,
  })
}

///|
fn Interpreter::changing_receiver_function_matches(
  self : Interpreter,
  snapshot : ChangingReceiverFunctionSnapshot,
) -> Bool {
  guard snapshot.callee is Object(expected) &&
    snapshot.callee is Object(actual) &&
    physical_equal(expected, actual) &&
    actual.class_name == "Function" &&
    actual.callable is Some(UserFunc(data)) &&
    lower_changing_receiver_activation(data) is Some(plan) else {
    return false
  }
  changing_receiver_plan_matches(snapshot.plan, plan) &&
  data.name == snapshot.name &&
  physical_equal(data.params, snapshot.params) &&
  physical_equal(data.body, snapshot.body) &&
  physical_equal(data.closure, snapshot.closure) &&
  data.strict == snapshot.strict &&
  data.has_name_binding == snapshot.has_name_binding &&
  data.is_method == snapshot.is_method &&
  data.source_text == snapshot.source_text &&
  numeric_recursion_realm_protos_match(
    snapshot.expected_realm_protos,
    callee_realm_protos(snapshot.callee),
  ) &&
  function_source_identity(snapshot.callee) == snapshot.expected_source_identity &&
  self.global.parent is None
}

///|
fn changing_receiver_chain(
  initial_receiver : Value,
  callee : Value,
  plan : ChangingReceiverActivationPlan,
  depth : Int,
) -> Array[Value]? {
  guard changing_receiver_resolves_prototype_data_method(
    initial_receiver,
    plan.method_property,
    callee,
  ) else {
    return None
  }
  let receivers = [initial_receiver]
  let mut current = initial_receiver
  for _ in 0..<depth {
    let next = match
      changing_receiver_own_data_property(current, plan.next_property) {
      Some(value) => value
      None => return None
    }
    guard changing_receiver_resolves_prototype_data_method(
      next,
      plan.method_property,
      callee,
    ) else {
      return None
    }
    receivers.push(next)
    current = next
  }
  Some(receivers)
}

///|
fn Interpreter::preflight_changing_receiver_call(
  self : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
  root_call_loc : @token.Loc,
) -> ChangingReceiverCallPreflight? {
  guard changing_receiver_depth(args) is Some(initial_depth) &&
    self.snapshot_changing_receiver_function(callee) is Some(function) &&
    self.numeric_recursion_canonical_global_object()
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
  guard changing_receiver_chain(
      this_value,
      callee,
      function.plan,
      initial_depth,
    )
    is Some(receivers) else {
    return None
  }
  Some({
    function,
    receivers,
    initial_depth,
    root_call_loc,
    throw_type_error_snapshot,
    expected_global_object,
  })
}

///|
fn changing_receiver_preflights_match(
  expected : ChangingReceiverCallPreflight,
  actual : ChangingReceiverCallPreflight,
) -> Bool {
  guard expected.initial_depth == actual.initial_depth &&
    expected.root_call_loc == actual.root_call_loc &&
    changing_receiver_plan_matches(expected.function.plan, actual.function.plan) &&
    changing_receiver_value_identity(
      expected.function.callee,
      actual.function.callee,
    ) &&
    expected.receivers.length() == actual.receivers.length() else {
    return false
  }
  for index, receiver in expected.receivers {
    guard changing_receiver_value_identity(receiver, actual.receivers[index]) else {
      return false
    }
  }
  true
}

///|
fn Interpreter::seal_changing_receiver_registry(
  self : Interpreter,
  preflight : ChangingReceiverCallPreflight,
  callee : Value,
  this_value : Value,
  args : Array[Value],
  root_call_loc : @token.Loc,
) -> TrustedChangingReceiverRegistry raise InvalidActivationDispatchShell {
  guard self.preflight_changing_receiver_call(
      callee, this_value, args, root_call_loc,
    )
    is Some(actual) &&
    changing_receiver_preflights_match(preflight, actual) &&
    self.changing_receiver_function_matches(preflight.function) &&
    self.numeric_recursion_canonical_global_object() is Some(global_object) &&
    physical_equal(global_object, preflight.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "changing-receiver call provenance changed before sealing",
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
      "changing-receiver ThrowTypeError binding changed before sealing",
    )
  }
  {
    function: preflight.function,
    receivers: preflight.receivers.copy(),
    initial_depth: preflight.initial_depth,
    root_call_loc: preflight.root_call_loc,
    throw_type_error: numeric_recursion_throw_type_error_value(
      throw_type_error_snapshot,
    ),
    throw_type_error_snapshot,
    expected_global_object: preflight.expected_global_object,
  }
}

///|
fn TrustedChangingReceiverRegistry::receiver_index(
  self : TrustedChangingReceiverRegistry,
  args : Array[Value],
) -> Int raise InvalidActivationDispatchShell {
  let depth = match changing_receiver_depth(args) {
    Some(value) => value
    None =>
      invalid_activation_dispatch_shell(
        "changing-receiver call argument escaped the admitted depth domain",
      )
  }
  guard depth <= self.initial_depth else {
    invalid_activation_dispatch_shell(
      "changing-receiver call depth exceeded the admitted root",
    )
  }
  self.initial_depth - depth
}

///|
fn TrustedChangingReceiverRegistry::require_call(
  self : TrustedChangingReceiverRegistry,
  interp : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
) -> Int raise InvalidActivationDispatchShell {
  let throw_type_error_snapshot = numeric_recursion_callback_free_throw_type_error(
    interp.global,
  )
  guard interp.numeric_recursion_canonical_global_object()
    is Some(global_object) &&
    physical_equal(global_object, self.expected_global_object) &&
    numeric_recursion_callback_free_binding_snapshots_match(
      self.throw_type_error_snapshot,
      throw_type_error_snapshot,
    ) &&
    interp.changing_receiver_function_matches(self.function) &&
    changing_receiver_value_identity(self.function.callee, callee) else {
    invalid_activation_dispatch_shell(
      "changing-receiver callable escaped sealed provenance",
    )
  }
  let index = self.receiver_index(args)
  guard index < self.receivers.length() &&
    changing_receiver_value_identity(self.receivers[index], this_value) else {
    invalid_activation_dispatch_shell(
      "changing-receiver activation lost receiver/depth correspondence",
    )
  }
  index
}

///|
fn TrustedChangingReceiverRegistry::next_receiver(
  self : TrustedChangingReceiverRegistry,
  interp : Interpreter,
  current : Value,
  args : Array[Value],
) -> Value raise InvalidActivationDispatchShell {
  let index = self.require_call(interp, self.function.callee, current, args)
  guard index + 1 < self.receivers.length() else {
    invalid_activation_dispatch_shell(
      "changing-receiver activation requested a successor past its base case",
    )
  }
  let next = self.receivers[index + 1]
  guard changing_receiver_own_data_property(
      current,
      self.function.plan.next_property,
    )
    is Some(actual_next) &&
    changing_receiver_value_identity(next, actual_next) &&
    changing_receiver_resolves_prototype_data_method(
      next,
      self.function.plan.method_property,
      self.function.callee,
    ) else {
    invalid_activation_dispatch_shell(
      "changing-receiver object graph changed after admission",
    )
  }
  next
}
