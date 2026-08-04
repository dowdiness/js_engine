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
/// Closed, effect-free numeric argument admitted from one normal-form Number
/// literal or one grouping around a comma tree of normal-form Number literals.
/// The shell accounts for every represented AST node through this budget.
#warnings("-unused_field")
priv struct NumericRecursionClosedArgumentRecipe {
  value : Double
  observation_count : Int
  root_loc : @token.Loc
  final_loc : @token.Loc
}

///|
fn NumericRecursionClosedArgumentRecipe::NumericRecursionClosedArgumentRecipe(
  value~ : Double,
  observation_count~ : Int,
  root_loc~ : @token.Loc,
  final_loc~ : @token.Loc,
) -> NumericRecursionClosedArgumentRecipe {
  { value, observation_count, root_loc, final_loc }
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
#warnings("-unused_constructor-unused_field")
priv enum NumericRecursionInvocationRecipe {
  NumericRecursionDirectCall
  NumericRecursionIntrinsicApplyArray
  NumericRecursionIntrinsicApplyMappedArguments
} derive(Eq)

///|
#warnings("-unused_field")
priv struct NumericRecursionFunctionSyntax {
  name : String
  parameter : String
  retained_parameter : String?
  recursive_callee : String
  invocation_recipe : NumericRecursionInvocationRecipe
  expression_recipe : NumericRecursionExpressionRecipe
  return_recipe : NumericRecursionFunctionReturnRecipe
}

///|
fn NumericRecursionFunctionSyntax::NumericRecursionFunctionSyntax(
  name~ : String,
  parameter~ : String,
  retained_parameter? : String? = None,
  recursive_callee~ : String,
  invocation_recipe? : NumericRecursionInvocationRecipe = NumericRecursionDirectCall,
  expression_recipe~ : NumericRecursionExpressionRecipe,
  return_recipe? : NumericRecursionFunctionReturnRecipe = NumericRecursionDirectReturn,
) -> NumericRecursionFunctionSyntax {
  {
    name,
    parameter,
    retained_parameter,
    recursive_callee,
    invocation_recipe,
    expression_recipe,
    return_recipe,
  }
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
priv enum NumericRecursionFunctionReturnRecipe {
  NumericRecursionDirectReturn
  NumericRecursionProtectedReturn(NumericRecursionClosedBodyRecipe)
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
  retained_argument : NumericRecursionClosedArgumentRecipe?
  root_call_loc : @token.Loc
  root_control : NumericRecursionRootControlRecipe
}

///|
fn NumericRecursionPlan::NumericRecursionPlan(
  entry~ : NumericRecursionFunctionPlan,
  peer~ : NumericRecursionFunctionPlan?,
  initial_argument~ : Double,
  retained_argument? : NumericRecursionClosedArgumentRecipe? = None,
  root_call_loc~ : @token.Loc,
  root_control~ : NumericRecursionRootControlRecipe,
) -> NumericRecursionPlan {
  {
    entry,
    peer,
    initial_argument,
    retained_argument,
    root_call_loc,
    root_control,
  }
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
  retained_parameter? : String? = None,
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
    ) => {
      let base_result_matches = match retained_parameter {
        None =>
          exact_numeric_recursion_number(base_result, NUMERIC_RECURSION_BASE)
        Some(expected) =>
          match base_result {
            @ast.Ident(actual, _) => actual == expected
            _ => false
          }
      }
      if condition_parameter == parameter &&
        exact_numeric_recursion_number(base_condition, NUMERIC_RECURSION_BASE) &&
        base_result_matches {
        Some(base_condition_loc)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
#warnings("-unused_field")
priv struct NumericRecursionStepClassification {
  recursive_callee : String
  invocation_recipe : NumericRecursionInvocationRecipe
  recursive_add_loc : @token.Loc
  recursive_call_loc : @token.Loc
  recursive_subtract_loc : @token.Loc
}

///|
fn NumericRecursionStepClassification::NumericRecursionStepClassification(
  recursive_callee~ : String,
  invocation_recipe? : NumericRecursionInvocationRecipe = NumericRecursionDirectCall,
  recursive_add_loc~ : @token.Loc,
  recursive_call_loc~ : @token.Loc,
  recursive_subtract_loc~ : @token.Loc,
) -> NumericRecursionStepClassification {
  {
    recursive_callee,
    invocation_recipe,
    recursive_add_loc,
    recursive_call_loc,
    recursive_subtract_loc,
  }
}

///|
fn classify_numeric_recursion_step_detail(
  stmt : @ast.Stmt,
  parameter : String,
  retained_parameter? : String? = None,
) -> NumericRecursionStepClassification? {
  match stmt {
    @ast.ReturnStmt(
      Some(@ast.Binary(@ast.Add, increment, call_expr, recursive_add_loc)),
      _
    ) => {
      guard exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) else {
        return None
      }
      match call_expr {
        @ast.Call(@ast.Ident(recursive_callee, _), args, recursive_call_loc) => {
          let expected_argument_count = match retained_parameter {
            None => 1
            Some(_) => 2
          }
          guard args.length() == expected_argument_count else { return None }
          let retained_argument_matches = match retained_parameter {
            None => true
            Some(expected) =>
              match args[1] {
                @ast.Ident(actual, _) => actual == expected
                _ => false
              }
          }
          guard retained_argument_matches else { return None }
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
                  invocation_recipe=NumericRecursionDirectCall,
                  recursive_add_loc~,
                  recursive_call_loc~,
                  recursive_subtract_loc~,
                ),
              )
            _ => None
          }
        }
        @ast.Call(
          @ast.Member(@ast.Ident(recursive_callee, _), "apply", _),
          args,
          recursive_call_loc
        ) => {
          guard retained_parameter is None && args.length() == 2 else {
            return None
          }
          guard args[0] is @ast.Ident("undefined", _) else { return None }
          match args[1] {
            @ast.ArrayLit(elements, _) if elements.length() == 1 =>
              match elements[0] {
                @ast.Binary(
                  @ast.Sub,
                  @ast.Ident(step_parameter, _),
                  decrement,
                  recursive_subtract_loc
                ) if step_parameter == parameter &&
                  exact_numeric_recursion_number(
                    decrement,
                    NUMERIC_RECURSION_STEP,
                  ) =>
                  Some(
                    NumericRecursionStepClassification(
                      recursive_callee~,
                      invocation_recipe=NumericRecursionIntrinsicApplyArray,
                      recursive_add_loc~,
                      recursive_call_loc~,
                      recursive_subtract_loc~,
                    ),
                  )
                _ => None
              }
            _ => None
          }
        }
        _ => None
      }
    }
    _ => None
  }
}

///|
fn classify_numeric_recursion_function_return(
  stmt : @ast.Stmt,
  parameter : String,
  retained_parameter? : String? = None,
) -> (NumericRecursionStepClassification, NumericRecursionFunctionReturnRecipe)? {
  match
    classify_numeric_recursion_step_detail(stmt, parameter, retained_parameter~) {
    Some(step) => Some((step, NumericRecursionDirectReturn))
    None =>
      match stmt {
        @ast.TryCatchStmt(try_body, None, None, Some(finalizer_body), _) => {
          guard try_body.length() == 1 &&
            classify_numeric_recursion_step_detail(
              try_body[0],
              parameter,
              retained_parameter~,
            )
            is Some(step) else {
            return None
          }
          match classify_numeric_recursion_closed_body(finalizer_body, None) {
            Some(
              NumericRecursionClosedBodyEmpty
              | NumericRecursionClosedNumberValue(_)
              | NumericRecursionClosedNumberThrow(_) as finalizer
            ) => Some((step, NumericRecursionProtectedReturn(finalizer)))
            _ => None
          }
        }
        _ => None
      }
  }
}

///|
fn classify_numeric_recursion_mapped_apply_assignment(
  stmt : @ast.Stmt,
  parameter : String,
) -> @token.Loc? {
  match stmt {
    @ast.ExprStmt(
      @ast.ComputedAssign(
        @ast.Ident("arguments", _),
        @ast.NumberLit(0.0, @token.LexForm::LexNormal, _),
        @ast.Binary(
          @ast.Sub,
          @ast.Ident(step_parameter, _),
          decrement,
          subtract_loc
        ),
        _
      ),
      _
    ) if step_parameter == parameter &&
      exact_numeric_recursion_number(decrement, NUMERIC_RECURSION_STEP) =>
      Some(subtract_loc)
    _ => None
  }
}

///|
fn classify_numeric_recursion_mapped_apply_step(
  stmt : @ast.Stmt,
  recursive_subtract_loc : @token.Loc,
) -> NumericRecursionStepClassification? {
  match stmt {
    @ast.ReturnStmt(
      Some(
        @ast.Binary(
          @ast.Add,
          increment,
          @ast.Call(
            @ast.Member(@ast.Ident(recursive_callee, _), "apply", _),
            args,
            recursive_call_loc
          ),
          recursive_add_loc
        )
      ),
      _
    ) => {
      guard exact_numeric_recursion_number(increment, NUMERIC_RECURSION_STEP) &&
        args.length() == 2 else {
        return None
      }
      guard args[0] is @ast.Ident("undefined", _) else { return None }
      guard args[1] is @ast.Ident("arguments", _) else { return None }
      Some(
        NumericRecursionStepClassification(
          recursive_callee~,
          invocation_recipe=NumericRecursionIntrinsicApplyMappedArguments,
          recursive_add_loc~,
          recursive_call_loc~,
          recursive_subtract_loc~,
        ),
      )
    }
    _ => None
  }
}

///|
fn classify_numeric_recursion_function_syntax(
  name : String,
  params : Array[String],
  body : Array[@ast.Stmt],
) -> NumericRecursionFunctionSyntax? {
  guard numeric_recursion_identifier_is_safe(name) &&
    (params.length() == 1 || params.length() == 2) &&
    (body.length() == 2 || body.length() == 3) else {
    return None
  }
  let parameter = params[0]
  let retained_parameter = if params.length() == 2 {
    Some(params[1])
  } else {
    None
  }
  guard numeric_recursion_identifier_is_safe(parameter) && parameter != name else {
    return None
  }
  guard (match retained_parameter {
    None => true
    Some(retained) =>
      numeric_recursion_identifier_is_safe(retained) &&
      retained != name &&
      retained != parameter
  }) else {
    return None
  }
  guard numeric_recursion_base_condition_loc(
      body[0],
      parameter,
      retained_parameter~,
    )
    is Some(base_condition_loc) else {
    return None
  }
  let (step, return_recipe) = if body.length() == 2 {
    match
      classify_numeric_recursion_function_return(
        body[1],
        parameter,
        retained_parameter~,
      ) {
      Some(result) => result
      None => return None
    }
  } else {
    guard params.length() == 1 && retained_parameter is None else {
      return None
    }
    let recursive_subtract_loc = match
      classify_numeric_recursion_mapped_apply_assignment(body[1], parameter) {
      Some(loc) => loc
      None => return None
    }
    match
      classify_numeric_recursion_mapped_apply_step(
        body[2],
        recursive_subtract_loc,
      ) {
      Some(step) => (step, NumericRecursionDirectReturn)
      None => return None
    }
  }
  Some(
    NumericRecursionFunctionSyntax(
      name~,
      parameter~,
      retained_parameter~,
      recursive_callee=step.recursive_callee,
      invocation_recipe=step.invocation_recipe,
      expression_recipe=NumericRecursionExpressionRecipe(
        base_condition_loc~,
        recursive_add_loc=step.recursive_add_loc,
        recursive_call_loc=step.recursive_call_loc,
        recursive_subtract_loc=step.recursive_subtract_loc,
      ),
      return_recipe~,
    ),
  )
}

///|
fn classify_numeric_recursion_function(
  stmt : @ast.Stmt,
  declaration_index : Int,
) -> NumericRecursionFunctionPlan? {
  match stmt {
    @ast.FuncDecl(name, params, body, _, _) =>
      match classify_numeric_recursion_function_syntax(name, params, body) {
        Some(syntax) =>
          Some(NumericRecursionFunctionPlan(syntax~, declaration_index~))
        None => None
      }
    _ => None
  }
}

///|
fn classify_numeric_recursion_root(
  stmt : @ast.Stmt,
) -> (
  String,
  Double,
  NumericRecursionClosedArgumentRecipe?,
  @token.Loc,
  NumericRecursionRootControlRecipe,
)? {
  match stmt {
    @ast.ExprStmt(@ast.Call(@ast.Ident(entry_name, _), args, root_call_loc), _) =>
      match classify_numeric_recursion_root_call_arguments(args) {
        Some((initial_argument, retained_argument)) =>
          Some(
            (
              entry_name,
              initial_argument,
              retained_argument,
              root_call_loc,
              NumericRecursionDirectRoot,
            ),
          )
        None => None
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
) -> (String, Double, NumericRecursionClosedArgumentRecipe?, @token.Loc)? {
  match expr {
    @ast.Call(@ast.Ident(entry_name, _), args, root_call_loc) =>
      match classify_numeric_recursion_root_call_arguments(args) {
        Some((initial_argument, retained_argument)) =>
          Some((entry_name, initial_argument, retained_argument, root_call_loc))
        None => None
      }
    _ => None
  }
}

///|
fn classify_numeric_recursion_root_call_arguments(
  args : Array[@ast.Expr],
) -> (Double, NumericRecursionClosedArgumentRecipe?)? {
  guard args.length() == 1 || args.length() == 2 else { return None }
  let initial_argument = match args[0] {
    @ast.NumberLit(value, lex_form, _) if value ==
      NUMERIC_RECURSION_INITIAL_ARGUMENT &&
      lex_form == @token.LexForm::LexNormal => value
    _ => return None
  }
  let retained_argument : NumericRecursionClosedArgumentRecipe? = if args.length() ==
    2 {
    match classify_numeric_recursion_closed_argument(args[1]) {
      Some(recipe) => Some(recipe)
      None => return None
    }
  } else {
    None
  }
  Some((initial_argument, retained_argument))
}

///|
/// Classify the closed retained argument with an explicit AST worklist. The
/// only accepted shapes are one normal-form Number literal or one Grouping
/// around a comma tree of normal-form Number literals.
fn classify_numeric_recursion_closed_argument(
  expr : @ast.Expr,
) -> NumericRecursionClosedArgumentRecipe? {
  let root_loc = match expr {
    @ast.NumberLit(_, _, loc) | @ast.Grouping(_, loc) => loc
    _ => return None
  }
  let root_is_grouping = expr is @ast.Grouping(_, _)
  let work : Array[@ast.Expr] = [expr]
  let mut grouping_count = 0
  let mut comma_count = 0
  let mut observation_count = 0
  let mut final_value = 0.0
  let mut final_loc = root_loc
  while work.pop() is Some(item) {
    observation_count = observation_count + 1
    match item {
      @ast.Grouping(inner, _) => {
        guard grouping_count == 0 && root_is_grouping else { return None }
        grouping_count = grouping_count + 1
        work.push(inner)
      }
      @ast.Comma(left, right, _) => {
        comma_count = comma_count + 1
        work.push(right)
        work.push(left)
      }
      @ast.NumberLit(value, lex_form, loc) => {
        guard lex_form == @token.LexForm::LexNormal else { return None }
        final_value = value
        final_loc = loc
      }
      _ => return None
    }
  }
  guard root_is_grouping || comma_count == 0 else { return None }
  guard !root_is_grouping || grouping_count == 1 else { return None }
  Some(
    NumericRecursionClosedArgumentRecipe(
      value=final_value,
      observation_count~,
      root_loc~,
      final_loc~,
    ),
  )
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
) -> (
  String,
  Double,
  NumericRecursionClosedArgumentRecipe?,
  @token.Loc,
  NumericRecursionRootControlRecipe,
)? {
  guard try_body.length() == 1 else { return None }
  let (
    entry_name,
    initial_argument,
    retained_argument,
    root_call_loc,
    try_completion,
  ) = match try_body[0] {
    @ast.ExprStmt(expr, _) =>
      match classify_numeric_recursion_root_call(expr) {
        Some((name, argument, retained, loc)) =>
          (name, argument, retained, loc, NumericRecursionRootCallValue)
        None => return None
      }
    @ast.ThrowStmt(expr, _) =>
      match classify_numeric_recursion_root_call(expr) {
        Some((name, argument, retained, loc)) =>
          (name, argument, retained, loc, NumericRecursionRootCallThrow)
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
      retained_argument,
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
    is Some(
      (
        entry_name,
        initial_argument,
        retained_argument,
        root_call_loc,
        root_control,
      )
    ) else {
    return None
  }
  let retained_shape_is_allowed = match
    (
      entry.syntax.retained_parameter,
      retained_argument,
      entry.syntax.return_recipe,
      root_control,
    ) {
    (None, None, _, _) => true
    (Some(_), Some(_), NumericRecursionDirectReturn, NumericRecursionDirectRoot) =>
      true
    _ => false
  }
  guard entry.syntax.recursive_callee == entry.syntax.name &&
    entry_name == entry.syntax.name &&
    retained_shape_is_allowed else {
    return None
  }
  Some(
    NumericRecursionPlan(
      entry~,
      peer=None,
      initial_argument~,
      retained_argument~,
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
    is Some(
      (
        entry_name,
        initial_argument,
        retained_argument,
        root_call_loc,
        root_control,
      )
    ) else {
    return None
  }
  guard entry.syntax.name != peer.syntax.name &&
    entry.syntax.parameter != peer.syntax.name &&
    peer.syntax.parameter != entry.syntax.name &&
    entry.syntax.recursive_callee == peer.syntax.name &&
    peer.syntax.recursive_callee == entry.syntax.name &&
    entry_name == entry.syntax.name &&
    entry.syntax.retained_parameter is None &&
    peer.syntax.retained_parameter is None &&
    retained_argument is None else {
    return None
  }
  Some(
    NumericRecursionPlan(
      entry~,
      peer=Some(peer),
      initial_argument~,
      retained_argument~,
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
