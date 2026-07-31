///|
fn run_value(source : String) -> String raise Error {
  let (output, value) = @js_engine.run(source)
  guard output.length() == 0 else {
    fail("stack-safety source produced unexpected output")
  }
  value
}

///|
fn run_failure_message(source : String) -> String raise Error {
  match @js_engine.run_diagnostic(source) {
    Ok(_) => fail("expected the source to fail")
    Err(diagnostic) => diagnostic.message()
  }
}

///|
fn nested_comma_source(depth : Int, final_expression : String) -> String {
  let mut source = final_expression
  for _ in 0..<depth {
    source = "0," + source
  }
  source
}

///|
const SELF_RECURSION_SOURCE =
  #|function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);

///|
const MUTUAL_RECURSION_SOURCE =
  #|function f(n){if(n===0)return 0;return 1+g(n-1);}
  #|function g(n){if(n===0)return 0;return 1+f(n-1);}
  #|f(256);

///|
const GETTER_REENTRY_SOURCE =
  #|let n=256;
  #|let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};
  #|o.x;

///|
const PROXY_REENTRY_SOURCE =
  #|let n=256;
  #|let p;
  #|p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});
  #|p.x;

///|
const NORMAL_FINALLY_SOURCE =
  #|function f(n){if(n===0)return 0;try{return 1+f(n-1);}finally{0;}}
  #|try{f(256);}finally{0;}

///|
const ABRUPT_FINALLY_SOURCE =
  #|function f(n){if(n===0)return 0;return 1+f(n-1);}
  #|try{throw f(256);}catch{1;}finally{throw 7;}

///|
const LABELLED_BREAK_SOURCE = "outer: try { break outer; } finally { 1; } 9;"

///|
const BOUNDED_CONTINUE_SOURCE =
  "do try { continue; } finally { 2; } while(false); 8;"

///|
const GUEST_THROW_FINALLY_SOURCE =
  #|function f(n){if(n===0)return 0;try{return 1+g(n-1);}finally{0;}}
  #|function g(n){if(n===0)return 0;try{return 1+f(n-1);}finally{throw 7;}}
  #|f(256);

///|
const PROTECTED_CATCH_SOURCE =
  #|function f(n){if(n===0)return 0;return 1+f(n-1);}
  #|try{throw f(256);}catch(e){e;}

///|
const PROTOTYPE_GETTER_LOOKALIKE_SOURCE =
  #|let n=8;let p={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};
  #|let o={__proto__:p};o.x;

///|
const PROTOTYPE_SHORTHAND_LOOKALIKE_SOURCE =
  #|let n=8;let __proto__={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};
  #|let o={__proto__};o.x;

///|
const OWN_GETTER_LOOKALIKE_SOURCE =
  #|let n=8;let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};o.x;

///|
const PROXY_GET_LOOKALIKE_SOURCE =
  #|let n=8;let p;p=new Proxy({},{get(t,k,r){if(n===0)return 0;n=n-1;return 1+p.x;}});p.x;

///|
test "stack safety public facade: exact production-admitted depth-256 values" {
  inspect(run_value(SELF_RECURSION_SOURCE), content="256")
  inspect(run_value(MUTUAL_RECURSION_SOURCE), content="256")
  inspect(run_value(GETTER_REENTRY_SOURCE), content="256")
  inspect(run_value(PROXY_REENTRY_SOURCE), content="256")
}

///|
test "stack safety public facade: protected completion and control values" {
  inspect(run_value(NORMAL_FINALLY_SOURCE), content="256")
  inspect(run_value(LABELLED_BREAK_SOURCE), content="9")
  inspect(run_value(BOUNDED_CONTINUE_SOURCE), content="8")
  inspect(run_value(PROTECTED_CATCH_SOURCE), content="256")
}

///|
test "stack safety public facade: guest and finalizer abrupt completion" {
  inspect(run_failure_message(ABRUPT_FINALLY_SOURCE), content="7")
  inspect(run_failure_message(GUEST_THROW_FINALLY_SOURCE), content="7")
}

///|
test "stack safety public facade: shallow legacy controls stay unchanged" {
  let lookalikes = [
    (PROTOTYPE_GETTER_LOOKALIKE_SOURCE, "8"),
    (PROTOTYPE_SHORTHAND_LOOKALIKE_SOURCE, "8"),
    (OWN_GETTER_LOOKALIKE_SOURCE, "8"),
    (PROXY_GET_LOOKALIKE_SOURCE, "8"),
  ]
  for pair in lookalikes {
    let (source, expected) = pair
    guard run_value(source) == expected else {
      fail("shallow lookalike changed: expected " + expected)
    }
  }
}

///|
test "stack safety public facade: post-parse phase isolation" {
  let source = "\"use strict\"; " + nested_comma_source(512, "eval = 0")
  inspect(
    run_failure_message(source),
    content="SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "stack safety public facade: post-parse first-error ordering" {
  inspect(
    run_failure_message("\"use strict\"; (eval = 0, function() { let x; var x; })"),
    content="SyntaxError: Unexpected eval or arguments in strict mode",
  )
  inspect(
    run_failure_message("function f(a = (eval = 0)) { let x; var x; }"),
    content="SyntaxError: Identifier 'x' has already been declared",
  )
  inspect(
    run_failure_message("class C extends (eval = 0) { m() { let x; var x; } }"),
    content="SyntaxError: Unexpected eval or arguments in strict mode",
  )
  inspect(
    run_failure_message("switch (eval = 0) { case 0: let x; var x; }"),
    content="SyntaxError: Identifier 'x' has already been declared",
  )
  inspect(
    run_failure_message(
      "\"use strict\"; ({[eval = 0]: x = function() { let y; var y; }} = {})",
    ),
    content="SyntaxError: Unexpected eval or arguments in strict mode",
  )
  inspect(
    run_failure_message("\"use strict\"; `\\1${eval = 0}`"),
    content="SyntaxError: Invalid escape sequence in template literal at line 1, col 15",
  )
}

///|
test "stack safety public facade: direct eval Contains remains phase-isolated" {
  let eval_body = nested_comma_source(4096, "new.target")
  inspect(
    run_failure_message("eval(\"" + eval_body + "\")"),
    content="SyntaxError: 'new.target' is not allowed outside of a function — eval source contains new.target at the top level",
  )
}

///|
test "stack safety public facade: bounded production dispatcher stress" {
  // This is deliberately the same source and depth as the required numeric
  // slice; its separate name records the measured CI-cost evidence for #619.
  inspect(run_value(SELF_RECURSION_SOURCE), content="256")
}
