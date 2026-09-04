///|
#valtype
pub struct NumericUpdatePlan {
  priv assigned : Value
  priv expression : Value
}

///|
pub fn plan_numeric_update(
  old_number : Double,
  op : @ast.UpdateOp,
  prefix : Bool,
) -> NumericUpdatePlan {
  let next_number = match op {
    Increment => old_number + 1.0
    Decrement => old_number - 1.0
  }
  let assigned = Value::Number(next_number)
  let expression = if prefix { assigned } else { Value::Number(old_number) }
  { assigned, expression }
}

///|
pub fn NumericUpdatePlan::assigned_value(self : NumericUpdatePlan) -> Value {
  self.assigned
}

///|
pub fn NumericUpdatePlan::expression_value(self : NumericUpdatePlan) -> Value {
  self.expression
}
