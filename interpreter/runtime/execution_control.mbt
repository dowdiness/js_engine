// Private, JavaScript-free execution-control state transitions.
// Public policy validation and runtime observation-point wiring are separate
// implementation slices.

///|
#warnings("-unused_constructor")
priv enum ExecutionControlFailure {
  Interrupted
  StackDepthLimit
  ExecutionLimit
  StaleActivationRelease
}

///|
priv suberror ExecutionControlError {
  ExecutionControlError(ExecutionControlFailure)
}

///|
#warnings("-unused_constructor")
priv enum ExecutionControlConfigurationParameter {
  StepBudget
  StackDepth
}

///|
priv suberror ExecutionControlConfigurationError {
  InvalidExecutionControlConfiguration(
    ExecutionControlConfigurationParameter,
    Int64
  )
}

///|
const MAX_PORTABLE_EXECUTION_COUNT : Int64 = 2147483647L

///|
priv struct ExecutionControlConfiguration {
  remaining_steps : Int64
  maximum_active_depth : Int64
}

///|
fn validate_execution_control_limit(
  parameter : ExecutionControlConfigurationParameter,
  value : Int64,
) -> Int64 raise ExecutionControlConfigurationError {
  guard value >= 0L && value <= MAX_PORTABLE_EXECUTION_COUNT else {
    raise InvalidExecutionControlConfiguration(parameter, value)
  }
  value
}

///|
fn ExecutionControlConfiguration::ExecutionControlConfiguration(
  remaining_steps~ : Int64,
  maximum_active_depth~ : Int64,
) -> ExecutionControlConfiguration raise ExecutionControlConfigurationError {
  {
    remaining_steps: validate_execution_control_limit(
      StepBudget,
      remaining_steps,
    ),
    maximum_active_depth: validate_execution_control_limit(
      StackDepth,
      maximum_active_depth,
    ),
  }
}

///|
priv struct ExecutionControlState {
  remaining_steps : Int64
  maximum_active_depth : Int64
  active_depth : Int64
}

///|
priv enum ExecutionControlEvent {
  ObserveStep(Bool)
  ObserveActivation(Bool)
  ReleaseActivation
}

// Tail replacement is intentionally not an event in this slice. A future
// valid tail replacement must carry the retained `active_depth` forward and
// must not emit another `ObserveActivation` acquisition.

///|
priv enum ExecutionControlDecision {
  StepObserved
  ActivationObserved
  ActivationReleased
  Rejected(ExecutionControlFailure)
}

///|
// Pure execution-control transition core. Interruption visibility is supplied
// by the imperative shell; the reducer owns all precedence and counter
// arithmetic without mutating the caller's state.
fn reduce_execution_control(
  state : ExecutionControlState,
  event : ExecutionControlEvent,
) -> (ExecutionControlState, ExecutionControlDecision) {
  match event {
    ObserveStep(interrupted) =>
      if interrupted {
        (state, Rejected(Interrupted))
      } else if state.remaining_steps == 0L {
        (state, Rejected(ExecutionLimit))
      } else {
        (
          {
            remaining_steps: state.remaining_steps - 1L,
            maximum_active_depth: state.maximum_active_depth,
            active_depth: state.active_depth,
          },
          StepObserved,
        )
      }
    ObserveActivation(interrupted) =>
      if interrupted {
        (state, Rejected(Interrupted))
      } else if state.active_depth >= state.maximum_active_depth {
        (state, Rejected(StackDepthLimit))
      } else if state.remaining_steps == 0L {
        (state, Rejected(ExecutionLimit))
      } else {
        (
          {
            remaining_steps: state.remaining_steps - 1L,
            maximum_active_depth: state.maximum_active_depth,
            active_depth: state.active_depth + 1L,
          },
          ActivationObserved,
        )
      }
    ReleaseActivation =>
      if state.active_depth == 0L {
        (state, Rejected(StaleActivationRelease))
      } else {
        (
          {
            remaining_steps: state.remaining_steps,
            maximum_active_depth: state.maximum_active_depth,
            active_depth: state.active_depth - 1L,
          },
          ActivationReleased,
        )
      }
  }
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
  mut state : ExecutionControlState
  interruption : ExecutionInterruptionRequest
}

///|
#warnings("-unused_value")
fn ExecutionControl::ExecutionControl(
  remaining_steps~ : Int64,
  maximum_active_depth~ : Int64,
  interruption~ : ExecutionInterruptionRequest,
) -> ExecutionControl raise ExecutionControlConfigurationError {
  let configuration = ExecutionControlConfiguration(
    remaining_steps~,
    maximum_active_depth~,
  )
  {
    state: {
      remaining_steps: configuration.remaining_steps,
      maximum_active_depth: configuration.maximum_active_depth,
      active_depth: 0L,
    },
    interruption,
  }
}

///|
#warnings("-unused_value")
fn ExecutionControl::remaining_steps(self : ExecutionControl) -> Int64 {
  self.state.remaining_steps
}

///|
#warnings("-unused_value")
fn ExecutionControl::active_depth(self : ExecutionControl) -> Int64 {
  self.state.active_depth
}

///|
fn ExecutionControl::transition(
  self : ExecutionControl,
  event : ExecutionControlEvent,
) -> ExecutionControlDecision {
  let (next_state, decision) = reduce_execution_control(self.state, event)
  self.state = next_state
  decision
}

///|
#warnings("-unused_value")
fn ExecutionControl::observe_step(
  self : ExecutionControl,
) -> Result[Unit, ExecutionControlFailure] {
  match self.transition(ObserveStep(self.interruption.is_requested())) {
    StepObserved => Ok(())
    Rejected(failure) => Err(failure)
    _ => Err(ExecutionLimit)
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
          [String_(operation)] if operation == EXECUTION_CONTROL_RELEASE =>
            match control.release_activation() {
              Ok(_) => Undefined
              Err(failure) => raise ExecutionControlError(failure)
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
pub fn Interpreter::observe_execution_step(
  self : Interpreter,
) -> Unit raise Error {
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
// Release is an ownership-only lifecycle hook. Valid dispatcher ownership
// always releases an acquired unit; the reducer rejects a stale zero-depth
// release without mutating state.
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
  errdefer restore_execution_control_binding(self.global, previous)
  let result = action()
  restore_execution_control_binding(self.global, previous)
  result
}

///|
#warnings("-unused_value")
fn ExecutionControl::observe_activation(
  self : ExecutionControl,
) -> Result[Unit, ExecutionControlFailure] {
  match self.transition(ObserveActivation(self.interruption.is_requested())) {
    ActivationObserved => Ok(())
    Rejected(failure) => Err(failure)
    _ => Err(ExecutionLimit)
  }
}

///|
fn ExecutionControl::release_activation(
  self : ExecutionControl,
) -> Result[Unit, ExecutionControlFailure] {
  match self.transition(ReleaseActivation) {
    ActivationReleased => Ok(())
    Rejected(failure) => Err(failure)
    _ => Err(StaleActivationRelease)
  }
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
        // Setup rejection records the acquired attempt; the dispatcher
        // releases it only after restoring the owned runtime state.
        rejected=() => (),
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
  match self.observe_activation() {
    Err(failure) => Err(failure)
    Ok(_) => {
      errdefer {
        let _ = self.release_activation()
      }
      let result = action()
      match self.release_activation() {
        Ok(_) => Ok(result)
        Err(failure) => Err(failure)
      }
    }
  }
}
