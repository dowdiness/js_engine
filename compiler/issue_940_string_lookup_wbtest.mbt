///|
// Issue #940: primitive String named-property lookup must observe the live
// String.prototype property before the lazy builtin shortcut.
test "issue 940 primitive String prototype override reaches default and candidate" {
  let source =
    #|String.prototype.toUpperCase = function() { return "override"; };
    #|"hello".toUpperCase();
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "override")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 computed String lookup observes prototype override" {
  let source =
    #|String.prototype.toUpperCase = function() { return "computed override"; };
    #|var key = "toUpperCase";
    #|"hello"[key]();
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "computed override")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 preserves callable Proxy String prototype overrides" {
  let source =
    #|var target = function() { "use strict"; return typeof this + ":" + this; };
    #|String.prototype.toUpperCase = new Proxy(target, {});
    #|"hello".toUpperCase();
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "string:hello")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 propagates revoked Proxy String prototype overrides" {
  let source =
    #|var record = Proxy.revocable(function() { "use strict"; return "proxy"; }, {});
    #|String.prototype.toUpperCase = record.proxy;
    #|record.revoke();
    #|try { "hello".toUpperCase(); } catch (error) { error.name; }
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "TypeError")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 explicit undefined shadows lazy String builtin" {
  let source =
    #|String.prototype.toUpperCase = undefined;
    #|try { "hello".toUpperCase(); } catch (error) { error.name; }
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "TypeError")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 String accessor observes primitive receiver once" {
  let source =
    #|var calls = 0;
    #|Object.defineProperty(String.prototype, "toUpperCase", { get: function() {
    #|  calls = calls + 1;
    #|  return function() { "use strict"; return typeof this + ":" + this; };
    #|} });
    #|"hello".toUpperCase() + ":" + calls;
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "string:hello:1")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 String accessors shadow lazy builtin when getter is absent" {
  let source =
    #|var errors = [];
    #|Object.defineProperty(String.prototype, "toUpperCase", { get: undefined, configurable: true });
    #|try { "hello".toUpperCase(); } catch (error) { errors.push(error.name); }
    #|Object.defineProperty(String.prototype, "toUpperCase", { set: function(_){}, configurable: true });
    #|try { "hello".toUpperCase(); } catch (error) { errors.push(error.name); }
    #|errors.join(":");
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "TypeError:TypeError")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 preserves String indexed properties and length" {
  let source =
    #|"abc"[0] + ":" + "abc".length;
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "a:3")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 observes String prototype chain properties" {
  let source =
    #|var upper = { upperStringMethod: function() {
    #|  "use strict";
    #|  return typeof this + ":" + this;
    #|} };
    #|Object.setPrototypeOf(String.prototype, upper);
    #|"hello".upperStringMethod();
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "string:hello")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 observes String prototype-chain Proxy exactly once" {
  let source =
    #|delete String.prototype.toUpperCase;
    #|var gets = 0;
    #|var receiverKind = "";
    #|var receiverText = "";
    #|var proxyProto = new Proxy({}, { get: function(target, key, receiver) {
    #|  gets = gets + 1;
    #|  receiverKind = typeof receiver;
    #|  receiverText = receiver + "";
    #|  return undefined;
    #|} });
    #|Object.setPrototypeOf(String.prototype, proxyProto);
    #|var errorName = "";
    #|try { "hello".toUpperCase(); } catch (error) { errorName = error.name; }
    #|errorName + ":" + gets + ":" + receiverKind + ":" + receiverText;
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "TypeError:1:string:hello")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 propagates String prototype getter errors without fallback" {
  let source =
    #|Object.defineProperty(String.prototype, "toUpperCase", { get: function() {
    #|  throw "string getter";
    #|}, configurable: true });
    #|try { "hello".toUpperCase(); } catch (error) { error; }
  let default_value = @interpreter.new_interpreter().run(
    @parser.parse(source).stmts,
  )
  let (candidate_value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(default_value.to_string(), "string getter")
  assert_eq(candidate_value.to_string(), default_value.to_string())
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
}

///|
test "issue 940 graduates the unchanged string_ops benchmark" {
  let source = @benchmark_workloads.STRING_OPS_SRC
  let program = prepare_candidate_program(@parser.parse(source).stmts)
  match program.root.selection {
    UseBytecode(_) => ()
    UseTreeWalker(_) => fail("string_ops root selected Tree-walker")
  }
  let (value, evidence) = candidate_run_with_evidence_for_wb(source)
  assert_eq(value.to_string(), "600")
  assert_eq(evidence.val.summary.tree_starts, 0)
  assert_eq(evidence.val.summary.fallback_violations, 0)
  assert_eq(evidence.val.summary.replay_violations, 0)
  assert_eq(evidence.val.summary.active_activations, 0)
  guard evidence.val.summary.bytecode_starts > 0 else {
    fail("string_ops did not start a Bytecode activation")
  }
}
