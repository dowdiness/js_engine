///|
fn run_executor_neutral_bytecode(
  interp : Interpreter,
  source : String,
) -> Value raise Error {
  parse_bytecode_for_wb(source).run(interp)
}

///|
test "Function.prototype.call forwarding recursion stays off the host stack" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "function f(n){if(n===0)return 0;return 1+f.call(undefined,n-1);}" +
    "f.call(undefined,1024);",
  )
  inspect(result.to_string(), content="1024")
}

///|
test "Function.prototype.call preserves ordinary return and receiver" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "function target(value){return this.base+value;}" +
    "target.call({base:4},3);",
  )
  inspect(result.to_string(), content="7")
}

///|
test "Function.prototype.call preserves guest throw identity" {
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    let _ = run_executor_neutral_bytecode(
      interp, "var marker={}; function target(){throw marker;} target.call(undefined);",
    )
    None
  } catch {
    error => Some(error)
  }
  let marker = interp.global.get("marker")
  match caught {
    Some(error) =>
      assert_true(physical_equal(@runtime.js_error_to_value(error), marker))
    None => fail("Function.prototype.call must propagate the guest throw")
  }
}

///|
test "Function.prototype.call does not admit a user replacement" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "function target(){return 1;}" +
    "target.call=function(){return 2;}; target.call(null);",
  )
  inspect(result.to_string(), content="2")
}

///|
test "detached Function.prototype.call rejects a non-callable receiver" {
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    let _ = run_executor_neutral_bytecode(
      interp, "var detached=Function.prototype.call; detached({},1);",
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      match value {
        Object(data) => inspect(data.class_name, content="TypeError")
        _ => fail("detached call must raise an object TypeError")
      }
    Some(error) =>
      fail("detached call raised a non-JavaScript error: " + error.to_string())
    None => fail("detached call must reject its non-callable receiver")
  }
}

///|
test "captured FuncCallMethod forwarding remains non-recursive" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "delete Function.prototype.call;" +
    "function f(n){if(n===0)return 0;return 1+f.call(undefined,n-1);}" +
    "f.call(undefined,1024);",
  )
  inspect(result.to_string(), content="1024")
}

///|
test "Function.prototype.call preserves name length and source identity" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "let call=Function.prototype.call;" +
    "call.name === 'call' && call.length === 1 &&" +
    "call.toString() === 'function call() { [native code] }';",
  )
  inspect(result.to_string(), content="true")
}

///|
fn assert_plain_member_call_lowering(
  code : Array[BytecodeInstr],
  context : String,
) -> Bool raise Error {
  let mut saw_prepare = false
  let mut saw_receiver_call = false
  for instr in code {
    match instr {
      PreparePlainPropertyCall("step", _) => saw_prepare = true
      CallWithReceiver(_, _) => saw_receiver_call = true
      _ => ()
    }
  }
  guard saw_prepare else {
    fail(context + " must use PreparePlainPropertyCall")
  }
  guard saw_receiver_call else {
    fail(context + " must retain CallWithReceiver")
  }
  true
}

///|
fn legacy_property_prepare_count(code : Array[BytecodeInstr]) -> Int {
  let mut count = 0
  for instr in code {
    match instr {
      PreparePropertyCall(_, _) => count += 1
      _ => ()
    }
  }
  count
}

///|
fn assert_grouped_optional_member_source_for_wb(
  source : String,
) -> Unit raise Error {
  let program = @parser.parse(source)
  guard program.stmts.length() == 1 else {
    fail("grouped optional member fixture must contain one statement")
  }
  match program.stmts[0] {
    @ast.ExprStmt(
      @ast.ChainMember(
        @ast.OptionalCall(
          @ast.Grouping(@ast.Member(@ast.Ident("receiver", _), "step", _), _),
          _,
          _
        ),
        "next",
        _
      ),
      _
    ) => ()
    _ =>
      fail(
        "grouped optional member fixture must parse as ChainMember(OptionalCall(Grouping(Member)))",
      )
  }
}

///|
test "plain static member calls use suspended preparation at root and recursion" {
  let source = "let remaining = 320;" +
    "let receiver = { get step() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = receiver.step();" +
    "return function() { return next + 1; };" +
    "} };" +
    "receiver.step();"
  let lowered = parse_bytecode_for_wb(source)
  assert_true(
    assert_plain_member_call_lowering(
      lowered.main.code,
      "root plain member call",
    ),
  )
  let mut saw_recursive_plain_call = false
  for child in lowered.main.children {
    if assert_plain_member_call_lowering(
        child.code,
        "recursive plain member call",
      ) {
      saw_recursive_plain_call = true
    }
  }
  assert_true(saw_recursive_plain_call)
}

///|
test "plain preparation leaves optional chain and tagged producers on legacy opcode" {
  let prefix = "var receiver = { step: function() {} };"
  let plain = parse_bytecode_for_wb(prefix + "receiver.step();")
  let optional = parse_bytecode_for_wb(prefix + "receiver?.step();")
  let optional_callee = parse_bytecode_for_wb(prefix + "receiver?.step?.();")
  let grouped_source = "(receiver.step)?.().next;"
  assert_grouped_optional_member_source_for_wb(grouped_source)
  let grouped = parse_bytecode_for_wb(prefix + grouped_source)
  let chain = parse_bytecode_for_wb(prefix + "receiver?.step.next();")
  let tagged = parse_bytecode_for_wb(prefix + "receiver.step`tag`;")
  let mut saw_plain = false
  for instr in plain.main.code {
    match instr {
      PreparePlainPropertyCall("step", _) => saw_plain = true
      _ => ()
    }
  }
  assert_true(saw_plain)
  assert_true(legacy_property_prepare_count(optional.main.code) >= 1)
  assert_true(legacy_property_prepare_count(optional_callee.main.code) >= 1)
  let mut grouped_receiver_call = false
  let mut grouped_plain_prepare = false
  for instr in grouped.main.code {
    match instr {
      CallWithReceiver(_, _) => grouped_receiver_call = true
      PreparePlainPropertyCall(_, _) => grouped_plain_prepare = true
      _ => ()
    }
  }
  assert_true(grouped_receiver_call)
  assert_false(grouped_plain_prepare)
  assert_eq(legacy_property_prepare_count(grouped.main.code), 1)
  assert_true(legacy_property_prepare_count(chain.main.code) >= 1)
  assert_true(legacy_property_prepare_count(tagged.main.code) >= 1)
}

///|
test "RED: tagged static accessor member-call reaches depth 320" {
  let source = "let remaining = 320;" +
    "let receiver = { get tag() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = receiver.tag`x`;" +
    "return function() { return next + 1; };" +
    "} };" +
    "receiver.tag`x`;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "tagged static accessor member-call keeps shallow control" {
  let source = "let remaining = 8;" +
    "let receiver = { get tag() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = receiver.tag`x`;" +
    "return function() { return next + 1; };" +
    "} };" +
    "receiver.tag`x`;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="8")
}

///|
test "static tagged accessor calls preserve receiver and evaluation order" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = '';" +
    "var receiver = { get tag() {" +
    "trace = trace + 'g';" +
    "return function(strings, value) {" +
    "trace = trace + (this === receiver ? 'r' : 'x');" +
    "return trace + ':' + strings[0] + strings[1] + ':' + value;" +
    "};" +
    "} };" +
    "receiver.tag`a${(trace = trace + 's', 'v')}b`;",
  )
  inspect(result.to_string(), content="gsr:ab:v")
}

///|
test "static tagged member calls retain property preparation at root and recursion" {
  let source = "let remaining = 2;" +
    "let receiver = { get tag() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = receiver.tag`x`;" +
    "return function() { return next + 1; };" +
    "} };" +
    "receiver.tag`x`;"
  let lowered = parse_bytecode_for_wb(source)
  assert_eq(legacy_property_prepare_count(lowered.main.code), 1)
  let mut recursive_prepare_count = 0
  for child in lowered.main.children {
    recursive_prepare_count += legacy_property_prepare_count(child.code)
  }
  assert_true(recursive_prepare_count >= 1)
}

///|
test "optional static accessor calls preserve receiver order and nullish skip" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = '';" +
    "var receiver = { get step() {" +
    "trace = trace + 'g';" +
    "return function(value) {" +
    "trace = trace + (this === receiver ? 'c' : 'x');" +
    "return trace + ':' + value;" +
    "};" +
    "} };" +
    "receiver?.step(trace = trace + 'a');",
  )
  inspect(result.to_string(), content="gac:ga")
  let nullish_result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = ''; var receiver = null;" +
    "receiver?.step(trace = trace + 'a'); trace;",
  )
  inspect(nullish_result.to_string(), content="")
  let nullish_callee_result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = ''; var receiver = { get step() {" +
    "trace = trace + 'g'; return null; } };" +
    "receiver?.step?.(trace = trace + 'a'); trace;",
  )
  inspect(nullish_callee_result.to_string(), content="g")
}

///|
test "static tagged accessor throw preserves identity and interpreter reuse" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var reads = 0;" +
    "var receiver = { get tag() { reads = reads + 1;" +
    "if (reads === 1) throw marker; return function() { return 7; }; } };",
  )
  let caught : Error? = try {
    let _ = run_executor_neutral_bytecode(interp, "receiver.tag`x`;")
    None
  } catch {
    error => Some(error)
  }
  let marker = interp.global.get("marker")
  match caught {
    Some(error) =>
      assert_true(physical_equal(@runtime.js_error_to_value(error), marker))
    None => fail("tagged getter throw must reach the caller")
  }
  let result = run_executor_neutral_bytecode(
    interp, "receiver.tag`x` === 7 && reads === 2;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "bytecode static accessor-prepared receiver calls suspend property preparation" {
  let source = "let remaining = 320;" +
    "let receiver = { get step() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = receiver.step();" +
    "return function() { return next + 1; };" +
    "} };" +
    "receiver.step();"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "plain accessor-prepared receiver calls preserve order and receiver identity" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = '';" +
    "var receiver = { get step() {" +
    "trace = trace + 'g';" +
    "return function(value) {" +
    "trace = trace + (this === receiver ? 'c' : 'x');" +
    "return trace + ':' + value;" +
    "};" +
    "} };" +
    "receiver.step(trace = trace + 'a');",
  )
  inspect(result.to_string(), content="gac:ga")
}

///|
test "plain accessor-prepared non-callable result evaluates arguments before TypeError" {
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    let _ = run_executor_neutral_bytecode(
      interp,
      "var trace = '';" +
      "var receiver = { get step() { trace = trace + 'g'; return 1; } };" +
      "function argument() { trace = trace + 'a'; return 7; }" +
      "receiver.step(argument());",
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) =>
      match @runtime.js_error_to_value_with_env(error, Some(interp.global)) {
        Object(data) => inspect(data.class_name, content="TypeError")
        _ => fail("expected a JavaScript TypeError object")
      }
    None => fail("non-callable receiver call must throw")
  }
  let trace = interp.global.get("trace")
  inspect(trace.to_string(), content="ga")
}

///|
test "plain accessor-prepared getter throw skips arguments and final call" {
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    let _ = run_executor_neutral_bytecode(
      interp,
      "var marker = {}; var trace = ''; var reads = 0;" +
      "var receiver = { get step() {" +
      "trace = trace + 'g'; reads = reads + 1;" +
      "if (reads === 1) throw marker;" +
      "return function() { trace = trace + 'c'; };" +
      "} };" +
      "function argument() { trace = trace + 'a'; return 7; }" +
      "receiver.step(argument());",
    )
    None
  } catch {
    error => Some(error)
  }
  let marker = interp.global.get("marker")
  match caught {
    Some(error) =>
      assert_true(physical_equal(@runtime.js_error_to_value(error), marker))
    None => fail("getter throw must propagate to the caller")
  }
  let trace = interp.global.get("trace")
  inspect(trace.to_string(), content="g")
  let reads = interp.global.get("reads")
  inspect(reads.to_string(), content="1")
}

///|
test "computed string literal getter recursion keeps the shallow control" {
  let source = "let remaining = 8;" +
    "let receiver = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "return 1 + receiver['x'];" +
    "} };" +
    "receiver['x'];"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="8")
}

///|
test "runtime-string computed getter recursion keeps the shallow control" {
  let source = "let remaining = 8; let key = 'x';" +
    "let receiver = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "return 1 + receiver[key];" +
    "} };" +
    "receiver[key];"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="8")
}

///|
test "runtime-string computed getter recursion reaches depth 256" {
  let source = "let remaining = 256; let key = 'x';" +
    "let receiver = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "return 1 + receiver[key];" +
    "} };" +
    "receiver[key];"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="256")
}

///|
test "runtime-string computed getter recursion lowers through GetComputed" {
  let source = "let remaining = 8; let key = 'x';" +
    "let receiver = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "return 1 + receiver[key];" +
    "} };" +
    "receiver[key];"
  let lowered = parse_bytecode_for_wb(source)
  let mut root_get = false
  for instr in lowered.main.code {
    match instr {
      GetComputed(_) => root_get = true
      _ => ()
    }
  }
  let mut getter_get = false
  for child in lowered.main.children {
    for instr in child.code {
      match instr {
        GetComputed(_) => getter_get = true
        _ => ()
      }
    }
  }
  assert_true(root_get)
  assert_true(getter_get)
}

///|
test "runtime-string computed getter reads deliver once and permit reuse" {
  let interp = @interpreter.new_interpreter()
  let first = run_executor_neutral_bytecode(
    interp,
    "var reads = 0; var marker = {}; var key = 'x';" +
    "var receiver = { get x() { reads = reads + 1; return marker; } };" +
    "receiver[key] === marker && reads === 1;",
  )
  inspect(first.to_string(), content="true")
  let second = run_executor_neutral_bytecode(
    interp, "receiver[key] === marker && reads === 2;",
  )
  inspect(second.to_string(), content="true")
}

///|
test "runtime-string computed getter reads preserve guest throw identity and reuse" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var reads = 0; var key = 'x';" +
    "var receiver = { get x() { reads = reads + 1;" +
    "if (reads === 1) throw marker; return 7; } };",
  )
  let caught : Error? = try {
    let _ = run_executor_neutral_bytecode(interp, "receiver[key];")
    None
  } catch {
    error => Some(error)
  }
  let marker = interp.global.get("marker")
  match caught {
    Some(error) =>
      assert_true(physical_equal(@runtime.js_error_to_value(error), marker))
    None => fail("computed getter throw must reach the caller")
  }
  let result = run_executor_neutral_bytecode(
    interp, "receiver[key] === 7 && reads === 2;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "runtime-string computed reads preserve legacy rejected families" {
  let object_key = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = '';" +
    "var key = { toString: function() { trace = trace + 'k'; return 'x'; } };" +
    "var receiver = { get x() { trace = trace + 'g'; return 1; } };" +
    "receiver[key]; trace;",
  )
  inspect(object_key.to_string(), content="kg")
  let symbol_key = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var key = Symbol('x'); var receiver = {}; receiver[key] = 7;" +
    "receiver[key];",
  )
  inspect(symbol_key.to_string(), content="7")
  let inherited = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = ''; var key = 'x';" +
    "var proto = { get x() { trace = trace + 'g'; return 2; } };" +
    "var receiver = Object.create(proto); receiver[key]; trace;",
  )
  inspect(inherited.to_string(), content="g")
  let data = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var key = 'x'; var receiver = { x: 3 }; receiver[key];",
  )
  inspect(data.to_string(), content="3")
  let proxy = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = ''; var key = 'x';" +
    "var receiver = new Proxy({}, { get: function() { trace = trace + 'p';" +
    "return 4; } }); receiver[key]; trace;",
  )
  inspect(proxy.to_string(), content="p")
  let array = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var key = 'length'; var receiver = []; receiver[key];",
  )
  inspect(array.to_string(), content="0")
}

///|
test "computed string literal accessor member-call keeps the shallow control" {
  let source = "let remaining = 8;" +
    "let receiver = { get step() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = receiver['step']();" +
    "return function() { return next + 1; };" +
    "} };" +
    "receiver['step']();"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="8")
}

///|
test "runtime-string computed accessor member-call keeps the shallow control" {
  let source = "let remaining = 8; let key = 'step';" +
    "let receiver = { get step() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = receiver[key]();" +
    "return function() { return next + 1; };" +
    "} };" +
    "receiver[key]();"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="8")
}

///|
test "runtime-string computed accessor member-call completes at depth 256" {
  let source = "let remaining = 256; let key = 'step';" +
    "let receiver = { get step() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = receiver[key]();" +
    "return function() { return next + 1; };" +
    "} };" +
    "receiver[key]();"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="256")
}

///|
test "runtime-string computed calls preserve legacy rejected families" {
  let object_key = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = '';" +
    "var receiver = { get step() { trace = trace + 'g';" +
    "return function() { trace = trace + 'c'; return 1; }; } };" +
    "var key = { toString: function() { trace = trace + 'k'; return 'step'; } };" +
    "receiver[key](); trace;",
  )
  inspect(object_key.to_string(), content="kgc")
  let symbol_key = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = ''; var key = Symbol('step'); var receiver = {};" +
    "receiver[key] = function() { trace = trace + 'c'; return 1; };" +
    "receiver[key](); trace;",
  )
  inspect(symbol_key.to_string(), content="c")
  let inherited = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = ''; var key = 'step';" +
    "var proto = { get step() { trace = trace + 'g';" +
    "return function() { trace = trace + 'c'; return 1; }; } };" +
    "var receiver = Object.create(proto); receiver[key](); trace;",
  )
  inspect(inherited.to_string(), content="gc")
  let proxy = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = ''; var key = 'step';" +
    "var receiver = new Proxy({}, { get: function() { trace = trace + 'p';" +
    "return function() { trace = trace + 'c'; return 1; }; } });" +
    "receiver[key](); trace;",
  )
  inspect(proxy.to_string(), content="pc")
  let array = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = ''; var key = 'step'; var receiver = [];" +
    "receiver.step = function() { trace = trace + 'c'; return 1; };" +
    "receiver[key](); trace;",
  )
  inspect(array.to_string(), content="c")
}

///|
test "runtime-string computed accessor calls preserve order before TypeError" {
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    let _ = run_executor_neutral_bytecode(
      interp,
      "var trace = ''; var key = 'step';" +
      "var receiver = { get step() { trace = trace + 'g'; return 1; } };" +
      "function argument() { trace = trace + 'a'; return 7; }" +
      "receiver[key](argument());",
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) =>
      match @runtime.js_error_to_value_with_env(error, Some(interp.global)) {
        Object(data) => inspect(data.class_name, content="TypeError")
        _ => fail("expected a JavaScript TypeError object")
      }
    None => fail("non-callable computed getter result must throw")
  }
  inspect(interp.global.get("trace").to_string(), content="ga")
}

///|
test "runtime-string computed accessor calls preserve guest throw identity" {
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    let _ = run_executor_neutral_bytecode(
      interp,
      "var marker = {}; var trace = ''; var entries = 0; var key = 'step';" +
      "var receiver = { get step() { trace = trace + 'g'; entries++;" +
      "if (entries === 1) throw marker;" +
      "return function() { trace = trace + 'c'; }; } };" +
      "receiver[key]();",
    )
    None
  } catch {
    error => Some(error)
  }
  let marker = interp.global.get("marker")
  match caught {
    Some(error) =>
      assert_true(physical_equal(@runtime.js_error_to_value(error), marker))
    None => fail("computed getter throw must reach the caller")
  }
  inspect(interp.global.get("trace").to_string(), content="g")
  let result = run_executor_neutral_bytecode(interp, "entries;")
  inspect(result.to_string(), content="1")
}

///|
test "RED: computed string literal accessor member-call reaches depth 256" {
  let source = "let remaining = 256;" +
    "let receiver = { get step() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = receiver['step']();" +
    "return function() { return next + 1; };" +
    "} };" +
    "receiver['step']();"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="256")
}

///|
test "RED: computed string literal getter recursion reaches depth 256" {
  let source = "let remaining = 256;" +
    "let receiver = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "return 1 + receiver['x'];" +
    "} };" +
    "receiver['x'];"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="256")
}

///|
test "RED: static own accessor reads lower through GetProperty" {
  let source = "let remaining = 320;" +
    "let receiver = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "return 1 + receiver.x;" +
    "} };" +
    "receiver.x;"
  let lowered = parse_bytecode_for_wb(source)
  let mut root_get = false
  for instr in lowered.main.code {
    match instr {
      GetProperty("x", _) => root_get = true
      PreparePropertyCall(_, _) | GetComputed(_) | PrepareComputedCall(_) =>
        fail("static accessor read selected another property opcode")
      _ => ()
    }
  }
  let mut getter_get = false
  for child in lowered.main.children {
    for instr in child.code {
      match instr {
        GetProperty("x", _) => getter_get = true
        PreparePropertyCall(_, _) | GetComputed(_) | PrepareComputedCall(_) =>
          fail(
            "recursive static accessor read selected another property opcode",
          )
        _ => ()
      }
    }
  }
  assert_true(root_get)
  assert_true(getter_get)
}

///|
// Pre-fix provenance: in a detached worktree at post-#740 base
// `2c6aa6632dbeae60776bc4dda8fe278efc51f9f9`, vary only `remaining` and the
// expected result in the second RED test, then run
// `moon test compiler/executor_neutral_activation_wbtest.mbt --target native`
// or `--target js` (debug, no host-stack tuning). Native passes at 252 and
// fails at 253 with signal 11 (SIGSEGV); JS passes at 71 and fails at 72 with
// `RangeError: Maximum call stack size exceeded`.
test "RED: bytecode static own accessor recursion reaches the synchronous boundary" {
  let source = "let remaining = 320;" +
    "let receiver = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "return 1 + receiver.x;" +
    "} };" +
    "receiver.x;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "RED: static compound-read getter recursion reaches depth 320" {
  let source = "let remaining = 320;" +
    "let receiver = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "receiver.x &&= 1;" +
    "return 1;" +
    "} };" +
    "receiver.x &&= 1;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="1")
}

///|
test "static compound-read getter recursion keeps shallow control" {
  let source = "let remaining = 8;" +
    "let receiver = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "receiver.x &&= 1;" +
    "return 1;" +
    "} };" +
    "receiver.x &&= 1;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="1")
}

///|
test "static compound-read lowering keeps reference reads at root and recursion" {
  let source = "let remaining = 8;" +
    "let receiver = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "receiver.x &&= 1;" +
    "return 1;" +
    "} };" +
    "receiver.x &&= 1;"
  let lowered = parse_bytecode_for_wb(source)
  let mut root_assign_read = false
  for instr in lowered.main.code {
    match instr {
      ReadPropertyForAssign("x", _) => root_assign_read = true
      _ => ()
    }
  }
  let mut recursive_assign_read = false
  for child in lowered.main.children {
    for instr in child.code {
      match instr {
        ReadPropertyForAssign("x", _) => recursive_assign_read = true
        _ => ()
      }
    }
  }
  assert_true(root_assign_read)
  assert_true(recursive_assign_read)
}

///|
test "static compound assignment preserves receiver setter order and result" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var trace = '';" +
    "var receiver = { value: 2, get x() {" +
    "trace = trace + (this === receiver ? 'g' : 'x');" +
    "return this.value;" +
    "}, set x(value) {" +
    "trace = trace + (this === receiver ? 's' : 'x');" +
    "this.value = value;" +
    "} };" +
    "var result = receiver.x += 3;" +
    "result === 5 && receiver.value === 5 && trace === 'gs';",
  )
  inspect(result.to_string(), content="true")
}

///|
test "static logical assignment short-circuits RHS and setter" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var reads = 0; var rhs = 0; var setter_calls = 0;" +
    "var receiver = { get x() { reads = reads + 1; return 0; }," +
    "set x(value) { setter_calls = setter_calls + 1; } };" +
    "var result = receiver.x &&= (rhs = 1);" +
    "result === 0 && rhs === 0 && reads === 1 && setter_calls === 0;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "static compound getter throw preserves identity and interpreter reuse" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var reads = 0; var result = 0;" +
    "var receiver = { get x() { reads = reads + 1;" +
    "if (reads === 1) throw marker; return 2; }," +
    "set x(value) { result = value; } };",
  )
  let caught : Error? = try {
    let _ = run_executor_neutral_bytecode(interp, "receiver.x += 1;")
    None
  } catch {
    error => Some(error)
  }
  let marker = interp.global.get("marker")
  match caught {
    Some(error) =>
      assert_true(physical_equal(@runtime.js_error_to_value(error), marker))
    None => fail("static compound getter throw must reach the caller")
  }
  let result = run_executor_neutral_bytecode(
    interp, "receiver.x += 1; result === 3 && reads === 2;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "static property lowering keeps non-read property families residual" {
  let lowered = parse_bytecode_for_wb(
    "function C() {}; var base = { x: 1 }; var key = 'x'; " +
    "base.x; base.x(); base[key]; base.x = 2; base.x += 1; " +
    "base.x++; delete base.x; ({ ...base }); [ ...base ]; " +
    "function child() {}; child(...base); new C(); eval('base.x');",
  )
  let mut saw_get = false
  let mut saw_plain_prepare = false
  let mut saw_computed = false
  let mut saw_assign_read = false
  let mut saw_set = false
  let mut saw_update = false
  let mut saw_delete = false
  let mut saw_object_spread = false
  let mut saw_array_spread = false
  let mut saw_arg_spread = false
  let mut saw_construct = false
  let mut saw_eval = false
  for instr in lowered.main.code {
    match instr {
      GetProperty("x", _) => saw_get = true
      PreparePlainPropertyCall("x", _) => saw_plain_prepare = true
      GetComputed(_) => saw_computed = true
      ReadPropertyForAssign("x", _) => saw_assign_read = true
      SetProperty("x", _) => saw_set = true
      UpdateProperty("x", _, _, _, _) => saw_update = true
      DeleteProperty("x") => saw_delete = true
      ObjectSpread(_) => saw_object_spread = true
      ArrayPushSpread(_) => saw_array_spread = true
      ArgPushSpread(_) => saw_arg_spread = true
      Construct(_, _) => saw_construct = true
      CallDirectEval(_) => saw_eval = true
      _ => ()
    }
  }
  assert_true(saw_get)
  assert_true(saw_plain_prepare)
  assert_true(saw_computed)
  assert_true(saw_assign_read)
  assert_true(saw_set)
  assert_true(saw_update)
  assert_true(saw_delete)
  assert_true(saw_object_spread)
  assert_true(saw_array_spread)
  assert_true(saw_arg_spread)
  assert_true(saw_construct)
  assert_true(saw_eval)
}

///|
test "bytecode static own accessor mutual recursion completes deeply" {
  let source = "let remaining = 320;" +
    "let left = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "return 1 + right.x;" +
    "} };" +
    "let right = { get x() {" +
    "if (remaining === 0) return 0;" +
    "remaining--;" +
    "return 1 + left.x;" +
    "} };" +
    "left.x;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "bytecode plain static accessor receiver calls mutually recurse deeply" {
  let source = "let remaining = 320;" +
    "let left = { get step() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = right.step();" +
    "return function() { return next + 1; };" +
    "} };" +
    "let right = { get step() {" +
    "if (remaining === 0) return function() { return 0; };" +
    "remaining--;" +
    "let next = left.step();" +
    "return function() { return next + 1; };" +
    "} };" +
    "left.step();"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "bytecode static own accessor preserves receiver and empty arguments" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "let receiver = { marker: 41, get x() {" +
    "return this === receiver && arguments.length === 0 ? this.marker : -1;" +
    "} }; receiver.x;",
  )
  inspect(result.to_string(), content="41")
}

///|
test "bytecode static own accessor preserves strict and arrow this" {
  let strict_result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "let receiver = { get x() { 'use strict'; return this === receiver; } };" +
    "receiver.x;",
  )
  inspect(strict_result.to_string(), content="true")
  let arrow_result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "let lexical = this; let getter = () => lexical; let receiver = {};" +
    "Object.defineProperty(receiver, 'x', { get: getter });" +
    "receiver.x === lexical;",
  )
  inspect(arrow_result.to_string(), content="true")
}

///|
test "bytecode static own accessor preserves returned identity" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "let receiver = { get x() { return receiver; } };" +
    "receiver.x === receiver;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "bytecode static own accessor propagates guest throw without replay" {
  let interp = @interpreter.new_interpreter()
  let caught : Error? = try {
    let _ = run_executor_neutral_bytecode(
      interp,
      "let entries = 0;" +
      "let receiver = { get x() { entries++; throw \"boom\"; } };" +
      "receiver.x;",
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(_) => ()
    None => fail("executor getter throw must reach the caller")
  }
  let result = run_executor_neutral_bytecode(interp, "entries;")
  inspect(result.to_string(), content="1")
}

///|
test "executor-neutral bytecode function keeps a classifiable runtime payload" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(interp, "function retained() {}")
  match interp.global.get("retained") {
    Object({ callable: Some(ExecutorCallable(executable)), .. }) =>
      inspect(executable.name(), content="retained")
    _ => fail("bytecode function must expose the neutral executor payload")
  }
}

///|
test "executor-neutral bytecode arrow keeps a classifiable runtime payload" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "var retainedArrow = (value) => value + 1;",
  )
  match interp.global.get("retainedArrow") {
    Object({ callable: Some(ExecutorCallable(executable)), .. }) =>
      inspect(executable.name(), content="")
    _ => fail("bytecode arrow must expose the neutral executor payload")
  }
}

///|
test "executor-neutral bytecode method activation preserves receiver" {
  let interp = @interpreter.new_interpreter()
  let result = run_executor_neutral_bytecode(
    interp,
    "function add(x) { return this.base + x; }\n" +
    "var holder = { base: 2, add: add };\n" +
    "holder.add(3);",
  )
  inspect(result.to_string(), content="5")
}

///|
test "ordinary bytecode recursive calls complete at finite depth" {
  let interp = @interpreter.new_interpreter()
  let depth = 97
  let source = "function count(n) { if (n === 0) return 0; return count(n - 1) + 1; }\n" +
    "count(" +
    depth.to_string() +
    ");"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="97")
}

///|
test "bytecode spread recursion reaches the synchronous final call boundary" {
  let source = "function count(n) { if (n === 0) return 0; " +
    "return count(n - 1, ...[]) + 1; }\n" +
    "count(321, ...[]);"
  let lowered = parse_bytecode_for_wb(source)
  let mut saw_arg_spread = false
  let mut saw_call_spread = false
  for instr in lowered.main.code {
    match instr {
      ArgPushSpread(_) => saw_arg_spread = true
      CallSpread(_) => saw_call_spread = true
      _ => ()
    }
  }
  assert_true(saw_arg_spread)
  assert_true(saw_call_spread)
  let mut saw_count_child = false
  let mut saw_recursive_arg_spread = false
  let mut saw_recursive_call_spread = false
  for child in lowered.main.children {
    match child.name {
      Some(name) if name == "count" => {
        saw_count_child = true
        for instr in child.code {
          match instr {
            ArgPushSpread(_) => saw_recursive_arg_spread = true
            CallSpread(_) => saw_recursive_call_spread = true
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  assert_true(saw_count_child)
  assert_true(saw_recursive_arg_spread)
  assert_true(saw_recursive_call_spread)
  let interp = @interpreter.new_interpreter()
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="321")
}

///|
test "spread bytecode mutual calls complete at deep finite depth" {
  let source = "function even(n) { if (n === 0) return true; " +
    "return odd(n - 1, ...[]); }\n" +
    "function odd(n) { if (n === 0) return false; " +
    "return even(n - 1, ...[]); }\n" +
    "even(2000, ...[]);"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread bytecode calls preserve ordered owned arguments" {
  let interp = @interpreter.new_interpreter()
  let result = run_executor_neutral_bytecode(
    interp,
    "var trace = ''; var extras = [2, 3];\n" +
    "function first() { trace = trace + 'f'; return 1; }\n" +
    "function last() { trace = trace + 'l'; return 4; }\n" +
    "function child(a, b, c, d) { return a * 1000 + b * 100 + c * 10 + d; }\n" +
    "child(first(), ...extras, last()) === 1234 && trace === 'fl';",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread bytecode iterator evaluation occurs exactly once" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var iterator_gets = 0; var next_calls = 0; var values = 0;\n" +
    "var iterable = {};\n" +
    "iterable[Symbol.iterator] = function() { iterator_gets = iterator_gets + 1; " +
    "var index = 0; return { next: function() { next_calls = next_calls + 1; " +
    "if (index === 0) { index = 1; values = values + 1; " +
    "return { value: 7, done: false }; } return { done: true }; } }; };\n" +
    "function child(value) { return value; }\n" +
    "child(...iterable) === 7 && iterator_gets === 1 && " +
    "next_calls === 2 && values === 1;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread bytecode calls own arguments before guest mutation" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var extras = [2, 3];\n" +
    "function child(a) { arguments[0] = 9; " +
    "return a + arguments[1] + arguments[2]; }\n" +
    "var answer = child(1, ...extras);\n" +
    "answer === 14 && extras[0] === 2 && extras[1] === 3;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread bytecode final invocation keeps tree and native fallbacks" {
  let interp = @interpreter.new_interpreter()
  let _ = interp.run(
    @parser.parse("function treeAdd(value) { return value + 1; }").stmts,
  )
  interp.global.def_builtin(
    "nativeAdd",
    @runtime.make_native_func(name="nativeAdd", args => {
      match args {
        [Number(left), Number(right)] => Number(left + right)
        _ => Value::Undefined
      }
    }),
  )
  let result = run_executor_neutral_bytecode(
    interp, "treeAdd(...[2]) + nativeAdd(...[3, 4]);",
  )
  inspect(result.to_string(), content="10")
}

///|
test "spread bytecode non-receiver calls preserve strict and sloppy this" {
  let source = "var strict_seen = false; var sloppy_seen = false;\n" +
    "function strict_child() { 'use strict'; " +
    "strict_seen = this === undefined; }\n" +
    "function sloppy_child() { sloppy_seen = this === globalThis; }\n" +
    "strict_child(...[]); sloppy_child(...[]);\n" +
    "strict_seen && sloppy_seen;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread lowering keeps receiver construct and direct-eval opcodes residual" {
  let lowered = parse_bytecode_for_wb(
    "function plain() {}; var obj = { call: function() {} }; var xs = []; " +
    "plain(...xs); obj.call(...xs); obj.call(); new Object(...xs); " +
    "eval(...xs);",
  )
  let mut saw_call_spread = false
  let mut saw_receiver = false
  let mut saw_fixed_receiver = false
  let mut saw_construct = false
  let mut saw_direct_eval = false
  for instr in lowered.main.code {
    match instr {
      CallSpread(_) => saw_call_spread = true
      CallSpreadWithReceiver(_) => saw_receiver = true
      CallWithReceiver(_, _) => saw_fixed_receiver = true
      ConstructSpread(_) => saw_construct = true
      CallDirectEval(_) => saw_direct_eval = true
      _ => ()
    }
  }
  assert_true(saw_call_spread)
  assert_true(saw_receiver)
  assert_true(saw_fixed_receiver)
  assert_true(saw_construct)
  assert_true(saw_direct_eval)
}

///|
test "spread evaluation abrupt completion does not invoke or replay" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var attempts = 0; var invoked = 0;\n" +
    "function boom() { attempts = attempts + 1; throw marker; }\n" +
    "function child() { invoked = invoked + 1; }\n" +
    "function attempt() { child(...boom()); }",
  )
  let result = interp.run(
    @parser.parse(
      "var same = false;\n" +
      "try { attempt(); } catch (error) { same = error === marker; }\n" +
      "same && attempts === 1 && invoked === 0;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread bytecode normal and guest throw results clean up once" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var calls = 0;\n" +
    "function child(mode) { calls = calls + 1; " +
    "if (mode === 1) throw marker; return 7; }\n" +
    "function invoke(mode) { return child(...[mode]); }",
  )
  let result = interp.run(
    @parser.parse(
      "var caught = false;\n" +
      "try { invoke(1); } catch (error) { caught = error === marker; }\n" +
      "caught && invoke(2) === 7 && calls === 2;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "bounded spread throw releases before a later spread leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var entered = 0;\n" +
    "function fail() { entered = entered + 1; throw marker; }\n" +
    "function caller() { fail(...[]); }\n" +
    "function leaf() { return 42; }\n" +
    "function probe() { return leaf(...[]); }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let result = interp.run_bounded(
    @parser.parse(
      "var caught = false;\n" +
      "try { caller(); } catch (error) { caught = error === marker; }\n" +
      "caught && entered === 1 ? probe() : -1;",
    ).stmts,
    policy,
  )
  inspect(result.to_string(), content="42")
}

///|
test "bounded spread rejection happens before child body" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var caller_entered = 0; var child_entered = 0;\n" +
    "function child() { child_entered = child_entered + 1; return 1; }\n" +
    "function caller() { caller_entered = caller_entered + 1; " +
    "return child(...[]); }\n" +
    "function outer() { return caller(...[]); }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = try {
    let _ = interp.run_bounded(@parser.parse("outer();").stmts, policy)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected a classified JavaScript depth exception, got " +
        error.to_string(),
      )
    None => fail("bounded spread child must be rejected before entry")
  }
  let result = interp.run(
    @parser.parse("caller_entered === 1 && child_entered === 0;").stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "bytecode receiver recursion reaches the synchronous call boundary" {
  let interp = @interpreter.new_interpreter()
  let depth = 320
  let source = "var receiver = { count: function(n) { " +
    "if (n === 0) return 0; return this.count(n - 1) + 1; } };\n" +
    "receiver.count(" +
    depth.to_string() +
    ");"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="320")
}

///|
test "bytecode receiver spread reaches the synchronous final call boundary" {
  let source = "function step(n) { if (n === 0) return this.marker; " +
    "return 1 + this.step(n - 1, ...[]); }\n" +
    "let receiver = { marker: 0, step: step };\n" +
    "receiver.step(320, ...[]);"
  let lowered = parse_bytecode_for_wb(source)
  let mut saw_main_spread = false
  let mut saw_main_receiver_call = false
  for instr in lowered.main.code {
    match instr {
      ArgPushSpread(_) => saw_main_spread = true
      CallSpreadWithReceiver(_) => saw_main_receiver_call = true
      _ => ()
    }
  }
  assert_true(saw_main_spread)
  assert_true(saw_main_receiver_call)
  let mut saw_step_child = false
  let mut saw_child_spread = false
  let mut saw_child_receiver_call = false
  for child in lowered.main.children {
    match child.name {
      Some(name) if name == "step" => {
        saw_step_child = true
        for instr in child.code {
          match instr {
            ArgPushSpread(_) => saw_child_spread = true
            CallSpreadWithReceiver(_) => saw_child_receiver_call = true
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  assert_true(saw_step_child)
  assert_true(saw_child_spread)
  assert_true(saw_child_receiver_call)
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "spread receiver calls preserve this identity and ordered arguments" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var receiver = { marker: 40 };\n" +
    "function read(first, second) { " +
    "return this === receiver && this.marker + first + second === 43; }\n" +
    "receiver.read = read; receiver.read(1, ...[2]);",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver mutual recursion completes deeply" {
  let source = "var left = 'left'; var right = 'right';\n" +
    "var receiver = { " +
    "left: function(n) { if (n === 0) return 1; " +
    "return this[right](n - 1, ...[]) + 1; }, " +
    "right: function(n) { if (n === 0) return 0; " +
    "return this[left](n - 1, ...[]) + 1; } };\n" +
    "receiver[left](2000, ...[]);"
  let lowered = parse_bytecode_for_wb(source)
  let mut saw_root_receiver_spread = false
  let mut child_receiver_spreads = 0
  for instr in lowered.main.code {
    match instr {
      CallSpreadWithReceiver(_) => saw_root_receiver_spread = true
      _ => ()
    }
  }
  for child in lowered.main.children {
    for instr in child.code {
      match instr {
        CallSpreadWithReceiver(_) => child_receiver_spreads += 1
        _ => ()
      }
    }
  }
  assert_true(saw_root_receiver_spread)
  assert_true(child_receiver_spreads >= 2)
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="2001")
}

///|
test "receiver spread materializes a custom iterator once in order" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var iterator_gets = 0; var next_calls = 0; var return_calls = 0; " +
    "var invoked = 0;\n" +
    "var receiver = { base: 40, read: function(first, second) { " +
    "invoked = invoked + 1; return this.base + first * 10 + second; } };\n" +
    "var iterable = {}; iterable[Symbol.iterator] = function() { " +
    "iterator_gets = iterator_gets + 1; var index = 0; return { " +
    "next: function() { next_calls = next_calls + 1; " +
    "if (index === 0) { index = 1; return { value: 1, done: false }; } " +
    "if (index === 1) { index = 2; return { value: 2, done: false }; } " +
    "return { done: true }; }, return: function() { " +
    "return_calls = return_calls + 1; return { done: true }; } }; };\n" +
    "receiver.read(...iterable) === 52 && iterator_gets === 1 && " +
    "next_calls === 3 && return_calls === 0 && invoked === 1;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "receiver spread iterator throw preserves identity without invocation or replay" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var iterator_gets = 0; var next_calls = 0; " +
    "var return_calls = 0; var invoked = 0;\n" +
    "var receiver = { read: function() { invoked = invoked + 1; } };\n" +
    "var iterable = {}; iterable[Symbol.iterator] = function() { " +
    "iterator_gets = iterator_gets + 1; return { next: function() { " +
    "next_calls = next_calls + 1; if (next_calls === 1) " +
    "return { value: 1, done: false }; throw marker; }, " +
    "return: function() { return_calls = return_calls + 1; " +
    "return { done: true }; } }; };\n" +
    "function attempt() { receiver.read(...iterable); }\n" +
    "function leaf() { return 42; }",
  )
  let result = interp.run(
    @parser.parse(
      "var same = false;\n" +
      "try { attempt(); } catch (error) { same = error === marker; }\n" +
      "same && iterator_gets === 1 && next_calls === 2 && " +
      "return_calls === 0 && invoked === 0 && leaf() === 42;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver preparation does not replay static lookup or arguments" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var lookups = 0; var factories = 0; var invoked = 0;\n" +
    "var receiver = { base: 40 };\n" +
    "Object.defineProperty(receiver, 'read', { get: function() { " +
    "lookups = lookups + 1; return function(value) { " +
    "invoked = invoked + 1; return this.base + value; }; } });\n" +
    "function make() { factories = factories + 1; return [2]; }\n" +
    "receiver.read(...make()) === 42 && lookups === 1 && " +
    "factories === 1 && invoked === 1;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread computed receiver preparation does not replay key or arguments" {
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    "var key_reads = 0; var factories = 0; var invoked = 0;\n" +
    "var receiver = { base: 40, read: function(value) { " +
    "invoked = invoked + 1; return this.base + value; } };\n" +
    "function key() { key_reads = key_reads + 1; return 'read'; }\n" +
    "function make() { factories = factories + 1; return [2]; }\n" +
    "receiver[key()](...make()) === 42 && key_reads === 1 && " +
    "factories === 1 && invoked === 1;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver abrupt argument evaluation preserves the thrown value" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var attempts = 0; var invoked = 0;\n" +
    "var receiver = { read: function() { invoked = invoked + 1; } };\n" +
    "function boom() { attempts = attempts + 1; throw marker; }\n" +
    "function attempt() { receiver.read(...boom()); }",
  )
  let result = interp.run(
    @parser.parse(
      "var same = false;\n" +
      "try { attempt(); } catch (error) { same = error === marker; }\n" +
      "same && attempts === 1 && invoked === 0;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver calls clean up after guest throw and resume later leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {}; var calls = 0;\n" +
    "function child(mode) { calls = calls + 1; " +
    "if (mode === 1) throw marker; return this.base + mode; }\n" +
    "var receiver = { base: 6, child: child };\n" +
    "function invoke(mode) { return receiver.child(...[mode]); }\n" +
    "function leaf() { return 42; }",
  )
  let result = interp.run(
    @parser.parse(
      "var caught = false;\n" +
      "try { invoke(1); } catch (error) { caught = error === marker; }\n" +
      "caught && invoke(2) === 8 && leaf() === 42 && calls === 2;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver logical depth rejection happens before child body" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var caller_entered = 0; var child_entered = 0;\n" +
    "function child() { child_entered = child_entered + 1; return 1; }\n" +
    "var receiver = { child: child };\n" +
    "function caller() { caller_entered = caller_entered + 1; " +
    "return receiver.child(...[]); }\n" +
    "function outer() { return caller(...[]); }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = try {
    let _ = interp.run_bounded(@parser.parse("outer();").stmts, policy)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected a classified JavaScript depth exception, got " +
        error.to_string(),
      )
    None => fail("bounded receiver spread child must be rejected before entry")
  }
  let result = interp.run(
    @parser.parse("caller_entered === 1 && child_entered === 0;").stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver runtime abrupt fallback releases before a later leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var receiver = { bad: 1 };\n" +
    "function attempt() { receiver.bad(...[]); }\n" +
    "function leaf() { return 42; }",
  )
  let result = interp.run(
    @parser.parse(
      "var caught = false;\n" +
      "try { attempt(); } catch (error) { caught = true; }\n" +
      "caught && leaf() === 42;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "spread receiver final invocation preserves tree and native fallbacks" {
  let interp = @interpreter.new_interpreter()
  let _ = interp.run(
    @parser.parse("function treeAdd(value) { return this.base + value; }").stmts,
  )
  interp.global.def_builtin(
    "nativeAdd",
    @runtime.make_native_func(name="nativeAdd", args => {
      match args {
        [Number(left), Number(right)] => Number(left + right)
        _ => Value::Undefined
      }
    }),
  )
  let result = run_executor_neutral_bytecode(
    interp,
    "var treeHolder = { base: 4, read: treeAdd };\n" +
    "var nativeHolder = { read: nativeAdd };\n" +
    "treeHolder.read(...[3]) + nativeHolder.read(...[4, 5]);",
  )
  inspect(result.to_string(), content="16")
}

///|
test "bytecode computed receiver mutual recursion completes deeply" {
  let interp = @interpreter.new_interpreter()
  let source = "var left = 'left'; var right = 'right';\n" +
    "var receiver = { " +
    "left: function(n) { if (n === 0) return 1; " +
    "return receiver[right](n - 1) + 1; }, " +
    "right: function(n) { if (n === 0) return 0; " +
    "return receiver[left](n - 1) + 1; } };\n" +
    "receiver[left](2000);"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="2001")
}

///|
test "ordinary bytecode mutual calls complete at deep finite depth" {
  let interp = @interpreter.new_interpreter()
  let source = "function even(n) { if (n === 0) return true; return odd(n - 1); }\n" +
    "function odd(n) { if (n === 0) return false; return even(n - 1); }\n" +
    "even(2000);"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="true")
}

///|
test "ordinary bytecode arrow calls complete at deep finite depth" {
  let interp = @interpreter.new_interpreter()
  let source = "var count = (n) => n === 0 ? 0 : count(n - 1) + 1;\n" +
    "count(2000);"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="2000")
}

///|
test "executor-neutral bytecode arrow receiver call keeps lexical this" {
  let interp = @interpreter.new_interpreter()
  let result = run_executor_neutral_bytecode(
    interp,
    "var expected = this; var arrow = () => this;\n" +
    "var holder = { arrow: arrow }; holder.arrow() === expected;",
  )
  inspect(result.to_string(), content="true")
}

///|
test "tree adapter trampolines nested ordinary bytecode calls" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function count(n) { if (n === 0) return 0; return count(n - 1) + 1; }",
  )
  let result = interp.run(@parser.parse("count(2000);").stmts)
  inspect(result.to_string(), content="2000")
}

///|
test "bounded compiled ordinary calls preserve the engine depth marker" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function count(n) { if (n === 0) return 0; return count(n - 1) + 1; }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = try {
    let _ = interp.run_bounded(@parser.parse("count(2);").stmts, policy)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected a classified JavaScript depth exception, got " +
        error.to_string(),
      )
    None => fail("bounded compiled recursion must reject at the depth limit")
  }
}

///|
test "ordinary bytecode call consumes its result once at the advanced IP" {
  let interp = @interpreter.new_interpreter()
  let source = "var calls = 0;\n" +
    "function child() { calls = calls + 1; return 2; }\n" +
    "function caller() { return child() + calls; }\n" +
    "caller();"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="3")
}

///|
test "bytecode frame accepts one pending activation result" {
  let interp = @interpreter.new_interpreter()
  let program = parse_bytecode_for_wb("0;")
  let frame = BytecodeFrame(program.main, interp.global, {
    strict: false,
    current_generator: None,
  })
  frame.pending_activation_result = Some(PushValue)
  @runtime.ExecutorActivationFrame::deliver_activation_completion(
    frame,
    @runtime.executor_activation_completion_normal(Number(7.0)),
  )
  inspect(frame.stack.length(), content="1")
  match frame.peek() {
    Number(value) => inspect(value, content="7")
    _ => fail("pending activation result must be pushed onto the operand stack")
  }
  let second_delivery : Error? = try {
    @runtime.ExecutorActivationFrame::deliver_activation_completion(
      frame,
      @runtime.executor_activation_completion_normal(Number(8.0)),
    )
    None
  } catch {
    error => Some(error)
  }
  match second_delivery {
    Some(@errors.InternalError(message~)) =>
      inspect(
        message,
        content="bytecode activation result has no pending consumer",
      )
    _ => fail("duplicate activation result delivery must be rejected")
  }
  inspect(frame.stack.length(), content="1")
}

///|
test "bytecode frame delivers an owned receiver with a plain property result" {
  let interp = @interpreter.new_interpreter()
  let program = parse_bytecode_for_wb("0;")
  let frame = BytecodeFrame(program.main, interp.global, {
    strict: false,
    current_generator: None,
  })
  let receiver = Value::String_("receiver")
  let callee = Value::String_("callee")
  frame.pending_activation_result = Some(PushReceiverAndValue(receiver))
  @runtime.ExecutorActivationFrame::deliver_activation_completion(
    frame,
    @runtime.executor_activation_completion_normal(callee),
  )
  inspect(frame.stack.length(), content="2")
  match frame.stack[0] {
    String_(value) => inspect(value, content="receiver")
    _ => fail("plain property delivery must push the receiver first")
  }
  match frame.stack[1] {
    String_(value) => inspect(value, content="callee")
    _ => fail("plain property delivery must push the callee second")
  }
}

///|
test "bytecode frame clears its destination before re-raising an abrupt completion" {
  let interp = @interpreter.new_interpreter()
  let program = parse_bytecode_for_wb("0;")
  let frame = BytecodeFrame(program.main, interp.global, {
    strict: false,
    current_generator: None,
  })
  frame.pending_activation_result = Some(PushValue)
  let sentinel : Error = @errors.RangeError(
    message="bytecode completion sentinel",
  )
  let caught : Error? = try {
    @runtime.ExecutorActivationFrame::deliver_activation_completion(
      frame,
      @runtime.executor_activation_completion_abrupt(sentinel),
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(error) => assert_true(physical_equal(error, sentinel))
    None => fail("bytecode frame must re-raise the original abrupt completion")
  }
  assert_true(frame.pending_activation_result is None)
  let duplicate : Error? = try {
    @runtime.ExecutorActivationFrame::deliver_activation_completion(
      frame,
      @runtime.executor_activation_completion_abrupt(sentinel),
    )
    None
  } catch {
    error => Some(error)
  }
  match duplicate {
    Some(@errors.InternalError(message~)) =>
      inspect(
        message,
        content="bytecode activation result has no pending consumer",
      )
    _ => fail("a consumed destination must reject duplicate delivery")
  }
}

///|
test "nested ordinary bytecode calls own child arguments" {
  let interp = @interpreter.new_interpreter()
  let source = "function child(value) { arguments[0] = 7; " +
    "return value + arguments.length; }\n" +
    "function caller() { return child(1, 2); }\n" +
    "caller();"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="9")
}

///|
test "nested ordinary bytecode calls preserve guest throw identity" {
  let interp = @interpreter.new_interpreter()
  let source = "var marker = {};\n" +
    "function child() { throw marker; }\n" +
    "function caller() { child(); }"
  let _ = run_executor_neutral_bytecode(interp, source)
  let result = interp.run(
    @parser.parse("try { caller(); } catch (error) { error === marker; }").stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "nested receiver bytecode calls release before a later bounded leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {};\n" +
    "var receiver = { fail: function() { throw marker; } };\n" +
    "function caller() { receiver.fail(); }\n" +
    "function leaf() { return 42; }\n" +
    "function probe() { return leaf(); }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let result = interp.run_bounded(
    @parser.parse(
      "var caught = false;\n" +
      "try { caller(); } catch (error) { caught = error === marker; }\n" +
      "caught ? probe() : -1;",
    ).stmts,
    policy,
  )
  inspect(result.to_string(), content="42")
}

///|
test "ordinary bytecode call normalizes fallthrough and arrow expression results" {
  let interp = @interpreter.new_interpreter()
  let source = "function noResult() { var local = 1; }\n" +
    "var arrow = () => 3;\n" +
    "noResult(); arrow();"
  let result = run_executor_neutral_bytecode(interp, source)
  inspect(result.to_string(), content="3")
}

///|
test "bytecode construct recursion reaches the synchronous constructor boundary" {
  let source = "function Step(n) { " +
    "if (n === 0) { this.value = 0; return; } " +
    "let child = new Step(n - 1); " +
    "this.value = child.value + 1; }\n" +
    "new Step(320).value;"
  let lowered = parse_bytecode_for_wb(source)
  let mut saw_root_construct = false
  for instr in lowered.main.code {
    match instr {
      Construct(_, _) => saw_root_construct = true
      _ => ()
    }
  }
  assert_true(saw_root_construct)
  let mut saw_step_child = false
  let mut saw_child_construct = false
  for child in lowered.main.children {
    match child.name {
      Some(name) if name == "Step" => {
        saw_step_child = true
        for instr in child.code {
          match instr {
            Construct(_, _) => saw_child_construct = true
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  assert_true(saw_step_child)
  assert_true(saw_child_construct)
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "bytecode construct spread recursion lowers and completes deeply" {
  let source = "function Step(n) { " +
    "if (n === 0) { this.value = 0; return; } " +
    "let child = new Step(...[n - 1]); " +
    "this.value = child.value + 1; }\n" +
    "new Step(...[320]).value;"
  let lowered = parse_bytecode_for_wb(source)
  let mut saw_root_arg_spread = false
  let mut saw_root_construct_spread = false
  let mut saw_root_fixed_construct = false
  let mut saw_root_call_spread = false
  let mut saw_root_receiver_spread = false
  let mut saw_root_direct_eval = false
  for instr in lowered.main.code {
    match instr {
      ArgPushSpread(_) => saw_root_arg_spread = true
      ConstructSpread(_) => saw_root_construct_spread = true
      Construct(_, _) => saw_root_fixed_construct = true
      CallSpread(_) => saw_root_call_spread = true
      CallSpreadWithReceiver(_) => saw_root_receiver_spread = true
      CallDirectEval(_) => saw_root_direct_eval = true
      _ => ()
    }
  }
  assert_true(saw_root_arg_spread)
  assert_true(saw_root_construct_spread)
  assert_false(saw_root_fixed_construct)
  assert_false(saw_root_call_spread)
  assert_false(saw_root_receiver_spread)
  assert_false(saw_root_direct_eval)
  let mut saw_step_child = false
  let mut saw_child_arg_spread = false
  let mut saw_child_construct = false
  let mut saw_child_fixed_construct = false
  let mut saw_child_call_spread = false
  let mut saw_child_receiver_spread = false
  let mut saw_child_direct_eval = false
  for child in lowered.main.children {
    match child.name {
      Some(name) if name == "Step" => {
        saw_step_child = true
        for instr in child.code {
          match instr {
            ArgPushSpread(_) => saw_child_arg_spread = true
            ConstructSpread(_) => saw_child_construct = true
            Construct(_, _) => saw_child_fixed_construct = true
            CallSpread(_) => saw_child_call_spread = true
            CallSpreadWithReceiver(_) => saw_child_receiver_spread = true
            CallDirectEval(_) => saw_child_direct_eval = true
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  assert_true(saw_step_child)
  assert_true(saw_child_arg_spread)
  assert_true(saw_child_construct)
  assert_false(saw_child_fixed_construct)
  assert_false(saw_child_call_spread)
  assert_false(saw_child_receiver_spread)
  assert_false(saw_child_direct_eval)
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "bytecode construct spread mutual recursion completes deeply" {
  let source = "function Left(n) { " +
    "if (n === 0) { this.value = 0; return; } " +
    "let child = new Right(...[n - 1]); " +
    "this.value = child.value + 1; }\n" +
    "function Right(n) { " +
    "if (n === 0) { this.value = 0; return; } " +
    "let child = new Left(...[n - 1]); " +
    "this.value = child.value + 1; }\n" +
    "new Left(...[320]).value;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "bytecode construct spread preserves activation and replacement semantics" {
  let source = "let closed = 5;\n" +
    "function C(a, b) { " +
    "this.self = this; this.sum = a + b + closed; " +
    "this.same = new.target === C; " +
    "this.args = arguments.length === 2 && arguments[0] === a && " +
    "arguments[1] === b; " +
    "if (a === 1) return { replaced: 9 }; return 7; }\n" +
    "var kept = new C(...[2, 3]); " +
    "var replacement = new C(...[1, 2]);\n" +
    "kept.sum === 10 && kept.self === kept && kept.same && kept.args && " +
    "Object.getPrototypeOf(kept) === C.prototype && " +
    "kept !== replacement && replacement.replaced === 9;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="true")
}

///|
test "bytecode construct spread drains iterator effects once before entry" {
  let source = "var log = ''; var entered = 0; " +
    "var iterator_return_calls = 0;\n" +
    "function C(value) { entered = entered + 1; log = log + 'b'; " +
    "this.value = value; }\n" +
    "function makeIterable() { log = log + 'a'; var iterable = {}; " +
    "iterable[Symbol.iterator] = function() { log = log + 'i'; " +
    "var index = 0; var iterator = { next: function() { " +
    "log = log + 'n'; if (index === 0) { index = 1; " +
    "var result = { done: false }; Object.defineProperty(result, 'value', " +
    "{ get: function() { log = log + 'v'; return 7; } }); " +
    "return result; } return { done: true }; } }; " +
    "iterator.return = function() { iterator_return_calls = " +
    "iterator_return_calls + 1; log = log + 'r'; }; return iterator; }; " +
    "return iterable; }\n" +
    "var value = new (log = log + 'c', C)(...makeIterable());\n" +
    "value.value === 7 && entered === 1 && log === 'cainvnb' && " +
    "iterator_return_calls === 0;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="true")
}

///|
test "bytecode construct spread iterator abrupt preserves identity" {
  let source = "var marker = {}; var entered = 0; var iterator_gets = 0; " +
    "var next_calls = 0; var iterator_return_calls = 0;\n" +
    "var iterable = {}; iterable[Symbol.iterator] = function() { " +
    "iterator_gets = iterator_gets + 1; var iterator = {}; " +
    "iterator.next = function() { next_calls = next_calls + 1; " +
    "throw marker; }; iterator.return = function() { " +
    "iterator_return_calls = iterator_return_calls + 1; }; return iterator; };\n" +
    "function C() { entered = entered + 1; }\n" +
    "function invoke() { new C(...iterable); }"
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(interp, source)
  let result = interp.run(
    @parser.parse(
      "var same = false; try { invoke(); } catch (error) { " +
      "same = error === marker; }\n" +
      "same && iterator_gets === 1 && next_calls === 1 && " +
      "iterator_return_calls === 0 && entered === 0;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "bytecode construct spread throw releases before a later leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {};\n" +
    "function Inner() { throw marker; }\n" +
    "function Outer() { new Inner(...[]); }\n" +
    "function invokeThrow() { new Outer(...[]); }\n" +
    "function Leaf() { this.value = 42; }\n" +
    "function laterLeaf() { return new Leaf(...[]).value; }",
  )
  let result = interp.run(
    @parser.parse(
      "var caught = false; " +
      "try { invokeThrow(); } catch (error) { caught = error === marker; } " +
      "caught ? laterLeaf() : -1;",
    ).stmts,
  )
  inspect(result.to_string(), content="42")
}

///|
test "bytecode construct spread depth rejection releases before a later leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var innerEntered = 0;\n" +
    "function Inner() { innerEntered = innerEntered + 1; }\n" +
    "function Outer() { new Inner(...[]); }\n" +
    "function invokeDepth() { new Outer(...[]); }\n" +
    "function Leaf() { this.value = 42; }\n" +
    "function laterLeaf() { return new Leaf(...[]).value; }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = try {
    let _ = interp.run_bounded(@parser.parse("invokeDepth();").stmts, policy)
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected a classified JavaScript depth exception, got " +
        error.to_string(),
      )
    None => fail("bounded spread constructor must be rejected before entry")
  }
  let result = interp.run(
    @parser.parse("innerEntered === 0 ? laterLeaf() : -1;").stmts,
  )
  inspect(result.to_string(), content="42")
}

///|
test "bytecode construct spread preserves bound proxy native and arrow fallbacks" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "function C(x) { this.x = x; }\n" +
    "var Bound = C.bind(null, 4);\n" +
    "var proxyCalls = 0;\n" +
    "var ProxyCtor = new Proxy(C, { construct: function(target, args) { " +
    "proxyCalls = proxyCalls + 1; return { x: args[0] + 1 }; } });\n" +
    "var arrow = () => 1;\n" +
    "var boundValue = new Bound(...[]);\n" +
    "var proxyValue = new ProxyCtor(...[5]);\n" +
    "var nativeValue = new Object(...[7]);\n" +
    "function invokeArrow() { new arrow(...[]); }",
  )
  let result = interp.run(
    @parser.parse(
      "var nonConstructableError = false; " +
      "try { invokeArrow(); } catch (error) { " +
      "nonConstructableError = error instanceof TypeError; } " +
      "boundValue.x + proxyValue.x + proxyCalls + Number(nativeValue) + " +
      "(nonConstructableError ? 1 : 0);",
    ).stmts,
  )
  inspect(result.to_string(), content="19")
}

///|
test "bytecode mutual constructor recursion stays on the activation stack" {
  let source = "function Left(n) { " +
    "if (n === 0) { this.value = 0; return; } " +
    "let child = new Right(n - 1); " +
    "this.value = child.value + 1; }\n" +
    "function Right(n) { " +
    "if (n === 0) { this.value = 0; return; } " +
    "let child = new Left(n - 1); " +
    "this.value = child.value + 1; }\n" +
    "new Left(320).value;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="320")
}

///|
test "bytecode construct suspension preserves setup and completion semantics" {
  let source = "var closed = 5;\n" +
    "function C(a, b) { " +
    "this.sum = a + b + closed; " +
    "this.same = new.target === C; " +
    "if (a === 1) return { replaced: 9 }; " +
    "return 7; }\n" +
    "var kept = new C(2, 3); " +
    "var replacement = new C(1, 2); " +
    "kept.sum + (kept.same ? 100 : 0) + " +
    "(Object.getPrototypeOf(kept) === C.prototype ? 10 : 0) + " +
    "replacement.replaced;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="129")
}

///|
test "bytecode construct evaluates operands once before suspended entry" {
  let source = "var log = ''; var entered = 0;\n" +
    "function C(a, b) { entered = entered + 1; log = log + 'b'; " +
    "this.value = a + b; }\n" +
    "function arg(value) { log = log + value; return 1; }\n" +
    "new (log = log + 'c', C)(arg('a'), arg('z'));\n" +
    "log + ':' + entered;"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="cazb:1")
}

///|
test "bytecode construct abrupt argument prevents suspended body entry" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var entered = 0; var marker = {};\n" +
    "function C(value) { entered = entered + 1; this.value = value; }\n" +
    "function boom() { throw marker; }\n" +
    "function invoke() { new C(boom()); }",
  )
  let result = interp.run(
    @parser.parse(
      "var caught = false; " +
      "try { invoke(); } catch (error) { caught = error === marker; } " +
      "caught && entered === 0;",
    ).stmts,
  )
  inspect(result.to_string(), content="true")
}

///|
test "bytecode nested constructor throw releases before a later leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var marker = {};\n" +
    "function Inner() { throw marker; }\n" +
    "function Outer() { new Inner(); }\n" +
    "function invokeThrow() { new Outer(); }\n" +
    "function Leaf() { this.value = 42; }\n" +
    "function laterLeaf() { return new Leaf().value; }",
  )
  let result = interp.run(
    @parser.parse(
      "var caught = false; " +
      "try { invokeThrow(); } catch (error) { caught = error === marker; } " +
      "caught ? laterLeaf() : -1;",
    ).stmts,
  )
  inspect(result.to_string(), content="42")
}

///|
test "bytecode constructor depth rejection releases before a later leaf" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "var innerEntered = 0;\n" +
    "function Inner() { innerEntered = innerEntered + 1; }\n" +
    "function Outer() { new Inner(); }\n" +
    "function invokeDepth() { new Outer(); }\n" +
    "function Leaf() { this.value = 42; }\n" +
    "function laterLeaf() { return new Leaf().value; }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let result = interp.run_bounded(
    @parser.parse(
      "var caught = false; " +
      "try { invokeDepth(); } catch (error) { caught = true; } " +
      "caught && innerEntered === 0 ? laterLeaf() : -1;",
    ).stmts,
    policy,
  )
  inspect(result.to_string(), content="42")
}

///|
test "bytecode construct keeps residual constructor families synchronous" {
  let source = "function C(x) { this.x = x; }\n" +
    "var Bound = C.bind(null, 4);\n" +
    "var proxyCalls = 0;\n" +
    "var ProxyCtor = new Proxy(C, { construct: function(target, args) { " +
    "proxyCalls = proxyCalls + 1; return { x: args[0] + 1 }; } });\n" +
    "var boundValue = new Bound();\n" +
    "var proxyValue = new ProxyCtor(5);\n" +
    "var nativeValue = new Object(7);\n" +
    "boundValue.x + proxyValue.x + proxyCalls + Number(nativeValue);"
  let result = run_executor_neutral_bytecode(
    @interpreter.new_interpreter(),
    source,
  )
  inspect(result.to_string(), content="18")
}

///|
test "executor-neutral bytecode activation preserves construct and new.target" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function C(x) { this.x = x; this.same = new.target === C; }",
  )
  let result = interp.run(
    @parser.parse("var value = new C(7); value.x + (value.same ? 1 : 0);").stmts,
  )
  inspect(result.to_string(), content="8")
}

///|
test "executor-neutral bytecode activation preserves arguments aliasing" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function f(a) { arguments[0] = 7; return a + arguments.length; }",
  )
  let result = interp.run(@parser.parse("f(1, 2);").stmts)
  inspect(result.to_string(), content="9")
}

///|
// Direct calls keep the sloppy undefined/global fallback; an undefined member
// base cannot form CallWithReceiver, so primitive member normalization is
// covered by the test below.
test "executor-neutral bytecode activation preserves strict and sloppy this" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp,
    "function sloppy() { return this === globalThis; }\n" +
    "function strict() { 'use strict'; return this === undefined; }",
  )
  let result = interp.run(@parser.parse("sloppy() && strict();").stmts)
  inspect(result.to_string(), content="true")
}

///|
test "executor-neutral primitive receiver calls normalize strict and sloppy this" {
  let lowered = parse_bytecode_for_wb("(7).receiver_730_strict();")
  let mut saw_receiver_call = false
  for instr in lowered.main.code {
    match instr {
      CallWithReceiver(_, _) => saw_receiver_call = true
      _ => ()
    }
  }
  guard saw_receiver_call else {
    fail("primitive member call must lower to CallWithReceiver")
  }
  let interp = @interpreter.new_interpreter()
  let result = run_executor_neutral_bytecode(
    interp,
    "Number.prototype.receiver_730_strict = function() { 'use strict'; " +
    "return typeof this + ':' + String(this); };\n" +
    "Number.prototype.receiver_730_sloppy = function() { " +
    "return this instanceof Number; };\n" +
    "String.prototype.receiver_730_strict = function() { 'use strict'; " +
    "return typeof this + ':' + String(this); };\n" +
    "String.prototype.receiver_730_sloppy = function() { " +
    "return this instanceof String; };\n" +
    "(7).receiver_730_strict() + '|' + " +
    "(7).receiver_730_sloppy() + '|' + " +
    "('x').receiver_730_strict() + '|' + " +
    "('x').receiver_730_sloppy();",
  )
  inspect(result.to_string(), content="number:7|true|string:x|true")
}

///|
test "executor-neutral mixed tree to bytecode call preserves receiver" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function bytecodeAdd(x) { return this.base + x; }",
  )
  let tree = @parser.parse("bytecodeAdd.call({ base: 4 }, 3);")
  let result = interp.run(tree.stmts)
  inspect(result.to_string(), content="7")
}

///|
test "executor-neutral mixed bytecode to tree call preserves return" {
  let interp = @interpreter.new_interpreter()
  let tree = @parser.parse("function treeAdd(x) { return this.base + x; }")
  let _ = interp.run(tree.stmts)
  let result = run_executor_neutral_bytecode(
    interp, "treeAdd.call({ base: 5 }, 3);",
  )
  inspect(result.to_string(), content="8")
}

///|
test "mixed bytecode and tree calls complete at deep finite depth" {
  let interp = @interpreter.new_interpreter()
  let tree = @parser.parse(
    "function treeStep(n) { " +
    "if (n === 0) return 0; return bytecodeStep(n - 1) + 1; }",
  )
  let _ = interp.run(tree.stmts)
  let result = run_executor_neutral_bytecode(
    interp,
    "function bytecodeStep(n) { " +
    "if (n === 0) return 0; return treeStep(n - 1) + 1; } " +
    "bytecodeStep(2000);",
  )
  inspect(result.to_string(), content="2000")
}

///|
test "mixed tree activation is structural and independent of call depth" {
  for depth in [1, 2, 3, 17] {
    let interp = @interpreter.new_interpreter()
    let tree = @parser.parse(
      "function renamedTree(value) {\n" +
      "  if ((value === 0)) { return 0; }\n" +
      "  return renamedBytecode((value - 1)) + 1;\n" +
      "}",
    )
    let _ = interp.run(tree.stmts)
    let result = run_executor_neutral_bytecode(
      interp,
      "function renamedBytecode(value) { " +
      "if (value === 0) return 0; " +
      "return renamedTree(value - 1) + 1; } " +
      "renamedBytecode(\{depth});",
    )
    inspect(result.to_string(), content=depth.to_string())
  }
}

///|
test "mixed tree activation admits one child and consumes its completion exactly once" {
  let interp = @interpreter.new_interpreter()
  let tree = @parser.parse(
    "function treeSingle(n) { return bytecodeLeaf(n) + 1; }",
  )
  let _ = interp.run(tree.stmts)
  let _ = run_executor_neutral_bytecode(
    interp, "function bytecodeLeaf(n) { return n; }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 0L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let admission : Error? = try {
    let _ = interp.with_execution_policy(policy, () => {
      run_executor_neutral_bytecode(interp, "treeSingle(3);")
    })
    None
  } catch {
    error => Some(error)
  }
  match admission {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected admitted tree activation to reach the depth bound, got " +
        error.to_string(),
      )
    None => fail("the single-call tree fixture must be admitted")
  }
  let result = run_executor_neutral_bytecode(interp, "treeSingle(3);")
  inspect(result.to_string(), content="4")
}

///|
test "mixed tree activation admits a static own-data member call" {
  let interp = @interpreter.new_interpreter()
  let tree = @parser.parse(
    "function inner(n) { return n + 1; } " +
    "function outer(n) { return n + 1; } " +
    "var holder = { outer: outer }; " +
    "function treeMember(n) { return holder.outer(inner(n)); }",
  )
  let _ = interp.run(tree.stmts)
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 0L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let admission : Error? = try {
    let _ = interp.with_execution_policy(policy, () => {
      run_executor_neutral_bytecode(interp, "treeMember(3);")
    })
    None
  } catch {
    error => Some(error)
  }
  match admission {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected admitted member call to reach the depth bound, got " +
        error.to_string(),
      )
    None => fail("the static own-data member call fixture must be admitted")
  }
  let result = run_executor_neutral_bytecode(interp, "treeMember(3);")
  inspect(result.to_string(), content="5")
}

///|
test "mixed tree activation admits an exact literal-computed own-data member call" {
  let interp = @interpreter.new_interpreter()
  let tree = @parser.parse(
    "function inner(n) { return n + 1; } " +
    "function outer(n) { return n + 1; } " +
    "var holder = { outer: outer }; " +
    "function treeComputedMember(n) { " +
    "return holder[\"outer\"](inner(n)); }",
  )
  let _ = interp.run(tree.stmts)
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 0L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let admission : Error? = try {
    let _ = interp.with_execution_policy(policy, () => {
      run_executor_neutral_bytecode(interp, "treeComputedMember(3);")
    })
    None
  } catch {
    error => Some(error)
  }
  match admission {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected admitted literal-computed member call to reach the depth bound, got " +
        error.to_string(),
      )
    None =>
      fail(
        "the exact literal-computed own-data member fixture must be admitted",
      )
  }
  let result = run_executor_neutral_bytecode(interp, "treeComputedMember(3);")
  inspect(result.to_string(), content="5")
}

///|
test "mixed tree activation propagates child depth rejection and permits reuse" {
  let interp = @interpreter.new_interpreter()
  let _ = interp.run(
    @parser.parse("function treeCaller(n) { return bytecodeLeaf(n - 1) + 1; }").stmts,
  )
  let _ = run_executor_neutral_bytecode(
    interp, "function bytecodeLeaf(n) { return n; }",
  )
  let policy = match
    @runtime.ExecutionPolicy::new(100000L, 1L, @runtime.InterruptionHandle()) {
    Ok(policy) => policy
    Err(_) => fail("expected a valid bounded policy")
  }
  let caught : Error? = try {
    let _ = interp.with_execution_policy(policy, () => {
      run_executor_neutral_bytecode(interp, "treeCaller(1);")
    })
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@runtime.JsException(value)) =>
      assert_true(@runtime.is_engine_stack_depth_error(value))
    Some(error) =>
      fail(
        "expected a classified child depth rejection, got " + error.to_string(),
      )
    None => fail("the admitted tree child must propagate its depth rejection")
  }
  let reused = run_executor_neutral_bytecode(interp, "treeCaller(1);")
  inspect(reused.to_string(), content="1")
}

///|
test "executor-neutral foreign realm receiver call preserves this" {
  let callee_interp = @interpreter.new_interpreter()
  let caller_interp = @interpreter.new_interpreter()
  let foreign_read = run_executor_neutral_bytecode(
    callee_interp, "function read() { return this.tag; } read;",
  )
  caller_interp.global.def_builtin("foreignRead", foreign_read)
  let result = run_executor_neutral_bytecode(
    caller_interp, "var holder = { tag: 'foreign-ok', read: foreignRead }; holder.read();",
  )
  inspect(result.to_string(), content="foreign-ok")
}

///|
test "executor-neutral bytecode to native call preserves arguments" {
  let interp = @interpreter.new_interpreter()
  interp.global.def_builtin(
    "nativeAdd",
    @runtime.make_native_func(name="nativeAdd", args => {
      match args {
        [Number(left), Number(right)] => Number(left + right)
        _ => Undefined
      }
    }),
  )
  let result = run_executor_neutral_bytecode(interp, "nativeAdd(2, 3);")
  inspect(result.to_string(), content="5")
}

///|
test "executor-neutral fixed receiver call falls back for native targets" {
  let interp = @interpreter.new_interpreter()
  interp.global.def_builtin(
    "nativeRead",
    @runtime.make_native_func(name="nativeRead", _args => {
      Value::String_("native-ok")
    }),
  )
  let result = run_executor_neutral_bytecode(
    interp, "var holder = { read: nativeRead }; holder.read();",
  )
  inspect(result.to_string(), content="native-ok")
}

///|
test "executor-neutral foreign constructor keeps callee realm prototype" {
  let callee_interp = @interpreter.new_interpreter()
  let caller_interp = @interpreter.new_interpreter()
  let ctor_value = run_executor_neutral_bytecode(
    callee_interp, "function C() {} C.prototype = 1; C;",
  )
  caller_interp.global.def_builtin("ForeignCtor", ctor_value)
  let instance = caller_interp.run(@parser.parse("new ForeignCtor();").stmts)
  guard instance is Object(instance_data) else {
    fail("expected executor-neutral constructor to return an object")
  }
  let callee_proto = @runtime.get_obj_proto(
    realm_state=Some(callee_interp.realm_state),
  )
  let caller_proto = @runtime.get_obj_proto(
    realm_state=Some(caller_interp.realm_state),
  )
  assert_true(physical_equal(instance_data.prototype, callee_proto))
  assert_false(physical_equal(instance_data.prototype, caller_proto))
}

///|
test "executor-neutral bytecode throw is caught by tree caller" {
  let interp = @interpreter.new_interpreter()
  let _ = run_executor_neutral_bytecode(
    interp, "function bytecodeThrow() { throw 9; }",
  )
  let tree = @parser.parse(
    "try { bytecodeThrow(); } catch (error) { error + 1; }",
  )
  let result = interp.run(tree.stmts)
  inspect(result.to_string(), content="10")
}
