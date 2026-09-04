///|
fn numeric_update_numbers(
  old_number : Double,
  op : @ast.UpdateOp,
  prefix : Bool,
) -> (Double, Double) raise {
  let plan = plan_numeric_update(old_number, op, prefix)
  guard plan.assigned_value() is Number(assigned) else {
    fail("numeric update assignment was not a Number")
  }
  guard plan.expression_value() is Number(expression) else {
    fail("numeric update expression was not a Number")
  }
  (assigned, expression)
}

///|
test "numeric update separates assignment from expression result" {
  let cases : Array[(@ast.UpdateOp, Bool, Double, Double)] = [
    (@ast.Increment, false, 8.0, 7.0),
    (@ast.Increment, true, 8.0, 8.0),
    (@ast.Decrement, false, 6.0, 7.0),
    (@ast.Decrement, true, 6.0, 6.0),
  ]
  for case in cases {
    let (op, prefix, assigned, expression) = case
    assert_eq(numeric_update_numbers(7.0, op, prefix), (assigned, expression))
  }
}

///|
test "numeric update preserves special Number results" {
  let negative_zero = -0.0
  let (assigned, expression) = numeric_update_numbers(
    negative_zero,
    @ast.Increment,
    false,
  )
  assert_eq(assigned, 1.0)
  assert_eq(
    expression.reinterpret_as_int64(),
    negative_zero.reinterpret_as_int64(),
  )
  let nan = 0.0 / 0.0
  let (nan_assigned, nan_expression) = numeric_update_numbers(
    nan,
    @ast.Increment,
    true,
  )
  assert_true(nan_assigned.is_nan())
  assert_true(nan_expression.is_nan())
  let infinity = 1.0 / 0.0
  let (infinite_assigned, infinite_expression) = numeric_update_numbers(
    infinity,
    @ast.Decrement,
    true,
  )
  assert_true(infinite_assigned.is_pos_inf())
  assert_true(infinite_expression.is_pos_inf())
}
