// Private, JavaScript-free execution-control state transitions.
// Public policy validation and runtime observation-point wiring are separate
// implementation slices.

///|
#warnings("-unused_constructor")
priv enum ExecutionControlFailure {
  Interrupted
  StackDepthLimit
  ExecutionLimit
}

///|
priv suberror ExecutionControlError {
  ExecutionControlError(ExecutionControlFailure)
}

///|
// Per-Interpreter carrier for the active operation control. Keeping it in the
// internal Environment avoids public record-shape changes and module-global
// mutable state; it is not a globalThis property or persistent configuration.
const EXECUTION_CONTROL_BINDING = "[[ExecutionControl]]"

///|
const EXECUTION_CONTROL_ACTIVATION = "activation"

///|
const EXECUTION_CONTROL_RELEASE = "release"

///|
const STACK_DEPTH_LIMIT_MESSAGE = "Maximum call stack size exceeded"

///|
priv struct ExecutionInterruptionRequest {
  requested : Ref[Bool]
}

///|
#warnings("-unused_value")
fn ExecutionInterruptionRequest::ExecutionInterruptionRequest() -> ExecutionInterruptionRequest {
  { requested: { val: false } }
}

///|
#warnings("-unused_value")
fn ExecutionInterruptionRequest::request(
  self : ExecutionInterruptionRequest,
) -> Unit {
  self.requested.val = true
}

///|
fn ExecutionInterruptionRequest::is_requested(
  self : ExecutionInterruptionRequest,
) -> Bool {
  self.requested.val
}

///|
priv struct ExecutionControl {
  mut remaining_steps_ : Int
  maximum_active_depth : Int
  mut active_depth_ : Int
  interruption : ExecutionInterruptionRequest
}

///|
#warnings("-unused_value")
fn ExecutionControl::ExecutionControl(
  remaining_steps~ : Int,
  maximum_active_depth~ : Int,
  interruption~ : ExecutionInterruptionRequest,
) -> ExecutionControl {
  {
    remaining_steps_: remaining_steps,
    maximum_active_depth,
    active_depth_: 0,
    interruption,
  }
}

///|
#warnings("-unused_value")
fn ExecutionControl::remaining_steps(self : ExecutionControl) -> Int {
  self.remaining_steps_
}

///|
#warnings("-unused_value")
fn ExecutionControl::active_depth(self : ExecutionControl) -> Int {
  self.active_depth_
}

///|
#warnings("-unused_value")
fn ExecutionControl::observe_step(
  self : ExecutionControl,
) -> Result[Unit, ExecutionControlFailure] {
  if self.interruption.is_requested() {
    Err(Interrupted)
  } else if self.remaining_steps_ == 0 {
    Err(ExecutionLimit)
  } else {
    self.remaining_steps_ = self.remaining_steps_ - 1
    Ok(())
  }
}

///|
fn execution_control_observer(control : ExecutionControl) -> Value {
  make_object(
    Map([]),
    Null,
    Some(
      NonConstructableCallable("[[execution-control-observer]]", fn(
        args,
      ) raise {
        match args {
          [String_(operation)] if operation == EXECUTION_CONTROL_ACTIVATION =>
            match control.observe_activation() {
              Ok(_) => Undefined
              Err(failure) => raise ExecutionControlError(failure)
            }
          [String_(operation)] if operation == EXECUTION_CONTROL_RELEASE => {
            control.release_activation()
            Undefined
          }
          _ =>
            match control.observe_step() {
              Ok(_) => Undefined
              Err(failure) => raise ExecutionControlError(failure)
            }
        }
      }),
    ),
    "Function",
    Map([]),
    true,
  )
}

///|
fn restore_execution_control_binding(
  global : Environment,
  previous : Binding?,
) -> Unit {
  match previous {
    Some(binding) => global.bindings[EXECUTION_CONTROL_BINDING] = binding
    None => {
      let _ = global.bindings.remove(EXECUTION_CONTROL_BINDING)
    }
  }
}

///|
fn Interpreter::observe_execution_step(self : Interpreter) -> Unit raise Error {
  match self.global.bindings.get(EXECUTION_CONTROL_BINDING) {
    Some(binding) =>
      match binding.value {
        Object(data) =>
          match data.callable {
            Some(NonConstructableCallable(_, observe)) => {
              let _ = observe([])
            }
            _ => ()
          }
        _ => ()
      }
    None => ()
  }
}

///|
fn Interpreter::observe_execution_activation(
  self : Interpreter,
) -> Unit raise Error {
  match self.global.bindings.get(EXECUTION_CONTROL_BINDING) {
    Some(binding) =>
      match binding.value {
        Object(data) =>
          match data.callable {
            Some(NonConstructableCallable(_, observe)) => {
              let _ = observe([String_(EXECUTION_CONTROL_ACTIVATION)])
            }
            _ => ()
          }
        _ => ()
      }
    None => ()
  }
}

///|
// Release is an ownership-only lifecycle hook. The active-depth transition is
// infallible once entry has been accepted; any stale carrier is ignored because
// unbounded execution has no activation policy to release.
fn Interpreter::release_execution_activation(self : Interpreter) -> Unit {
  match self.global.bindings.get(EXECUTION_CONTROL_BINDING) {
    Some(binding) =>
      match binding.value {
        Object(data) =>
          match data.callable {
            Some(NonConstructableCallable(_, observe)) =>
              try {
                let _ = observe([String_(EXECUTION_CONTROL_RELEASE)])
              } catch {
                _ => ()
              }
            _ => ()
          }
        _ => ()
      }
    None => ()
  }
}

///|
#warnings("-unused_value")
// Saving and restoring a previous carrier guarantees scoped cleanup only. It
// does not authorize or define same-Engine re-entry through public operations.
fn[T] Interpreter::with_execution_control(
  self : Interpreter,
  control : ExecutionControl,
  action : () -> T raise Error,
) -> T raise Error {
  let previous = self.global.bindings.get(EXECUTION_CONTROL_BINDING)
  self.global.bindings[EXECUTION_CONTROL_BINDING] = {
    value: execution_control_observer(control),
    kind: VarBinding,
    initialized: true,
    annex_b_hoisted: false,
    is_parameter: false,
  }
  let result = action() catch {
    error => {
      restore_execution_control_binding(self.global, previous)
      raise error
    }
  }
  restore_execution_control_binding(self.global, previous)
  result
}

///|
#warnings("-unused_value")
fn ExecutionControl::observe_activation(
  self : ExecutionControl,
) -> Result[Unit, ExecutionControlFailure] {
  if self.interruption.is_requested() {
    Err(Interrupted)
  } else if self.active_depth_ == self.maximum_active_depth {
    Err(StackDepthLimit)
  } else if self.remaining_steps_ == 0 {
    Err(ExecutionLimit)
  } else {
    self.active_depth_ = self.active_depth_ + 1
    self.remaining_steps_ = self.remaining_steps_ - 1
    Ok(())
  }
}

///|
fn ExecutionControl::release_activation(self : ExecutionControl) -> Unit {
  self.active_depth_ = self.active_depth_ - 1
}

///|
// Adapt the deterministic depth policy to the policy-free lifecycle port. The
// shell owns cleanup ordering; this adapter only acquires depth at entry and
// releases it on rejected setup or final activation cleanup.
fn Interpreter::execution_control_activation_observation_port(
  self : Interpreter,
) -> ActivationObservationPort {
  ActivationObservationPort(
    begin_entry=() => {
      self.observe_execution_activation()
      ActivationObservationAttemptHooks(
        accepted=() => (),
        rejected=() => self.release_execution_activation(),
        released=() => self.release_execution_activation(),
      )
    },
    denied=() => (),
  )
}

///|
#warnings("-unused_value")
fn[T] ExecutionControl::with_activation(
  self : ExecutionControl,
  action : () -> T raise Error,
) -> Result[T, ExecutionControlFailure] raise Error {
  let previous_depth = self.active_depth_
  match self.observe_activation() {
    Err(failure) => Err(failure)
    Ok(_) =>
      try {
        let result = action()
        self.active_depth_ = previous_depth
        Ok(result)
      } catch {
        error => {
          self.active_depth_ = previous_depth
          raise error
        }
      }
  }
}
