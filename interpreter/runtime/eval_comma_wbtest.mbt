///|
fn comma_test_loc() -> @token.Loc {
  @token.Loc::default()
}

///|
fn comma_test_number(value : Double, loc : @token.Loc) -> @ast.Expr {
  @ast.Expr::NumberLit(value, @token.LexForm::LexNormal, loc)
}

///|
fn comma_test_ident(name : String, loc : @token.Loc) -> @ast.Expr {
  @ast.Expr::Ident(name, loc)
}

///|
fn comma_test_comma(
  left : @ast.Expr,
  right : @ast.Expr,
  loc : @token.Loc,
) -> @ast.Expr {
  @ast.Expr::Comma(left, right, loc)
}

///|
fn comma_test_record_call(label : String, loc : @token.Loc) -> @ast.Expr {
  @ast.Expr::Call(
    @ast.Expr::Ident("record", loc),
    [@ast.Expr::StringLit(label, false, @token.LexForm::LexNormal, loc)],
    loc,
  )
}

///|
fn comma_test_eval(
  interp : Interpreter,
  expr : @ast.Expr,
  ctx? : ExecContext = { strict: false, current_generator: None },
) -> Value raise Error {
  interp.eval_expr(ctx, expr, interp.global)
}

///|
fn comma_test_eval_with_control(
  interp : Interpreter,
  expr : @ast.Expr,
  ctx : ExecContext,
  control : ExecutionControl,
) -> Value raise Error {
  interp.with_execution_control(control, () => {
    interp.eval_expr(ctx, expr, interp.global)
  })
}

///|
fn comma_test_recorder(
  interp : Interpreter,
  events : Array[String],
) -> Unit raise Error {
  let recorder : Value = make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("comma-test-recorder", args => {
        match args {
          [String_(label)] => {
            events.push(label)
            Undefined
          }
          _ =>
            raise @errors.TypeError(
              message="comma test recorder received the wrong arguments",
            )
        }
      }),
    ),
    "Function",
    Map([]),
    true,
  )
  interp.global.def("record", recorder, VarBinding)
}

///|
fn comma_test_resuming_generator(
  interp : Interpreter,
) -> GeneratorObject raise Error {
  let program = @parser.parse("function* g() {}").stmts
  ignore(interp.run(program))
  let generator = interp.call_value(
    interp.global.get("g"),
    Undefined,
    [],
    comma_test_loc(),
  )
  match get_generator_object(interp, generator) {
    Some(gen) => {
      gen.resuming = true
      gen
    }
    None => fail("expected a generator object")
  }
}

///|
test "direct comma left right and mixed shapes preserve effect order" {
  let interp = Interpreter::new()
  let events : Array[String] = []
  comma_test_recorder(interp, events)
  let loc = comma_test_loc()
  let left_nested = comma_test_comma(
    comma_test_comma(
      comma_test_record_call("left-a", loc),
      comma_test_record_call("left-b", loc),
      loc,
    ),
    comma_test_record_call("left-c", loc),
    loc,
  )
  ignore(comma_test_eval(interp, left_nested))
  json_inspect(events, content=["left-a", "left-b", "left-c"])
  events.clear()
  let right_nested = comma_test_comma(
    comma_test_record_call("right-a", loc),
    comma_test_comma(
      comma_test_record_call("right-b", loc),
      comma_test_record_call("right-c", loc),
      loc,
    ),
    loc,
  )
  ignore(comma_test_eval(interp, right_nested))
  json_inspect(events, content=["right-a", "right-b", "right-c"])
  events.clear()
  let mixed = comma_test_comma(
    comma_test_comma(
      comma_test_record_call("mixed-a", loc),
      comma_test_comma(
        comma_test_record_call("mixed-b", loc),
        comma_test_record_call("mixed-c", loc),
        loc,
      ),
      loc,
    ),
    comma_test_comma(
      comma_test_record_call("mixed-d", loc),
      comma_test_record_call("mixed-e", loc),
      loc,
    ),
    loc,
  )
  ignore(comma_test_eval(interp, mixed))
  json_inspect(events, content=[
    "mixed-a", "mixed-b", "mixed-c", "mixed-d", "mixed-e",
  ])
}

///|
test "direct comma returns the exact final object value" {
  let interp = Interpreter::new()
  let marker = make_object(Map([]), Null, None, "Object", Map([]), true)
  interp.global.def("marker", marker, LetBinding)
  let loc = comma_test_loc()
  let result = comma_test_eval(
    interp,
    comma_test_comma(
      comma_test_number(0.0, loc),
      comma_test_ident("marker", loc),
      loc,
    ),
  )
  assert_true(physical_equal(result, marker))
}

///|
test "direct comma performs discarded-left getter and preserves abrupt identity" {
  let interp = Interpreter::new()
  let result = interp.run(
    @parser.parse(
      "let sentinel={};" +
      "let getter=false;" +
      "let later=false;" +
      "let target={get value(){getter=true;throw sentinel;}};" +
      "let caught;" +
      "try{(target.value,later=true);}" +
      "catch(error){caught=error;}" +
      "caught===sentinel && getter===true && later===false;",
    ).stmts,
  )
  match result {
    Bool(true) => ()
    other =>
      fail(
        "expected abrupt sentinel identity and no later effect, got " +
        other.to_string(),
      )
  }
}

///|
test "direct comma generator resume does not replay or omit effects" {
  let interp = Interpreter::new()
  let program = @parser.parse(
      "function* g(){" +
      "let count=0;" +
      "let value=(count=count+1,yield 7,count=count+1,count);" +
      "yield value;}",
    ).stmts
  ignore(interp.run(program))
  let generator = interp.call_value(
    interp.global.get("g"),
    Undefined,
    [],
    comma_test_loc(),
  )
  let first = generator_resume(interp, generator, Next(Undefined))
  let second = generator_resume(interp, generator, Next(Undefined))
  let third = generator_resume(interp, generator, Next(Undefined))
  let first_value = interp.get_property(first, "value", comma_test_loc())
  let second_value = interp.get_property(second, "value", comma_test_loc())
  let third_done = interp.get_property(third, "done", comma_test_loc())
  match (first_value, second_value, third_done) {
    (Number(first), Number(second), Bool(done)) => {
      inspect(first, content="7")
      inspect(second, content="2")
      inspect(done, content="true")
    }
    _ => fail("expected generator replay values")
  }
}

///|
fn comma_test_expect_exact_steps(
  expr : @ast.Expr,
  expected : Double,
  budget : Int64,
) -> Unit raise Error {
  let interp = Interpreter::new()
  let control = ExecutionControl(
    remaining_steps=budget,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = comma_test_eval_with_control(
    interp,
    expr,
    { strict: false, current_generator: None },
    control,
  )
  match result {
    Number(value) if value == expected => ()
    other => fail("unexpected direct comma result: " + other.to_string())
  }
  inspect(control.remaining_steps(), content="0")
}

///|
test "direct comma observes root and each entered nested node exactly once" {
  let loc = comma_test_loc()
  comma_test_expect_exact_steps(
    comma_test_comma(
      comma_test_comma(
        comma_test_number(1.0, loc),
        comma_test_number(2.0, loc),
        loc,
      ),
      comma_test_number(3.0, loc),
      loc,
    ),
    3.0,
    5L,
  )
  comma_test_expect_exact_steps(
    comma_test_comma(
      comma_test_number(1.0, loc),
      comma_test_comma(
        comma_test_number(2.0, loc),
        comma_test_number(3.0, loc),
        loc,
      ),
      loc,
    ),
    3.0,
    5L,
  )
  comma_test_expect_exact_steps(
    comma_test_comma(
      comma_test_comma(
        comma_test_number(1.0, loc),
        comma_test_comma(
          comma_test_number(2.0, loc),
          comma_test_number(3.0, loc),
          loc,
        ),
        loc,
      ),
      comma_test_comma(
        comma_test_number(4.0, loc),
        comma_test_number(5.0, loc),
        loc,
      ),
      loc,
    ),
    5.0,
    9L,
  )
}

///|
test "resuming generator skips a no-yield comma subtree without observing it" {
  let interp = Interpreter::new()
  let generator = comma_test_resuming_generator(interp)
  let loc = comma_test_loc()
  let control = ExecutionControl(
    remaining_steps=2,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let result = comma_test_eval_with_control(
    interp,
    comma_test_comma(
      comma_test_comma(
        comma_test_number(1.0, loc),
        comma_test_number(2.0, loc),
        loc,
      ),
      comma_test_number(3.0, loc),
      loc,
    ),
    { strict: false, current_generator: Some(generator) },
    control,
  )
  match result {
    Number(value) if value == 3.0 => ()
    other => fail("expected resumed right leaf, got " + other.to_string())
  }
  inspect(control.remaining_steps(), content="0")
}

///|
test "direct comma budget rejects before the next leaf effect and later leaf succeeds" {
  let interp = Interpreter::new()
  interp.global.def("counter", Number(0.0), VarBinding)
  let loc = comma_test_loc()
  let expr = comma_test_comma(
    comma_test_comma(
      comma_test_number(1.0, loc),
      comma_test_number(2.0, loc),
      loc,
    ),
    @ast.Expr::Assign("counter", comma_test_number(4.0, loc), loc),
    loc,
  )
  let control = ExecutionControl(
    remaining_steps=5,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let failure = try {
    let _ = comma_test_eval_with_control(
      interp,
      expr,
      { strict: false, current_generator: None },
      control,
    )
    "completed"
  } catch {
    ExecutionControlError(ExecutionLimit) => "execution-limit"
    _ => "wrong-failure"
  }
  inspect(failure, content="execution-limit")
  match interp.global.get("counter") {
    Number(value) if value == 0.0 => ()
    other =>
      fail(
        "budget rejection allowed the next leaf effect: " + other.to_string(),
      )
  }
  inspect(control.remaining_steps(), content="0")
  match comma_test_eval(interp, comma_test_number(9.0, loc)) {
    Number(value) if value == 9.0 => ()
    other =>
      fail(
        "later leaf failed after comma budget rejection: " + other.to_string(),
      )
  }
}
