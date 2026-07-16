// Stable embedding usage baselines.
//
// Run with:
//   make embedding-baseline
//
// These rows measure different usage envelopes. Do not divide one result by
// the other to claim a speedup:
//
// - one_shot includes Engine construction, builtin setup, parsing, evaluation,
//   and display-string conversion through @lib.run.
// - persistent starts after Engine construction and rule-source evaluation,
//   and measures one synchronous call plus strict JSON conversion in each
//   direction.

///|
const EMBEDDING_RULE_SOURCE =
  #|let evaluationCount = 0;
  #|function allow(request) {
  #|  evaluationCount += 1;
  #|  const allowed = request.role === "admin" || request.action === "read";
  #|  return { allowed, evaluationCount };
  #|}

///|
const EMBEDDING_ONE_SHOT_SOURCE =
  #|let evaluationCount = 0;
  #|function allow(request) {
  #|  evaluationCount += 1;
  #|  const allowed = request.role === "admin" || request.action === "read";
  #|  return { allowed, evaluationCount };
  #|}
  #|allow({ role: "member", action: "read" }).evaluationCount;

///|
fn embedding_request() -> Json {
  Json::object({
    "role": Json::string("member"),
    "action": Json::string("read"),
  })
}

///|
fn load_embedding_engine() -> @lib.Engine raise @lib.EngineError {
  let engine = @lib.Engine()
  engine.eval(EMBEDDING_RULE_SOURCE)
  engine
}

///|
fn expect_embedding_json(name : String, got : Json, want : String) -> Unit {
  let actual = got.stringify()
  guard actual == want else {
    abort(
      "[\{name}] bench correctness check failed\n  expected: \{want}\n  got:      \{actual}",
    )
  }
}

///|
/// One-shot trusted-rule execution baseline.
///
/// Includes fresh runtime construction, builtin setup, parse, evaluation, and
/// display-string conversion. Excludes MoonBit process startup.
test "embedding/one_shot/run_rule" (b : @bench.T) {
  let (_, got) = @lib.run(EMBEDDING_ONE_SHOT_SOURCE) catch {
    _ => abort("one-shot embedding precheck raised")
  }
  guard got == "1" else {
    abort(
      "[embedding/one_shot/run_rule] bench correctness check failed\n  expected: 1\n  got:      \{got}",
    )
  }
  b.bench(
    fn() {
      let (_, result) = @lib.run(EMBEDDING_ONE_SHOT_SOURCE) catch {
        _ => abort("one-shot embedding baseline raised")
      }
      b.keep(result)
    },
    count=10,
  )
}

///|
/// Repeated persistent Engine call baseline.
///
/// Engine construction and rule-source evaluation happen before timing. Each
/// measured operation converts one fixed MoonBit Json request into JavaScript,
/// calls the synchronous rule, mutates Engine-owned state, and converts the
/// plain-object result back to Json.
test "embedding/persistent/call_json_rule" (b : @bench.T) {
  let precheck = load_embedding_engine() catch {
    _ => abort("persistent embedding setup precheck raised")
  }
  let request = embedding_request()
  let first = precheck.call_json("allow", [request]) catch {
    _ => abort("persistent embedding precheck call raised")
  }
  expect_embedding_json(
    "embedding/persistent/call_json_rule", first, "{\"allowed\":true,\"evaluationCount\":1}",
  )
  let engine = load_embedding_engine() catch {
    _ => abort("persistent embedding measured setup raised")
  }
  b.bench(
    fn() {
      let result = engine.call_json("allow", [request]) catch {
        _ => abort("persistent embedding baseline raised")
      }
      b.keep(result)
    },
    count=10,
  )
}
