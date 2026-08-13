///|
test "destructuring plan constructors own their child arrays" {
  let binding = destructure_plan_bind_name("value")
  let elements : Array[DestructurePlan?] = [Some(binding)]
  let array_plan = destructure_plan_array(elements, None)
  elements[0] = None
  match array_plan.node {
    ArrayPattern(stored, None) =>
      match stored[0] {
        Some(_) => ()
        None => abort("array plan borrowed its input elements")
      }
    _ => abort("expected array destructuring plan")
  }

  let properties : Array[DestructurePropertyPlan] = [
    destructure_plan_property("value", binding),
  ]
  let object_plan = destructure_plan_object(properties, None)
  properties[0] = destructure_plan_property("changed", binding)
  match object_plan.node {
    ObjectPattern(stored, None) => assert_true(stored[0].key == "value")
    _ => abort("expected object destructuring plan")
  }
}
