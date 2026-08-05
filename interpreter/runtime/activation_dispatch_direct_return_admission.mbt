// Closed, effect-free admission for the exact ordinary UserFunc direct-return
// recursion slice. Runtime identity and provenance are sealed separately.

///|
const DIRECT_RETURN_RECURSION_INITIAL_ARGUMENT = 256.0

///|
const DIRECT_RETURN_RECURSION_BASE_ARGUMENT = 0.0

///|
const DIRECT_RETURN_RECURSION_STEP = 1.0

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
  DirectReturnBaseLeafCall(String, @token.Loc)
}

///|
priv struct DirectReturnLeafSyntax {
  name : String
  literal_loc : @token.Loc
  completion : DirectReturnBaseCompletion
}

///|
fn DirectReturnLeafSyntax::DirectReturnLeafSyntax(
  name~ : String,
  literal_loc~ : @token.Loc,
  completion~ : DirectReturnBaseCompletion,
) -> DirectReturnLeafSyntax {
  { name, literal_loc, completion }
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
  let (base_condition_loc, base_literal_loc, base_completion) = match body[0] {
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
              (condition_loc, literal_loc, DirectReturnBaseValue(literal))
            None =>
              match expr {
                @ast.Call(@ast.Ident(leaf_name, _), [], leaf_call_loc) if direct_return_identifier_is_safe(
                    leaf_name,
                  ) =>
                  (
                    condition_loc,
                    leaf_call_loc,
                    DirectReturnBaseLeafCall(leaf_name, leaf_call_loc),
                  )
                _ => return None
              }
          }
        @ast.ThrowStmt(expr, _) =>
          match classify_direct_return_closed_literal(expr) {
            Some((literal, literal_loc)) =>
              (condition_loc, literal_loc, DirectReturnBaseThrow(literal))
            None => return None
          }
        _ => return None
      }
      completion
    }
    _ => return None
  }
  let (recursive_callee, recursive_call_loc, recursive_subtract_loc) = match
    body[1] {
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
      decrement == DIRECT_RETURN_RECURSION_STEP =>
      (callee_name, call_loc, subtract_loc)
    _ => return None
  }
  guard recursive_callee == name else { return None }
  DirectReturnFunctionSyntax(
    name~,
    parameter~,
    recursive_callee~,
    base_condition_loc~,
    base_literal_loc~,
    recursive_call_loc~,
    recursive_subtract_loc~,
    base_completion~,
  )
  |> Some
}

///|
fn classify_direct_return_leaf_syntax(
  name : String,
  params : Array[String],
  body : Array[@ast.Stmt],
) -> DirectReturnLeafSyntax? {
  guard direct_return_identifier_is_safe(name) &&
    params.is_empty() &&
    body.length() == 1 else {
    return None
  }
  let (literal_loc, completion) = match body[0] {
    @ast.ReturnStmt(Some(expr), _) =>
      match classify_direct_return_closed_literal(expr) {
        Some((literal, loc)) => (loc, DirectReturnBaseValue(literal))
        None => return None
      }
    @ast.ThrowStmt(expr, _) =>
      match classify_direct_return_closed_literal(expr) {
        Some((literal, loc)) => (loc, DirectReturnBaseThrow(literal))
        None => return None
      }
    _ => return None
  }
  Some(DirectReturnLeafSyntax(name~, literal_loc~, completion~))
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
        Some(entry) => (entry, None, 1)
        None => return None
      }
    3 => {
      guard classify_direct_return_leaf(stmts[0], 0) is Some(leaf) &&
        classify_direct_return_function(stmts[1], 1) is Some(entry) else {
        return None
      }
      guard entry.syntax.base_completion
        is DirectReturnBaseLeafCall(leaf_name, _) &&
        leaf_name == leaf.syntax.name &&
        leaf.syntax.name != entry.syntax.name else {
        return None
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
