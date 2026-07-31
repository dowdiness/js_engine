// Policy-free activation lifecycle ownership for the dispatcher shell. This
// module records one accepted-or-rejected entry outcome and exactly one release
// for each accepted guest activation. Logical-depth policy remains in #617.

///|
priv suberror InvalidActivationObservationTransition {
  InvalidActivationObservationTransition(String)
}

///|
#warnings("-unused_constructor")
priv enum ActivationObservationPhase {
  ActivationEntryAttempted
  ActivationEntryAccepted
  ActivationEntryRejected
  ActivationReleased
}

///|
priv enum ActivationObservationEvent {
  AcceptActivationEntry
  RejectActivationEntry
  ReleaseObservedActivation
  ReleaseRejectedActivation
}

///|
priv enum ActivationObservationDecision {
  EmitActivationAccepted
  EmitActivationRejected
  EmitActivationReleased
}

///|
fn[T] invalid_activation_observation_transition(
  message : String,
) -> T raise InvalidActivationObservationTransition {
  raise InvalidActivationObservationTransition(message)
}

///|
fn reduce_activation_observation(
  phase : ActivationObservationPhase,
  event : ActivationObservationEvent,
) -> (ActivationObservationPhase, ActivationObservationDecision) raise InvalidActivationObservationTransition {
  match (phase, event) {
    (ActivationEntryAttempted, AcceptActivationEntry) =>
      (ActivationEntryAccepted, EmitActivationAccepted)
    (ActivationEntryAttempted, RejectActivationEntry) =>
      (ActivationEntryRejected, EmitActivationRejected)
    (ActivationEntryAccepted, ReleaseObservedActivation) =>
      (ActivationReleased, EmitActivationReleased)
    (ActivationEntryRejected, ReleaseRejectedActivation) =>
      (ActivationReleased, EmitActivationReleased)
    _ =>
      invalid_activation_observation_transition(
        "activation observation capability is stale or out of order",
      )
  }
}

///|
priv struct ActivationObservationAttemptHooks {
  accepted : () -> Unit
  rejected : () -> Unit
  released : () -> Unit
}

///|
fn ActivationObservationAttemptHooks::ActivationObservationAttemptHooks(
  accepted~ : () -> Unit,
  rejected~ : () -> Unit,
  released~ : () -> Unit,
) -> ActivationObservationAttemptHooks {
  { accepted, rejected, released }
}

///|
priv struct ActivationObservationPort {
  begin_entry : () -> ActivationObservationAttemptHooks raise Error
  denied : () -> Unit
}

///|
fn ActivationObservationPort::ActivationObservationPort(
  begin_entry~ : () -> ActivationObservationAttemptHooks raise Error,
  denied~ : () -> Unit,
) -> ActivationObservationPort {
  { begin_entry, denied }
}

///|
priv struct ActivationEntryAttempt {
  phase : Ref[ActivationObservationPhase]
  hooks : ActivationObservationAttemptHooks
}

///|
fn ActivationEntryAttempt::ActivationEntryAttempt(
  hooks : ActivationObservationAttemptHooks,
) -> ActivationEntryAttempt {
  { phase: { val: ActivationEntryAttempted }, hooks }
}

///|
priv struct ActivationObservationToken {
  phase : Ref[ActivationObservationPhase]
  released : () -> Unit
}

///|
fn ActivationObservationToken::ActivationObservationToken(
  phase~ : Ref[ActivationObservationPhase],
  released~ : () -> Unit,
) -> ActivationObservationToken {
  { phase, released }
}

///|
#warnings("-unused_value")
fn observe_activation_entry(
  port : ActivationObservationPort,
) -> ActivationEntryAttempt raise Error {
  let hooks = (port.begin_entry)() catch {
    error => {
      (port.denied)()
      raise error
    }
  }
  ActivationEntryAttempt(hooks)
}

///|
#warnings("-unused_value")
fn ActivationEntryAttempt::accept(
  self : ActivationEntryAttempt,
) -> ActivationObservationToken raise InvalidActivationObservationTransition {
  let (next_phase, decision) = reduce_activation_observation(
    self.phase.val,
    AcceptActivationEntry,
  )
  self.phase.val = next_phase
  match decision {
    EmitActivationAccepted => (self.hooks.accepted)()
    _ =>
      invalid_activation_observation_transition(
        "accept entry produced an invalid observation decision",
      )
  }
  ActivationObservationToken(phase=self.phase, released=self.hooks.released)
}

///|
#warnings("-unused_value")
fn ActivationEntryAttempt::reject(
  self : ActivationEntryAttempt,
) -> Unit raise InvalidActivationObservationTransition {
  let (next_phase, decision) = reduce_activation_observation(
    self.phase.val,
    RejectActivationEntry,
  )
  self.phase.val = next_phase
  match decision {
    EmitActivationRejected => (self.hooks.rejected)()
    _ =>
      invalid_activation_observation_transition(
        "reject entry produced an invalid observation decision",
      )
  }
}

///|
// Setup rejection is distinct from denial: the entry observation may already
// have acquired an activation unit. The shell records the rejected attempt,
// restores its owned runtime state, and calls this method exactly once after
// restoration so the release hook observes the restored state.
fn ActivationEntryAttempt::release_after_rejection(
  self : ActivationEntryAttempt,
) -> Unit raise InvalidActivationObservationTransition {
  let (next_phase, decision) = reduce_activation_observation(
    self.phase.val,
    ReleaseRejectedActivation,
  )
  self.phase.val = next_phase
  match decision {
    EmitActivationReleased => (self.hooks.released)()
    _ =>
      invalid_activation_observation_transition(
        "rejected activation release produced an invalid observation decision",
      )
  }
}

///|
#warnings("-unused_value")
fn ActivationObservationToken::release(
  self : ActivationObservationToken,
) -> Unit raise InvalidActivationObservationTransition {
  let (next_phase, decision) = reduce_activation_observation(
    self.phase.val,
    ReleaseObservedActivation,
  )
  self.phase.val = next_phase
  match decision {
    EmitActivationReleased => (self.released)()
    _ =>
      invalid_activation_observation_transition(
        "release produced an invalid observation decision",
      )
  }
}

///|
#warnings("-unused_value")
fn allow_all_activation_observation_port() -> ActivationObservationPort {
  ActivationObservationPort(
    begin_entry=() => {
      ActivationObservationAttemptHooks(accepted=() => (), rejected=() => (), released=() => {
        ()
      })
    },
    denied=() => (),
  )
}
