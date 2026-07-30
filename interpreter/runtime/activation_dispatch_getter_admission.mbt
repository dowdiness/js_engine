// Exact, callback-free admission for the #616 ordinary getter recursion
// slice. The normalized plan is semantic data; runtime provenance is sealed
// separately after the admitted root setup declarations have executed.

///|
#warnings("-unused_field")
priv struct GetterRecursionExpressionRecipe {
  base_condition_loc : @token.Loc
  decrement_loc : @token.Loc
  recursive_add_loc : @token.Loc
  recursive_member_loc : @token.Loc
  root_member_loc : @token.Loc
}

///|
fn GetterRecursionExpressionRecipe::GetterRecursionExpressionRecipe(
  base_condition_loc~ : @token.Loc,
  decrement_loc~ : @token.Loc,
  recursive_add_loc~ : @token.Loc,
  recursive_member_loc~ : @token.Loc,
  root_member_loc~ : @token.Loc,
) -> GetterRecursionExpressionRecipe {
  {
    base_condition_loc,
    decrement_loc,
    recursive_add_loc,
    recursive_member_loc,
    root_member_loc,
  }
}

///|
#warnings("-unused_field")
priv enum GetterRecursionAccessorPlacement {
  GetterOwnAccessor
  GetterDirectPrototypeAccessor(String)
}

///|
#warnings("-unused_field")
priv struct GetterRecursionPlan {
  counter_name : String
  object_name : String
  property_name : String
  initial_count : Double
  placement : GetterRecursionAccessorPlacement
  recipe : GetterRecursionExpressionRecipe
}

///|
fn GetterRecursionPlan::GetterRecursionPlan(
  counter_name~ : String,
  object_name~ : String,
  property_name~ : String,
  initial_count~ : Double,
  placement~ : GetterRecursionAccessorPlacement,
  recipe~ : GetterRecursionExpressionRecipe,
) -> GetterRecursionPlan {
  { counter_name, object_name, property_name, initial_count, placement, recipe }
}

///|
fn getter_recursion_accessor_holder_name(plan : GetterRecursionPlan) -> String {
  match plan.placement {
    GetterOwnAccessor => plan.object_name
    GetterDirectPrototypeAccessor(holder_name) => holder_name
  }
}

///|
fn getter_recursion_seal_statement_index(plan : GetterRecursionPlan) -> Int {
  match plan.placement {
    GetterOwnAccessor => 1
    GetterDirectPrototypeAccessor(_) => 2
  }
}

///|
fn getter_recursion_root_statement_index(plan : GetterRecursionPlan) -> Int {
  getter_recursion_seal_statement_index(plan) + 1
}

///|
fn getter_recursion_static_property_name(expr : @ast.Expr) -> String? {
  match expr {
    @ast.StringLit(name, false, @token.LexForm::LexNormal, _) => Some(name)
    _ => None
  }
}

///|
fn classify_getter_recursion_body(
  body : Array[@ast.Stmt],
  counter_name : String,
  object_name : String,
  property_name : String,
  root_member_loc : @token.Loc,
) -> GetterRecursionExpressionRecipe? {
  guard body.length() == 3 else { return None }
  let base_condition_loc = match body[0] {
    @ast.IfStmt(
      @ast.Binary(
        @ast.EqEqEq,
        @ast.Ident(condition_counter, _),
        base_condition,
        condition_loc
      ),
      @ast.ReturnStmt(Some(base_result), _),
      None,
      _
    ) if condition_counter == counter_name &&
      exact_numeric_recursion_number(base_condition, NUMERIC_RECURSION_BASE) &&
      exact_numeric_recursion_number(base_result, NUMERIC_RECURSION_BASE) =>
      condition_loc
    _ => return None
  }
  let decrement_loc = match body[1] {
    @ast.ExprStmt(
      @ast.Assign(
        assignment_counter,
        @ast.Binary(
          @ast.Sub,
          @ast.Ident(decrement_counter, _),
          decrement,
          subtraction_loc
        ),
        _
      ),
      _
    ) if assignment_counter == counter_name &&
      decrement_counter == counter_name &&
      exact_numeric_recursion_number(decrement, NUMERIC_RECURSION_STEP) =>
      subtraction_loc
    _ => return None
  }
  let (recursive_add_loc, recursive_member_loc) = match body[2] {
    @ast.ReturnStmt(
      Some(
        @ast.Binary(
          @ast.Add,
          increment,
          @ast.Member(
            @ast.Ident(recursive_object, _),
            recursive_property,
            member_loc
          ),
          add_loc
        )
      ),
      _
    ) if recursive_object == object_name &&
      recursive_property == property_name &&
      exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) =>
      (add_loc, member_loc)
    _ => return None
  }
  Some(
    GetterRecursionExpressionRecipe(
      base_condition_loc~,
      decrement_loc~,
      recursive_add_loc~,
      recursive_member_loc~,
      root_member_loc~,
    ),
  )
}

///|
fn classify_getter_recursion_accessor_object(
  stmt : @ast.Stmt,
  counter_name : String,
  recursive_object_name : String,
  root_property_name : String,
  root_member_loc : @token.Loc,
) -> (String, String, GetterRecursionExpressionRecipe)? {
  match stmt {
    @ast.VarDecl(
      @ast.LetKind,
      object_name,
      Some(@ast.ObjectLit(properties, _)),
      _
    ) => {
      guard numeric_recursion_identifier_is_safe(object_name) &&
        properties.length() == 1 else {
        return None
      }
      let property = properties[0]
      guard property.kind == @ast.Get &&
        !property.computed &&
        property.is_method else {
        return None
      }
      let property_name = match
        getter_recursion_static_property_name(property.key) {
        Some(found) => found
        None => return None
      }
      guard property_name == root_property_name else { return None }
      match property.value {
        @ast.FuncExpr(Some(getter_name), params, body, _, _) if getter_name ==
          property_name &&
          params.is_empty() =>
          match
            classify_getter_recursion_body(
              body, counter_name, recursive_object_name, property_name, root_member_loc,
            ) {
            Some(recipe) => Some((object_name, property_name, recipe))
            None => None
          }
        _ => None
      }
    }
    _ => None
  }
}

///|
fn getter_recursion_direct_prototype_target_matches(
  stmt : @ast.Stmt,
  target_name : String,
  holder_name : String,
) -> Bool {
  match stmt {
    @ast.VarDecl(
      @ast.LetKind,
      object_name,
      Some(@ast.ObjectLit(properties, _)),
      _
    ) => {
      guard object_name == target_name &&
        numeric_recursion_identifier_is_safe(object_name) &&
        properties.length() == 1 else {
        return false
      }
      let property = properties[0]
      property.kind == @ast.Init &&
      !property.computed &&
      !property.is_method &&
      (match (property.key, property.value) {
        (
          @ast.StringLit("__proto__", false, @token.LexForm::LexNormal, key_loc),
          @ast.Ident(prototype_name, value_loc),
        ) =>
          // The parser assigns a shorthand value (`{ __proto__ }`) the
          // object literal's opening location. An explicit initializer's
          // value follows its key, so this keeps the special colon form exact.
          prototype_name == holder_name && value_loc.offset > key_loc.offset
        _ => false
      })
    }
    _ => false
  }
}

///|
#warnings("-unused_value")
fn classify_getter_recursion_program(
  stmts : Array[@ast.Stmt],
) -> GetterRecursionPlan? {
  guard stmts.length() == 3 || stmts.length() == 4 else { return None }
  let (counter_name, initial_count) = match stmts[0] {
    @ast.VarDecl(@ast.LetKind, name, Some(initial), _) if numeric_recursion_identifier_is_safe(
        name,
      ) &&
      exact_numeric_recursion_number(
        initial,
        NUMERIC_RECURSION_INITIAL_ARGUMENT,
      ) => (name, NUMERIC_RECURSION_INITIAL_ARGUMENT)
    _ => return None
  }
  let root_statement_index = stmts.length() - 1
  let (root_object_name, root_property_name, root_member_loc) = match
    stmts[root_statement_index] {
    @ast.ExprStmt(
      @ast.Member(@ast.Ident(object_name, _), property_name, member_loc),
      _
    ) => (object_name, property_name, member_loc)
    _ => return None
  }
  guard counter_name != root_object_name else { return None }
  match
    classify_getter_recursion_accessor_object(
      stmts[1],
      counter_name,
      root_object_name,
      root_property_name,
      root_member_loc,
    ) {
    Some((holder_name, property_name, recipe)) => {
      let placement = if stmts.length() == 3 {
        guard holder_name == root_object_name else { return None }
        GetterOwnAccessor
      } else {
        guard holder_name != root_object_name &&
          holder_name != counter_name &&
          getter_recursion_direct_prototype_target_matches(
            stmts[2],
            root_object_name,
            holder_name,
          ) else {
          return None
        }
        GetterDirectPrototypeAccessor(holder_name)
      }
      Some(
        GetterRecursionPlan(
          counter_name~,
          object_name=root_object_name,
          property_name~,
          initial_count~,
          placement~,
          recipe~,
        ),
      )
    }
    None => None
  }
}

///|
#warnings("-unused_value")
fn getter_recursion_plan_is_dispatchable(plan : GetterRecursionPlan) -> Bool {
  match plan.placement {
    GetterOwnAccessor => true
    GetterDirectPrototypeAccessor(_) => false
  }
}

///|
#warnings("-unused_value")
fn getter_recursion_root_statement_matches(
  plan : GetterRecursionPlan,
  index : Int,
  stmt : @ast.Stmt,
) -> Bool {
  match index {
    0 =>
      match stmt {
        @ast.VarDecl(@ast.LetKind, name, Some(initial), _) =>
          name == plan.counter_name &&
          exact_numeric_recursion_number(initial, plan.initial_count)
        _ => false
      }
    1 =>
      match
        classify_getter_recursion_accessor_object(
          stmt,
          plan.counter_name,
          plan.object_name,
          plan.property_name,
          plan.recipe.root_member_loc,
        ) {
        Some((holder_name, property_name, _)) =>
          holder_name == getter_recursion_accessor_holder_name(plan) &&
          property_name == plan.property_name
        None => false
      }
    2 if getter_recursion_seal_statement_index(plan) == 2 =>
      getter_recursion_direct_prototype_target_matches(
        stmt,
        plan.object_name,
        getter_recursion_accessor_holder_name(plan),
      )
    root_index if root_index == getter_recursion_root_statement_index(plan) =>
      match stmt {
        @ast.ExprStmt(
          @ast.Member(@ast.Ident(object_name, _), property_name, _),
          _
        ) =>
          object_name == plan.object_name && property_name == plan.property_name
        _ => false
      }
    _ => false
  }
}

///|
#warnings("-unused_value")
fn getter_recursion_body_statement_matches(
  plan : GetterRecursionPlan,
  index : Int,
  stmt : @ast.Stmt,
) -> Bool {
  match index {
    0 =>
      match stmt {
        @ast.IfStmt(
          @ast.Binary(
            @ast.EqEqEq,
            @ast.Ident(counter_name, _),
            base_condition,
            _
          ),
          @ast.ReturnStmt(Some(base_result), _),
          None,
          _
        ) =>
          counter_name == plan.counter_name &&
          exact_numeric_recursion_number(base_condition, NUMERIC_RECURSION_BASE) &&
          exact_numeric_recursion_number(base_result, NUMERIC_RECURSION_BASE)
        _ => false
      }
    1 =>
      match stmt {
        @ast.ExprStmt(
          @ast.Assign(
            assignment_counter,
            @ast.Binary(
              @ast.Sub,
              @ast.Ident(decrement_counter, _),
              decrement,
              _
            ),
            _
          ),
          _
        ) =>
          assignment_counter == plan.counter_name &&
          decrement_counter == plan.counter_name &&
          exact_numeric_recursion_number(decrement, NUMERIC_RECURSION_STEP)
        _ => false
      }
    2 =>
      match stmt {
        @ast.ReturnStmt(
          Some(
            @ast.Binary(
              @ast.Add,
              increment,
              @ast.Member(@ast.Ident(object_name, _), property_name, _),
              _
            )
          ),
          _
        ) =>
          object_name == plan.object_name &&
          property_name == plan.property_name &&
          exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP)
        _ => false
      }
    _ => false
  }
}
