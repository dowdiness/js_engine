///|
priv suberror DispatchObservationProbeError {
  DispatchObservationProbeError(String)
}

///|
priv struct DispatchObservationProbe {
  deny_first : Bool
  mut attempts : Int
  mut accepted : Int
  mut rejected : Int
  mut released : Int
  mut denied : Int
  mut active : Int
  mut maximum_active : Int
}

///|
fn DispatchObservationProbe::DispatchObservationProbe(
  deny_first? : Bool = false,
) -> DispatchObservationProbe {
  {
    deny_first,
    attempts: 0,
    accepted: 0,
    rejected: 0,
    released: 0,
    denied: 0,
    active: 0,
    maximum_active: 0,
  }
}

///|
fn DispatchObservationProbe::port(
  self : DispatchObservationProbe,
) -> ActivationObservationPort {
  ActivationObservationPort(
    begin_entry=() => {
      self.attempts += 1
      if self.deny_first && self.attempts == 1 {
        raise DispatchObservationProbeError("entry denied")
      }
      ActivationObservationAttemptHooks(
        accepted=() => {
          self.accepted += 1
          self.active += 1
          if self.active > self.maximum_active {
            self.maximum_active = self.active
          }
        },
        rejected=() => self.rejected += 1,
        released=() => {
          self.released += 1
          self.active -= 1
        },
      )
    },
    denied=() => self.denied += 1,
  )
}

///|
fn dispatch_observation_numeric_fixture(
  interp : Interpreter,
  probe : DispatchObservationProbe,
) -> (PrimitiveProgramDispatchShell, Array[@ast.Stmt], ExecContext) raise {
  let stmts = @parser.parse(
      "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
    ).stmts
  let preflight = match
    interp.preflight_dispatchable_numeric_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected exact numeric recursion preflight")
  }
  let ctx : ExecContext = { strict: false, current_generator: None }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    numeric_root_preflight=Some(preflight),
    activation_observation_port=probe.port(),
  )
  (shell, stmts, ctx)
}

///|
fn dispatch_observation_getter_fixture(
  interp : Interpreter,
  probe : DispatchObservationProbe,
) -> (PrimitiveProgramDispatchShell, Array[@ast.Stmt], ExecContext) raise {
  let stmts = @parser.parse(
      "let n=256;" +
      "let o={get x(){if(n===0)return 0;n=n-1;return 1+o.x;}};" +
      "o.x;",
    ).stmts
  let preflight = match
    interp.preflight_dispatchable_getter_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected exact getter recursion preflight")
  }
  let ctx : ExecContext = { strict: false, current_generator: None }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    getter_root_preflight=Some(preflight),
    getter_root_stmts=Some(stmts),
    activation_observation_port=probe.port(),
  )
  (shell, stmts, ctx)
}

///|
fn dispatch_observation_proxy_fixture(
  interp : Interpreter,
  probe : DispatchObservationProbe,
) -> (PrimitiveProgramDispatchShell, Array[@ast.Stmt], ExecContext) raise {
  let stmts = @parser.parse(
      "let n=256;" +
      "let p;" +
      "p=new Proxy({},{get(t,k,r){" +
      "if(n===0)return 0;n=n-1;return 1+p.x;" +
      "}});" +
      "p.x;",
    ).stmts
  let preflight = match
    interp.preflight_dispatchable_proxy_get_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected exact Proxy recursion preflight")
  }
  let ctx : ExecContext = { strict: false, current_generator: None }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    proxy_root_preflight=Some(preflight),
    proxy_root_stmts=Some(stmts),
    activation_observation_port=probe.port(),
  )
  (shell, stmts, ctx)
}

///|
fn expect_nested_dispatch_observation_balanced(
  probe : DispatchObservationProbe,
) -> Unit raise {
  inspect(probe.attempts, content="257")
  inspect(probe.accepted, content="257")
  inspect(probe.rejected, content="0")
  inspect(probe.released, content="257")
  inspect(probe.denied, content="0")
  inspect(probe.active, content="0")
  inspect(probe.maximum_active, content="257")
}

///|
test "managed activation observation balances every nested numeric call" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe()
  let (shell, stmts, ctx) = dispatch_observation_numeric_fixture(interp, probe)
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    Number(value) => inspect(value, content="256")
    other => fail("expected 256, got " + other.to_string())
  }
  expect_nested_dispatch_observation_balanced(probe)
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "runtime abrupt completion releases every observed numeric call" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe()
  let (shell, stmts, ctx) = dispatch_observation_numeric_fixture(interp, probe)
  let control = ExecutionControl(
    remaining_steps=100,
    maximum_active_depth=1,
    interruption=ExecutionInterruptionRequest(),
  )
  let completion = interp.with_execution_control(control, () => {
    shell.drive_root_program(stmts, ctx)
  })
  match completion {
    DispatchRuntimeAbrupt(ExecutionControlError(ExecutionLimit)) => ()
    _ => fail("expected the execution limit to leave the managed cycle")
  }
  inspect(probe.accepted > 0, content="true")
  inspect(probe.accepted == probe.released, content="true")
  inspect(probe.rejected, content="0")
  inspect(probe.active, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "managed activation observation balances getter re-entry" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe()
  let (shell, stmts, ctx) = dispatch_observation_getter_fixture(interp, probe)
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    Number(value) => inspect(value, content="256")
    other => fail("expected 256, got " + other.to_string())
  }
  expect_nested_dispatch_observation_balanced(probe)
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "managed activation observation balances Proxy get re-entry" {
  let interp = proxy_get_recursion_trust_test_interpreter()
  let probe = DispatchObservationProbe()
  let (shell, stmts, ctx) = dispatch_observation_proxy_fixture(interp, probe)
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    Number(value) => inspect(value, content="256")
    other => fail("expected 256, got " + other.to_string())
  }
  expect_nested_dispatch_observation_balanced(probe)
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "denied managed activation installs no call ownership" {
  let interp = Interpreter::new()
  dispatch_shell_test_install_realm_sentinel(interp, 71)
  let probe = DispatchObservationProbe(deny_first=true)
  let (shell, stmts, ctx) = dispatch_observation_numeric_fixture(interp, probe)
  let failure = match shell.drive_root_program(stmts, ctx) {
    DispatchRuntimeAbrupt(DispatchObservationProbeError(message)) => message
    _ => "wrong completion"
  }
  inspect(failure, content="entry denied")
  inspect(probe.attempts, content="1")
  inspect(probe.accepted, content="0")
  inspect(probe.rejected, content="0")
  inspect(probe.released, content="0")
  inspect(probe.denied, content="1")
  inspect(probe.active, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
  dispatch_shell_test_expect_realm_sentinel(interp, 71)
}

///|
test "cleanup generation exhaustion precedes activation observation" {
  let (interp, _, registry, plan) = numeric_activation_test_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  let probe = DispatchObservationProbe()
  let shell = PrimitiveProgramDispatchShell(
    interp,
    numeric_registry=Some(registry),
    activation_observation_port=probe.port(),
  )
  shell.next_cleanup_id = MAX_DISPATCH_CLEANUP_ID
  let failure = try {
    let _ = numeric_activation_test_enter(
      shell,
      registry,
      "f",
      1.0,
      plan.root_call_loc,
    )
    "none"
  } catch {
    InvalidActivationDispatchShell(message) => message
    _ => "wrong failure"
  }
  inspect(failure, content="cleanup generation is exhausted")
  inspect(probe.attempts, content="0")
  inspect(probe.accepted, content="0")
  inspect(probe.rejected, content="0")
  inspect(probe.released, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
}
