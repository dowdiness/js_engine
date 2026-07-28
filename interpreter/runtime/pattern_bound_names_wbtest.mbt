///|
fn deeply_nested_binding_pattern(name : String, depth : Int) -> @ast.Pattern {
  let mut pattern = @ast.Pattern::IdentPat(name)
  for _ in 0..<depth {
    pattern = @ast.Pattern::ArrayPat([Some(pattern)], None)
  }
  pattern
}

///|
test "pattern arguments predicate stops before a large trailing subtree" {
  let arguments_first = deeply_nested_binding_pattern("arguments", 4096)
  let large_tail = deeply_nested_binding_pattern("tail", 4096)
  let pattern = @ast.Pattern::ArrayPat(
    [Some(arguments_first), Some(large_tail)],
    None,
  )
  inspect(pattern_includes_arguments(pattern), content="true")
}

///|
test "post-parse stack safety: deep pattern name preparation" {
  let deep_x = deeply_nested_binding_pattern("x", 4096)
  let deep_arguments = deeply_nested_binding_pattern("arguments", 4096)
  let deep_eval = deeply_nested_binding_pattern("eval", 4096)
  let duplicate_result : Result[Unit, Error] = Ok(
    check_duplicate_params_ext(
      [
        {
          name: "$pattern",
          default_val: None,
          pattern: Some(deep_x),
          is_rest_pattern: false,
        },
        { name: "x", default_val: None, pattern: None, is_rest_pattern: false },
      ],
      None,
    ),
  ) catch {
    error => Err(error)
  }
  debug_inspect(
    duplicate_result,
    content="Err(SyntaxError(message=\"Duplicate parameter name not allowed in this context\"))",
  )
  inspect(pattern_includes_arguments(deep_arguments), content="true")
  let strict_result : Result[Unit, Error] = Ok(
    validate_strict_pattern_binding_names(deep_eval),
  ) catch {
    error => Err(error)
  }
  debug_inspect(
    strict_result,
    content="Err(SyntaxError(message=\"Unexpected eval or arguments in strict mode\"))",
  )
  let names : Array[String] = []
  for name in @static_semantics.bound_names(deep_x) {
    names.push(name)
  }
  json_inspect(names, content=["x"])
  let var_env = Environment::new()
  hoist_pattern(deep_x, var_env)
  inspect(var_env.bindings.contains("x"), content="true")
  let lexical_env = Environment::new()
  hoist_pattern_tdz(deep_x, lexical_env, LetBinding)
  inspect(lexical_env.bindings.contains("x"), content="true")
}
