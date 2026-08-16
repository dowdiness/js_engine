// Focused route-proven benchmark for issue #889.
//
// Run with:
//   moon bench -p compiler -f issue_889_copy_data_properties_benchmark_wbtest.mbt --target native --release

///|
fn issue889_benchmark_route_check(source : String) -> Unit raise Error {
  let (_, evidence) = candidate_run_with_evidence_for_wb(source)
  let mut bytecode_starts = 0
  let mut tree_starts = 0
  for event in evidence.val.events {
    match event {
      CandidateRouteStartedEvent(item) =>
        match item.executor {
          CandidateBytecodeExecutor => bytecode_starts += 1
          CandidateTreeWalkerExecutor => tree_starts += 1
        }
      _ => ()
    }
  }
  guard bytecode_starts > 0 else {
    fail("issue-889 benchmark did not prove a bytecode route")
  }
  guard tree_starts == 0 else {
    fail("issue-889 benchmark unexpectedly used the Tree-walker")
  }
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue-889/object-spread-route-vs-control" (b : @bench.T) {
  let spread_source =
    #|var source = { a: 1, b: 2, c: 3 };
    #|var copy = { ...source };
    #|copy.a + copy.b + copy.c;
  let control_source =
    #|var source = { a: 1, b: 2, c: 3 };
    #|var copy = { a: source.a, b: source.b, c: source.c };
    #|copy.a + copy.b + copy.c;
  issue889_benchmark_route_check(spread_source)
  b.bench(name="managed-object-spread", fn() {
    let (value, _) = candidate_run_with_summary_for_wb(spread_source) catch {
      _ => abort("issue-889 spread benchmark execution failed")
    }
    b.keep(value)
  })
  b.bench(name="no-spread-control", fn() {
    let (value, _) = candidate_run_with_summary_for_wb(control_source) catch {
      _ => abort("issue-889 control benchmark execution failed")
    }
    b.keep(value)
  })
}
