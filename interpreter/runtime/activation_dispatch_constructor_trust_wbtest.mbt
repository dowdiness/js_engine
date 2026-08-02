///|
fn constructor_recursion_trust_test_registry(
  interp : Interpreter,
  source : String,
) -> TrustedConstructorRecursionRegistry raise {
  let stmts = @parser.parse(source).stmts
  let plan = match classify_constructor_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected an exact constructor-recursion plan")
  }
  let preflight = match interp.preflight_constructor_recursion_program(plan) {
    Some(found) => found
    None => fail("expected callback-free constructor preflight")
  }
  interp.prepare_root_program_execution(stmts, interp.global, false)
  interp.seal_constructor_recursion_registry(preflight, stmts)
}

///|
test "constructor recursion trust rejects binding and prototype drift" {
  let source = "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
    "new Node(4).value;"
  let interp = Interpreter::new()
  let registry = constructor_recursion_trust_test_registry(interp, source)
  guard interp.global.bindings.get("Node") is Some(binding) else {
    fail("expected the sealed constructor binding")
  }
  let original_binding = binding.value
  binding.value = Number(0.0)
  let binding_result = try {
    let _ = registry.require_root_function(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  binding.value = original_binding

  guard original_binding is Object(function_data) else {
    fail("expected the sealed constructor object")
  }
  let original_prototype = match function_data.bag.properties.get("prototype") {
    Some(value) => value
    None => fail("expected an own constructor prototype")
  }
  function_data.bag.properties["prototype"] = Number(0.0)
  let prototype_result = try {
    let _ = registry.require_root_function(interp)
    "accepted"
  } catch {
    InvalidActivationDispatchShell(_) => "rejected"
  }
  function_data.bag.properties["prototype"] = original_prototype

  inspect(binding_result, content="rejected")
  inspect(prototype_result, content="rejected")
  let _ = registry.require_root_function(interp)
}
