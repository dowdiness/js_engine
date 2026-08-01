// Exact, callback-free admission for the first ordinary receiver-call slice.
// The syntax recipe is deliberately closed; runtime identity and descriptor
// provenance are sealed by activation_dispatch_receiver_trust.mbt.

///|
#warnings("-unused_field")
priv struct ReceiverRecursionExpressionRecipe {
  base_condition_loc : @token.Loc
  marker_member_loc : @token.Loc
  recursive_add_loc : @token.Loc
  recursive_member_loc : @token.Loc
  recursive_call_loc : @token.Loc
  recursive_subtract_loc : @token.Loc
  root_member_loc : @token.Loc
}

///|
fn ReceiverRecursionExpressionRecipe::ReceiverRecursionExpressionRecipe(
  base_condition_loc~ : @token.Loc,
  marker_member_loc~ : @token.Loc,
  recursive_add_loc~ : @token.Loc,
  recursive_member_loc~ : @token.Loc,
  recursive_call_loc~ : @token.Loc,
  recursive_subtract_loc~ : @token.Loc,
  root_member_loc~ : @token.Loc,
) -> ReceiverRecursionExpressionRecipe {
  {
    base_condition_loc,
    marker_member_loc,
    recursive_add_loc,
    recursive_member_loc,
    recursive_call_loc,
    recursive_subtract_loc,
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
fn receiver_recursion_static_property_name(expr : @ast.Expr) -> String? {
  match expr {
    @ast.StringLit(name, false, @token.LexForm::LexNormal, _) if name !=
      "__proto__" => Some(name)
    _ => None
  }
}

///|
fn classify_receiver_recursion_function(
  stmt : @ast.Stmt,
  receiver_name : String,
  root_property_name : String,
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
      let (marker_name, base_condition_loc, marker_member_loc) = match body[0] {
        @ast.IfStmt(
          @ast.Binary(
            @ast.EqEqEq,
            @ast.Ident(condition_parameter, _),
            base_condition,
            base_condition_loc
          ),
          @ast.ReturnStmt(
            Some(@ast.Member(@ast.ThisExpr(_), marker_name, marker_member_loc)),
            _
          ),
          None,
          _
        ) if condition_parameter == parameter &&
          exact_numeric_recursion_number(base_condition, NUMERIC_RECURSION_BASE) =>
          (marker_name, base_condition_loc, marker_member_loc)
        _ => return None
      }
      let (
        recursive_add_loc,
        recursive_member_loc,
        recursive_call_loc,
        recursive_subtract_loc,
      ) = match body[1] {
        @ast.ReturnStmt(
          Some(
            @ast.Binary(
              @ast.Add,
              increment,
              @ast.Call(
                @ast.Member(
                  @ast.ThisExpr(_),
                  recursive_property,
                  recursive_member_loc
                ),
                args,
                recursive_call_loc
              ),
              recursive_add_loc
            )
          ),
          _
        ) if recursive_property == root_property_name &&
          exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) => {
          guard args.length() == 1 else { return None }
          match args[0] {
            @ast.Binary(
              @ast.Sub,
              @ast.Ident(step_parameter, _),
              decrement,
              recursive_subtract_loc
            ) if step_parameter == parameter &&
              exact_numeric_recursion_number(decrement, NUMERIC_RECURSION_STEP) =>
              (
                recursive_add_loc, recursive_member_loc, recursive_call_loc, recursive_subtract_loc,
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
            marker_member_loc~,
            recursive_add_loc~,
            recursive_member_loc~,
            recursive_call_loc~,
            recursive_subtract_loc~,
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
    function_name,
    root_property_name,
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
      let marker_name = match
        receiver_recursion_static_property_name(properties[0].key) {
        Some(name) => name
        None => return None
      }
      guard properties[0].kind == @ast.Init &&
        !properties[0].computed &&
        !properties[0].is_method &&
        exact_numeric_recursion_number(
          properties[0].value,
          NUMERIC_RECURSION_BASE,
        ) else {
        return None
      }
      let root_property_name = match
        receiver_recursion_static_property_name(properties[1].key) {
        Some(name) => name
        None => return None
      }
      let function_name = match properties[1].value {
        @ast.Ident(value_name, _) => value_name
        _ => return None
      }
      guard properties[1].kind == @ast.Init &&
        !properties[1].computed &&
        !properties[1].is_method &&
        function_name == root_property_name &&
        numeric_recursion_identifier_is_safe(function_name) else {
        return None
      }
      match stmts[2] {
        @ast.ExprStmt(
          @ast.Call(
            @ast.Member(
              @ast.Ident(root_object_name, _),
              root_property_name_in_call,
              root_member_loc
            ),
            args,
            _
          ),
          _
        ) if root_object_name == receiver_name &&
          root_property_name_in_call == root_property_name &&
          args.length() == 1 =>
          match args[0] {
            @ast.NumberLit(value, @token.LexForm::LexNormal, _) if value ==
              NUMERIC_RECURSION_INITIAL_ARGUMENT =>
              (
                receiver_name, marker_name, function_name, root_property_name, root_member_loc,
              )
            _ => return None
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
          let first_name = receiver_recursion_static_property_name(
            properties[0].key,
          )
          let second_name = receiver_recursion_static_property_name(
            properties[1].key,
          )
          first_name == Some(plan.marker_name) &&
          second_name == Some(plan.property_name) &&
          properties[0].kind == @ast.Init &&
          !properties[0].computed &&
          !properties[0].is_method &&
          exact_numeric_recursion_number(
            properties[0].value,
            NUMERIC_RECURSION_BASE,
          ) &&
          properties[1].kind == @ast.Init &&
          !properties[1].computed &&
          !properties[1].is_method &&
          (match properties[1].value {
            @ast.Ident(name, _) => name == plan.function_name
            _ => false
          })
        }
        _ => false
      }
    2 =>
      match stmt {
        @ast.ExprStmt(
          @ast.Call(
            @ast.Member(@ast.Ident(receiver_name, _), property_name, _),
            args,
            _
          ),
          _
        ) =>
          receiver_name == plan.receiver_name &&
          property_name == plan.property_name &&
          args.length() == 1 &&
          exact_numeric_recursion_number(args[0], plan.initial_argument)
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
          @ast.Binary(@ast.EqEqEq, @ast.Ident(parameter, _), base_condition, _),
          @ast.ReturnStmt(
            Some(@ast.Member(@ast.ThisExpr(_), marker_name, _)),
            _
          ),
          None,
          _
        ) =>
          parameter == plan.parameter &&
          marker_name == plan.marker_name &&
          exact_numeric_recursion_number(base_condition, NUMERIC_RECURSION_BASE)
        _ => false
      }
    1 =>
      match stmt {
        @ast.ReturnStmt(
          Some(
            @ast.Binary(
              @ast.Add,
              increment,
              @ast.Call(
                @ast.Member(@ast.ThisExpr(_), property_name, _),
                args,
                _
              ),
              _
            )
          ),
          _
        ) => {
          guard property_name == plan.property_name &&
            exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) &&
            args.length() == 1 else {
            return false
          }
          match args[0] {
            @ast.Binary(@ast.Sub, @ast.Ident(parameter, _), decrement, _) =>
              parameter == plan.parameter &&
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
fn receiver_recursion_plan_is_dispatchable(_ : ReceiverRecursionPlan) -> Bool {
  true
}
