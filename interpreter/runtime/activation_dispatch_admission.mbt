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
priv struct NumericRecursionFunctionSyntax {
  name : String
  parameter : String
  recursive_callee : String
  expression_recipe : NumericRecursionExpressionRecipe
}

///|
fn NumericRecursionFunctionSyntax::NumericRecursionFunctionSyntax(
  name~ : String,
  parameter~ : String,
  recursive_callee~ : String,
  expression_recipe~ : NumericRecursionExpressionRecipe,
) -> NumericRecursionFunctionSyntax {
  { name, parameter, recursive_callee, expression_recipe }
}

///|
#warnings("-unused_field")
priv struct NumericRecursionFunctionPlan {
  syntax : NumericRecursionFunctionSyntax
  declaration_index : Int
}

///|
fn NumericRecursionFunctionPlan::NumericRecursionFunctionPlan(
  syntax~ : NumericRecursionFunctionSyntax,
  declaration_index~ : Int,
) -> NumericRecursionFunctionPlan {
  { syntax, declaration_index }
}

///|
#warnings("-unused_constructor")
priv enum NumericRecursionRootCallCompletion {
  NumericRecursionRootCallValue
  NumericRecursionRootCallThrow
}

///|
#warnings("-unused_constructor-unused_field")
priv enum NumericRecursionClosedBodyRecipe {
  NumericRecursionClosedBodyEmpty
  NumericRecursionClosedNumberValue(Double)
  NumericRecursionClosedNumberThrow(Double)
  NumericRecursionClosedBindingValue
  NumericRecursionClosedBindingThrow
}

///|
#warnings("-unused_constructor-unused_field")
priv enum NumericRecursionCatchRecipe {
  NumericRecursionNoCatch
  NumericRecursionCatch(String?, NumericRecursionClosedBodyRecipe)
}

///|
#warnings("-unused_constructor-unused_field")
priv enum NumericRecursionFinalizerRecipe {
  NumericRecursionNoFinalizer
  NumericRecursionFinalizer(NumericRecursionClosedBodyRecipe)
}

///|
#warnings("-unused_field")
priv struct NumericRecursionProtectedRootRecipe {
  try_completion : NumericRecursionRootCallCompletion
  catch_recipe : NumericRecursionCatchRecipe
  finalizer_recipe : NumericRecursionFinalizerRecipe
}

///|
fn NumericRecursionProtectedRootRecipe::NumericRecursionProtectedRootRecipe(
  try_completion~ : NumericRecursionRootCallCompletion,
  catch_recipe~ : NumericRecursionCatchRecipe,
  finalizer_recipe~ : NumericRecursionFinalizerRecipe,
) -> NumericRecursionProtectedRootRecipe {
  { try_completion, catch_recipe, finalizer_recipe }
}

///|
#warnings("-unused_constructor-unused_field")
priv enum NumericRecursionRootControlRecipe {
  NumericRecursionDirectRoot
  NumericRecursionProtectedRoot(NumericRecursionProtectedRootRecipe)
}

///|
#warnings("-unused_field")
priv struct NumericRecursionPlan {
  entry : NumericRecursionFunctionPlan
  peer : NumericRecursionFunctionPlan?
  initial_argument : Double
  root_call_loc : @token.Loc
  root_control : NumericRecursionRootControlRecipe
}

///|
fn NumericRecursionPlan::NumericRecursionPlan(
  entry~ : NumericRecursionFunctionPlan,
  peer~ : NumericRecursionFunctionPlan?,
  initial_argument~ : Double,
  root_call_loc~ : @token.Loc,
  root_control~ : NumericRecursionRootControlRecipe,
) -> NumericRecursionPlan {
  { entry, peer, initial_argument, root_call_loc, root_control }
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
          syntax=NumericRecursionFunctionSyntax(
            name~,
            parameter~,
            recursive_callee=step.recursive_callee,
            expression_recipe~,
          ),
          declaration_index~,
        ),
      )
    }
    _ => None
  }
}

///|
fn classify_numeric_recursion_root(
  stmt : @ast.Stmt,
) -> (String, Double, @token.Loc, NumericRecursionRootControlRecipe)? {
  match stmt {
    @ast.ExprStmt(@ast.Call(@ast.Ident(entry_name, _), args, root_call_loc), _) => {
      guard args.length() == 1 else { return None }
      match args[0] {
        @ast.NumberLit(initial_argument, lex_form, _) if initial_argument ==
          NUMERIC_RECURSION_INITIAL_ARGUMENT &&
          lex_form == @token.LexForm::LexNormal =>
          Some(
            (
              entry_name,
              initial_argument,
              root_call_loc,
              NumericRecursionDirectRoot,
            ),
          )
        _ => None
      }
    }
    @ast.TryCatchStmt(try_body, catch_parameter, catch_body, finalizer_body, _) =>
      classify_numeric_recursion_protected_root(
        try_body, catch_parameter, catch_body, finalizer_body,
      )
    _ => None
  }
}

///|
fn classify_numeric_recursion_root_call(
  expr : @ast.Expr,
) -> (String, Double, @token.Loc)? {
  match expr {
    @ast.Call(@ast.Ident(entry_name, _), args, root_call_loc) => {
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
fn classify_numeric_recursion_closed_body(
  body : Array[@ast.Stmt],
  binding : String?,
) -> NumericRecursionClosedBodyRecipe? {
  match body.length() {
    0 => Some(NumericRecursionClosedBodyEmpty)
    1 =>
      match body[0] {
        @ast.ExprStmt(@ast.NumberLit(value, lex_form, _), _) =>
          if lex_form == @token.LexForm::LexNormal {
            Some(NumericRecursionClosedNumberValue(value))
          } else {
            None
          }
        @ast.ThrowStmt(@ast.NumberLit(value, lex_form, _), _) =>
          if lex_form == @token.LexForm::LexNormal {
            Some(NumericRecursionClosedNumberThrow(value))
          } else {
            None
          }
        @ast.ExprStmt(@ast.Ident(name, _), _) =>
          match binding {
            Some(expected) if name == expected =>
              Some(NumericRecursionClosedBindingValue)
            _ => None
          }
        @ast.ThrowStmt(@ast.Ident(name, _), _) =>
          match binding {
            Some(expected) if name == expected =>
              Some(NumericRecursionClosedBindingThrow)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn classify_numeric_recursion_catch(
  parameter : @ast.Pattern?,
  body : Array[@ast.Stmt]?,
) -> NumericRecursionCatchRecipe? {
  match (parameter, body) {
    (None, None) => Some(NumericRecursionNoCatch)
    (None, Some(stmts)) =>
      match classify_numeric_recursion_closed_body(stmts, None) {
        Some(
          NumericRecursionClosedBodyEmpty
          | NumericRecursionClosedNumberValue(_)
          | NumericRecursionClosedNumberThrow(_) as recipe
        ) => Some(NumericRecursionCatch(None, recipe))
        _ => None
      }
    (Some(@ast.IdentPat(name)), Some(stmts)) => {
      guard numeric_recursion_identifier_is_safe(name) else { return None }
      match classify_numeric_recursion_closed_body(stmts, Some(name)) {
        Some(
          NumericRecursionClosedBodyEmpty
          | NumericRecursionClosedBindingValue
          | NumericRecursionClosedBindingThrow as recipe
        ) => Some(NumericRecursionCatch(Some(name), recipe))
        _ => None
      }
    }
    _ => None
  }
}

///|
fn classify_numeric_recursion_finalizer(
  body : Array[@ast.Stmt]?,
) -> NumericRecursionFinalizerRecipe? {
  match body {
    None => Some(NumericRecursionNoFinalizer)
    Some(stmts) =>
      match classify_numeric_recursion_closed_body(stmts, None) {
        Some(
          NumericRecursionClosedBodyEmpty
          | NumericRecursionClosedNumberValue(_)
          | NumericRecursionClosedNumberThrow(_) as recipe
        ) => Some(NumericRecursionFinalizer(recipe))
        _ => None
      }
  }
}

///|
fn classify_numeric_recursion_protected_root(
  try_body : Array[@ast.Stmt],
  catch_parameter : @ast.Pattern?,
  catch_body : Array[@ast.Stmt]?,
  finalizer_body : Array[@ast.Stmt]?,
) -> (String, Double, @token.Loc, NumericRecursionRootControlRecipe)? {
  guard try_body.length() == 1 else { return None }
  let (entry_name, initial_argument, root_call_loc, try_completion) = match
    try_body[0] {
    @ast.ExprStmt(expr, _) =>
      match classify_numeric_recursion_root_call(expr) {
        Some((name, argument, loc)) =>
          (name, argument, loc, NumericRecursionRootCallValue)
        None => return None
      }
    @ast.ThrowStmt(expr, _) =>
      match classify_numeric_recursion_root_call(expr) {
        Some((name, argument, loc)) =>
          (name, argument, loc, NumericRecursionRootCallThrow)
        None => return None
      }
    _ => return None
  }
  guard classify_numeric_recursion_catch(catch_parameter, catch_body)
    is Some(catch_recipe) else {
    return None
  }
  guard classify_numeric_recursion_finalizer(finalizer_body)
    is Some(finalizer_recipe) else {
    return None
  }
  let has_catch = match catch_recipe {
    NumericRecursionNoCatch => false
    NumericRecursionCatch(_, _) => true
  }
  let has_finalizer = match finalizer_recipe {
    NumericRecursionNoFinalizer => false
    NumericRecursionFinalizer(_) => true
  }
  guard has_catch || has_finalizer else { return None }
  Some(
    (
      entry_name,
      initial_argument,
      root_call_loc,
      NumericRecursionProtectedRoot(
        NumericRecursionProtectedRootRecipe(
          try_completion~,
          catch_recipe~,
          finalizer_recipe~,
        ),
      ),
    ),
  )
}

///|
fn classify_self_numeric_recursion_program(
  stmts : Array[@ast.Stmt],
) -> NumericRecursionPlan? {
  guard classify_numeric_recursion_function(stmts[0], 0) is Some(entry) else {
    return None
  }
  guard classify_numeric_recursion_root(stmts[1])
    is Some((entry_name, initial_argument, root_call_loc, root_control)) else {
    return None
  }
  guard entry.syntax.recursive_callee == entry.syntax.name &&
    entry_name == entry.syntax.name else {
    return None
  }
  Some(
    NumericRecursionPlan(
      entry~,
      peer=None,
      initial_argument~,
      root_call_loc~,
      root_control~,
    ),
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
    is Some((entry_name, initial_argument, root_call_loc, root_control)) else {
    return None
  }
  guard entry.syntax.name != peer.syntax.name &&
    entry.syntax.parameter != peer.syntax.name &&
    peer.syntax.parameter != entry.syntax.name &&
    entry.syntax.recursive_callee == peer.syntax.name &&
    peer.syntax.recursive_callee == entry.syntax.name &&
    entry_name == entry.syntax.name else {
    return None
  }
  Some(
    NumericRecursionPlan(
      entry~,
      peer=Some(peer),
      initial_argument~,
      root_call_loc~,
      root_control~,
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

///|
#warnings("-unused_value")
fn numeric_recursion_plan_is_dispatchable(plan : NumericRecursionPlan) -> Bool {
  match plan.root_control {
    NumericRecursionDirectRoot | NumericRecursionProtectedRoot(_) => true
  }
}
