///|
test "completion routing drains 10000 completed statement frames" {
  let mut frames = DispatchFrameStackEmpty
  for id in 0..<10000 {
    frames = DispatchFrameStackNode(
      DispatchStatementFrame(dispatch_test_statement_resume(id)),
      frames,
    )
  }
  let (_, decision) = route_dispatch_completion(
    dispatch_test_ready_state(frames),
    DispatchNormal(Number(42.0)),
  )
  match decision {
    DispatchFinish(DispatchNormal(Number(value))) =>
      inspect(value, content="42")
    _ => fail("expected exact normal completion after draining every frame")
  }
}
