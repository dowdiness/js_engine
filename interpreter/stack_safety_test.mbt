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
const INTRINSIC_APPLY_RECURSION_SOURCE =
  #|function step(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + step.apply(undefined, [n - 1]);
  #|}
  #|step(256);

///|
const INTRINSIC_APPLY_MAPPED_ARGUMENTS_SOURCE =
  #|function step(n) {
  #|  if (n === 0) return 0;
  #|  arguments[0] = n - 1;
  #|  return 1 + step.apply(undefined, arguments);
  #|}
  #|step(256);

///|
const ARRAY_MAP_MEMBER_RECURSION_SOURCE =
  #|function step(n) {
  #|  if (n === 0) return 0;
  #|  var items = [{next: function() { return step(n - 1); }}];
  #|  return 1 + items.map(function(t) { return t.next(); })[0];
  #|}
  #|step(256);

///|
const ARRAY_MAP_DIRECT_RECURSION_SOURCE =
  #|function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return u(t-1,e,!f);})[0];}
  #|u(256,0,false);

///|
const ARRAY_MAP_FORWARDING_RECURSION_SOURCE =
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
const NUMERIC_MAP_COMPOSITION_SOURCE =
  #|function step(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + step(n - 1);
  #|}
  #|function f(t) {
  #|  if (t === 0) return 0;
  #|  return u(t);
  #|}
  #|function u(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + [n - 1, 0].map(function(t) { return f(t); })[0];
  #|}
  #|step(256) + u(256);

///|
const LEFT_ASSOCIATED_NUMERIC_MAP_COMPOSITION_SOURCE =
  #|function step(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + step(n - 1);
  #|}
  #|function f(t) {
  #|  if (t === 0) return 0;
  #|  return u(t);
  #|}
  #|function u(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + [n - 1, 0].map(function(t) { return f(t); })[0];
  #|}
  #|step(256) + u(256) + step(256);

///|
const FOUR_CALL_LEFT_ASSOCIATED_SOURCE =
  #|function step(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + step(n - 1);
  #|}
  #|function f(t) {
  #|  if (t === 0) return 0;
  #|  return u(t);
  #|}
  #|function u(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + [n - 1, 0].map(function(t) { return f(t); })[0];
  #|}
  #|step(256) + u(256) + step(256) + u(256);

///|
const FIVE_CALL_LEFT_ASSOCIATED_SOURCE =
  #|function step(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + step(n - 1);
  #|}
  #|function f(t) {
  #|  if (t === 0) return 0;
  #|  return u(t);
  #|}
  #|function u(n) {
  #|  if (n === 0) return 0;
  #|  return 1 + [n - 1, 0].map(function(t) { return f(t); })[0];
  #|}
  #|step(256) + u(256) + step(256) + u(256) + step(256);

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
test "execution stack safety: intrinsic apply forwarding recursion at depth 256" {
  match run(INTRINSIC_APPLY_RECURSION_SOURCE) {
    Value::Number(256.0) => ()
    other =>
      fail("expected intrinsic apply result 256, got " + other.to_string())
  }
}

///|
test "execution stack safety: intrinsic apply forwarding mapped arguments at depth 256" {
  match run(INTRINSIC_APPLY_MAPPED_ARGUMENTS_SOURCE) {
    Value::Number(256.0) => ()
    other =>
      fail(
        "expected intrinsic apply mapped arguments result 256, got " +
        other.to_string(),
      )
  }
}

///|
test "execution stack safety: exact array map member callback at depth 256" {
  match run(ARRAY_MAP_MEMBER_RECURSION_SOURCE) {
    Value::Number(256.0) => ()
    other =>
      fail(
        "expected exact array map member callback result 256, got " +
        other.to_string(),
      )
  }
}

///|
test "execution stack safety: exact array map direct callback at depth 256" {
  match run(ARRAY_MAP_DIRECT_RECURSION_SOURCE) {
    Value::Number(256.0) => ()
    other =>
      fail(
        "expected exact array map direct callback result 256, got " +
        other.to_string(),
      )
  }
}

///|
test "execution stack safety: array map forwarding callback at depth 256" {
  match run(ARRAY_MAP_FORWARDING_RECURSION_SOURCE) {
    Value::Number(256.0) => ()
    other =>
      fail(
        "expected array map forwarding callback result 256, got " +
        other.to_string(),
      )
  }
}

///|
test "execution stack safety: numeric and map calls compose at depth 256" {
  match run(NUMERIC_MAP_COMPOSITION_SOURCE) {
    Value::Number(512.0) => ()
    other =>
      fail(
        "expected numeric and map composition result 512, got " +
        other.to_string(),
      )
  }
}

///|
test "execution stack safety: left-associated numeric and map calls compose" {
  match run(LEFT_ASSOCIATED_NUMERIC_MAP_COMPOSITION_SOURCE) {
    Value::Number(768.0) => ()
    other =>
      fail(
        "expected left-associated composition result 768, got " +
        other.to_string(),
      )
  }
}

///|
test "execution stack safety: four left-associated numeric and map calls compose" {
  match run(FOUR_CALL_LEFT_ASSOCIATED_SOURCE) {
    Value::Number(1024.0) => ()
    other =>
      fail(
        "expected four-call composition result 1024, got " + other.to_string(),
      )
  }
}

///|
test "execution stack safety: five left-associated numeric and map calls compose" {
  match run(FIVE_CALL_LEFT_ASSOCIATED_SOURCE) {
    Value::Number(1280.0) => ()
    other =>
      fail("expected five-call composition result 1280, got " + other.to_string())
  }
}

///|
test "numeric and map composition cleanup permits a second run" {
  let interp = new_interpreter()
  let first = interp.run(@parser.parse(NUMERIC_MAP_COMPOSITION_SOURCE).stmts)
  let second = interp.run(@parser.parse(NUMERIC_MAP_COMPOSITION_SOURCE).stmts)
  match (first, second) {
    (Value::Number(512.0), Value::Number(512.0)) => ()
    (first, second) =>
      fail(
        "composition cleanup changed repeated results: " +
        first.to_string() +
        ", " +
        second.to_string(),
      )
  }
}

///|
test "array map cleanup permits a second run on the same Interpreter" {
  let interp = new_interpreter()
  let first = interp.run(@parser.parse(ARRAY_MAP_MEMBER_RECURSION_SOURCE).stmts)
  let second = interp.run(
    @parser.parse(ARRAY_MAP_MEMBER_RECURSION_SOURCE).stmts,
  )
  match (first, second) {
    (Value::Number(256.0), Value::Number(256.0)) => ()
    (first, second) =>
      fail(
        "array map cleanup changed repeated results: " +
        first.to_string() +
        ", " +
        second.to_string(),
      )
  }
}

///|
test "array map direct cleanup permits a second run on the same Interpreter" {
  let interp = new_interpreter()
  let first = interp.run(@parser.parse(ARRAY_MAP_DIRECT_RECURSION_SOURCE).stmts)
  let second = interp.run(
    @parser.parse(ARRAY_MAP_DIRECT_RECURSION_SOURCE).stmts,
  )
  match (first, second) {
    (Value::Number(256.0), Value::Number(256.0)) => ()
    (first, second) =>
      fail(
        "direct map cleanup changed repeated results: " +
        first.to_string() +
        ", " +
        second.to_string(),
      )
  }
}

///|
test "array map forwarding cleanup permits a second run on the same Interpreter" {
  let interp = new_interpreter()
  let first = interp.run(
    @parser.parse(ARRAY_MAP_FORWARDING_RECURSION_SOURCE).stmts,
  )
  let second = interp.run(
    @parser.parse(ARRAY_MAP_FORWARDING_RECURSION_SOURCE).stmts,
  )
  match (first, second) {
    (Value::Number(256.0), Value::Number(256.0)) => ()
    (first, second) =>
      fail(
        "forwarding map cleanup changed repeated results: " +
        first.to_string() +
        ", " +
        second.to_string(),
      )
  }
}

///|
test "array map replacement stays legacy across same Interpreter runs" {
  let interp = new_interpreter()
  let replacement = @parser.parse(
      "Array.prototype.map=function(){return [7];};",
    ).stmts
  ignore(interp.run(replacement))
  let exact = @parser.parse(ARRAY_MAP_MEMBER_RECURSION_SOURCE).stmts
  match interp.run(exact) {
    Value::Number(8.0) => ()
    other =>
      fail(
        "replaced Array.prototype.map must stay legacy, got " +
        other.to_string(),
      )
  }
}

///|
test "array map near miss: replaced and own map stay legacy" {
  match
    run(
      "function step(n){if(n===0)return 0;" +
      "var items=[{next:function(){return step(n-1);}}];" +
      "items.map=function(){return [41];};" +
      "return 1+items.map(function(t){return t.next();})[0];}step(2);",
    ) {
    Value::Number(42.0) => ()
    other => fail("own map override changed result: " + other.to_string())
  }
  match
    run(
      "Array.prototype.map=function(){return [7];};" +
      "function step(n){if(n===0)return 0;" +
      "var items=[{next:function(){return step(n-1);}}];" +
      "return 1+items.map(function(t){return t.next();})[0];}step(2);",
    ) {
    Value::Number(8.0) => ()
    other => fail("prototype map override changed result: " + other.to_string())
  }
}

///|
test "array map near miss: prototype and species drift stay legacy" {
  match
    run(
      "var source=[1];var calls=0;" +
      "source.constructor={};" +
      "Object.defineProperty(source.constructor,Symbol.species,{get:function(){" +
      "calls=calls+1;return Array;}});" +
      "var result=source.map(function(x){return x+1;});calls+result[0];",
    ) {
    Value::Number(3.0) => ()
    other =>
      fail("species drift did not preserve result/order: " + other.to_string())
  }
}

///|
test "array map near miss: sparse accessor and proxy receivers stay legacy" {
  match
    run(
      "var source=[];source[1]=2;var seen=[];" +
      "var result=source.map(function(x,i){seen.push(i+\":\"+x);return x;});" +
      "result.length+\":\"+result[0]+\":\"+result[1]+\":\"+seen.join(\"|\");",
    ) {
    Value::String_(value) => inspect(value, content="2:undefined:2:1:2")
    other => fail("sparse map semantics changed: " + other.to_string())
  }
  match
    run(
      "var source=[1];var reads=0;" +
      "Object.defineProperty(source,\"0\",{get:function(){reads=reads+1;return 7;}});" +
      "var result=source.map(function(x){return x+1;});reads+result[0];",
    ) {
    Value::Number(9.0) => ()
    other => fail("accessor map semantics changed: " + other.to_string())
  }
  match
    run(
      "var source=[1];var seen=[];" +
      "var proxy=new Proxy(source,{has:function(t,k){seen.push(\"has:\"+k);" +
      "return Reflect.has(t,k);},get:function(t,k,r){seen.push(\"get:\"+k);" +
      "return Reflect.get(t,k,r);}});" +
      "var result=proxy.map(function(x){return x+1;});" +
      "result[0]+\":\"+seen.join(\"|\");",
    ) {
    Value::String_(value) =>
      inspect(value, content="2:get:map|get:length|get:constructor|has:0|get:0")
    other => fail("proxy map semantics changed: " + other.to_string())
  }
}

///|
test "array map near miss: computed member, callback body, and callee stay legacy" {
  match
    run(
      "function step(n){if(n===0)return 0;" +
      "var items=[{next:function(){return step(n-1);}}];" +
      "return 1+items.map(function(t){return t[\"next\"]();})[0];}step(2);",
    ) {
    Value::Number(2.0) => ()
    other => fail("computed member map changed result: " + other.to_string())
  }
  match
    run(
      "function step(n){if(n===0)return 0;" +
      "var items=[{next:function(){return step(n-1);}}];" +
      "return 1+items.map(function(t){var marker=1;return t.next()+marker-1;})[0];" +
      "}step(2);",
    ) {
    Value::Number(2.0) => ()
    other => fail("callback body mutation changed result: " + other.to_string())
  }
  match
    run(
      "function step(n){if(n===0)return 0;" +
      "var items=[{next:function(){return step(n-1);}}];" +
      "var map=items.map;return 1+map.call(items,function(t){return t.next();})[0];" +
      "}step(2);",
    ) {
    Value::Number(2.0) => ()
    other => fail("callee mutation changed result: " + other.to_string())
  }
}

///|
test "array map near miss: non-UserFunc callback and non-one-element length stay legacy" {
  match run("[1].map(String)[0]") {
    Value::String_(value) => inspect(value, content="1")
    other => fail("builtin callback map changed result: " + other.to_string())
  }
  match
    run(
      "var source=[{next:function(){return 1;}},{next:function(){return 2;}}];" +
      "var calls=[];var result=source.map(function(t,i,receiver){" +
      "calls.push(i+\":\"+(receiver===source));return t.next();});" +
      "result.length+\":\"+result[0]+\":\"+result[1]+\":\"+calls.join(\"|\");",
    ) {
    Value::String_(value) => inspect(value, content="2:1:2:0:true|1:true")
    other =>
      fail("non-one-element map changed result/order: " + other.to_string())
  }
}

///|
test "array map forwarding shape length near misses stay legacy" {
  match
    run(
      "function f(t){if(t===0)return 0;return u(t);}" +
      "function u(n){if(n===0)return 0;return 1+[].map(function(t){return f(t);})[0];}" +
      "u(2)!==u(2);",
    ) {
    Value::Bool(true) => ()
    other =>
      fail("empty forwarding map changed NaN semantics: " + other.to_string())
  }
  match
    run(
      "function f(t){if(t===0)return 0;return u(t);}" +
      "function u(n){if(n===0)return 0;return 1+[n-1].map(function(t){return f(t);})[0];}" +
      "u(2);",
    ) {
    Value::Number(2.0) => ()
    other =>
      fail("one-element forwarding map changed result: " + other.to_string())
  }
  match
    run(
      "function f(t){if(t===0)return 0;return u(t);}" +
      "function u(n){if(n===0)return 0;return 1+[n-1,0,0].map(function(t){return f(t);})[0];}" +
      "u(2);",
    ) {
    Value::Number(2.0) => ()
    other =>
      fail("three-element forwarding map changed result: " + other.to_string())
  }
}

///|
test "array map direct near misses stay legacy" {
  let cases = [
    (
      "function u(t,e,f){if(t===0)return 0;return 1+[e,e].map(function(e){return u(t-1,e,!f);})[0];}u(2,0,false);",
      2.0,
    ),
    (
      "function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return u(t-1,e,!f);})[0];}u(2,0,false);",
      2.0,
    ),
    (
      "function u(t,e){if(t===0)return 0;return 1+[e].map(function(e){return u(t-1,e);})[0];}u(2,0);",
      2.0,
    ),
    (
      "function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return u(t-1,e,!f)+0;})[0];}u(2,0,false);",
      2.0,
    ),
    (
      "function v(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return v(t-1,e,!f);})[0];}function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return v(t-1,e,!f);})[0];}u(2,0,false);",
      2.0,
    ),
    (
      "function u(t,e,f){if(t==0)return 0;return 1+[e].map(function(e){return u(t-1,e,!f);})[0];}u(2,0,false);",
      2.0,
    ),
    (
      "function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return u.call(undefined,t-1,e,!f);})[0];}u(2,0,false);",
      2.0,
    ),
    (
      "function u(t,e,f){if(t===0)return 0;return 1+[e].map(Number)[0];}u(2,0,false);",
      1.0,
    ),
    (
      "\"use strict\";function u(t,e,f){if(t===0)return 0;return 1+[e].map(function(e){return u(t-1,e,!f);})[0];}u(2,0,false);",
      2.0,
    ),
    (
      "function u(t,e,f){if(t===0)return this===undefined?1:0;return 1+[e].map(function(e){return u(t-1,e,!f);})[0];}u(2,0,false);",
      2.0,
    ),
    (
      "function u(t,e,f){\"use strict\";if(t===0)return this===undefined?1:0;return 1+[e].map(function(e){return u(t-1,e,!f);})[0];}u(2,0,false);",
      3.0,
    ),
  ]
  for pair in cases {
    let (source, expected) = pair
    match run(source) {
      Value::Number(value) => inspect(value, content=expected.to_string())
      other => fail("direct near miss changed result: " + other.to_string())
    }
  }
}

///|
test "array map observes length before callback callability" {
  match
    run(
      "var seen=[];var source=new Proxy([1],{get:function(t,k,r){" +
      "seen.push(k);return Reflect.get(t,k,r);}});" +
      "try{source.map(0);}catch(e){}seen.join(\"|\");",
    ) {
    Value::String_(value) => inspect(value, content="map|length")
    other => fail("map length/callability order changed: " + other.to_string())
  }
}

///|
test "array map preserves callback thisArg argument order result and length" {
  match
    run(
      "var source=[{next:function(){return 7;}}];" +
      "var thisArg={marker:3};var seen=0;" +
      "var result=source.map(function(value,index,receiver){" +
      "seen=(this===thisArg?1:0)+index+(receiver===source?10:0)+" +
      "(value===source[0]?100:0);return this.marker+value.next();},thisArg);" +
      "result.length+\":\"+result[0]+\":\"+seen;",
    ) {
    Value::String_(value) => inspect(value, content="1:10:111")
    other =>
      fail("map callback arguments or result changed: " + other.to_string())
  }
}

///|
test "intrinsic apply recursion stays legacy when the function owns apply" {
  match
    run(
      "function step(n){if(n===0)return 0;return 1+step.apply(undefined,[n-1]);}" +
      "step.apply=function(){return 7;};step(256);",
    ) {
    Value::Number(8.0) => ()
    other =>
      fail("expected overridden own apply result 8, got " + other.to_string())
  }
}

///|
test "intrinsic apply recursion stays legacy when Function.prototype.apply changes" {
  match
    run(
      "function step(n){if(n===0)return 0;return 1+step.apply(undefined,[n-1]);}" +
      "Function.prototype.apply=function(){return 7;};step(256);",
    ) {
    Value::Number(8.0) => ()
    other =>
      fail(
        "expected replaced Function.prototype.apply result 8, got " +
        other.to_string(),
      )
  }
}

///|
test "intrinsic apply recursion stays legacy after function prototype drift" {
  match
    run(
      "function step(n){if(n===0)return 0;return 1+step.apply(undefined,[n-1]);}" +
      "Object.setPrototypeOf(step,{apply:function(){return 7;}});step(2);",
    ) {
    Value::Number(value) => inspect(value, content="8")
    other => fail("unexpected prototype drift result: " + other.to_string())
  }
}

///|
test "intrinsic apply preserves sparse array holes through legacy reads" {
  match
    run(
      "function read(value){return value===undefined;}" +
      "read.apply(undefined,[,]);",
    ) {
    Value::Bool(true) => ()
    other =>
      fail(
        "expected a sparse hole to read as undefined, got " + other.to_string(),
      )
  }
}

///|
test "intrinsic apply preserves array accessor reads through legacy fallback" {
  match
    run(
      "let reads=0;let args=[0];" +
      "Object.defineProperty(args,\"0\",{get:function(){reads=reads+1;return 7;}});" +
      "function read(value){return value;}read.apply(undefined,args)+reads;",
    ) {
    Value::Number(8.0) => ()
    other =>
      fail("expected one accessor read and value 7, got " + other.to_string())
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
