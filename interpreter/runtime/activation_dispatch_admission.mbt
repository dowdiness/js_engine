///|
const NUMERIC_RECURSION_BASE = 0.0

///|
const NUMERIC_RECURSION_STEP = 1.0

///|
const NUMERIC_RECURSION_INITIAL_ARGUMENT = 256.0

///|
#warnings("-unused_field")
priv struct NumericRecursionExpressionRecipe {
  base_condition_loc : @token.Loc
  recursive_add_loc : @token.Loc
  recursive_call_loc : @token.Loc
  recursive_subtract_loc : @token.Loc
}

///|
fn NumericRecursionExpressionRecipe::NumericRecursionExpressionRecipe(
  base_condition_loc~ : @token.Loc,
  recursive_add_loc~ : @token.Loc,
  recursive_call_loc~ : @token.Loc,
  recursive_subtract_loc~ : @token.Loc,
) -> NumericRecursionExpressionRecipe {
  {
    base_condition_loc,
    recursive_add_loc,
    recursive_call_loc,
    recursive_subtract_loc,
  }
}

///|
#warnings("-unused_field")
priv struct NumericRecursionFunctionPlan {
  name : String
  parameter : String
  recursive_callee : String
  declaration_index : Int
  expression_recipe : NumericRecursionExpressionRecipe
}

///|
fn NumericRecursionFunctionPlan::NumericRecursionFunctionPlan(
  name~ : String,
  parameter~ : String,
  recursive_callee~ : String,
  declaration_index~ : Int,
  expression_recipe~ : NumericRecursionExpressionRecipe,
) -> NumericRecursionFunctionPlan {
  { name, parameter, recursive_callee, declaration_index, expression_recipe }
}

///|
#warnings("-unused_field")
priv struct NumericRecursionPlan {
  entry : NumericRecursionFunctionPlan
  peer : NumericRecursionFunctionPlan?
  initial_argument : Double
  root_call_loc : @token.Loc
}

///|
fn NumericRecursionPlan::NumericRecursionPlan(
  entry~ : NumericRecursionFunctionPlan,
  peer~ : NumericRecursionFunctionPlan?,
  initial_argument~ : Double,
  root_call_loc~ : @token.Loc,
) -> NumericRecursionPlan {
  { entry, peer, initial_argument, root_call_loc }
}

///|
fn exact_numeric_recursion_number(expr : @ast.Expr, expected : Double) -> Bool {
  match expr {
    @ast.NumberLit(value, lex_form, _) =>
      value == expected && lex_form == @token.LexForm::LexNormal
    _ => false
  }
}

///|
fn numeric_recursion_identifier_is_safe(name : String) -> Bool {
  name != "eval" && name != "arguments"
}

///|
fn numeric_recursion_base_condition_loc(
  stmt : @ast.Stmt,
  parameter : String,
) -> @token.Loc? {
  match stmt {
    @ast.IfStmt(
      @ast.Binary(
        @ast.EqEqEq,
        @ast.Ident(condition_parameter, _),
        base_condition,
        base_condition_loc
      ),
      @ast.ReturnStmt(Some(base_result), _),
      None,
      _
    ) =>
      if condition_parameter == parameter &&
        exact_numeric_recursion_number(base_condition, NUMERIC_RECURSION_BASE) &&
        exact_numeric_recursion_number(base_result, NUMERIC_RECURSION_BASE) {
        Some(base_condition_loc)
      } else {
        None
      }
    _ => None
  }
}

///|
#warnings("-unused_field")
priv struct NumericRecursionStepClassification {
  recursive_callee : String
  recursive_add_loc : @token.Loc
  recursive_call_loc : @token.Loc
  recursive_subtract_loc : @token.Loc
}

///|
fn NumericRecursionStepClassification::NumericRecursionStepClassification(
  recursive_callee~ : String,
  recursive_add_loc~ : @token.Loc,
  recursive_call_loc~ : @token.Loc,
  recursive_subtract_loc~ : @token.Loc,
) -> NumericRecursionStepClassification {
  {
    recursive_callee,
    recursive_add_loc,
    recursive_call_loc,
    recursive_subtract_loc,
  }
}

///|
fn classify_numeric_recursion_step_detail(
  stmt : @ast.Stmt,
  parameter : String,
) -> NumericRecursionStepClassification? {
  match stmt {
    @ast.ReturnStmt(
      Some(
        @ast.Binary(
          @ast.Add,
          increment,
          @ast.Call(@ast.Ident(recursive_callee, _), args, recursive_call_loc),
          recursive_add_loc
        )
      ),
      _
    ) => {
      guard exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) &&
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
          Some(
            NumericRecursionStepClassification(
              recursive_callee~,
              recursive_add_loc~,
              recursive_call_loc~,
              recursive_subtract_loc~,
            ),
          )
        _ => None
      }
    }
    _ => None
  }
}

///|
fn exact_numeric_recursion_base_case(
  stmt : @ast.Stmt,
  parameter : String,
) -> Bool {
  numeric_recursion_base_condition_loc(stmt, parameter) is Some(_)
}

///|
fn classify_numeric_recursion_step(
  stmt : @ast.Stmt,
  parameter : String,
) -> String? {
  match classify_numeric_recursion_step_detail(stmt, parameter) {
    Some(detail) => Some(detail.recursive_callee)
    None => None
  }
}

///|
fn classify_numeric_recursion_function(
  stmt : @ast.Stmt,
  declaration_index : Int,
) -> NumericRecursionFunctionPlan? {
  match stmt {
    @ast.FuncDecl(name, params, body, _, _) => {
      guard numeric_recursion_identifier_is_safe(name) &&
        params.length() == 1 &&
        body.length() == 2 else {
        return None
      }
      let parameter = params[0]
      guard numeric_recursion_identifier_is_safe(parameter) && parameter != name else {
        return None
      }
      guard numeric_recursion_base_condition_loc(body[0], parameter)
        is Some(base_condition_loc) else {
        return None
      }
      guard classify_numeric_recursion_step_detail(body[1], parameter)
        is Some(step) else {
        return None
      }
      let expression_recipe = NumericRecursionExpressionRecipe(
        base_condition_loc~,
        recursive_add_loc=step.recursive_add_loc,
        recursive_call_loc=step.recursive_call_loc,
        recursive_subtract_loc=step.recursive_subtract_loc,
      )
      Some(
        NumericRecursionFunctionPlan(
          name~,
          parameter~,
          recursive_callee=step.recursive_callee,
          declaration_index~,
          expression_recipe~,
        ),
      )
    }
    _ => None
  }
}

///|
fn classify_numeric_recursion_root(
  stmt : @ast.Stmt,
) -> (String, Double, @token.Loc)? {
  match stmt {
    @ast.ExprStmt(@ast.Call(@ast.Ident(entry_name, _), args, root_call_loc), _) => {
      guard args.length() == 1 else { return None }
      match args[0] {
        @ast.NumberLit(initial_argument, lex_form, _) if initial_argument ==
          NUMERIC_RECURSION_INITIAL_ARGUMENT &&
          lex_form == @token.LexForm::LexNormal =>
          Some((entry_name, initial_argument, root_call_loc))
        _ => None
      }
    }
    _ => None
  }
}

///|
fn classify_self_numeric_recursion_program(
  stmts : Array[@ast.Stmt],
) -> NumericRecursionPlan? {
  guard classify_numeric_recursion_function(stmts[0], 0) is Some(entry) else {
    return None
  }
  guard classify_numeric_recursion_root(stmts[1])
    is Some((entry_name, initial_argument, root_call_loc)) else {
    return None
  }
  guard entry.recursive_callee == entry.name && entry_name == entry.name else {
    return None
  }
  Some(
    NumericRecursionPlan(entry~, peer=None, initial_argument~, root_call_loc~),
  )
}

///|
fn classify_mutual_numeric_recursion_program(
  stmts : Array[@ast.Stmt],
) -> NumericRecursionPlan? {
  guard classify_numeric_recursion_function(stmts[0], 0) is Some(entry) else {
    return None
  }
  guard classify_numeric_recursion_function(stmts[1], 1) is Some(peer) else {
    return None
  }
  guard classify_numeric_recursion_root(stmts[2])
    is Some((entry_name, initial_argument, root_call_loc)) else {
    return None
  }
  guard entry.name != peer.name &&
    entry.parameter != peer.name &&
    peer.parameter != entry.name &&
    entry.recursive_callee == peer.name &&
    peer.recursive_callee == entry.name &&
    entry_name == entry.name else {
    return None
  }
  Some(
    NumericRecursionPlan(
      entry~,
      peer=Some(peer),
      initial_argument~,
      root_call_loc~,
    ),
  )
}

///|
#warnings("-unused_value")
fn classify_numeric_recursion_program(
  stmts : Array[@ast.Stmt],
) -> NumericRecursionPlan? {
  match stmts.length() {
    2 => classify_self_numeric_recursion_program(stmts)
    3 => classify_mutual_numeric_recursion_program(stmts)
    _ => None
  }
}
