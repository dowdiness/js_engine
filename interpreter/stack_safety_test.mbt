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
fn retained_numeric_argument_source() -> String {
  let mut argument = "7"
  for _ in 0..<263 {
    argument = "0," + argument
  }
  "function step(n,x){if(n===0)return x;return 1+step(n-1,x);}" +
  "step(256,(" +
  argument +
  "));"
}

///|
test "execution stack safety: self recursion at depth 256" {
  match run("function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);") {
    Value::Number(256.0) => ()
    other => fail("expected 256, got " + other.to_string())
  }
}

///|
// Regression coverage for the exact #790 retained-argument managed slice.
test "execution stack safety: retained numeric argument across tree-walker activations" {
  match run(retained_numeric_argument_source()) {
    Value::Number(263.0) => ()
    other =>
      fail("expected retained argument result 263, got " + other.to_string())
  }
}

///|
// RED on current main: native debug completes depth 50 and terminates at 51;
// the production target is the same direct ordinary constructor at depth 1024.
test "RED: recursive constructor activation at depth 1024" {
  match
    run(
      "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
      "new Node(1024).value;",
    ) {
    Value::Number(1024.0) => ()
    other => fail("expected constructor value 1024, got " + other.to_string())
  }
}

///|
test "execution stack safety: mutual constructor activation at depth 1024" {
  match
    run(
      "function A(n){this.value=n;if(n>0){this.child=new B(n-1);}}" +
      "function B(n){this.value=n;if(n>0){this.child=new A(n-1);}}" +
      "new A(1024).value;",
    ) {
    Value::Number(1024.0) => ()
    other =>
      fail("expected mutual constructor value 1024, got " + other.to_string())
  }
}

///|
test "ordinary constructor return replacement stays exact" {
  match
    run(
      "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}" +
      "return {value:99,marker:1};}" +
      "new Node(4).marker;",
    ) {
    Value::Number(1.0) => ()
    other => fail("expected object return marker 1, got " + other.to_string())
  }
  match
    run(
      "function Plain(n){this.value=n;if(n>0){this.child=new Plain(n-1);}" +
      "return n;}" +
      "new Plain(4).value;",
    ) {
    Value::Number(4.0) => ()
    other =>
      fail("expected primitive fallback value 4, got " + other.to_string())
  }
  match
    run(
      "function UndefinedNode(n){this.value=n;if(n>0){this.child=new UndefinedNode(n-1);}" +
      "return undefined;}" +
      "new UndefinedNode(4).value;",
    ) {
    Value::Number(4.0) => ()
    other =>
      fail("expected undefined fallback value 4, got " + other.to_string())
  }
}

///|
test "ordinary constructor throw releases activation state" {
  let interp = Interpreter::new()
  let source = "function Boom(n){this.value=n;if(n>0){this.child=new Boom(n-1);}" +
    "throw n;}new Boom(2).value;"
  // The recursive base activation throws its own exact parameter value.
  let thrown : Error? = try {
    let _ = interp.run(@parser.parse(source).stmts)
    None
  } catch {
    error => Some(error)
  }
  match thrown {
    Some(@runtime.JsException(Number(value))) => inspect(value, content="0")
    Some(error) =>
      fail("expected the exact constructor throw, got " + error.to_string())
    None => fail("expected the recursive constructor to throw")
  }
  match
    interp.run(
      @parser.parse(
        "function Safe(n){this.value=n;if(n>0){this.child=new Safe(n-1);}}" +
        "new Safe(0).value;",
      ).stmts,
    ) {
    Value::Number(0.0) => ()
    other =>
      fail("expected a later shallow construction, got " + other.to_string())
  }
}

///|
test "mutation-sensitive ordinary constructors stay on legacy shallow path" {
  for
    source in [
      "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}this.extra=1;}" +
      "new Node(0).value;",
      "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
      "new Node(...[0]).value;",
      "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
      "new (Node)(0).value;",
      "function Node(n=0){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
      "new Node(0).value;",
      "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
      "Node.prototype=new Proxy({},{});new Node(0).value;",
      "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
      "function zero(){return 0;}new Node(zero()).value;",
    ] {
    let result : Result[Value, Error] = Ok(run(source)) catch {
      error => Err(error)
    }
    match result {
      Ok(Value::Number(0.0)) => ()
      Ok(result) =>
        fail(
          "legacy constructor boundary changed: expected 0, got " +
          result.to_string() +
          " source=" +
          source,
        )
      Err(error) =>
        fail(
          "legacy constructor boundary raised " +
          error.to_string() +
          " source=" +
          source,
        )
    }
  }
  match
    run(
      "function Node(n){this.value=n;if(n>0){this.child=new Node(n-1);}}" +
      "Node=function Other(n){this.value=99;};new Node(0).value;",
    ) {
    Value::Number(99.0) => ()
    result =>
      fail(
        "legacy reassigned constructor changed: expected 99, got " +
        result.to_string(),
      )
  }
}

///|
test "execution stack safety: ordinary own-data receiver recursion at depth 256" {
  match
    run(
      "function step(n){if(n===0)return this.marker;return 1+this.step(n-1);}" +
      "let receiver={marker:0,step:step};receiver.step(256);",
    ) {
    Value::Number(256.0) => ()
    other => fail("expected receiver recursion 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: computed-literal own-data receiver recursion at depth 256" {
  match
    run(
      "function step(n){if(n===0)return this[\"marker\"];return 1+this[\"step\"](n-1);}" +
      "let receiver={[\"marker\"]:0,[\"step\"]:step};receiver[\"step\"](256);",
    ) {
    Value::Number(256.0) => ()
    other =>
      fail("expected computed receiver recursion 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: escaped computed own-data receiver recursion at depth 256" {
  match
    run(
      "function step(n){if(n===0)return this[\"\\x6darker\"];return 1+this[\"\\x73tep\"](n-1);}" +
      "let receiver={[\"\\x6darker\"]:0,[\"\\x73tep\"]:step};receiver[\"\\x73tep\"](256);",
    ) {
    Value::Number(256.0) => ()
    other =>
      fail(
        "expected escaped computed receiver recursion 256, got " +
        other.to_string(),
      )
  }
}

///|
test "execution stack safety: escaped computed mutual receiver recursion at depth 256" {
  for
    source in [
      MUTUAL_RECEIVER_RECURSION_SOURCE,
      REVERSED_MUTUAL_RECEIVER_RECURSION_SOURCE,
    ] {
    match run(source) {
      Value::Number(256.0) => ()
      other =>
        fail(
          "expected escaped computed mutual receiver recursion 256, got " +
          other.to_string(),
        )
    }
  }
}

///|
test "execution dispatch preserves legacy receiver argument ordering" {
  match
    run(
      "let receiver={step:0};let evaluated=0;" +
      "try{receiver.step(evaluated=1);}catch{} evaluated;",
    ) {
    Value::Number(1.0) => ()
    other =>
      fail(
        "expected the receiver argument to evaluate before TypeError, got " +
        other.to_string(),
      )
  }
}

///|
test "execution dispatch preserves computed receiver argument ordering" {
  match
    run(
      "let receiver={[\"step\"]:0};let evaluated=0;" +
      "try{receiver[\"step\"](evaluated=1);}catch{} evaluated;",
    ) {
    Value::Number(1.0) => ()
    other =>
      fail(
        "expected the computed receiver argument to evaluate before TypeError, got " +
        other.to_string(),
      )
  }
}

///|
test "execution stack safety: recursive return crosses normal finally at depth 256" {
  match
    run(
      "function f(n){if(n===0)return 0;" +
      "try{return 1+f(n-1);}finally{0;}} f(256);",
    ) {
    Value::Number(256.0) => ()
    other => fail("expected resumed 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: recursive return is replaced by abrupt finally" {
  inspect(
    run_throws(
      "function f(n){if(n===0)return 0;" +
      "try{return 1+f(n-1);}finally{throw 7;}} f(256);",
    ),
    content="7",
  )
}

///|
test "execution stack safety: labelled break crosses a closed finalizer" {
  match run("outer: try { break outer; } finally { 1; } 9;") {
    Value::Number(9.0) => ()
    other => fail("expected 9 after labelled break, got " + other.to_string())
  }
}

///|
test "execution stack safety: bounded continue crosses a closed finalizer" {
  match run("do try { continue; } finally { 2; } while(false); 8;") {
    Value::Number(8.0) => ()
    other => fail("expected 8 after bounded continue, got " + other.to_string())
  }
}

///|
test "execution dispatch preserves structural control lookalike behavior" {
  match run("outer: try { break outer; } finally { 1; 2; } 9;") {
    Value::Number(9.0) => ()
    other => fail("expected legacy labelled-break 9, got " + other.to_string())
  }
  match run("do try { continue; } finally { 2; 3; } while(false); 8;") {
    Value::Number(8.0) => ()
    other =>
      fail("expected legacy bounded-continue 8, got " + other.to_string())
  }
}

///|
test "execution stack safety: guest throw crosses a normal recursive finalizer" {
  inspect(
    run_throws(
      "function f(n){if(n===0)return 0;" +
      "try{return 1+g(n-1);}finally{0;}}" +
      "function g(n){if(n===0)return 0;" +
      "try{return 1+f(n-1);}finally{throw 7;}}" +
      "f(256);",
    ),
    content="7",
  )
}

///|
test "execution stack safety: mutual recursion at depth 256" {
  match
    run(
      "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
      "function g(n){if(n===0)return 0;return 1+f(n-1);}" +
      "f(256);",
    ) {
    Value::Number(256.0) => ()
    other => fail("expected 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: public call_value self recursion at depth 256" {
  let interp = new_interpreter()
  let program = @parser.parse(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}",
  )
  let _ = interp.run(program.stmts)
  let result = interp.call_value(
    interp.global.get("f"),
    Value::Undefined,
    [Value::Number(256.0)],
    @token.Loc::default(),
  )
  match result {
    Value::Number(256.0) => ()
    other => fail("expected 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: public call_value preserves stamped source provenance" {
  let interp = new_interpreter()
  let program = @parser.parse(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}",
  )
  @runtime.with_source_identity(interp.realm_state, Some("direct.js"), () => {
    ignore(interp.run(program.stmts))
  })
  let result = interp.call_value(
    interp.global.get("f"),
    Value::Undefined,
    [Value::Number(256.0)],
    @token.Loc::default(),
  )
  match result {
    Value::Number(256.0) => ()
    other => fail("expected 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: public call_value mutual recursion at depth 256" {
  let interp = new_interpreter()
  let program = @parser.parse(
    "function f(n){if(n===0)return 0;return 1+g(n-1);}" +
    "function g(n){if(n===0)return 0;return 1+f(n-1);}",
  )
  let _ = interp.run(program.stmts)
  let result = interp.call_value(
    interp.global.get("f"),
    Value::Undefined,
    [Value::Number(256.0)],
    @token.Loc::default(),
  )
  match result {
    Value::Number(256.0) => ()
    other => fail("expected 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: public call_value preserves mutual source provenance" {
  let interp = new_interpreter()
  let entry = @parser.parse("function f(n){if(n===0)return 0;return 1+g(n-1);}")
  @runtime.with_source_identity(interp.realm_state, Some("entry.js"), () => {
    ignore(interp.run(entry.stmts))
  })
  let peer = @parser.parse("function g(n){if(n===0)return 0;return 1+f(n-1);}")
  @runtime.with_source_identity(interp.realm_state, Some("peer.js"), () => {
    ignore(interp.run(peer.stmts))
  })
  let result = interp.call_value(
    interp.global.get("f"),
    Value::Undefined,
    [Value::Number(256.0)],
    @token.Loc::default(),
  )
  match result {
    Value::Number(256.0) => ()
    other => fail("expected 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: getter re-entry at depth 256" {
  match
    run(
      "let n=256;" +
      "let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
      "o.x;",
    ) {
    Value::Number(256.0) => ()
    other => fail("expected 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: prototype getter re-entry at depth 256" {
  match
    run(
      "let n=256;" +
      "let p={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
      "let o={__proto__:p};" +
      "o.x;",
    ) {
    Value::Number(256.0) => ()
    other => fail("expected 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: Proxy get re-entry at depth 256" {
  match
    run(
      "let n=256;" +
      "let p;" +
      "p=new Proxy({},{get(t,k,r){" +
      "if(n===0)return 0;n=n-1;return 1+p.x;" +
      "}});" +
      "p.x;",
    ) {
    Value::Number(256.0) => ()
    other => fail("expected 256, got " + other.to_string())
  }
}

///|
test "execution dispatch preserves shallow prototype getter lookalike behavior" {
  match
    run(
      "let n=8;" +
      "let p={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
      "let o={__proto__:p};" +
      "o.x;",
    ) {
    Value::Number(8.0) => ()
    other => fail("expected 8, got " + other.to_string())
  }
}

///|
test "execution dispatch preserves shallow getter __proto__ shorthand fallback" {
  match
    run(
      "let n=8;" +
      "let __proto__={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
      "let o={__proto__};" +
      "o.x;",
    ) {
    Value::Number(8.0) => ()
    other => fail("expected 8, got " + other.to_string())
  }
}

///|
test "execution dispatch preserves shallow getter lookalike behavior" {
  match
    run(
      "let n=8;" +
      "let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
      "o.x;",
    ) {
    Value::Number(8.0) => ()
    other => fail("expected 8, got " + other.to_string())
  }
}

///|
test "execution dispatch preserves shallow Proxy get lookalike behavior" {
  match
    run(
      "let n=8;" +
      "let p;" +
      "p=new Proxy({},{get(t,k,r){" +
      "if(n===0)return 0;n=n-1;return 1+p.x;" +
      "}});" +
      "p.x;",
    ) {
    Value::Number(8.0) => ()
    other => fail("expected 8, got " + other.to_string())
  }
}

///|
test "execution stack safety: protected catch resumes a deep throw" {
  match
    run(
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{throw f(256);}catch(e){e;}",
    ) {
    Value::Number(256.0) => ()
    other => fail("expected caught 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: normal finally resumes a deep completion" {
  match
    run(
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{f(256);}finally{0;}",
    ) {
    Value::Number(256.0) => ()
    other => fail("expected resumed 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: abrupt finally replaces a deep completion" {
  inspect(
    run_throws(
      "function f(n){if(n===0)return 0;return 1+f(n-1);}" +
      "try{throw f(256);}catch{1;}finally{throw 7;}",
    ),
    content="7",
  )
}

///|
test "post-parse stack safety: GeneratorFunction parameter Contains(YieldExpression)" {
  // Constructor integration reaches the parser's independent validation first;
  // generator_wbtest.mbt directly covers the private runtime walker.
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
test "post-parse stack safety phase isolation: 512 comma expressions" {
  inspect(
    run_throws("\"use strict\"; " + nested_comma_source(512, "eval = 0")),
    content="SyntaxError: Unexpected eval or arguments in strict mode",
  )
}

///|
test "post-parse stack safety: 512 comma expressions" {
  inspect(run(nested_comma_source(512, "7")), content="7")
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
test "PerformEval Contains scans destructuring declaration patterns" {
  inspect(
    run_throws("eval(\"let {[new.target]: value} = {};\")"),
    content="SyntaxError: 'new.target' is not allowed outside of a function — eval source contains new.target at the top level",
  )
}

///|
test "PerformEval Contains scans for-of patterns" {
  inspect(
    run_throws("eval(\"for (let {[new.target]: value} of []) {}\")"),
    content="SyntaxError: 'new.target' is not allowed outside of a function — eval source contains new.target at the top level",
  )
}

///|
test "PerformEval Contains scans catch parameters" {
  inspect(
    run_throws("eval(\"try {} catch ({[new.target]: value}) {}\")"),
    content="SyntaxError: 'new.target' is not allowed outside of a function — eval source contains new.target at the top level",
  )
}

///|
test "PerformEval Contains scans destructuring assignment patterns" {
  inspect(
    run_throws("eval(\"({[new.target]: value} = {});\")"),
    content="SyntaxError: 'new.target' is not allowed outside of a function — eval source contains new.target at the top level",
  )
}

///|
test "PerformEval Contains scans computed class declaration keys" {
  inspect(
    run_throws(
      "let executed = false; eval(\"class C { [new.target]() { executed = true; } }\"); executed",
    ),
    content="SyntaxError: 'new.target' is not allowed outside of a function — eval source contains new.target at the top level",
  )
}

///|
test "PerformEval Contains scans computed class expression keys" {
  inspect(
    run_throws(
      "let executed = false; eval(\"(class { [new.target] = (executed = true) })\"); executed",
    ),
    content="SyntaxError: 'new.target' is not allowed outside of a function — eval source contains new.target at the top level",
  )
}

///|
test "PerformEval Contains skips class member bodies and field initializers" {
  inspect(
    run(
      "eval(\"class C { field = new.target; method() { return new.target; } }; let c = new C(); c.field === undefined && c.method() === undefined\")",
    ),
    content="true",
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
