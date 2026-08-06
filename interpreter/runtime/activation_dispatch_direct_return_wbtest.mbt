///|
fn direct_return_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
const DIRECT_RETURN_TEST_SOURCE = "function f(n){if(n===0)return \"done\";return f(n-1);}f(256);"

///|
const DIRECT_RETURN_LEAF_TEST_SOURCE = "function leaf(){return \"done\";}function f(n){if(n===0)return leaf();return f(n-1);}f(256);"

///|
const DIRECT_RETURN_LEAF_THROW_SOURCE = "function leaf(){throw \"boom\";}function f(n){if(n===0)return leaf();return f(n-1);}f(256);"

///|
const DIRECT_RETURN_ARGUMENT_LEAF_TEST_SOURCE = "function leaf(value){return value;}function f(n){if(n===0)return leaf(\"done\");return f(n-1);}f(256);"

///|
const DIRECT_RETURN_ARGUMENT_LEAF_THROW_SOURCE = "function leaf(value){throw value;}function f(n){if(n===0)return leaf(\"boom\");return f(n-1);}f(256);"

///|
const DIRECT_RETURN_ARGUMENT_VECTOR_LEAF_TEST_SOURCE = "function leaf(ignored,value){return value;}function f(n){if(n===0)return leaf(\"ignored\",\"done\");return f(n-1);}f(256);"

///|
const DIRECT_RETURN_ARGUMENT_VECTOR_LEAF_THROW_SOURCE = "function leaf(ignored,value){throw value;}function f(n){if(n===0)return leaf(\"ignored\",\"boom\");return f(n-1);}f(256);"

///|
const DIRECT_RETURN_RESULT_FED_LEAF_TEST_SOURCE = "function id(x){return x;}function f(n){if(n===0)return \"done\";return id(f(n-1));}f(256);"

///|
const DIRECT_RETURN_TWO_HELPER_RESULT_FED_TEST_SOURCE = "function inner(value){return value;}function outer(ignored,value){return value;}function f(n){if(n===0)return \"done\";return outer(\"ignored\",inner(f(n-1)));}f(256);"

///|
const DIRECT_RETURN_RESULT_FED_LEAF_THROW_SOURCE = "function id(x){throw x;}function f(n){if(n===0)return \"boom\";return id(f(n-1));}f(256);"

///|
const DIRECT_RETURN_TWO_HELPER_INNER_THROW_SOURCE = "function inner(value){throw value;}function outer(ignored,value){return value;}function f(n){if(n===0)return \"inner-boom\";return outer(\"ignored\",inner(f(n-1)));}f(256);"

///|
const DIRECT_RETURN_TWO_HELPER_OUTER_THROW_SOURCE = "function inner(value){return value;}function outer(ignored,value){throw value;}function f(n){if(n===0)return \"outer-boom\";return outer(\"ignored\",inner(f(n-1)));}f(256);"

///|
const DIRECT_RETURN_MIXED_ARGUMENT_RESULT_FED_TEST_SOURCE = "function leaf(ignored,value){return value;}function f(n){if(n===0)return \"done\";return leaf(\"ignored\",f(n-1));}f(256);"

///|
const DIRECT_RETURN_REVERSED_MIXED_ARGUMENT_RESULT_FED_TEST_SOURCE = "function leaf(value,ignored){return value;}function f(n){if(n===0)return \"done\";return leaf(f(n-1),\"ignored\");}f(256);"

///|
const DIRECT_RETURN_MIXED_ARGUMENT_RESULT_FED_LEAF_THROW_SOURCE = "function leaf(ignored,value){throw value;}function f(n){if(n===0)return \"boom\";return leaf(\"ignored\",f(n-1));}f(256);"

///|
const DIRECT_RETURN_WRAPPED_RESULT_FED_TEST_SOURCE = "function id(x){return x;}function f(n){if(n===0)return \"done\";return id(f(n-1));}function entry(){return f(256);}entry();"

///|
const DIRECT_RETURN_WRAPPED_RESULT_FED_THROW_SOURCE = "function id(x){throw x;}function f(n){if(n===0)return \"done\";return id(f(n-1));}function entry(){return f(256);}entry();"

///|
const DIRECT_RETURN_WRAPPED_BASE_LEAF_TEST_SOURCE = "function id(){return \"done\";}function f(n){if(n===0)return id();return f(n-1);}function entry(){return f(256);}entry();"

///|
const DIRECT_RETURN_WRAPPED_RECURSIVE_NAME_COLLISION_SOURCE = "function id(x){return x;}function entry(n){if(n===0)return \"done\";return id(entry(n-1));}function entry(){return entry(256);}entry();"

///|
const DIRECT_RETURN_WRAPPED_LEAF_NAME_COLLISION_SOURCE = "function entry(x){return x;}function f(n){if(n===0)return \"done\";return entry(f(n-1));}function entry(){return f(256);}entry();"

///|
test "direct-return admission recognizes the exact ordinary function shape" {
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact direct-return shape to be admitted")
  }
  inspect(plan.entry.syntax.name, content="f")
  inspect(plan.entry.syntax.parameter, content="n")
  inspect(plan.entry.syntax.recursive_callee, content="f")
  match plan.root_invocation {
    DirectReturnEntryInvocation(root) =>
      inspect(root.initial_argument, content="256")
    DirectReturnWrappedInvocation(_) =>
      fail("expected direct entry invocation for the direct root fixture")
  }
  match plan.entry.syntax.base_completion {
    DirectReturnBaseValue(DirectReturnClosedString(value)) =>
      inspect(value, content="done")
    _ => fail("expected a closed string return completion")
  }
  let interp = Interpreter::new()
  inspect(
    root_admission_test_kind(
      interp.classify_activation_dispatch_root_program(stmts),
    ),
    content="direct-return",
  )
}

///|
test "direct-return admission recognizes the closed throw twin" {
  let stmts = direct_return_test_program(
    "function f(n){if(n===0)throw \"boom\";return f(n-1);}f(256);",
  )
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact direct-return throw shape to be admitted")
  }
  match plan.entry.syntax.base_completion {
    DirectReturnBaseThrow(DirectReturnClosedString(value)) =>
      inspect(value, content="boom")
    _ => fail("expected a closed string throw completion")
  }
}

///|
test "direct-return admission recognizes a sealed leaf callee" {
  let stmts = direct_return_test_program(DIRECT_RETURN_LEAF_TEST_SOURCE)
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact direct-return leaf shape to be admitted")
  }
  inspect(plan.entry.syntax.name, content="f")
  let leaf = match plan.first_helper() {
    Some(found) => found
    None => fail("expected a sealed direct-return leaf plan")
  }
  inspect(leaf.syntax.name, content="leaf")
  inspect(leaf.declaration_index, content="0")
  inspect(plan.entry.declaration_index, content="1")
  match plan.entry.syntax.base_completion {
    DirectReturnBaseLeafCall({ callee_name: name, .. }) =>
      inspect(name, content="leaf")
    _ => fail("expected the base completion to call the sealed leaf")
  }
  match leaf.syntax.leaf_completion {
    DirectReturnLeafClosedValue(DirectReturnClosedString(value)) =>
      inspect(value, content="done")
    _ => fail("expected the leaf to return a closed string")
  }
}

///|
test "direct-return admission owns a result-fed leaf call plan" {
  let stmts = direct_return_test_program(
    DIRECT_RETURN_RESULT_FED_LEAF_TEST_SOURCE,
  )
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the result-fed direct-return shape to be admitted")
  }
  guard plan.entry.syntax.base_completion
    is DirectReturnBaseValue(DirectReturnClosedString("done")) else {
    fail("expected a closed base value before the result-fed call")
  }
  guard plan.entry.syntax.recursive_completion
    is DirectReturnRecursiveResultFedLeafCall(
      {
        callee_name: "id",
        call_loc: outer_loc,
        argument_sources: [DirectReturnLeafCarriedResult(inner_loc)],
      }
    ) &&
    outer_loc != inner_loc else {
    fail("expected one sealed recursive-result argument source")
  }
  let leaf = match plan.first_helper() {
    Some(found) => found
    None => fail("expected the sealed helper declaration")
  }
  json_inspect(leaf.syntax.parameters, content=["x"])
  guard leaf.syntax.leaf_completion
    is DirectReturnLeafParameterValue({ name: "x", index: 0, .. }) else {
    fail("expected the helper to return its sole parameter")
  }
}

///|
test "direct-return admission owns an ordered two-helper carried-result plan" {
  let stmts = direct_return_test_program(
    DIRECT_RETURN_TWO_HELPER_RESULT_FED_TEST_SOURCE,
  )
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the two-helper direct-return shape to be admitted")
  }
  inspect(plan.helpers.length(), content="2")
  inspect(plan.helpers[0].syntax.name, content="inner")
  inspect(plan.helpers[0].declaration_index, content="0")
  inspect(plan.helpers[1].syntax.name, content="outer")
  inspect(plan.helpers[1].declaration_index, content="1")
  inspect(plan.entry.declaration_index, content="2")
  guard plan.entry.syntax.recursive_completion
    is DirectReturnRecursiveResultFedCallChain(
      { calls: [inner_call, outer_call] }
    ) else {
    fail("expected the ordered two-stage carried-result chain")
  }
  guard inner_call.callee_name == "inner" &&
    inner_call.argument_sources is [DirectReturnLeafCarriedResult(_)] &&
    outer_call.callee_name == "outer" &&
    outer_call.argument_sources
    is [DirectReturnLeafClosedArgument(_), DirectReturnLeafCarriedResult(_)] else {
    fail("expected inner then outer carried-result argument recipes")
  }
}

///|
test "direct-return admission rejects two-helper order and shape drift" {
  for
    source in [
      "function outer(ignored,value){return value;}function inner(value){return value;}function f(n){if(n===0)return \"done\";return outer(\"ignored\",inner(f(n-1)));}f(256);",
      "function inner(value){return value;}function f(n){if(n===0)return \"done\";return outer(\"ignored\",inner(f(n-1)));}f(256);",
      "function inner(value){return value;}function outer(ignored,value){return value;}function f(n){if(n===0)return \"done\";return outer(\"ignored\",inner(f(n-1),0));}f(256);",
      "function inner(value){return value;}function outer(ignored,value){return value;}function f(n){if(n===0)return \"done\";return outer(\"ignored\",(inner)(f(n-1)));}f(256);",
    ] {
    guard classify_direct_return_recursion_program(
        direct_return_test_program(source),
      )
      is None else {
      fail("unexpectedly admitted two-helper near miss: " + source)
    }
  }
}

///|
test "direct-return admission owns ordered closed and recursive argument sources" {
  let stmts = direct_return_test_program(
    DIRECT_RETURN_MIXED_ARGUMENT_RESULT_FED_TEST_SOURCE,
  )
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the mixed result-fed direct-return shape")
  }
  guard plan.entry.syntax.recursive_completion
    is DirectReturnRecursiveResultFedLeafCall(
      {
        callee_name: "leaf",
        call_loc: outer_loc,
        argument_sources: [
          DirectReturnLeafClosedArgument(
            { literal: DirectReturnClosedString("ignored"), loc: closed_loc }
          ),
          DirectReturnLeafCarriedResult(inner_loc),
        ],
      }
    ) &&
    outer_loc != inner_loc &&
    closed_loc != inner_loc else {
    fail("expected ordered closed and recursive argument sources")
  }
  let leaf = match plan.first_helper() {
    Some(found) => found
    None => fail("expected the sealed mixed-argument helper")
  }
  json_inspect(leaf.syntax.parameters, content=["ignored", "value"])
  guard leaf.syntax.leaf_completion
    is DirectReturnLeafParameterValue({ name: "value", index: 1, .. }) else {
    fail("expected the helper to return the recursive-result parameter")
  }
}

///|
test "direct-return admission owns recursive and closed argument sources in order" {
  let stmts = direct_return_test_program(
    DIRECT_RETURN_REVERSED_MIXED_ARGUMENT_RESULT_FED_TEST_SOURCE,
  )
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the reverse mixed result-fed direct-return shape")
  }
  guard plan.entry.syntax.recursive_completion
    is DirectReturnRecursiveResultFedLeafCall(
      {
        callee_name: "leaf",
        call_loc: outer_loc,
        argument_sources: [
          DirectReturnLeafCarriedResult(inner_loc),
          DirectReturnLeafClosedArgument(
            { literal: DirectReturnClosedString("ignored"), loc: closed_loc }
          ),
        ],
      }
    ) &&
    outer_loc != inner_loc &&
    closed_loc != inner_loc else {
    fail("expected recursive and closed argument sources in source order")
  }
  let leaf = match plan.first_helper() {
    Some(found) => found
    None => fail("expected the sealed reverse mixed-argument helper")
  }
  json_inspect(leaf.syntax.parameters, content=["value", "ignored"])
  guard leaf.syntax.leaf_completion
    is DirectReturnLeafParameterValue({ name: "value", index: 0, .. }) else {
    fail("expected the helper to return its recursive-result parameter")
  }
}

///|
test "direct-return admission rejects multiple recursive-result arguments" {
  let source = "function leaf(left,right){return right;}" +
    "function f(n){if(n===0)return \"done\";return leaf(f(n-1),f(n-1));}" +
    "f(256);"
  guard classify_direct_return_recursion_program(
      direct_return_test_program(source),
    )
    is None else {
    fail("multiple recursive-result arguments must remain outside admission")
  }
}

///|
test "direct-return admission owns a wrapped root invocation" {
  let stmts = direct_return_test_program(
    DIRECT_RETURN_WRAPPED_RESULT_FED_TEST_SOURCE,
  )
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the wrapped result-fed direct-return shape")
  }
  guard plan.entry.syntax.recursive_completion
    is DirectReturnRecursiveResultFedLeafCall(_) else {
    fail("expected wrapper fixture to retain its result-fed completion")
  }
  guard plan.first_helper() is Some(_) else {
    fail("expected wrapper fixture to retain its sealed helper")
  }
  match plan.root_invocation {
    DirectReturnWrappedInvocation(wrapper) => {
      inspect(wrapper.declaration_index, content="2")
      inspect(wrapper.syntax.name, content="entry")
      inspect(wrapper.syntax.entry_name, content="f")
      inspect(wrapper.initial_argument, content="256")
      guard wrapper.syntax.inner_call_loc != wrapper.outer_call_loc else {
        fail("expected distinct inner and outer wrapper locations")
      }
    }
    DirectReturnEntryInvocation(_) =>
      fail("expected a sealed wrapped root invocation")
  }
}

///|
test "direct-return wrapped root rejects a recursive-name collision" {
  guard classify_direct_return_recursion_program(
      direct_return_test_program(
        DIRECT_RETURN_WRAPPED_RECURSIVE_NAME_COLLISION_SOURCE,
      ),
    )
    is None else {
    fail("RED: wrapper name collision with recursive entry was admitted")
  }
}

///|
test "direct-return wrapped root rejects a leaf-name collision" {
  guard classify_direct_return_recursion_program(
      direct_return_test_program(
        DIRECT_RETURN_WRAPPED_LEAF_NAME_COLLISION_SOURCE,
      ),
    )
    is None else {
    fail("RED: wrapper name collision with leaf was admitted")
  }
}

///|
test "direct-return wrapped root balances the extra ordinary activation" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_WRAPPED_RESULT_FED_TEST_SOURCE,
  )
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    String_(value) => inspect(value, content="done")
    other =>
      fail("expected wrapped direct-return result, got " + other.to_string())
  }
  inspect(probe.attempts, content="514")
  inspect(probe.acquired, content="514")
  inspect(probe.accepted, content="514")
  inspect(probe.rejected, content="0")
  inspect(probe.released, content="514")
  inspect(probe.denied, content="0")
  inspect(probe.active, content="0")
  inspect(probe.maximum_active, content="258")
  inspect(probe.release_ordinals.length(), content="514")
  inspect(probe.lifo_violations, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "direct-return wrapped root preserves helper throw identity" {
  let interp = Interpreter::new()
  let result = try {
    let _ = interp.run(
      direct_return_test_program(DIRECT_RETURN_WRAPPED_RESULT_FED_THROW_SOURCE),
    )
    "no throw"
  } catch {
    JsException(String_(value)) => value
    _ => "wrong throw"
  }
  inspect(result, content="done")
}

///|
test "direct-return wrapped result-fed throw observes its helper activation" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_WRAPPED_RESULT_FED_THROW_SOURCE,
  )
  let result = try {
    let _ = activation_dispatch_root_value(shell.drive_root_program(stmts, ctx))
    "no throw"
  } catch {
    JsException(String_(value)) => value
    _ => "wrong throw"
  }
  inspect(result, content="done")
  inspect(probe.attempts, content="259")
  inspect(probe.acquired, content="259")
  inspect(probe.released, content="259")
  inspect(probe.active, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "direct-return wrapped root routes a base leaf call" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_WRAPPED_BASE_LEAF_TEST_SOURCE,
  )
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    String_(value) => inspect(value, content="done")
    other => fail("expected wrapped base leaf result, got " + other.to_string())
  }
  expect_dispatch_observation_balanced(probe, 259)
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "direct-return syntax snapshots payload leaf plans" {
  let loc = @token.Loc::default()
  let argument = DirectReturnClosedArgument(
    literal=DirectReturnClosedString("done"),
    loc~,
  )
  let argument_sources = [DirectReturnLeafClosedArgument(argument)]
  let plan = DirectReturnLeafCallPlan(
    callee_name="leaf",
    call_loc=loc,
    argument_sources~,
  )
  let recursive_sources = [DirectReturnLeafCarriedResult(loc)]
  let recursive_plan = DirectReturnLeafCallPlan(
    callee_name="id",
    call_loc=loc,
    argument_sources=recursive_sources,
  )
  let syntax = DirectReturnFunctionSyntax(
    name="f",
    parameter="n",
    recursive_callee="f",
    base_condition_loc=loc,
    base_literal_loc=loc,
    recursive_call_loc=loc,
    recursive_subtract_loc=loc,
    base_completion=DirectReturnBaseLeafCall(plan),
    recursive_completion=DirectReturnRecursiveResultFedLeafCall(recursive_plan),
  )
  argument_sources[0] = DirectReturnLeafClosedArgument(
    DirectReturnClosedArgument(
      literal=DirectReturnClosedString("changed"),
      loc~,
    ),
  )
  plan.argument_sources[0] = DirectReturnLeafClosedArgument(
    DirectReturnClosedArgument(
      literal=DirectReturnClosedString("changed-again"),
      loc~,
    ),
  )
  recursive_sources[0] = DirectReturnLeafClosedArgument(argument)
  recursive_plan.argument_sources[0] = DirectReturnLeafClosedArgument(argument)
  guard syntax.base_completion
    is DirectReturnBaseLeafCall(
      {
        argument_sources: [
          DirectReturnLeafClosedArgument(
            { literal: DirectReturnClosedString("done"), .. }
          ),
        ],
        ..,
      }
    ) else {
    fail("expected syntax to own an immutable leaf-plan snapshot")
  }
  guard syntax.recursive_completion
    is DirectReturnRecursiveResultFedLeafCall(
      { argument_sources: [DirectReturnLeafCarriedResult(_)], .. }
    ) else {
    fail("expected recursive syntax to own an immutable leaf-plan snapshot")
  }
}

///|
test "direct-return admission owns a bound leaf argument plan" {
  let stmts = direct_return_test_program(
    DIRECT_RETURN_ARGUMENT_LEAF_TEST_SOURCE,
  )
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the bound direct-return leaf shape to be admitted")
  }
  let leaf = match plan.first_helper() {
    Some(found) => found
    None => fail("expected a bound direct-return leaf plan")
  }
  json_inspect(leaf.syntax.parameters, content=["value"])
  guard leaf.syntax.leaf_completion
    is DirectReturnLeafParameterValue({ name: "value", index: 0, .. }) else {
    fail("expected the leaf to return its sealed parameter")
  }
  guard plan.entry.syntax.base_completion
    is DirectReturnBaseLeafCall(
      {
        argument_sources: [
          DirectReturnLeafClosedArgument(
            { literal: DirectReturnClosedString("done"), .. }
          ),
        ],
        ..,
      }
    ) else {
    fail("expected one sealed string call argument with its location")
  }
}

///|
test "direct-return admission owns an ordered argument vector plan" {
  let stmts = direct_return_test_program(
    DIRECT_RETURN_ARGUMENT_VECTOR_LEAF_TEST_SOURCE,
  )
  let plan = match classify_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the ordered direct-return leaf shape to be admitted")
  }
  let leaf = match plan.first_helper() {
    Some(found) => found
    None => fail("expected an ordered direct-return leaf plan")
  }
  json_inspect(leaf.syntax.parameters, content=["ignored", "value"])
  guard leaf.syntax.leaf_completion
    is DirectReturnLeafParameterValue({ name: "value", index: 1, .. }) else {
    fail("expected the leaf to return argument index one")
  }
  guard plan.entry.syntax.base_completion
    is DirectReturnBaseLeafCall(
      {
        argument_sources: [
          DirectReturnLeafClosedArgument(
            { literal: DirectReturnClosedString("ignored"), loc: first_loc }
          ),
          DirectReturnLeafClosedArgument(
            { literal: DirectReturnClosedString("done"), loc: second_loc }
          ),
        ],
        ..,
      }
    ) &&
    first_loc != second_loc else {
    fail("expected two ordered sealed arguments with distinct locations")
  }
}

///|
test "direct-return argument vector rejects unsupported arity" {
  guard classify_direct_return_recursion_program(
      direct_return_test_program(
        "function leaf(a,b,c){return c;}function f(n){if(n===0)return leaf(\"a\",\"b\",\"c\");return f(n-1);}f(256);",
      ),
    )
    is None else {
    fail("unexpectedly admitted a three-argument direct-return leaf")
  }
}

///|
test "direct-return argument vector rejects duplicate parameters" {
  guard classify_direct_return_recursion_program(
      direct_return_test_program(
        "function leaf(value,value){return value;}function f(n){if(n===0)return leaf(\"first\",\"second\");return f(n-1);}f(256);",
      ),
    )
    is None else {
    fail("unexpectedly admitted duplicate direct-return parameters")
  }
}

///|
test "direct-return leaf admission rejects exact-shape near misses" {
  for
    source in [
      "function f(n){if(n===0)return leaf();return f(n-1);}function leaf(){return \"done\";}f(256);",
      "function leaf(x){return \"done\";}function f(n){if(n===0)return leaf();return f(n-1);}f(256);",
      "function leaf(){return String(\"done\");}function f(n){if(n===0)return leaf();return f(n-1);}f(256);",
      "function leaf(){return \"done\";}function f(n){if(n===0)return leaf(0);return f(n-1);}f(256);",
      "function leaf(){return \"done\";}function f(n){if(n===0)return (leaf)();return f(n-1);}f(256);",
      "function leaf(){return \"done\";}function f(n){if(n===0)return leaf();return f(n-1);}f(255);",
      "function leaf(){return \"done\";}function f(n){if(n===0)return leaf();return f(n-1);}f(256);0;",
      "function leaf(){\"use strict\";return \"done\";}function f(n){if(n===0)return leaf();return f(n-1);}f(256);",
      "function n(){return \"done\";}function f(n){if(n===0)return n();return f(n-1);}f(256);",
      "function leaf(value,extra){return value;}function f(n){if(n===0)return leaf(\"done\");return f(n-1);}f(256);",
      "function leaf(value=\"done\"){return value;}function f(n){if(n===0)return leaf(\"done\");return f(n-1);}f(256);",
      "function leaf(...value){return value;}function f(n){if(n===0)return leaf(\"done\");return f(n-1);}f(256);",
      "function leaf(eval){return eval;}function f(n){if(n===0)return leaf(\"done\");return f(n-1);}f(256);",
      "function leaf(arguments){return arguments;}function f(n){if(n===0)return leaf(\"done\");return f(n-1);}f(256);",
      "function leaf(leaf){return leaf;}function f(n){if(n===0)return leaf(\"done\");return f(n-1);}f(256);",
      "function leaf(value){return other;}function f(n){if(n===0)return leaf(\"done\");return f(n-1);}f(256);",
      "function leaf(value){return value+\"\";}function f(n){if(n===0)return leaf(\"done\");return f(n-1);}f(256);",
      "function leaf(value){return value;}function f(n){if(n===0)return leaf();return f(n-1);}f(256);",
      "function leaf(value){return value;}function f(n){if(n===0)return leaf(\"done\",\"extra\");return f(n-1);}f(256);",
      "function leaf(value){return value;}function f(n){if(n===0)return leaf(String(\"done\"));return f(n-1);}f(256);",
      "function id(x){return x;}function f(n){if(n===0)return \"done\";return id(f(n-1),0);}f(256);",
      "function id(x){return x;}function f(n){if(n===0)return \"done\";return id(0,f(n-1));}f(256);",
      "function id(x){return x;}function f(n){if(n===0)return \"done\";return (id)(f(n-1));}f(256);",
      "function id(x){return x;}function f(n){if(n===0)return \"done\";return id((f)(n-1));}f(256);",
      "function id(x){return x;}function f(n){if(n===0)return \"done\";return id(f(n-2));}f(256);",
      "function id(x){return x;}function f(n){if(n===0)return \"done\";return id(f(n-1));}f(255);",
      "function f(n){if(n===0)return \"done\";return id(f(n-1));}function id(x){return x;}f(256);",
      "function id(x){return x;0;}function f(n){if(n===0)return \"done\";return id(f(n-1));}f(256);",
      "function id(x=0){return x;}function f(n){if(n===0)return \"done\";return id(f(n-1));}f(256);",
      "function id(...x){return x;}function f(n){if(n===0)return \"done\";return id(f(n-1));}f(256);",
    ] {
    guard classify_direct_return_recursion_program(
        direct_return_test_program(source),
      )
      is None else {
      fail("unexpectedly admitted direct-return leaf near miss: " + source)
    }
  }
}

///|
test "direct-return admission rejects exact-shape near misses" {
  for
    source in [
      "function f(n){if(n===0)return leaf();return f(n-1);}f(256);", "function f(n){if(n===0)return missing();return f(n-1);}f(256);",
      "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);", "function f(n){if(n==0)return \"done\";return f(n-1);}f(256);",
      "function f(n){if(n===0){return \"done\";}return f(n-1);}f(256);", "function f(n){if(n===0)return n;return f(n-1);}f(256);",
      "function f(n){if(n===0)return \"done\";return f(n-2);}f(256);", "function f(n){if(n===0)return \"done\";return (f)(n-1);}f(256);",
      "function f(n){if(n===0)return \"done\";return f(n-1);}f(255);", "function f(n){if(n===0)return \"done\";return f(n-1);}f(256);0;",
      "function f(n=0){if(n===0)return \"done\";return f(n-1);}f(256);", "function* f(n){if(n===0)return \"done\";return f(n-1);}f(256);",
      "function eval(n){if(n===0)return \"done\";return eval(n-1);}eval(256);", "function arguments(n){if(n===0)return \"done\";return arguments(n-1);}arguments(256);",
      "function f(n){return f(n-1);if(n===0)return \"done\";}f(256);", "function f(n){if(n===0)return \"done\";return f(n-1);}f(256,0);",
      "function f(n){if(n===0)return \"done\";return f(n-1);}({f:f}).f(256);", "function f(n){if(n===0)return \"done\";return f(n-1);}g(256);",
      "function f(n){\"use strict\";if(n===0)return \"done\";return f(n-1);}f(256);",
    ] {
    guard classify_direct_return_recursion_program(
        direct_return_test_program(source),
      )
      is None else {
      fail("unexpectedly admitted direct-return near miss: " + source)
    }
  }
}

///|
fn direct_return_observation_fixture_for_source(
  interp : Interpreter,
  probe : DispatchObservationProbe,
  source : String,
) -> (PrimitiveProgramDispatchShell, Array[@ast.Stmt], ExecContext) raise {
  let stmts = direct_return_test_program(source)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected exact direct-return preflight")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    activation_observation_port=probe.port(),
  )
  (shell, stmts, { strict: false, current_generator: None })
}

///|
fn direct_return_observation_fixture(
  interp : Interpreter,
  probe : DispatchObservationProbe,
) -> (PrimitiveProgramDispatchShell, Array[@ast.Stmt], ExecContext) raise {
  direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_TEST_SOURCE,
  )
}

///|
fn run_direct_return_shell_source_once(
  interp : Interpreter,
  source : String,
  expected_count : Int,
) -> Value raise Error {
  let probe = DispatchObservationProbe()
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp, probe, source,
  )
  let value = activation_dispatch_root_value(
    shell.drive_root_program(stmts, ctx),
  )
  expect_dispatch_observation_balanced(probe, expected_count)
  inspect(shell.cleanup_stack.length(), content="0")
  value
}

///|
fn expect_result_fed_dispatch_observation_balanced(
  probe : DispatchObservationProbe,
) -> Unit raise {
  inspect(probe.attempts, content="513")
  inspect(probe.acquired, content="513")
  inspect(probe.accepted, content="513")
  inspect(probe.rejected, content="0")
  inspect(probe.released, content="513")
  inspect(probe.denied, content="0")
  inspect(probe.active, content="0")
  // Result-fed helper calls happen while the recursive chain unwinds, so the
  // peak is the 257-entry f chain rather than all 513 observations at once.
  inspect(probe.maximum_active, content="257")
  inspect(probe.release_ordinals.length(), content="513")
  inspect(probe.lifo_violations, content="0")
}

///|
fn expect_two_helper_result_fed_dispatch_observation_balanced(
  probe : DispatchObservationProbe,
) -> Unit raise {
  inspect(probe.attempts, content="769")
  inspect(probe.acquired, content="769")
  inspect(probe.accepted, content="769")
  inspect(probe.rejected, content="0")
  inspect(probe.released, content="769")
  inspect(probe.denied, content="0")
  inspect(probe.active, content="0")
  inspect(probe.maximum_active, content="257")
  inspect(probe.release_ordinals.length(), content="769")
  inspect(probe.lifo_violations, content="0")
}

///|
fn run_direct_return_result_fed_shell_once(
  interp : Interpreter,
  source : String,
  expected_observations? : Int = 513,
) -> Value raise Error {
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp, probe, source,
  )
  let value = activation_dispatch_root_value(
    shell.drive_root_program(stmts, ctx),
  )
  match expected_observations {
    513 => expect_result_fed_dispatch_observation_balanced(probe)
    769 => expect_two_helper_result_fed_dispatch_observation_balanced(probe)
    _ => fail("unsupported result-fed observation count")
  }
  inspect(shell.cleanup_stack.length(), content="0")
  value
}

///|
fn expect_wrapped_result_fed_dispatch_observation_balanced(
  probe : DispatchObservationProbe,
) -> Unit raise {
  inspect(probe.attempts, content="514")
  inspect(probe.acquired, content="514")
  inspect(probe.accepted, content="514")
  inspect(probe.rejected, content="0")
  inspect(probe.released, content="514")
  inspect(probe.denied, content="0")
  inspect(probe.active, content="0")
  inspect(probe.maximum_active, content="258")
  inspect(probe.release_ordinals.length(), content="514")
  inspect(probe.lifo_violations, content="0")
}

///|
fn run_direct_return_wrapped_result_fed_shell_once(
  interp : Interpreter,
) -> Value raise Error {
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_WRAPPED_RESULT_FED_TEST_SOURCE,
  )
  let value = activation_dispatch_root_value(
    shell.drive_root_program(stmts, ctx),
  )
  expect_wrapped_result_fed_dispatch_observation_balanced(probe)
  inspect(shell.cleanup_stack.length(), content="0")
  value
}

///|
fn run_direct_return_shell_once(interp : Interpreter) -> Value raise Error {
  run_direct_return_shell_source_once(interp, DIRECT_RETURN_TEST_SOURCE, 257)
}

///|
test "direct-return observation balances every nested ordinary call" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 109)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture(interp, probe)
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    String_(value) => inspect(value, content="done")
    other => fail("expected direct-return completion, got " + other.to_string())
  }
  expect_nested_dispatch_observation_balanced(probe)
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 109)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected caller source identity to be restored")
  }
}

///|
test "direct-return leaf catalog balances entry and leaf activations" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 127)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_LEAF_TEST_SOURCE,
  )
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    String_(value) => inspect(value, content="done")
    other =>
      fail("expected direct-return leaf result, got " + other.to_string())
  }
  expect_dispatch_observation_balanced(probe, 258)
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 127)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected caller source identity to be restored")
  }
}

///|
test "direct-return result-fed leaf balances every ordinary activation" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 131)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  match
    run_direct_return_result_fed_shell_once(
      interp,
      DIRECT_RETURN_RESULT_FED_LEAF_TEST_SOURCE,
    ) {
    String_(value) => inspect(value, content="done")
    other =>
      fail("expected result-fed direct-return result, got " + other.to_string())
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 131)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected caller source identity to be restored")
  }
}

///|
test "direct-return two-helper carried-result pipeline balances every activation" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 132)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_TWO_HELPER_RESULT_FED_TEST_SOURCE,
  )
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    String_(value) => inspect(value, content="done")
    other =>
      fail("expected two-helper direct-return result, got " + other.to_string())
  }
  expect_two_helper_result_fed_dispatch_observation_balanced(probe)
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 132)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected caller source identity after two-helper run")
  }
}

///|
test "direct-return recursive-result and closed argument order balances every ordinary activation" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 133)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  match
    run_direct_return_result_fed_shell_once(
      interp,
      DIRECT_RETURN_REVERSED_MIXED_ARGUMENT_RESULT_FED_TEST_SOURCE,
    ) {
    String_(value) => inspect(value, content="done")
    other =>
      fail(
        "expected recursive-result/closed mixed direct-return result, got " +
        other.to_string(),
      )
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 133)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected caller source identity to be restored")
  }
}

///|
test "direct-return bound leaf balances argument activation lifecycle" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 137)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_ARGUMENT_LEAF_TEST_SOURCE,
  )
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    String_(value) => inspect(value, content="done")
    other =>
      fail("expected bound direct-return leaf result, got " + other.to_string())
  }
  expect_dispatch_observation_balanced(probe, 258)
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 137)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected caller source identity to be restored")
  }
}

///|
test "direct-return argument vector balances activation lifecycle" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 143)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let (shell, stmts, ctx) = direct_return_observation_fixture_for_source(
    interp,
    probe,
    DIRECT_RETURN_ARGUMENT_VECTOR_LEAF_TEST_SOURCE,
  )
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    String_(value) => inspect(value, content="done")
    other =>
      fail(
        "expected ordered direct-return leaf result, got " + other.to_string(),
      )
  }
  expect_dispatch_observation_balanced(probe, 258)
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 143)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected caller source identity to be restored")
  }
}

///|
test "direct-return closed throw crosses depth 256 without host recursion" {
  let interp = Interpreter::new()
  let source = "function f(n){if(n===0)throw \"boom\";return f(n-1);}f(256);"
  let result = try {
    let _ = interp.run(direct_return_test_program(source))
    "no throw"
  } catch {
    JsException(String_(value)) => value
    _ => "wrong throw"
  }
  inspect(result, content="boom")
}

///|
fn run_direct_return_result_fed_throw(
  interp : Interpreter,
  source : String,
) -> String {
  let result = try {
    let _ = interp.run(direct_return_test_program(source))
    "no throw"
  } catch {
    JsException(String_(value)) => value
    _ => "wrong throw"
  }
  result
}

///|
test "direct-return result-fed helper throw preserves guest value" {
  inspect(
    run_direct_return_result_fed_throw(
      Interpreter::new(),
      DIRECT_RETURN_RESULT_FED_LEAF_THROW_SOURCE,
    ),
    content="boom",
  )
}

///|
test "direct-return two-helper inner throw preserves guest value" {
  inspect(
    run_direct_return_result_fed_throw(
      Interpreter::new(),
      DIRECT_RETURN_TWO_HELPER_INNER_THROW_SOURCE,
    ),
    content="inner-boom",
  )
}

///|
test "direct-return two-helper outer throw preserves guest value" {
  inspect(
    run_direct_return_result_fed_throw(
      Interpreter::new(),
      DIRECT_RETURN_TWO_HELPER_OUTER_THROW_SOURCE,
    ),
    content="outer-boom",
  )
}

///|
test "direct-return result-fed helper throw permits same-interpreter reuse" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 161)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  inspect(
    run_direct_return_result_fed_throw(
      interp,
      DIRECT_RETURN_RESULT_FED_LEAF_THROW_SOURCE,
    ),
    content="boom",
  )
  dispatch_shell_test_expect_realm_sentinel(interp, 161)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after result-fed helper throw")
  }
  match
    run_direct_return_result_fed_shell_once(
      interp,
      DIRECT_RETURN_RESULT_FED_LEAF_TEST_SOURCE,
    ) {
    String_(value) => inspect(value, content="done")
    other =>
      fail(
        "unexpected result-fed result after helper throw: " + other.to_string(),
      )
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 161)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after helper-throw reuse")
  }
}

///|
test "direct-return two-helper abrupt completion permits same-interpreter reuse" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 164)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  inspect(
    run_direct_return_result_fed_throw(
      interp,
      DIRECT_RETURN_TWO_HELPER_INNER_THROW_SOURCE,
    ),
    content="inner-boom",
  )
  dispatch_shell_test_expect_realm_sentinel(interp, 164)
  inspect(
    run_direct_return_result_fed_throw(
      interp,
      DIRECT_RETURN_TWO_HELPER_OUTER_THROW_SOURCE,
    ),
    content="outer-boom",
  )
  dispatch_shell_test_expect_realm_sentinel(interp, 164)
  match
    run_direct_return_result_fed_shell_once(
      interp,
      DIRECT_RETURN_TWO_HELPER_RESULT_FED_TEST_SOURCE,
      expected_observations=769,
    ) {
    String_(value) => inspect(value, content="done")
    other =>
      fail(
        "unexpected two-helper result after abrupt completion: " +
        other.to_string(),
      )
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 164)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after two-helper abrupt reuse")
  }
}

///|
test "direct-return mixed helper throw preserves guest value and permits same-interpreter reuse" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 162)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  inspect(
    run_direct_return_result_fed_throw(
      interp,
      DIRECT_RETURN_MIXED_ARGUMENT_RESULT_FED_LEAF_THROW_SOURCE,
    ),
    content="boom",
  )
  dispatch_shell_test_expect_realm_sentinel(interp, 162)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after mixed helper throw")
  }
  match
    run_direct_return_result_fed_shell_once(
      interp,
      DIRECT_RETURN_REVERSED_MIXED_ARGUMENT_RESULT_FED_TEST_SOURCE,
    ) {
    String_(value) => inspect(value, content="done")
    other =>
      fail(
        "unexpected mixed result-fed result after helper throw: " +
        other.to_string(),
      )
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 162)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after mixed helper-throw reuse")
  }
}

///|
test "direct-return result-fed interruption bypasses its saved return consumer" {
  run_direct_return_result_fed_interruption(Interpreter::new())
}

///|
test "direct-return result-fed interruption permits same-interpreter reuse" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 163)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  run_direct_return_result_fed_interruption(interp)
  dispatch_shell_test_expect_realm_sentinel(interp, 163)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after result-fed interruption")
  }
  match
    run_direct_return_result_fed_shell_once(
      interp,
      DIRECT_RETURN_RESULT_FED_LEAF_TEST_SOURCE,
    ) {
    String_(value) => inspect(value, content="done")
    other =>
      fail(
        "unexpected result-fed result after interruption: " + other.to_string(),
      )
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 163)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after result-fed interruption reuse")
  }
}

///|
test "direct-return leaf throw crosses every admitted return continuation" {
  let interp = Interpreter::new()
  let result = try {
    let _ = interp.run(
      direct_return_test_program(DIRECT_RETURN_LEAF_THROW_SOURCE),
    )
    "no throw"
  } catch {
    JsException(String_(value)) => value
    _ => "wrong throw"
  }
  inspect(result, content="boom")
}

///|
test "direct-return bound leaf throw preserves the parameter value" {
  let interp = Interpreter::new()
  let result = try {
    let _ = interp.run(
      direct_return_test_program(DIRECT_RETURN_ARGUMENT_LEAF_THROW_SOURCE),
    )
    "no throw"
  } catch {
    JsException(String_(value)) => value
    _ => "wrong throw"
  }
  inspect(result, content="boom")
}

///|
test "direct-return argument vector throw preserves the selected parameter" {
  let interp = Interpreter::new()
  let result = try {
    let _ = interp.run(
      direct_return_test_program(
        DIRECT_RETURN_ARGUMENT_VECTOR_LEAF_THROW_SOURCE,
      ),
    )
    "no throw"
  } catch {
    JsException(String_(value)) => value
    _ => "wrong throw"
  }
  inspect(result, content="boom")
}

///|
test "direct-return trust rejects global binding mutation before sealing" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  guard interp.global.bindings.get("f") is Some(binding) else {
    fail("expected the hoisted direct-return binding")
  }
  let original = binding.value
  binding.value = Number(0.0)
  let result = try {
    let _ = interp.seal_direct_return_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  binding.value = original
  inspect(
    result,
    content="direct-return declaration did not hoist a function object",
  )
}

///|
test "direct-return trust rejects post-seal UserFunc mutation" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let callee = registry.entry.callee
  guard callee is Object({ callable: Some(UserFunc(data)), .. }) else {
    fail("expected a trusted direct-return UserFunc")
  }

  let original_parameter = data.params[0]
  data.params[0] = "changed"
  let parameter_result = try {
    let _ = registry.require_callee(interp, callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  data.params[0] = original_parameter

  let original_base_case = data.body[0]
  data.body[0] = @parser.parse("0;").stmts[0]
  let body_result = try {
    let _ = registry.require_callee(interp, callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  data.body[0] = original_base_case

  inspect(
    parameter_result,
    content="direct-return callee provenance changed after sealing",
  )
  inspect(
    body_result,
    content="direct-return callee provenance changed after sealing",
  )
  let restored = registry.require_callee(interp, callee)
  inspect(restored.name, content="f")
}

///|
test "direct-return trust rejects post-seal leaf mutation" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_LEAF_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return leaf preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let leaf = match registry.first_helper() {
    Some(found) => found
    None => fail("expected a trusted direct-return leaf")
  }
  guard leaf.callee is Object({ callable: Some(UserFunc(data)), .. }) else {
    fail("expected a trusted direct-return leaf UserFunc")
  }
  let original_stmt = data.body[0]
  data.body[0] = @parser.parse("return 0;").stmts[0]
  let result = try {
    let _ = registry.require_leaf(interp, leaf.callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  data.body[0] = original_stmt
  inspect(result, content="direct-return leaf provenance changed after sealing")
  let restored = registry.require_leaf(interp, leaf.callee)
  inspect(restored.name, content="leaf")
}

///|
test "direct-return trust rejects post-seal closed leaf location drift" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_LEAF_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return leaf preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let leaf = match registry.first_helper() {
    Some(found) => found
    None => fail("expected a trusted direct-return leaf")
  }
  guard leaf.callee is Object({ callable: Some(UserFunc(data)), .. }) else {
    fail("expected a trusted direct-return leaf UserFunc")
  }
  let original_stmt = data.body[0]
  let replacement_stmt = @parser.parse("return \"done\";").stmts[0]
  guard original_stmt
    is @ast.ReturnStmt(
      Some(@ast.StringLit(_, _, @token.LexForm::LexNormal, original_loc)),
      _
    ) &&
    replacement_stmt
    is @ast.ReturnStmt(
      Some(@ast.StringLit(_, _, @token.LexForm::LexNormal, replacement_loc)),
      _
    ) &&
    original_loc != replacement_loc else {
    fail("expected the replacement literal to have a different location")
  }
  data.body[0] = replacement_stmt
  let result = try {
    let _ = registry.require_leaf(interp, leaf.callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  data.body[0] = original_stmt
  guard result == "direct-return leaf provenance changed after sealing" else {
    fail("expected closed leaf location drift rejection, got " + result)
  }
  let _ = registry.require_leaf(interp, leaf.callee)
}

///|
test "direct-return trust rejects a changed bound leaf argument" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(
    DIRECT_RETURN_ARGUMENT_LEAF_TEST_SOURCE,
  )
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected bound direct-return leaf preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let leaf = match registry.first_helper() {
    Some(found) => found
    None => fail("expected a trusted bound direct-return leaf")
  }
  let call_loc = match registry.entry.syntax.base_completion {
    DirectReturnBaseLeafCall(plan) => plan.call_loc
    _ => fail("expected a sealed leaf call location")
  }
  let result = try {
    registry.require_call(
      interp,
      leaf.callee,
      Undefined,
      [String_("changed")],
      call_loc,
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    result,
    content="direct-return leaf activation escaped its sealed argument plan",
  )
  registry.require_call(
    interp,
    leaf.callee,
    Undefined,
    [String_("done")],
    call_loc,
  )
}

///|
test "direct-return result-fed trust rejects helper binding mutation" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(
    DIRECT_RETURN_RESULT_FED_LEAF_TEST_SOURCE,
  )
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected result-fed direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let leaf = match registry.first_helper() {
    Some(found) => found
    None => fail("expected a trusted result-fed helper")
  }
  let call_loc = match registry.entry.syntax.recursive_completion {
    DirectReturnRecursiveResultFedLeafCall(plan) => plan.call_loc
    _ => fail("expected the result-fed call plan")
  }
  guard interp.global.bindings.get("id") is Some(binding) else {
    fail("expected the hoisted result-fed helper binding")
  }
  let original = binding.value
  binding.value = Number(0.0)
  let result = try {
    registry.require_call(
      interp,
      leaf.callee,
      Undefined,
      [String_("done")],
      call_loc,
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  binding.value = original
  inspect(result, content="direct-return leaf diverged from its global binding")
}

///|
test "direct-return trust rejects reordered argument vectors" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(
    DIRECT_RETURN_ARGUMENT_VECTOR_LEAF_TEST_SOURCE,
  )
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected ordered direct-return leaf preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let leaf = match registry.first_helper() {
    Some(found) => found
    None => fail("expected a trusted ordered direct-return leaf")
  }
  let call_loc = match registry.entry.syntax.base_completion {
    DirectReturnBaseLeafCall(plan) => plan.call_loc
    _ => fail("expected a sealed leaf call location")
  }
  let result = try {
    registry.require_call(
      interp,
      leaf.callee,
      Undefined,
      [String_("done"), String_("ignored")],
      call_loc,
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    result,
    content="direct-return leaf activation escaped its sealed argument plan",
  )
  registry.require_call(
    interp,
    leaf.callee,
    Undefined,
    [String_("ignored"), String_("done")],
    call_loc,
  )
}

///|
test "direct-return bound leaf rejects a changed prepared parameter" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(
    DIRECT_RETURN_ARGUMENT_LEAF_TEST_SOURCE,
  )
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected bound direct-return leaf preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let leaf = match registry.first_helper() {
    Some(found) => found
    None => fail("expected a trusted bound direct-return leaf")
  }
  guard leaf.callee is Object({ callable: Some(UserFunc(data)), .. }) else {
    fail("expected a trusted bound direct-return leaf UserFunc")
  }
  let gate = interp.begin_simple_user_func_parameter_gate()
  let prepared = interp.prepare_user_func_activation(
    leaf.callee,
    Undefined,
    [String_("done")],
    data,
    throw_type_error_source=UsePreResolvedThrowTypeError(
      registry.throw_type_error,
    ),
  )
  prepared.env.assign("value", String_("changed"))
  let parameter = match leaf.syntax.leaf_completion {
    DirectReturnLeafParameterValue(parameter) => parameter
    _ => fail("expected a sealed leaf parameter completion")
  }
  let result = try {
    let _ = direct_return_leaf_parameter_value(
      { ctx: prepared.ctx, stmt: leaf.body[0], env: prepared.env, index: 0 },
      registry,
      leaf.syntax,
      parameter,
      [String_("done")],
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  interp.finish_simple_user_func_parameter_gate(gate)
  inspect(
    result,
    content="direct-return leaf parameter lost its sealed binding provenance",
  )
}

///|
test "direct-return argument vector validates every prepared binding" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(
    DIRECT_RETURN_ARGUMENT_VECTOR_LEAF_TEST_SOURCE,
  )
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected ordered direct-return leaf preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let leaf = match registry.first_helper() {
    Some(found) => found
    None => fail("expected a trusted ordered direct-return leaf")
  }
  guard leaf.callee is Object({ callable: Some(UserFunc(data)), .. }) else {
    fail("expected a trusted ordered direct-return UserFunc")
  }
  let gate = interp.begin_simple_user_func_parameter_gate()
  let prepared = interp.prepare_user_func_activation(
    leaf.callee,
    Undefined,
    [String_("ignored"), String_("done")],
    data,
    throw_type_error_source=UsePreResolvedThrowTypeError(
      registry.throw_type_error,
    ),
  )
  prepared.env.assign("ignored", String_("changed"))
  let parameter = match leaf.syntax.leaf_completion {
    DirectReturnLeafParameterValue(parameter) => parameter
    _ => fail("expected a sealed argument-vector completion")
  }
  let result = try {
    let _ = direct_return_leaf_parameter_value(
      { ctx: prepared.ctx, stmt: leaf.body[0], env: prepared.env, index: 0 },
      registry,
      leaf.syntax,
      parameter,
      [String_("ignored"), String_("done")],
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  interp.finish_simple_user_func_parameter_gate(gate)
  inspect(
    result,
    content="direct-return leaf parameter lost its sealed binding provenance",
  )
}

///|
test "direct-return ordinary cleanup owns an argument snapshot" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(
    DIRECT_RETURN_ARGUMENT_LEAF_TEST_SOURCE,
  )
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected bound direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let leaf = match registry.first_helper() {
    Some(found) => found
    None => fail("expected a trusted direct-return leaf")
  }
  let request = DispatchCallRequest(
    callee=leaf.callee,
    this_value=Undefined,
    args=[String_("done")],
    loc=match registry.entry.syntax.base_completion {
      DirectReturnBaseLeafCall(plan) => plan.call_loc
      _ => fail("expected the sealed leaf call plan")
    },
  )
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    direct_return_registry=Some(registry),
  )
  match shell.enter_direct_return_call(request) {
    DispatchCallAccepted(_, _) => ()
    _ => fail("expected the ordinary leaf call to be accepted")
  }
  request.args[0] = String_("changed")
  guard shell.cleanup_stack[shell.cleanup_stack.length() - 1].resources
    is DispatchOrdinaryRealmCleanup({ actual_arguments: [String_("done")], .. }) else {
    fail("expected ordinary cleanup to retain its defensive argument snapshot")
  }
  shell.restore_all_cleanup()
}

///|
test "direct-return trust revalidates binding and mirror after sealing" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let callee = registry.entry.callee
  guard callee is Object({ callable: Some(UserFunc(data)), .. }) &&
    interp.global.bindings.get("f") is Some(binding) &&
    interp.global_this is Object(global_object) else {
    fail("expected trusted direct-return global UserFunc provenance")
  }
  let replacement = make_func(data)

  let original_binding = binding.value
  binding.value = replacement
  let binding_result = try {
    let _ = registry.require_callee(interp, callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  binding.value = original_binding

  let original_mirror = global_object.bag.properties["f"]
  global_object.bag.properties["f"] = replacement
  let mirror_result = try {
    let _ = registry.require_callee(interp, callee)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  global_object.bag.properties["f"] = original_mirror

  inspect(
    binding_result,
    content="direct-return callee diverged from its global binding",
  )
  inspect(
    mirror_result,
    content="direct-return callee diverged from its global mirror",
  )
}

///|
fn direct_return_wrapped_entry_attempt(
  interp : Interpreter,
  preflight : DirectReturnRecursionPreflight,
  stmts : Array[@ast.Stmt],
  registry : TrustedDirectReturnRecursionRegistry,
  wrapper : TrustedDirectReturnWrapperFunction,
  probe : DispatchObservationProbe,
) -> String {
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    direct_return_registry=Some(registry),
    activation_observation_port=probe.port(),
  )
  let request = DispatchCallRequest(
    callee=wrapper.callee,
    this_value=Undefined,
    args=[],
    loc=wrapper.plan.outer_call_loc,
  )
  try {
    match shell.enter_direct_return_call(request) {
      DispatchCallAccepted(_, _) => {
        shell.restore_all_cleanup()
        "accepted"
      }
      _ => "unexpected dispatch result"
    }
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
}

///|
test "direct-return wrapped trust rejects post-seal root mutations before observation" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(
    DIRECT_RETURN_WRAPPED_RESULT_FED_TEST_SOURCE,
  )
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected wrapped direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let wrapper = match registry.root {
    TrustedDirectReturnWrapperRoot(found) => found
    TrustedDirectReturnEntryRoot =>
      fail("expected a trusted wrapped direct-return root")
  }
  guard wrapper.callee is Object({ callable: Some(UserFunc(data)), .. }) &&
    interp.global.bindings.get("entry") is Some(binding) &&
    interp.global_this is Object(global_object) else {
    fail("expected trusted wrapped root provenance")
  }
  let replacement = make_func(data)

  let binding_probe = DispatchObservationProbe(observed_interp=Some(interp))
  let original_binding = binding.value
  binding.value = replacement
  let binding_result = direct_return_wrapped_entry_attempt(
    interp, preflight, stmts, registry, wrapper, binding_probe,
  )
  binding.value = original_binding
  inspect(binding_probe.attempts, content="0")
  inspect(
    binding_result,
    content="direct-return wrapper diverged from its global binding",
  )
  let _ = registry.require_wrapper(interp, wrapper.callee)

  let mirror_probe = DispatchObservationProbe(observed_interp=Some(interp))
  let original_mirror = global_object.bag.properties["entry"]
  global_object.bag.properties["entry"] = replacement
  let mirror_result = direct_return_wrapped_entry_attempt(
    interp, preflight, stmts, registry, wrapper, mirror_probe,
  )
  global_object.bag.properties["entry"] = original_mirror
  inspect(mirror_probe.attempts, content="0")
  inspect(
    mirror_result,
    content="direct-return wrapper diverged from its global mirror",
  )
  let _ = registry.require_wrapper(interp, wrapper.callee)

  // The exact zero-parameter guard rejects this too; keep the mutation to
  // prove that the sealed parameter snapshot is independently owned.
  let params_probe = DispatchObservationProbe(observed_interp=Some(interp))
  wrapper.params.push("changed")
  let params_result = direct_return_wrapped_entry_attempt(
    interp, preflight, stmts, registry, wrapper, params_probe,
  )
  let _ = wrapper.params.pop()
  inspect(params_probe.attempts, content="0")
  inspect(
    params_result,
    content="direct-return wrapper provenance changed after sealing",
  )
  let _ = registry.require_wrapper(interp, wrapper.callee)

  let body_probe = DispatchObservationProbe(observed_interp=Some(interp))
  let original_body = data.body[0]
  data.body[0] = @parser.parse("return 0;").stmts[0]
  let body_result = direct_return_wrapped_entry_attempt(
    interp, preflight, stmts, registry, wrapper, body_probe,
  )
  data.body[0] = original_body
  inspect(body_probe.attempts, content="0")
  inspect(
    body_result,
    content="direct-return wrapper provenance changed after sealing",
  )
  let _ = registry.require_wrapper(interp, wrapper.callee)

  let root_probe = DispatchObservationProbe(observed_interp=Some(interp))
  let altered_registry = {
    ..registry,
    plan: {
      ..registry.plan,
      root_invocation: DirectReturnEntryInvocation(
        DirectReturnEntryRootPlan(
          entry_name="f",
          call_loc=wrapper.plan.outer_call_loc,
          initial_argument=256.0,
        ),
      ),
    },
  }
  let root_result = direct_return_wrapped_entry_attempt(
    interp, preflight, stmts, altered_registry, wrapper, root_probe,
  )
  inspect(root_probe.attempts, content="0")
  inspect(
    root_result,
    content="direct-return registry lost its wrapper root-plan ownership",
  )
  let _ = registry.require_wrapper(interp, wrapper.callee)
}

///|
test "direct-return execution rejects a foreign activation environment" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    direct_return_registry=Some(registry),
  )
  let foreign_parent = Environment::new()
  let wrong_parent = Environment::new(parent=Some(foreign_parent))
  wrong_parent.is_var_scope = true
  let with_object = Environment::new(parent=Some(interp.global))
  with_object.is_var_scope = true
  with_object.with_object = Some(Undefined)
  let non_var_scope = Environment::new(parent=Some(interp.global))
  for env in [wrong_parent, with_object, non_var_scope] {
    env.def_parameter("n", Number(1.0))
    let result = try {
      let _ = shell.execute_direct_return_statement({
        ctx: { strict: false, current_generator: None },
        stmt: registry.entry.body[0],
        env,
        index: 0,
      })
      "accepted"
    } catch {
      InvalidActivationDispatchShell(message) => message
    }
    inspect(
      result,
      content="direct-return statement lost its sealed body provenance",
    )
  }
}

///|
test "direct-return trust rejects source identity drift during hoisting" {
  let interp = Interpreter::new()
  interp.realm_state.active_source_identity.val = Some("preflight.js")
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.realm_state.active_source_identity.val = Some("hoist.js")
  interp.prepare_root_program_execution(stmts, interp.global, false)
  interp.realm_state.active_source_identity.val = Some("preflight.js")
  let result = try {
    let _ = interp.seal_direct_return_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    result,
    content="direct-return UserFunc source identity changed during root hoisting",
  )
}

///|
test "direct-return trust rejects foreign realm metadata during hoisting" {
  let interp = Interpreter::new()
  let foreign = Interpreter::new()
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected direct-return preflight")
  }
  interp.global.interpreter_context = Some(foreign)
  interp.prepare_root_program_execution(stmts, interp.global, false)
  interp.global.interpreter_context = Some(interp)
  let result = try {
    let _ = interp.seal_direct_return_recursion_registry(preflight, stmts)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    result,
    content="direct-return UserFunc realm provenance changed during root hoisting",
  )
}

///|
test "direct-return one-short budget stops before later recursive calls" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe()
  let (shell, stmts, ctx) = direct_return_observation_fixture(interp, probe)
  let control = ExecutionControl(
    remaining_steps=513,
    maximum_active_depth=300,
    interruption=ExecutionInterruptionRequest(),
  )
  let completion = interp.with_execution_control(control, () => {
    shell.drive_root_program(stmts, ctx)
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ => fail("expected the one-short direct-return execution limit")
  }
  inspect(probe.attempts, content="256")
  inspect(probe.accepted, content=probe.released.to_string())
  inspect(probe.active, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "direct-return interruption suppresses later recursive calls" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let interruption = ExecutionInterruptionRequest()
  let base_port = probe.port()
  let port = ActivationObservationPort(
    begin_entry=() => {
      let hooks = (base_port.begin_entry)()
      if probe.attempts == 128 {
        interruption.request()
      }
      hooks
    },
    denied=() => (base_port.denied)(),
  )
  let stmts = direct_return_test_program(DIRECT_RETURN_TEST_SOURCE)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected exact direct-return preflight")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    activation_observation_port=port,
  )
  let control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=300,
    interruption~,
  )
  let completion = interp.with_execution_control(control, () => {
    shell.drive_root_program(stmts, { strict: false, current_generator: None })
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(Interrupted)) => ()
    _ => fail("expected direct-return interruption identity")
  }
  inspect(probe.attempts, content="128")
  inspect(probe.accepted, content=probe.released.to_string())
  inspect(probe.active, content="0")
  inspect(probe.lifo_violations, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
fn expect_direct_return_interruption_at_leaf(source : String) -> Unit raise {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let interruption = ExecutionInterruptionRequest()
  let base_port = probe.port()
  let port = ActivationObservationPort(
    begin_entry=() => {
      let hooks = (base_port.begin_entry)()
      if probe.attempts == 258 {
        interruption.request()
      }
      hooks
    },
    denied=() => (base_port.denied)(),
  )
  let stmts = direct_return_test_program(source)
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected exact direct-return leaf preflight")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    activation_observation_port=port,
  )
  let control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=300,
    interruption~,
  )
  let completion = interp.with_execution_control(control, () => {
    shell.drive_root_program(stmts, { strict: false, current_generator: None })
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(Interrupted)) => ()
    _ => fail("expected interruption at the direct-return leaf")
  }
  expect_dispatch_observation_balanced(probe, 258)
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
fn run_direct_return_result_fed_interruption(
  interp : Interpreter,
) -> Unit raise {
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let interruption = ExecutionInterruptionRequest()
  let base_port = probe.port()
  let port = ActivationObservationPort(
    begin_entry=() => {
      let hooks = (base_port.begin_entry)()
      if probe.attempts == 258 {
        interruption.request()
      }
      hooks
    },
    denied=() => (base_port.denied)(),
  )
  let stmts = direct_return_test_program(
    DIRECT_RETURN_RESULT_FED_LEAF_TEST_SOURCE,
  )
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected result-fed direct-return preflight")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    activation_observation_port=port,
  )
  let control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=300,
    interruption~,
  )
  let completion = interp.with_execution_control(control, () => {
    shell.drive_root_program(stmts, { strict: false, current_generator: None })
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(Interrupted)) => ()
    _ => fail("expected interruption at the result-fed helper")
  }
  inspect(probe.attempts, content="258")
  inspect(probe.acquired, content="258")
  inspect(probe.accepted, content="258")
  inspect(probe.rejected, content="0")
  inspect(probe.released, content="258")
  inspect(probe.active, content="0")
  inspect(probe.maximum_active, content="257")
  inspect(probe.release_ordinals.length(), content="258")
  inspect(probe.lifo_violations, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "direct-return interruption at leaf bypasses saved return consumers" {
  expect_direct_return_interruption_at_leaf(DIRECT_RETURN_LEAF_TEST_SOURCE)
}

///|
test "direct-return bound leaf interruption bypasses saved return consumers" {
  expect_direct_return_interruption_at_leaf(
    DIRECT_RETURN_ARGUMENT_LEAF_TEST_SOURCE,
  )
}

///|
test "direct-return argument vector interruption bypasses saved return consumers" {
  expect_direct_return_interruption_at_leaf(
    DIRECT_RETURN_ARGUMENT_VECTOR_LEAF_TEST_SOURCE,
  )
}

///|
test "direct-return cleanup permits same-interpreter reuse" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 113)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  match run_direct_return_shell_once(interp) {
    String_(value) => inspect(value, content="done")
    other => fail("unexpected first direct-return result: " + other.to_string())
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 113)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after first direct-return run")
  }
  match run_direct_return_shell_once(interp) {
    String_(value) => inspect(value, content="done")
    other =>
      fail("unexpected second direct-return result: " + other.to_string())
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 113)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after second direct-return run")
  }
}

///|
fn expect_direct_return_leaf_cleanup_permits_reuse(
  source : String,
  sentinel : Int,
) -> Unit raise {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, sentinel)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  for attempt in 0..<2 {
    match run_direct_return_shell_source_once(interp, source, 258) {
      String_(value) => inspect(value, content="done")
      other =>
        fail(
          "unexpected direct-return leaf result at attempt " +
          attempt.to_string() +
          ": " +
          other.to_string(),
        )
    }
    dispatch_shell_test_expect_realm_sentinel(interp, sentinel)
    match interp.realm_state.active_source_identity.val {
      Some(source) => inspect(source, content="caller.js")
      None => fail("expected source identity after direct-return leaf run")
    }
  }
}

///|
test "direct-return leaf cleanup permits same-interpreter reuse" {
  expect_direct_return_leaf_cleanup_permits_reuse(
    DIRECT_RETURN_LEAF_TEST_SOURCE,
    131,
  )
}

///|
test "direct-return bound leaf cleanup permits same-interpreter reuse" {
  expect_direct_return_leaf_cleanup_permits_reuse(
    DIRECT_RETURN_ARGUMENT_LEAF_TEST_SOURCE,
    139,
  )
}

///|
test "direct-return argument vector cleanup permits same-interpreter reuse" {
  expect_direct_return_leaf_cleanup_permits_reuse(
    DIRECT_RETURN_ARGUMENT_VECTOR_LEAF_TEST_SOURCE,
    149,
  )
}

///|
test "direct-return result-fed cleanup permits same-interpreter reuse" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 157)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  for attempt in 0..<2 {
    match
      run_direct_return_result_fed_shell_once(
        interp,
        DIRECT_RETURN_RESULT_FED_LEAF_TEST_SOURCE,
      ) {
      String_(value) => inspect(value, content="done")
      other =>
        fail(
          "unexpected result-fed direct-return result at attempt " +
          attempt.to_string() +
          ": " +
          other.to_string(),
        )
    }
    dispatch_shell_test_expect_realm_sentinel(interp, 157)
    match interp.realm_state.active_source_identity.val {
      Some(source) => inspect(source, content="caller.js")
      None => fail("expected source identity after result-fed run")
    }
  }
}

///|
fn expect_direct_return_result_fed_one_short_budget(
  source : String,
  sentinel : Int,
  expected_observations : Int,
) -> Unit raise {
  let exact_interp = Interpreter::new()
  let exact_probe = DispatchObservationProbe(observed_interp=Some(exact_interp))
  let (exact_shell, exact_stmts, exact_ctx) = direct_return_observation_fixture_for_source(
    exact_interp, exact_probe, source,
  )
  let full_budget = 10000L
  let exact_control = ExecutionControl(
    remaining_steps=full_budget,
    maximum_active_depth=300L,
    interruption=ExecutionInterruptionRequest(),
  )
  let exact_completion = exact_interp.with_execution_control(exact_control, () => {
    exact_shell.drive_root_program(exact_stmts, exact_ctx)
  })
  match exact_completion {
    DispatchNormal(String_(value)) => inspect(value, content="done")
    _ => fail("expected exact result-fed budget to complete normally")
  }
  let used_steps = full_budget - exact_control.remaining_steps()
  guard used_steps > 0L else {
    fail("expected result-fed execution to charge steps")
  }

  let short_interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(short_interp, sentinel)
  short_interp.realm_state.active_source_identity.val = Some("caller.js")
  let short_probe = DispatchObservationProbe(observed_interp=Some(short_interp))
  let (short_shell, short_stmts, short_ctx) = direct_return_observation_fixture_for_source(
    short_interp, short_probe, source,
  )
  let short_control = ExecutionControl(
    remaining_steps=used_steps - 1L,
    maximum_active_depth=300L,
    interruption=ExecutionInterruptionRequest(),
  )
  let short_completion = short_interp.with_execution_control(short_control, () => {
    short_shell.drive_root_program(short_stmts, short_ctx)
  })
  match short_completion {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ => fail("expected one-short result-fed execution limit")
  }
  guard short_probe.attempts == expected_observations &&
    short_probe.acquired == expected_observations &&
    short_probe.accepted == expected_observations &&
    short_probe.released == expected_observations &&
    short_probe.rejected == 0 &&
    short_probe.active == 0 &&
    short_probe.lifo_violations == 0 else {
    fail("result-fed one-short budget observation count drifted")
  }
  inspect(short_shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(short_interp, sentinel)
  match short_interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after result-fed budget failure")
  }
  match
    run_direct_return_result_fed_shell_once(
      short_interp,
      source,
      expected_observations~,
    ) {
    String_(value) => inspect(value, content="done")
    other =>
      fail(
        "unexpected result-fed result after budget failure: " +
        other.to_string(),
      )
  }
  dispatch_shell_test_expect_realm_sentinel(short_interp, sentinel)
  match short_interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after result-fed budget reuse")
  }
}

///|
test "direct-return result-fed one-short budget bypasses saved return consumer" {
  expect_direct_return_result_fed_one_short_budget(
    DIRECT_RETURN_RESULT_FED_LEAF_TEST_SOURCE,
    167,
    513,
  )
}

///|
test "direct-return mixed result-fed one-short budget bypasses saved return consumer" {
  expect_direct_return_result_fed_one_short_budget(
    DIRECT_RETURN_MIXED_ARGUMENT_RESULT_FED_TEST_SOURCE,
    169,
    513,
  )
}

///|
test "direct-return two-helper one-short budget preserves cleanup and reuse" {
  expect_direct_return_result_fed_one_short_budget(
    DIRECT_RETURN_TWO_HELPER_RESULT_FED_TEST_SOURCE,
    171,
    769,
  )
}

///|
test "direct-return wrapped result-fed one-short budget bypasses saved return consumer" {
  let exact_interp = Interpreter::new()
  let exact_probe = DispatchObservationProbe(observed_interp=Some(exact_interp))
  let (exact_shell, exact_stmts, exact_ctx) = direct_return_observation_fixture_for_source(
    exact_interp,
    exact_probe,
    DIRECT_RETURN_WRAPPED_RESULT_FED_TEST_SOURCE,
  )
  let full_budget = 10000L
  let exact_control = ExecutionControl(
    remaining_steps=full_budget,
    maximum_active_depth=300L,
    interruption=ExecutionInterruptionRequest(),
  )
  let exact_completion = exact_interp.with_execution_control(exact_control, () => {
    exact_shell.drive_root_program(exact_stmts, exact_ctx)
  })
  match exact_completion {
    DispatchNormal(String_(value)) => inspect(value, content="done")
    _ => fail("expected exact wrapped result-fed budget to complete normally")
  }
  let used_steps = full_budget - exact_control.remaining_steps()
  guard used_steps > 0L else {
    fail("expected wrapped result-fed execution to charge steps")
  }

  let short_interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(short_interp, 179)
  short_interp.realm_state.active_source_identity.val = Some("caller.js")
  let short_probe = DispatchObservationProbe(observed_interp=Some(short_interp))
  let (short_shell, short_stmts, short_ctx) = direct_return_observation_fixture_for_source(
    short_interp,
    short_probe,
    DIRECT_RETURN_WRAPPED_RESULT_FED_TEST_SOURCE,
  )
  let short_control = ExecutionControl(
    remaining_steps=used_steps - 1L,
    maximum_active_depth=300L,
    interruption=ExecutionInterruptionRequest(),
  )
  let short_completion = short_interp.with_execution_control(short_control, () => {
    short_shell.drive_root_program(short_stmts, short_ctx)
  })
  match short_completion {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ => fail("expected one-short wrapped result-fed execution limit")
  }
  inspect(short_probe.attempts, content="514")
  inspect(short_probe.acquired, content="514")
  inspect(short_probe.accepted, content="514")
  inspect(short_probe.rejected, content="0")
  inspect(short_probe.released, content="514")
  inspect(short_probe.denied, content="0")
  inspect(short_probe.active, content="0")
  inspect(short_probe.maximum_active, content="258")
  inspect(short_probe.release_ordinals.length(), content="514")
  inspect(short_probe.lifo_violations, content="0")
  inspect(short_shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(short_interp, 179)
  match short_interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after wrapped budget failure")
  }
  match run_direct_return_wrapped_result_fed_shell_once(short_interp) {
    String_(value) => inspect(value, content="done")
    other =>
      fail(
        "unexpected wrapped result-fed result after budget failure: " +
        other.to_string(),
      )
  }
  dispatch_shell_test_expect_realm_sentinel(short_interp, 179)
  match short_interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after wrapped budget reuse")
  }
}

///|
fn run_direct_return_wrapped_result_fed_interruption(
  interp : Interpreter,
) -> Unit raise {
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let interruption = ExecutionInterruptionRequest()
  let base_port = probe.port()
  let port = ActivationObservationPort(
    begin_entry=() => {
      let hooks = (base_port.begin_entry)()
      if probe.attempts == 259 {
        interruption.request()
      }
      hooks
    },
    denied=() => (base_port.denied)(),
  )
  let stmts = direct_return_test_program(
    DIRECT_RETURN_WRAPPED_RESULT_FED_TEST_SOURCE,
  )
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected wrapped result-fed direct-return preflight")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    activation_observation_port=port,
  )
  let control = ExecutionControl(
    remaining_steps=1000,
    maximum_active_depth=300,
    interruption~,
  )
  let completion = interp.with_execution_control(control, () => {
    shell.drive_root_program(stmts, { strict: false, current_generator: None })
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(Interrupted)) => ()
    _ => fail("expected interruption at the wrapped result-fed helper")
  }
  inspect(probe.attempts, content="259")
  inspect(probe.acquired, content="259")
  inspect(probe.accepted, content="259")
  inspect(probe.rejected, content="0")
  inspect(probe.released, content="259")
  inspect(probe.active, content="0")
  inspect(probe.maximum_active, content="258")
  inspect(probe.release_ordinals.length(), content="259")
  inspect(probe.lifo_violations, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "direct-return wrapped interruption bypasses saved return consumers and permits reuse" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 181)
  interp.realm_state.active_source_identity.val = Some("caller.js")
  run_direct_return_wrapped_result_fed_interruption(interp)
  dispatch_shell_test_expect_realm_sentinel(interp, 181)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after wrapped interruption")
  }
  match run_direct_return_wrapped_result_fed_shell_once(interp) {
    String_(value) => inspect(value, content="done")
    other =>
      fail(
        "unexpected wrapped result-fed result after interruption: " +
        other.to_string(),
      )
  }
  dispatch_shell_test_expect_realm_sentinel(interp, 181)
  match interp.realm_state.active_source_identity.val {
    Some(source) => inspect(source, content="caller.js")
    None => fail("expected source identity after wrapped interruption reuse")
  }
}

///|
test "direct-return result-fed leaf rejects a changed prepared parameter" {
  let interp = Interpreter::new()
  let stmts = direct_return_test_program(
    DIRECT_RETURN_RESULT_FED_LEAF_TEST_SOURCE,
  )
  let preflight = match
    interp.preflight_dispatchable_direct_return_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected result-fed direct-return preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  let registry = interp.seal_direct_return_recursion_registry(preflight, stmts)
  let leaf = match registry.first_helper() {
    Some(found) => found
    None => fail("expected a trusted result-fed helper")
  }
  let call_loc = match registry.entry.syntax.recursive_completion {
    DirectReturnRecursiveResultFedLeafCall(plan) => plan.call_loc
    _ => fail("expected the result-fed helper call plan")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    direct_return_root_preflight=Some(preflight),
    direct_return_root_stmts=Some(stmts),
    direct_return_registry=Some(registry),
  )
  let cursor = match
    shell.enter_direct_return_call(
      DispatchCallRequest(
        callee=leaf.callee,
        this_value=Undefined,
        args=[String_("done")],
        loc=call_loc,
      ),
    ) {
    DispatchCallAccepted(_, DispatchCallBody(cursor)) => cursor
    _ => fail("expected the result-fed helper activation to be accepted")
  }
  guard cursor.env.bindings.get("x") is Some(binding) else {
    fail("expected the prepared result-fed helper parameter")
  }
  binding.value = String_("changed")
  let result = try {
    let _ = shell.execute_direct_return_leaf_statement(
      { ctx: cursor.ctx, stmt: leaf.body[0], env: cursor.env, index: 0 },
      registry,
      leaf,
    )
    "accepted"
  } catch {
    InvalidActivationDispatchShell(message) => message
  }
  inspect(
    result,
    content="direct-return leaf parameter lost its sealed binding provenance",
  )
  shell.restore_all_cleanup()
  inspect(shell.cleanup_stack.length(), content="0")
}
