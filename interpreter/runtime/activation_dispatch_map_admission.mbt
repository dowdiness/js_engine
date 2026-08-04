// Closed, effect-free admission for the exact ordinary Array.map callback
// recursion recipe. Runtime identities are sealed after root declarations run.

///|
#warnings("-unused_field")
priv struct ArrayMapRecursionPlan {
  function_name : String
  parameter_name : String
  items_name : String
  callback_parameter : String
  map_property_name : String
  member_property_name : String
  initial_count : Double
  root_call_loc : @token.Loc
  base_condition_loc : @token.Loc
  map_call_loc : @token.Loc
  callback_call_loc : @token.Loc
  member_call_loc : @token.Loc
  recursive_call_loc : @token.Loc
  recursive_subtract_loc : @token.Loc
  recursive_add_loc : @token.Loc
  result_member_loc : @token.Loc
}

///|
#warnings("-unused_value")
fn ArrayMapRecursionPlan::ArrayMapRecursionPlan(
  function_name~ : String,
  parameter_name~ : String,
  items_name~ : String,
  callback_parameter~ : String,
  map_property_name~ : String,
  member_property_name~ : String,
  initial_count~ : Double,
  root_call_loc~ : @token.Loc,
  base_condition_loc~ : @token.Loc,
  map_call_loc~ : @token.Loc,
  callback_call_loc~ : @token.Loc,
  member_call_loc~ : @token.Loc,
  recursive_call_loc~ : @token.Loc,
  recursive_subtract_loc~ : @token.Loc,
  recursive_add_loc~ : @token.Loc,
  result_member_loc~ : @token.Loc,
) -> ArrayMapRecursionPlan {
  {
    function_name,
    parameter_name,
    items_name,
    callback_parameter,
    map_property_name,
    member_property_name,
    initial_count,
    root_call_loc,
    base_condition_loc,
    map_call_loc,
    callback_call_loc,
    member_call_loc,
    recursive_call_loc,
    recursive_subtract_loc,
    recursive_add_loc,
    result_member_loc,
  }
}

///|
fn array_map_identifier_is_safe(name : String) -> Bool {
  name != "eval" && name != "arguments" && name != "undefined"
}

///|
fn array_map_number(expr : @ast.Expr, expected : Double) -> Bool {
  exact_numeric_recursion_number(expr, expected)
}

///|
fn array_map_static_string(expr : @ast.Expr, expected : String) -> Bool {
  match expr {
    @ast.Ident(value, _) => value == expected
    @ast.StringLit(value, false, @token.LexForm::LexNormal, _) =>
      value == expected
    _ => false
  }
}

///|
fn classify_array_map_callback(
  expr : @ast.Expr,
  member_property_name : String,
) -> (String, @token.Loc, @token.Loc)? {
  match expr {
    @ast.FuncExpr(
      None,
      [callback_parameter],
      [
        @ast.ReturnStmt(
          Some(
            @ast.Call(
              @ast.Member(
                @ast.Ident(actual_parameter, _),
                actual_property,
                member_call_loc
              ),
              [],
              callback_call_loc
            )
          ),
          _
        ),
      ],
      _,
      _
    ) if array_map_identifier_is_safe(callback_parameter) &&
      actual_parameter == callback_parameter &&
      actual_property == member_property_name =>
      Some((callback_parameter, callback_call_loc, member_call_loc))
    _ => None
  }
}

///|
fn classify_array_map_next_function(
  expr : @ast.Expr,
  function_name : String,
  parameter_name : String,
) -> (@token.Loc, @token.Loc, @token.Loc)? {
  match expr {
    @ast.FuncExpr(
      None,
      [],
      [
        @ast.ReturnStmt(
          Some(
            @ast.Call(
              @ast.Ident(actual_name, _),
              [
                @ast.Binary(
                  @ast.Sub,
                  @ast.Ident(actual_parameter, _),
                  decrement,
                  subtract_loc
                ),
              ],
              recursive_call_loc
            )
          ),
          _
        ),
      ],
      _,
      _
    ) if actual_name == function_name &&
      actual_parameter == parameter_name &&
      array_map_number(decrement, 1.0) =>
      Some((subtract_loc, recursive_call_loc, recursive_call_loc))
    _ => None
  }
}

///|
fn classify_array_map_items(
  stmt : @ast.Stmt,
  function_name : String,
  parameter_name : String,
  items_name : String,
  member_property_name : String,
) -> (@token.Loc, @token.Loc, @token.Loc)? {
  match stmt {
    @ast.VarDecl(
      @ast.VarKind::VarKind,
      actual_items_name,
      Some(@ast.ArrayLit([@ast.ObjectLit([property], _)], _)),
      _
    ) if actual_items_name == items_name &&
      property.kind == @ast.PropKind::Init &&
      !property.computed &&
      !property.is_method &&
      array_map_static_string(property.key, member_property_name) =>
      classify_array_map_next_function(
        property.value,
        function_name,
        parameter_name,
      )
    _ => None
  }
}

///|
fn classify_array_map_body(
  body : Array[@ast.Stmt],
  function_name : String,
  parameter_name : String,
  items_name : String,
  member_property_name : String,
) -> (
  @token.Loc,
  @token.Loc,
  @token.Loc,
  @token.Loc,
  @token.Loc,
  @token.Loc,
  @token.Loc,
  @token.Loc,
  String,
  @token.Loc,
  @token.Loc,
)? {
  guard body.length() == 3 else { return None }
  let base_condition_loc = match body[0] {
    @ast.IfStmt(
      @ast.Binary(
        @ast.EqEqEq,
        @ast.Ident(actual_parameter, _),
        base,
        condition_loc
      ),
      @ast.ReturnStmt(Some(base_result), _),
      None,
      _
    ) if actual_parameter == parameter_name &&
      array_map_number(base, 0.0) &&
      array_map_number(base_result, 0.0) => condition_loc
    _ => return None
  }
  let (subtract_loc, recursive_call_loc, next_recursive_call_loc) = match
    classify_array_map_items(
      body[1],
      function_name,
      parameter_name,
      items_name,
      member_property_name,
    ) {
    Some(found) => found
    None => return None
  }
  let (
    recursive_add_loc,
    map_call_loc,
    callback_parameter,
    callback_call_loc,
    member_call_loc,
    result_member_loc,
  ) = match body[2] {
    @ast.ReturnStmt(
      Some(
        @ast.Binary(
          @ast.Add,
          increment,
          @ast.ComputedMember(
            @ast.Call(
              @ast.Member(
                @ast.Ident(actual_items_name, _),
                map_property_name,
                map_loc
              ),
              [callback],
              _
            ),
            @ast.NumberLit(result_index, _, _),
            result_loc
          ),
          add_loc
        )
      ),
      _
    ) if actual_items_name == items_name &&
      map_property_name == "map" &&
      result_index == 0 &&
      array_map_number(increment, 1.0) =>
      match classify_array_map_callback(callback, member_property_name) {
        Some((parameter, callback_loc, member_loc)) =>
          (add_loc, map_loc, parameter, callback_loc, member_loc, result_loc)
        None => return None
      }
    _ => return None
  }
  Some(
    (
      base_condition_loc, subtract_loc, next_recursive_call_loc, recursive_add_loc,
      map_call_loc, callback_call_loc, member_call_loc, result_member_loc, callback_parameter,
      recursive_call_loc, subtract_loc,
    ),
  )
}

///|
#warnings("-unused_value")
fn classify_array_map_recursion_program(
  stmts : Array[@ast.Stmt],
) -> ArrayMapRecursionPlan? {
  guard stmts.length() == 2 else { return None }
  let (function_name, parameter_name, body) = match stmts[0] {
    @ast.FuncDecl(name, [parameter], body, _, _) if array_map_identifier_is_safe(
        name,
      ) &&
      array_map_identifier_is_safe(parameter) => (name, parameter, body)
    _ => return None
  }
  let (root_call_loc, initial_count) = match stmts[1] {
    @ast.ExprStmt(@ast.Call(@ast.Ident(actual_name, _), [initial], call_loc), _) if actual_name ==
      function_name &&
      array_map_number(initial, 256.0) => (call_loc, 256.0)
    _ => return None
  }
  let items_name = "items"
  let member_property_name = "next"
  match
    classify_array_map_body(
      body, function_name, parameter_name, items_name, member_property_name,
    ) {
    Some(
      (
        base_condition_loc,
        subtract_loc,
        recursive_call_loc,
        recursive_add_loc,
        map_call_loc,
        callback_call_loc,
        member_call_loc,
        result_member_loc,
        callback_parameter,
        _,
        _,
      )
    ) =>
      Some(
        ArrayMapRecursionPlan(
          function_name~,
          parameter_name~,
          items_name~,
          callback_parameter~,
          map_property_name="map",
          member_property_name~,
          initial_count~,
          root_call_loc~,
          base_condition_loc~,
          map_call_loc~,
          callback_call_loc~,
          member_call_loc~,
          recursive_call_loc~,
          recursive_subtract_loc=subtract_loc,
          recursive_add_loc~,
          result_member_loc~,
        ),
      )
    None => None
  }
}

///|
fn array_map_plan_is_dispatchable(plan : ArrayMapRecursionPlan) -> Bool {
  plan.initial_count == 256.0 &&
  plan.map_property_name == "map" &&
  plan.member_property_name == "next"
}

///|
priv struct ArrayMapRecursionPreflight {
  plan : ArrayMapRecursionPlan
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
  expected_array_prototype : Value
  expected_array_constructor : Value
  expected_map_method : Value
  expected_map_method_descriptor : ArrayMapDescriptorShape
  expected_species : ArrayMapSpeciesSnapshot
  expected_source_identity : String?
}

///|
// ArraySpeciesCreate observes this exact callback-free path for an ordinary
// Array receiver: the prototype's data constructor and the Array constructor's
// canonical MethodCallable species getter.  Keep the observed values and
// descriptor shapes so later map entries can reject any drift without invoking
// guest code during admission or validation.
priv struct ArrayMapSpeciesSnapshot {
  receiver_constructor : Value
  receiver_constructor_descriptor : ArrayMapDescriptorShape
  species_value : Value
  species_getter : Value
  species_descriptor : ArrayMapDescriptorShape
}

///|
priv struct ArrayMapDescriptorShape {
  writable : Bool
  enumerable : Bool
  configurable : Bool
  is_accessor : Bool
  has_getter : Bool
  has_setter : Bool
}

///|
#warnings("-unused_value")
fn ArrayMapRecursionPreflight::ArrayMapRecursionPreflight(
  plan~ : ArrayMapRecursionPlan,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
  expected_array_prototype~ : Value,
  expected_array_constructor~ : Value,
  expected_map_method~ : Value,
  expected_map_method_descriptor~ : ArrayMapDescriptorShape,
  expected_species~ : ArrayMapSpeciesSnapshot,
  expected_source_identity~ : String?,
) -> ArrayMapRecursionPreflight {
  {
    plan,
    throw_type_error_snapshot,
    expected_global_object,
    expected_array_prototype,
    expected_array_constructor,
    expected_map_method,
    expected_map_method_descriptor,
    expected_species,
    expected_source_identity,
  }
}

///|
fn array_map_method_descriptor_is_canonical(desc : PropDescriptor) -> Bool {
  !desc.is_accessor &&
  desc.writable &&
  !desc.enumerable &&
  desc.configurable &&
  desc.getter is None &&
  desc.setter is None
}

///|
fn array_map_method_callable_is_canonical(value : Value) -> Bool {
  match value {
    Object(data) =>
      match data.callable {
        Some(InterpreterCallable(name, _)) => name == "map"
        _ => false
      }
    _ => false
  }
}

///|
fn array_map_intrinsic_values(
  interp : Interpreter,
) -> (Value, Value, Value, ArrayMapDescriptorShape)? {
  let array_constructor = match interp.global.bindings.get("Array") {
    Some(binding) if binding.initialized => binding.value
    _ => return None
  }
  let array_prototype = interp.realm_state.get_array_proto()
  guard array_prototype is Object(proto_data) else { return None }
  guard proto_data.class_name == "Array" && proto_data.callable is None else {
    return None
  }
  let map_method = match proto_data.bag.properties.get("map") {
    Some(value) => value
    None => return None
  }
  guard array_map_method_callable_is_canonical(map_method) else { return None }
  let map_descriptor = match proto_data.bag.descriptors.get("map") {
    Some(desc) if array_map_method_descriptor_is_canonical(desc) => desc
    _ => return None
  }
  Some(
    (
      array_constructor,
      array_prototype,
      map_method,
      array_map_descriptor_shape(map_descriptor),
    ),
  )
}

///|
fn array_map_species_getter_is_canonical(getter : Value) -> Bool {
  match getter {
    Object(data) =>
      match data.callable {
        Some(MethodCallable(name, _)) => name == "get [Symbol.species]"
        _ => false
      }
    _ => false
  }
}

///|
fn array_map_species_data_descriptor_is_canonical(
  desc : PropDescriptor,
) -> Bool {
  !desc.is_accessor &&
  desc.writable &&
  !desc.enumerable &&
  desc.configurable &&
  desc.getter is None &&
  desc.setter is None
}

///|
fn array_map_species_accessor_descriptor_is_canonical(
  desc : PropDescriptor,
) -> Bool {
  desc.is_accessor &&
  !desc.writable &&
  !desc.enumerable &&
  desc.configurable &&
  desc.setter is None &&
  desc.getter is Some(_)
}

///|
fn array_map_descriptor_shape(desc : PropDescriptor) -> ArrayMapDescriptorShape {
  {
    writable: desc.writable,
    enumerable: desc.enumerable,
    configurable: desc.configurable,
    is_accessor: desc.is_accessor,
    has_getter: desc.getter is Some(_),
    has_setter: desc.setter is Some(_),
  }
}

///|
fn array_map_species_snapshot(
  interp : Interpreter,
  array_prototype : Value,
  array_constructor : Value,
) -> ArrayMapSpeciesSnapshot? {
  let (receiver_constructor, receiver_constructor_descriptor) = match
    array_prototype {
    Object(proto_data) =>
      match
        (
          proto_data.bag.properties.get("constructor"),
          proto_data.bag.descriptors.get("constructor"),
        ) {
        (Some(value), Some(desc)) if array_map_species_data_descriptor_is_canonical(
            desc,
          ) &&
          array_map_value_identity_matches(value, array_constructor) =>
          (value, desc)
        _ => return None
      }
    _ => return None
  }
  let species_sym = interp.realm_state.well_known_symbols.species
  match array_constructor {
    Object(ctor_data) =>
      match
        (
          ctor_data.bag.symbol_properties.get(species_sym.id),
          ctor_data.bag.symbol_descriptors.get(species_sym.id),
        ) {
        (Some(species_value), Some(species_descriptor)) if species_value
          is Undefined &&
          array_map_species_accessor_descriptor_is_canonical(species_descriptor) =>
          match species_descriptor.getter {
            Some(species_getter) if array_map_species_getter_is_canonical(
                species_getter,
              ) =>
              Some({
                receiver_constructor,
                receiver_constructor_descriptor: array_map_descriptor_shape(
                  receiver_constructor_descriptor,
                ),
                species_value,
                species_getter,
                species_descriptor: array_map_descriptor_shape(
                  species_descriptor,
                ),
              })
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn array_map_species_descriptor_shape_matches(
  expected : ArrayMapDescriptorShape,
  actual : ArrayMapDescriptorShape,
) -> Bool {
  expected.writable == actual.writable &&
  expected.enumerable == actual.enumerable &&
  expected.configurable == actual.configurable &&
  expected.is_accessor == actual.is_accessor &&
  expected.has_getter == actual.has_getter &&
  expected.has_setter == actual.has_setter
}

///|
fn array_map_species_snapshot_matches(
  expected : ArrayMapSpeciesSnapshot,
  actual : ArrayMapSpeciesSnapshot,
) -> Bool {
  array_map_value_identity_matches(
    expected.receiver_constructor,
    actual.receiver_constructor,
  ) &&
  array_map_species_descriptor_shape_matches(
    expected.receiver_constructor_descriptor,
    actual.receiver_constructor_descriptor,
  ) &&
  same_value(expected.species_value, actual.species_value) &&
  array_map_value_identity_matches(
    expected.species_getter,
    actual.species_getter,
  ) &&
  array_map_species_descriptor_shape_matches(
    expected.species_descriptor,
    actual.species_descriptor,
  )
}

///|
fn array_map_existing_step_binding_is_compatible(
  interp : Interpreter,
  plan : ArrayMapRecursionPlan,
) -> Bool {
  match interp.global.bindings.get(plan.function_name) {
    None => true
    Some(binding) if binding.initialized =>
      match binding.value {
        Object(data) =>
          match data.callable {
            Some(UserFunc(func)) =>
              func.name == Some(plan.function_name) &&
              func.params.length() == 1 &&
              func.params[0] == plan.parameter_name &&
              !func.strict &&
              !func.has_name_binding &&
              !func.is_method &&
              physical_equal(func.closure, interp.global) &&
              classify_array_map_body(
                func.body,
                plan.function_name,
                plan.parameter_name,
                plan.items_name,
                plan.member_property_name,
              )
              is Some(_)
            _ => false
          }
        _ => false
      }
    Some(_) => false
  }
}

///|
#warnings("-unused_value")
fn Interpreter::preflight_array_map_recursion_program(
  self : Interpreter,
  plan : ArrayMapRecursionPlan,
) -> ArrayMapRecursionPreflight? {
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) else {
    return None
  }
  guard array_map_existing_step_binding_is_compatible(self, plan) else {
    return None
  }
  let (array_constructor, array_prototype, map_method, map_method_descriptor) = match
    array_map_intrinsic_values(self) {
    Some(values) => values
    None => return None
  }
  let expected_species = match
    array_map_species_snapshot(self, array_prototype, array_constructor) {
    Some(snapshot) => snapshot
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
    ArrayMapRecursionPreflight(
      plan~,
      throw_type_error_snapshot~,
      expected_global_object~,
      expected_array_prototype=array_prototype,
      expected_array_constructor=array_constructor,
      expected_map_method=map_method,
      expected_map_method_descriptor=map_method_descriptor,
      expected_species~,
      expected_source_identity=self.realm_state.active_source_identity.val,
    ),
  )
}

///|
#warnings("-unused_value")
fn Interpreter::preflight_dispatchable_array_map_recursion_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> ArrayMapRecursionPreflight? {
  match classify_array_map_recursion_program(stmts) {
    Some(plan) if array_map_plan_is_dispatchable(plan) =>
      self.preflight_array_map_recursion_program(plan)
    Some(_) | None => None
  }
}

///|
priv struct TrustedArrayMapRecursionRegistry {
  plan : ArrayMapRecursionPlan
  step_function : Value
  expected_global_object : ObjectData
  expected_array_prototype : Value
  expected_array_constructor : Value
  expected_map_method : Value
  expected_map_method_descriptor : ArrayMapDescriptorShape
  expected_species : ArrayMapSpeciesSnapshot
  expected_throw_type_error : Value?
}

///|
#warnings("-unused_value")
fn TrustedArrayMapRecursionRegistry::TrustedArrayMapRecursionRegistry(
  plan~ : ArrayMapRecursionPlan,
  step_function~ : Value,
  expected_global_object~ : ObjectData,
  expected_array_prototype~ : Value,
  expected_array_constructor~ : Value,
  expected_map_method~ : Value,
  expected_map_method_descriptor~ : ArrayMapDescriptorShape,
  expected_species~ : ArrayMapSpeciesSnapshot,
  expected_throw_type_error~ : Value?,
) -> TrustedArrayMapRecursionRegistry {
  {
    plan,
    step_function,
    expected_global_object,
    expected_array_prototype,
    expected_array_constructor,
    expected_map_method,
    expected_map_method_descriptor,
    expected_species,
    expected_throw_type_error,
  }
}

///|
fn array_map_value_identity_matches(expected : Value, actual : Value) -> Bool {
  match (expected, actual) {
    (Object(expected_data), Object(actual_data)) =>
      physical_equal(expected_data, actual_data)
    (Array(expected_data), Array(actual_data)) =>
      physical_equal(expected_data, actual_data)
    _ => false
  }
}

///|
#warnings("-unused_value")
fn array_map_callback_body_matches(
  body : Array[@ast.Stmt],
  parameter_name : String,
  member_property_name : String,
) -> Bool {
  match
    classify_array_map_callback(
      @ast.FuncExpr(None, [parameter_name], body, @token.Loc::default(), None),
      member_property_name,
    ) {
    Some(_) => true
    None => false
  }
}

///|
#warnings("-unused_value")
fn array_map_next_body_matches(
  body : Array[@ast.Stmt],
  function_name : String,
  parameter_name : String,
) -> Bool {
  match
    classify_array_map_next_function(
      @ast.FuncExpr(None, [], body, @token.Loc::default(), None),
      function_name,
      parameter_name,
    ) {
    Some(_) => true
    None => false
  }
}

///|
fn array_map_registry_throw_type_error(
  snapshot : CallbackFreeBindingSnapshot,
) -> Value? {
  match snapshot {
    CallbackFreeBindingPresent(value) => Some(value)
    CallbackFreeBindingMissing | CallbackFreeBindingUnsafe => None
  }
}

///|
#warnings("-unused_value")
fn Interpreter::seal_array_map_recursion_registry(
  self : Interpreter,
  preflight : ArrayMapRecursionPreflight,
  stmts : Array[@ast.Stmt],
) -> TrustedArrayMapRecursionRegistry raise InvalidActivationDispatchShell {
  guard stmts.length() == 2 else {
    invalid_activation_dispatch_shell(
      "array map root statement list changed during sealing",
    )
  }
  let step_function = match
    self.global.bindings.get(preflight.plan.function_name) {
    Some(binding) if binding.initialized => binding.value
    _ =>
      invalid_activation_dispatch_shell(
        "array map function declaration did not produce a binding",
      )
  }
  guard step_function is Object(step_data) &&
    step_data.callable is Some(UserFunc(data)) &&
    data.name == Some(preflight.plan.function_name) &&
    data.params.length() == 1 &&
    data.params[0] == preflight.plan.parameter_name &&
    !data.strict &&
    !data.has_name_binding &&
    physical_equal(data.closure, self.global) &&
    function_source_identity(step_function) ==
    preflight.expected_source_identity &&
    classify_array_map_recursion_program(stmts) is Some(_) else {
    invalid_activation_dispatch_shell(
      "array map function lost its sealed provenance",
    )
  }
  guard array_map_intrinsic_values(self)
    is Some(
      (array_constructor, array_prototype, map_method, map_method_descriptor)
    ) &&
    array_map_value_identity_matches(
      preflight.expected_array_constructor,
      array_constructor,
    ) &&
    array_map_value_identity_matches(
      preflight.expected_array_prototype,
      array_prototype,
    ) &&
    array_map_value_identity_matches(preflight.expected_map_method, map_method) &&
    array_map_species_descriptor_shape_matches(
      preflight.expected_map_method_descriptor,
      map_method_descriptor,
    ) else {
    invalid_activation_dispatch_shell(
      "array map intrinsic identity drifted before sealing",
    )
  }
  guard array_map_species_snapshot(self, array_prototype, array_constructor)
    is Some(actual_species) &&
    array_map_species_snapshot_matches(
      preflight.expected_species,
      actual_species,
    ) else {
    invalid_activation_dispatch_shell(
      "array map species identity drifted before sealing",
    )
  }
  TrustedArrayMapRecursionRegistry(
    plan=preflight.plan,
    step_function~,
    expected_global_object=preflight.expected_global_object,
    expected_array_prototype=preflight.expected_array_prototype,
    expected_array_constructor=preflight.expected_array_constructor,
    expected_map_method=preflight.expected_map_method,
    expected_map_method_descriptor=preflight.expected_map_method_descriptor,
    expected_species=preflight.expected_species,
    expected_throw_type_error=array_map_registry_throw_type_error(
      preflight.throw_type_error_snapshot,
    ),
  )
}
