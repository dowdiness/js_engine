// Closed, effect-free admission for the exact ordinary UserFunc direct-return
// recursion slice. Runtime identity and provenance are sealed separately.

///|
const DIRECT_RETURN_RECURSION_INITIAL_ARGUMENT = 256.0

///|
const DIRECT_RETURN_RECURSION_BASE_ARGUMENT = 0.0

///|
const DIRECT_RETURN_RECURSION_STEP = 1.0

///|
const DIRECT_RETURN_MAX_LEAF_ARGUMENTS = 2

///|
priv enum DirectReturnClosedLiteral {
  DirectReturnClosedNumber(Double)
  DirectReturnClosedString(String)
  DirectReturnClosedBool(Bool)
  DirectReturnClosedNull
  DirectReturnClosedUndefined
}

///|
priv enum DirectReturnBaseCompletion {
  DirectReturnBaseValue(DirectReturnClosedLiteral)
  DirectReturnBaseThrow(DirectReturnClosedLiteral)
  DirectReturnBaseLeafCall
}

///|
priv enum DirectReturnLeafArgumentSource {
  DirectReturnLeafClosedArgument(DirectReturnClosedArgument)
  DirectReturnLeafRecursiveResult(@token.Loc)
}

///|
priv struct DirectReturnLeafCallPlan {
  callee_name : String
  call_loc : @token.Loc
  argument_sources : Array[DirectReturnLeafArgumentSource]
}

///|
fn DirectReturnLeafCallPlan::DirectReturnLeafCallPlan(
  callee_name~ : String,
  call_loc~ : @token.Loc,
  argument_sources~ : Array[DirectReturnLeafArgumentSource],
) -> DirectReturnLeafCallPlan {
  { callee_name, call_loc, argument_sources: argument_sources.copy() }
}

///|
priv enum DirectReturnRecursiveCompletion {
  DirectReturnRecursiveSelfCall
  DirectReturnRecursiveResultFedLeafCall
}

///|
priv struct DirectReturnClosedArgument {
  literal : DirectReturnClosedLiteral
  loc : @token.Loc
}

///|
fn DirectReturnClosedArgument::DirectReturnClosedArgument(
  literal~ : DirectReturnClosedLiteral,
  loc~ : @token.Loc,
) -> DirectReturnClosedArgument {
  { literal, loc }
}

///|
priv struct DirectReturnBoundParameter {
  name : String
  index : Int
  loc : @token.Loc
}

///|
fn DirectReturnBoundParameter::DirectReturnBoundParameter(
  name~ : String,
  index~ : Int,
  loc~ : @token.Loc,
) -> DirectReturnBoundParameter {
  { name, index, loc }
}

///|
priv enum DirectReturnLeafCompletion {
  DirectReturnLeafClosedValue(DirectReturnClosedLiteral)
  DirectReturnLeafClosedThrow(DirectReturnClosedLiteral)
  DirectReturnLeafParameterValue(DirectReturnBoundParameter)
  DirectReturnLeafParameterThrow(DirectReturnBoundParameter)
}

///|
priv struct DirectReturnLeafSyntax {
  name : String
  parameters : Array[String]
  leaf_completion : DirectReturnLeafCompletion
  completion_loc : @token.Loc
}

///|
fn DirectReturnLeafSyntax::DirectReturnLeafSyntax(
  name~ : String,
  parameters~ : Array[String],
  leaf_completion~ : DirectReturnLeafCompletion,
  completion_loc~ : @token.Loc,
) -> DirectReturnLeafSyntax {
  { name, parameters: parameters.copy(), leaf_completion, completion_loc }
}

///|
priv struct DirectReturnFunctionSyntax {
  name : String
  parameter : String
  recursive_callee : String
  base_condition_loc : @token.Loc
  base_literal_loc : @token.Loc
  recursive_call_loc : @token.Loc
  recursive_subtract_loc : @token.Loc
  base_completion : DirectReturnBaseCompletion
  recursive_completion : DirectReturnRecursiveCompletion
  leaf_call : DirectReturnLeafCallPlan?
}

///|
fn DirectReturnFunctionSyntax::DirectReturnFunctionSyntax(
  name~ : String,
  parameter~ : String,
  recursive_callee~ : String,
  base_condition_loc~ : @token.Loc,
  base_literal_loc~ : @token.Loc,
  recursive_call_loc~ : @token.Loc,
  recursive_subtract_loc~ : @token.Loc,
  base_completion~ : DirectReturnBaseCompletion,
  recursive_completion~ : DirectReturnRecursiveCompletion,
  leaf_call~ : DirectReturnLeafCallPlan?,
) -> DirectReturnFunctionSyntax {
  {
    name,
    parameter,
    recursive_callee,
    base_condition_loc,
    base_literal_loc,
    recursive_call_loc,
    recursive_subtract_loc,
    base_completion,
    recursive_completion,
    leaf_call,
  }
}

///|
priv struct DirectReturnFunctionPlan {
  syntax : DirectReturnFunctionSyntax
  declaration_index : Int
}

///|
priv struct DirectReturnLeafPlan {
  syntax : DirectReturnLeafSyntax
  declaration_index : Int
}

///|
fn DirectReturnLeafPlan::DirectReturnLeafPlan(
  syntax~ : DirectReturnLeafSyntax,
  declaration_index~ : Int,
) -> DirectReturnLeafPlan {
  { syntax, declaration_index }
}

///|
fn DirectReturnFunctionPlan::DirectReturnFunctionPlan(
  syntax~ : DirectReturnFunctionSyntax,
  declaration_index~ : Int,
) -> DirectReturnFunctionPlan {
  { syntax, declaration_index }
}

///|
priv struct DirectReturnRecursionPlan {
  entry : DirectReturnFunctionPlan
  leaf : DirectReturnLeafPlan?
  initial_argument : Double
  root_call_loc : @token.Loc
}

///|
fn DirectReturnRecursionPlan::DirectReturnRecursionPlan(
  entry~ : DirectReturnFunctionPlan,
  leaf? : DirectReturnLeafPlan? = None,
  initial_argument~ : Double,
  root_call_loc~ : @token.Loc,
) -> DirectReturnRecursionPlan {
  { entry, leaf, initial_argument, root_call_loc }
}

///|
fn direct_return_identifier_is_safe(name : String) -> Bool {
  name != "eval" && name != "arguments"
}

///|
fn classify_direct_return_closed_literal(
  expr : @ast.Expr,
) -> (DirectReturnClosedLiteral, @token.Loc)? {
  match expr {
    @ast.NumberLit(value, @token.LexForm::LexNormal, loc) =>
      Some((DirectReturnClosedNumber(value), loc))
    @ast.StringLit(value, _, @token.LexForm::LexNormal, loc) =>
      Some((DirectReturnClosedString(value), loc))
    @ast.BoolLit(value, loc) => Some((DirectReturnClosedBool(value), loc))
    @ast.NullLit(loc) => Some((DirectReturnClosedNull, loc))
    @ast.UndefinedLit(loc) => Some((DirectReturnClosedUndefined, loc))
    _ => None
  }
}

///|
fn classify_direct_return_closed_arguments(
  args : Array[@ast.Expr],
) -> Array[DirectReturnClosedArgument]? {
  guard args.length() <= DIRECT_RETURN_MAX_LEAF_ARGUMENTS else { return None }
  let arguments : Array[DirectReturnClosedArgument] = []
  for expr in args {
    guard classify_direct_return_closed_literal(expr) is Some((literal, loc)) else {
      return None
    }
    arguments.push(DirectReturnClosedArgument(literal~, loc~))
  }
  Some(arguments)
}

///|
fn direct_return_leaf_parameters_are_safe(
  function_name : String,
  params : Array[String],
) -> Bool {
  guard params.length() <= DIRECT_RETURN_MAX_LEAF_ARGUMENTS else {
    return false
  }
  for i, parameter in params {
    guard direct_return_identifier_is_safe(parameter) &&
      parameter != function_name else {
      return false
    }
    for previous in 0..<i {
      guard params[previous] != parameter else { return false }
    }
  }
  true
}

///|
fn direct_return_parameter_ref(
  params : Array[String],
  name : String,
  loc : @token.Loc,
) -> DirectReturnBoundParameter? {
  for index, parameter in params {
    if parameter == name {
      return Some(DirectReturnBoundParameter(name~, index~, loc~))
    }
  }
  None
}

///|
fn classify_direct_return_function_syntax(
  name : String,
  params : Array[String],
  body : Array[@ast.Stmt],
) -> DirectReturnFunctionSyntax? {
  guard direct_return_identifier_is_safe(name) &&
    params.length() == 1 &&
    body.length() == 2 else {
    return None
  }
  let parameter = params[0]
  guard direct_return_identifier_is_safe(parameter) && parameter != name else {
    return None
  }
  let (base_condition_loc, base_literal_loc, base_completion, base_leaf_call) = match
    body[0] {
    @ast.IfStmt(
      @ast.Binary(
        @ast.EqEqEq,
        @ast.Ident(condition_parameter, _),
        @ast.NumberLit(base, @token.LexForm::LexNormal, _),
        condition_loc
      ),
      base_stmt,
      None,
      _
    ) if condition_parameter == parameter &&
      base == DIRECT_RETURN_RECURSION_BASE_ARGUMENT => {
      let completion = match base_stmt {
        @ast.ReturnStmt(Some(expr), _) =>
          match classify_direct_return_closed_literal(expr) {
            Some((literal, literal_loc)) =>
              (condition_loc, literal_loc, DirectReturnBaseValue(literal), None)
            None =>
              match expr {
                @ast.Call(@ast.Ident(leaf_name, _), args, leaf_call_loc) if direct_return_identifier_is_safe(
                    leaf_name,
                  ) => {
                  let arguments = match
                    classify_direct_return_closed_arguments(args) {
                    Some(arguments) => arguments
                    None => return None
                  }
                  let argument_sources = arguments.map(argument => {
                    DirectReturnLeafClosedArgument(argument)
                  })
                  (
                    condition_loc,
                    leaf_call_loc,
                    DirectReturnBaseLeafCall,
                    Some(
                      DirectReturnLeafCallPlan(
                        callee_name=leaf_name,
                        call_loc=leaf_call_loc,
                        argument_sources~,
                      ),
                    ),
                  )
                }
                _ => return None
              }
          }
        @ast.ThrowStmt(expr, _) =>
          match classify_direct_return_closed_literal(expr) {
            Some((literal, literal_loc)) =>
              (condition_loc, literal_loc, DirectReturnBaseThrow(literal), None)
            None => return None
          }
        _ => return None
      }
      completion
    }
    _ => return None
  }
  let (
    recursive_callee,
    recursive_call_loc,
    recursive_subtract_loc,
    recursive_completion,
    recursive_leaf_call,
  ) = match body[1] {
    @ast.ReturnStmt(
      Some(
        @ast.Call(
          @ast.Ident(callee_name, _),
          [
            @ast.Binary(
              @ast.Sub,
              @ast.Ident(step_parameter, _),
              @ast.NumberLit(decrement, @token.LexForm::LexNormal, subtract_loc),
              _
            ),
          ],
          call_loc
        )
      ),
      _
    ) if direct_return_identifier_is_safe(callee_name) &&
      step_parameter == parameter &&
      decrement == DIRECT_RETURN_RECURSION_STEP &&
      callee_name == name =>
      (callee_name, call_loc, subtract_loc, DirectReturnRecursiveSelfCall, None)
    @ast.ReturnStmt(
      Some(
        @ast.Call(
          @ast.Ident(helper_name, _),
          [
            @ast.Call(
              @ast.Ident(callee_name, _),
              [
                @ast.Binary(
                  @ast.Sub,
                  @ast.Ident(step_parameter, _),
                  @ast.NumberLit(
                    decrement,
                    @token.LexForm::LexNormal,
                    subtract_loc
                  ),
                  _
                ),
              ],
              recursive_call_loc
            ),
          ],
          helper_call_loc
        )
      ),
      _
    ) if direct_return_identifier_is_safe(helper_name) &&
      direct_return_identifier_is_safe(callee_name) &&
      helper_name != name &&
      helper_name != parameter &&
      callee_name == name &&
      step_parameter == parameter &&
      decrement == DIRECT_RETURN_RECURSION_STEP =>
      (
        callee_name,
        recursive_call_loc,
        subtract_loc,
        DirectReturnRecursiveResultFedLeafCall,
        Some(
          DirectReturnLeafCallPlan(
            callee_name=helper_name,
            call_loc=helper_call_loc,
            argument_sources=[
              DirectReturnLeafRecursiveResult(recursive_call_loc),
            ],
          ),
        ),
      )
    _ => return None
  }
  DirectReturnFunctionSyntax(
    name~,
    parameter~,
    recursive_callee~,
    base_condition_loc~,
    base_literal_loc~,
    recursive_call_loc~,
    recursive_subtract_loc~,
    base_completion~,
    recursive_completion~,
    leaf_call=match (base_leaf_call, recursive_leaf_call) {
      (Some(base), None) => Some(base)
      (None, Some(recursive)) => Some(recursive)
      (None, None) => None
      (Some(_), Some(_)) => return None
    },
  )
  |> Some
}

///|
fn classify_direct_return_leaf_syntax(
  name : String,
  params : Array[String],
  body : Array[@ast.Stmt],
) -> DirectReturnLeafSyntax? {
  guard direct_return_identifier_is_safe(name) && body.length() == 1 else {
    return None
  }
  guard direct_return_leaf_parameters_are_safe(name, params) else {
    return None
  }
  let (leaf_completion, completion_loc) = match body[0] {
    @ast.ReturnStmt(Some(expr), _) =>
      match (params, classify_direct_return_closed_literal(expr), expr) {
        ([], Some((literal, loc)), _) =>
          (DirectReturnLeafClosedValue(literal), loc)
        ([_, ..], None, @ast.Ident(actual, loc)) =>
          match direct_return_parameter_ref(params, actual, loc) {
            Some(parameter) => (DirectReturnLeafParameterValue(parameter), loc)
            None => return None
          }
        _ => return None
      }
    @ast.ThrowStmt(expr, _) =>
      match (params, classify_direct_return_closed_literal(expr), expr) {
        ([], Some((literal, loc)), _) =>
          (DirectReturnLeafClosedThrow(literal), loc)
        ([_, ..], None, @ast.Ident(actual, loc)) =>
          match direct_return_parameter_ref(params, actual, loc) {
            Some(parameter) => (DirectReturnLeafParameterThrow(parameter), loc)
            None => return None
          }
        _ => return None
      }
    _ => return None
  }
  Some(
    DirectReturnLeafSyntax(
      name~,
      parameters=params,
      leaf_completion~,
      completion_loc~,
    ),
  )
}

///|
fn classify_direct_return_leaf(
  stmt : @ast.Stmt,
  declaration_index : Int,
) -> DirectReturnLeafPlan? {
  match stmt {
    @ast.FuncDecl(name, params, body, _, _) =>
      match classify_direct_return_leaf_syntax(name, params, body) {
        Some(syntax) => Some(DirectReturnLeafPlan(syntax~, declaration_index~))
        None => None
      }
    _ => None
  }
}

///|
fn classify_direct_return_function(
  stmt : @ast.Stmt,
  declaration_index : Int,
) -> DirectReturnFunctionPlan? {
  match stmt {
    @ast.FuncDecl(name, params, body, _, _) =>
      match classify_direct_return_function_syntax(name, params, body) {
        Some(syntax) =>
          Some(DirectReturnFunctionPlan(syntax~, declaration_index~))
        None => None
      }
    _ => None
  }
}

///|
fn classify_direct_return_recursion_program(
  stmts : Array[@ast.Stmt],
) -> DirectReturnRecursionPlan? {
  let (entry, leaf, root_index) = match stmts.length() {
    2 =>
      match classify_direct_return_function(stmts[0], 0) {
        Some(entry) => {
          guard entry.syntax.base_completion
            is (DirectReturnBaseValue(_) | DirectReturnBaseThrow(_)) &&
            entry.syntax.recursive_completion is DirectReturnRecursiveSelfCall &&
            entry.syntax.leaf_call is None else {
            return None
          }
          (entry, None, 1)
        }
        None => return None
      }
    3 => {
      guard classify_direct_return_leaf(stmts[0], 0) is Some(leaf) &&
        classify_direct_return_function(stmts[1], 1) is Some(entry) else {
        return None
      }
      guard entry.syntax.leaf_call is Some(leaf_call) &&
        leaf_call.callee_name == leaf.syntax.name &&
        leaf.syntax.name != entry.syntax.name &&
        leaf.syntax.name != entry.syntax.parameter &&
        leaf.syntax.parameters.length() == leaf_call.argument_sources.length() else {
        return None
      }
      match entry.syntax.base_completion {
        DirectReturnBaseLeafCall => {
          guard entry.syntax.recursive_completion
            is DirectReturnRecursiveSelfCall else {
            return None
          }
          for source in leaf_call.argument_sources {
            guard source is DirectReturnLeafClosedArgument(_) else {
              return None
            }
          }
        }
        DirectReturnBaseValue(_) | DirectReturnBaseThrow(_) => {
          guard entry.syntax.recursive_completion
            is DirectReturnRecursiveResultFedLeafCall else {
            return None
          }
        }
      }
      (entry, Some(leaf), 2)
    }
    _ => return None
  }
  match stmts[root_index] {
    @ast.ExprStmt(
      @ast.Call(
        @ast.Ident(root_name, _),
        [@ast.NumberLit(argument, @token.LexForm::LexNormal, _)],
        root_call_loc
      ),
      _
    ) if root_name == entry.syntax.name &&
      argument == DIRECT_RETURN_RECURSION_INITIAL_ARGUMENT =>
      Some(
        DirectReturnRecursionPlan(
          entry~,
          leaf~,
          initial_argument=argument,
          root_call_loc~,
        ),
      )
    _ => None
  }
}

///|
fn direct_return_closed_literal_value(
  literal : DirectReturnClosedLiteral,
) -> Value {
  match literal {
    DirectReturnClosedNumber(value) => Number(value)
    DirectReturnClosedString(value) => String_(value)
    DirectReturnClosedBool(value) => Bool(value)
    DirectReturnClosedNull => Null
    DirectReturnClosedUndefined => Undefined
  }
}
