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
