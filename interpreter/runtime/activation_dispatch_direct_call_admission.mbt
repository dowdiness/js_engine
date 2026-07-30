// Exact, callback-free admission for a public `Interpreter::call_value` root
// that enters the numeric self/mutual recursion slice. The plan contains call
// syntax only; closure, binding, object, realm, and source provenance are
// sealed by the next layer before managed execution begins.

///|
#warnings("-unused_constructor-unused_field")
priv enum DirectNumericRecursionCycle {
  DirectNumericSelf
  DirectNumericMutualPeer(String)
}

///|
#warnings("-unused_field")
priv struct DirectNumericRecursionEntryPlan {
  name : String
  parameter : String
  recursive_callee : String
  expression_recipe : NumericRecursionExpressionRecipe
}

///|
fn DirectNumericRecursionEntryPlan::DirectNumericRecursionEntryPlan(
  name~ : String,
  parameter~ : String,
  recursive_callee~ : String,
  expression_recipe~ : NumericRecursionExpressionRecipe,
) -> DirectNumericRecursionEntryPlan {
  { name, parameter, recursive_callee, expression_recipe }
}

///|
#warnings("-unused_field")
priv struct DirectNumericRecursionCallPlan {
  entry : DirectNumericRecursionEntryPlan
  cycle : DirectNumericRecursionCycle
  initial_argument : Double
  root_call_loc : @token.Loc
}

///|
fn DirectNumericRecursionCallPlan::DirectNumericRecursionCallPlan(
  entry~ : DirectNumericRecursionEntryPlan,
  cycle~ : DirectNumericRecursionCycle,
  initial_argument~ : Double,
  root_call_loc~ : @token.Loc,
) -> DirectNumericRecursionCallPlan {
  { entry, cycle, initial_argument, root_call_loc }
}

///|
fn classify_direct_numeric_recursion_user_func(
  data : FuncData,
) -> (DirectNumericRecursionEntryPlan, DirectNumericRecursionCycle)? {
  guard data.name is Some(name) &&
    numeric_recursion_identifier_is_safe(name) &&
    data.params.length() == 1 &&
    data.body.length() == 2 &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method else {
    return None
  }
  let parameter = data.params[0]
  guard numeric_recursion_identifier_is_safe(parameter) && parameter != name else {
    return None
  }
  guard numeric_recursion_base_condition_loc(data.body[0], parameter)
    is Some(base_condition_loc) else {
    return None
  }
  guard classify_numeric_recursion_step_detail(data.body[1], parameter)
    is Some(step) &&
    numeric_recursion_identifier_is_safe(step.recursive_callee) &&
    step.recursive_callee != parameter else {
    return None
  }
  let cycle = if step.recursive_callee == name {
    DirectNumericSelf
  } else {
    DirectNumericMutualPeer(step.recursive_callee)
  }
  let expression_recipe = NumericRecursionExpressionRecipe(
    base_condition_loc~,
    recursive_add_loc=step.recursive_add_loc,
    recursive_call_loc=step.recursive_call_loc,
    recursive_subtract_loc=step.recursive_subtract_loc,
  )
  Some(
    (
      DirectNumericRecursionEntryPlan(
        name~,
        parameter~,
        recursive_callee=step.recursive_callee,
        expression_recipe~,
      ),
      cycle,
    ),
  )
}

///|
#warnings("-unused_value")
fn classify_direct_numeric_recursion_call(
  callee : Value,
  this_value : Value,
  args : Array[Value],
  root_call_loc : @token.Loc,
) -> DirectNumericRecursionCallPlan? {
  guard this_value is Undefined &&
    args.length() == 1 &&
    args[0] is Number(initial_argument) &&
    initial_argument == NUMERIC_RECURSION_INITIAL_ARGUMENT else {
    return None
  }
  guard callee is Object(object_data) &&
    object_data.class_name == "Function" &&
    object_data.callable is Some(UserFunc(data)) else {
    return None
  }
  match classify_direct_numeric_recursion_user_func(data) {
    Some((entry, cycle)) =>
      Some(
        DirectNumericRecursionCallPlan(
          entry~,
          cycle~,
          initial_argument~,
          root_call_loc~,
        ),
      )
    None => None
  }
}
