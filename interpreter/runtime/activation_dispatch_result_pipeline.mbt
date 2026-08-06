// Deterministic forwarding of one completed normal result through a sealed,
// non-empty sequence of direct-return helper calls. The pipeline has no
// completion policy and performs no guest or lifecycle effects.

///|
priv struct DispatchResultPipelineCalleeToken(Value)

///|
priv struct DispatchResultPipelineStage {
  request : DispatchCallRequest
  callee_token : DispatchResultPipelineCalleeToken
  result_argument_index : Int
}

///|
fn validate_dispatch_result_pipeline_stage(
  request~ : DispatchCallRequest,
  callee_token~ : DispatchResultPipelineCalleeToken,
  result_argument_index~ : Int,
) -> DispatchResultPipelineStage? {
  guard result_argument_index >= 0 &&
    result_argument_index < request.args.length() else {
    return None
  }
  Some({
    request: DispatchCallRequest(
      callee=request.callee,
      this_value=request.this_value,
      args=request.args,
      loc=request.loc,
    ),
    callee_token,
    result_argument_index,
  })
}

///|
fn snapshot_dispatch_result_pipeline_stage(
  stage : DispatchResultPipelineStage,
) -> DispatchResultPipelineStage {
  {
    request: DispatchCallRequest(
      callee=stage.request.callee,
      this_value=stage.request.this_value,
      args=stage.request.args,
      loc=stage.request.loc,
    ),
    callee_token: stage.callee_token,
    result_argument_index: stage.result_argument_index,
  }
}

///|
priv struct DispatchResultPipeline {
  stages : Array[DispatchResultPipelineStage]
}

///|
fn validate_dispatch_result_pipeline(
  stages~ : Array[DispatchResultPipelineStage],
) -> DispatchResultPipeline? {
  guard !stages.is_empty() else { return None }
  Some({ stages: stages.map(snapshot_dispatch_result_pipeline_stage) })
}

///|
fn snapshot_dispatch_result_pipeline(
  pipeline : DispatchResultPipeline,
) -> DispatchResultPipeline {
  { stages: pipeline.stages.map(snapshot_dispatch_result_pipeline_stage) }
}

///|
fn DispatchResultPipeline::start(
  self : DispatchResultPipeline,
) -> DispatchResultPipelineCursor {
  { pipeline: snapshot_dispatch_result_pipeline(self), next_index: 0 }
}

///|
priv struct DispatchResultPipelineCursor {
  pipeline : DispatchResultPipeline
  next_index : Int
}

///|
fn snapshot_dispatch_result_pipeline_cursor(
  cursor : DispatchResultPipelineCursor,
) -> DispatchResultPipelineCursor {
  {
    pipeline: snapshot_dispatch_result_pipeline(cursor.pipeline),
    next_index: cursor.next_index,
  }
}

///|
priv enum DispatchResultPipelineDecision {
  DispatchResultPipelineSuspend(
    DispatchCallRequest,
    DispatchResultPipelineCursor
  )
  DispatchResultPipelineComplete(Value)
}

///|
fn dispatch_result_pipeline_callee_matches(
  token : DispatchResultPipelineCalleeToken,
  callee : Value,
) -> Bool {
  same_value(token.0, callee)
}

///|
fn dispatch_result_pipeline_transition(
  cursor : DispatchResultPipelineCursor,
  previous_result : Value,
) -> DispatchResultPipelineDecision raise InvalidDispatchTransition {
  let pipeline = cursor.pipeline
  guard cursor.next_index >= 0 && cursor.next_index <= pipeline.stages.length() else {
    invalid_dispatch_transition("result pipeline cursor is outside its stages")
  }
  guard cursor.next_index < pipeline.stages.length() else {
    return DispatchResultPipelineComplete(previous_result)
  }
  let stage = pipeline.stages[cursor.next_index]
  guard dispatch_result_pipeline_callee_matches(
    stage.callee_token,
    stage.request.callee,
  ) else {
    invalid_dispatch_transition("result pipeline stage callee token drifted")
  }
  guard stage.result_argument_index >= 0 &&
    stage.result_argument_index < stage.request.args.length() else {
    invalid_dispatch_transition(
      "result pipeline carried-result index is outside request args",
    )
  }
  let args = stage.request.args.copy()
  args[stage.result_argument_index] = previous_result
  let request = DispatchCallRequest(
    callee=stage.request.callee,
    this_value=stage.request.this_value,
    args~,
    loc=stage.request.loc,
  )
  let next_cursor : DispatchResultPipelineCursor = {
    pipeline: snapshot_dispatch_result_pipeline(pipeline),
    next_index: cursor.next_index + 1,
  }
  DispatchResultPipelineSuspend(request, next_cursor)
}

///|
fn direct_return_result_pipeline_helper(
  registry : TrustedDirectReturnRecursionRegistry,
  name : String,
) -> TrustedDirectReturnLeafFunction? {
  for helper in registry.helpers {
    if helper.syntax.name == name {
      return Some(helper)
    }
  }
  None
}

///|
fn direct_return_result_pipeline(
  registry : TrustedDirectReturnRecursionRegistry,
) -> DispatchResultPipeline? {
  let call_plans = match
    direct_return_recursive_call_plans(registry.entry.syntax) {
    Some(call_plans) => call_plans
    None => return None
  }
  let stages : Array[DispatchResultPipelineStage] = []
  for call in call_plans {
    let helper = match
      direct_return_result_pipeline_helper(registry, call.callee_name) {
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
