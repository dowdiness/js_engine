// Exact, callback-free admission for the first ordinary receiver-call slice.
// The syntax recipe is deliberately closed; runtime identity and descriptor
// provenance are sealed by activation_dispatch_receiver_trust.mbt.

///|
#warnings("-unused_value")
priv enum ReceiverRecursionAccessKind {
  ReceiverRecursionStatic
  ReceiverRecursionComputedLiteral(@token.Loc, Bool)
}

///|
#warnings("-unused_field")
priv struct ReceiverRecursionExpressionRecipe {
  base_condition_loc : @token.Loc
  marker_property_access : ReceiverRecursionAccessKind
  marker_member_loc : @token.Loc
  marker_access : ReceiverRecursionAccessKind
  recursive_add_loc : @token.Loc
  property_access : ReceiverRecursionAccessKind
  recursive_member_loc : @token.Loc
  recursive_access : ReceiverRecursionAccessKind
  recursive_call_loc : @token.Loc
  recursive_subtract_loc : @token.Loc
  root_access : ReceiverRecursionAccessKind
  root_member_loc : @token.Loc
}

///|
fn ReceiverRecursionExpressionRecipe::ReceiverRecursionExpressionRecipe(
  base_condition_loc~ : @token.Loc,
  marker_property_access~ : ReceiverRecursionAccessKind,
  marker_member_loc~ : @token.Loc,
  marker_access~ : ReceiverRecursionAccessKind,
  recursive_add_loc~ : @token.Loc,
  property_access~ : ReceiverRecursionAccessKind,
  recursive_member_loc~ : @token.Loc,
  recursive_access~ : ReceiverRecursionAccessKind,
  recursive_call_loc~ : @token.Loc,
  recursive_subtract_loc~ : @token.Loc,
  root_access~ : ReceiverRecursionAccessKind,
  root_member_loc~ : @token.Loc,
) -> ReceiverRecursionExpressionRecipe {
  {
    base_condition_loc,
    marker_property_access,
    marker_member_loc,
    marker_access,
    recursive_add_loc,
    property_access,
    recursive_member_loc,
    recursive_access,
    recursive_call_loc,
    recursive_subtract_loc,
    root_access,
    root_member_loc,
  }
}

///|
#warnings("-unused_field")
priv struct ReceiverRecursionPlan {
  function_name : String
  receiver_name : String
  parameter : String
  property_name : String
  marker_name : String
  initial_argument : Double
  recipe : ReceiverRecursionExpressionRecipe
}

///|
fn ReceiverRecursionPlan::ReceiverRecursionPlan(
  function_name~ : String,
  receiver_name~ : String,
  parameter~ : String,
  property_name~ : String,
  marker_name~ : String,
  initial_argument~ : Double,
  recipe~ : ReceiverRecursionExpressionRecipe,
) -> ReceiverRecursionPlan {
  {
    function_name,
    receiver_name,
    parameter,
    property_name,
    marker_name,
    initial_argument,
    recipe,
  }
}

///|
fn receiver_recursion_access_mode_matches(
  left : ReceiverRecursionAccessKind,
  right : ReceiverRecursionAccessKind,
) -> Bool {
  match (left, right) {
    (ReceiverRecursionStatic, ReceiverRecursionStatic) => true
    (
      ReceiverRecursionComputedLiteral(_, left_escaped),
      ReceiverRecursionComputedLiteral(_, right_escaped),
    ) => left_escaped == right_escaped
    _ => false
  }
}

///|
fn receiver_recursion_access_matches(
  expected : ReceiverRecursionAccessKind,
  actual : ReceiverRecursionAccessKind,
) -> Bool {
  match (expected, actual) {
    (ReceiverRecursionStatic, ReceiverRecursionStatic) => true
    (
      ReceiverRecursionComputedLiteral(expected_loc, expected_escaped),
      ReceiverRecursionComputedLiteral(actual_loc, actual_escaped),
    ) => expected_loc == actual_loc && expected_escaped == actual_escaped
    _ => false
  }
}

///|
fn receiver_recursion_property_access(
  property : @ast.Property,
) -> (String, ReceiverRecursionAccessKind)? {
  guard property.kind == @ast.Init && !property.is_method else { return None }
  match property.key {
    @ast.StringLit(name, has_escape, @token.LexForm::LexNormal, key_loc) if name !=
      "__proto__" =>
      if property.computed {
        Some((name, ReceiverRecursionComputedLiteral(key_loc, has_escape)))
      } else if !has_escape {
        Some((name, ReceiverRecursionStatic))
      } else {
        None
      }
    _ => None
  }
}

///|
fn receiver_recursion_this_member_access(
  expr : @ast.Expr,
) -> (String, ReceiverRecursionAccessKind, @token.Loc)? {
  match expr {
    @ast.Member(@ast.ThisExpr(_), name, member_loc) =>
      Some((name, ReceiverRecursionStatic, member_loc))
    @ast.ComputedMember(
      @ast.ThisExpr(_),
      @ast.StringLit(name, false, @token.LexForm::LexNormal, key_loc),
      member_loc
    ) => Some((name, ReceiverRecursionComputedLiteral(key_loc, false), member_loc))
    @ast.ComputedMember(
      @ast.ThisExpr(_),
      @ast.StringLit(name, true, @token.LexForm::LexNormal, key_loc),
      member_loc
    ) => Some((name, ReceiverRecursionComputedLiteral(key_loc, true), member_loc))
    _ => None
  }
}

///|
fn receiver_recursion_ident_member_access(
  expr : @ast.Expr,
  expected_base : String,
) -> (String, ReceiverRecursionAccessKind, @token.Loc)? {
  match expr {
    @ast.Member(@ast.Ident(base, _), name, member_loc) if base == expected_base =>
      Some((name, ReceiverRecursionStatic, member_loc))
    @ast.ComputedMember(
      @ast.Ident(base, _),
      @ast.StringLit(name, false, @token.LexForm::LexNormal, key_loc),
      member_loc
    ) if base == expected_base =>
      Some((name, ReceiverRecursionComputedLiteral(key_loc, false), member_loc))
    @ast.ComputedMember(
      @ast.Ident(base, _),
      @ast.StringLit(name, true, @token.LexForm::LexNormal, key_loc),
      member_loc
    ) if base == expected_base =>
      Some((name, ReceiverRecursionComputedLiteral(key_loc, true), member_loc))
    _ => None
  }
}

///|
fn receiver_recursion_recipe_access_modes_match(
  recipe : ReceiverRecursionExpressionRecipe,
) -> Bool {
  receiver_recursion_access_mode_matches(
    recipe.marker_property_access,
    recipe.property_access,
  ) &&
  receiver_recursion_access_mode_matches(
    recipe.marker_property_access,
    recipe.marker_access,
  ) &&
  receiver_recursion_access_mode_matches(
    recipe.marker_property_access,
    recipe.recursive_access,
  ) &&
  receiver_recursion_access_mode_matches(
    recipe.marker_property_access,
    recipe.root_access,
  )
}

///|
fn classify_receiver_recursion_function(
  stmt : @ast.Stmt,
  receiver_name : String,
  root_property_name : String,
  marker_property_access : ReceiverRecursionAccessKind,
  property_access : ReceiverRecursionAccessKind,
  root_access : ReceiverRecursionAccessKind,
  root_member_loc : @token.Loc,
) -> (String, String, String, ReceiverRecursionExpressionRecipe)? {
  match stmt {
    @ast.FuncDecl(function_name, params, body, _, _) => {
      guard numeric_recursion_identifier_is_safe(function_name) &&
        function_name == root_property_name &&
        params.length() == 1 &&
        body.length() == 2 else {
        return None
      }
      let parameter = params[0]
      guard numeric_recursion_identifier_is_safe(parameter) &&
        parameter != function_name &&
        parameter != receiver_name else {
        return None
      }
      let (marker_name, marker_access, base_condition_loc, marker_member_loc) = match
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
          match receiver_recursion_this_member_access(marker_expr) {
            Some((marker_name, marker_access, marker_member_loc)) =>
              (
                marker_name, marker_access, base_condition_loc, marker_member_loc,
              )
            None => return None
          }
        _ => return None
      }
      let (
        recursive_add_loc,
        recursive_access,
        recursive_member_loc,
        recursive_call_loc,
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
            receiver_recursion_this_member_access(recursive_expr) {
            Some(found) => found
            None => return None
          }
          guard recursive_property == root_property_name &&
            receiver_recursion_access_mode_matches(
              marker_property_access, recursive_access,
            ) &&
            receiver_recursion_access_mode_matches(
              marker_access, recursive_access,
            ) &&
            receiver_recursion_access_mode_matches(
              property_access, recursive_access,
            ) &&
            receiver_recursion_access_mode_matches(
              root_access, recursive_access,
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
                recursive_add_loc, recursive_access, recursive_member_loc, recursive_call_loc,
                recursive_subtract_loc,
              )
            _ => return None
          }
        }
        _ => return None
      }
      Some(
        (
          function_name,
          parameter,
          marker_name,
          ReceiverRecursionExpressionRecipe(
            base_condition_loc~,
            marker_property_access~,
            marker_member_loc~,
            marker_access~,
            recursive_add_loc~,
            property_access~,
            recursive_member_loc~,
            recursive_access~,
            recursive_call_loc~,
            recursive_subtract_loc~,
            root_access~,
            root_member_loc~,
          ),
        ),
      )
    }
    _ => None
  }
}

///|
#warnings("-unused_value")
fn classify_receiver_recursion_program(
  stmts : Array[@ast.Stmt],
) -> ReceiverRecursionPlan? {
  guard stmts.length() == 3 else { return None }
  let (
    receiver_name,
    marker_name,
    marker_property_access,
    function_name,
    root_property_name,
    property_access,
    root_access,
    root_member_loc,
  ) = match stmts[1] {
    @ast.VarDecl(
      @ast.LetKind,
      receiver_name,
      Some(@ast.ObjectLit(properties, _)),
      _
    ) => {
      guard numeric_recursion_identifier_is_safe(receiver_name) &&
        properties.length() == 2 else {
        return None
      }
      let (marker_name, marker_property_access) = match
        receiver_recursion_property_access(properties[0]) {
        Some(found) => found
        None => return None
      }
      guard properties[0].kind == @ast.Init &&
        exact_numeric_recursion_number(
          properties[0].value,
          NUMERIC_RECURSION_BASE,
        ) else {
        return None
      }
      let (root_property_name, property_access) = match
        receiver_recursion_property_access(properties[1]) {
        Some(found) => found
        None => return None
      }
      let function_name = match properties[1].value {
        @ast.Ident(value_name, _) => value_name
        _ => return None
      }
      guard properties[1].kind == @ast.Init &&
        function_name == root_property_name &&
        numeric_recursion_identifier_is_safe(function_name) else {
        return None
      }
      match stmts[2] {
        @ast.ExprStmt(@ast.Call(root_member_expr, args, _), _) if args.length() ==
          1 => {
          let (root_property_name_in_call, root_access, root_member_loc) = match
            receiver_recursion_ident_member_access(
              root_member_expr, receiver_name,
            ) {
            Some(found) => found
            None => return None
          }
          guard root_property_name_in_call == root_property_name else {
            return None
          }
          match args[0] {
            @ast.NumberLit(value, @token.LexForm::LexNormal, _) if value ==
              NUMERIC_RECURSION_INITIAL_ARGUMENT =>
              (
                receiver_name, marker_name, marker_property_access, function_name,
                root_property_name, property_access, root_access, root_member_loc,
              )
            _ => return None
          }
        }
        _ => return None
      }
    }
    _ => return None
  }
  guard receiver_name != function_name && receiver_name != marker_name else {
    return None
  }
  guard function_name != marker_name else { return None }
  guard stmts[0] is @ast.FuncDecl(_, _, _, _, _) else { return None }
  match
    classify_receiver_recursion_function(
      stmts[0],
      receiver_name,
      root_property_name,
      marker_property_access,
      property_access,
      root_access,
      root_member_loc,
    ) {
    Some((actual_function_name, parameter, marker_name_from_body, recipe)) => {
      guard actual_function_name == function_name &&
        marker_name_from_body == marker_name else {
        return None
      }
      Some(
        ReceiverRecursionPlan(
          function_name~,
          receiver_name~,
          parameter~,
          property_name=root_property_name,
          marker_name~,
          initial_argument=NUMERIC_RECURSION_INITIAL_ARGUMENT,
          recipe~,
        ),
      )
    }
    None => None
  }
}

///|
#warnings("-unused_value")
fn receiver_recursion_root_statement_matches(
  plan : ReceiverRecursionPlan,
  index : Int,
  stmt : @ast.Stmt,
) -> Bool {
  match index {
    0 =>
      match stmt {
        @ast.FuncDecl(name, params, body, _, _) =>
          name == plan.function_name &&
          params.length() == 1 &&
          params[0] == plan.parameter &&
          body.length() == 2
        _ => false
      }
    1 =>
      match stmt {
        @ast.VarDecl(
          @ast.LetKind,
          receiver_name,
          Some(@ast.ObjectLit(properties, _)),
          _
        ) => {
          guard receiver_name == plan.receiver_name && properties.length() == 2 else {
            return false
          }
          let (first_name, first_access) = match
            receiver_recursion_property_access(properties[0]) {
            Some(found) => found
            None => return false
          }
          let (second_name, second_access) = match
            receiver_recursion_property_access(properties[1]) {
            Some(found) => found
            None => return false
          }
          first_name == plan.marker_name &&
          second_name == plan.property_name &&
          receiver_recursion_access_matches(
            plan.recipe.marker_property_access,
            first_access,
          ) &&
          receiver_recursion_access_matches(
            plan.recipe.property_access,
            second_access,
          ) &&
          exact_numeric_recursion_number(
            properties[0].value,
            NUMERIC_RECURSION_BASE,
          ) &&
          (match properties[1].value {
            @ast.Ident(name, _) => name == plan.function_name
            _ => false
          })
        }
        _ => false
      }
    2 =>
      match stmt {
        @ast.ExprStmt(@ast.Call(root_member_expr, args, _), _) => {
          let (property_name, root_access, root_member_loc) = match
            receiver_recursion_ident_member_access(
              root_member_expr,
              plan.receiver_name,
            ) {
            Some(found) => found
            None => return false
          }
          property_name == plan.property_name &&
          receiver_recursion_access_matches(
            plan.recipe.root_access,
            root_access,
          ) &&
          root_member_loc == plan.recipe.root_member_loc &&
          args.length() == 1 &&
          exact_numeric_recursion_number(args[0], plan.initial_argument)
        }
        _ => false
      }
    _ => false
  }
}

///|
#warnings("-unused_value")
fn receiver_recursion_body_statement_matches(
  plan : ReceiverRecursionPlan,
  index : Int,
  stmt : @ast.Stmt,
) -> Bool {
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
            receiver_recursion_this_member_access(marker_expr) {
            Some(found) => found
            None => return false
          }
          parameter == plan.parameter &&
          marker_name == plan.marker_name &&
          receiver_recursion_access_matches(
            plan.recipe.marker_access,
            marker_access,
          ) &&
          base_condition_loc == plan.recipe.base_condition_loc &&
          marker_member_loc == plan.recipe.marker_member_loc &&
          exact_numeric_recursion_number(base_condition, NUMERIC_RECURSION_BASE)
        }
        _ => false
      }
    1 =>
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
            receiver_recursion_this_member_access(recursive_expr) {
            Some(found) => found
            None => return false
          }
          guard property_name == plan.property_name &&
            receiver_recursion_access_matches(
              plan.recipe.recursive_access,
              recursive_access,
            ) &&
            recursive_add_loc == plan.recipe.recursive_add_loc &&
            recursive_member_loc == plan.recipe.recursive_member_loc &&
            recursive_call_loc == plan.recipe.recursive_call_loc &&
            exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) &&
            args.length() == 1 else {
            return false
          }
          match args[0] {
            @ast.Binary(
              @ast.Sub,
              @ast.Ident(parameter, _),
              decrement,
              recursive_subtract_loc
            ) =>
              parameter == plan.parameter &&
              recursive_subtract_loc == plan.recipe.recursive_subtract_loc &&
              exact_numeric_recursion_number(decrement, NUMERIC_RECURSION_STEP)
            _ => false
          }
        }
        _ => false
      }
    _ => false
  }
}

///|
#warnings("-unused_value")
fn receiver_recursion_plan_is_dispatchable(
  plan : ReceiverRecursionPlan,
) -> Bool {
  receiver_recursion_recipe_access_modes_match(plan.recipe)
}
