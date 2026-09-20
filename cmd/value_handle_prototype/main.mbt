///|
// THROWAWAY executable observations, not permanent product tests.
fn error_code(error : Error) -> String {
  match error {
    @js.ProbeTypeError::ExpectedNumber => "expected-number"
    @js.ProbeOwnerError::ForeignValue => "foreign-value"
    @js.ExecutionSessionError::SessionBusy => "busy"
    @js.ExecutionSessionError::SessionClosed => "closed"
    @js.ExecutionSessionError::SessionFaulted => "faulted"
    @js.ExecutionSessionError::HostFailure(..) => "host-failure"
    @js.ExecutionSessionError::ExecutionFailure(diagnostic) =>
      diagnostic.failure_kind_code()
    _ => error.to_string()
  }
}

///|
fn rejected(action : () -> Unit raise, expected : String) -> String raise {
  let observed = try {
    action()
    "unexpected-success"
  } catch {
    error => error_code(error)
  }
  assert_eq(observed, expected)
  observed
}

///|
fn run(name : String) -> Json raise {
  match name {
    "retained-host-object" => {
      let calls = Ref(0)
      let js = @js.ProbeRuntime(functions={
        "hostDouble": (vm, args) => {
          calls.val += 1
          vm.number(args[0].expect_number() * 2)
        },
      })
      let source =
        #|if(globalThis.hostDouble!==hostDouble || !(hostDouble instanceof Function)) throw new Error("registration");
        #|var counter={n:0,next(){ return hostDouble(++this.n); }};
      js.evaluate(source)
      let counter = js.global("counter")
      let first = counter.call_method("next", []).expect_number()
      let second = counter.call_method("next", []).expect_number()
      js.evaluate("counter={n:100,next(){return ++this.n;}};")
      let retained = counter.call_method("next", []).expect_number()
      let replacement = js
        .global("counter")
        .call_method("next", [])
        .expect_number()
      assert_eq(first, 2.0)
      assert_eq(second, 4.0)
      assert_eq(retained, 6.0)
      assert_eq(replacement, 101.0)
      assert_eq(calls.val, 3)
      {
        "values": [first, second, retained],
        "replacement": replacement,
        "host_calls": calls.val,
        "state": js.state(),
      }
    }
    "strict-versus-coerce" => {
      let js = @js.ProbeRuntime()
      js.evaluate(
        "var touched=0; var box={valueOf(){touched++;return 42;}}; var text='42';",
      )
      let box = js.global("box")
      let error = rejected(() => ignore(box.expect_number()), "expected-number")
      assert_eq(js.global("touched").expect_number(), 0.0)
      ignore(
        rejected(
          () => ignore(js.global("text").expect_number()),
          "expected-number",
        ),
      )
      let converted = box.coerce_number()
      assert_eq(converted, 42.0)
      assert_eq(js.global("text").coerce_number(), 42.0)
      assert_eq(js.global("touched").expect_number(), 1.0)
      {
        "strict_error": error,
        "strict_side_effects": 0,
        "coerced": converted,
        "coercion_side_effects": 1,
        "state": js.state(),
      }
    }
    "host-type-error" => {
      let js = @js.ProbeRuntime(functions={
        "numberOnly": (vm, args) => vm.number(args[0].expect_number()),
      })
      js.evaluate(
        "var caught=0; try{numberOnly('42')}catch(e){if(e instanceof TypeError)caught=1;} var valid=numberOnly(7);",
      )
      assert_eq(js.global("caught").expect_number(), 1.0)
      assert_eq(js.global("valid").expect_number(), 7.0)
      {
        "js_caught_type_error": true,
        "subsequent_value": 7,
        "state": js.state(),
      }
    }
    "host-failure" => {
      let js = @js.ProbeRuntime(functions={
        "broken": (_vm, _args) => fail("database unavailable"),
      })
      let error = rejected(
        () => js.evaluate("try{broken()}catch(e){}"),
        "host-failure",
      )
      let subsequent = rejected(() => js.evaluate("1"), "faulted")
      let other = @js.ProbeRuntime()
      other.evaluate("var value=42;")
      assert_eq(other.global("value").expect_number(), 42.0)
      {
        "error": error,
        "subsequent": subsequent,
        "state": js.state(),
        "other_session": other.state(),
      }
    }
    "closed-handles" => {
      let js = @js.ProbeRuntime()
      js.evaluate("var object={next(){return 1;}};")
      let object = js.global("object")
      let number = object.call_method("next", [])
      js.close()
      let inspect_error = rejected(
        () => ignore(number.expect_number()),
        "closed",
      )
      let call_error = rejected(
        () => ignore(object.call_method("next", [])),
        "closed",
      )
      { "inspection": inspect_error, "call": call_error, "state": js.state() }
    }
    "foreign-handles" => {
      let js = @js.ProbeRuntime()
      let other = @js.ProbeRuntime()
      js.evaluate(
        "var touched=0; var object={get method(){touched++;return function(x){return x;}}};",
      )
      let object = js.global("object")
      let foreign = other.number(2)
      let error = rejected(
        () => ignore(object.call_method("method", [foreign])),
        "foreign-value",
      )
      assert_eq(js.global("touched").expect_number(), 0.0)
      let function = object.get("method")
      ignore(
        rejected(
          () => ignore(function.call_with_this(foreign, [])),
          "foreign-value",
        ),
      )
      {
        "argument_error": error,
        "getter_ran_before_rejection": false,
        "receiver_rejected": true,
        "state": js.state(),
      }
    }
    "reentry" => {
      let observed = Ref("")
      let js = @js.ProbeRuntime(functions={
        "reenter": (vm, _args) => {
          observed.val = rejected(
            () => vm.evaluate("throw new Error('must not run')"),
            "busy",
          )
          vm.number(7)
        },
      })
      js.evaluate("var result=reenter();")
      assert_eq(js.global("result").expect_number(), 7.0)
      { "nested": observed.val, "outer_result": 7, "state": js.state() }
    }
    "method-turn-order" => {
      let js = @js.ProbeRuntime()
      js.evaluate(
        "var phase=0; var object={get method(){Promise.resolve().then(()=>{phase=10;});return function(){return phase;};}};",
      )
      let object = js.global("object")
      let combined = object.call_method("method", []).expect_number()
      let after = js.global("phase").expect_number()
      js.evaluate("phase=0;")
      let function = object.get("method")
      let separate = function.call_with_this(object, []).expect_number()
      assert_eq(combined, 0.0)
      assert_eq(after, 10.0)
      assert_eq(separate, 10.0)
      {
        "atomic_get_and_call": combined,
        "after_checkpoint": after,
        "separate_get_then_call": separate,
        "state": js.state(),
      }
    }
    "saved-function" => {
      let js = @js.ProbeRuntime()
      js.evaluate("var object={method(){return 1;}};")
      let object = js.global("object")
      let saved = object.get("method")
      js.evaluate("object.method=function(){return 2;};")
      let current = object.call_method("method", []).expect_number()
      let previous = saved.call_with_this(object, []).expect_number()
      assert_eq(current, 2.0)
      assert_eq(previous, 1.0)
      {
        "live_property": current,
        "saved_function": previous,
        "state": js.state(),
      }
    }
    "coercion-exception" => {
      let js = @js.ProbeRuntime()
      js.evaluate(
        "var box={valueOf(){throw new TypeError('no conversion');}}; var good=9;",
      )
      let box = js.global("box")
      let error = rejected(
        () => ignore(box.coerce_number()),
        "javascript-exception",
      )
      assert_eq(js.global("good").expect_number(), 9.0)
      { "error": error, "state": js.state(), "subsequent_value": 9 }
    }
    _ => fail("unknown scenario: " + name)
  }
}

///|
fn main raise {
  let args = @env.args()
  let names = [
    "retained-host-object", "strict-versus-coerce", "host-type-error", "host-failure",
    "closed-handles", "foreign-handles", "reentry", "method-turn-order", "saved-function",
    "coercion-exception",
  ]
  let selected = if args.length() == 2 { [args[1]] } else { names }
  for name in selected {
    let report : Json = { "scenario": name, "observation": run(name) }
    println(report.stringify())
  }
}
