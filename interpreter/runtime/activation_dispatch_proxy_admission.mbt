// Exact, callback-free admission for the #616 Proxy `get` recursion slice.
// The normalized plan contains syntax only; runtime provenance is sealed after
// the admitted root setup has created the Proxy and its trap function.

///|
const PROXY_GET_RECURSION_CONSTRUCTOR_NAME = "Proxy"

///|
const PROXY_GET_RECURSION_TRAP_NAME = "get"

///|
#warnings("-unused_field")
priv struct ProxyGetRecursionExpressionRecipe {
  base_condition_loc : @token.Loc
  decrement_loc : @token.Loc
  recursive_add_loc : @token.Loc
  recursive_member_loc : @token.Loc
  root_member_loc : @token.Loc
}

///|
fn ProxyGetRecursionExpressionRecipe::ProxyGetRecursionExpressionRecipe(
  base_condition_loc~ : @token.Loc,
  decrement_loc~ : @token.Loc,
  recursive_add_loc~ : @token.Loc,
  recursive_member_loc~ : @token.Loc,
  root_member_loc~ : @token.Loc,
) -> ProxyGetRecursionExpressionRecipe {
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
priv struct ProxyGetRecursionPlan {
  counter_name : String
  proxy_name : String
  property_name : String
  target_parameter : String
  key_parameter : String
  receiver_parameter : String
  initial_count : Double
  recipe : ProxyGetRecursionExpressionRecipe
}

///|
fn ProxyGetRecursionPlan::ProxyGetRecursionPlan(
  counter_name~ : String,
  proxy_name~ : String,
  property_name~ : String,
  target_parameter~ : String,
  key_parameter~ : String,
  receiver_parameter~ : String,
  initial_count~ : Double,
  recipe~ : ProxyGetRecursionExpressionRecipe,
) -> ProxyGetRecursionPlan {
  {
    counter_name,
    proxy_name,
    property_name,
    target_parameter,
    key_parameter,
    receiver_parameter,
    initial_count,
    recipe,
  }
}

///|
fn proxy_get_recursion_static_property_name(expr : @ast.Expr) -> String? {
  match expr {
    @ast.StringLit(name, false, @token.LexForm::LexNormal, _) => Some(name)
    _ => None
  }
}

///|
fn proxy_get_recursion_parameters_are_exact(
  params : Array[String],
  counter_name : String,
  proxy_name : String,
) -> Bool {
  guard params.length() == 3 else { return false }
  let target_parameter = params[0]
  let key_parameter = params[1]
  let receiver_parameter = params[2]
  numeric_recursion_identifier_is_safe(target_parameter) &&
  numeric_recursion_identifier_is_safe(key_parameter) &&
  numeric_recursion_identifier_is_safe(receiver_parameter) &&
  target_parameter != key_parameter &&
  target_parameter != receiver_parameter &&
  key_parameter != receiver_parameter &&
  target_parameter != counter_name &&
  target_parameter != proxy_name &&
  key_parameter != counter_name &&
  key_parameter != proxy_name &&
  receiver_parameter != counter_name &&
  receiver_parameter != proxy_name
}

///|
fn classify_proxy_get_recursion_body(
  body : Array[@ast.Stmt],
  counter_name : String,
  proxy_name : String,
  property_name : String,
  root_member_loc : @token.Loc,
) -> ProxyGetRecursionExpressionRecipe? {
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
            @ast.Ident(recursive_proxy, _),
            recursive_property,
            member_loc
          ),
          add_loc
        )
      ),
      _
    ) if recursive_proxy == proxy_name &&
      recursive_property == property_name &&
      exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) =>
      (add_loc, member_loc)
    _ => return None
  }
  Some(
    ProxyGetRecursionExpressionRecipe(
      base_condition_loc~,
      decrement_loc~,
      recursive_add_loc~,
      recursive_member_loc~,
      root_member_loc~,
    ),
  )
}

///|
fn classify_proxy_get_recursion_handler(
  expr : @ast.Expr,
  counter_name : String,
  proxy_name : String,
  property_name : String,
  root_member_loc : @token.Loc,
) -> (Array[String], ProxyGetRecursionExpressionRecipe)? {
  guard expr is @ast.ObjectLit(properties, _) && properties.length() == 1 else {
    return None
  }
  let property = properties[0]
  guard property.kind == @ast.Init &&
    !property.computed &&
    property.is_method &&
    proxy_get_recursion_static_property_name(property.key) ==
    Some(PROXY_GET_RECURSION_TRAP_NAME) else {
    return None
  }
  match property.value {
    @ast.FuncExpr(Some(trap_name), params, body, _, _) if trap_name ==
      PROXY_GET_RECURSION_TRAP_NAME &&
      proxy_get_recursion_parameters_are_exact(params, counter_name, proxy_name) =>
      match
        classify_proxy_get_recursion_body(
          body, counter_name, proxy_name, property_name, root_member_loc,
        ) {
        Some(recipe) => Some((params, recipe))
        None => None
      }
    _ => None
  }
}

///|
fn classify_proxy_get_recursion_setup(
  stmt : @ast.Stmt,
  counter_name : String,
  proxy_name : String,
  property_name : String,
  root_member_loc : @token.Loc,
) -> (Array[String], ProxyGetRecursionExpressionRecipe)? {
  match stmt {
    @ast.ExprStmt(
      @ast.Assign(
        assignment_name,
        @ast.NewExpr(@ast.Ident(constructor_name, _), args, _),
        _
      ),
      _
    ) if assignment_name == proxy_name &&
      constructor_name == PROXY_GET_RECURSION_CONSTRUCTOR_NAME &&
      args.length() == 2 => {
      guard args[0] is @ast.ObjectLit(target_properties, _) &&
        target_properties.is_empty() else {
        return None
      }
      classify_proxy_get_recursion_handler(
        args[1],
        counter_name,
        proxy_name,
        property_name,
        root_member_loc,
      )
    }
    _ => None
  }
}

///|
#warnings("-unused_value")
fn classify_proxy_get_recursion_program(
  stmts : Array[@ast.Stmt],
) -> ProxyGetRecursionPlan? {
  guard stmts.length() == 4 else { return None }
  let (counter_name, initial_count) = match stmts[0] {
    @ast.VarDecl(@ast.LetKind, name, Some(initial), _) if numeric_recursion_identifier_is_safe(
        name,
      ) &&
      exact_numeric_recursion_number(
        initial,
        NUMERIC_RECURSION_INITIAL_ARGUMENT,
      ) &&
      name != PROXY_GET_RECURSION_CONSTRUCTOR_NAME =>
      (name, NUMERIC_RECURSION_INITIAL_ARGUMENT)
    _ => return None
  }
  let proxy_name = match stmts[1] {
    @ast.VarDecl(@ast.LetKind, name, None, _) if numeric_recursion_identifier_is_safe(
        name,
      ) &&
      name != counter_name &&
      name != PROXY_GET_RECURSION_CONSTRUCTOR_NAME => name
    _ => return None
  }
  let (root_proxy_name, property_name, root_member_loc) = match stmts[3] {
    @ast.ExprStmt(@ast.Member(@ast.Ident(name, _), property, member_loc), _) =>
      (name, property, member_loc)
    _ => return None
  }
  guard root_proxy_name == proxy_name else { return None }
  match
    classify_proxy_get_recursion_setup(
      stmts[2],
      counter_name,
      proxy_name,
      property_name,
      root_member_loc,
    ) {
    Some((params, recipe)) =>
      Some(
        ProxyGetRecursionPlan(
          counter_name~,
          proxy_name~,
          property_name~,
          target_parameter=params[0],
          key_parameter=params[1],
          receiver_parameter=params[2],
          initial_count~,
          recipe~,
        ),
      )
    None => None
  }
}

///|
#warnings("-unused_value")
fn proxy_get_recursion_plan_is_dispatchable(
  _plan : ProxyGetRecursionPlan,
) -> Bool {
  true
}

///|
fn proxy_get_recursion_seal_statement_index(
  _plan : ProxyGetRecursionPlan,
) -> Int {
  2
}

///|
fn proxy_get_recursion_root_statement_index(
  _plan : ProxyGetRecursionPlan,
) -> Int {
  3
}

///|
#warnings("-unused_value")
fn proxy_get_recursion_root_statement_matches(
  plan : ProxyGetRecursionPlan,
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
      match stmt {
        @ast.VarDecl(@ast.LetKind, name, None, _) => name == plan.proxy_name
        _ => false
      }
    seal_index if seal_index == proxy_get_recursion_seal_statement_index(plan) =>
      match
        classify_proxy_get_recursion_setup(
          stmt,
          plan.counter_name,
          plan.proxy_name,
          plan.property_name,
          plan.recipe.root_member_loc,
        ) {
        Some((params, _)) =>
          params[0] == plan.target_parameter &&
          params[1] == plan.key_parameter &&
          params[2] == plan.receiver_parameter
        None => false
      }
    root_index if root_index == proxy_get_recursion_root_statement_index(plan) =>
      match stmt {
        @ast.ExprStmt(@ast.Member(@ast.Ident(name, _), property, _), _) =>
          name == plan.proxy_name && property == plan.property_name
        _ => false
      }
    _ => false
  }
}

///|
#warnings("-unused_value")
fn proxy_get_recursion_body_statement_matches(
  plan : ProxyGetRecursionPlan,
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
              @ast.Member(@ast.Ident(proxy_name, _), property_name, _),
              _
            )
          ),
          _
        ) =>
          proxy_name == plan.proxy_name &&
          property_name == plan.property_name &&
          exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP)
        _ => false
      }
    _ => false
  }
}
