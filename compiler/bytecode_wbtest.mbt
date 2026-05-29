///|
fn parse_bytecode_for_wb(src : String) -> BytecodeProgram {
  let prog = @parser.parse(src) catch { _ => abort("parse raised") }
  compile_script_to_bytecode(prog.stmts) catch {
    _ => abort("bytecode compile raised")
  }
}

///|
test "bytecode uses local slots for function params and vars" {
  let src =
    #|function f(a) {
    #|  var b = a + 1;
    #|  return b;
    #|}
    #|f(1);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["a", "b"])
}

///|
test "bytecode keeps arguments functions on environment bindings" {
  let src =
    #|function f(a) {
    #|  var b = a;
    #|  return arguments[0] + b;
    #|}
    #|f(1);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  json_inspect(child.local_names, content=[])
  let mut saw_arguments_load = false
  for instr in child.code {
    match instr {
      LoadName("arguments") => saw_arguments_load = true
      _ => ()
    }
  }
  guard saw_arguments_load else { abort("expected arguments name load") }
}

///|
test "bytecode keeps destructuring assignment functions on environment bindings" {
  let src =
    #|function f() {
    #|  var x = 0;
    #|  [x] = [1];
    #|  return x;
    #|}
    #|f();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  json_inspect(child.local_names, content=[])
  let mut saw_assign_pattern = false
  for instr in child.code {
    match instr {
      AssignPattern(_) => saw_assign_pattern = true
      _ => ()
    }
  }
  guard saw_assign_pattern else { abort("expected destructuring assignment") }
}

///|
test "bytecode keeps var destructuring declaration functions on environment bindings" {
  let src =
    #|function f() {
    #|  var [x] = [1];
    #|  return x;
    #|}
    #|f();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let child = bytecode.main.children[0]
  json_inspect(child.local_names, content=[])
  let mut saw_assign_pattern = false
  for instr in child.code {
    match instr {
      AssignPattern(_) => saw_assign_pattern = true
      _ => ()
    }
  }
  guard saw_assign_pattern else {
    abort("expected destructuring declaration assignment")
  }
}

///|
test "bytecode treats destructuring assignment targets as captured" {
  let src =
    #|function outer() {
    #|  var x = 0;
    #|  return function() { [x] = [1]; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode plans block var declarations as function locals" {
  let src =
    #|function f() {
    #|  { var x = 1; }
    #|  return x;
    #|}
    #|f();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["x"])
}

///|
test "bytecode plans control-flow var declarations as function locals" {
  let src =
    #|function f(flag) {
    #|  if (flag) {
    #|    var x = 1;
    #|  }
    #|  return x;
    #|}
    #|f(true);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["flag", "x"])
}

///|
test "bytecode plans labeled var declarations as function locals" {
  let src =
    #|function f() {
    #|  label: { var x = 1; }
    #|  return x;
    #|}
    #|f();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["x"])
}

///|
test "bytecode plans switch var declarations as function locals" {
  let src =
    #|function f(flag) {
    #|  switch (flag) {
    #|    case true:
    #|      var x = 1;
    #|  }
    #|  return x;
    #|}
    #|f(true);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["flag", "x"])
}

///|
test "bytecode treats names inside nested labeled statements as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  label: {
    #|    return function() { return x; };
    #|  }
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode omits captured vars from local slots" {
  let src =
    #|function outer(a) {
    #|  var b = a;
    #|  return function() { return b; };
    #|}
    #|outer(1)();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=["a"])
}

///|
test "bytecode lowers unary minus to a unary value instruction" {
  let bytecode = parse_bytecode_for_wb("var x = -1;")
  let mut saw_unary = false
  for instr in bytecode.main.code {
    match instr {
      UnaryValueOp(Neg, _) => saw_unary = true
      _ => ()
    }
  }
  guard saw_unary else { abort("expected unary value op") }
}

///|
test "bytecode lowers member and computed updates to update instructions" {
  let bytecode = parse_bytecode_for_wb("var o = { x: 1 }; o.x++; ++o['x'];")
  let mut saw_property_update = false
  let mut saw_computed_update = false
  for instr in bytecode.main.code {
    match instr {
      UpdateProperty("x", Increment, false, _, _) => saw_property_update = true
      UpdateComputed(Increment, true, _, _) => saw_computed_update = true
      _ => ()
    }
  }
  guard saw_property_update else { abort("expected property update") }
  guard saw_computed_update else { abort("expected computed update") }
}

///|
test "bytecode treats names inside nested computed updates as captured" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function(o) { return o[key]++; };
    #|}
    #|outer()({ x: 1 });
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers property delete expressions to delete instructions" {
  let bytecode = parse_bytecode_for_wb(
    "var xs = []; delete xs.foo; delete xs[0];",
  )
  let mut saw_property_delete = false
  let mut saw_computed_delete = false
  for instr in bytecode.main.code {
    match instr {
      DeleteProperty("foo") => saw_property_delete = true
      DeleteComputed => saw_computed_delete = true
      _ => ()
    }
  }
  guard saw_property_delete else { abort("expected property delete") }
  guard saw_computed_delete else { abort("expected computed delete") }
}

///|
test "bytecode lowers identifier delete expressions to delete-name instructions" {
  let bytecode = parse_bytecode_for_wb("delete missing;")
  let mut saw_name_delete = false
  for instr in bytecode.main.code {
    match instr {
      DeleteName("missing") => saw_name_delete = true
      _ => ()
    }
  }
  guard saw_name_delete else { abort("expected identifier delete") }
}

///|
test "bytecode lowers typeof identifiers to a typeof-name instruction" {
  let bytecode = parse_bytecode_for_wb("typeof missing;")
  let mut saw_typeof = false
  for instr in bytecode.main.code {
    match instr {
      TypeofName("missing") => saw_typeof = true
      _ => ()
    }
  }
  guard saw_typeof else { abort("expected typeof-name instruction") }
}

///|
test "bytecode lowers typeof local slots through value typeof" {
  let bytecode = parse_bytecode_for_wb(
    "function f(a) { return typeof a; } f(1);",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let mut saw_local = false
  let mut saw_typeof = false
  for instr in bytecode.main.children[0].code {
    match instr {
      LoadLocal(0) => saw_local = true
      UnaryValueOp(Typeof, _) => saw_typeof = true
      _ => ()
    }
  }
  guard saw_local else { abort("expected local load") }
  guard saw_typeof else { abort("expected value typeof") }
}

///|
test "bytecode treats names inside nested typeof expressions as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return typeof x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers instanceof to the shared binary op instruction" {
  let bytecode = parse_bytecode_for_wb("var r = 1 instanceof function() {};")
  let mut saw_instanceof = false
  for instr in bytecode.main.code {
    match instr {
      BinaryOp(Instanceof, _) => saw_instanceof = true
      _ => ()
    }
  }
  guard saw_instanceof else { abort("expected instanceof binary op") }
}

///|
test "bytecode lowers template literals to append instructions" {
  let bytecode = parse_bytecode_for_wb("var x = 1; `a${x}b`;")
  let mut saw_template = false
  for instr in bytecode.main.code {
    match instr {
      AppendTemplate("b") => saw_template = true
      _ => ()
    }
  }
  guard saw_template else { abort("expected template append instruction") }
}

///|
test "bytecode lowers tagged templates to template-object calls" {
  let bytecode = parse_bytecode_for_wb("tag`a${x}b`;")
  let mut saw_template_object = false
  let mut saw_call = false
  for instr in bytecode.main.code {
    match instr {
      MakeTemplateObject(strings) => {
        saw_template_object = true
        json_inspect(strings, content=["a", "b"])
      }
      Call(2, _) => saw_call = true
      _ => ()
    }
  }
  guard saw_template_object else { abort("expected tagged template object") }
  guard saw_call else { abort("expected tagged template call") }
}

///|
test "bytecode lowers member tagged templates to receiver calls" {
  let bytecode = parse_bytecode_for_wb("obj.tag`a${x}b`; obj[key]`c`; ")
  let mut saw_property_prepare = false
  let mut saw_computed_prepare = false
  let mut saw_receiver_call = false
  for instr in bytecode.main.code {
    match instr {
      PreparePropertyCall("tag", _) => saw_property_prepare = true
      PrepareComputedCall(_) => saw_computed_prepare = true
      CallWithReceiver(_, _) => saw_receiver_call = true
      _ => ()
    }
  }
  guard saw_property_prepare else { abort("expected property tag receiver") }
  guard saw_computed_prepare else { abort("expected computed tag receiver") }
  guard saw_receiver_call else {
    abort("expected tagged template receiver call")
  }
}

///|
test "bytecode treats names inside nested tagged templates as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  function tag(strings, value) { return value; }
    #|  return function() { return tag`${x}`; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers regex literals to a runtime regexp instruction" {
  let bytecode = parse_bytecode_for_wb("var r = /a/i;")
  let mut saw_regexp = false
  for instr in bytecode.main.code {
    match instr {
      MakeRegExp("a", "i") => saw_regexp = true
      _ => ()
    }
  }
  guard saw_regexp else { abort("expected regexp instruction") }
}

///|
test "bytecode lowers array holes to sparse make array instruction" {
  let bytecode = parse_bytecode_for_wb("var xs = [1,,3];")
  let mut saw_sparse_array = false
  for instr in bytecode.main.code {
    match instr {
      MakeArrayWithHoles(3, holes) => {
        saw_sparse_array = true
        json_inspect(holes, content=[1])
      }
      _ => ()
    }
  }
  guard saw_sparse_array else { abort("expected sparse array instruction") }
}

///|
test "bytecode lowers array spreads to incremental append instructions" {
  let bytecode = parse_bytecode_for_wb("var xs = [0, ...ys,, 3];")
  let mut saw_start = false
  let mut saw_value = false
  let mut saw_spread = false
  let mut saw_hole = false
  for instr in bytecode.main.code {
    match instr {
      StartArray => saw_start = true
      ArrayPushValue => saw_value = true
      ArrayPushSpread(_) => saw_spread = true
      ArrayPushHole => saw_hole = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected array accumulator") }
  guard saw_value else { abort("expected array value append") }
  guard saw_spread else { abort("expected array spread append") }
  guard saw_hole else { abort("expected array hole append") }
}

///|
test "bytecode lowers spread call arguments to dynamic arg instructions" {
  let bytecode = parse_bytecode_for_wb(
    "f(1, ...xs); obj.m(...ys); new C(...zs);",
  )
  let mut saw_start = false
  let mut saw_value = false
  let mut saw_spread = false
  let mut saw_call = false
  let mut saw_receiver_call = false
  let mut saw_construct = false
  for instr in bytecode.main.code {
    match instr {
      StartArgs => saw_start = true
      ArgPushValue => saw_value = true
      ArgPushSpread(_) => saw_spread = true
      CallSpread(_) => saw_call = true
      CallSpreadWithReceiver(_) => saw_receiver_call = true
      ConstructSpread(_) => saw_construct = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected dynamic argument list") }
  guard saw_value else { abort("expected plain argument append") }
  guard saw_spread else { abort("expected spread argument append") }
  guard saw_call else { abort("expected spread call") }
  guard saw_receiver_call else { abort("expected spread receiver call") }
  guard saw_construct else { abort("expected spread construct") }
}

///|
test "bytecode treats names inside nested array spreads as captured" {
  let src =
    #|function outer() {
    #|  var xs = [1, 2];
    #|  return function() { return [...xs][1]; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers simple object literals to a make object instruction" {
  let bytecode = parse_bytecode_for_wb("var o = { a: 1, b: 2 };")
  let mut saw_object = false
  for instr in bytecode.main.code {
    match instr {
      MakeObject(keys) => {
        saw_object = true
        json_inspect(keys, content=["a", "b"])
      }
      _ => ()
    }
  }
  guard saw_object else { abort("expected make object instruction") }
}

///|
test "bytecode lowers object literal methods to method functions" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { x: 1, m() { return this.x; } };",
  )
  let mut saw_start = false
  let mut saw_method = false
  let mut saw_set = false
  for instr in bytecode.main.code {
    match instr {
      StartObject => saw_start = true
      MakeMethodFunction(_) => saw_method = true
      ObjectSetStatic("m") => saw_set = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected object accumulator") }
  guard saw_method else { abort("expected method function") }
  guard saw_set else { abort("expected method static property") }
}

///|
test "bytecode lowers object literal static accessors to accessor instructions" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { get x() { return 1; }, set x(v) { this.v = v; } };",
  )
  let mut saw_getter = false
  let mut saw_setter = false
  for instr in bytecode.main.code {
    match instr {
      ObjectSetStaticGetter("x") => saw_getter = true
      ObjectSetStaticSetter("x") => saw_setter = true
      _ => ()
    }
  }
  guard saw_getter else { abort("expected static getter instruction") }
  guard saw_setter else { abort("expected static setter instruction") }
}

///|
test "bytecode lowers object literal computed accessors to computed accessor instructions" {
  let bytecode = parse_bytecode_for_wb(
    "var key = 'x'; var o = { get [key]() { return 1; }, set [key](v) { this.v = v; } };",
  )
  let mut saw_key = false
  let mut saw_method = false
  let mut saw_getter = false
  let mut saw_setter = false
  for instr in bytecode.main.code {
    match instr {
      ToObjectLiteralPropertyKey => saw_key = true
      MakeComputedMethodFunction(_) => saw_method = true
      ObjectSetComputedGetter => saw_getter = true
      ObjectSetComputedSetter => saw_setter = true
      _ => ()
    }
  }
  guard saw_key else {
    abort("expected computed accessor key canonicalization")
  }
  guard saw_method else { abort("expected computed accessor method function") }
  guard saw_getter else { abort("expected computed getter instruction") }
  guard saw_setter else { abort("expected computed setter instruction") }
}

///|
test "bytecode treats names inside nested computed accessors as captured" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  var value = 1;
    #|  return function() { return ({ get [key]() { return value; } }).x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested object literal methods as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return { m() { return x; } };
    #|}
    #|outer().m();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers computed object literal methods with computed home object" {
  let bytecode = parse_bytecode_for_wb(
    "var key = 'm'; var o = { [key]() { return this; } };",
  )
  let mut saw_key = false
  let mut saw_method = false
  let mut saw_computed = false
  for instr in bytecode.main.code {
    match instr {
      ToObjectLiteralPropertyKey => saw_key = true
      MakeComputedMethodFunction(_) => saw_method = true
      ObjectSetComputed => saw_computed = true
      _ => ()
    }
  }
  guard saw_key else { abort("expected computed method key canonicalization") }
  guard saw_method else { abort("expected computed method function") }
  guard saw_computed else { abort("expected computed method property set") }
}

///|
test "bytecode lowers super property access and calls inside methods" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { m() { super.x; super['m'](); } };",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one method child")
  }
  let method_child = bytecode.main.children[0]
  let mut saw_property = false
  let mut saw_computed_call = false
  for instr in method_child.code {
    match instr {
      LoadSuperProperty("x", _) => saw_property = true
      PrepareSuperComputedCall(_) => saw_computed_call = true
      _ => ()
    }
  }
  guard saw_property else { abort("expected super property load") }
  guard saw_computed_call else { abort("expected super computed call") }
}

///|
test "bytecode treats names inside nested super computed keys as captured" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return { m() { return super[key]; } };
    #|}
    #|outer().m();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers object spreads to incremental object instructions" {
  let bytecode = parse_bytecode_for_wb("var o = { a: 1, ...src, b: 2 };")
  let mut saw_start = false
  let mut saw_a = false
  let mut saw_spread = false
  let mut saw_b = false
  for instr in bytecode.main.code {
    match instr {
      StartObject => saw_start = true
      ObjectSetStatic("a") => saw_a = true
      ObjectSpread(_) => saw_spread = true
      ObjectSetStatic("b") => saw_b = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected object accumulator") }
  guard saw_a else { abort("expected static property before spread") }
  guard saw_spread else { abort("expected object spread") }
  guard saw_b else { abort("expected static property after spread") }
}

///|
test "bytecode lowers object literal __proto__ through proto instruction" {
  let bytecode = parse_bytecode_for_wb(
    "var proto = {}; var o = { a: 1, __proto__: proto, b: 2 };",
  )
  let mut saw_start = false
  let mut saw_proto = false
  let mut saw_a = false
  let mut saw_b = false
  for instr in bytecode.main.code {
    match instr {
      StartObject => saw_start = true
      ObjectSetStatic("a") => saw_a = true
      ObjectSetProto => saw_proto = true
      ObjectSetStatic("b") => saw_b = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected object accumulator") }
  guard saw_a else { abort("expected static property before __proto__") }
  guard saw_proto else { abort("expected object __proto__ instruction") }
  guard saw_b else { abort("expected static property after __proto__") }
}

///|
test "bytecode lowers computed object literal data properties" {
  let bytecode = parse_bytecode_for_wb(
    "var key = 'x'; var o = { [key]: 1, after: 2 };",
  )
  let mut saw_key = false
  let mut saw_computed = false
  let mut saw_after = false
  for instr in bytecode.main.code {
    match instr {
      ToObjectLiteralPropertyKey => saw_key = true
      ObjectSetComputed => saw_computed = true
      ObjectSetStatic("after") => saw_after = true
      _ => ()
    }
  }
  guard saw_key else { abort("expected object literal key canonicalization") }
  guard saw_computed else { abort("expected computed data property set") }
  guard saw_after else { abort("expected static property after computed") }
}

///|
test "bytecode lowers named function expressions with a self-name instruction" {
  let bytecode = parse_bytecode_for_wb("var f = function g() { return g; };")
  let mut saw_named_function = false
  for instr in bytecode.main.code {
    match instr {
      MakeNamedFunction(_, "g") => saw_named_function = true
      _ => ()
    }
  }
  guard saw_named_function else { abort("expected named function expression") }
}

///|
test "bytecode lowers arrow functions with a dedicated arrow instruction" {
  let bytecode = parse_bytecode_for_wb("var f = a => a + 1;")
  let mut saw_arrow_function = false
  for instr in bytecode.main.code {
    match instr {
      MakeArrowFunction(_) => saw_arrow_function = true
      _ => ()
    }
  }
  guard saw_arrow_function else { abort("expected arrow function") }
}

///|
test "bytecode lowers rest arrow functions as environment-backed children" {
  let bytecode = parse_bytecode_for_wb("var f = (a, ...rest) => rest[0];")
  guard bytecode.main.children.length() == 1 else {
    abort("expected one arrow child")
  }
  let child = bytecode.main.children[0]
  guard child.rest_param is Some("rest") else {
    abort("expected rest parameter metadata")
  }
  json_inspect(child.local_names, content=[])
}

///|
test "bytecode lowers ordinary rest functions as environment-backed children" {
  let bytecode = parse_bytecode_for_wb(
    "function f(a, ...rest) { return rest[0]; } f(1, 2);",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one function child")
  }
  let child = bytecode.main.children[0]
  guard child.rest_param is Some("rest") else {
    abort("expected rest parameter metadata")
  }
  json_inspect(child.local_names, content=[])
}

///|
test "bytecode lowers object method rest functions as environment-backed children" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { m(a, ...rest) { return rest[0]; } }; o.m(1, 2);",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one method child")
  }
  let child = bytecode.main.children[0]
  guard child.rest_param is Some("rest") else {
    abort("expected rest parameter metadata")
  }
  json_inspect(child.local_names, content=[])
}

///|
test "bytecode treats names inside nested arrow functions as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return () => x;
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers this expressions to a dedicated load instruction" {
  let bytecode = parse_bytecode_for_wb("function f() { return this; } f();")
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let mut saw_this = false
  for instr in bytecode.main.children[0].code {
    match instr {
      LoadThis => saw_this = true
      _ => ()
    }
  }
  guard saw_this else { abort("expected load this instruction") }
}

///|
test "bytecode lowers new.target expressions to a dedicated load instruction" {
  let bytecode = parse_bytecode_for_wb(
    "function f() { return new.target; } new f();",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let mut saw_new_target = false
  for instr in bytecode.main.children[0].code {
    match instr {
      LoadNewTarget => saw_new_target = true
      _ => ()
    }
  }
  guard saw_new_target else { abort("expected load new.target instruction") }
}

///|
test "bytecode lowers console members to a shared host helper load" {
  let bytecode = parse_bytecode_for_wb("console.log(1);")
  let mut saw_console = false
  for instr in bytecode.main.code {
    match instr {
      LoadConsoleMember("log") => saw_console = true
      _ => ()
    }
  }
  guard saw_console else { abort("expected console member load") }
}

///|
test "bytecode treats names inside nested unary expressions as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return -x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested template expressions as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return `${x}`; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested do while statements as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() {
    #|    do { x = x + 1; } while (false);
    #|  };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers switch statements with duplicated discriminant dispatch" {
  let bytecode = parse_bytecode_for_wb(
    "switch (x) { case 1: 'one'; break; default: 'default'; }",
  )
  let mut saw_dup = false
  let mut saw_strict_equal = false
  let mut saw_patched_jump = false
  for instr in bytecode.main.code {
    match instr {
      Dup => saw_dup = true
      BinaryOp(EqEqEq, _) => saw_strict_equal = true
      Jump(target) => {
        if target == -1 {
          abort("unpatched switch jump")
        }
        saw_patched_jump = true
      }
      JumpIfFalse(target) =>
        if target == -1 {
          abort("unpatched switch test jump")
        }
      _ => ()
    }
  }
  guard saw_dup else { abort("expected switch discriminant duplication") }
  guard saw_strict_equal else { abort("expected strict equality test") }
  guard saw_patched_jump else { abort("expected switch dispatch jump") }
}

///|
test "bytecode treats names inside nested switch statements as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function(flag) {
    #|    switch (flag) {
    #|      case true:
    #|        return x;
    #|    }
    #|  };
    #|}
    #|outer()(true);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers for-in assignment loops to iterator instructions" {
  let bytecode = parse_bytecode_for_wb(
    "var k; for (k in obj) { if (k === 'a') break; }",
  )
  let mut saw_start = false
  let mut saw_next = false
  let mut saw_end = false
  for instr in bytecode.main.code {
    match instr {
      StartForIn => saw_start = true
      ForInNext(target) => {
        if target == -1 {
          abort("unpatched for-in exit jump")
        }
        saw_next = true
      }
      EndForIn => saw_end = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected for-in iterator start") }
  guard saw_next else { abort("expected for-in next instruction") }
  guard saw_end else { abort("expected for-in break cleanup") }
}

///|
test "bytecode treats names inside nested for-in assignment loops as captured" {
  let src =
    #|function outer() {
    #|  var obj = { a: 1 };
    #|  var k = "";
    #|  return function() { for (k in obj) {} };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers for-in member and computed assignment targets" {
  let bytecode = parse_bytecode_for_wb(
    "var target = {}; for (target.x in obj) {} for (target[key] in obj) {}",
  )
  let mut saw_property_set = false
  let mut saw_computed_set = false
  for instr in bytecode.main.code {
    match instr {
      SetForInProperty("x", _) => saw_property_set = true
      SetForInComputed(_) => saw_computed_set = true
      _ => ()
    }
  }
  guard saw_property_set else { abort("expected for-in property set") }
  guard saw_computed_set else { abort("expected for-in computed set") }
}

///|
test "bytecode lowers for-in destructuring assignment targets" {
  let bytecode = parse_bytecode_for_wb("var first; for ([first] in obj) {}")
  let mut saw_start = false
  let mut saw_assign_pattern = false
  for instr in bytecode.main.code {
    match instr {
      StartForIn => saw_start = true
      AssignPattern(_) => saw_assign_pattern = true
      _ => ()
    }
  }
  guard saw_start else { abort("expected for-in iterator start") }
  guard saw_assign_pattern else { abort("expected for-in pattern assignment") }
}

///|
test "bytecode treats names inside nested for-in destructuring targets as captured" {
  let src =
    #|function outer() {
    #|  var first = "";
    #|  return function(src) { for ([first] in src) {} };
    #|}
    #|outer()({ xy: 1 });
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested for-in expression targets as captured" {
  let src =
    #|function outer() {
    #|  var target = {};
    #|  var key = "x";
    #|  return function(obj) { for (target[key] in obj) {} };
    #|}
    #|outer()({ x: 1 });
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode patches unlabeled break and continue jumps" {
  let break_bytecode = parse_bytecode_for_wb("while (true) break;")
  let mut saw_break_to_exit = false
  for instr in break_bytecode.main.code {
    match instr {
      Jump(target) => {
        if target == -1 {
          abort("unpatched break jump")
        }
        if target == break_bytecode.main.code.length() {
          saw_break_to_exit = true
        }
      }
      JumpIfFalse(target) =>
        if target == -1 {
          abort("unpatched loop exit jump")
        }
      _ => ()
    }
  }
  guard saw_break_to_exit else { abort("expected break jump to loop exit") }
  let continue_bytecode = parse_bytecode_for_wb("do continue; while (false);")
  let mut saw_continue_to_condition = false
  for i, instr in continue_bytecode.main.code {
    match instr {
      Jump(target) => {
        if target == -1 {
          abort("unpatched continue jump")
        }
        if target == i + 1 {
          saw_continue_to_condition = true
        }
      }
      JumpIfFalse(target) =>
        if target == -1 {
          abort("unpatched do-while exit jump")
        }
      _ => ()
    }
  }
  guard saw_continue_to_condition else {
    abort("expected continue jump to condition")
  }
}

///|
test "bytecode patches labeled break and continue jumps" {
  let break_bytecode = parse_bytecode_for_wb("label: { break label; }")
  let mut saw_labeled_break = false
  for instr in break_bytecode.main.code {
    match instr {
      Jump(target) => {
        if target == -1 {
          abort("unpatched labeled break jump")
        }
        if target == break_bytecode.main.code.length() {
          saw_labeled_break = true
        }
      }
      _ => ()
    }
  }
  guard saw_labeled_break else { abort("expected labeled break to label exit") }
  let continue_bytecode = parse_bytecode_for_wb(
    "outer: do continue outer; while (false);",
  )
  let mut saw_labeled_continue = false
  for i, instr in continue_bytecode.main.code {
    match instr {
      Jump(target) => {
        if target == -1 {
          abort("unpatched labeled continue jump")
        }
        if target == i + 1 {
          saw_labeled_continue = true
        }
      }
      JumpIfFalse(target) =>
        if target == -1 {
          abort("unpatched labeled do-while exit jump")
        }
      _ => ()
    }
  }
  guard saw_labeled_continue else {
    abort("expected labeled continue to loop condition")
  }
}

///|
test "bytecode treats names inside nested object literals as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { return { value: x }.value; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested computed object literal keys as captured" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function() { return ({ [key]: 1 }).x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode treats names inside nested object spreads as captured" {
  let src =
    #|function outer() {
    #|  var source = { x: 1 };
    #|  return function() { return { ...source }.x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers optional member access with a nullish guard" {
  let bytecode = parse_bytecode_for_wb("var r = obj?.x;")
  let mut saw_guard = false
  let mut saw_get = false
  for instr in bytecode.main.code {
    match instr {
      JumpIfNotNullishKeep(target) => {
        if target == -1 {
          abort("unpatched optional member guard")
        }
        saw_guard = true
      }
      GetProperty("x", _) => saw_get = true
      _ => ()
    }
  }
  guard saw_guard else { abort("expected optional nullish guard") }
  guard saw_get else { abort("expected optional property get") }
}

///|
test "bytecode treats names inside nested optional chains as captured" {
  let src =
    #|function outer() {
    #|  var obj = { x: 1 };
    #|  return function() { return obj?.x; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers member and computed assignments to property set instructions" {
  let src =
    #|var xs = [];
    #|xs.foo = 1;
    #|xs[0] = 2;
  let bytecode = parse_bytecode_for_wb(src)
  let mut saw_property_set = false
  let mut saw_computed_set = false
  for instr in bytecode.main.code {
    match instr {
      SetProperty("foo", _) => saw_property_set = true
      SetComputed(_) => saw_computed_set = true
      _ => ()
    }
  }
  guard saw_property_set else { abort("expected property set instruction") }
  guard saw_computed_set else { abort("expected computed set instruction") }
}

///|
test "bytecode lowers identifier compound assignment through binary op and local store" {
  let bytecode = parse_bytecode_for_wb(
    "function f() { var x = 1; x += 2; return x; } f();",
  )
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  let mut saw_add = false
  let mut saw_store_local = false
  for instr in bytecode.main.children[0].code {
    match instr {
      BinaryOp(Add, _) => saw_add = true
      StoreLocal(0) => saw_store_local = true
      _ => ()
    }
  }
  guard saw_add else { abort("expected compound binary add") }
  guard saw_store_local else { abort("expected compound local store") }
}

///|
test "bytecode lowers global compound assignment reads through assignment names" {
  let bytecode = parse_bytecode_for_wb("x += 1;")
  let mut saw_assignment_load = false
  for instr in bytecode.main.code {
    match instr {
      LoadAssignmentName("x") => saw_assignment_load = true
      _ => ()
    }
  }
  guard saw_assignment_load else { abort("expected assignment-name load") }
}

///|
test "bytecode treats names inside nested compound assignments as captured" {
  let src =
    #|function outer() {
    #|  var x = 1;
    #|  return function() { x += 1; };
    #|}
    #|outer()();
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers member compound assignments through reference-preserving reads" {
  let bytecode = parse_bytecode_for_wb("var o = { x: 1 }; o.x += 2;")
  let mut saw_add = false
  let mut saw_property_read = false
  let mut saw_property_set = false
  for instr in bytecode.main.code {
    match instr {
      ReadPropertyForAssign("x", _) => saw_property_read = true
      BinaryOp(Add, _) => saw_add = true
      SetProperty("x", _) => saw_property_set = true
      _ => ()
    }
  }
  guard saw_property_read else { abort("expected property assignment read") }
  guard saw_add else { abort("expected compound binary add") }
  guard saw_property_set else { abort("expected property set") }
}

///|
test "bytecode lowers computed compound assignments through canonicalized keys" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { x: 1 }; var k = 'x'; o[k] *= 3;",
  )
  let mut saw_mul = false
  let mut saw_computed_read = false
  let mut saw_computed_set = false
  for instr in bytecode.main.code {
    match instr {
      ReadComputedForAssign(_) => saw_computed_read = true
      BinaryOp(Mul, _) => saw_mul = true
      SetComputed(_) => saw_computed_set = true
      _ => ()
    }
  }
  guard saw_computed_read else { abort("expected computed assignment read") }
  guard saw_mul else { abort("expected compound binary multiply") }
  guard saw_computed_set else { abort("expected computed set") }
}

///|
test "bytecode lowers logical member compound assignments with reference cleanup" {
  let bytecode = parse_bytecode_for_wb(
    "var o = { x: 0 }; o.x ||= 1; o['x'] &&= 2;",
  )
  let mut saw_or_guard = false
  let mut saw_and_guard = false
  let mut saw_property_cleanup = false
  let mut saw_computed_cleanup = false
  for instr in bytecode.main.code {
    match instr {
      JumpIfTrueKeep(target) => {
        if target == -1 {
          abort("unpatched property logical assignment guard")
        }
        saw_or_guard = true
      }
      JumpIfFalseKeep(target) => {
        if target == -1 {
          abort("unpatched computed logical assignment guard")
        }
        saw_and_guard = true
      }
      DropPropertyAssignReference => saw_property_cleanup = true
      DropComputedAssignReference => saw_computed_cleanup = true
      _ => ()
    }
  }
  guard saw_or_guard else { abort("expected logical-or guard") }
  guard saw_and_guard else { abort("expected logical-and guard") }
  guard saw_property_cleanup else {
    abort("expected property reference cleanup")
  }
  guard saw_computed_cleanup else {
    abort("expected computed reference cleanup")
  }
}

///|
test "bytecode treats names inside nested computed compound assignments as captured" {
  let src =
    #|function outer() {
    #|  var key = "x";
    #|  return function(o) { o[key] += 1; };
    #|}
    #|outer()({ x: 1 });
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}

///|
test "bytecode lowers new expressions to construct instructions" {
  let bytecode = parse_bytecode_for_wb("function C() {} new C();")
  let mut saw_construct = false
  for instr in bytecode.main.code {
    match instr {
      Construct(0, _) => saw_construct = true
      _ => ()
    }
  }
  guard saw_construct else { abort("expected construct instruction") }
}

///|
test "bytecode treats names inside nested computed assignments as captured" {
  let src =
    #|function outer() {
    #|  var key = 0;
    #|  return function(xs) { xs[key] = 1; };
    #|}
    #|outer()([]);
  let bytecode = parse_bytecode_for_wb(src)
  guard bytecode.main.children.length() == 1 else {
    abort("expected one child function")
  }
  json_inspect(bytecode.main.children[0].local_names, content=[])
}
