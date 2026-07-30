///|
priv suberror DispatchObservationProbeError {
  DispatchObservationProbeError(String)
}

///|
priv struct DispatchObservationProbe {
  deny_first : Bool
  observed_interp : Interpreter?
  mut attempts : Int
  mut accepted : Int
  mut rejected : Int
  mut released : Int
  mut denied : Int
  mut active : Int
  mut maximum_active : Int
  release_ordinals : Array[Int]
  release_state_restored : Array[Bool]
}

///|
fn DispatchObservationProbe::DispatchObservationProbe(
  deny_first? : Bool = false,
  observed_interp? : Interpreter? = None,
) -> DispatchObservationProbe {
  {
    deny_first,
    observed_interp,
    attempts: 0,
    accepted: 0,
    rejected: 0,
    released: 0,
    denied: 0,
    active: 0,
    maximum_active: 0,
    release_ordinals: [],
    release_state_restored: [],
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
      let ordinal = self.attempts
      let state_before = match self.observed_interp {
        Some(interp) =>
          Some(
            (
              active_realm_protos(interp.realm_state).object_proto,
              interp.realm_state.active_source_identity.val,
              interp.in_nonarrow_param_default_eval,
              interp.param_default_eval_var_conflicts,
            ),
          )
        None => None
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
          self.release_ordinals.push(ordinal)
          match (self.observed_interp, state_before) {
            (
              Some(interp),
              Some(
                (
                  object_proto_before,
                  source_before,
                  parameter_eval_before,
                  conflicts_before,
                )
              ),
            ) => {
              let object_proto_restored = match
                (
                  object_proto_before,
                  active_realm_protos(interp.realm_state).object_proto,
                ) {
                (None, None) => true
                (Some(before), Some(after)) => same_value(before, after)
                _ => false
              }
              let conflicts_restored = match
                (conflicts_before, interp.param_default_eval_var_conflicts) {
                (None, None) => true
                (Some(before), Some(after)) => physical_equal(before, after)
                _ => false
              }
              self.release_state_restored.push(
                object_proto_restored &&
                interp.realm_state.active_source_identity.val == source_before &&
                interp.in_nonarrow_param_default_eval == parameter_eval_before &&
                conflicts_restored,
              )
            }
            _ => ()
          }
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
  source? : String = "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
) -> (PrimitiveProgramDispatchShell, Array[@ast.Stmt], ExecContext) raise {
  let stmts = @parser.parse(source).stmts
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
  inspect(probe.release_ordinals.length(), content="257")
  let mut releases_are_strictly_lifo = true
  for index in 0..<probe.release_ordinals.length() {
    if probe.release_ordinals[index] != 257 - index {
      releases_are_strictly_lifo = false
    }
  }
  inspect(releases_are_strictly_lifo, content="true")
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
test "managed activation observation releases protected returns in strict LIFO order" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe()
  let (shell, stmts, ctx) = dispatch_observation_numeric_fixture(
    interp,
    probe,
    source="function f(n){if(n===0)return 0;" +
      "try{return 1+f(n-1);}finally{0;}}f(256);",
  )
  match activation_dispatch_root_value(shell.drive_root_program(stmts, ctx)) {
    Number(value) => inspect(value, content="256")
    other => fail("expected protected 256, got " + other.to_string())
  }
  expect_nested_dispatch_observation_balanced(probe)
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "guest throw crosses a normal finalizer before LIFO activation release" {
  let interp = Interpreter::new()
  let probe = DispatchObservationProbe()
  let (shell, stmts, ctx) = dispatch_observation_numeric_fixture(
    interp,
    probe,
    source="function f(n){if(n===0)return 0;" +
      "try{return 1+g(n-1);}finally{0;}}" +
      "function g(n){if(n===0)return 0;" +
      "try{return 1+f(n-1);}finally{throw 7;}}" +
      "f(256);",
  )
  match shell.drive_root_program(stmts, ctx) {
    DispatchThrow(JsException(Number(value))) => inspect(value, content="7")
    _ => fail("expected the finalizer guest throw to survive normal finalizers")
  }
  expect_nested_dispatch_observation_balanced(probe)
  inspect(shell.cleanup_stack.length(), content="0")
}

///|
test "observed activation releases after restoring its owned runtime state" {
  let (interp, _, registry, plan) = numeric_activation_test_fixture(
    "function f(n){if(n===0)return 0;return 1+f(n-1);}f(256);",
  )
  dispatch_shell_test_install_realm_sentinel(interp, 72)
  let saved_conflicts : @set.Set[String] = @set.Set::default()
  saved_conflicts.add("observation-release")
  interp.in_nonarrow_param_default_eval = true
  interp.param_default_eval_var_conflicts = Some(saved_conflicts)
  let probe = DispatchObservationProbe(observed_interp=Some(interp))
  let shell = PrimitiveProgramDispatchShell(
    interp,
    numeric_registry=Some(registry),
    activation_observation_port=probe.port(),
  )
  let (cleanup, _) = numeric_activation_test_enter(
    shell,
    registry,
    "f",
    1.0,
    plan.root_call_loc,
  )
  inspect(interp.in_nonarrow_param_default_eval, content="false")
  inspect(interp.param_default_eval_var_conflicts is None, content="true")
  numeric_activation_test_release(shell, cleanup, DispatchReturn(Number(1.0)))
  inspect(probe.release_ordinals.length(), content="1")
  inspect(probe.release_ordinals[0], content="1")
  inspect(probe.release_state_restored.length(), content="1")
  inspect(probe.release_state_restored[0], content="true")
  dispatch_shell_test_expect_realm_sentinel(interp, 72)
  inspect(interp.in_nonarrow_param_default_eval, content="true")
  match interp.param_default_eval_var_conflicts {
    Some(found) =>
      inspect(physical_equal(found, saved_conflicts), content="true")
    None => fail("expected the observation release to restore conflicts")
  }
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
test "runtime abrupt skips catch, runs finalizers, and preserves identity before release" {
  let interp = Interpreter::new()
  let trace : Array[String] = []
  let observed_steps : Ref[Int] = { val: 0 }
  let runtime_failure : Error = ExecutionControlError(Interrupted)
  interp.global.bindings[EXECUTION_CONTROL_BINDING] = {
    value: make_object(
      Map([]),
      Null,
      Some(
        NonConstructableCallable("one-shot runtime abrupt", _args => {
          observed_steps.val += 1
          let step = observed_steps.val
          trace.push("step:" + step.to_string())
          if step == 12 {
            trace.push("runtime-abrupt")
            raise runtime_failure
          }
          Undefined
        }),
      ),
      "Function",
      Map([]),
      true,
    ),
    kind: VarBinding,
    initialized: true,
    annex_b_hoisted: false,
    is_parameter: false,
  }
  let attempts : Ref[Int] = { val: 0 }
  let accepted : Ref[Int] = { val: 0 }
  let rejected : Ref[Int] = { val: 0 }
  let released : Ref[Int] = { val: 0 }
  let denied : Ref[Int] = { val: 0 }
  let observation_port = ActivationObservationPort(
    begin_entry=() => {
      attempts.val += 1
      trace.push("activation-attempt")
      ActivationObservationAttemptHooks(
        accepted=() => {
          accepted.val += 1
          trace.push("activation-accepted")
        },
        rejected=() => {
          rejected.val += 1
          trace.push("activation-rejected")
        },
        released=() => {
          released.val += 1
          trace.push("activation-released")
        },
      )
    },
    denied=() => {
      denied.val += 1
      trace.push("activation-denied")
    },
  )
  let source = "function f(n){if(n===0)return 0;" +
    "try{return 1+f(n-1);}finally{0;}}" +
    "try{f(256);}catch{throw 9;}finally{0;}"
  let stmts = @parser.parse(source).stmts
  let preflight = match
    interp.preflight_dispatchable_numeric_recursion_program(stmts) {
    Some(found) => found
    None => fail("expected protected runtime-abrupt preflight")
  }
  let shell = PrimitiveProgramDispatchShell(
    interp,
    numeric_root_preflight=Some(preflight),
    activation_observation_port=observation_port,
  )
  let completion = shell.drive_root_program(stmts, {
    strict: false,
    current_generator: None,
  })
  match completion {
    DispatchRuntimeAbrupt(found) =>
      inspect(physical_equal(found, runtime_failure), content="true")
    _ => fail("runtime abrupt must skip catch and survive both finalizers")
  }
  inspect(attempts.val, content="1")
  inspect(accepted.val, content="1")
  inspect(rejected.val, content="0")
  inspect(released.val, content="1")
  inspect(denied.val, content="0")
  inspect(shell.cleanup_stack.length(), content="0")
  json_inspect(trace, content=[
    "step:1", "step:2", "step:3", "step:4", "step:5", "step:6", "activation-attempt",
    "activation-accepted", "step:7", "step:8", "step:9", "step:10", "step:11", "step:12",
    "runtime-abrupt", "step:13", "step:14", "activation-released", "step:15", "step:16",
  ])
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
