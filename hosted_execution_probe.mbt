///|
/// Experimental stateful embedding facade used by the exception/reentry probes.
/// This is intentionally small and is not a production API.
pub struct HostedProbe {
  priv session : ExecutionSession
  priv policy : @runtime.ExecutionPolicy
  priv mut next_frame : Int
  priv mut current_frame : Int?
  priv mut effects : Int
  priv mut terminal_cause : Error?
}

///|
pub struct HostedValue {
  priv owner : HostedProbe
  priv value : @runtime.Value
}

///|
priv struct HostedFrame {
  owner : HostedProbe
  id : Int
  mut active : Bool
}

///|
pub struct HostedCall {
  priv frame : HostedFrame
}

///|
fn HostedValue::HostedValue(
  owner : HostedProbe,
  value : @runtime.Value,
) -> HostedValue {
  { owner, value, }
}

///|
fn HostedCall::HostedCall(frame : HostedFrame) -> HostedCall {
  { frame, }
}

///|
// Kept inside the runtime's opaque terminal carrier until the public boundary.
// Retaining the error here avoids formatting host diagnostics during guest unwind.
priv suberror HostedCallbackFailure {
  HostedCallbackFailure(Error)
}

///|
pub(all) suberror HostedProbeError {
  HostedParse(String)
  HostedGuestThrow(HostedValue)
  HostedGuestThrowWithSecondary(
    primary~ : HostedValue,
    secondary~ : HostedValue
  )
  HostedTerminal(Error)
  HostedHostFailure(String)
  HostedForeignValue
  HostedExpiredHostCall
  HostedSessionBusy
  HostedSessionClosed
  HostedSessionFaulted
  HostedExpectedNumber
  HostedExpectedBool
  HostedExpectedString
}

///|
pub fn HostedProbe::HostedProbe(
  policy : @runtime.ExecutionPolicy,
) -> HostedProbe raise {
  {
    session: HostEnvironment().create_session(),
    policy,
    next_frame: 1,
    current_frame: None,
    effects: 0,
    terminal_cause: None,
  }
}

///|
pub fn HostedProbe::register(
  self : HostedProbe,
  name : String,
  callback : (HostedCall, Array[HostedValue]) -> HostedValue raise,
) -> Unit raise {
  self.require_available()
  let native = @runtime.make_native_func(
    name~,
    realm_state=Some(self.session.engine.interp.realm_state),
    args => self.dispatch_callback(callback, args),
  )
  self.session.engine.install_host_global(name, native)
}

///|
fn HostedProbe::dispatch_callback(
  self : HostedProbe,
  callback : (HostedCall, Array[HostedValue]) -> HostedValue raise,
  args : Array[@runtime.Value],
) -> @runtime.Value raise {
  self.session.engine.interp.check_hosted_execution()
  let id = self.next_frame
  self.next_frame += 1
  let frame = { owner: self, id, active: true, }
  let previous = self.current_frame
  self.current_frame = Some(id)
  let result : Result[HostedValue, Error] = Ok(
    {
      let value = callback(
        HostedCall::HostedCall(frame),
        args.map(value => HostedValue::HostedValue(self, value)),
      )
      self.require_owner(value)
      value
    },
  ) catch {
    error => Err(error)
  }
  frame.active = false
  self.current_frame = previous
  // A caught nested terminal wins over every callback outcome, including
  // guest throws, foreign returns, and errors raised by Host cleanup.
  self.session.engine.interp.check_hosted_execution()
  match result {
    Ok(value) => value.value
    Err(error) => {
      match error {
        @runtime.JsException(_) => ()
        _ =>
          match @runtime.hosted_execution_failure_cause(error) {
            Some(_) => ()
            None =>
              self.session.engine.interp.terminate_hosted_execution(
                HostedCallbackFailure(error),
              )
          }
      }
      raise error
    }
  }
}

///|
fn HostedProbe::require_available(
  self : HostedProbe,
) -> Unit raise HostedProbeError {
  match self.session.state {
    Available => ()
    Running => raise HostedSessionBusy
    Closed => raise HostedSessionClosed
    Faulted => raise HostedSessionFaulted
  }
}

///|
fn HostedProbe::require_live(self : HostedProbe) -> Unit raise HostedProbeError {
  match self.session.state {
    Available | Running => ()
    Closed => raise HostedSessionClosed
    Faulted => raise HostedSessionFaulted
  }
}

///|
fn HostedProbe::require_owner(
  self : HostedProbe,
  value : HostedValue,
) -> Unit raise HostedProbeError {
  guard physical_equal(self, value.owner) else { raise HostedForeignValue }
  self.require_live()
}

///|
fn HostedProbe::begin_nested(
  self : HostedProbe,
  frame : HostedFrame,
) -> Unit raise {
  let current_matches = match self.current_frame {
    Some(id) => id == frame.id
    None => false
  }
  guard frame.active && current_matches else { raise HostedExpiredHostCall }
  self.require_live()
  self.session.engine.interp.check_hosted_execution()
}

///|
fn HostedProbe::inner_call(
  self : HostedProbe,
  frame : HostedFrame,
  callee : HostedValue,
  receiver : HostedValue,
  args : Array[HostedValue],
) -> HostedValue raise {
  self.begin_nested(frame)
  self.require_owner(callee)
  self.require_owner(receiver)
  for arg in args {
    self.require_owner(arg)
  }
  let saved = self.current_frame
  self.current_frame = None
  let result : Result[@runtime.Value, Error] = Ok(
    self.session.engine.interp.call_value(
      callee.value,
      receiver.value,
      args.map(arg => arg.value),
      @token.Loc::default(),
    ),
  ) catch {
    error => Err(error)
  }
  self.current_frame = saved
  match result {
    Ok(value) => {
      self.session.engine.interp.check_hosted_execution()
      HostedValue::HostedValue(self, value)
    }
    Err(error) => raise error
  }
}

///|
fn HostedProbe::inner_get(
  self : HostedProbe,
  frame : HostedFrame,
  target : HostedValue,
  name : String,
) -> HostedValue raise {
  self.begin_nested(frame)
  self.require_owner(target)
  let saved = self.current_frame
  self.current_frame = None
  let result : Result[@runtime.Value, Error] = Ok(
    self.session.engine.interp.get_property(
      target.value,
      name,
      @token.Loc::default(),
    ),
  ) catch {
    error => Err(error)
  }
  self.current_frame = saved
  match result {
    Ok(value) => HostedValue::HostedValue(self, value)
    Err(error) => raise error
  }
}

///|
fn[T] HostedProbe::public_turn(
  self : HostedProbe,
  action : () -> T raise Error,
) -> T raise {
  self.require_available()
  self.session.state = Running
  let result : Result[T, Error] = Ok(
    self.session.engine.interp.with_hosted_execution_policy(self.policy, action),
  ) catch {
    error => Err(error)
  }
  match result {
    Ok(value) => {
      self.session.state = Available
      value
    }
    Err(error) =>
      match @runtime.hosted_execution_failure_cause(error) {
        Some(cause) => {
          self.session.state = Faulted
          self.terminal_cause = Some(cause)
          self.session.host_binding.invalidate_scheduled_turns()
          match cause {
            HostedCallbackFailure(error) =>
              raise HostedHostFailure(error.to_string())
            _ => raise HostedTerminal(cause)
          }
        }
        None => {
          self.session.state = Available
          raise error
        }
      }
  }
}

///|
pub fn HostedProbe::global(
  self : HostedProbe,
  name : String,
) -> HostedValue raise {
  self.public_turn(() => {
    let value = self.session.engine.get_global_export_for_diagnostic(name)
    HostedValue::HostedValue(self, value)
  })
}

///|
pub fn HostedProbe::evaluate(
  self : HostedProbe,
  source : String,
) -> HostedValue raise {
  let program = @parser.parse(source) catch {
    error => raise HostedParse(error.to_string())
  }
  let outcome : Result[HostedValue, HostedValue] = self.public_turn(() => {
    self.session.engine.interp.check_hosted_execution()
    let body : Result[@runtime.Value, Error] = Ok(
      if @engine_candidate_mode.candidate_mode_enabled() {
        @compiler.run_candidate_program(
          self.session.engine.interp,
          program.stmts,
        )
      } else {
        self.session.engine.interp.run(program.stmts)
      },
    ) catch {
      error => Err(error)
    }
    let primary = match body {
      Ok(value) => Ok(HostedValue::HostedValue(self, value))
      Err(@runtime.JsException(value)) =>
        Err(HostedValue::HostedValue(self, value))
      Err(error) => raise error
    }
    self.session.engine.interp.check_hosted_execution()
    let checkpoint : Result[Unit, Error] = Ok(
      self.session.engine.interp.run_microtasks(),
    ) catch {
      error => Err(error)
    }
    match checkpoint {
      Ok(_) => primary
      Err(@runtime.JsException(value)) =>
        match primary {
          Ok(_) => Err(HostedValue::HostedValue(self, value))
          Err(first) =>
            raise HostedGuestThrowWithSecondary(
              primary=first,
              secondary=HostedValue::HostedValue(self, value),
            )
        }
      Err(error) => raise error
    }
  })
  match outcome {
    Ok(value) => value
    Err(value) => raise HostedGuestThrow(value)
  }
}

///|
pub fn HostedProbe::number(
  self : HostedProbe,
  value : Double,
) -> HostedValue raise {
  self.require_available()
  { owner: self, value: @runtime.Number(value), }
}

///|
pub fn HostedProbe::effect_count(self : HostedProbe) -> Int {
  self.effects
}

///|
pub fn HostedProbe::state(self : HostedProbe) -> String {
  match self.session.state {
    Available => "available"
    Running => "running"
    Closed => "closed"
    Faulted => "faulted"
  }
}

///|
pub fn HostedProbe::close(self : HostedProbe) -> Unit raise {
  self.session.close()
}

///|
pub fn HostedValue::expect_number(
  self : HostedValue,
) -> Double raise HostedProbeError {
  self.owner.require_live()
  match self.value {
    Number(value) => value
    _ => raise HostedExpectedNumber
  }
}

///|
pub fn HostedProbe::terminal_cause(self : HostedProbe) -> Error? {
  self.terminal_cause
}

///|
pub fn HostedValue::expect_bool(
  self : HostedValue,
) -> Bool raise HostedProbeError {
  self.owner.require_live()
  match self.value {
    Bool(value) => value
    _ => raise HostedExpectedBool
  }
}

///|
pub fn HostedValue::expect_string(
  self : HostedValue,
) -> String raise HostedProbeError {
  self.owner.require_live()
  match self.value {
    String_(value) => value
    _ => raise HostedExpectedString
  }
}

///|
pub fn HostedValue::get(self : HostedValue, name : String) -> HostedValue raise {
  self.owner.public_turn(() => {
    let value = self.owner.session.engine.interp.get_property(
      self.value,
      name,
      @token.Loc::default(),
    )
    HostedValue::HostedValue(self.owner, value)
  })
}

///|
pub fn HostedValue::call(
  self : HostedValue,
  args : Array[HostedValue],
) -> HostedValue raise {
  self.owner.public_turn(() => {
    for arg in args {
      self.owner.require_owner(arg)
    }
    let value = self.owner.session.engine.interp.call_value(
      self.value,
      @runtime.Undefined,
      args.map(arg => arg.value),
      @token.Loc::default(),
    )
    HostedValue::HostedValue(self.owner, value)
  })
}

///|
pub fn HostedValue::call_property(
  self : HostedValue,
  name : String,
  args : Array[HostedValue],
) -> HostedValue raise {
  self.owner.public_turn(() => {
    for arg in args {
      self.owner.require_owner(arg)
    }
    let callee = self.owner.session.engine.interp.get_property(
      self.value,
      name,
      @token.Loc::default(),
    )
    // A getter can reenter Host code and replace elements of the argument array.
    for arg in args {
      self.owner.require_owner(arg)
    }
    let value = self.owner.session.engine.interp.call_value(
      callee,
      self.value,
      args.map(arg => arg.value),
      @token.Loc::default(),
    )
    HostedValue::HostedValue(self.owner, value)
  })
}

///|
pub fn HostedCall::get(
  self : HostedCall,
  value : HostedValue,
  name : String,
) -> HostedValue raise {
  self.frame.owner.inner_get(self.frame, value, name)
}

///|
pub fn HostedCall::call(
  self : HostedCall,
  function : HostedValue,
  args : Array[HostedValue],
) -> HostedValue raise {
  self.frame.owner.inner_call(
    self.frame,
    function,
    HostedValue::HostedValue(self.frame.owner, @runtime.Undefined),
    args,
  )
}

///|
pub fn HostedCall::call_property(
  self : HostedCall,
  value : HostedValue,
  name : String,
  args : Array[HostedValue],
) -> HostedValue raise {
  self.frame.owner.begin_nested(self.frame)
  // Host arrays are mutable: check arguments before the getter and again in
  // inner_call after it returns.
  for arg in args {
    self.frame.owner.require_owner(arg)
  }
  let function = self.get(value, name)
  self.frame.owner.inner_call(self.frame, function, value, args)
}

///|
pub fn HostedCall::record_effect(self : HostedCall) -> Unit raise {
  self.frame.owner.begin_nested(self.frame)
  self.frame.owner.effects += 1
}

///|
pub fn HostedProbe::bool(self : HostedProbe, value : Bool) -> HostedValue raise {
  self.require_available()
  { owner: self, value: @runtime.Bool(value), }
}

///|
pub fn HostedProbe::string(
  self : HostedProbe,
  value : String,
) -> HostedValue raise {
  self.require_available()
  { owner: self, value: @runtime.String_(value), }
}

///|
pub fn HostedCall::throw_value(
  self : HostedCall,
  value : HostedValue,
) -> Unit raise {
  self.frame.owner.begin_nested(self.frame)
  self.frame.owner.require_owner(value)
  @runtime.raise_js_exception(value.value)
}

///|
pub fn HostedCall::terminate(self : HostedCall, cause : Error) -> Unit raise {
  self.frame.owner.begin_nested(self.frame)
  self.frame.owner.session.engine.interp.terminate_hosted_execution(cause)
}
