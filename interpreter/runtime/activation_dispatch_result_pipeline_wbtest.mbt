///|
test "result pipeline suspends one sealed call and consumes its result" {
  let request = DispatchCallRequest(
    callee=String_("id"),
    this_value=Undefined,
    args=[Undefined],
    loc=@token.Loc::default(),
  )
  let stage = match
    validate_dispatch_result_pipeline_stage(
      request~,
      callee_token=DispatchResultPipelineCalleeToken(String_("id")),
      result_argument_index=0,
    ) {
    Some(stage) => stage
    None => fail("expected the valid result pipeline stage")
  }
  let pipeline = match validate_dispatch_result_pipeline(stages=[stage]) {
    Some(pipeline) => pipeline
    None => fail("expected the valid result pipeline")
  }
  let cursor = pipeline.start()
  match dispatch_result_pipeline_transition(cursor, String_("done")) {
    DispatchResultPipelineSuspend(next_request, next_cursor) => {
      guard next_request.args is [String_("done")] else {
        fail("result pipeline did not copy the carried result into the request")
      }
      guard request.args is [Undefined] else {
        fail("result pipeline mutated the sealed request template")
      }
      guard next_cursor.next_index == 1 else {
        fail("result pipeline did not advance one stage")
      }
    }
    DispatchResultPipelineComplete(_) =>
      fail("result pipeline completed before suspending its only stage")
  }
}

///|
test "result pipeline advances monotonically and completes with its value" {
  let loc = @token.Loc::default()
  let inner_stage = match
    validate_dispatch_result_pipeline_stage(
      request=DispatchCallRequest(
        callee=String_("inner"),
        this_value=Undefined,
        args=[Undefined],
        loc~,
      ),
      callee_token=DispatchResultPipelineCalleeToken(String_("inner")),
      result_argument_index=0,
    ) {
    Some(stage) => stage
    None => fail("expected the valid inner result pipeline stage")
  }
  let outer_stage = match
    validate_dispatch_result_pipeline_stage(
      request=DispatchCallRequest(
        callee=String_("outer"),
        this_value=Undefined,
        args=[String_("closed"), Undefined],
        loc~,
      ),
      callee_token=DispatchResultPipelineCalleeToken(String_("outer")),
      result_argument_index=1,
    ) {
    Some(stage) => stage
    None => fail("expected the valid outer result pipeline stage")
  }
  let pipeline = match
    validate_dispatch_result_pipeline(stages=[inner_stage, outer_stage]) {
    Some(pipeline) => pipeline
    None => fail("expected the valid result pipeline")
  }
  let cursor = pipeline.start()
  let (inner_request, outer_cursor) = match
    dispatch_result_pipeline_transition(cursor, String_("seed")) {
    DispatchResultPipelineSuspend(request, next_cursor) =>
      (request, next_cursor)
    DispatchResultPipelineComplete(_) =>
      fail("result pipeline completed before its first stage")
  }
  guard inner_request.args is [String_("seed")] else {
    fail("result pipeline changed the first stage argument order")
  }
  let (outer_request, final_cursor) = match
    dispatch_result_pipeline_transition(outer_cursor, String_("inner")) {
    DispatchResultPipelineSuspend(request, next_cursor) =>
      (request, next_cursor)
    DispatchResultPipelineComplete(_) =>
      fail("result pipeline completed before its final stage")
  }
  guard outer_request.args is [String_("closed"), String_("inner")] else {
    fail("result pipeline changed the second stage argument order")
  }
  guard final_cursor.next_index == 2 else {
    fail("result pipeline cursor did not advance through both stages")
  }
  match dispatch_result_pipeline_transition(final_cursor, String_("done")) {
    DispatchResultPipelineComplete(value) =>
      match value {
        String_("done") => ()
        _ => fail("result pipeline completion changed the final value")
      }
    DispatchResultPipelineSuspend(_, _) =>
      fail("result pipeline suspended after its final stage")
  }
}

///|
test "result pipeline advances one stage at a time through three helpers" {
  let loc = @token.Loc::default()
  let inner_stage = match
    validate_dispatch_result_pipeline_stage(
      request=DispatchCallRequest(
        callee=String_("inner"),
        this_value=Undefined,
        args=[Undefined],
        loc~,
      ),
      callee_token=DispatchResultPipelineCalleeToken(String_("inner")),
      result_argument_index=0,
    ) {
    Some(stage) => stage
    None => fail("expected the valid inner result pipeline stage")
  }
  let middle_stage = match
    validate_dispatch_result_pipeline_stage(
      request=DispatchCallRequest(
        callee=String_("middle"),
        this_value=Undefined,
        args=[String_("closed-middle"), Undefined],
        loc~,
      ),
      callee_token=DispatchResultPipelineCalleeToken(String_("middle")),
      result_argument_index=1,
    ) {
    Some(stage) => stage
    None => fail("expected the valid middle result pipeline stage")
  }
  let outer_stage = match
    validate_dispatch_result_pipeline_stage(
      request=DispatchCallRequest(
        callee=String_("outer"),
        this_value=Undefined,
        args=[String_("closed-outer"), Undefined],
        loc~,
      ),
      callee_token=DispatchResultPipelineCalleeToken(String_("outer")),
      result_argument_index=1,
    ) {
    Some(stage) => stage
    None => fail("expected the valid outer result pipeline stage")
  }
  let pipeline = match
    validate_dispatch_result_pipeline(stages=[
      inner_stage, middle_stage, outer_stage,
    ]) {
    Some(pipeline) => pipeline
    None => fail("expected the valid three-stage result pipeline")
  }
  let (inner_request, middle_cursor) = match
    dispatch_result_pipeline_transition(pipeline.start(), String_("seed")) {
    DispatchResultPipelineSuspend(request, next_cursor) =>
      (request, next_cursor)
    DispatchResultPipelineComplete(_) =>
      fail("three-stage result pipeline completed before inner")
  }
  guard inner_request.callee is String_("inner") &&
    inner_request.args is [String_("seed")] else {
    fail("three-stage result pipeline changed inner semantics")
  }
  let (middle_request, outer_cursor) = match
    dispatch_result_pipeline_transition(middle_cursor, String_("inner-result")) {
    DispatchResultPipelineSuspend(request, next_cursor) =>
      (request, next_cursor)
    DispatchResultPipelineComplete(_) =>
      fail("three-stage result pipeline completed before middle")
  }
  guard middle_request.callee is String_("middle") &&
    middle_request.args is [String_("closed-middle"), String_("inner-result")] else {
    fail("three-stage result pipeline changed middle semantics")
  }
  let (outer_request, final_cursor) = match
    dispatch_result_pipeline_transition(outer_cursor, String_("middle-result")) {
    DispatchResultPipelineSuspend(request, next_cursor) =>
      (request, next_cursor)
    DispatchResultPipelineComplete(_) =>
      fail("three-stage result pipeline completed before outer")
  }
  guard outer_request.callee is String_("outer") &&
    outer_request.args is [String_("closed-outer"), String_("middle-result")] else {
    fail("three-stage result pipeline changed outer semantics")
  }
  match dispatch_result_pipeline_transition(final_cursor, String_("done")) {
    DispatchResultPipelineComplete(String_(value)) =>
      inspect(value, content="done")
    DispatchResultPipelineComplete(_) =>
      fail("three-stage result pipeline changed its final value")
    DispatchResultPipelineSuspend(_, _) =>
      fail("three-stage result pipeline suspended after its final stage")
  }
}

///|
test "result pipeline rejects a drifted sealed callee" {
  let request = DispatchCallRequest(
    callee=String_("changed"),
    this_value=Undefined,
    args=[Undefined],
    loc=@token.Loc::default(),
  )
  let stage = match
    validate_dispatch_result_pipeline_stage(
      request~,
      callee_token=DispatchResultPipelineCalleeToken(String_("id")),
      result_argument_index=0,
    ) {
    Some(stage) => stage
    None => fail("expected the valid result pipeline stage")
  }
  let pipeline = match validate_dispatch_result_pipeline(stages=[stage]) {
    Some(pipeline) => pipeline
    None => fail("expected the valid result pipeline")
  }
  expect_invalid_dispatch(() => {
    let _ = dispatch_result_pipeline_transition(
      pipeline.start(),
      String_("done"),
    )
  })
}

///|
test "result pipeline stage rejects an out-of-bounds slot" {
  let result = validate_dispatch_result_pipeline_stage(
    request=DispatchCallRequest(
      callee=String_("id"),
      this_value=Undefined,
      args=[],
      loc=@token.Loc::default(),
    ),
    callee_token=DispatchResultPipelineCalleeToken(String_("id")),
    result_argument_index=0,
  )
  guard result is None else {
    fail("expected the out-of-bounds slot to be rejected")
  }
}

///|
test "result pipeline validator rejects an empty pipeline" {
  guard validate_dispatch_result_pipeline(stages=[]) is None else {
    fail("expected an empty result pipeline to be rejected")
  }
}
