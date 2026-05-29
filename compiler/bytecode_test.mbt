///|
const BYTECODE_CLOSURE_FACTORY_PROGRAM : String =
  #|function makeCounter(start) {
  #|  var count = start;
  #|  return function() {
  #|    count = count + 1;
  #|    return count;
  #|  };
  #|}
  #|var counters = [];
  #|for (var i = 0; i < 1000; i++) {
  #|  counters.push(makeCounter(i));
  #|}
  #|var total = 0;
  #|for (var i = 0; i < 1000; i++) {
  #|  total = total + counters[i]();
  #|}
  #|total;

///|
const BYTECODE_PIPELINE_EXEC_PROGRAM : String =
  #|(function() {
  #|  function makeCounter(start) {
  #|    var count = start;
  #|    return function() {
  #|      count = count + 1;
  #|      return count;
  #|    };
  #|  }
  #|  var counters = [];
  #|  for (var i = 0; i < 1000; i++) {
  #|    counters.push(makeCounter(i));
  #|  }
  #|  var total = 0;
  #|  for (var i = 0; i < 1000; i++) {
  #|    total = total + counters[i]();
  #|  }
  #|  return total;
  #|})();

///|
fn bytecode_interpreter_outcome(src : String) -> String {
  try {
    let prog = @parser.parse(src)
    let interp = @interpreter.new_interpreter()
    "value:" + interp.run(prog.stmts).to_string()
  } catch {
    @runtime.JsException(value) => "throw:" + value.to_string()
    err => "error:" + err.to_string()
  }
}

///|
fn bytecode_outcome(src : String) -> String {
  try {
    let prog = @parser.parse(src)
    let interp = @interpreter.new_interpreter()
    let bytecode = compile_script_to_bytecode(prog.stmts)
    "value:" + bytecode.run(interp).to_string()
  } catch {
    @runtime.JsException(value) => "throw:" + value.to_string()
    err => "error:" + err.to_string()
  }
}

///|
fn bytecode_compare(src : String) -> String {
  let expected = bytecode_interpreter_outcome(src)
  let actual = bytecode_outcome(src)
  if actual == expected {
    actual
  } else {
    "expected \{expected}; got \{actual}"
  }
}

///|
fn bytecode_interpreter_output_outcome(src : String) -> String {
  let interp = @interpreter.new_interpreter()
  try {
    let prog = @parser.parse(src)
    "value:" +
    interp.run(prog.stmts).to_string() +
    "; output:" +
    interp.host.output.join("|")
  } catch {
    @runtime.JsException(value) =>
      "throw:" + value.to_string() + "; output:" + interp.host.output.join("|")
    err =>
      "error:" + err.to_string() + "; output:" + interp.host.output.join("|")
  }
}

///|
fn bytecode_output_outcome(src : String) -> String {
  let interp = @interpreter.new_interpreter()
  try {
    let prog = @parser.parse(src)
    let bytecode = compile_script_to_bytecode(prog.stmts)
    "value:" +
    bytecode.run(interp).to_string() +
    "; output:" +
    interp.host.output.join("|")
  } catch {
    @runtime.JsException(value) =>
      "throw:" + value.to_string() + "; output:" + interp.host.output.join("|")
    err =>
      "error:" + err.to_string() + "; output:" + interp.host.output.join("|")
  }
}

///|
fn bytecode_compare_with_output(src : String) -> String {
  let expected = bytecode_interpreter_output_outcome(src)
  let actual = bytecode_output_outcome(src)
  if actual == expected {
    actual
  } else {
    "expected \{expected}; got \{actual}"
  }
}

///|
test "bytecode constants locals and binary ops" {
  let src =
    #|var x = 1;
    #|x = x + 2;
    #|x;
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode comma expression returns right value" {
  let src =
    #|(0, "right");
  inspect(bytecode_compare(src), content="value:right")
}

///|
test "bytecode comma expression runs left side effects before right" {
  let src =
    #|var x = 0;
    #|(x = 1, x = x + 1);
    #|x;
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode comma in assignment expression statement returns right value" {
  let src =
    #|var x = 0;
    #|x = (1, 2);
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode nested grouped comma expressions preserve evaluation order" {
  let src =
    #|var order = "";
    #|var result = ((order = order + "a", order = order + "b"), (order = order + "c", order = order + "d"));
    #|order + ":" + result;
  inspect(bytecode_compare(src), content="value:abcd:abcd")
}

///|
test "bytecode template literal interpolates values" {
  let src =
    #|var x = 2;
    #|var y = true;
    #|`a${x + 1}b${y}c`;
  inspect(bytecode_compare(src), content="value:a3btruec")
}

///|
test "bytecode template literal converts substitutions before later expressions" {
  let src =
    #|var log = "";
    #|var f = function() {};
    #|f.toString = function() { log = log + "s"; return "F"; };
    #|var result = `${f}${(log = log + "e", "E")}`;
    #|result + ":" + log;
  inspect(bytecode_compare(src), content="value:FE:se")
}

///|
test "bytecode template literal captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = "cap";
    #|  return function() { return `:${x}:`; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value::cap:")
}

///|
test "bytecode tagged template passes template object and substitutions" {
  let src =
    #|function tag(strings, a, b) {
    #|  return strings[0] + "," + strings[1] + "," + strings[2] + ":" + strings.raw[0] + ":" + a + ":" + b;
    #|}
    #|tag`a${1 + 1}b${"x"}c`;
  inspect(bytecode_compare(src), content="value:a,b,c:a:2:x")
}

///|
test "bytecode tagged template evaluates tag before substitutions" {
  let src =
    #|var log = "";
    #|function getTag() {
    #|  log = log + "t";
    #|  return function(strings, value) { return log + ":" + value; };
    #|}
    #|getTag()`a${(log = log + "e", "v")}b`;
  inspect(bytecode_compare(src), content="value:te:v")
}

///|
test "bytecode tagged template captures tag and substitution bindings" {
  let src =
    #|function outer() {
    #|  var x = 3;
    #|  function tag(strings, value) { return value; }
    #|  return function() { return tag`${x}`; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode member tagged template preserves receiver" {
  let src =
    #|var obj = { x: "ok", tag: function(strings) { return this.x + ":" + strings[0]; } };
    #|obj.tag`hello`;
  inspect(bytecode_compare(src), content="value:ok:hello")
}

///|
test "bytecode computed tagged template preserves receiver and evaluation order" {
  let src =
    #|var log = "";
    #|var obj = { x: 2 };
    #|obj.tag = function(strings, value) { return this.x + ":" + log + ":" + strings[0] + strings[1] + ":" + value; };
    #|function getObj() { log = log + "o"; return obj; }
    #|function key() { log = log + "k"; return "tag"; }
    #|getObj()[key()]`a${(log = log + "e", "v")}b`;
  inspect(bytecode_compare(src), content="value:2:oke:ab:v")
}

///|
test "bytecode member tagged template captures receiver bindings" {
  let src =
    #|function outer() {
    #|  var obj = { x: 4, tag: function(strings, value) { return this.x + ":" + value; } };
    #|  return function() { return obj.tag`${1}`; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:4:1")
}

///|
test "bytecode rejects optional member tagged templates until optional tag semantics are shared" {
  let src =
    #|var obj = { tag: function(strings) { return this === obj; } };
    #|obj?.tag`x`;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: tagged template optional member call",
  )
}

///|
test "bytecode regex literal uses runtime regexp semantics" {
  let src =
    #|var r = /a+/;
    #|r.test("caaat") + "," + r.test("bbb");
  inspect(bytecode_compare(src), content="value:true,false")
}

///|
test "bytecode regex literal honors flags" {
  let src =
    #|var r = /a/i;
    #|r.test("A");
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode regex literal creates a fresh object each evaluation" {
  let src =
    #|function make() { return /x/g; }
    #|make() === make();
  inspect(bytecode_compare(src), content="value:false")
}

///|
test "bytecode logical and skips rhs and returns original falsy operand" {
  let src =
    #|var rhs = 0;
    #|var result = 0 && (rhs = 1);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:0,0")
}

///|
test "bytecode logical and evaluates rhs and returns rhs when lhs is truthy" {
  let src =
    #|var rhs = 0;
    #|var result = 2 && (rhs = 5);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:5,5")
}

///|
test "bytecode logical or skips rhs and returns original truthy operand" {
  let src =
    #|var rhs = 0;
    #|var result = "left" || (rhs = 1);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:left,0")
}

///|
test "bytecode logical or evaluates rhs and returns rhs when lhs is falsy" {
  let src =
    #|var rhs = 0;
    #|var result = false || (rhs = 7);
    #|result + "," + rhs;
  inspect(bytecode_compare(src), content="value:7,7")
}

///|
test "bytecode nullish coalescing only skips non-nullish lhs values" {
  let src =
    #|var side = 0;
    #|var a = 0 ?? (side = side + 1);
    #|var b = false ?? (side = side + 10);
    #|var c = "" ?? (side = side + 100);
    #|var d = null ?? (side = side + 1000);
    #|var e = undefined ?? (side = side + 10000);
    #|a + "," + b + "," + c + "," + d + "," + e + "," + side;
  inspect(bytecode_compare(src), content="value:0,false,,1000,11000,11000")
}

///|
test "bytecode ternary uses truthiness and returns selected branch" {
  let src =
    #|var a = 0 ? "bad" : "zero";
    #|var b = "x" ? "string" : "bad";
    #|a + "," + b;
  inspect(bytecode_compare(src), content="value:zero,string")
}

///|
test "bytecode ternary skips unselected branch side effects" {
  let src =
    #|var hits = 0;
    #|var a = true ? (hits = hits + 1) : (hits = hits + 100);
    #|var b = false ? (hits = hits + 1000) : (hits = hits + 10);
    #|a + "," + b + "," + hits;
  inspect(bytecode_compare(src), content="value:1,11,11")
}

///|
test "bytecode ternary expression statement updates completion" {
  let src =
    #|false ? "then" : "else";
  inspect(bytecode_compare(src), content="value:else")
}

///|
test "bytecode unary numeric logical and bitwise operators" {
  let src =
    #|var x = "2";
    #|(-x) + "," + (+true) + "," + (!0) + "," + (~1);
  inspect(bytecode_compare(src), content="value:-2,1,true,-2")
}

///|
test "bytecode void evaluates operand effects and yields undefined" {
  let src =
    #|var x = 0;
    #|var r = void (x = 42);
    #|(r === undefined) + "," + x;
  inspect(bytecode_compare(src), content="value:true,42")
}

///|
test "bytecode unary captured vars use environment fallback" {
  let src =
    #|function outer() {
    #|  var x = 2;
    #|  return function() { return -x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:-2")
}

///|
test "bytecode delete member property removes own object property" {
  let src =
    #|var o = { x: 1, y: 2 };
    #|var r = delete o.x;
    #|r + "," + ("x" in o) + "," + o.x + "," + o.y;
  inspect(bytecode_compare(src), content="value:true,false,undefined,2")
}

///|
test "bytecode delete computed array element creates a hole" {
  let src =
    #|var xs = [1, 2, 3];
    #|var r = delete xs[1];
    #|xs.length + ":" + r + "," + (1 in xs) + "," + xs[1];
  inspect(bytecode_compare(src), content="value:3:true,false,undefined")
}

///|
test "bytecode delete computed property preserves object key order" {
  let src =
    #|var log = "";
    #|var o = { x: 1 };
    #|function obj() { log = log + "o"; return o; }
    #|function key() { log = log + "k"; return "x"; }
    #|var r = delete obj()[key()];
    #|r + ":" + log + ":" + ("x" in o);
  inspect(bytecode_compare(src), content="value:true:ok:false")
}

///|
test "bytecode delete property handles primitive and null receivers like interpreter" {
  inspect(bytecode_compare("var n = 1; delete n.x;"), content="value:true")
  inspect(
    bytecode_compare("var target = null; delete target.x;"),
    content="throw:TypeError: Cannot convert undefined or null to object",
  )
}

///|
test "bytecode delete identifiers uses shared runtime semantics" {
  let src =
    #|function f() { return delete arguments; }
    #|var missing_delete = delete missing;
    #|missing_delete + "," + f();
  inspect(bytecode_compare(src), content="value:true,true")
}

///|
test "bytecode delete var binding matches interpreter global descriptor behavior" {
  let src =
    #|var x = 1;
    #|var r = delete x;
    #|r + "," + x;
  inspect(bytecode_compare(src), content="value:false,1")
}

///|
test "bytecode delete identifiers preserves strict mode SyntaxError" {
  let src =
    #|"use strict";
    #|delete x;
  inspect(
    bytecode_compare(src),
    content="throw:SyntaxError: Delete of an unqualified identifier in strict mode.",
  )
}

///|
test "bytecode rejects non-identifier non-property delete until reference semantics are shared" {
  let src =
    #|var x = 1;
    #|delete (x = 2);
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: delete non-property operator",
  )
}

///|
test "bytecode typeof handles missing and resolved identifiers" {
  let src =
    #|var x = 1;
    #|var f = function() {};
    #|typeof missing + "," + typeof x + "," + typeof f;
  inspect(bytecode_compare(src), content="value:undefined,number,function")
}

///|
test "bytecode typeof reads function local slots" {
  let src =
    #|function f(a) {
    #|  var b = "x";
    #|  return typeof a + "," + typeof b;
    #|}
    #|f(1);
  inspect(bytecode_compare(src), content="value:number,string")
}

///|
test "bytecode typeof evaluates non-identifier operands" {
  let src =
    #|var x = 1;
    #|typeof (x + 1);
  inspect(bytecode_compare(src), content="value:number")
}

///|
test "bytecode typeof keeps lexical TDZ errors" {
  let src =
    #|typeof x;
    #|let x = 1;
  inspect(
    bytecode_compare(src),
    content="throw:ReferenceError: Cannot access 'x' before initialization",
  )
}

///|
test "bytecode typeof captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return typeof x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:number")
}

///|
test "bytecode jumps and branch completion" {
  let src =
    #|var x = 0;
    #|if (1 < 2) {
    #|  x = 3;
    #|} else {
    #|  x = 4;
    #|}
    #|x;
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode do while runs body before checking condition" {
  let src =
    #|var x = 0;
    #|do {
    #|  x = x + 1;
    #|} while (false);
    #|x;
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode do while preserves condition order and repeats" {
  let src =
    #|var x = 0;
    #|var log = "";
    #|do {
    #|  log = log + "b";
    #|  x = x + 1;
    #|} while ((log = log + "c", x < 3));
    #|log + ":" + x;
  inspect(bytecode_compare(src), content="value:bcbcbc:3")
}

///|
test "bytecode do while statement completion comes from body" {
  let src =
    #|do {
    #|  "body";
    #|} while (false);
  inspect(bytecode_compare(src), content="value:body")
}

///|
test "bytecode do while captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = 0;
    #|  return function() {
    #|    do {
    #|      x = x + 1;
    #|    } while (false);
    #|    return x;
    #|  };
    #|}
    #|var f = outer();
    #|f() + "," + f();
  inspect(bytecode_compare(src), content="value:1,2")
}

///|
test "bytecode switch dispatch skips later case tests and falls through" {
  let src =
    #|var log = "";
    #|switch ((log = log + "d", 2)) {
    #|  case (log = log + "a", 1):
    #|    log = log + "A";
    #|    break;
    #|  case (log = log + "b", 2):
    #|    log = log + "B";
    #|  case (log = log + "c", 3):
    #|    log = log + "C";
    #|    break;
    #|  default:
    #|    log = log + "D";
    #|}
    #|log;
  inspect(bytecode_compare(src), content="value:dabBC")
}

///|
test "bytecode switch default evaluates tests then falls through from default" {
  let src =
    #|var log = "";
    #|switch (9) {
    #|  case (log = log + "a", 1):
    #|    log = log + "A";
    #|  default:
    #|    log = log + "D";
    #|  case (log = log + "b", 2):
    #|    log = log + "B";
    #|}
    #|log;
  inspect(bytecode_compare(src), content="value:abDB")
}

///|
test "bytecode switch completion and empty no-match result" {
  inspect(
    bytecode_compare("switch (1) { case 1: 'before'; break; 'after'; }"),
    content="value:before",
  )
  inspect(
    bytecode_compare("switch (3) { case 1: 'one'; }"),
    content="value:undefined",
  )
}

///|
test "bytecode switch break and continue target the right enclosing statement" {
  let src =
    #|var log = "";
    #|for (var i = 0; i < 3; i = i + 1) {
    #|  switch (i) {
    #|    case 0:
    #|      log = log + "a";
    #|      break;
    #|    case 1:
    #|      log = log + "b";
    #|      continue;
    #|    default:
    #|      log = log + "c";
    #|  }
    #|  log = log + "x";
    #|}
    #|log + ":" + i;
  inspect(bytecode_compare(src), content="value:axbcx:3")
}

///|
test "bytecode switch var declarations can be captured" {
  let src =
    #|function outer(flag) {
    #|  switch (flag) {
    #|    case true:
    #|      var x = 4;
    #|      break;
    #|  }
    #|  return function() { return x; };
    #|}
    #|outer(true)() + "," + outer(false)();
  inspect(bytecode_compare(src), content="value:4,undefined")
}

///|
test "bytecode rejects switch lexical and function declarations explicitly" {
  inspect(
    bytecode_outcome("switch (1) { case 1: let x = 1; }"),
    content="error:InternalError: bytecode prototype unsupported: switch lexical declaration",
  )
  inspect(
    bytecode_outcome("switch (1) { case 1: function f() { return 1; } }"),
    content="error:InternalError: bytecode prototype unsupported: control-flow function declaration",
  )
}

///|
test "bytecode break exits while loops" {
  let src =
    #|var i = 0;
    #|while (true) {
    #|  i = i + 1;
    #|  if (i === 3) {
    #|    break;
    #|  }
    #|}
    #|i;
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode break preserves prior loop completion" {
  let src =
    #|while (true) {
    #|  "body";
    #|  break;
    #|  "after";
    #|}
  inspect(bytecode_compare(src), content="value:body")
  let nested =
    #|while (true) {
    #|  "body";
    #|  if (true) break;
    #|}
  inspect(bytecode_compare(nested), content="value:body")
}

///|
test "bytecode continue preserves prior loop completion" {
  let src =
    #|var i = 0;
    #|while (i < 1) {
    #|  i = i + 1;
    #|  "body";
    #|  if (true) continue;
    #|  "after";
    #|}
  inspect(bytecode_compare(src), content="value:body")
}

///|
test "bytecode continue in for loops runs the update expression" {
  let src =
    #|var log = "";
    #|for (var i = 0; i < 3; i = i + 1) {
    #|  log = log + "b" + i;
    #|  continue;
    #|  log = log + "x";
    #|}
    #|log + ":" + i;
  inspect(bytecode_compare(src), content="value:b0b1b2:3")
}

///|
test "bytecode continue in do while loops still evaluates the condition" {
  let src =
    #|var i = 0;
    #|var log = "";
    #|do {
    #|  i = i + 1;
    #|  log = log + "b";
    #|  if (i < 2) {
    #|    continue;
    #|  }
    #|  log = log + "x";
    #|} while ((log = log + "c", i < 3));
    #|log + ":" + i;
  inspect(bytecode_compare(src), content="value:bcbxcbxc:3")
}

///|
test "bytecode labeled statements run unlabeled inner statements" {
  inspect(bytecode_compare("label: { 'inside'; }"), content="value:inside")
  let loop_src =
    #|label: while (true) {
    #|  "body";
    #|  break;
    #|  "after";
    #|}
  inspect(bytecode_compare(loop_src), content="value:body")
}

///|
test "bytecode labeled statements can capture outer bindings" {
  let src =
    #|function outer() {
    #|  var x = 5;
    #|  label: {
    #|    return function() { return x; };
    #|  }
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode labeled break exits labeled blocks" {
  let src =
    #|label: {
    #|  "before";
    #|  break label;
    #|  "after";
    #|}
  inspect(bytecode_compare(src), content="value:before")
}

///|
test "bytecode labeled break exits outer loops" {
  let src =
    #|var log = "";
    #|outer: while (true) {
    #|  log = log + "o";
    #|  while (true) {
    #|    log = log + "i";
    #|    break outer;
    #|  }
    #|  log = log + "x";
    #|}
    #|log;
  inspect(bytecode_compare(src), content="value:oi")
}

///|
test "bytecode labeled continue targets outer loops" {
  let src =
    #|var log = "";
    #|outer: for (var i = 0; i < 3; i = i + 1) {
    #|  log = log + "b" + i;
    #|  for (var j = 0; j < 2; j = j + 1) {
    #|    continue outer;
    #|  }
    #|  log = log + "x";
    #|}
    #|log + ":" + i;
  inspect(bytecode_compare(src), content="value:b0b1b2:3")
}

///|
test "bytecode rejects unresolved labeled breaks and non-loop labeled continues" {
  inspect(
    bytecode_outcome("while (true) { break label; }"),
    content="error:InternalError: bytecode prototype unsupported: labeled break statement",
  )
  inspect(
    bytecode_outcome("label: { continue label; }"),
    content="error:InternalError: bytecode prototype unsupported: labeled continue statement",
  )
}

///|
test "bytecode rejects labeled function declarations until label semantics are implemented" {
  let src =
    #|label: {
    #|  function f() { return 1; }
    #|}
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: control-flow function declaration",
  )
}

///|
test "bytecode calls and return" {
  let src =
    #|function add(a, b) {
    #|  return a + b;
    #|}
    #|add(2, 3);
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode hoists nested function declarations" {
  let src =
    #|(function() {
    #|  return f();
    #|  function f() { return 7; }
    #|})();
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode function declaration identity is stable after hoist" {
  let src =
    #|(function() {
    #|  var a = f;
    #|  function f() { return 1; }
    #|  var b = f;
    #|  return a === b;
    #|})();
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode hoists captured var bindings to undefined" {
  let src =
    #|(function() {
    #|  var f = function() { return x; };
    #|  return f();
    #|  var x = 1;
    #|})();
  inspect(bytecode_compare(src), content="value:undefined")
}

///|
test "bytecode mirrors top-level var initialization to global object" {
  let src =
    #|var x = 1;
    #|globalThis.x;
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode statement completion matches interpreter for declarations and skipped branches" {
  inspect(bytecode_compare("1; var x = 2;"), content="value:undefined")
  inspect(bytecode_compare("1; if (false) { 2; }"), content="value:undefined")
  inspect(
    bytecode_compare("1; while (false) { 2; }"),
    content="value:undefined",
  )
}

///|
test "bytecode sets function names for anonymous assignment targets" {
  let src =
    #|var f = function() {};
    #|f.name;
  inspect(bytecode_compare(src), content="value:f")
}

///|
test "bytecode reuses runtime name assignment semantics" {
  let src =
    #|x = 1;
    #|globalThis.x;
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode member update preserves prefix and postfix results" {
  let src =
    #|var o = { x: 41 };
    #|var post = o.x++;
    #|var pre = ++o.x;
    #|post + "," + pre + "," + o.x;
  inspect(bytecode_compare(src), content="value:41,43,43")
}

///|
test "bytecode computed update canonicalizes key once" {
  let src =
    #|var log = "";
    #|var o = { x: 1 };
    #|var key = { toString: function() { log = log + "k"; return "x"; } };
    #|var post = o[key]++;
    #|post + ":" + o.x + ":" + log;
  inspect(bytecode_compare(src), content="value:1:2:k")
}

///|
test "bytecode member update null receiver throws like interpreter" {
  let src =
    #|var target = null;
    #|target.x++;
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Cannot read properties of null (reading 'x')",
  )
}

///|
test "bytecode computed update captures outer key binding" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function(o) { return ++o[key]; };
    #|}
    #|outer()({ x: 2 });
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode identifier compound assignment reuses binary semantics" {
  let src =
    #|var x = "4";
    #|x += 2;
    #|x;
  inspect(bytecode_compare(src), content="value:42")
}

///|
test "bytecode identifier compound assignment updates local slots" {
  let src =
    #|function f(a) {
    #|  var x = a;
    #|  x *= 3;
    #|  return x;
    #|}
    #|f(4);
  inspect(bytecode_compare(src), content="value:12")
}

///|
test "bytecode logical compound assignment short-circuits identifiers" {
  let src =
    #|var log = "";
    #|function rhs(v) { log = log + v; return v; }
    #|var a = 0;
    #|var b = 1;
    #|a &&= rhs("a");
    #|b &&= rhs("b");
    #|a + "," + b + "," + log;
  inspect(bytecode_compare(src), content="value:0,b,b")
}

///|
test "bytecode nullish and or compound assignment short-circuits identifiers" {
  let src =
    #|var log = "";
    #|function rhs(v) { log = log + v; return v; }
    #|var a = 1;
    #|var b = 0;
    #|var c = null;
    #|var d = "x";
    #|var e = undefined;
    #|a ||= rhs("a");
    #|b ||= rhs("b");
    #|c ??= rhs("c");
    #|d ??= rhs("d");
    #|e ??= rhs("e");
    #|a + "," + b + "," + c + "," + d + "," + e + "," + log;
  inspect(bytecode_compare(src), content="value:1,b,c,x,e,bce")
}

///|
test "bytecode identifier compound assignment captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { x += 2; return x; };
    #|}
    #|var f = outer();
    #|f() + "," + f();
  inspect(bytecode_compare(src), content="value:3,5")
}

///|
test "bytecode identifier compound assignment uses assignment reference reads" {
  let src =
    #|globalThis.x = 1;
    #|x += 2;
  inspect(
    bytecode_compare(src),
    content="throw:ReferenceError: x is not defined",
  )
}

///|
test "bytecode member compound assignment reuses property semantics" {
  let src =
    #|var o = { x: "4" };
    #|o.x += 2;
    #|o.x;
  inspect(bytecode_compare(src), content="value:42")
}

///|
test "bytecode computed compound assignment canonicalizes key once" {
  let src =
    #|var log = "";
    #|var o = { x: 1 };
    #|var key = { toString: function() { log = log + "k"; return "x"; } };
    #|function rhs() { log = log + "r"; return 2; }
    #|o[key] += rhs();
    #|o.x + ":" + log;
  inspect(bytecode_compare(src), content="value:3:kr")
}

///|
test "bytecode member compound assignment null receiver throws like interpreter" {
  let src =
    #|var target = null;
    #|target.x += 1;
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Cannot read properties of null (reading 'x')",
  )
}

///|
test "bytecode computed compound assignment captures outer key binding" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function(o) { o[key] += 2; return o.x; };
    #|}
    #|outer()({ x: 1 });
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode member logical compound assignment preserves short-circuit semantics" {
  let src =
    #|var log = "";
    #|function rhs(v) { log = log + v; return v; }
    #|var o = { a: 0, b: 1, c: null, d: "x", e: undefined };
    #|var r1 = o.a &&= rhs("a");
    #|var r2 = o.b &&= rhs("b");
    #|var r3 = o.a ||= rhs("o");
    #|var r4 = o.d ||= rhs("d");
    #|var r5 = o.c ??= rhs("c");
    #|var r6 = o.e ??= rhs("e");
    #|var r7 = o.d ??= rhs("n");
    #|r1 + "," + r2 + "," + r3 + "," + r4 + "," + r5 + "," + r6 + "," + r7 + "," + log + "," + o.a + "," + o.b + "," + o.c + "," + o.d + "," + o.e;
  inspect(bytecode_compare(src), content="value:0,b,o,x,c,e,x,boce,o,b,c,x,e")
}

///|
test "bytecode computed logical compound assignment canonicalizes key once" {
  let src =
    #|var log = "";
    #|var o = { x: 0 };
    #|var key = { toString: function() { log = log + "k"; return "x"; } };
    #|function rhs() { log = log + "r"; return 2; }
    #|var a = o[key] ||= rhs();
    #|var b = o[key] &&= rhs();
    #|var c = o[key] ??= rhs();
    #|a + "," + b + "," + c + ":" + o.x + ":" + log;
  inspect(bytecode_compare(src), content="value:2,2,2:2:krkrk")
}

///|
test "bytecode member logical compound assignment null receiver throws like interpreter" {
  let src =
    #|var target = null;
    #|target.x ||= 1;
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Cannot read properties of null (reading 'x')",
  )
}

///|
test "bytecode computed logical compound assignment captures outer key binding" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function(o) { o[key] ||= 3; return o.x; };
    #|}
    #|outer()({ x: 0 });
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode rejects invalid compound assignment targets" {
  let src =
    #|var x = 1;
    #|var y = 2;
    #|(x + y) += 1;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: compound assignment target",
  )
}

///|
test "bytecode array literal holes preserve length and absent indices" {
  let src =
    #|var xs = [1,,3];
    #|xs.length + ":" + (0 in xs) + "," + (1 in xs) + "," + (2 in xs) + ":" + xs[1];
  inspect(bytecode_compare(src), content="value:3:true,false,true:undefined")
}

///|
test "bytecode array literal holes skip value evaluation" {
  let src =
    #|var log = "";
    #|function side(x) { log = log + x; return x; }
    #|var xs = [side("a"),,side("b")];
    #|log + ":" + xs.length + ":" + (1 in xs);
  inspect(bytecode_compare(src), content="value:ab:3:false")
}

///|
test "bytecode array literal holes fall through to prototypes" {
  let src =
    #|Array.prototype[1] = "proto";
    #|var xs = [0,,2];
    #|xs[1] + "," + (1 in xs);
  inspect(bytecode_compare(src), content="value:proto,true")
}

///|
test "bytecode array spread elements expand arrays and strings" {
  let src =
    #|var xs = [0, ...[1, 2], ..."ab"];
    #|xs.length + ":" + xs[0] + "," + xs[1] + "," + xs[2] + "," + xs[3] + xs[4];
  inspect(bytecode_compare(src), content="value:5:0,1,2,ab")
}

///|
test "bytecode array spread exhausts iterators before later elements" {
  let src =
    #|var log = "";
    #|var iterable = {};
    #|iterable[Symbol.iterator] = function() {
    #|  var done = false;
    #|  return {
    #|    next: function() {
    #|      if (done) {
    #|        return { done: true };
    #|      }
    #|      done = true;
    #|      log = log + "n";
    #|      return { value: 1, done: false };
    #|    }
    #|  };
    #|};
    #|var xs = [...iterable, (log = log + "e", 2)];
    #|log + ":" + xs[0] + "," + xs[1];
  inspect(bytecode_compare(src), content="value:ne:1,2")
}

///|
test "bytecode array spread preserves surrounding holes" {
  let src =
    #|var xs = [0,,...[2]];
    #|xs.length + ":" + (1 in xs) + "," + xs[1] + "," + xs[2];
  inspect(bytecode_compare(src), content="value:3:false,undefined,2")
}

///|
test "bytecode array spread captures outer bindings" {
  let src =
    #|function outer() {
    #|  var xs = [1, 2];
    #|  return function() {
    #|    var ys = [0, ...xs];
    #|    return ys[2];
    #|  };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode spread call arguments expand arrays and strings" {
  let src =
    #|function join(a, b, c, d, e) {
    #|  return a + ":" + b + ":" + c + ":" + d + e;
    #|}
    #|join("x", ...[1, 2], ..."ab");
  inspect(bytecode_compare(src), content="value:x:1:2:ab")
}

///|
test "bytecode spread call arguments exhaust iterators before later args" {
  let src =
    #|var log = "";
    #|var iterable = {};
    #|iterable[Symbol.iterator] = function() {
    #|  var done = false;
    #|  return {
    #|    next: function() {
    #|      if (done) {
    #|        return { done: true };
    #|      }
    #|      done = true;
    #|      log = log + "n";
    #|      return { value: 1, done: false };
    #|    }
    #|  };
    #|};
    #|function pair(a, b) { return log + ":" + a + "," + b; }
    #|pair(...iterable, (log = log + "e", 2));
  inspect(bytecode_compare(src), content="value:ne:1,2")
}

///|
test "bytecode spread method call preserves receiver" {
  let src =
    #|var obj = { x: 4, get: function(a, b) { return this.x + a + b; } };
    #|obj.get(...[1, 2]);
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode optional spread call skips arguments for nullish callees" {
  let src =
    #|var hit = 0;
    #|var fn = null;
    #|var result = fn?.(...(hit = 1, [2]));
    #|(result === undefined) + "," + hit;
  inspect(bytecode_compare(src), content="value:true,0")
}

///|
test "bytecode spread call arguments capture outer iterables" {
  let src =
    #|function outer() {
    #|  var xs = [2, 3];
    #|  return function(fn) { return fn(1, ...xs); };
    #|}
    #|outer()(function(a, b, c) { return a + b + c; });
  inspect(bytecode_compare(src), content="value:6")
}

///|
test "bytecode spread call arguments reuse runtime iterable errors" {
  let src =
    #|function f() {}
    #|f(...1);
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: number is not iterable",
  )
}

///|
test "bytecode resolves computed callees before arguments" {
  let src =
    #|var fns = [
    #|  function() { return "old"; },
    #|  function() { return "new"; }
    #|];
    #|function arg() {
    #|  fns.shift();
    #|  return 0;
    #|}
    #|fns[0](arg());
  inspect(bytecode_compare(src), content="value:old")
}

///|
test "bytecode optional member access reads present receivers and short-circuits nullish receivers" {
  let src =
    #|var present = { x: 3 };
    #|var missing = null;
    #|var a = present?.x;
    #|var b = missing?.x;
    #|a + "," + (b === undefined);
  inspect(bytecode_compare(src), content="value:3,true")
}

///|
test "bytecode optional computed member skips key evaluation for nullish receivers" {
  let src =
    #|var log = "";
    #|var base = null;
    #|var value = base?.[(log = "k", "x")];
    #|(value === undefined) + ":" + log;
  inspect(bytecode_compare(src), content="value:true:")
}

///|
test "bytecode optional call skips arguments for nullish callees" {
  let src =
    #|var hit = 0;
    #|var fn = null;
    #|var result = fn?.(hit = 1);
    #|(result === undefined) + "," + hit;
  inspect(bytecode_compare(src), content="value:true,0")
}

///|
test "bytecode optional method call preserves receivers and skips nullish functions" {
  let src =
    #|var obj = [];
    #|obj.x = 4;
    #|obj.get = function() { return this.x; };
    #|var a = obj.get?.();
    #|var hit = 0;
    #|var b = obj.missing?.(hit = 1);
    #|a + "," + (b === undefined) + "," + hit;
  inspect(bytecode_compare(src), content="value:4,true,0")
}

///|
test "bytecode optional member calls skip property and arguments for nullish receivers" {
  let src =
    #|var hit = 0;
    #|var obj = null;
    #|var result = obj?.get(hit = 1);
    #|(result === undefined) + "," + hit;
  inspect(bytecode_compare(src), content="value:true,0")
}

///|
test "bytecode optional chaining captures outer receiver bindings" {
  let src =
    #|function outer() {
    #|  var obj = { x: 5 };
    #|  return function() { return obj?.x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode member assignment writes through runtime property semantics" {
  let src =
    #|var xs = [];
    #|xs.label = 3;
    #|xs.label = xs.label + 4;
    #|xs.label;
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode computed assignment preserves object key value order" {
  let src =
    #|var log = "";
    #|var xs = [];
    #|function obj() { log = log + "o"; return xs; }
    #|function key() { log = log + "k"; return 0; }
    #|function val() { log = log + "v"; return 9; }
    #|obj()[key()] = val();
    #|log + ":" + xs[0];
  inspect(bytecode_compare(src), content="value:okv:9")
}

///|
test "bytecode member assignment null receiver throws like interpreter" {
  let src =
    #|var target = null;
    #|target.x = 1;
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Cannot set properties of null (setting 'x')",
  )
}

///|
test "bytecode computed assignment captures outer key binding" {
  let src =
    #|function outer() {
    #|  var key = 0;
    #|  return function(xs) {
    #|    xs[key] = 5;
    #|    return xs[0];
    #|  };
    #|}
    #|outer()([]);
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode object literal evaluates static data properties" {
  let src =
    #|var o = { a: 1, b: 2 };
    #|o.a + o.b;
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode object literal preserves value evaluation order" {
  let src =
    #|var log = "";
    #|function side(x) { log = log + x; return x; }
    #|var o = { a: side("a"), b: side("b") };
    #|log + ":" + o.a + o.b;
  inspect(bytecode_compare(src), content="value:ab:ab")
}

///|
test "bytecode object literal uses the runtime object prototype" {
  let src =
    #|"toString" in {};
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode object literal sets anonymous function property names" {
  let src =
    #|var o = { f: function() {} };
    #|o.f.name;
  inspect(bytecode_compare(src), content="value:f")
}

///|
test "bytecode object literal captures outer bindings" {
  let src =
    #|function outer() {
    #|  var x = 7;
    #|  return function() { return { value: x }.value; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode object literal methods preserve receiver and names" {
  let src =
    #|var o = {
    #|  x: 4,
    #|  m() { return this.x + ":" + this.m.name; }
    #|};
    #|o.m();
  inspect(bytecode_compare(src), content="value:4:m")
}

///|
test "bytecode object literal methods capture outer bindings" {
  let src =
    #|function outer() {
    #|  var x = 5;
    #|  return { m() { return x + 1; } };
    #|}
    #|outer().m();
  inspect(bytecode_compare(src), content="value:6")
}

///|
test "bytecode object literal methods do not expose prototype properties" {
  let src =
    #|var o = { m() { return 1; } };
    #|("prototype" in o.m) + "," + typeof o.m;
  inspect(bytecode_compare(src), content="value:false,function")
}

///|
test "bytecode object literal computed methods preserve receiver and inferred names" {
  let src =
    #|var key = "m";
    #|var o = {
    #|  x: 4,
    #|  [key]() { return this.x + ":" + this.m.name; }
    #|};
    #|o.m();
  inspect(bytecode_compare(src), content="value:4:m")
}

///|
test "bytecode object literal computed methods canonicalize keys before later values" {
  let src =
    #|var log = "";
    #|var key = { toString: function() { log = log + "k"; return "m"; } };
    #|var o = {
    #|  [key]() { return log; },
    #|  after: (log = log + "v", 0)
    #|};
    #|o.m() + ":" + log;
  inspect(bytecode_compare(src), content="value:kv:kv")
}

///|
test "bytecode object literal computed symbol methods" {
  let src =
    #|var sym = Symbol("m");
    #|var o = { [sym]() { return this === o; } };
    #|o[sym].name + ":" + o[sym]();
  inspect(bytecode_compare(src), content="value:[m]:true")
}

///|
test "bytecode object literal static accessors use descriptors and receivers" {
  let src =
    #|var log = "";
    #|var o = {
    #|  value: 1,
    #|  get x() { log = log + "g"; return this.value + 1; },
    #|  set x(v) { log = log + "s" + v; this.value = v; }
    #|};
    #|var desc = Object.getOwnPropertyDescriptor(o, "x");
    #|var read = o.x;
    #|o.x = 5;
    #|read + ":" + desc.get.name + "," + desc.set.name + ":" + o.value + ":" + log;
  inspect(bytecode_compare(src), content="value:2:get x,set x:5:gs5")
}

///|
test "bytecode object literal static accessors capture outer bindings" {
  let src =
    #|function outer() {
    #|  var value = 3;
    #|  return {
    #|    get x() { return value; },
    #|    set x(next) { value = next; }
    #|  };
    #|}
    #|var o = outer();
    #|var before = o.x;
    #|o.x = 7;
    #|before + "," + o.x;
  inspect(bytecode_compare(src), content="value:3,7")
}

///|
test "bytecode object literal computed accessors use descriptors receivers and key order" {
  let src =
    #|var log = "";
    #|var key = { toString: function() { log = log + "k"; return "x"; } };
    #|var o = {
    #|  value: 1,
    #|  get [key]() { log = log + "g"; return this.value + 2; },
    #|  set [key](v) { log = log + "s" + v; this.value = v; },
    #|  after: (log = log + "a", 0)
    #|};
    #|var desc = Object.getOwnPropertyDescriptor(o, "x");
    #|var read = o.x;
    #|o.x = 6;
    #|read + ":" + desc.get.name + "," + desc.set.name + ":" + o.value + ":" + log;
  inspect(bytecode_compare(src), content="value:3:get x,set x:6:kkags6")
}

///|
test "bytecode object literal computed accessors capture keys and bodies" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  var value = 3;
    #|  return {
    #|    get [key]() { return value; },
    #|    set [key](next) { value = next; }
    #|  };
    #|}
    #|var o = outer();
    #|var before = o.x;
    #|o.x = 9;
    #|before + "," + o.x;
  inspect(bytecode_compare(src), content="value:3,9")
}

///|
test "bytecode object methods read super properties" {
  let src =
    #|var proto = { x: 3 };
    #|var o = { __proto__: proto, own: 4, m() { return super.x + this.own; } };
    #|o.m();
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode object methods call super methods with the current receiver" {
  let src =
    #|var proto = { getX: function() { return this.x + ":" + this.flag; } };
    #|var o = { __proto__: proto, x: 5, flag: "ok", m() { return super.getX(); } };
    #|o.m();
  inspect(bytecode_compare(src), content="value:5:ok")
}

///|
test "bytecode object methods call computed super methods in order" {
  let src =
    #|var log = "";
    #|var proto = { f: function(v) { return this.x + ":" + v + ":" + log; } };
    #|var o = { __proto__: proto, x: 2, m() { return super[(log = log + "k", "f")]((log = log + "a", "v")); } };
    #|o.m();
  inspect(bytecode_compare(src), content="value:2:v:ka")
}

///|
test "bytecode object methods capture super computed keys" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  var proto = { x: 9 };
    #|  return { __proto__: proto, m() { return super[key]; } };
    #|}
    #|outer().m();
  inspect(bytecode_compare(src), content="value:9")
}

///|
test "bytecode rejects __proto__ methods until object method semantics are settled" {
  inspect(
    bytecode_outcome("({ __proto__() { return 7; } });"),
    content="error:InternalError: bytecode prototype unsupported: object literal __proto__ method property",
  )
}

///|
test "bytecode object spread copies enumerable own properties in order" {
  let src =
    #|var a = { x: 1, y: 2 };
    #|var b = { y: 20, z: 30 };
    #|var o = { first: 0, ...a, y: 3, ...b };
    #|o.first + ":" + o.x + "," + o.y + "," + o.z;
  inspect(bytecode_compare(src), content="value:0:1,20,30")
}

///|
test "bytecode object spread skips non-enumerable properties and invokes getters" {
  let src =
    #|var log = "";
    #|var source = { a: 1 };
    #|Object.defineProperty(source, "hidden", { value: 2, enumerable: false });
    #|Object.defineProperty(source, "x", {
    #|  get: function() { log = log + "g"; return 4; },
    #|  enumerable: true
    #|});
    #|var o = { before: (log = log + "b", 0), ...source, after: log };
    #|o.a + "," + o.x + "," + ("hidden" in o) + "," + o.after + "," + log;
  inspect(bytecode_compare(src), content="value:1,4,false,bg,bg")
}

///|
test "bytecode object spread handles nullish and primitive sources" {
  let src =
    #|var o = { ...null, ...undefined, ...1, ...true, ..."ab" };
    #|o[0] + o[1] + "," + ("x" in o);
  inspect(bytecode_compare(src), content="value:ab,false")
}

///|
test "bytecode object spread captures outer source bindings" {
  let src =
    #|function outer() {
    #|  var source = { x: 7 };
    #|  return function() { return ({ ...source }).x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode object literal __proto__ sets object and null prototypes" {
  let src =
    #|var proto = { inherited: 4 };
    #|var a = { __proto__: proto, own: 1 };
    #|var b = { __proto__: null, own: 2 };
    #|(Object.getPrototypeOf(a) === proto) + "," + a.inherited + "," + a.own + "," + (Object.getPrototypeOf(b) === null) + "," + ("toString" in b);
  inspect(bytecode_compare(src), content="value:true,4,1,true,false")
}

///|
test "bytecode object literal primitive __proto__ remains a data property" {
  let src =
    #|var o = { __proto__: 1, x: 2 };
    #|(Object.getPrototypeOf(o) === Object.prototype) + "," + o.__proto__ + "," + o.x;
  inspect(bytecode_compare(src), content="value:true,1,2")
}

///|
test "bytecode object literal __proto__ works with spread and captures" {
  let src =
    #|function outer() {
    #|  var proto = { p: 5 };
    #|  return function() {
    #|    var o = { before: 1, ...{ x: 2 }, __proto__: proto, after: 3 };
    #|    return (Object.getPrototypeOf(o) === proto) + "," + o.p + "," + o.x + "," + o.after;
    #|  };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:true,5,2,3")
}

///|
test "bytecode object literal computed properties define data properties" {
  let src =
    #|var key = "x";
    #|var o = { [key]: 4, y: 5 };
    #|o.x + "," + o.y;
  inspect(bytecode_compare(src), content="value:4,5")
}

///|
test "bytecode object literal computed keys canonicalize before values" {
  let src =
    #|var log = "";
    #|var key = { toString: function() { log = log + "k"; return "x"; } };
    #|function val() { log = log + "v"; return 7; }
    #|var o = { [key]: val() };
    #|log + ":" + o.x;
  inspect(bytecode_compare(src), content="value:kv:7")
}

///|
test "bytecode object literal computed symbol keys" {
  let src =
    #|var sym = Symbol("s");
    #|var o = { [sym]: 9 };
    #|o[sym];
  inspect(bytecode_compare(src), content="value:9")
}

///|
test "bytecode object literal computed __proto__ remains data property" {
  let src =
    #|var proto = { p: 1 };
    #|var o = { ["__proto__"]: proto, x: 2 };
    #|(Object.getPrototypeOf(o) === Object.prototype) + "," + (o.__proto__ === proto) + "," + o.x;
  inspect(bytecode_compare(src), content="value:true,true,2")
}

///|
test "bytecode object literal computed properties capture outer keys" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function() { return ({ [key]: 6 }).x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:6")
}

///|
test "bytecode rejects unsupported object literal forms explicitly" {
  inspect(
    bytecode_outcome("({ m() { return m; } });"),
    content="error:InternalError: bytecode prototype unsupported: object literal method self reference",
  )
  inspect(
    bytecode_outcome("({ async m() { return 1; } });"),
    content="error:InternalError: bytecode prototype unsupported: object literal method property",
  )
}

///|
test "bytecode new expression constructs bytecode functions" {
  let src =
    #|function C(x) {
    #|  this.x = x;
    #|}
    #|var o = new C(4);
    #|o.x + "," + (o.constructor === C);
  inspect(bytecode_compare(src), content="value:4,true")
}

///|
test "bytecode new expression ignores primitive constructor return" {
  let src =
    #|function C() {
    #|  this.x = 1;
    #|  return 9;
    #|}
    #|new C().x;
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode new expression preserves object constructor return" {
  let src =
    #|function C() {
    #|  return [1, 2, 3];
    #|}
    #|var o = new C();
    #|o.length + "," + o[1];
  inspect(bytecode_compare(src), content="value:3,2")
}

///|
test "bytecode new expression reuses builtin constructor semantics" {
  let src =
    #|var xs = new Array(2);
    #|xs.length;
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode new expression captures outer constructor binding" {
  let src =
    #|function outer() {
    #|  var C = function() { this.x = 5; };
    #|  return function() { return new C().x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode spread new expression constructs with expanded arguments" {
  let src =
    #|function C(a, b) { this.sum = a + b; }
    #|new C(...[2, 3]).sum;
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode top-level this resolves global object" {
  let src =
    #|this === globalThis;
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode this uses call receiver and sloppy global fallback" {
  let src =
    #|var obj = [];
    #|obj.x = 4;
    #|obj.get = function() { return this.x; };
    #|function plain() { return this === globalThis; }
    #|obj.get() + "," + plain();
  inspect(bytecode_compare(src), content="value:4,true")
}

///|
test "bytecode strict function call keeps undefined this" {
  let src =
    #|function strictThis() {
    #|  "use strict";
    #|  return this === undefined;
    #|}
    #|strictThis();
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode new.target sees constructor calls" {
  let src =
    #|function C() {
    #|  this.isCtor = new.target === C;
    #|}
    #|new C().isCtor;
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode new.target is undefined in ordinary calls" {
  let src =
    #|function f() {
    #|  return new.target === undefined;
    #|}
    #|f();
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode new.target respects Reflect.construct newTarget" {
  let src =
    #|function F() {
    #|  return new.target;
    #|}
    #|function G() {}
    #|Reflect.construct(F, [], G) === G;
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode named function expressions bind self name inside function only" {
  let src =
    #|var f = function g(n) {
    #|  if (n === 0) {
    #|    return g;
    #|  }
    #|  return g(n - 1);
    #|};
    #|var outside = typeof g;
    #|(f(2) === f) + "," + outside + "," + f.name;
  inspect(bytecode_compare(src), content="value:true,undefined,g")
}

///|
test "bytecode named function expressions do not overwrite outer bindings" {
  let src =
    #|var g = "outer";
    #|var f = function g() { g = "inner"; return g; };
    #|f() + "," + g;
  inspect(bytecode_compare(src), content="value:inner,outer")
}

///|
test "bytecode nested closures capture named function expression self binding" {
  let src =
    #|var f = function g() {
    #|  return function() { return g === f; };
    #|};
    #|f()();
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode arrow functions capture lexical bindings" {
  let src =
    #|function outer(a) {
    #|  var b = a + 1;
    #|  return () => b + 1;
    #|}
    #|outer(2)();
  inspect(bytecode_compare(src), content="value:4")
}

///|
test "bytecode arrow functions preserve lexical this" {
  let src =
    #|var obj = {
    #|  x: 5,
    #|  make: function() { return () => this.x; }
    #|};
    #|var f = obj.make();
    #|f();
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode arrow functions preserve lexical new.target" {
  let src =
    #|function C() {
    #|  var f = () => new.target === C;
    #|  this.ok = f();
    #|}
    #|var top = () => new.target === undefined;
    #|new C().ok + "," + top();
  inspect(bytecode_compare(src), content="value:true,true")
}

///|
test "bytecode arrow function names are inferred from bindings" {
  let src =
    #|var f = () => 1;
    #|f.name + ":" + f();
  inspect(bytecode_compare(src), content="value:f:1")
}

///|
test "bytecode rest arrow functions collect trailing arguments" {
  let src =
    #|var f = (first, ...rest) => first + ":" + rest.length + ":" + rest[0] + ":" + rest[1];
    #|f(1, 2, 3);
  inspect(bytecode_compare(src), content="value:1:2:2:3")
}

///|
test "bytecode rest arrow functions preserve lexical arguments" {
  let src =
    #|function outer(a) {
    #|  return (...rest) => arguments[0] + ":" + rest.length;
    #|}
    #|outer("outer")(1, 2);
  inspect(bytecode_compare(src), content="value:outer:2")
}

///|
test "bytecode rest arrow parameters can shadow arguments" {
  let src =
    #|((...arguments) => arguments.length + ":" + arguments[1])(4, 5);
  inspect(bytecode_compare(src), content="value:2:5")
}

///|
test "bytecode rest arrow functions capture rest bindings" {
  let src =
    #|var make = (...xs) => function() { return xs[1]; };
    #|make(4, 5)();
  inspect(bytecode_compare(src), content="value:5")
}

///|
test "bytecode rejects unsupported arrow parameter forms explicitly" {
  inspect(
    bytecode_outcome("((x = 1) => x)();"),
    content="error:InternalError: bytecode prototype unsupported: default or destructuring parameter",
  )
  inspect(
    bytecode_outcome("(({ x }) => x)({ x: 1 });"),
    content="error:InternalError: bytecode prototype unsupported: default or destructuring parameter",
  )
}

///|
test "bytecode rejects non-arrow rest parameters until compiled binding semantics are shared" {
  inspect(
    bytecode_outcome("(function(...xs) { return xs.length; })(1);"),
    content="error:InternalError: bytecode prototype unsupported: rest parameter",
  )
}

///|
test "bytecode arguments object exposes call arguments" {
  let src =
    #|function f() {
    #|  return arguments.length + ":" + arguments[0] + "," + arguments[1];
    #|}
    #|f("a", "b");
  inspect(bytecode_compare(src), content="value:2:a,b")
}

///|
test "bytecode arguments object stays mapped to simple parameters" {
  let src =
    #|function f(a) {
    #|  arguments[0] = 5;
    #|  a = a + 1;
    #|  return arguments[0] + "," + a;
    #|}
    #|f(1);
  inspect(bytecode_compare(src), content="value:6,6")
}

///|
test "bytecode arrow functions capture outer arguments object" {
  let src =
    #|function outer(a) {
    #|  var read = () => arguments[0];
    #|  a = 4;
    #|  return read();
    #|}
    #|outer(1);
  inspect(bytecode_compare(src), content="value:4")
}

///|
test "bytecode arguments parameter shadows arguments object" {
  let src =
    #|function f(arguments) {
    #|  return arguments;
    #|}
    #|f(7);
  inspect(bytecode_compare(src), content="value:7")
}

///|
test "bytecode var arguments declaration preserves arguments object without initializer" {
  let src =
    #|function f() {
    #|  var before = arguments.length;
    #|  var arguments;
    #|  return before + ":" + arguments.length;
    #|}
    #|f(1, 2);
  inspect(bytecode_compare(src), content="value:2:2")
}

///|
test "bytecode arguments callee points at the compiled function" {
  let src =
    #|function f(n) {
    #|  if (n === 0) {
    #|    return "done";
    #|  }
    #|  return arguments.callee(n - 1);
    #|}
    #|f(2);
  inspect(bytecode_compare(src), content="value:done")
}

///|
test "bytecode array destructuring assignment swaps identifiers" {
  let src =
    #|var a = 1;
    #|var b = 2;
    #|[a, b] = [b, a];
    #|a + "," + b;
  inspect(bytecode_compare(src), content="value:2,1")
}

///|
test "bytecode object destructuring assignment handles rest properties" {
  let src =
    #|var a = 0;
    #|var rest;
    #|({ x: a, ...rest } = { x: 3, y: 4 });
    #|a + ":" + rest.y + "," + ("x" in rest);
  inspect(bytecode_compare(src), content="value:3:4,false")
}

///|
test "bytecode destructuring assignment updates function bindings" {
  let src =
    #|function f() {
    #|  var x = 0;
    #|  [x] = [3];
    #|  return x;
    #|}
    #|f();
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode destructuring assignment captures outer targets" {
  let src =
    #|function outer() {
    #|  var x = 0;
    #|  return function() {
    #|    [x] = [x + 1];
    #|    return x;
    #|  };
    #|}
    #|var f = outer();
    #|f() + "," + f();
  inspect(bytecode_compare(src), content="value:1,2")
}

///|
test "bytecode rejects destructuring assignment defaults until pattern expressions are compiled" {
  let src =
    #|var x = 0;
    #|[x = 1] = [undefined];
    #|x;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: destructuring assignment pattern",
  )
}

///|
test "bytecode var destructuring declarations bind identifiers" {
  let src =
    #|var [a,,b] = [1, 2, 3];
    #|var { x: c, ...rest } = { x: 4, y: 5 };
    #|a + "," + b + "," + c + ":" + rest.y + "," + ("x" in rest);
  inspect(bytecode_compare(src), content="value:1,3,4:5,false")
}

///|
test "bytecode var destructuring declarations update function bindings" {
  let src =
    #|function f(a) {
    #|  var [a] = [3];
    #|  return a;
    #|}
    #|f(1);
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode var destructuring declarations can be captured" {
  let src =
    #|function outer() {
    #|  var [x] = [4];
    #|  return function() { return x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:4")
}

///|
test "bytecode rejects unsupported destructuring declaration contexts and kinds" {
  let control_flow =
    #|if (true) {
    #|  var [x] = [1];
    #|}
  inspect(
    bytecode_outcome(control_flow),
    content="error:InternalError: bytecode prototype unsupported: destructuring declaration context",
  )
  inspect(
    bytecode_outcome("let [x] = [1];"),
    content="error:InternalError: bytecode prototype unsupported: destructuring declaration kind",
  )
}

///|
test "bytecode rejects var destructuring declaration defaults until pattern expressions are compiled" {
  let src =
    #|var [x = 1] = [undefined];
    #|x;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: destructuring assignment pattern",
  )
}

///|
test "bytecode console log writes through shared host output helper" {
  let src =
    #|console.log(1, "two");
    #|console.log(true);
  inspect(
    bytecode_compare_with_output(src),
    content="value:undefined; output:1 two|true",
  )
}

///|
test "bytecode console member expression returns callable log function" {
  let src =
    #|var log = console.log;
    #|log("saved");
    #|"done";
  inspect(bytecode_compare_with_output(src), content="value:done; output:saved")
}

///|
test "bytecode console member errors like interpreter for unsupported methods" {
  let src =
    #|console.warn(1);
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: console.warn is not supported",
  )
}

///|
test "bytecode leaves captured vars in environment fallback" {
  let src =
    #|function outer(a) {
    #|  var b = a;
    #|  return function() { return b; };
    #|}
    #|outer(1)();
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode closure captures parent binding" {
  let src =
    #|function makeCounter(start) {
    #|  var count = start;
    #|  return function() {
    #|    count = count + 1;
    #|    return count;
    #|  };
    #|}
    #|var counter = makeCounter(2);
    #|counter();
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode hoists function body lexical bindings before execution" {
  let src =
    #|var x = 2;
    #|function f() {
    #|  return x;
    #|  let x = 1;
    #|}
    #|f();
  inspect(
    bytecode_compare(src),
    content="throw:ReferenceError: Cannot access 'x' before initialization",
  )
}

///|
test "bytecode rejects direct eval until caller-env semantics are implemented" {
  let src =
    #|var x = 1;
    #|eval("x = 2");
    #|x;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: direct eval call",
  )
}

///|
test "bytecode block var declarations bind in the outer scope" {
  let src =
    #|var x = 1;
    #|{
    #|  var x = 2;
    #|}
    #|x;
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode block var declarations use function-local slots" {
  let src =
    #|function f() {
    #|  {
    #|    var x = 3;
    #|  }
    #|  return x;
    #|}
    #|f();
  inspect(bytecode_compare(src), content="value:3")
}

///|
test "bytecode block var declaration completion matches interpreter" {
  inspect(bytecode_compare("{ var x = 1; }"), content="value:undefined")
  inspect(bytecode_compare("{ var x = 1; 'done'; }"), content="value:done")
  inspect(bytecode_compare("{ 'before'; var x = 1; }"), content="value:before")
}

///|
test "bytecode block var declarations can be captured" {
  let src =
    #|function outer() {
    #|  {
    #|    var x = 4;
    #|  }
    #|  return function() { return x; };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:4")
}

///|
test "bytecode rejects block lexical declarations until block envs are implemented" {
  let src =
    #|var x = 1;
    #|{
    #|  let x = 2;
    #|}
    #|x;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: block lexical declaration",
  )
}

///|
test "bytecode rejects for lexical initializers until loop scoping is implemented" {
  let src =
    #|for (let i = 0; i < 1; i = i + 1) {
    #|}
    #|i;
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: for lexical initializer",
  )
}

///|
test "bytecode control-flow var declarations preserve prior completion" {
  let src =
    #|if (true) {
    #|  1;
    #|  var x = 2;
    #|}
  inspect(bytecode_compare(src), content="value:1")
}

///|
test "bytecode control-flow var declarations are hoisted when skipped" {
  let src =
    #|var before = typeof x;
    #|if (false) {
    #|  var x = 2;
    #|}
    #|before + "," + x;
  inspect(bytecode_compare(src), content="value:undefined,undefined")
}

///|
test "bytecode loop var declarations use function-local slots" {
  let src =
    #|function f() {
    #|  var i = 0;
    #|  while (i < 3) {
    #|    var x = i;
    #|    i = i + 1;
    #|  }
    #|  return x;
    #|}
    #|f();
  inspect(bytecode_compare(src), content="value:2")
}

///|
test "bytecode control-flow var declarations can be captured" {
  let src =
    #|function outer(flag) {
    #|  if (flag) {
    #|    var x = 4;
    #|  }
    #|  return function() { return x; };
    #|}
    #|outer(true)() + "," + outer(false)();
  inspect(bytecode_compare(src), content="value:4,undefined")
}

///|
test "bytecode rejects control-flow function declarations until block semantics are implemented" {
  let src =
    #|if (true) {
    #|  function f() { return 1; }
    #|}
    #|f();
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: control-flow function declaration",
  )
}

///|
test "bytecode for-in assignment iterates enumerable keys" {
  let src =
    #|var obj = { a: 1, b: 2 };
    #|var k = "";
    #|var out = "";
    #|for (k in obj) {
    #|  out = out + k + obj[k];
    #|}
    #|out + ":" + k;
  inspect(bytecode_compare(src), content="value:a1b2:b")
}

///|
test "bytecode for-in assignment reuses runtime key enumeration" {
  let src =
    #|var proto = { p: 3 };
    #|var obj = { a: 1 };
    #|Object.defineProperty(obj, "hidden", { value: 2, enumerable: false });
    #|Object.setPrototypeOf(obj, proto);
    #|var k;
    #|var out = "";
    #|for (k in obj) {
    #|  out = out + k;
    #|}
    #|out;
  inspect(bytecode_compare(src), content="value:ap")
}

///|
test "bytecode for-in assignment supports break continue and completion" {
  let src =
    #|var obj = { a: 1, b: 2, c: 3 };
    #|var k;
    #|var out = "";
    #|for (k in obj) {
    #|  out = out + k;
    #|  if (k === "a") continue;
    #|  "body";
    #|  if (k === "b") break;
    #|  out = out + "x";
    #|}
  inspect(bytecode_compare(src), content="value:body")
}

///|
test "bytecode for-in assignment captures outer target and object" {
  let src =
    #|function outer() {
    #|  var obj = { a: 1 };
    #|  var k = "";
    #|  return function() {
    #|    for (k in obj) {}
    #|    return k;
    #|  };
    #|}
    #|outer()();
  inspect(bytecode_compare(src), content="value:a")
}

///|
test "bytecode for-in member assignment writes each key through property assignment" {
  let src =
    #|var target = { last: "" };
    #|for (target.last in { a: 1, b: 2 }) {
    #|}
    #|target.last;
  inspect(bytecode_compare(src), content="value:b")
}

///|
test "bytecode for-in computed assignment preserves target evaluation order" {
  let src =
    #|var log = "";
    #|var target = {};
    #|function getTarget() { log = log + "t"; return target; }
    #|function getKey() { log = log + "k"; return "slot"; }
    #|for (getTarget()[getKey()] in { a: 1, b: 2 }) {
    #|  log = log + target.slot;
    #|}
    #|log + ":" + target.slot;
  inspect(bytecode_compare(src), content="value:tkatkb:b")
}

///|
test "bytecode for-in computed assignment captures outer target and key" {
  let src =
    #|function outer() {
    #|  var target = {};
    #|  var key = "slot";
    #|  return function(src) {
    #|    for (target[key] in src) {}
    #|    return target.slot;
    #|  };
    #|}
    #|outer()({ x: 1 });
  inspect(bytecode_compare(src), content="value:x")
}

///|
test "bytecode for-in destructuring assignment targets receive keys" {
  let src =
    #|var first = "";
    #|var second = "";
    #|for ([first, second] in { ab: 1, cd: 2 }) {
    #|}
    #|first + second;
  inspect(bytecode_compare(src), content="value:cd")
}

///|
test "bytecode for-in destructuring assignment supports loop control completion" {
  let src =
    #|var first = "";
    #|for ([first] in { ab: 1, cd: 2 }) {
    #|  "body";
    #|  break;
    #|}
  inspect(bytecode_compare(src), content="value:body")
}

///|
test "bytecode for-in destructuring assignment captures outer targets" {
  let src =
    #|function outer() {
    #|  var first = "";
    #|  return function(src) {
    #|    for ([first] in src) {}
    #|    return first;
    #|  };
    #|}
    #|outer()({ xy: 1 });
  inspect(bytecode_compare(src), content="value:x")
}

///|
test "bytecode rejects unsupported for-in destructuring assignment patterns" {
  let src =
    #|var x = 0;
    #|for ([x = 1] in { a: 1 }) {
    #|}
  inspect(
    bytecode_outcome(src),
    content="error:InternalError: bytecode prototype unsupported: destructuring assignment pattern",
  )
}

///|
test "bytecode rejects for-in declarations until loop binding semantics are shared" {
  inspect(
    bytecode_outcome("for (var k in { a: 1 }) {}"),
    content="error:InternalError: bytecode prototype unsupported: for-in var declaration",
  )
  inspect(
    bytecode_outcome("for (var [k] in { a: 1 }) {}"),
    content="error:InternalError: bytecode prototype unsupported: for-in var declaration",
  )
  inspect(
    bytecode_outcome("for (let k in { a: 1 }) {}"),
    content="error:InternalError: bytecode prototype unsupported: for-in lexical declaration",
  )
  inspect(
    bytecode_outcome("for (let [k] in { a: 1 }) {}"),
    content="error:InternalError: bytecode prototype unsupported: for-in lexical declaration",
  )
}

///|
test "bytecode in operator finds own array index property" {
  let src =
    #|var xs = [10];
    #|0 in xs;
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode in operator walks array prototype chain" {
  let src =
    #|"push" in [];
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode in operator rejects primitive rhs like interpreter" {
  let src =
    #|"x" in 1;
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Cannot use 'in' operator to search for 'x' in number",
  )
}

///|
test "bytecode instanceof uses runtime prototype chain semantics" {
  let src =
    #|function C() {}
    #|var o = new C();
    #|o instanceof C;
  inspect(bytecode_compare(src), content="value:true")
}

///|
test "bytecode instanceof returns false for primitive lhs" {
  let src =
    #|1 instanceof function() {};
  inspect(bytecode_compare(src), content="value:false")
}

///|
test "bytecode instanceof reuses runtime rhs error semantics" {
  let src =
    #|({}) instanceof {};
  inspect(
    bytecode_compare(src),
    content="throw:TypeError: Right-hand side of 'instanceof' is not callable",
  )
}

///|
test "bytecode instanceof honors Symbol.hasInstance" {
  let src =
    #|var C = {};
    #|C[Symbol.hasInstance] = function(value) { return value === 7; };
    #|(7 instanceof C) + "," + (8 instanceof C);
  inspect(bytecode_compare(src), content="value:true,false")
}

///|
test "bytecode closure factory workload" {
  inspect(
    bytecode_compare(BYTECODE_CLOSURE_FACTORY_PROGRAM),
    content="value:500500",
  )
}

///|
test "bytecode pipeline evaluate workload" {
  inspect(
    bytecode_compare(BYTECODE_PIPELINE_EXEC_PROGRAM),
    content="value:500500",
  )
}
