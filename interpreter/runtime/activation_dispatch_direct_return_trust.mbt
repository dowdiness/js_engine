// Runtime provenance sealing for the closed direct-return ordinary-function
// slice. No guest lookup or callback is performed after the root is sealed.

///|
priv struct DirectReturnRecursionPreflight {
  plan : DirectReturnRecursionPlan
  previous_entry_object : ObjectData?
  previous_helper_objects : Array[ObjectData?]
  previous_wrapper_object : ObjectData?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
priv struct TrustedDirectReturnRecursionFunction {
  syntax : DirectReturnFunctionSyntax
  callee : Value
  params : Array[String]
  body : Array[@ast.Stmt]
  source_text : String?
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
priv struct TrustedDirectReturnLeafFunction {
  syntax : DirectReturnLeafSyntax
  callee : Value
  params : Array[String]
  body : Array[@ast.Stmt]
  source_text : String?
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
priv struct TrustedDirectReturnWrapperFunction {
  plan : DirectReturnWrapperPlan
  callee : Value
  params : Array[String]
  body : Array[@ast.Stmt]
  source_text : String?
  expected_realm_protos : FunctionRealmProtos
  expected_source_identity : String?
}

///|
priv enum TrustedDirectReturnRoot {
  TrustedDirectReturnEntryRoot
  TrustedDirectReturnWrapperRoot(TrustedDirectReturnWrapperFunction)
}

///|
priv enum SealedDirectReturnRecursiveExecution {
  SealedDirectReturnSelfCall
  SealedDirectReturnResultFed(DispatchResultPipeline)
}

///|
priv struct SealedDirectReturnProgram {
  plan : DirectReturnRecursionPlan
  root : TrustedDirectReturnRoot
  entry : TrustedDirectReturnRecursionFunction
  helpers : Array[TrustedDirectReturnLeafFunction]
  throw_type_error : Value?
  throw_type_error_snapshot : CallbackFreeBindingSnapshot
  expected_global_object : ObjectData
  recursive_execution : SealedDirectReturnRecursiveExecution
}

///|
fn DirectReturnRecursionPreflight::DirectReturnRecursionPreflight(
  plan~ : DirectReturnRecursionPlan,
  previous_entry_object~ : ObjectData?,
  previous_helper_objects~ : Array[ObjectData?],
  previous_wrapper_object~ : ObjectData?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> DirectReturnRecursionPreflight {
  {
    plan,
    previous_entry_object,
    previous_helper_objects: previous_helper_objects.copy(),
    previous_wrapper_object,
    throw_type_error_snapshot,
    expected_global_object,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
fn TrustedDirectReturnLeafFunction::TrustedDirectReturnLeafFunction(
  syntax~ : DirectReturnLeafSyntax,
  callee~ : Value,
  params~ : Array[String],
  body~ : Array[@ast.Stmt],
  source_text~ : String?,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedDirectReturnLeafFunction {
  {
    syntax,
    callee,
    params,
    body,
    source_text,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
fn TrustedDirectReturnRecursionFunction::TrustedDirectReturnRecursionFunction(
  syntax~ : DirectReturnFunctionSyntax,
  callee~ : Value,
  params~ : Array[String],
  body~ : Array[@ast.Stmt],
  source_text~ : String?,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedDirectReturnRecursionFunction {
  {
    syntax,
    callee,
    params,
    body,
    source_text,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
fn TrustedDirectReturnWrapperFunction::TrustedDirectReturnWrapperFunction(
  plan~ : DirectReturnWrapperPlan,
  callee~ : Value,
  params~ : Array[String],
  body~ : Array[@ast.Stmt],
  source_text~ : String?,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
) -> TrustedDirectReturnWrapperFunction {
  {
    plan,
    callee,
    params,
    body,
    source_text,
    expected_realm_protos,
    expected_source_identity,
  }
}

///|
fn SealedDirectReturnProgram::SealedDirectReturnProgram(
  plan~ : DirectReturnRecursionPlan,
  root~ : TrustedDirectReturnRoot,
  entry~ : TrustedDirectReturnRecursionFunction,
  helpers~ : Array[TrustedDirectReturnLeafFunction],
  throw_type_error~ : Value?,
  throw_type_error_snapshot~ : CallbackFreeBindingSnapshot,
  expected_global_object~ : ObjectData,
  recursive_execution~ : SealedDirectReturnRecursiveExecution,
) -> SealedDirectReturnProgram {
  {
    plan,
    root,
    entry,
    helpers: helpers.copy(),
    throw_type_error,
    throw_type_error_snapshot,
    expected_global_object,
    recursive_execution,
  }
}

///|
#warnings("-unused_value")
fn SealedDirectReturnProgram::first_helper(
  self : SealedDirectReturnProgram,
) -> TrustedDirectReturnLeafFunction? {
  if self.helpers.is_empty() {
    None
  } else {
    Some(self.helpers[0])
  }
}

///|
fn SealedDirectReturnProgram::recursive_continuation(
  self : SealedDirectReturnProgram,
) -> DispatchContinuation {
  match self.recursive_execution {
    SealedDirectReturnSelfCall => DispatchCompleteReturn
    SealedDirectReturnResultFed(pipeline) =>
      DispatchContinueResultPipeline(pipeline.start())
  }
}

///|
fn direct_return_result_pipeline_helper(
  helpers : Array[TrustedDirectReturnLeafFunction],
  name : String,
) -> TrustedDirectReturnLeafFunction? {
  for helper in helpers {
    if helper.syntax.name == name {
      return Some(helper)
    }
  }
  None
}

///|
fn SealedDirectReturnProgram::require_result_pipeline_helper(
  self : SealedDirectReturnProgram,
  name : String,
) -> TrustedDirectReturnLeafFunction raise InvalidActivationDispatchShell {
  match direct_return_result_pipeline_helper(self.helpers, name) {
    Some(helper) => helper
    None =>
      invalid_activation_dispatch_shell(
        "direct-return base call lost its sealed helper",
      )
  }
}

///|
fn direct_return_result_pipeline(
  entry : TrustedDirectReturnRecursionFunction,
  helpers : Array[TrustedDirectReturnLeafFunction],
) -> DispatchResultPipeline? {
  let call_plans = match direct_return_recursive_call_plans(entry.syntax) {
    Some(call_plans) => call_plans
    None => return None
  }
  let stages : Array[DispatchResultPipelineStage] = []
  for call in call_plans {
    let helper = match
      direct_return_result_pipeline_helper(helpers, call.callee_name) {
      Some(helper) => helper
      None => return None
    }
    let args : Array[Value] = []
    let mut result_argument_index : Int? = None
    for index, source in call.argument_sources {
      match source {
        DirectReturnLeafClosedArgument(argument) =>
          args.push(direct_return_closed_literal_value(argument.literal))
        DirectReturnLeafCarriedResult(_) => {
          guard result_argument_index is None else { return None }
          result_argument_index = Some(index)
          args.push(Undefined)
        }
      }
    }
    let result_argument_index = match result_argument_index {
      Some(index) => index
      None => return None
    }
    let stage = match
      validate_dispatch_result_pipeline_stage(
        request=DispatchCallRequest(
          callee=helper.callee,
          this_value=Undefined,
          args~,
          loc=call.call_loc,
        ),
        callee_token=DispatchResultPipelineCalleeToken(helper.callee),
        result_argument_index~,
      ) {
      Some(stage) => stage
      None => return None
    }
    stages.push(stage)
  }
  guard !stages.is_empty() else { return None }
  validate_dispatch_result_pipeline(stages~)
}

///|
fn direct_return_closed_literals_match(
  expected : DirectReturnClosedLiteral,
  actual : DirectReturnClosedLiteral,
) -> Bool {
  match (expected, actual) {
    (DirectReturnClosedNull, DirectReturnClosedNull)
    | (DirectReturnClosedUndefined, DirectReturnClosedUndefined) => true
    (DirectReturnClosedNumber(expected), DirectReturnClosedNumber(actual)) =>
      expected == actual
    (DirectReturnClosedString(expected), DirectReturnClosedString(actual)) =>
      expected == actual
    (DirectReturnClosedBool(expected), DirectReturnClosedBool(actual)) =>
      expected == actual
    _ => false
  }
}

///|
fn direct_return_closed_literal_matches_value(
  expected : DirectReturnClosedLiteral,
  actual : Value,
) -> Bool {
  match (expected, actual) {
    (DirectReturnClosedNull, Null) | (DirectReturnClosedUndefined, Undefined) =>
      true
    (DirectReturnClosedNumber(expected), Number(actual)) => expected == actual
    (DirectReturnClosedString(expected), String_(actual)) => expected == actual
    (DirectReturnClosedBool(expected), Bool(actual)) => expected == actual
    _ => false
  }
}

///|
fn direct_return_base_completions_match(
  expected : DirectReturnBaseCompletion,
  actual : DirectReturnBaseCompletion,
) -> Bool {
  match (expected, actual) {
    (DirectReturnBaseValue(expected), DirectReturnBaseValue(actual))
    | (DirectReturnBaseThrow(expected), DirectReturnBaseThrow(actual)) =>
      direct_return_closed_literals_match(expected, actual)
    (DirectReturnBaseLeafCall(expected), DirectReturnBaseLeafCall(actual)) =>
      direct_return_leaf_call_plans_match(expected, actual)
    _ => false
  }
}

///|
fn direct_return_leaf_argument_sources_match(
  expected : Array[DirectReturnLeafArgumentSource],
  actual : Array[DirectReturnLeafArgumentSource],
) -> Bool {
  guard expected.length() == actual.length() else { return false }
  for index, expected in expected {
    let actual = actual[index]
    match (expected, actual) {
      (
        DirectReturnLeafClosedArgument(expected),
        DirectReturnLeafClosedArgument(actual),
      ) => {
        guard expected.loc == actual.loc &&
          direct_return_closed_literals_match(expected.literal, actual.literal) else {
          return false
        }
      }
      (
        DirectReturnLeafCarriedResult(expected),
        DirectReturnLeafCarriedResult(actual),
      ) if expected == actual => ()
      _ => return false
    }
  }
  true
}

///|
fn direct_return_leaf_call_plans_match(
  expected : DirectReturnLeafCallPlan,
  actual : DirectReturnLeafCallPlan,
) -> Bool {
  expected.callee_name == actual.callee_name &&
  expected.call_loc == actual.call_loc &&
  direct_return_leaf_argument_sources_match(
    expected.argument_sources,
    actual.argument_sources,
  )
}

///|
fn direct_return_recursive_completions_match(
  expected : DirectReturnRecursiveCompletion,
  actual : DirectReturnRecursiveCompletion,
) -> Bool {
  match (expected, actual) {
    (DirectReturnRecursiveSelfCall, DirectReturnRecursiveSelfCall) => true
    (
      DirectReturnRecursiveResultFedCallChain(expected),
      DirectReturnRecursiveResultFedCallChain(actual),
    ) => {
      guard expected.calls.length() == actual.calls.length() else {
        return false
      }
      for index, expected_call in expected.calls {
        guard direct_return_leaf_call_plans_match(
          expected_call,
          actual.calls[index],
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
fn direct_return_bound_parameters_match(
  expected : DirectReturnBoundParameter,
  actual : DirectReturnBoundParameter,
) -> Bool {
  expected.name == actual.name &&
  expected.index == actual.index &&
  expected.loc == actual.loc
}

///|
fn direct_return_leaf_completions_match(
  expected : DirectReturnLeafCompletion,
  actual : DirectReturnLeafCompletion,
) -> Bool {
  match (expected, actual) {
    (DirectReturnLeafClosedValue(expected), DirectReturnLeafClosedValue(actual))
    | (
      DirectReturnLeafClosedThrow(expected),
      DirectReturnLeafClosedThrow(actual),
    ) => direct_return_closed_literals_match(expected, actual)
    (
      DirectReturnLeafParameterValue(expected),
      DirectReturnLeafParameterValue(actual),
    )
    | (
      DirectReturnLeafParameterThrow(expected),
      DirectReturnLeafParameterThrow(actual),
    ) => direct_return_bound_parameters_match(expected, actual)
    _ => false
  }
}

///|
fn direct_return_leaf_parameters_match(
  expected : Array[String],
  actual : Array[String],
) -> Bool {
  guard expected.length() == actual.length() else { return false }
  for index, expected in expected {
    guard expected == actual[index] else { return false }
  }
  true
}

///|
fn direct_return_leaf_syntaxes_match(
  expected : DirectReturnLeafSyntax,
  actual : DirectReturnLeafSyntax,
) -> Bool {
  expected.name == actual.name &&
  direct_return_leaf_parameters_match(expected.parameters, actual.parameters) &&
  expected.completion_loc == actual.completion_loc &&
  direct_return_leaf_completions_match(
    expected.leaf_completion,
    actual.leaf_completion,
  )
}

///|
fn direct_return_function_syntaxes_match(
  expected : DirectReturnFunctionSyntax,
  actual : DirectReturnFunctionSyntax,
) -> Bool {
  expected.name == actual.name &&
  expected.parameter == actual.parameter &&
  expected.recursive_callee == actual.recursive_callee &&
  expected.base_condition_loc == actual.base_condition_loc &&
  expected.base_literal_loc == actual.base_literal_loc &&
  expected.recursive_call_loc == actual.recursive_call_loc &&
  expected.recursive_subtract_loc == actual.recursive_subtract_loc &&
  direct_return_recursive_completions_match(
    expected.recursive_completion,
    actual.recursive_completion,
  ) &&
  direct_return_base_completions_match(
    expected.base_completion,
    actual.base_completion,
  )
}

///|
fn direct_return_helper_call_plan(
  syntax : DirectReturnFunctionSyntax,
  helper_name : String,
) -> DirectReturnLeafCallPlan? {
  match syntax.base_completion {
    DirectReturnBaseLeafCall(plan) if plan.callee_name == helper_name =>
      Some(plan)
    _ =>
      match syntax.recursive_completion {
        DirectReturnRecursiveResultFedCallChain(chain) => {
          for call in chain.calls {
            if call.callee_name == helper_name {
              return Some(call)
            }
          }
          None
        }
        _ => None
      }
  }
}

///|
fn direct_return_recursive_call_plans(
  syntax : DirectReturnFunctionSyntax,
) -> Array[DirectReturnLeafCallPlan]? {
  match syntax.recursive_completion {
    DirectReturnRecursiveResultFedCallChain(chain) => Some(chain.calls)
    _ => None
  }
}

///|
fn direct_return_function_plans_match(
  expected : DirectReturnFunctionPlan,
  actual : DirectReturnFunctionPlan,
) -> Bool {
  expected.declaration_index == actual.declaration_index &&
  direct_return_function_syntaxes_match(expected.syntax, actual.syntax)
}

///|
fn direct_return_leaf_plans_match(
  expected : DirectReturnLeafPlan,
  actual : DirectReturnLeafPlan,
) -> Bool {
  expected.declaration_index == actual.declaration_index &&
  direct_return_leaf_syntaxes_match(expected.syntax, actual.syntax)
}

///|
fn direct_return_wrapper_syntaxes_match(
  expected : DirectReturnWrapperSyntax,
  actual : DirectReturnWrapperSyntax,
) -> Bool {
  expected.name == actual.name &&
  expected.entry_name == actual.entry_name &&
  expected.inner_call_loc == actual.inner_call_loc &&
  expected.return_loc == actual.return_loc
}

///|
fn direct_return_wrapper_plans_match(
  expected : DirectReturnWrapperPlan,
  actual : DirectReturnWrapperPlan,
) -> Bool {
  direct_return_wrapper_syntaxes_match(expected.syntax, actual.syntax) &&
  expected.declaration_index == actual.declaration_index &&
  expected.outer_call_loc == actual.outer_call_loc &&
  expected.initial_argument == actual.initial_argument
}

///|
fn direct_return_wrapper_body_snapshots_match(
  expected : Array[@ast.Stmt],
  actual : Array[@ast.Stmt],
) -> Bool {
  guard expected.length() == actual.length() else { return false }
  for index in 0..<expected.length() {
    guard physical_equal(expected[index], actual[index]) else { return false }
  }
  true
}

///|
fn direct_return_root_invocations_match(
  expected : DirectReturnRootInvocation,
  actual : DirectReturnRootInvocation,
) -> Bool {
  match (expected, actual) {
    (DirectReturnEntryInvocation(expected), DirectReturnEntryInvocation(actual)) =>
      expected.entry_name == actual.entry_name &&
      expected.call_loc == actual.call_loc &&
      expected.initial_argument == actual.initial_argument
    (
      DirectReturnWrappedInvocation(expected),
      DirectReturnWrappedInvocation(actual),
    ) => direct_return_wrapper_plans_match(expected, actual)
    _ => false
  }
}

///|
fn direct_return_helper_plans_match(
  expected : Array[DirectReturnLeafPlan],
  actual : Array[DirectReturnLeafPlan],
) -> Bool {
  guard expected.length() == actual.length() else { return false }
  for index in 0..<expected.length() {
    guard direct_return_leaf_plans_match(expected[index], actual[index]) else {
      return false
    }
  }
  true
}

///|
fn direct_return_recursion_plans_match(
  expected : DirectReturnRecursionPlan,
  actual : DirectReturnRecursionPlan,
) -> Bool {
  direct_return_root_invocations_match(
    expected.root_invocation,
    actual.root_invocation,
  ) &&
  direct_return_function_plans_match(expected.entry, actual.entry) &&
  direct_return_helper_plans_match(expected.helpers, actual.helpers)
}

///|
fn direct_return_leaf_argument_sources_match_values(
  sources : Array[DirectReturnLeafArgumentSource],
  values : Array[Value],
) -> Bool {
  guard sources.length() == values.length() else { return false }
  for index, source in sources {
    match source {
      DirectReturnLeafClosedArgument(argument) => {
        guard direct_return_closed_literal_matches_value(
          argument.literal,
          values[index],
        ) else {
          return false
        }
      }
      DirectReturnLeafCarriedResult(_) => ()
    }
  }
  true
}

///|
fn direct_return_throw_type_error_value(
  snapshot : CallbackFreeBindingSnapshot,
) -> Value? raise InvalidActivationDispatchShell {
  match snapshot {
    CallbackFreeBindingMissing => None
    CallbackFreeBindingPresent(value) => Some(value)
    CallbackFreeBindingUnsafe =>
      invalid_activation_dispatch_shell(
        "direct-return ThrowTypeError binding became callback-capable",
      )
  }
}

///|
fn direct_return_throw_type_error_snapshot_matches(
  expected : CallbackFreeBindingSnapshot,
  actual : CallbackFreeBindingSnapshot,
) -> Bool {
  numeric_recursion_callback_free_binding_snapshots_match(expected, actual)
}

///|
fn Interpreter::preflight_direct_return_recursion_program(
  self : Interpreter,
  plan : DirectReturnRecursionPlan,
) -> DirectReturnRecursionPreflight? {
  guard self.numeric_recursion_canonical_global_object()
    is Some(expected_global_object) else {
    return None
  }
  guard numeric_recursion_global_declaration_is_sealable(
    expected_global_object,
    plan.entry.syntax.name,
  ) else {
    return None
  }
  let (entry_ok, previous_entry_object) = numeric_recursion_existing_binding_snapshot(
    self.global,
    plan.entry.syntax.name,
  )
  guard entry_ok else { return None }
  let previous_wrapper_object = match plan.root_invocation {
    DirectReturnEntryInvocation(_) => None
    DirectReturnWrappedInvocation(wrapper) => {
      guard numeric_recursion_global_declaration_is_sealable(
        expected_global_object,
        wrapper.syntax.name,
      ) else {
        return None
      }
      let (wrapper_ok, previous_wrapper_object) = numeric_recursion_existing_binding_snapshot(
        self.global,
        wrapper.syntax.name,
      )
      guard wrapper_ok else { return None }
      previous_wrapper_object
    }
  }
  let previous_helper_objects : Array[ObjectData?] = []
  for helper in plan.helpers {
    guard numeric_recursion_global_declaration_is_sealable(
      expected_global_object,
      helper.syntax.name,
    ) else {
      return None
    }
    let (helper_ok, previous_helper_object) = numeric_recursion_existing_binding_snapshot(
      self.global,
      helper.syntax.name,
    )
    guard helper_ok else { return None }
    previous_helper_objects.push(previous_helper_object)
  }
  let throw_type_error_snapshot = numeric_recursion_callback_free_throw_type_error(
    self.global,
  )
  match throw_type_error_snapshot {
    CallbackFreeBindingUnsafe => return None
    _ => ()
  }
  Some(
    DirectReturnRecursionPreflight(
      plan~,
      previous_entry_object~,
      previous_helper_objects~,
      previous_wrapper_object~,
      throw_type_error_snapshot~,
      expected_global_object~,
      expected_realm_protos=function_realm_protos_from_realm_state(
        self.realm_state,
      ),
      expected_source_identity=self.realm_state.active_source_identity.val,
    ),
  )
}

///|
fn Interpreter::preflight_dispatchable_direct_return_recursion_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> DirectReturnRecursionPreflight? {
  match classify_direct_return_recursion_program(stmts) {
    Some(plan) => self.preflight_direct_return_recursion_program(plan)
    None => None
  }
}

///|
fn direct_return_recursion_trusted_declaration(
  interp : Interpreter,
  plan : DirectReturnFunctionPlan,
  previous_object~ : ObjectData?,
  expected_global_object~ : ObjectData,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
  stmts~ : Array[@ast.Stmt],
) -> TrustedDirectReturnRecursionFunction raise InvalidActivationDispatchShell {
  guard plan.declaration_index >= 0 && plan.declaration_index < stmts.length() else {
    invalid_activation_dispatch_shell(
      "direct-return declaration index is outside the admitted program",
    )
  }
  guard stmts[plan.declaration_index]
    is @ast.FuncDecl(ast_name, ast_params, ast_body, _, ast_source_text) else {
    invalid_activation_dispatch_shell(
      "direct-return declaration no longer matches its admitted syntax",
    )
  }
  let syntax = plan.syntax
  guard interp.global.bindings.get(syntax.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding else {
    invalid_activation_dispatch_shell(
      "direct-return declaration binding was not created by root hoisting",
    )
  }
  let callee = binding.value
  guard callee is Object(object_identity) &&
    object_identity.class_name == "Function" else {
    invalid_activation_dispatch_shell(
      "direct-return declaration did not hoist a function object",
    )
  }
  guard interp.global_this is Object(global_object) &&
    physical_equal(global_object, expected_global_object) &&
    global_object.bag.properties.get(syntax.name) is Some(Object(mirrored)) &&
    physical_equal(mirrored, object_identity) &&
    numeric_recursion_global_property_is_canonical(global_object, syntax.name) else {
    invalid_activation_dispatch_shell(
      "direct-return declaration diverged from its global mirror",
    )
  }
  match previous_object {
    Some(previous) if physical_equal(previous, object_identity) =>
      invalid_activation_dispatch_shell(
        "direct-return declaration reused its pre-hoist object identity",
      )
    _ => ()
  }
  guard object_identity.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "direct-return declaration did not hoist an ordinary UserFunc",
    )
  }
  guard classify_direct_return_function_syntax(ast_name, ast_params, ast_body)
    is Some(actual_syntax) &&
    direct_return_function_syntaxes_match(syntax, actual_syntax) &&
    data.name == Some(syntax.name) &&
    data.params.length() == 1 &&
    data.params[0] == syntax.parameter &&
    physical_equal(data.params, ast_params) &&
    physical_equal(data.body, ast_body) &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method &&
    data.source_text == ast_source_text else {
    invalid_activation_dispatch_shell(
      "direct-return UserFunc provenance did not match the admitted declaration",
    )
  }
  let source_identity = function_source_identity(callee)
  guard source_identity == expected_source_identity else {
    invalid_activation_dispatch_shell(
      "direct-return UserFunc source identity changed during root hoisting",
    )
  }
  let realm_protos = callee_realm_protos(callee)
  guard numeric_recursion_realm_protos_match(
    expected_realm_protos, realm_protos,
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return UserFunc realm provenance changed during root hoisting",
    )
  }
  TrustedDirectReturnRecursionFunction(
    syntax~,
    callee~,
    params=data.params,
    body=data.body,
    source_text=data.source_text,
    expected_realm_protos=realm_protos,
    expected_source_identity=source_identity,
  )
}

///|
fn direct_return_leaf_trusted_declaration(
  interp : Interpreter,
  plan : DirectReturnLeafPlan,
  previous_object~ : ObjectData?,
  expected_global_object~ : ObjectData,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
  stmts~ : Array[@ast.Stmt],
) -> TrustedDirectReturnLeafFunction raise InvalidActivationDispatchShell {
  guard plan.declaration_index >= 0 && plan.declaration_index < stmts.length() else {
    invalid_activation_dispatch_shell(
      "direct-return leaf declaration index is outside the admitted program",
    )
  }
  guard stmts[plan.declaration_index]
    is @ast.FuncDecl(ast_name, ast_params, ast_body, _, ast_source_text) else {
    invalid_activation_dispatch_shell(
      "direct-return leaf declaration no longer matches its admitted syntax",
    )
  }
  let syntax = plan.syntax
  guard interp.global.bindings.get(syntax.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding else {
    invalid_activation_dispatch_shell(
      "direct-return leaf binding was not created by root hoisting",
    )
  }
  let callee = binding.value
  guard callee is Object(object_identity) &&
    object_identity.class_name == "Function" else {
    invalid_activation_dispatch_shell(
      "direct-return leaf did not hoist a function object",
    )
  }
  guard interp.global_this is Object(global_object) &&
    physical_equal(global_object, expected_global_object) &&
    global_object.bag.properties.get(syntax.name) is Some(Object(mirrored)) &&
    physical_equal(mirrored, object_identity) &&
    numeric_recursion_global_property_is_canonical(global_object, syntax.name) else {
    invalid_activation_dispatch_shell(
      "direct-return leaf diverged from its global mirror",
    )
  }
  match previous_object {
    Some(previous) if physical_equal(previous, object_identity) =>
      invalid_activation_dispatch_shell(
        "direct-return leaf reused its pre-hoist object identity",
      )
    _ => ()
  }
  guard object_identity.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "direct-return leaf did not hoist an ordinary UserFunc",
    )
  }
  guard classify_direct_return_leaf_syntax(ast_name, ast_params, ast_body)
    is Some(actual_syntax) &&
    direct_return_leaf_syntaxes_match(syntax, actual_syntax) &&
    data.name == Some(syntax.name) &&
    direct_return_leaf_parameters_match(syntax.parameters, data.params) &&
    physical_equal(data.params, ast_params) &&
    physical_equal(data.body, ast_body) &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method &&
    data.source_text == ast_source_text else {
    invalid_activation_dispatch_shell(
      "direct-return leaf provenance did not match the admitted declaration",
    )
  }
  let source_identity = function_source_identity(callee)
  guard source_identity == expected_source_identity else {
    invalid_activation_dispatch_shell(
      "direct-return leaf source identity changed during root hoisting",
    )
  }
  let realm_protos = callee_realm_protos(callee)
  guard numeric_recursion_realm_protos_match(
    expected_realm_protos, realm_protos,
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return leaf realm provenance changed during root hoisting",
    )
  }
  TrustedDirectReturnLeafFunction(
    syntax~,
    callee~,
    params=data.params,
    body=data.body,
    source_text=data.source_text,
    expected_realm_protos=realm_protos,
    expected_source_identity=source_identity,
  )
}

///|
fn direct_return_wrapper_trusted_declaration(
  interp : Interpreter,
  plan : DirectReturnWrapperPlan,
  entry_plan : DirectReturnFunctionPlan,
  leaf_plan : DirectReturnLeafPlan,
  previous_object~ : ObjectData?,
  expected_global_object~ : ObjectData,
  expected_realm_protos~ : FunctionRealmProtos,
  expected_source_identity~ : String?,
  stmts~ : Array[@ast.Stmt],
) -> TrustedDirectReturnWrapperFunction raise InvalidActivationDispatchShell {
  guard plan.declaration_index >= 0 && plan.declaration_index < stmts.length() else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper declaration index is outside the admitted program",
    )
  }
  guard stmts[plan.declaration_index]
    is @ast.FuncDecl(ast_name, ast_params, ast_body, _, ast_source_text) else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper declaration no longer matches its admitted syntax",
    )
  }
  let syntax = plan.syntax
  guard direct_return_wrapper_name_is_distinct(
    syntax.name,
    entry_plan,
    leaf_plan,
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper name collides with a sealed recursive or leaf declaration",
    )
  }
  guard interp.global.bindings.get(syntax.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper binding was not created by root hoisting",
    )
  }
  let callee = binding.value
  guard callee is Object(object_identity) &&
    object_identity.class_name == "Function" else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper did not hoist a function object",
    )
  }
  guard interp.global_this is Object(global_object) &&
    physical_equal(global_object, expected_global_object) &&
    global_object.bag.properties.get(syntax.name) is Some(Object(mirrored)) &&
    physical_equal(mirrored, object_identity) &&
    numeric_recursion_global_property_is_canonical(global_object, syntax.name) else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper diverged from its global mirror",
    )
  }
  match previous_object {
    Some(previous) if physical_equal(previous, object_identity) =>
      invalid_activation_dispatch_shell(
        "direct-return wrapper reused its pre-hoist object identity",
      )
    _ => ()
  }
  guard object_identity.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper did not hoist an ordinary UserFunc",
    )
  }
  guard classify_direct_return_wrapper(
      stmts[plan.declaration_index],
      plan.declaration_index,
      entry_plan,
      leaf_plan,
      plan.outer_call_loc,
    )
    is Some(actual_plan) &&
    direct_return_wrapper_plans_match(plan, actual_plan) &&
    ast_name == syntax.name &&
    data.name == Some(syntax.name) &&
    data.params.is_empty() &&
    physical_equal(data.params, ast_params) &&
    physical_equal(data.body, ast_body) &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method &&
    data.source_text == ast_source_text else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper UserFunc provenance did not match the admitted declaration",
    )
  }
  let source_identity = function_source_identity(callee)
  guard source_identity == expected_source_identity else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper source identity changed during root hoisting",
    )
  }
  let realm_protos = callee_realm_protos(callee)
  guard numeric_recursion_realm_protos_match(
    expected_realm_protos, realm_protos,
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper realm provenance changed during root hoisting",
    )
  }
  TrustedDirectReturnWrapperFunction(
    plan~,
    callee~,
    params=data.params.copy(),
    body=data.body.copy(),
    source_text=data.source_text,
    expected_realm_protos=realm_protos,
    expected_source_identity=source_identity,
  )
}

///|
fn Interpreter::seal_direct_return_program(
  self : Interpreter,
  preflight : DirectReturnRecursionPreflight,
  stmts : Array[@ast.Stmt],
) -> SealedDirectReturnProgram raise InvalidActivationDispatchShell {
  guard self.numeric_recursion_canonical_global_object() is Some(global_object) &&
    physical_equal(global_object, preflight.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "direct-return canonical global object changed before sealing",
    )
  }
  guard classify_direct_return_recursion_program(stmts) is Some(actual_plan) &&
    direct_return_recursion_plans_match(preflight.plan, actual_plan) else {
    invalid_activation_dispatch_shell(
      "direct-return program no longer matches exact admission",
    )
  }
  let throw_type_error_snapshot = numeric_recursion_callback_free_throw_type_error(
    self.global,
  )
  guard direct_return_throw_type_error_snapshot_matches(
    preflight.throw_type_error_snapshot,
    throw_type_error_snapshot,
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return ThrowTypeError binding changed before sealing",
    )
  }
  let entry = direct_return_recursion_trusted_declaration(
    self,
    preflight.plan.entry,
    previous_object=preflight.previous_entry_object,
    expected_global_object=preflight.expected_global_object,
    expected_realm_protos=preflight.expected_realm_protos,
    expected_source_identity=preflight.expected_source_identity,
    stmts~,
  )
  let helpers : Array[TrustedDirectReturnLeafFunction] = []
  for index, plan in preflight.plan.helpers {
    guard index < preflight.previous_helper_objects.length() else {
      invalid_activation_dispatch_shell(
        "direct-return helper snapshot count drifted before sealing",
      )
    }
    helpers.push(
      direct_return_leaf_trusted_declaration(
        self,
        plan,
        previous_object=preflight.previous_helper_objects[index],
        expected_global_object=preflight.expected_global_object,
        expected_realm_protos=preflight.expected_realm_protos,
        expected_source_identity=preflight.expected_source_identity,
        stmts~,
      ),
    )
  }
  let root = match preflight.plan.root_invocation {
    DirectReturnEntryInvocation(_) => TrustedDirectReturnEntryRoot
    DirectReturnWrappedInvocation(wrapper) => {
      guard preflight.plan.helpers.length() == 1 else {
        invalid_activation_dispatch_shell(
          "direct-return wrapper root requires one sealed helper",
        )
      }
      let leaf_plan = preflight.plan.helpers[0]
      TrustedDirectReturnWrapperRoot(
        direct_return_wrapper_trusted_declaration(
          self,
          wrapper,
          preflight.plan.entry,
          leaf_plan,
          previous_object=preflight.previous_wrapper_object,
          expected_global_object=preflight.expected_global_object,
          expected_realm_protos=preflight.expected_realm_protos,
          expected_source_identity=preflight.expected_source_identity,
          stmts~,
        ),
      )
    }
  }
  let recursive_execution = match entry.syntax.recursive_completion {
    DirectReturnRecursiveSelfCall => SealedDirectReturnSelfCall
    DirectReturnRecursiveResultFedCallChain(_) => {
      let pipeline = match direct_return_result_pipeline(entry, helpers) {
        Some(pipeline) => pipeline
        None =>
          invalid_activation_dispatch_shell(
            "direct-return result-fed pipeline was not sealed",
          )
      }
      SealedDirectReturnResultFed(pipeline)
    }
  }
  SealedDirectReturnProgram(
    plan=preflight.plan,
    root~,
    entry~,
    helpers~,
    throw_type_error=direct_return_throw_type_error_value(
      throw_type_error_snapshot,
    ),
    throw_type_error_snapshot~,
    expected_global_object=preflight.expected_global_object,
    recursive_execution~,
  )
}

///|
fn SealedDirectReturnProgram::require_callee(
  self : SealedDirectReturnProgram,
  interp : Interpreter,
  callee : Value,
) -> DirectReturnFunctionSyntax raise InvalidActivationDispatchShell {
  guard self.plan.entry.syntax.name == self.entry.syntax.name else {
    invalid_activation_dispatch_shell(
      "direct-return program lost its entry syntax identity",
    )
  }
  guard interp.numeric_recursion_canonical_global_object()
    is Some(global_object) &&
    physical_equal(global_object, self.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "direct-return canonical global object changed after sealing",
    )
  }
  guard numeric_recursion_callback_free_binding_snapshots_match(
    self.throw_type_error_snapshot,
    numeric_recursion_callback_free_throw_type_error(interp.global),
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return ThrowTypeError binding changed after sealing",
    )
  }
  guard callee is Object(actual) else {
    invalid_activation_dispatch_shell(
      "direct-return call requested an unsealed callee",
    )
  }
  guard (match self.entry.callee {
    Object(expected) => physical_equal(actual, expected)
    _ => false
  }) else {
    invalid_activation_dispatch_shell(
      "direct-return program lost its function object",
    )
  }
  guard interp.global.bindings.get(self.entry.syntax.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding &&
    binding.value is Object(bound) &&
    physical_equal(bound, actual) else {
    invalid_activation_dispatch_shell(
      "direct-return callee diverged from its global binding",
    )
  }
  guard global_object.bag.properties.get(self.entry.syntax.name)
    is Some(Object(mirrored)) &&
    physical_equal(mirrored, actual) &&
    numeric_recursion_global_property_is_canonical(
      global_object,
      self.entry.syntax.name,
    ) else {
    invalid_activation_dispatch_shell(
      "direct-return callee diverged from its global mirror",
    )
  }
  guard actual.class_name == "Function" &&
    actual.callable is Some(UserFunc(data)) &&
    data.name == Some(self.entry.syntax.name) &&
    data.params.length() == 1 &&
    data.params[0] == self.entry.syntax.parameter &&
    physical_equal(data.params, self.entry.params) &&
    physical_equal(data.body, self.entry.body) &&
    classify_direct_return_function_syntax(
      self.entry.syntax.name,
      self.entry.params,
      self.entry.body,
    )
    is Some(actual_syntax) &&
    direct_return_function_syntaxes_match(self.entry.syntax, actual_syntax) &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method &&
    data.source_text == self.entry.source_text &&
    function_source_identity(callee) == self.entry.expected_source_identity &&
    numeric_recursion_realm_protos_match(
      self.entry.expected_realm_protos,
      callee_realm_protos(callee),
    ) else {
    invalid_activation_dispatch_shell(
      "direct-return callee provenance changed after sealing",
    )
  }
  self.entry.syntax
}

///|
fn SealedDirectReturnProgram::require_helper(
  self : SealedDirectReturnProgram,
  interp : Interpreter,
  callee : Value,
  helper : TrustedDirectReturnLeafFunction,
) -> DirectReturnLeafSyntax raise InvalidActivationDispatchShell {
  let mut matched_plan : DirectReturnLeafPlan? = None
  for plan in self.plan.helpers {
    if direct_return_leaf_syntaxes_match(plan.syntax, helper.syntax) {
      matched_plan = Some(plan)
    }
  }
  guard matched_plan is Some(_) else {
    invalid_activation_dispatch_shell(
      "direct-return program lost its helper syntax identity",
    )
  }
  guard interp.numeric_recursion_canonical_global_object()
    is Some(global_object) &&
    physical_equal(global_object, self.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "direct-return canonical global object changed after sealing",
    )
  }
  guard numeric_recursion_callback_free_binding_snapshots_match(
    self.throw_type_error_snapshot,
    numeric_recursion_callback_free_throw_type_error(interp.global),
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return ThrowTypeError binding changed after sealing",
    )
  }
  guard callee is Object(actual) else {
    invalid_activation_dispatch_shell(
      "direct-return helper call requested an unsealed callee",
    )
  }
  guard (match helper.callee {
    Object(expected) => physical_equal(actual, expected)
    _ => false
  }) else {
    invalid_activation_dispatch_shell(
      "direct-return program lost its helper function object",
    )
  }
  guard interp.global.bindings.get(helper.syntax.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding &&
    binding.value is Object(bound) &&
    physical_equal(bound, actual) else {
    invalid_activation_dispatch_shell(
      "direct-return leaf diverged from its global binding",
    )
  }
  guard global_object.bag.properties.get(helper.syntax.name)
    is Some(Object(mirrored)) &&
    physical_equal(mirrored, actual) &&
    numeric_recursion_global_property_is_canonical(
      global_object,
      helper.syntax.name,
    ) else {
    invalid_activation_dispatch_shell(
      "direct-return helper diverged from its global mirror",
    )
  }
  guard actual.class_name == "Function" &&
    actual.callable is Some(UserFunc(data)) &&
    data.name == Some(helper.syntax.name) &&
    direct_return_leaf_parameters_match(helper.syntax.parameters, data.params) &&
    physical_equal(data.params, helper.params) &&
    physical_equal(data.body, helper.body) &&
    classify_direct_return_leaf_syntax(
      helper.syntax.name,
      helper.params,
      helper.body,
    )
    is Some(actual_syntax) &&
    direct_return_leaf_syntaxes_match(helper.syntax, actual_syntax) &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method &&
    data.source_text == helper.source_text &&
    function_source_identity(callee) == helper.expected_source_identity &&
    numeric_recursion_realm_protos_match(
      helper.expected_realm_protos,
      callee_realm_protos(callee),
    ) else {
    invalid_activation_dispatch_shell(
      "direct-return leaf provenance changed after sealing",
    )
  }
  helper.syntax
}

///|
#warnings("-unused_value")
fn SealedDirectReturnProgram::require_leaf(
  self : SealedDirectReturnProgram,
  interp : Interpreter,
  callee : Value,
) -> DirectReturnLeafSyntax raise InvalidActivationDispatchShell {
  guard self.helpers.length() == 1 else {
    invalid_activation_dispatch_shell(
      "direct-return call requested a non-single helper catalog leaf",
    )
  }
  self.require_helper(interp, callee, self.helpers[0])
}

///|
fn SealedDirectReturnProgram::require_wrapper(
  self : SealedDirectReturnProgram,
  interp : Interpreter,
  callee : Value,
) -> TrustedDirectReturnWrapperFunction raise InvalidActivationDispatchShell {
  let wrapper = match self.root {
    TrustedDirectReturnWrapperRoot(wrapper) => wrapper
    TrustedDirectReturnEntryRoot =>
      invalid_activation_dispatch_shell(
        "direct-return call requested a wrapper outside the sealed root role",
      )
  }
  guard self.plan.root_invocation is DirectReturnWrappedInvocation(root_plan) &&
    direct_return_wrapper_plans_match(root_plan, wrapper.plan) else {
    invalid_activation_dispatch_shell(
      "direct-return program lost its wrapper root-plan ownership",
    )
  }
  let leaf_name_is_distinct = self.plan.helpers.length() == 1 &&
    direct_return_wrapper_name_is_distinct(
      wrapper.plan.syntax.name,
      self.plan.entry,
      self.plan.helpers[0],
    )
  guard leaf_name_is_distinct else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper name collides with a sealed recursive or leaf declaration",
    )
  }
  guard interp.numeric_recursion_canonical_global_object()
    is Some(global_object) &&
    physical_equal(global_object, self.expected_global_object) else {
    invalid_activation_dispatch_shell(
      "direct-return canonical global object changed after sealing",
    )
  }
  guard numeric_recursion_callback_free_binding_snapshots_match(
    self.throw_type_error_snapshot,
    numeric_recursion_callback_free_throw_type_error(interp.global),
  ) else {
    invalid_activation_dispatch_shell(
      "direct-return ThrowTypeError binding changed after sealing",
    )
  }
  guard callee is Object(actual) else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper call requested an unsealed callee",
    )
  }
  guard wrapper.callee is Object(expected) && physical_equal(actual, expected) else {
    invalid_activation_dispatch_shell(
      "direct-return program lost its wrapper function object",
    )
  }
  guard interp.global.bindings.get(wrapper.plan.syntax.name) is Some(binding) &&
    binding.initialized &&
    binding.kind == VarBinding &&
    binding.value is Object(bound) &&
    physical_equal(bound, actual) else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper diverged from its global binding",
    )
  }
  guard global_object.bag.properties.get(wrapper.plan.syntax.name)
    is Some(Object(mirrored)) &&
    physical_equal(mirrored, actual) &&
    numeric_recursion_global_property_is_canonical(
      global_object,
      wrapper.plan.syntax.name,
    ) else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper diverged from its global mirror",
    )
  }
  guard actual.class_name == "Function" &&
    actual.callable is Some(UserFunc(data)) &&
    data.name == Some(wrapper.plan.syntax.name) &&
    data.params.is_empty() &&
    data.params == wrapper.params &&
    direct_return_wrapper_body_snapshots_match(wrapper.body, data.body) &&
    physical_equal(data.closure, interp.global) &&
    !data.strict &&
    !data.has_name_binding &&
    !data.is_method &&
    data.source_text == wrapper.source_text &&
    function_source_identity(callee) == wrapper.expected_source_identity &&
    numeric_recursion_realm_protos_match(
      wrapper.expected_realm_protos,
      callee_realm_protos(callee),
    ) else {
    invalid_activation_dispatch_shell(
      "direct-return wrapper provenance changed after sealing",
    )
  }
  wrapper
}

///|
fn SealedDirectReturnProgram::require_call(
  self : SealedDirectReturnProgram,
  interp : Interpreter,
  callee : Value,
  this_value : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> Unit raise InvalidActivationDispatchShell {
  guard this_value is Undefined else {
    invalid_activation_dispatch_shell(
      "direct-return activation requires undefined this",
    )
  }
  match self.root {
    TrustedDirectReturnWrapperRoot(wrapper) =>
      if (match (wrapper.callee, callee) {
          (Object(expected), Object(actual)) => physical_equal(expected, actual)
          _ => false
        }) {
        guard args.is_empty() && loc == wrapper.plan.outer_call_loc else {
          invalid_activation_dispatch_shell(
            "direct-return wrapper activation escaped its sealed root plan",
          )
        }
        let _ = self.require_wrapper(interp, callee)
        return
      }
    TrustedDirectReturnEntryRoot => ()
  }
  for helper in self.helpers {
    if (match (helper.callee, callee) {
        (Object(expected), Object(actual)) => physical_equal(expected, actual)
        _ => false
      }) {
      let helper_call = match
        direct_return_helper_call_plan(self.entry.syntax, helper.syntax.name) {
        Some(plan) => plan
        None =>
          invalid_activation_dispatch_shell(
            "direct-return program helpers lost their completion plan",
          )
      }
      guard helper_call.callee_name == helper.syntax.name &&
        this_value is Undefined &&
        direct_return_leaf_argument_sources_match_values(
          helper_call.argument_sources,
          args,
        ) else {
        invalid_activation_dispatch_shell(
          "direct-return leaf activation escaped its sealed argument plan",
        )
      }
      guard loc == helper_call.call_loc else {
        invalid_activation_dispatch_shell(
          "direct-return helper call location escaped the sealed source recipe",
        )
      }
      let _ = self.require_helper(interp, callee, helper)
      return
    }
  }
  guard args.length() == 1 else {
    invalid_activation_dispatch_shell(
      "direct-return activation requires undefined this and one argument",
    )
  }
  guard args[0] is Number(_) else {
    invalid_activation_dispatch_shell(
      "direct-return activation requires a Number argument",
    )
  }
  let entry_root_matches = match self.root {
    TrustedDirectReturnEntryRoot =>
      match self.plan.root_invocation {
        DirectReturnEntryInvocation(root) =>
          root.entry_name == self.entry.syntax.name &&
          (
            loc == self.entry.syntax.recursive_call_loc ||
            (
              loc == root.call_loc &&
              args[0] is Number(value) &&
              value == root.initial_argument
            )
          )
        DirectReturnWrappedInvocation(_) => false
      }
    TrustedDirectReturnWrapperRoot(wrapper) =>
      loc == self.entry.syntax.recursive_call_loc ||
      (
        loc == wrapper.plan.syntax.inner_call_loc &&
        args[0] is Number(value) &&
        value == wrapper.plan.initial_argument
      )
  }
  guard entry_root_matches else {
    invalid_activation_dispatch_shell(
      "direct-return call location escaped the sealed source recipe",
    )
  }
  let _ = self.require_callee(interp, callee)
}
