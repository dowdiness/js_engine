///|
// Issue #889 candidate-route coverage for the runtime-owned CopyDataProperties
// operation and its closed completion boundary.

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
      CandidateRoutePreparedEvent(item) if bytecode_source_identity_coordinates_equal_for_wb(
          item.source_identity,
          root_identity,
        ) => {
        prepared += 1
        match item.decision {
          UseBytecode(_) => ()
          UseTreeWalker(_) => fail("issue 889 root selected Tree-walker")
        }
      }
      CandidateRouteStartedEvent(item) if bytecode_source_identity_coordinates_equal_for_wb(
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
test "issue 889 candidate object spread starts bytecode" {
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
test "issue 889 candidate preserves object spread source order" {
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

///|
test "issue 889 candidate object spread abrupt completion retains lifecycle evidence" {
  let source =
    #|var events = [];
    #|function failSpread() {
    #|  var source = {
    #|    get a() { events.push("a"); queueMicrotask(function() { events.push("m"); }); return 1; },
    #|    get b() { events.push("b"); throw new Error("spread"); }
    #|  };
    #|  return { ...source };
    #|}
    #|var kind = "none";
    #|try { failSpread(); } catch (error) { kind = error instanceof Error ? "Error" : "other"; }
    #|events.join("") + ":" + kind;
  let (value, evidence) = issue889_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "ab:Error")
  assert_true(evidence.val.summary.abrupt_completions > 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 889 candidate object spread supports finite getter re-entry" {
  let source =
    #|function recurse(n) {
    #|  if (n === 0) return 0;
    #|  var source = { get value() { return recurse(n - 1); } };
    #|  return { ...source }.value;
    #|}
    #|recurse(24);
  let (value, evidence) = issue889_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "0")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 889 object rest stays on the pre-start TreeWalker route" {
  let source =
    #|var { x, ...rest } = { x: 1, y: 2 };
    #|rest.y;
  let root = prepare_candidate_program(@parser.parse(source).stmts).root
  match root.selection {
    UseTreeWalker(CandidateActivationUnsupported(_)) => ()
    UseTreeWalker(CandidateLoweringUnsupported(_)) => ()
    UseBytecode(_) => fail("object rest unexpectedly selected bytecode")
  }
  let (value, evidence) = issue889_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "2")
  assert_eq(evidence.val.summary.tree_starts, 1)
  assert_eq(evidence.val.summary.bytecode_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  guard evidence.val.events.length() >= 3 else {
    fail("object rest route evidence is incomplete")
  }
  match evidence.val.events[0] {
    CandidateRoutePreparedEvent(prepared) =>
      match prepared.decision {
        UseTreeWalker(CandidateActivationUnsupported(_)) => ()
        UseTreeWalker(CandidateLoweringUnsupported(_)) => ()
        UseBytecode(_) => fail("object rest prepared bytecode")
      }
    _ => fail("object rest started before its route decision")
  }
  match evidence.val.events[1] {
    CandidateRouteStartedEvent(started) =>
      match started.executor {
        CandidateTreeWalkerExecutor => ()
        CandidateBytecodeExecutor => fail("object rest started bytecode")
      }
    _ => fail("object rest route did not start after preparation")
  }
}

///|
test "issue 889 candidate object spread preserves Proxy trap order" {
  let source =
    #|var events = [];
    #|var target = { a: 1, b: 2 };
    #|var source = new Proxy(target, {
    #|  ownKeys: function() { events.push("keys"); return ["a", "b"]; },
    #|  getOwnPropertyDescriptor: function() { events.push("descriptor"); return { enumerable: true, configurable: true }; },
    #|  get: function(target, key) { events.push("get"); return target[key] + 10; }
    #|});
    #|var copy = { ...source };
    #|events.join(",") + ":" + copy.a + ":" + copy.b;
  let (value, evidence) = issue889_candidate_route_for_wb(source)
  assert_eq(value.to_string(), "keys,descriptor,get,descriptor,get:11:12")
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}
