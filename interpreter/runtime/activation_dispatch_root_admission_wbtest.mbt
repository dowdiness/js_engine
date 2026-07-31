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
    ActivationDispatchManagedRoot(ActivationDispatchNumericRoot(_)) => "numeric"
    ActivationDispatchManagedRoot(ActivationDispatchGetterRoot(_)) => "getter"
    ActivationDispatchManagedRoot(ActivationDispatchProxyRoot(_)) => "proxy"
    ActivationDispatchLegacyRoot => "legacy"
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
