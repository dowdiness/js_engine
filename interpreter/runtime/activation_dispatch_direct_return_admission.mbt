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
  DirectReturnBaseLeafCall(DirectReturnLeafCallPlan)
}

///|
priv enum DirectReturnLeafArgumentSource {
  DirectReturnLeafClosedArgument(DirectReturnClosedArgument)
  DirectReturnLeafCarriedResult(@token.Loc)
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
priv struct DirectReturnResultFedCallChainPlan {
  calls : Array[DirectReturnLeafCallPlan]
}

///|
fn validate_direct_return_result_fed_call_chain_plan(
  calls~ : Array[DirectReturnLeafCallPlan],
) -> DirectReturnResultFedCallChainPlan? {
  guard !calls.is_empty() else { return None }
  for call in calls {
    let mut carried_result_count = 0
    for source in call.argument_sources {
      match source {
        DirectReturnLeafClosedArgument(_) => ()
        DirectReturnLeafCarriedResult(_) => carried_result_count += 1
      }
    }
    guard carried_result_count == 1 else { return None }
  }
  Some({
    calls: calls.map(call => {
      DirectReturnLeafCallPlan(
        callee_name=call.callee_name,
        call_loc=call.call_loc,
        argument_sources=call.argument_sources,
      )
    }),
  })
}

///|
fn snapshot_direct_return_result_fed_call_chain_plan(
  plan : DirectReturnResultFedCallChainPlan,
) -> DirectReturnResultFedCallChainPlan {
  {
    calls: plan.calls.map(call => {
      DirectReturnLeafCallPlan(
        callee_name=call.callee_name,
        call_loc=call.call_loc,
        argument_sources=call.argument_sources,
      )
    }),
  }
}

///|
fn direct_return_base_completion_copy(
  completion : DirectReturnBaseCompletion,
) -> DirectReturnBaseCompletion {
  match completion {
    DirectReturnBaseValue(literal) => DirectReturnBaseValue(literal)
    DirectReturnBaseThrow(literal) => DirectReturnBaseThrow(literal)
    DirectReturnBaseLeafCall(plan) =>
      DirectReturnBaseLeafCall(
        DirectReturnLeafCallPlan(
          callee_name=plan.callee_name,
          call_loc=plan.call_loc,
          argument_sources=plan.argument_sources,
        ),
      )
  }
}

///|
priv enum DirectReturnRecursiveCompletion {
  DirectReturnRecursiveSelfCall
  DirectReturnRecursiveResultFedCallChain(DirectReturnResultFedCallChainPlan)
}

///|
fn direct_return_recursive_completion_copy(
  completion : DirectReturnRecursiveCompletion,
) -> DirectReturnRecursiveCompletion {
  match completion {
    DirectReturnRecursiveSelfCall => DirectReturnRecursiveSelfCall
    DirectReturnRecursiveResultFedCallChain(plan) =>
      DirectReturnRecursiveResultFedCallChain(
        snapshot_direct_return_result_fed_call_chain_plan(plan),
      )
  }
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
) -> DirectReturnFunctionSyntax {
  {
    name,
    parameter,
    recursive_callee,
    base_condition_loc,
    base_literal_loc,
    recursive_call_loc,
    recursive_subtract_loc,
    base_completion: direct_return_base_completion_copy(base_completion),
    recursive_completion: direct_return_recursive_completion_copy(
      recursive_completion,
    ),
  }
}

///|
priv struct DirectReturnFunctionPlan {
  syntax : DirectReturnFunctionSyntax
  declaration_index : Int
}

///|
priv struct DirectReturnWrapperSyntax {
  name : String
  entry_name : String
  inner_call_loc : @token.Loc
  return_loc : @token.Loc
}

///|
fn DirectReturnWrapperSyntax::DirectReturnWrapperSyntax(
  name~ : String,
  entry_name~ : String,
  inner_call_loc~ : @token.Loc,
  return_loc~ : @token.Loc,
) -> DirectReturnWrapperSyntax {
  { name, entry_name, inner_call_loc, return_loc }
}

///|
priv struct DirectReturnWrapperPlan {
  syntax : DirectReturnWrapperSyntax
  declaration_index : Int
  outer_call_loc : @token.Loc
  initial_argument : Double
}

///|
fn DirectReturnWrapperPlan::DirectReturnWrapperPlan(
  syntax~ : DirectReturnWrapperSyntax,
  declaration_index~ : Int,
  outer_call_loc~ : @token.Loc,
  initial_argument~ : Double,
) -> DirectReturnWrapperPlan {
  { syntax, declaration_index, outer_call_loc, initial_argument }
}

///|
priv struct DirectReturnEntryRootPlan {
  entry_name : String
  call_loc : @token.Loc
  initial_argument : Double
}

///|
fn DirectReturnEntryRootPlan::DirectReturnEntryRootPlan(
  entry_name~ : String,
  call_loc~ : @token.Loc,
  initial_argument~ : Double,
) -> DirectReturnEntryRootPlan {
  { entry_name, call_loc, initial_argument }
}

///|
priv enum DirectReturnRootInvocation {
  DirectReturnEntryInvocation(DirectReturnEntryRootPlan)
  DirectReturnWrappedInvocation(DirectReturnWrapperPlan)
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
  helpers : Array[DirectReturnLeafPlan]
  root_invocation : DirectReturnRootInvocation
}

///|
fn DirectReturnRecursionPlan::DirectReturnRecursionPlan(
  entry~ : DirectReturnFunctionPlan,
  helpers~ : Array[DirectReturnLeafPlan],
  root_invocation~ : DirectReturnRootInvocation,
) -> DirectReturnRecursionPlan {
  { entry, helpers: helpers.copy(), root_invocation }
}

///|
#warnings("-unused_value")
fn DirectReturnRecursionPlan::first_helper(
  self : DirectReturnRecursionPlan,
) -> DirectReturnLeafPlan? {
  if self.helpers.is_empty() {
    None
  } else {
    Some(self.helpers[0])
  }
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
fn classify_direct_return_closed_argument(
  expr : @ast.Expr,
) -> DirectReturnClosedArgument? {
  match classify_direct_return_closed_literal(expr) {
    Some((literal, loc)) => Some(DirectReturnClosedArgument(literal~, loc~))
    None => None
  }
}

///|
fn classify_direct_return_closed_arguments(
  args : Array[@ast.Expr],
) -> Array[DirectReturnClosedArgument]? {
  guard args.length() <= DIRECT_RETURN_MAX_LEAF_ARGUMENTS else { return None }
  let arguments : Array[DirectReturnClosedArgument] = []
  for expr in args {
    guard classify_direct_return_closed_argument(expr) is Some(argument) else {
      return None
    }
    arguments.push(argument)
  }
  Some(arguments)
}

///|
fn classify_direct_return_result_fed_call_chain(
  args : Array[@ast.Expr],
  outer_name : String,
  outer_call_loc : @token.Loc,
  entry_name : String,
  parameter : String,
) -> (DirectReturnResultFedCallChainPlan, @token.Loc, @token.Loc)? {
  let calls_outer_to_inner : Array[DirectReturnLeafCallPlan] = []
  let mut current_args = args
  let mut current_name = outer_name
  let mut current_call_loc = outer_call_loc
  let mut recursive_call_loc : @token.Loc? = None
  let mut recursive_subtract_loc : @token.Loc? = None
  let mut complete = false
  while !complete {
    guard current_args.length() > 0 &&
      current_args.length() <= DIRECT_RETURN_MAX_LEAF_ARGUMENTS else {
      return None
    }
    let argument_sources : Array[DirectReturnLeafArgumentSource] = []
    let mut next_name : String? = None
    let mut next_args : Array[@ast.Expr]? = None
    let mut next_call_loc : @token.Loc? = None
    for expr in current_args {
      match classify_direct_return_closed_argument(expr) {
        Some(argument) =>
          argument_sources.push(DirectReturnLeafClosedArgument(argument))
        None =>
          match expr {
            @ast.Call(@ast.Ident(callee_name, _), args, call_loc) if direct_return_identifier_is_safe(
                callee_name,
              ) &&
              callee_name != parameter &&
              next_name is None => {
              next_name = Some(callee_name)
              next_args = Some(args)
              next_call_loc = Some(call_loc)
              argument_sources.push(DirectReturnLeafCarriedResult(call_loc))
            }
            _ => return None
          }
      }
    }
    let next_name = match next_name {
      Some(name) => name
      None => return None
    }
    let next_args = match next_args {
      Some(args) => args
      None => return None
    }
    let next_call_loc = match next_call_loc {
      Some(loc) => loc
      None => return None
    }
    calls_outer_to_inner.push(
      DirectReturnLeafCallPlan(
        callee_name=current_name,
        call_loc=current_call_loc,
        argument_sources~,
      ),
    )
    match next_args {
      [
        @ast.Binary(
          @ast.Sub,
          @ast.Ident(step_parameter, _),
          @ast.NumberLit(decrement, @token.LexForm::LexNormal, subtract_loc),
          _
        ),
      ] if next_name == entry_name &&
        step_parameter == parameter &&
        decrement == DIRECT_RETURN_RECURSION_STEP => {
        recursive_call_loc = Some(next_call_loc)
        recursive_subtract_loc = Some(subtract_loc)
        complete = true
      }
      _ if next_name != entry_name => {
        current_name = next_name
        current_args = next_args
        current_call_loc = next_call_loc
      }
      _ => return None
    }
  }
  let recursive_call_loc = match recursive_call_loc {
    Some(loc) => loc
    None => return None
  }
  let recursive_subtract_loc = match recursive_subtract_loc {
    Some(loc) => loc
    None => return None
  }
  match
    validate_direct_return_result_fed_call_chain_plan(
      calls=calls_outer_to_inner.rev(),
    ) {
    Some(chain) => Some((chain, recursive_call_loc, recursive_subtract_loc))
    None => None
  }
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
                    DirectReturnBaseLeafCall(
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
              (condition_loc, literal_loc, DirectReturnBaseThrow(literal))
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
      (callee_name, call_loc, subtract_loc, DirectReturnRecursiveSelfCall)
    @ast.ReturnStmt(
      Some(@ast.Call(@ast.Ident(helper_name, _), args, helper_call_loc)),
      _
    ) if direct_return_identifier_is_safe(helper_name) &&
      helper_name != name &&
      helper_name != parameter =>
      match
        classify_direct_return_result_fed_call_chain(
          args, helper_name, helper_call_loc, name, parameter,
        ) {
        Some((chain, recursive_call_loc, recursive_subtract_loc)) =>
          (
            name,
            recursive_call_loc,
            recursive_subtract_loc,
            DirectReturnRecursiveResultFedCallChain(chain),
          )
        None => return None
      }
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
fn direct_return_wrapper_name_is_distinct(
  wrapper_name : String,
  entry : DirectReturnFunctionPlan,
  leaf : DirectReturnLeafPlan,
) -> Bool {
  wrapper_name != entry.syntax.name && wrapper_name != leaf.syntax.name
}

///|
fn classify_direct_return_wrapper(
  stmt : @ast.Stmt,
  declaration_index : Int,
  entry : DirectReturnFunctionPlan,
  leaf : DirectReturnLeafPlan,
  outer_call_loc : @token.Loc,
) -> DirectReturnWrapperPlan? {
  match stmt {
    @ast.FuncDecl(name, params, body, _, _) if name == "entry" => {
      guard direct_return_identifier_is_safe(name) &&
        direct_return_wrapper_name_is_distinct(name, entry, leaf) &&
        params.is_empty() &&
        body.length() == 1 else {
        return None
      }
      match body[0] {
        @ast.ReturnStmt(
          Some(
            @ast.Call(
              @ast.Ident(callee_name, _),
              [@ast.NumberLit(argument, @token.LexForm::LexNormal, _)],
              inner_call_loc
            )
          ),
          return_loc
        ) if callee_name == entry.syntax.name &&
          argument == DIRECT_RETURN_RECURSION_INITIAL_ARGUMENT =>
          Some(
            DirectReturnWrapperPlan(
              syntax=DirectReturnWrapperSyntax(
                name~,
                entry_name=callee_name,
                inner_call_loc~,
                return_loc~,
              ),
              declaration_index~,
              outer_call_loc~,
              initial_argument=argument,
            ),
          )
        _ => None
      }
    }
    _ => None
  }
}

///|
fn classify_direct_return_result_fed_program(
  stmts : Array[@ast.Stmt],
) -> DirectReturnRecursionPlan? {
  guard stmts.length() >= 3 else { return None }
  let helper_count = stmts.length() - 2
  let helpers : Array[DirectReturnLeafPlan] = []
  for declaration_index in 0..<helper_count {
    let helper = match
      classify_direct_return_leaf(stmts[declaration_index], declaration_index) {
      Some(helper) => helper
      None => return None
    }
    for previous in helpers {
      guard previous.syntax.name != helper.syntax.name else { return None }
    }
    helpers.push(helper)
  }
  let entry = match
    classify_direct_return_function(stmts[helper_count], helper_count) {
    Some(entry) => entry
    None => return None
  }
  for helper in helpers {
    guard helper.syntax.name != entry.syntax.name &&
      helper.syntax.name != entry.syntax.parameter else {
      return None
    }
  }
  guard entry.syntax.base_completion
    is (DirectReturnBaseValue(_) | DirectReturnBaseThrow(_)) else {
    return None
  }
  let chain = match entry.syntax.recursive_completion {
    DirectReturnRecursiveResultFedCallChain(chain) => chain
    _ => return None
  }
  guard chain.calls.length() == helper_count else { return None }
  for declaration_index, call in chain.calls {
    let helper = helpers[declaration_index]
    guard call.callee_name == helper.syntax.name &&
      helper.syntax.parameters.length() == call.argument_sources.length() else {
      return None
    }
  }
  let root = match stmts[helper_count + 1] {
    @ast.ExprStmt(
      @ast.Call(
        @ast.Ident(root_name, _),
        [@ast.NumberLit(argument, @token.LexForm::LexNormal, root_call_loc)],
        _
      ),
      _
    ) if root_name == entry.syntax.name &&
      argument == DIRECT_RETURN_RECURSION_INITIAL_ARGUMENT =>
      DirectReturnEntryInvocation(
        DirectReturnEntryRootPlan(
          entry_name=root_name,
          call_loc=root_call_loc,
          initial_argument=argument,
        ),
      )
    _ => return None
  }
  Some(DirectReturnRecursionPlan(entry~, helpers~, root_invocation=root))
}

///|
fn classify_direct_return_recursion_program(
  stmts : Array[@ast.Stmt],
) -> DirectReturnRecursionPlan? {
  match classify_direct_return_result_fed_program(stmts) {
    Some(plan) => return Some(plan)
    None => ()
  }
  let (entry, leaf, root_invocation) = match stmts.length() {
    2 =>
      match classify_direct_return_function(stmts[0], 0) {
        Some(entry) => {
          guard entry.syntax.base_completion
            is (DirectReturnBaseValue(_) | DirectReturnBaseThrow(_)) &&
            entry.syntax.recursive_completion is DirectReturnRecursiveSelfCall else {
            return None
          }
          match stmts[1] {
            @ast.ExprStmt(
              @ast.Call(
                @ast.Ident(root_name, _),
                [
                  @ast.NumberLit(
                    argument,
                    @token.LexForm::LexNormal,
                    root_call_loc
                  ),
                ],
                _
              ),
              _
            ) if root_name == entry.syntax.name &&
              argument == DIRECT_RETURN_RECURSION_INITIAL_ARGUMENT =>
              (
                entry,
                None,
                DirectReturnEntryInvocation(
                  DirectReturnEntryRootPlan(
                    entry_name=root_name,
                    call_loc=root_call_loc,
                    initial_argument=argument,
                  ),
                ),
              )
            _ => return None
          }
        }
        None => return None
      }
    3 | 4 => {
      guard classify_direct_return_leaf(stmts[0], 0) is Some(leaf) &&
        classify_direct_return_function(stmts[1], 1) is Some(entry) else {
        return None
      }
      let leaf_call = match
        (entry.syntax.base_completion, entry.syntax.recursive_completion) {
        (DirectReturnBaseLeafCall(leaf_call), DirectReturnRecursiveSelfCall) => {
          for source in leaf_call.argument_sources {
            guard source is DirectReturnLeafClosedArgument(_) else {
              return None
            }
          }
          leaf_call
        }
        (
          DirectReturnBaseValue(_)
          | DirectReturnBaseThrow(_),
          DirectReturnRecursiveResultFedCallChain(chain),
        ) => {
          guard chain.calls.length() == 1 else { return None }
          chain.calls[0]
        }
        _ => return None
      }
      guard leaf_call.callee_name == leaf.syntax.name &&
        leaf.syntax.name != entry.syntax.name &&
        leaf.syntax.name != entry.syntax.parameter &&
        leaf.syntax.parameters.length() == leaf_call.argument_sources.length() else {
        return None
      }
      if stmts.length() == 3 {
        match stmts[2] {
          @ast.ExprStmt(
            @ast.Call(
              @ast.Ident(root_name, _),
              [
                @ast.NumberLit(
                  argument,
                  @token.LexForm::LexNormal,
                  root_call_loc
                ),
              ],
              _
            ),
            _
          ) if root_name == entry.syntax.name &&
            argument == DIRECT_RETURN_RECURSION_INITIAL_ARGUMENT =>
            (
              entry,
              Some(leaf),
              DirectReturnEntryInvocation(
                DirectReturnEntryRootPlan(
                  entry_name=root_name,
                  call_loc=root_call_loc,
                  initial_argument=argument,
                ),
              ),
            )
          _ => return None
        }
      } else {
        match stmts[3] {
          @ast.ExprStmt(
            @ast.Call(@ast.Ident(root_name, _), [], root_call_loc),
            _
          ) if root_name == "entry" => {
            let wrapper = match
              classify_direct_return_wrapper(
                stmts[2],
                2,
                entry,
                leaf,
                root_call_loc,
              ) {
              Some(wrapper) => wrapper
              None => return None
            }
            (entry, Some(leaf), DirectReturnWrappedInvocation(wrapper))
          }
          _ => return None
        }
      }
    }
    _ => return None
  }
  let helpers = match leaf {
    Some(leaf) => [leaf]
    None => []
  }
  Some(DirectReturnRecursionPlan(entry~, helpers~, root_invocation~))
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
