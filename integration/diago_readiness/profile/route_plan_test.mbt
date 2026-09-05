///|
// The JS diagnostic runner calls this linked test-only bridge. Keeping the
// projection here avoids a profiling API on the stable Engine facade.
fn diago_route_plan(source : String) -> String raise Error {
  @compiler.profile_candidate_route_plan_json(@parser.parse(source).stmts).stringify()
}

///|
test "route profile bridge retains a typed static selection" {
  let report = @json.parse(diago_route_plan("1 + 2;"))
  guard report
    is {
      "schema_version": 1,
      "summary": { "functions": 1, "bytecode": 1, "tree": 0, .. },
      ..
    } else {
    fail("unexpected static route profile")
  }
}
