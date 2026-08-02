// Closed admission for the first tree-walker ordinary-constructor slice.
// Only the exact fixed-parameter, numeric self/mutual-recursive body below is
// admitted.  Everything else remains on the legacy construction path.

///|
#warnings("-unused_constructor")
priv enum ConstructorRecursionTerminal {
  ConstructorRecursionNormal
  ConstructorRecursionReturn
  ConstructorRecursionThrow
}

///|
#warnings("-unused_field")
priv struct ConstructorRecursionFunctionPlan {
  name : String
  parameter : String
  value_property : String
  child_property : String
  recursive_callee : String
  condition_loc : @token.Loc
  subtract_loc : @token.Loc
  construct_loc : @token.Loc
  terminal : ConstructorRecursionTerminal
}

///|
fn ConstructorRecursionFunctionPlan::ConstructorRecursionFunctionPlan(
  name~ : String,
  parameter~ : String,
  value_property~ : String,
  child_property~ : String,
  recursive_callee~ : String,
  condition_loc~ : @token.Loc,
  subtract_loc~ : @token.Loc,
  construct_loc~ : @token.Loc,
  terminal~ : ConstructorRecursionTerminal,
) -> ConstructorRecursionFunctionPlan {
  {
    name,
    parameter,
    value_property,
    child_property,
    recursive_callee,
    condition_loc,
    subtract_loc,
    construct_loc,
    terminal,
  }
}

///|
fn constructor_recursion_terminal_expr_is_admissible(expr : @ast.Expr) -> Bool {
  match expr {
    @ast.NumberLit(_, _, _)
    | @ast.StringLit(_, _, _, _)
    | @ast.BoolLit(_, _)
    | @ast.NullLit(_)
    | @ast.UndefinedLit(_)
    | @ast.Ident(_, _)
    | @ast.ThisExpr(_) => true
    @ast.ObjectLit(properties, _) => {
      for property in properties {
        guard property.kind == @ast.Init &&
          !property.computed &&
          !property.is_method &&
          (
            property.value is @ast.NumberLit(_, _, _) ||
            property.value is @ast.StringLit(_, _, _, _) ||
            property.value is @ast.BoolLit(_, _) ||
            property.value is @ast.NullLit(_) ||
            property.value is @ast.UndefinedLit(_) ||
            property.value is @ast.Ident(_, _) ||
            property.value is @ast.ThisExpr(_)
          ) else {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn constructor_recursion_terminals_match(
  left : ConstructorRecursionTerminal,
  right : ConstructorRecursionTerminal,
) -> Bool {
  match (left, right) {
    (ConstructorRecursionNormal, ConstructorRecursionNormal)
    | (ConstructorRecursionReturn, ConstructorRecursionReturn)
    | (ConstructorRecursionThrow, ConstructorRecursionThrow) => true
    _ => false
  }
}

///|
#warnings("-unused_field")
priv struct ConstructorRecursionPlan {
  functions : Array[ConstructorRecursionFunctionPlan]
  root_name : String
  parameter : String
  value_property : String
  initial_argument : Double
  root_member_loc : @token.Loc
}

///|
fn ConstructorRecursionPlan::ConstructorRecursionPlan(
  functions~ : Array[ConstructorRecursionFunctionPlan],
  root_name~ : String,
  parameter~ : String,
  value_property~ : String,
  initial_argument~ : Double,
  root_member_loc~ : @token.Loc,
) -> ConstructorRecursionPlan {
  {
    functions: functions.copy(),
    root_name,
    parameter,
    value_property,
    initial_argument,
    root_member_loc,
  }
}

///|
fn constructor_recursion_function_plan(
  stmt : @ast.Stmt,
) -> ConstructorRecursionFunctionPlan? {
  match stmt {
    @ast.FuncDecl(name, params, body, _, _) => {
      guard numeric_recursion_identifier_is_safe(name) &&
        params.length() == 1 &&
        numeric_recursion_identifier_is_safe(params[0]) &&
        params[0] != name &&
        (body.length() == 2 || body.length() == 3) else {
        return None
      }
      let parameter = params[0]
      let (value_property, value_loc) = match body[0] {
        @ast.ExprStmt(
          @ast.MemberAssign(
            @ast.ThisExpr(_),
            property,
            @ast.Ident(value_parameter, value_loc),
            _
          ),
          _
        ) if value_parameter == parameter => (property, value_loc)
        _ => return None
      }
      ignore(value_loc)
      let (
        child_property,
        recursive_callee,
        condition_loc,
        subtract_loc,
        construct_loc,
      ) = match body[1] {
        @ast.IfStmt(
          @ast.Binary(
            @ast.Gt,
            @ast.Ident(condition_parameter, _),
            @ast.NumberLit(base, @token.LexForm::LexNormal, condition_loc),
            _
          ),
          @ast.Block(
            [
              @ast.ExprStmt(
                @ast.MemberAssign(
                  @ast.ThisExpr(_),
                  child_property,
                  @ast.NewExpr(
                    @ast.Ident(recursive_callee, _),
                    [
                      @ast.Binary(
                        @ast.Sub,
                        @ast.Ident(subtract_parameter, _),
                        @ast.NumberLit(
                          decrement,
                          @token.LexForm::LexNormal,
                          subtract_loc
                        ),
                        _
                      ),
                    ],
                    construct_loc
                  ),
                  _
                ),
                _
              ),
            ],
            _
          ),
          None,
          _
        ) if condition_parameter == parameter &&
          subtract_parameter == parameter &&
          base == 0.0 &&
          decrement == 1.0 &&
          numeric_recursion_identifier_is_safe(recursive_callee) =>
          (
            child_property, recursive_callee, condition_loc, subtract_loc, construct_loc,
          )
        _ => return None
      }
      guard child_property != value_property else { return None }
      let terminal = if body.length() == 2 {
        ConstructorRecursionNormal
      } else {
        match body[2] {
          @ast.ReturnStmt(Some(expr), _) if constructor_recursion_terminal_expr_is_admissible(
              expr,
            ) => ConstructorRecursionReturn
          @ast.ReturnStmt(None, _) => ConstructorRecursionReturn
          @ast.ThrowStmt(expr, _) if constructor_recursion_terminal_expr_is_admissible(
              expr,
            ) => ConstructorRecursionThrow
          _ => return None
        }
      }
      Some(
        ConstructorRecursionFunctionPlan(
          name~,
          parameter~,
          value_property~,
          child_property~,
          recursive_callee~,
          condition_loc~,
          subtract_loc~,
          construct_loc~,
          terminal~,
        ),
      )
    }
    _ => None
  }
}

///|
fn constructor_recursion_plan_is_closed(
  functions : Array[ConstructorRecursionFunctionPlan],
  root_name : String,
) -> Bool {
  guard functions.length() == 1 || functions.length() == 2 else { return false }
  guard functions[0].name == root_name else { return false }
  guard functions[0].recursive_callee == root_name || functions.length() == 2 else {
    return false
  }
  if functions.length() == 2 {
    guard functions[1].name != functions[0].name else { return false }
    guard functions[0].recursive_callee == functions[1].name &&
      functions[1].recursive_callee == functions[0].name else {
      return false
    }
    guard functions[0].parameter == functions[1].parameter &&
      functions[0].value_property == functions[1].value_property &&
      functions[0].child_property == functions[1].child_property &&
      constructor_recursion_terminals_match(
        functions[0].terminal,
        functions[1].terminal,
      ) else {
      return false
    }
  }
  true
}

///|
#warnings("-unused_value")
fn classify_constructor_recursion_program(
  stmts : Array[@ast.Stmt],
) -> ConstructorRecursionPlan? {
  guard stmts.length() == 2 || stmts.length() == 3 else { return None }
  let declaration_count = stmts.length() - 1
  let functions : Array[ConstructorRecursionFunctionPlan] = []
  for index in 0..<declaration_count {
    match constructor_recursion_function_plan(stmts[index]) {
      Some(plan) => functions.push(plan)
      None => return None
    }
  }
  let (root_name, initial_argument, root_member_loc) = match
    stmts[declaration_count] {
    @ast.ExprStmt(
      @ast.Member(
        @ast.NewExpr(
          @ast.Ident(name, _),
          [@ast.NumberLit(value, @token.LexForm::LexNormal, _)],
          _
        ),
        property,
        root_member_loc
      ),
      _
    ) => (name, value, root_member_loc)
    _ => return None
  }
  guard constructor_recursion_plan_is_closed(functions, root_name) else {
    return None
  }
  let parameter = functions[0].parameter
  let value_property = functions[0].value_property
  let root_property = match stmts[declaration_count] {
    @ast.ExprStmt(@ast.Member(@ast.NewExpr(_, _, _), property, _), _) =>
      property
    _ => ""
  }
  guard value_property == root_property else { return None }
  Some(
    ConstructorRecursionPlan(
      functions~,
      root_name~,
      parameter~,
      value_property~,
      initial_argument~,
      root_member_loc~,
    ),
  )
}

///|
fn constructor_recursion_root_statement_matches(
  plan : ConstructorRecursionPlan,
  index : Int,
  stmt : @ast.Stmt,
) -> Bool {
  guard index >= 0 && index < plan.functions.length() else { return false }
  match stmt {
    @ast.FuncDecl(name, params, body, _, _) =>
      name == plan.functions[index].name &&
      params.length() == 1 &&
      params[0] == plan.functions[index].parameter &&
      body.length() ==
      (match plan.functions[index].terminal {
        ConstructorRecursionNormal => 2
        ConstructorRecursionReturn | ConstructorRecursionThrow => 3
      })
    _ => false
  }
}

///|
fn constructor_recursion_root_expression_matches(
  plan : ConstructorRecursionPlan,
  stmt : @ast.Stmt,
) -> Bool {
  let index = plan.functions.length()
  match stmt {
    @ast.ExprStmt(
      @ast.Member(
        @ast.NewExpr(
          @ast.Ident(name, _),
          [@ast.NumberLit(value, @token.LexForm::LexNormal, _)],
          _
        ),
        property,
        root_member_loc
      ),
      _
    ) =>
      name == plan.root_name &&
      property == plan.value_property &&
      value == plan.initial_argument &&
      root_member_loc == plan.root_member_loc &&
      index >= 0
    _ => false
  }
}

///|
fn constructor_recursion_body_statement_matches(
  plan : ConstructorRecursionPlan,
  function_index : Int,
  index : Int,
  stmt : @ast.Stmt,
) -> Bool {
  guard function_index >= 0 && function_index < plan.functions.length() else {
    return false
  }
  match index {
    0 =>
      match stmt {
        @ast.ExprStmt(
          @ast.MemberAssign(
            @ast.ThisExpr(_),
            property,
            @ast.Ident(parameter, _),
            _
          ),
          _
        ) =>
          property == plan.functions[function_index].value_property &&
          parameter == plan.functions[function_index].parameter
        _ => false
      }
    1 =>
      match stmt {
        @ast.IfStmt(
          @ast.Binary(
            @ast.Gt,
            @ast.Ident(condition_parameter, _),
            @ast.NumberLit(base, @token.LexForm::LexNormal, _),
            _
          ),
          @ast.Block(
            [
              @ast.ExprStmt(
                @ast.MemberAssign(
                  @ast.ThisExpr(_),
                  child_property,
                  @ast.NewExpr(
                    @ast.Ident(recursive_callee, _),
                    [
                      @ast.Binary(
                        @ast.Sub,
                        @ast.Ident(subtract_parameter, _),
                        @ast.NumberLit(decrement, @token.LexForm::LexNormal, _),
                        _
                      ),
                    ],
                    _
                  ),
                  _
                ),
                _
              ),
            ],
            _
          ),
          None,
          _
        ) =>
          condition_parameter == plan.functions[function_index].parameter &&
          base == 0.0 &&
          child_property == plan.functions[function_index].child_property &&
          recursive_callee == plan.functions[function_index].recursive_callee &&
          subtract_parameter == plan.functions[function_index].parameter &&
          decrement == 1.0
        _ => false
      }
    2 =>
      match (plan.functions[function_index].terminal, stmt) {
        (ConstructorRecursionReturn, @ast.ReturnStmt(_, _)) => true
        (ConstructorRecursionThrow, @ast.ThrowStmt(_, _)) => true
        _ => false
      }
    _ => false
  }
}
