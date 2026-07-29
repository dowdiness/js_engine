///|
test "numeric root expression observes callee before its argument" {
  let stmts = @parser.parse(
      "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
    ).stmts
  let plan = match classify_numeric_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact numeric recursion plan")
  }
  let capture = DispatchCalleeCaptureToken(id=1900)
  let expression = numeric_recursion_root_dispatch_expression(plan, capture)
  stmts.clear()
  let (running, root_ticket) = start_accepted_dispatch_root(1900)
  let (observing_call, call_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(DispatchSuspendNumericExpression(expression, None)),
    ),
  )
  let call_ticket = match call_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveCall(loc))
      )
    ) => {
      inspect(loc.line, content="1")
      ticket
    }
    _ => fail("expected call observation first")
  }
  let (observing_callee, callee_decision) = reduce_activation_dispatch(
    observing_call,
    DispatchEffectCompleted(
      call_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let callee_ticket = match callee_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(
          DispatchNumericObserveTrustedCallee(found)
        )
      )
    ) => {
      inspect(found.id, content="1900")
      ticket
    }
    _ => fail("expected trusted callee observation before capture")
  }
  let (capturing_callee, capture_decision) = reduce_activation_dispatch(
    observing_callee,
    DispatchEffectCompleted(
      callee_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let capture_ticket = match capture_decision {
    DispatchPerform(ticket, DispatchRun(DispatchCaptureTrustedCallee(found))) => {
      inspect(found.id, content="1900")
      ticket
    }
    _ => fail("expected callee capture before argument observation")
  }
  let (observing_argument, argument_decision) = reduce_activation_dispatch(
    capturing_callee,
    DispatchEffectCompleted(
      capture_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let argument_ticket = match argument_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveNumber(value))
      )
    ) => {
      inspect(value, content="256")
      ticket
    }
    _ => fail("expected numeric argument observation after callee capture")
  }
  let (_, start_decision) = reduce_activation_dispatch(
    observing_argument,
    DispatchEffectCompleted(
      argument_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  match start_decision {
    DispatchPerform(
      _,
      DispatchRun(DispatchStartCapturedNumericCall(found, value, loc))
    ) => {
      inspect(found.id, content="1900")
      inspect(value, content="256")
      inspect(loc.line, content="1")
    }
    _ => fail("expected captured call start after argument observation")
  }
}

///|
test "numeric base condition reads its parameter only after observation" {
  let stmts = @parser.parse(
      "function f(n) {\n" +
      "  if (n\n" +
      "    === 0) return 0;\n" +
      "  return 1\n" +
      "    + f\n" +
      "      (\n" +
      "        n\n" +
      "        - 1\n" +
      "      );\n" +
      "}\n" +
      "f(256);",
    ).stmts
  let plan = match classify_numeric_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the multiline numeric recursion plan")
  }
  let parameter = DispatchParameterBindingToken(id=2000)
  let expression = numeric_recursion_base_condition_dispatch_expression(
    plan.entry,
    parameter,
  )
  stmts.clear()
  let (running, root_ticket) = start_accepted_dispatch_root(2000)
  let (observing_binary, binary_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(DispatchSuspendNumericExpression(expression, None)),
    ),
  )
  let binary_ticket = match binary_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(
          DispatchNumericObserveBinary(DispatchNumericStrictEqual, loc)
        )
      )
    ) => {
      inspect(loc.line.to_string() + ":" + loc.col.to_string(), content="3:5")
      ticket
    }
    _ => fail("expected strict-equality observation first")
  }
  let (observing_parameter, parameter_decision) = reduce_activation_dispatch(
    observing_binary,
    DispatchEffectCompleted(
      binary_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let parameter_ticket = match parameter_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveParameter(found))
      )
    ) => {
      inspect(found.id, content="2000")
      ticket
    }
    _ => fail("expected parameter observation before parameter read")
  }
  let (reading_parameter, read_decision) = reduce_activation_dispatch(
    observing_parameter,
    DispatchEffectCompleted(
      parameter_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let read_ticket = match read_decision {
    DispatchPerform(ticket, DispatchRun(DispatchReadNumericParameter(found))) => {
      inspect(found.id, content="2000")
      ticket
    }
    _ => fail("expected activation-owned parameter read after observation")
  }
  let (observing_zero, zero_decision) = reduce_activation_dispatch(
    reading_parameter,
    DispatchEffectCompleted(
      read_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(0.0))),
    ),
  )
  let zero_ticket = match zero_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveNumber(value))
      )
    ) => {
      inspect(value, content="0")
      ticket
    }
    _ => fail("expected right operand only after the parameter read")
  }
  let (_, apply_decision) = reduce_activation_dispatch(
    observing_zero,
    DispatchEffectCompleted(
      zero_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  match apply_decision {
    DispatchPerform(
      _,
      DispatchRun(
        DispatchResumeContinuation(
          DispatchApplyBinaryRight(binary),
          Number(right)
        )
      )
    ) => {
      inspect(binary.op == @ast.EqEqEq, content="true")
      inspect(dispatch_test_value_tag(binary.left), content="0")
      inspect(right, content="0")
      inspect(
        binary.loc.line.to_string() + ":" + binary.loc.col.to_string(),
        content="3:5",
      )
    }
    _ => fail("expected strict-equality application after both operands")
  }
}

///|
test "numeric base result completes return only after literal observation" {
  let expression = numeric_recursion_base_result_dispatch_expression()
  let (running, root_ticket) = start_accepted_dispatch_root(2100)
  let (observing_result, observation_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendNumericExpression(
          expression,
          Some(DispatchCompleteReturn),
        ),
      ),
    ),
  )
  let observation_ticket = match observation_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveNumber(value))
      )
    ) => {
      inspect(value, content="0")
      ticket
    }
    _ => fail("expected base literal observation before return completion")
  }
  let (_, release_decision) = reduce_activation_dispatch(
    observing_result,
    DispatchEffectCompleted(
      observation_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  match release_decision {
    DispatchPerform(
      _,
      DispatchReleaseActivation(_, DispatchReturn(Number(value)))
    ) => inspect(value, content="0")
    _ => fail("expected return completion after base literal observation")
  }
}

///|
test "numeric recursive result preserves source order across child activation" {
  let stmts = @parser.parse(
      "function f(n) {\n" +
      "  if (n\n" +
      "    === 0) return 0;\n" +
      "  return 1\n" +
      "    + f\n" +
      "      (\n" +
      "        n\n" +
      "        - 1\n" +
      "      );\n" +
      "}\n" +
      "f(256);",
    ).stmts
  let plan = match classify_numeric_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the multiline numeric recursion plan")
  }
  let parameter = DispatchParameterBindingToken(id=2200)
  let capture = DispatchCalleeCaptureToken(id=2201)
  let expression = numeric_recursion_recursive_result_dispatch_expression(
    plan.entry,
    parameter,
    capture,
  )
  stmts.clear()
  let trace : Array[String] = []
  let (running, root_ticket) = start_accepted_dispatch_root(2200)
  let (observing_add, add_observation_decision) = reduce_activation_dispatch(
    running,
    DispatchEffectCompleted(
      root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendNumericExpression(
          expression,
          Some(DispatchCompleteReturn),
        ),
      ),
    ),
  )
  let add_observation_ticket = match add_observation_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(
          DispatchNumericObserveBinary(DispatchNumericAdd, loc)
        )
      )
    ) => {
      trace.push("observe:add")
      inspect(loc.line.to_string() + ":" + loc.col.to_string(), content="5:5")
      ticket
    }
    _ => fail("expected recursive add observation first")
  }
  let (observing_increment, increment_decision) = reduce_activation_dispatch(
    observing_add,
    DispatchEffectCompleted(
      add_observation_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let increment_ticket = match increment_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveNumber(value))
      )
    ) => {
      trace.push("observe:1-left")
      inspect(value, content="1")
      ticket
    }
    _ => fail("expected increment observation before recursive call")
  }
  let (observing_call, call_decision) = reduce_activation_dispatch(
    observing_increment,
    DispatchEffectCompleted(
      increment_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let call_ticket = match call_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveCall(loc))
      )
    ) => {
      trace.push("observe:call")
      inspect(loc.line.to_string() + ":" + loc.col.to_string(), content="6:7")
      ticket
    }
    _ => fail("expected call observation after left add operand")
  }
  let (observing_callee, callee_decision) = reduce_activation_dispatch(
    observing_call,
    DispatchEffectCompleted(
      call_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let callee_ticket = match callee_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(
          DispatchNumericObserveTrustedCallee(found)
        )
      )
    ) => {
      trace.push("observe:callee")
      inspect(found.id, content="2201")
      ticket
    }
    _ => fail("expected callee observation before capture")
  }
  let (capturing_callee, capture_decision) = reduce_activation_dispatch(
    observing_callee,
    DispatchEffectCompleted(
      callee_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let capture_ticket = match capture_decision {
    DispatchPerform(ticket, DispatchRun(DispatchCaptureTrustedCallee(found))) => {
      trace.push("capture:callee")
      inspect(found.id, content="2201")
      ticket
    }
    _ => fail("expected one-shot callee capture")
  }
  let (observing_subtract, subtract_decision) = reduce_activation_dispatch(
    capturing_callee,
    DispatchEffectCompleted(
      capture_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let subtract_ticket = match subtract_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(
          DispatchNumericObserveBinary(DispatchNumericSubtract, loc)
        )
      )
    ) => {
      trace.push("observe:subtract")
      inspect(loc.line.to_string() + ":" + loc.col.to_string(), content="8:9")
      ticket
    }
    _ => fail("expected subtraction before its operands")
  }
  let (observing_parameter, parameter_decision) = reduce_activation_dispatch(
    observing_subtract,
    DispatchEffectCompleted(
      subtract_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let parameter_ticket = match parameter_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveParameter(found))
      )
    ) => {
      trace.push("observe:parameter")
      inspect(found.id, content="2200")
      ticket
    }
    _ => fail("expected parameter observation before its read")
  }
  let (reading_parameter, read_decision) = reduce_activation_dispatch(
    observing_parameter,
    DispatchEffectCompleted(
      parameter_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let read_ticket = match read_decision {
    DispatchPerform(ticket, DispatchRun(DispatchReadNumericParameter(found))) => {
      trace.push("read:parameter")
      inspect(found.id, content="2200")
      ticket
    }
    _ => fail("expected parameter capability read")
  }
  let (observing_decrement, decrement_decision) = reduce_activation_dispatch(
    reading_parameter,
    DispatchEffectCompleted(
      read_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(3.0))),
    ),
  )
  let decrement_ticket = match decrement_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveNumber(value))
      )
    ) => {
      trace.push("observe:1-right")
      inspect(value, content="1")
      ticket
    }
    _ => fail("expected decrement observation after parameter read")
  }
  let (applying_subtract, subtract_apply_decision) = reduce_activation_dispatch(
    observing_decrement,
    DispatchEffectCompleted(
      decrement_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let subtract_apply_ticket = match subtract_apply_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchResumeContinuation(
          DispatchApplyBinaryRight(binary),
          Number(right)
        )
      )
    ) => {
      trace.push("apply:subtract")
      inspect(binary.op == @ast.Sub, content="true")
      inspect(dispatch_test_value_tag(binary.left), content="3")
      inspect(right, content="1")
      inspect(
        binary.loc.line.to_string() + ":" + binary.loc.col.to_string(),
        content="8:9",
      )
      ticket
    }
    _ => fail("expected subtraction before child activation")
  }
  let (starting_call, start_decision) = reduce_activation_dispatch(
    applying_subtract,
    DispatchEffectCompleted(
      subtract_apply_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(2.0))),
    ),
  )
  let start_ticket = match start_decision {
    DispatchPerform(
      ticket,
      DispatchRun(DispatchStartCapturedNumericCall(found, argument, loc))
    ) => {
      trace.push("start:call")
      inspect(found.id, content="2201")
      inspect(argument, content="2")
      inspect(loc.line.to_string() + ":" + loc.col.to_string(), content="6:7")
      ticket
    }
    _ => fail("expected captured call start after subtraction")
  }
  let request = DispatchCallRequest(
    callee=String_("captured:f"),
    this_value=Undefined,
    args=[Number(2.0)],
    loc=plan.entry.expression_recipe.recursive_call_loc,
  )
  let (entering_child, child_entry_decision) = reduce_activation_dispatch(
    starting_call,
    DispatchEffectCompleted(
      start_ticket,
      DispatchWorkSuspended(
        DispatchSuspendCall(request, DispatchDeliverCallResult),
      ),
    ),
  )
  let child_entry_ticket = match child_entry_decision {
    DispatchPerform(
      ticket,
      DispatchEnterActivation(DispatchCallActivation(found))
    ) => {
      trace.push("enter:child")
      inspect(dispatch_test_value_tag(found.callee), content="captured:f")
      inspect(found.args.length(), content="1")
      ticket
    }
    _ => fail("expected child entry before pending addition")
  }
  let (running_child, child_decision) = reduce_activation_dispatch(
    entering_child,
    DispatchEffectCompleted(
      child_entry_ticket,
      DispatchCallAccepted(
        DispatchActivationCleanup(2202),
        DispatchCallBody(dispatch_test_statement_work(2203)),
      ),
    ),
  )
  let child_ticket = match child_decision {
    DispatchPerform(ticket, DispatchRun(DispatchExecuteStatement(step))) => {
      trace.push("run:child")
      inspect(dispatch_test_step_label(step), content="2203")
      ticket
    }
    _ => fail("expected child work while addition remains suspended")
  }
  let (releasing_child, child_release_decision) = reduce_activation_dispatch(
    running_child,
    DispatchEffectCompleted(
      child_ticket,
      DispatchWorkCompleted(DispatchReturn(Number(2.0))),
    ),
  )
  let child_release_ticket = match child_release_decision {
    DispatchPerform(
      ticket,
      DispatchReleaseActivation(_, DispatchNormal(Number(value)))
    ) => {
      trace.push("release:child")
      inspect(value, content="2")
      ticket
    }
    _ => fail("expected normalized child return before addition")
  }
  let (applying_add, add_apply_decision) = reduce_activation_dispatch(
    releasing_child,
    DispatchEffectCompleted(child_release_ticket, DispatchCleanupCompleted),
  )
  let add_apply_ticket = match add_apply_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchResumeContinuation(
          DispatchApplyBinaryRight(binary),
          Number(right)
        )
      )
    ) => {
      trace.push("apply:add")
      inspect(binary.op == @ast.Add, content="true")
      inspect(dispatch_test_value_tag(binary.left), content="1")
      inspect(right, content="2")
      inspect(
        binary.loc.line.to_string() + ":" + binary.loc.col.to_string(),
        content="5:5",
      )
      ticket
    }
    _ => fail("expected addition only after child release")
  }
  let (_, root_release_decision) = reduce_activation_dispatch(
    applying_add,
    DispatchEffectCompleted(
      add_apply_ticket,
      DispatchWorkCompleted(DispatchNormal(Number(3.0))),
    ),
  )
  match root_release_decision {
    DispatchPerform(
      _,
      DispatchReleaseActivation(_, DispatchReturn(Number(value)))
    ) => {
      trace.push("return:root")
      inspect(value, content="3")
    }
    _ => fail("expected outer return only after recursive addition")
  }
  json_inspect(trace, content=[
    "observe:add", "observe:1-left", "observe:call", "observe:callee", "capture:callee",
    "observe:subtract", "observe:parameter", "read:parameter", "observe:1-right",
    "apply:subtract", "start:call", "enter:child", "run:child", "release:child",
    "apply:add", "return:root",
  ])
}

///|
test "numeric expression work rejects invalid payloads and propagates abrupt observation" {
  let (running_literal, literal_root_ticket) = start_accepted_dispatch_root(
    2300,
  )
  let (observing_literal, literal_decision) = reduce_activation_dispatch(
    running_literal,
    DispatchEffectCompleted(
      literal_root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendNumericExpression(
          DispatchNumericNumber(0.0),
          Some(DispatchCompleteReturn),
        ),
      ),
    ),
  )
  let literal_ticket = match literal_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveNumber(0.0))
      )
    ) => ticket
    _ => fail("expected numeric literal observation")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      observing_literal,
      DispatchEffectCompleted(
        literal_ticket,
        DispatchWorkCompleted(DispatchNormal(Number(9.0))),
      ),
    )
  })
  let (_, abrupt_decision) = reduce_activation_dispatch(
    observing_literal,
    DispatchEffectCompleted(
      literal_ticket,
      DispatchWorkCompleted(
        DispatchThrow(JsException(String_("observer-abrupt"))),
      ),
    ),
  )
  match abrupt_decision {
    DispatchPerform(
      _,
      DispatchReleaseActivation(_, DispatchThrow(JsException(String_(message))))
    ) => inspect(message, content="observer-abrupt")
    _ => fail("observation abrupt completion must skip numeric continuations")
  }
  let parameter = DispatchParameterBindingToken(id=2400)
  let (running_parameter, parameter_root_ticket) = start_accepted_dispatch_root(
    2400,
  )
  let (observing_parameter, parameter_decision) = reduce_activation_dispatch(
    running_parameter,
    DispatchEffectCompleted(
      parameter_root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendNumericExpression(
          DispatchNumericParameter(parameter),
          None,
        ),
      ),
    ),
  )
  let parameter_ticket = match parameter_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(DispatchNumericObserveParameter(found))
      )
    ) => {
      inspect(found.id, content="2400")
      ticket
    }
    _ => fail("expected parameter observation")
  }
  let (reading_parameter, read_decision) = reduce_activation_dispatch(
    observing_parameter,
    DispatchEffectCompleted(
      parameter_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let read_ticket = match read_decision {
    DispatchPerform(ticket, DispatchRun(DispatchReadNumericParameter(found))) => {
      inspect(found.id, content="2400")
      ticket
    }
    _ => fail("expected parameter read")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      reading_parameter,
      DispatchEffectCompleted(
        read_ticket,
        DispatchWorkCompleted(DispatchNormal(String_("not-a-number"))),
      ),
    )
  })
  let capture = DispatchCalleeCaptureToken(id=2500)
  let (running_call, call_root_ticket) = start_accepted_dispatch_root(2500)
  let (observing_call, call_decision) = reduce_activation_dispatch(
    running_call,
    DispatchEffectCompleted(
      call_root_ticket,
      DispatchWorkSuspended(
        DispatchSuspendNumericExpression(
          DispatchNumericSingleArgumentCall(
            capture,
            DispatchNumericNumber(1.0),
            @token.Loc::default(),
          ),
          None,
        ),
      ),
    ),
  )
  let call_ticket = match call_decision {
    DispatchPerform(
      ticket,
      DispatchRun(DispatchObserveExpressionStep(DispatchNumericObserveCall(_)))
    ) => ticket
    _ => fail("expected call observation")
  }
  let (observing_callee, callee_decision) = reduce_activation_dispatch(
    observing_call,
    DispatchEffectCompleted(
      call_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let callee_ticket = match callee_decision {
    DispatchPerform(
      ticket,
      DispatchRun(
        DispatchObserveExpressionStep(
          DispatchNumericObserveTrustedCallee(found)
        )
      )
    ) => {
      inspect(found.id, content="2500")
      ticket
    }
    _ => fail("expected callee observation")
  }
  let (capturing_callee, capture_decision) = reduce_activation_dispatch(
    observing_callee,
    DispatchEffectCompleted(
      callee_ticket,
      DispatchWorkCompleted(DispatchNormal(Undefined)),
    ),
  )
  let capture_ticket = match capture_decision {
    DispatchPerform(ticket, DispatchRun(DispatchCaptureTrustedCallee(found))) => {
      inspect(found.id, content="2500")
      ticket
    }
    _ => fail("expected callee capture")
  }
  expect_invalid_dispatch(() => {
    let _ = reduce_activation_dispatch(
      capturing_callee,
      DispatchEffectCompleted(
        capture_ticket,
        DispatchWorkCompleted(DispatchNormal(Number(1.0))),
      ),
    )
  })
}

///|
test "mutual recursion expression retains only the selected peer recipe and tokens" {
  let stmts = @parser.parse(
      "function f(n) {\n" +
      "  if (n === 0) return 0;\n" +
      "  return 1 + g(n - 1);\n" +
      "}\n" +
      "function g(m) {\n" +
      "  if (m === 0) return 0;\n" +
      "  return 1 + f(m - 1);\n" +
      "}\n" +
      "f(256);",
    ).stmts
  let plan = match classify_numeric_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected the exact mutual numeric recursion plan")
  }
  let peer = match plan.peer {
    Some(found) => found
    None => fail("expected a peer function plan")
  }
  let expression = numeric_recursion_recursive_result_dispatch_expression(
    peer,
    DispatchParameterBindingToken(id=2600),
    DispatchCalleeCaptureToken(id=2601),
  )
  stmts.clear()
  match expression {
    DispatchNumericBinary(
      DispatchNumericAdd,
      DispatchNumericNumber(increment),
      DispatchNumericSingleArgumentCall(
        capture,
        DispatchNumericBinary(
          DispatchNumericSubtract,
          DispatchNumericParameter(parameter),
          DispatchNumericNumber(decrement),
          subtract_loc
        ),
        call_loc
      ),
      add_loc
    ) => {
      inspect(increment, content="1")
      inspect(decrement, content="1")
      inspect(parameter.id, content="2600")
      inspect(capture.id, content="2601")
      inspect(add_loc.line, content="7")
      inspect(call_loc.line, content="7")
      inspect(subtract_loc.line, content="7")
    }
    _ => fail("expected the closed recursive expression recipe")
  }
}
