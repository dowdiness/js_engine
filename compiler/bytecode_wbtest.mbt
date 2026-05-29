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
