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
priv struct DirectNumericRecursionCallPlan {
  entry : NumericRecursionFunctionSyntax
  cycle : DirectNumericRecursionCycle
  initial_argument : Double
  root_call_loc : @token.Loc
}

///|
fn DirectNumericRecursionCallPlan::DirectNumericRecursionCallPlan(
  entry~ : NumericRecursionFunctionSyntax,
  cycle~ : DirectNumericRecursionCycle,
  initial_argument~ : Double,
  root_call_loc~ : @token.Loc,
) -> DirectNumericRecursionCallPlan {
  { entry, cycle, initial_argument, root_call_loc }
}

///|
fn classify_direct_numeric_recursion_user_func(
  data : FuncData,
) -> (NumericRecursionFunctionSyntax, DirectNumericRecursionCycle)? {
  guard data.name is Some(name) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method else {
    return None
  }
  guard classify_numeric_recursion_function_syntax(name, data.params, data.body)
    is Some(entry) &&
    entry.return_recipe is NumericRecursionDirectReturn &&
    numeric_recursion_identifier_is_safe(entry.recursive_callee) &&
    entry.recursive_callee != entry.parameter else {
    return None
  }
  let cycle = if entry.recursive_callee == name {
    DirectNumericSelf
  } else {
    DirectNumericMutualPeer(entry.recursive_callee)
  }
  Some((entry, cycle))
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
