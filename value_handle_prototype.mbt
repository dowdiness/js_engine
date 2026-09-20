///|
// THROWAWAY value-handle API experiment; not a production API.
// Uses the real ExecutionSession Hosted Turn, failure and checkpoint machinery.
// Questions: strict extraction, retained identity, atomic method calls, Host
// failure vs JS rejection, cross-owner admission, reentry and close semantics.
// Assumptions: synchronous single-threaded calls; handles retain their owner;
// pure inspection is allowed inside a callback, JS reentry is rejected.
pub struct ProbeRuntime {
  priv session : ExecutionSession
}

///|
pub struct ProbeValue {
  priv owner : ProbeRuntime
  priv value : @runtime.Value
}

///|
pub suberror ProbeTypeError {
  ExpectedNumber
}

///|
pub suberror ProbeOwnerError {
  ForeignValue
}

///|
pub fn ProbeRuntime::ProbeRuntime(
  functions? : Map[
    String,
    (ProbeRuntime, Array[ProbeValue]) -> ProbeValue raise,
  ] = {},
) -> ProbeRuntime raise {
  let self = { session: HostEnvironment().create_session(), }
  for name, callback in functions {
    let native = @runtime.make_native_func(
      name~,
      realm_state=Some(self.session.engine.interp.realm_state),
      args => {
        let result = callback(self, args.map(value => ProbeValue(self, value))) catch {
          ExpectedNumber => raise @errors.TypeError(message="expected number")
          other => {
            self.session.host_binding.record_failure(name, other)
            raise @errors.InternalError(message="prototype Host failure")
          }
        }
        self.require_owner(result) catch {
          other => {
            self.session.host_binding.record_failure(name, other)
            raise @errors.InternalError(message="foreign Host return value")
          }
        }
        result.value
      },
    )
    self.session.engine.install_host_global(name, native)
  }
  self
}

///|
fn ProbeValue::ProbeValue(
  owner : ProbeRuntime,
  value : @runtime.Value,
) -> ProbeValue {
  { owner, value, }
}

///|
fn ProbeRuntime::require_live(
  self : ProbeRuntime,
) -> Unit raise ExecutionSessionError {
  match self.session.state {
    Available | Running => ()
    Closed => raise SessionClosed
    Faulted => raise SessionFaulted
  }
}

///|
fn ProbeRuntime::require_owner(
  self : ProbeRuntime,
  value : ProbeValue,
) -> Unit raise {
  guard physical_equal(self, value.owner) else { raise ForeignValue }
  self.require_live()
}

///|
fn ProbeRuntime::turn(
  self : ProbeRuntime,
  action : () -> @runtime.Value raise,
) -> ProbeValue raise {
  let result = self.session.run_hosted_turn(() => {
    Ok(action()) catch {
      error =>
        Err(
          runtime_engine_diagnostic(
            error,
            operation="prototype-value",
            phase="execute",
            source_identity=None,
            javascript_integrity=Reusable,
            javascript_effects=MayRemain,
            javascript_jobs=self.session.engine.pending_jobs_snapshot(),
            internal_integrity=Discard,
          ),
        )
    }
  })
  ProbeValue(self, result)
}

///|
pub fn ProbeRuntime::evaluate(
  self : ProbeRuntime,
  source : String,
) -> Unit raise {
  self.session.evaluate(source)
}

///|
pub fn ProbeRuntime::global(
  self : ProbeRuntime,
  name : String,
) -> ProbeValue raise {
  self.turn(() => self.session.engine.get_global_export_for_diagnostic(name))
}

///|
pub fn ProbeRuntime::number(
  self : ProbeRuntime,
  value : Double,
) -> ProbeValue raise {
  self.require_live()
  ProbeValue(self, @runtime.Number(value))
}

///|
pub fn ProbeRuntime::close(self : ProbeRuntime) -> Unit raise {
  self.session.close()
}

///|
pub fn ProbeRuntime::state(self : ProbeRuntime) -> String {
  match self.session.state {
    Available => "available"
    Running => "running"
    Closed => "closed"
    Faulted => "faulted"
  }
}

///|
pub fn ProbeValue::expect_number(self : ProbeValue) -> Double raise {
  self.owner.require_live()
  match self.value {
    Number(n) => n
    _ => raise ExpectedNumber
  }
}

///|
pub fn ProbeValue::coerce_number(self : ProbeValue) -> Double raise {
  self.owner
  .turn(() => {
    @runtime.Number(self.owner.session.engine.interp.to_number(self.value))
  })
  .expect_number()
}

///|
pub fn ProbeValue::get(self : ProbeValue, name : String) -> ProbeValue raise {
  self.owner.turn(() => {
    self.owner.session.engine.interp.get_property(
      self.value,
      name,
      @token.Loc::default(),
    )
  })
}

///|
pub fn ProbeValue::call_method(
  self : ProbeValue,
  name : String,
  args : Array[ProbeValue],
) -> ProbeValue raise {
  self.owner.require_live()
  for arg in args {
    self.owner.require_owner(arg)
  }
  self.owner.turn(() => {
    let interp = self.owner.session.engine.interp
    let function = interp.get_property(self.value, name, @token.Loc::default())
    interp.call_value(
      function,
      self.value,
      args.map(arg => arg.value),
      @token.Loc::default(),
    )
  })
}

///|
pub fn ProbeValue::call_with_this(
  self : ProbeValue,
  receiver : ProbeValue,
  args : Array[ProbeValue],
) -> ProbeValue raise {
  self.owner.require_owner(receiver)
  for arg in args {
    self.owner.require_owner(arg)
  }
  self.owner.turn(() => {
    self.owner.session.engine.interp.call_value(
      self.value,
      receiver.value,
      args.map(arg => arg.value),
      @token.Loc::default(),
    )
  })
}
