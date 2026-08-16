///|
// Issue #889 entry-gate REDs. ObjectSpread remains pre-activation unsupported
// until the runtime-owned CopyDataProperties request and frame are complete.

///|
fn issue889_candidate_route_for_wb(
  source : String,
) -> (@runtime.Value, Ref[CandidateRouteEvidence]) raise Error {
  candidate_run_with_evidence_for_wb(source)
}

///|
fn issue889_assert_root_bytecode_for_wb(
  source : String,
  evidence : Ref[CandidateRouteEvidence],
) -> Unit raise Error {
  let root_identity = prepare_candidate_program(@parser.parse(source).stmts).root.source_identity
  let mut prepared = 0
  let mut bytecode_starts = 0
  let mut tree_starts = 0
  for event in evidence.val.events {
    match event {
      CandidateRoutePreparedEvent(item) if
        bytecode_source_identity_coordinates_equal_for_wb(
          item.source_identity,
          root_identity,
        ) => {
        prepared += 1
        match item.decision {
          UseBytecode(_) => ()
          UseTreeWalker(_) => fail("issue 889 root selected Tree-walker")
        }
      }
      CandidateRouteStartedEvent(item) if
        bytecode_source_identity_coordinates_equal_for_wb(
          item.source_identity,
          root_identity,
        ) =>
        match item.executor {
          CandidateBytecodeExecutor => bytecode_starts += 1
          CandidateTreeWalkerExecutor => tree_starts += 1
        }
      _ => ()
    }
  }
  assert_eq(prepared, 1)
  assert_eq(bytecode_starts, 1)
  assert_eq(tree_starts, 0)
}

///|
test "RED issue 889 candidate object spread must start bytecode" {
  let source =
    #|var source = { a: 1, b: 2 };
    #|var copy = { before: 0, ...source, after: 3 };
    #|copy.before + ":" + copy.a + "," + copy.b + "," + copy.after;
  let (value, evidence) = issue889_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "0:1,2,3")
  issue889_assert_root_bytecode_for_wb(source, evidence)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "RED issue 889 candidate preserves object spread source order" {
  let source =
    #|var log = [];
    #|var source = { get z() { log.push("z"); return 2; }, get a() { log.push("a"); return 1; } };
    #|var copy = { ...source };
    #|log.join(",") + ":" + copy.z + ":" + copy.a;
  let (value, evidence) = issue889_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "z,a:2:1")
  issue889_assert_root_bytecode_for_wb(source, evidence)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}
