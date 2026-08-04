///|
fn root_admission_test_program(source : String) -> Array[@ast.Stmt] raise {
  @parser.parse(source).stmts
}

///|
fn root_admission_test_kind(
  admission : ActivationDispatchRootAdmission,
) -> String {
  match admission {
    ActivationDispatchManagedRoot(ActivationDispatchLeafRoot) => "leaf"
    ActivationDispatchManagedRoot(ActivationDispatchControlRoot(_)) => "control"
    ActivationDispatchManagedRoot(ActivationDispatchConstructorRoot(_)) =>
      "constructor"
    ActivationDispatchManagedRoot(ActivationDispatchNumericMapExpressionRoot(_)) =>
      "numeric map expression"
    ActivationDispatchManagedRoot(
      ActivationDispatchNumericMapCompositionRoot(_)
    ) => "numeric map composition"
    ActivationDispatchManagedRoot(ActivationDispatchArrayMapRoot(_)) =>
      "array map"
    ActivationDispatchManagedRoot(ActivationDispatchNumericRoot(_)) => "numeric"
    ActivationDispatchManagedRoot(ActivationDispatchGetterRoot(_)) => "getter"
    ActivationDispatchManagedRoot(ActivationDispatchProxyRoot(_)) => "proxy"
    ActivationDispatchManagedRoot(ActivationDispatchReceiverRoot(_)) =>
      "receiver"
    ActivationDispatchManagedRoot(ActivationDispatchMutualReceiverRoot(_)) =>
      "mutual-receiver"
    ActivationDispatchLegacyRoot => "legacy"
  }
}

///|
const MUTUAL_RECEIVER_RECURSION_SOURCE =
  #|function left(n){if(n===0)return this["\x6darker"];return 1+this["\x72ight"](n-1);}
  #|function right(n){if(n===0)return this["\x6darker"];return 1+this["\x6ceft"](n-1);}
  #|let receiver={["\x6darker"]:0,["\x6ceft"]:left,["\x72ight"]:right};
  #|receiver["\x6ceft"](256);

///|
const REVERSED_MUTUAL_RECEIVER_RECURSION_SOURCE =
  #|function left(n){if(n===0)return this["\x6darker"];return 1+this["\x72ight"](n-1);}
  #|function right(n){if(n===0)return this["\x6darker"];return 1+this["\x6ceft"](n-1);}
  #|let receiver={["\x6darker"]:0,["\x6ceft"]:left,["\x72ight"]:right};
  #|receiver["\x72ight"](256);

///|
const ARRAY_MAP_RECURSION_ADMISSION_SOURCE =
  #|function step(n) {
  #|  if (n === 0) return 0;
  #|  var items = [{next: function() { return step(n - 1); }}];
  #|  return 1 + items.map(function(t) { return t.next(); })[0];
  #|}
  #|step(256);

///|
const ARRAY_MAP_DIRECT_RECURSION_ADMISSION_SOURCE =
  #|function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return u(t-1,e,!f);})[0];}
  #|u(256,0,false);

///|
const ARRAY_MAP_FORWARDING_RECURSION_ADMISSION_SOURCE =
  #|function f(t) {
  #|  if (t === 0) return 0;
  #|  return u(t);
  #|}
  #|function u(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + [n - 1, 0].map(function(t) { return f(t); })[0];
  #|}
  #|u(256);

///|
test "numeric map composition source is admitted by the closed classifier" {
  let source =
    #|function step(n){if(n===0)return 0;return 1+step(n-1);}
    #|function f(t){if(t===0)return 0;return u(t);}
    #|function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}
    #|step(256)+u(256);
  let stmts = root_admission_test_program(source)
  inspect(
    classify_numeric_map_composition_source(stmts) is Some(_),
    content="true",
  )
}

///|
test "numeric map composition classifier keeps near misses legacy" {
  let sources = [
    "function step(n){if(n===0)return 0;return 1+step(n-1);}" +
    "function f(t){if(t===0)return 0;return u(t);}" +
    "function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}" +
    "step(256)+u(256);0;",
    "function step(n){if(n===0)return 0;return 1+step(n-1);}" +
    "function f(t){if(t===0)return 0;return u(t);}" +
    "function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}" +
    "u(256)+step(256);",
    "function step(n){if(n===0)return 0;return 1+step(n-1);}" +
    "function f(t){if(t===0)return 0;return u(t);}" +
    "function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}" +
    "step(256)+u(255);",
  ]
  for source in sources {
    inspect(
      classify_numeric_map_composition_source(
        root_admission_test_program(source),
      )
      is None,
      content="true",
    )
  }
}

///|
test "numeric map expression classifier keeps order and arity near misses legacy" {
  let prefix = "function step(n){if(n===0)return 0;return 1+step(n-1);}" +
    "function f(t){if(t===0)return 0;return u(t);}" +
    "function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}"
  let sources = [
    prefix + "u(256)+step(256)+step(256);",
    prefix + "step(256)+step(256)+u(256);",
    prefix + "step(256)+u(256)+step(256);0;",
    prefix + "step(256)+u(256)+step(256)+0;",
    prefix + "step(256)+u(256)+step(256)+step(256)+u(256);",
    prefix + "step(256)+(u(256)+step(256)+u(256));",
    prefix + "step(256)+u(256)+step(256)-u(256);",
    prefix + "step(256)+u(256)+step(256)+u(255);",
    prefix + "function receiver(){};step(256)+u(256)+receiver(256);",
    prefix + "step(256)+u(256)+step.call(undefined,256)+u(256);",
  ]
  for source in sources {
    inspect(
      numeric_map_expression_source(root_admission_test_program(source)) is None,
      content="true",
    )
  }
}

///|
test "numeric map expression rejects non-number results at root admission" {
  let source =
    "function step(n){if(n===0)return \"0\";return 1+step(n-1);}" +
    "function f(t){if(t===0)return 0;return u(t);}" +
    "function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}" +
    "step(256)+u(256)+step(256)+u(256);"
  let interp = Interpreter::new()
  inspect(
    root_admission_test_kind(
      interp.classify_activation_dispatch_root_program(
        root_admission_test_program(source),
      ),
    ),
    content="legacy",
  )
}

///|
test "numeric map expression classifier admits the exact seven-step source" {
  let stmts = root_admission_test_program(
    FOUR_CALL_NUMERIC_MAP_EXPRESSION_SOURCE,
  )
  match numeric_map_expression_source(stmts) {
    Some(source) => {
      inspect(source.steps.length(), content="7")
      inspect(expression_source_shape_is_admissible(source.steps), content="true")
      inspect(
        source.steps[0] is DispatchExpressionCallSourceStep({ name: "step", .. }),
        content="true",
      )
      inspect(
        source.steps[1] is DispatchExpressionCallSourceStep({ name: "u", .. }),
        content="true",
      )
      inspect(source.steps[2] is DispatchExpressionAddSourceStep(_), content="true")
      inspect(
        source.steps[3] is DispatchExpressionCallSourceStep({ name: "step", .. }),
        content="true",
      )
      inspect(source.steps[4] is DispatchExpressionAddSourceStep(_), content="true")
      inspect(
        source.steps[5] is DispatchExpressionCallSourceStep({ name: "u", .. }),
        content="true",
      )
      inspect(source.steps[6] is DispatchExpressionAddSourceStep(_), content="true")
    }
    None => fail("expected the exact seven-step source to classify")
  }
}

///|
fn array_map_forwarding_near_miss_sources() -> Array[String] {
  [
    "function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[].map(function(t){return f(t);})[0];}u(256);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1].map(function(t){return f(t);})[0];}u(256);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0,0].map(function(t){return f(t);})[0];}u(256);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}u(255);",
    "function f(t,x){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}u(256);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n,x){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}u(256);",
    "function f(t){if(t==0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}u(256);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}u(256,0);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return g(t);})[0];}u(256);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return this.f(t);})[0];}u(256);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(String)[0];}u(256);",
    "\"use strict\";function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}u(256);",
    "function f(t){\"use strict\";if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}u(256);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n){\"use strict\";if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}u(256);",
    "function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}function f(t){if(t===0)return 0;return u(t);}u(256);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f.call(undefined,t);})[0];}u(256);",
    "function f(t){if(t===0)return 0;return u(t);}function u(n){if(n===0)return 0;return 1+[n-1,0].map(function(t){return f(t);})[0];}u(256);0;",
  ]
}

///|
fn array_map_direct_near_miss_sources() -> Array[String] {
  [
    "function u(t,e,f){if(t===0)return 0;return 1+[e,e].map(function(e){return u(t-1,e,!f);})[0];}u(2,0,false);",
    "function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return u(t-1,e,!f);})[0];}u(2,0,false);",
    "function u(t,e){if(t===0)return 0;return 1+[e].map(function(e){return u(t-1,e);})[0];}u(2,0);",
    "function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return u(t-1,e,!f)+0;})[0];}u(2,0,false);",
    "function v(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return v(t-1,e,!f);})[0];}function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return v(t-1,e,!f);})[0];}u(2,0,false);",
    "function u(t,e,f){if(t==0)return 0;return 1+[e].map(function(e){return u(t-1,e,!f);})[0];}u(2,0,false);",
    "function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return u.call(undefined,t-1,e,!f);})[0];}u(2,0,false);",
    "function u(t,e,f){if(t===0)return 0;return 1+[e].map(Number)[0];}u(2,0,false);",
    "\"use strict\";function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return u(t-1,e,!f);})[0];}u(2,0,false);",
  ]
}

///|
test "array map admission classifies the exact source" {
  let stmts = root_admission_test_program(ARRAY_MAP_RECURSION_ADMISSION_SOURCE)
  inspect(
    classify_array_map_recursion_program(stmts) is Some(_),
    content="true",
  )
}

///|
test "array map admission classifies the direct callback source" {
  let stmts = root_admission_test_program(
    ARRAY_MAP_DIRECT_RECURSION_ADMISSION_SOURCE,
  )
  match classify_array_map_recursion_program(stmts) {
    Some(plan) => {
      inspect(array_map_plan_is_dispatchable(plan), content="true")
      match stmts[0] {
        @ast.FuncDecl(_, _, body, _, _) =>
          inspect(
            array_map_direct_step_statement_matches(body[1], plan),
            content="true",
          )
        _ => fail("expected direct callback function declaration")
      }
    }
    None => fail("expected exact direct callback source admission")
  }
}

///|
test "array map admission classifies the forwarding callback source" {
  let stmts = root_admission_test_program(
    ARRAY_MAP_FORWARDING_RECURSION_ADMISSION_SOURCE,
  )
  match classify_array_map_recursion_program(stmts) {
    Some(plan) => {
      inspect(
        plan.callback_family is ArrayMapForwardingCallback,
        content="true",
      )
      inspect(plan.function_name, content="u")
      inspect(plan.forward_function_name, content="f")
      inspect(plan.parameter_name, content="n")
      inspect(plan.forward_parameter_name, content="t")
      inspect(plan.callback_parameter, content="t")
      inspect(plan.initial_count, content="256")
      inspect(plan.map_property_name, content="map")
      inspect(array_map_plan_is_dispatchable(plan), content="true")
    }
    None => fail("expected exact forwarding callback source admission")
  }
}

///|
test "array map forwarding admission rejects exact-shape near misses" {
  for source in array_map_forwarding_near_miss_sources() {
    let stmts = root_admission_test_program(source)
    inspect(classify_array_map_recursion_program(stmts) is None, content="true")
  }
}

///|
test "array map direct admission rejects the nine near-miss sources" {
  for source in array_map_direct_near_miss_sources() {
    let stmts = root_admission_test_program(source)
    inspect(classify_array_map_recursion_program(stmts) is None, content="true")
  }
}

///|
test "array map admission rejects near-miss source families" {
  for
    source in [
      "function step(n){if(n===0)return 0;var items=[{next:function(){return step(n-1);}}];items.map=function(){return [41];};return 1+items.map(function(t){return t.next();})[0];}step(2);",
      "Array.prototype.map=function(){return [7];};function step(n){if(n===0)return 0;var items=[{next:function(){return step(n-1);}}];return 1+items.map(function(t){return t.next();})[0];}step(2);",
      "function step(n){if(n===0)return 0;var items=[{next:function(){return step(n-1);}}];return 1+items.map(function(t){return t[\"next\"]();})[0];}step(2);",
      "var source=[];source[1]=2;source.map(function(x){return x;});", "var source=[1];Object.defineProperty(source,\"0\",{get:function(){return 7;}});source.map(function(x){return x;});",
      "var source=[1];var proxy=new Proxy(source,{});proxy.map(function(x){return x;});",
      "[1].map(String);", "[{next:function(){return 1;}},{next:function(){return 2;}}].map(function(t){return t.next();});",
    ] {
    let stmts = root_admission_test_program(source)
    inspect(classify_array_map_recursion_program(stmts) is None, content="true")
  }
}

///|
test "array map sealing rejects a reclassified location mutation" {
  let original = root_admission_test_program(
    ARRAY_MAP_DIRECT_RECURSION_ADMISSION_SOURCE,
  )
  let shifted = root_admission_test_program(
    "\n" + ARRAY_MAP_DIRECT_RECURSION_ADMISSION_SOURCE,
  )
  match
    (
      classify_array_map_recursion_program(original),
      classify_array_map_recursion_program(shifted),
    ) {
    (Some(expected), Some(actual)) =>
      inspect(array_map_plan_matches(expected, actual), content="false")
    _ => fail("expected both direct sources to classify before plan comparison")
  }
}

///|
test "array map forwarding sealing rejects a reclassified location mutation" {
  let original = root_admission_test_program(
    ARRAY_MAP_FORWARDING_RECURSION_ADMISSION_SOURCE,
  )
  let shifted = root_admission_test_program(
    "\n" + ARRAY_MAP_FORWARDING_RECURSION_ADMISSION_SOURCE,
  )
  match
    (
      classify_array_map_recursion_program(original),
      classify_array_map_recursion_program(shifted),
    ) {
    (Some(expected), Some(actual)) =>
      inspect(array_map_plan_matches(expected, actual), content="false")
    _ =>
      fail(
        "expected both forwarding sources to classify before plan comparison",
      )
  }
}

///|
test "array map direct call arguments retain source order and values" {
  let stmts = root_admission_test_program(
    ARRAY_MAP_DIRECT_RECURSION_ADMISSION_SOURCE,
  )
  match classify_array_map_recursion_program(stmts) {
    Some(plan) => {
      let env = Environment::new()
      env.def_parameter(plan.parameter_name, Number(4.0))
      env.def_parameter(plan.callback_parameter, Number(7.0))
      env.def_parameter(plan.flag_parameter_name, Bool(false))
      let args = array_map_direct_call_arguments(env, plan)
      inspect(args.count, content="4")
      match args.value {
        Number(value) => inspect(value, content="7")
        _ => fail("direct argument value was not numeric")
      }
      inspect(args.flag, content="false")
      let request_args = array_map_direct_call_request_args(env, plan)
      inspect(request_args.length(), content="3")
      match (request_args[0], request_args[1], request_args[2]) {
        (Number(count), Number(value), Bool(flag)) => {
          inspect(count, content="3")
          inspect(value, content="7")
          inspect(flag, content="true")
        }
        _ => fail("direct request arguments changed type or order")
      }
    }
    None => fail("expected direct plan for argument ownership test")
  }
}

///|
test "array map sealing rejects a reclassified direct location" {
  let (interp, original, preflight) = map_observation_test_fixture_for_source(
    MAP_DIRECT_OBSERVATION_SOURCE,
  )
  let shifted = root_admission_test_program(
    "\n" + MAP_DIRECT_OBSERVATION_SOURCE,
  )
  let ctx : ExecContext = { strict: false, current_generator: None }
  let _ = interp.exec_stmt(ctx, original[0], interp.global)
  let _ = try {
    ignore(interp.seal_array_map_recursion_registry(preflight, shifted))
    fail("sealing accepted a reclassified direct location")
  } catch {
    InvalidActivationDispatchShell(_) => ()
    error => fail("unexpected direct seal error: " + error.to_string())
  }
}

///|
test "Interpreter run uses one closed root admission seam" {
  for
    pair in [
      ("1;", "leaf", 1.0),
      ("outer: try { break outer; } finally { 1; } 9;", "control", 9.0),
      (
        "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);", "numeric", 256.0,
      ),
      (
        "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
        "new Node(1024).value;",
        "constructor",
        1024.0,
      ),
      (
        "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
        "let receiver={marker:0,step:step};receiver.step(256);",
        "receiver",
        256.0,
      ),
      (MUTUAL_RECEIVER_RECURSION_SOURCE, "mutual-receiver", 256.0),
      (REVERSED_MUTUAL_RECEIVER_RECURSION_SOURCE, "mutual-receiver", 256.0),
      (getter_recursion_trust_test_source(), "getter", 256.0),
      (proxy_get_recursion_exact_source(), "proxy", 256.0),
      ("outer: try { break outer; } finally { 1; 2; } 9;", "legacy", 9.0),
    ] {
    let (source, expected_kind, expected_value) = pair
    let interp = if expected_kind == "proxy" {
      proxy_get_recursion_trust_test_interpreter()
    } else {
      Interpreter::new()
    }
    let stmts = root_admission_test_program(source)
    inspect(
      root_admission_test_kind(
        interp.classify_activation_dispatch_root_program(stmts),
      ),
      content=expected_kind,
    )
    match interp.run(stmts) {
      Number(value) => inspect(value, content=expected_value.to_string())
      _ => fail("expected an exact numeric root result")
    }
  }
}

///|
test "mutual receiver admission rejects non-escaped and non-mutual shapes" {
  let sources = [
    "function left(n){if(n===0)return this.marker;return 1+this.right(n-1);}" +
    "function right(n){if(n===0)return this.marker;return 1+this.left(n-1);}" +
    "let receiver={marker:0,left:left,right:right};receiver.left(256);",
    "function left(n){if(n===0)return this[\"\\x6darker\"];return 1+this.right(n-1);}" +
    "function right(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x6ceft\"](n-1);}" +
    "let receiver={[\"\\x6darker\"]:0,[\"\\x6ceft\"]:left,[\"\\x72ight\"]:right};receiver[\"\\x6ceft\"](256);",
    "function left(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x6ceft\"](n-1);}" +
    "function right(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x6ceft\"](n-1);}" +
    "let receiver={[\"\\x6darker\"]:0,[\"\\x6ceft\"]:left,[\"\\x72ight\"]:right};receiver[\"\\x6ceft\"](256);",
    "function left(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x72ight\"](n-1);}" +
    "function right(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x6ceft\"](n-1);}" +
    "let receiver={[\"\\x6darker\"]:0,[\"\\x6ceft\"]:left,[\"\\x72ight\"]:right,[\"extra\"]:0};receiver[\"\\x6ceft\"](256);",
  ]
  for source in sources {
    let interp = Interpreter::new()
    inspect(
      root_admission_test_kind(
        interp.classify_activation_dispatch_root_program(
          root_admission_test_program(source),
        ),
      ),
      content="legacy",
    )
  }
}
