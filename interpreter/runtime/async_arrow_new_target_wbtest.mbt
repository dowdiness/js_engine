///|
fn async_arrow_new_target_run_output(
  source : String,
) -> Array[String] raise Error {
  let interp = Interpreter::new()
  try {
    let _ = interp.run(@parser.parse(source).stmts)
    interp.host.output
  } catch {
    JsException(value) =>
      fail("unexpected JavaScript exception: " + value.to_string())
    error => fail("unexpected runtime error: " + error.to_string())
  }
}

///|
fn async_arrow_new_target_run_pending_output(
  source : String,
) -> Array[String] raise Error {
  let interp = Interpreter::new()
  let pending_data = new_promise_data()
  interp.global.def_builtin("pending", Promise(pending_data))
  try {
    let _ = interp.run(@parser.parse(source).stmts)
    fulfill_promise(interp, pending_data, Number(42.0))
    interp.run_microtasks()
    interp.host.output
  } catch {
    JsException(value) =>
      fail("unexpected JavaScript exception: " + value.to_string())
    error => fail("unexpected runtime error: " + error.to_string())
  }
}

///|
test "async arrow default parameter inherits constructor new target" {
  let output = async_arrow_new_target_run_output(
    (
      #|let expected;
      #|function Factory() {
      #|  expected = new.target;
      #|  let arrow = async (seen = new.target === expected) => {
      #|    console.log(seen);
      #|    console.log(new.target === expected);
      #|  };
      #|  arrow();
      #|}
      #|new Factory();
    ),
  )
  json_inspect(output, content=["true", "true"])
}

///|
test "async arrow retains constructor new target after await" {
  let output = async_arrow_new_target_run_pending_output(
    (
      #|let expected;
      #|function Factory() {
      #|  expected = new.target;
      #|  let arrow = async () => {
      #|    await pending;
      #|    console.log(new.target === expected);
      #|  };
      #|  arrow();
      #|}
      #|new Factory();
    ),
  )
  json_inspect(output, content=["true"])
}

///|
test "derived async arrow super await keeps new target and base state" {
  let output = async_arrow_new_target_run_pending_output(
    (
      #|class Base {
      #|  constructor(value) { this.base = value; }
      #|}
      #|class Derived extends Base {
      #|  constructor() {
      #|    let arrow = async () => {
      #|      super(await pending);
      #|      console.log(this.base === 42);
      #|      console.log(this instanceof Derived);
      #|      console.log(new.target === Derived);
      #|    };
      #|    return arrow();
      #|  }
      #|}
      #|new Derived();
    ),
  )
  json_inspect(output, content=["true", "true", "true"])
}

///|
test "nested ordinary async and sync generator keep undefined new target" {
  let output = async_arrow_new_target_run_output(
    (
      #|function Factory() {
      #|  let ordinary = async function() {
      #|    console.log(new.target === undefined);
      #|  };
      #|  let generator = function*() { yield new.target; };
      #|  ordinary();
      #|  console.log(generator().next().value === undefined);
      #|}
      #|new Factory();
    ),
  )
  json_inspect(output, content=["true", "true"])
}
