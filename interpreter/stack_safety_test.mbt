///|
fn nested_comma_source(depth : Int, final_expression : String) -> String {
  let mut source = final_expression
  for _ in 0..<depth {
    source = "0," + source
  }
  source
}

///|
fn nested_array_pattern_source(depth : Int, inner : String) -> String {
  let mut source = inner
  for _ in 0..<depth {
    source = "[" + source + "]"
  }
  source
}

///|
test "post-parse stack safety: GeneratorFunction parameter Contains(YieldExpression)" {
  let parameter = nested_array_pattern_source(512, "value = yield 0")
  inspect(
    run_throws(
      "let GF = (function*(){}).constructor; new GF(\"" +
      parameter +
      "\", \"\");",
    ),
    content="SyntaxError: Generator formal parameters may not contain yield expressions",
  )
}

///|
#skip("blocked by #608 runtime evaluator stack safety")
test "post-parse stack safety: 512 comma expressions" {
  inspect(run(nested_comma_source(512, "7")), content="7")
}

///|
test "post-parse stack safety phase isolation: 512 comma expressions" {
  inspect(
    run_throws("\"use strict\"; " + nested_comma_source(512, "eval = 0")),
    content="SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "post-parse stack safety: direct eval Contains handles 4096 comma expressions" {
  let eval_body = nested_comma_source(4096, "new.target")
  inspect(
    run_throws("eval(\"" + eval_body + "\")"),
    content="SyntaxError: 'new.target' is not allowed outside of a function — eval source contains new.target at the top level",
  )
}

///|
test "post-parse stack safety: comma expression preserves first error" {
  inspect(
    run_throws("\"use strict\"; (eval = 0, function() { let x; var x; })"),
    content="SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "post-parse stack safety: function preserves first error" {
  inspect(
    run_throws("function f(a = (eval = 0)) { let x; var x; }"),
    content="SyntaxError: Identifier 'x' has already been declared",
  )
}

///|
test "post-parse stack safety: class preserves first error" {
  inspect(
    run_throws("class C extends (eval = 0) { m() { let x; var x; } }"),
    content="SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "post-parse stack safety: switch preserves first error" {
  inspect(
    run_throws("switch (eval = 0) { case 0: let x; var x; }"),
    content="SyntaxError: Identifier 'x' has already been declared",
  )
}

///|
test "post-parse stack safety: pattern preserves first error" {
  inspect(
    run_throws(
      "\"use strict\"; ({[eval = 0]: x = function() { let y; var y; }} = {})",
    ),
    content="SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "post-parse stack safety: template quasi precedes substitution" {
  inspect(
    run_throws("\"use strict\"; `\\1${eval = 0}`"),
    content="SyntaxError: Invalid escape sequence in template literal at line 1, col 15",
  )
}
