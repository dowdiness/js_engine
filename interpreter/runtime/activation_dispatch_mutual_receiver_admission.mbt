// Exact, callback-free admission for the two-node escaped-computed receiver
// recursion slice. This recipe is intentionally separate from the #744
// one-function receiver plan.

///|
priv enum MutualReceiverNode {
  MutualReceiverLeft
  MutualReceiverRight
}

///|
#warnings("-unused_value-unused_constructor")
priv enum MutualReceiverAccessKind {
  MutualReceiverStatic
  MutualReceiverComputedLiteral(@token.Loc, Bool)
}

///|
#warnings("-unused_field")
priv struct MutualReceiverExpressionRecipe {
  base_condition_loc : @token.Loc
  marker_access : MutualReceiverAccessKind
  marker_member_loc : @token.Loc
  recursive_add_loc : @token.Loc
  recursive_access : MutualReceiverAccessKind
  recursive_member_loc : @token.Loc
  recursive_call_loc : @token.Loc
  recursive_subtract_loc : @token.Loc
}

///|
fn MutualReceiverExpressionRecipe::MutualReceiverExpressionRecipe(
  base_condition_loc~ : @token.Loc,
  marker_access~ : MutualReceiverAccessKind,
  marker_member_loc~ : @token.Loc,
  recursive_add_loc~ : @token.Loc,
  recursive_access~ : MutualReceiverAccessKind,
  recursive_member_loc~ : @token.Loc,
  recursive_call_loc~ : @token.Loc,
  recursive_subtract_loc~ : @token.Loc,
) -> MutualReceiverExpressionRecipe {
  {
    base_condition_loc,
    marker_access,
    marker_member_loc,
    recursive_add_loc,
    recursive_access,
    recursive_member_loc,
    recursive_call_loc,
    recursive_subtract_loc,
  }
}

///|
#warnings("-unused_field")
priv struct MutualReceiverNodePlan {
  node : MutualReceiverNode
  function_name : String
  property_name : String
  parameter : String
  recipe : MutualReceiverExpressionRecipe
}

///|
fn MutualReceiverNodePlan::MutualReceiverNodePlan(
  node~ : MutualReceiverNode,
  function_name~ : String,
  property_name~ : String,
  parameter~ : String,
  recipe~ : MutualReceiverExpressionRecipe,
) -> MutualReceiverNodePlan {
  { node, function_name, property_name, parameter, recipe }
}

///|
#warnings("-unused_field")
priv struct MutualReceiverRecursionPlan {
  left : MutualReceiverNodePlan
  right : MutualReceiverNodePlan
  receiver_name : String
  marker_name : String
  marker_property_access : MutualReceiverAccessKind
  left_property_access : MutualReceiverAccessKind
  right_property_access : MutualReceiverAccessKind
  root_access : MutualReceiverAccessKind
  root_member_loc : @token.Loc
  root_node : MutualReceiverNode
  initial_argument : Double
}

///|
fn MutualReceiverRecursionPlan::MutualReceiverRecursionPlan(
  left~ : MutualReceiverNodePlan,
  right~ : MutualReceiverNodePlan,
  receiver_name~ : String,
  marker_name~ : String,
  marker_property_access~ : MutualReceiverAccessKind,
  left_property_access~ : MutualReceiverAccessKind,
  right_property_access~ : MutualReceiverAccessKind,
  root_access~ : MutualReceiverAccessKind,
  root_member_loc~ : @token.Loc,
  root_node~ : MutualReceiverNode,
  initial_argument~ : Double,
) -> MutualReceiverRecursionPlan {
  {
    left,
    right,
    receiver_name,
    marker_name,
    marker_property_access,
    left_property_access,
    right_property_access,
    root_access,
    root_member_loc,
    root_node,
    initial_argument,
  }
}

///|
fn mutual_receiver_access_mode_matches(
  left : MutualReceiverAccessKind,
  right : MutualReceiverAccessKind,
) -> Bool {
  match (left, right) {
    (MutualReceiverStatic, MutualReceiverStatic) => true
    (
      MutualReceiverComputedLiteral(_, left_escaped),
      MutualReceiverComputedLiteral(_, right_escaped),
    ) => left_escaped == right_escaped
    _ => false
  }
}

///|
fn mutual_receiver_access_matches(
  expected : MutualReceiverAccessKind,
  actual : MutualReceiverAccessKind,
) -> Bool {
  match (expected, actual) {
    (MutualReceiverStatic, MutualReceiverStatic) => true
    (
      MutualReceiverComputedLiteral(expected_loc, expected_escaped),
      MutualReceiverComputedLiteral(actual_loc, actual_escaped),
    ) => expected_loc == actual_loc && expected_escaped == actual_escaped
    _ => false
  }
}

///|
fn mutual_receiver_property_access(
  property : @ast.Property,
) -> (String, MutualReceiverAccessKind)? {
  guard property.kind == @ast.Init && !property.is_method && property.computed else {
    return None
  }
  match property.key {
    @ast.StringLit(name, has_escape, @token.LexForm::LexNormal, key_loc) if has_escape &&
      name != "__proto__" =>
      Some((name, MutualReceiverComputedLiteral(key_loc, has_escape)))
    _ => None
  }
}

///|
fn mutual_receiver_this_member_access(
  expr : @ast.Expr,
) -> (String, MutualReceiverAccessKind, @token.Loc)? {
  match expr {
    @ast.ComputedMember(
      @ast.ThisExpr(_),
      @ast.StringLit(name, has_escape, @token.LexForm::LexNormal, key_loc),
      member_loc
    ) if has_escape =>
      Some(
        (name, MutualReceiverComputedLiteral(key_loc, has_escape), member_loc),
      )
    _ => None
  }
}

///|
fn mutual_receiver_ident_member_access(
  expr : @ast.Expr,
  expected_base : String,
) -> (String, MutualReceiverAccessKind, @token.Loc)? {
  match expr {
    @ast.ComputedMember(
      @ast.Ident(base, _),
      @ast.StringLit(name, has_escape, @token.LexForm::LexNormal, key_loc),
      member_loc
    ) if base == expected_base && has_escape =>
      Some(
        (name, MutualReceiverComputedLiteral(key_loc, has_escape), member_loc),
      )
    _ => None
  }
}

///|
fn mutual_receiver_recipe_access_modes_match(
  plan : MutualReceiverRecursionPlan,
) -> Bool {
  let mode = plan.marker_property_access
  mutual_receiver_access_mode_matches(mode, plan.left_property_access) &&
  mutual_receiver_access_mode_matches(mode, plan.right_property_access) &&
  mutual_receiver_access_mode_matches(mode, plan.root_access) &&
  mutual_receiver_access_mode_matches(mode, plan.left.recipe.marker_access) &&
  mutual_receiver_access_mode_matches(mode, plan.left.recipe.recursive_access) &&
  mutual_receiver_access_mode_matches(mode, plan.right.recipe.marker_access) &&
  mutual_receiver_access_mode_matches(mode, plan.right.recipe.recursive_access)
}

///|
fn mutual_receiver_access_is_escaped_computed(
  access : MutualReceiverAccessKind,
) -> Bool {
  match access {
    MutualReceiverComputedLiteral(_, true) => true
    _ => false
  }
}

///|
fn mutual_receiver_function_plan(
  stmt : @ast.Stmt,
  node : MutualReceiverNode,
  receiver_name : String,
  marker_name : String,
  function_name : String,
  property_name : String,
  opposite_property_name : String,
  marker_property_access : MutualReceiverAccessKind,
) -> MutualReceiverNodePlan? {
  match stmt {
    @ast.FuncDecl(actual_name, params, body, _, _) => {
      guard actual_name == function_name &&
        numeric_recursion_identifier_is_safe(actual_name) &&
        params.length() == 1 &&
        body.length() == 2 else {
        return None
      }
      let parameter = params[0]
      guard numeric_recursion_identifier_is_safe(parameter) &&
        parameter != actual_name &&
        parameter != receiver_name &&
        parameter != marker_name else {
        return None
      }
      let (marker_access, base_condition_loc, marker_member_loc) = match
        body[0] {
        @ast.IfStmt(
          @ast.Binary(
            @ast.EqEqEq,
            @ast.Ident(condition_parameter, _),
            base_condition,
            base_condition_loc
          ),
          @ast.ReturnStmt(Some(marker_expr), _),
          None,
          _
        ) if condition_parameter == parameter &&
          exact_numeric_recursion_number(base_condition, NUMERIC_RECURSION_BASE) =>
          match mutual_receiver_this_member_access(marker_expr) {
            Some((marker_property, marker_access, marker_member_loc)) if marker_property ==
              marker_name &&
              mutual_receiver_access_mode_matches(
                marker_property_access, marker_access,
              ) => (marker_access, base_condition_loc, marker_member_loc)
            _ => return None
          }
        _ => return None
      }
      let (
        recursive_access,
        recursive_member_loc,
        recursive_call_loc,
        recursive_add_loc,
        recursive_subtract_loc,
      ) = match body[1] {
        @ast.ReturnStmt(
          Some(
            @ast.Binary(
              @ast.Add,
              increment,
              @ast.Call(recursive_expr, args, recursive_call_loc),
              recursive_add_loc
            )
          ),
          _
        ) if exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) => {
          let (recursive_property, recursive_access, recursive_member_loc) = match
            mutual_receiver_this_member_access(recursive_expr) {
            Some(found) => found
            None => return None
          }
          guard recursive_property == opposite_property_name &&
            mutual_receiver_access_mode_matches(
              marker_property_access, recursive_access,
            ) &&
            args.length() == 1 else {
            return None
          }
          match args[0] {
            @ast.Binary(
              @ast.Sub,
              @ast.Ident(step_parameter, _),
              decrement,
              recursive_subtract_loc
            ) if step_parameter == parameter &&
              exact_numeric_recursion_number(decrement, NUMERIC_RECURSION_STEP) =>
              (
                recursive_access, recursive_member_loc, recursive_call_loc, recursive_add_loc,
                recursive_subtract_loc,
              )
            _ => return None
          }
        }
        _ => return None
      }
      Some(
        MutualReceiverNodePlan(
          node~,
          function_name~,
          property_name~,
          parameter~,
          recipe=MutualReceiverExpressionRecipe(
            base_condition_loc~,
            marker_access~,
            marker_member_loc~,
            recursive_add_loc~,
            recursive_access~,
            recursive_member_loc~,
            recursive_call_loc~,
            recursive_subtract_loc~,
          ),
        ),
      )
    }
    _ => None
  }
}

///|
#warnings("-unused_value")
fn classify_mutual_receiver_recursion_program(
  stmts : Array[@ast.Stmt],
) -> MutualReceiverRecursionPlan? {
  guard stmts.length() == 4 else { return None }
  let (left_name, left_params, left_body) = match stmts[0] {
    @ast.FuncDecl(name, params, body, _, _) => (name, params, body)
    _ => return None
  }
  let (right_name, right_params, right_body) = match stmts[1] {
    @ast.FuncDecl(name, params, body, _, _) => (name, params, body)
    _ => return None
  }
  guard numeric_recursion_identifier_is_safe(left_name) &&
    numeric_recursion_identifier_is_safe(right_name) &&
    left_name != right_name &&
    left_params.length() == 1 &&
    right_params.length() == 1 &&
    left_body.length() == 2 &&
    right_body.length() == 2 else {
    return None
  }
  let (
    receiver_name,
    marker_name,
    marker_property_access,
    left_property_access,
    right_property_access,
  ) = match stmts[2] {
    @ast.VarDecl(
      @ast.LetKind,
      receiver_name,
      Some(@ast.ObjectLit(properties, _)),
      _
    ) => {
      guard numeric_recursion_identifier_is_safe(receiver_name) &&
        properties.length() == 3 else {
        return None
      }
      let (marker_name, marker_property_access) = match
        mutual_receiver_property_access(properties[0]) {
        Some(found) => found
        None => return None
      }
      let (left_property_name, left_property_access) = match
        mutual_receiver_property_access(properties[1]) {
        Some(found) => found
        None => return None
      }
      let (right_property_name, right_property_access) = match
        mutual_receiver_property_access(properties[2]) {
        Some(found) => found
        None => return None
      }
      guard left_property_name == left_name &&
        right_property_name == right_name &&
        exact_numeric_recursion_number(
          properties[0].value,
          NUMERIC_RECURSION_BASE,
        ) else {
        return None
      }
      guard (match properties[1].value {
          @ast.Ident(name, _) => name == left_name
          _ => false
        }) &&
        (match properties[2].value {
          @ast.Ident(name, _) => name == right_name
          _ => false
        }) else {
        return None
      }
      (
        receiver_name, marker_name, marker_property_access, left_property_access,
        right_property_access,
      )
    }
    _ => return None
  }
  guard receiver_name != left_name &&
    receiver_name != right_name &&
    receiver_name != marker_name &&
    marker_name != left_name &&
    marker_name != right_name else {
    return None
  }
  let left_plan = match
    mutual_receiver_function_plan(
      stmts[0],
      MutualReceiverLeft,
      receiver_name,
      marker_name,
      left_name,
      left_name,
      right_name,
      marker_property_access,
    ) {
    Some(found) => found
    None => return None
  }
  let right_plan = match
    mutual_receiver_function_plan(
      stmts[1],
      MutualReceiverRight,
      receiver_name,
      marker_name,
      right_name,
      right_name,
      left_name,
      marker_property_access,
    ) {
    Some(found) => found
    None => return None
  }
  let (root_node, root_access, root_member_loc) = match stmts[3] {
    @ast.ExprStmt(@ast.Call(root_expr, args, _), _) if args.length() == 1 => {
      let (root_property, root_access, root_member_loc) = match
        mutual_receiver_ident_member_access(root_expr, receiver_name) {
        Some(found) => found
        None => return None
      }
      let root_node = if root_property == left_name {
        MutualReceiverLeft
      } else if root_property == right_name {
        MutualReceiverRight
      } else {
        return None
      }
      guard mutual_receiver_access_mode_matches(
          marker_property_access, root_access,
        ) &&
        exact_numeric_recursion_number(
          args[0],
          NUMERIC_RECURSION_INITIAL_ARGUMENT,
        ) else {
        return None
      }
      (root_node, root_access, root_member_loc)
    }
    _ => return None
  }
  Some(
    MutualReceiverRecursionPlan(
      left=left_plan,
      right=right_plan,
      receiver_name~,
      marker_name~,
      marker_property_access~,
      left_property_access~,
      right_property_access~,
      root_access~,
      root_member_loc~,
      root_node~,
      initial_argument=NUMERIC_RECURSION_INITIAL_ARGUMENT,
    ),
  )
}

///|
fn mutual_receiver_nodes_match(
  left : MutualReceiverNode,
  right : MutualReceiverNode,
) -> Bool {
  match (left, right) {
    (MutualReceiverLeft, MutualReceiverLeft)
    | (MutualReceiverRight, MutualReceiverRight) => true
    _ => false
  }
}

///|
fn mutual_receiver_expression_recipe_matches(
  expected : MutualReceiverExpressionRecipe,
  actual : MutualReceiverExpressionRecipe,
) -> Bool {
  expected.base_condition_loc == actual.base_condition_loc &&
  mutual_receiver_access_matches(expected.marker_access, actual.marker_access) &&
  expected.marker_member_loc == actual.marker_member_loc &&
  expected.recursive_add_loc == actual.recursive_add_loc &&
  mutual_receiver_access_matches(
    expected.recursive_access,
    actual.recursive_access,
  ) &&
  expected.recursive_member_loc == actual.recursive_member_loc &&
  expected.recursive_call_loc == actual.recursive_call_loc &&
  expected.recursive_subtract_loc == actual.recursive_subtract_loc
}

///|
fn mutual_receiver_node_plans_match(
  expected : MutualReceiverNodePlan,
  actual : MutualReceiverNodePlan,
) -> Bool {
  mutual_receiver_nodes_match(expected.node, actual.node) &&
  expected.function_name == actual.function_name &&
  expected.property_name == actual.property_name &&
  expected.parameter == actual.parameter &&
  mutual_receiver_expression_recipe_matches(expected.recipe, actual.recipe)
}

///|
fn mutual_receiver_recursion_plans_match(
  expected : MutualReceiverRecursionPlan,
  actual : MutualReceiverRecursionPlan,
) -> Bool {
  expected.receiver_name == actual.receiver_name &&
  expected.marker_name == actual.marker_name &&
  mutual_receiver_access_matches(
    expected.marker_property_access,
    actual.marker_property_access,
  ) &&
  mutual_receiver_access_matches(
    expected.left_property_access,
    actual.left_property_access,
  ) &&
  mutual_receiver_access_matches(
    expected.right_property_access,
    actual.right_property_access,
  ) &&
  mutual_receiver_access_matches(expected.root_access, actual.root_access) &&
  expected.root_member_loc == actual.root_member_loc &&
  mutual_receiver_nodes_match(expected.root_node, actual.root_node) &&
  expected.initial_argument == actual.initial_argument &&
  mutual_receiver_node_plans_match(expected.left, actual.left) &&
  mutual_receiver_node_plans_match(expected.right, actual.right)
}

///|
#warnings("-unused_value")
fn mutual_receiver_root_statement_matches(
  plan : MutualReceiverRecursionPlan,
  index : Int,
  stmt : @ast.Stmt,
) -> Bool {
  match index {
    0 =>
      match
        mutual_receiver_function_plan(
          stmt,
          MutualReceiverLeft,
          plan.receiver_name,
          plan.marker_name,
          plan.left.function_name,
          plan.left.property_name,
          plan.right.property_name,
          plan.marker_property_access,
        ) {
        Some(found) => mutual_receiver_node_plans_match(plan.left, found)
        None => false
      }
    1 =>
      match
        mutual_receiver_function_plan(
          stmt,
          MutualReceiverRight,
          plan.receiver_name,
          plan.marker_name,
          plan.right.function_name,
          plan.right.property_name,
          plan.left.property_name,
          plan.marker_property_access,
        ) {
        Some(found) => mutual_receiver_node_plans_match(plan.right, found)
        None => false
      }
    2 =>
      match stmt {
        @ast.VarDecl(
          @ast.LetKind,
          receiver_name,
          Some(@ast.ObjectLit(properties, _)),
          _
        ) => {
          guard receiver_name == plan.receiver_name && properties.length() == 3 else {
            return false
          }
          let (marker_name, marker_access) = match
            mutual_receiver_property_access(properties[0]) {
            Some(found) => found
            None => return false
          }
          let (left_name, left_access) = match
            mutual_receiver_property_access(properties[1]) {
            Some(found) => found
            None => return false
          }
          let (right_name, right_access) = match
            mutual_receiver_property_access(properties[2]) {
            Some(found) => found
            None => return false
          }
          marker_name == plan.marker_name &&
          left_name == plan.left.property_name &&
          right_name == plan.right.property_name &&
          mutual_receiver_access_matches(
            plan.marker_property_access,
            marker_access,
          ) &&
          mutual_receiver_access_matches(plan.left_property_access, left_access) &&
          mutual_receiver_access_matches(
            plan.right_property_access,
            right_access,
          ) &&
          exact_numeric_recursion_number(
            properties[0].value,
            NUMERIC_RECURSION_BASE,
          ) &&
          (match properties[1].value {
            @ast.Ident(name, _) => name == plan.left.function_name
            _ => false
          }) &&
          (match properties[2].value {
            @ast.Ident(name, _) => name == plan.right.function_name
            _ => false
          })
        }
        _ => false
      }
    3 =>
      match stmt {
        @ast.ExprStmt(@ast.Call(root_expr, args, _), _) if args.length() == 1 => {
          let (property_name, root_access, root_member_loc) = match
            mutual_receiver_ident_member_access(root_expr, plan.receiver_name) {
            Some(found) => found
            None => return false
          }
          let expected_property = match plan.root_node {
            MutualReceiverLeft => plan.left.property_name
            MutualReceiverRight => plan.right.property_name
          }
          property_name == expected_property &&
          mutual_receiver_access_matches(plan.root_access, root_access) &&
          root_member_loc == plan.root_member_loc &&
          exact_numeric_recursion_number(args[0], plan.initial_argument)
        }
        _ => false
      }
    _ => false
  }
}

///|
fn mutual_receiver_body_statement_matches(
  plan : MutualReceiverRecursionPlan,
  node : MutualReceiverNode,
  index : Int,
  stmt : @ast.Stmt,
) -> Bool {
  let selected = match node {
    MutualReceiverLeft => plan.left
    MutualReceiverRight => plan.right
  }
  match index {
    0 =>
      match stmt {
        @ast.IfStmt(
          @ast.Binary(
            @ast.EqEqEq,
            @ast.Ident(parameter, _),
            base_condition,
            base_condition_loc
          ),
          @ast.ReturnStmt(Some(marker_expr), _),
          None,
          _
        ) => {
          let (marker_name, marker_access, marker_member_loc) = match
            mutual_receiver_this_member_access(marker_expr) {
            Some(found) => found
            None => return false
          }
          parameter == selected.parameter &&
          marker_name == plan.marker_name &&
          mutual_receiver_access_matches(
            selected.recipe.marker_access,
            marker_access,
          ) &&
          base_condition_loc == selected.recipe.base_condition_loc &&
          marker_member_loc == selected.recipe.marker_member_loc &&
          exact_numeric_recursion_number(base_condition, NUMERIC_RECURSION_BASE)
        }
        _ => false
      }
    1 => {
      let opposite = match node {
        MutualReceiverLeft => plan.right.property_name
        MutualReceiverRight => plan.left.property_name
      }
      match stmt {
        @ast.ReturnStmt(
          Some(
            @ast.Binary(
              @ast.Add,
              increment,
              @ast.Call(recursive_expr, args, recursive_call_loc),
              recursive_add_loc
            )
          ),
          _
        ) => {
          let (property_name, recursive_access, recursive_member_loc) = match
            mutual_receiver_this_member_access(recursive_expr) {
            Some(found) => found
            None => return false
          }
          guard property_name == opposite && args.length() == 1 else {
            return false
          }
          guard mutual_receiver_access_matches(
              selected.recipe.recursive_access,
              recursive_access,
            ) &&
            recursive_add_loc == selected.recipe.recursive_add_loc &&
            recursive_member_loc == selected.recipe.recursive_member_loc &&
            recursive_call_loc == selected.recipe.recursive_call_loc &&
            exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) else {
            return false
          }
          match args[0] {
            @ast.Binary(
              @ast.Sub,
              @ast.Ident(parameter, _),
              decrement,
              recursive_subtract_loc
            ) =>
              parameter == selected.parameter &&
              recursive_subtract_loc == selected.recipe.recursive_subtract_loc &&
              exact_numeric_recursion_number(decrement, NUMERIC_RECURSION_STEP)
            _ => false
          }
        }
        _ => false
      }
    }
    _ => false
  }
}

///|
#warnings("-unused_value")
fn mutual_receiver_recursion_plan_is_dispatchable(
  plan : MutualReceiverRecursionPlan,
) -> Bool {
  mutual_receiver_recipe_access_modes_match(plan) &&
  mutual_receiver_access_is_escaped_computed(plan.marker_property_access) &&
  mutual_receiver_access_is_escaped_computed(plan.left_property_access) &&
  mutual_receiver_access_is_escaped_computed(plan.right_property_access) &&
  mutual_receiver_access_is_escaped_computed(plan.root_access) &&
  mutual_receiver_access_is_escaped_computed(plan.left.recipe.marker_access) &&
  mutual_receiver_access_is_escaped_computed(plan.left.recipe.recursive_access) &&
  mutual_receiver_access_is_escaped_computed(plan.right.recipe.marker_access) &&
  mutual_receiver_access_is_escaped_computed(plan.right.recipe.recursive_access)
}
