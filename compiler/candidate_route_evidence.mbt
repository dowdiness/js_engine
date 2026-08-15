///|
// Candidate routing is deliberately represented as a closed lifecycle.  The
// only legal transition after preparation is one executor start followed by a
// completion; there is no fallback or replay event in this model.
priv enum CandidateRouteExecutor {
  CandidateBytecodeExecutor
  CandidateTreeWalkerExecutor
} derive(Eq)

///|
priv struct CandidateRoutePrepared {
  activation_id : Int
  source_identity : BytecodeSourceIdentity
  decision : CandidateSelection
}

///|
fn CandidateRoutePrepared::CandidateRoutePrepared(
  activation_id : Int,
  source_identity : BytecodeSourceIdentity,
  decision : CandidateSelection,
) -> CandidateRoutePrepared {
  { activation_id, source_identity, decision }
}

///|
priv struct CandidateRouteStarted {
  activation_id : Int
  source_identity : BytecodeSourceIdentity
  executor : CandidateRouteExecutor
}

///|
fn CandidateRouteStarted::CandidateRouteStarted(
  activation_id : Int,
  source_identity : BytecodeSourceIdentity,
  executor : CandidateRouteExecutor,
) -> CandidateRouteStarted {
  { activation_id, source_identity, executor }
}

///|
priv struct CandidateRouteCompleted {
  activation_id : Int
  source_identity : BytecodeSourceIdentity
  completion : CandidateRouteCompletion
}

///|
fn CandidateRouteCompleted::CandidateRouteCompleted(
  activation_id : Int,
  source_identity : BytecodeSourceIdentity,
  completion : CandidateRouteCompletion,
) -> CandidateRouteCompleted {
  { activation_id, source_identity, completion }
}

///|
priv enum CandidateRouteCompletion {
  CandidateRouteNormal
  CandidateRouteAbrupt
}

///|
priv enum CandidateRouteEvent {
  CandidateRoutePreparedEvent(CandidateRoutePrepared)
  CandidateRouteStartedEvent(CandidateRouteStarted)
  CandidateRouteCompletedEvent(CandidateRouteCompleted)
}

///|
priv enum CandidateRouteLifecycle {
  CandidateRoutePending(CandidateRoutePrepared)
  CandidateRouteRunning(CandidateRouteStarted)
  CandidateRouteFinished(CandidateRouteCompleted)
}

///|
priv struct CandidateRouteEvidence {
  mut next_activation_id : Int
  events : Array[CandidateRouteEvent]
  lifecycles : Map[Int, CandidateRouteLifecycle]
}

///|
fn CandidateRouteEvidence::CandidateRouteEvidence() -> CandidateRouteEvidence {
  { next_activation_id: 0, events: [], lifecycles: Map([]) }
}

///|
// Keep the evidence values typed all the way to storage. This small recorder
// also forces every event payload to remain part of the private invariant,
// rather than degrading into an uninspected string log.
fn candidate_route_record_event(
  evidence : Ref[CandidateRouteEvidence],
  event : CandidateRouteEvent,
) -> Unit {
  match event {
    CandidateRoutePreparedEvent(prepared) => {
      ignore(prepared.activation_id)
      ignore(prepared.source_identity)
      ignore(prepared.decision)
    }
    CandidateRouteStartedEvent(started) => {
      ignore(started.activation_id)
      ignore(started.source_identity)
      ignore(started.executor)
    }
    CandidateRouteCompletedEvent(completed) => {
      ignore(completed.activation_id)
      ignore(completed.source_identity)
      match completed.completion {
        CandidateRouteNormal => ()
        CandidateRouteAbrupt => ()
      }
    }
  }
  evidence.val.events.push(event)
}

///|
priv struct CandidateRouteActivation {
  evidence : Ref[CandidateRouteEvidence]
  prepared : CandidateRoutePrepared
}

///|
fn candidate_route_prepare(
  evidence : Ref[CandidateRouteEvidence],
  source_identity : BytecodeSourceIdentity,
  decision : CandidateSelection,
) -> CandidateRouteActivation {
  let activation_id = evidence.val.next_activation_id
  evidence.val.next_activation_id += 1
  let prepared = CandidateRoutePrepared(
    activation_id, source_identity, decision,
  )
  evidence.val.lifecycles[activation_id] = CandidateRoutePending(prepared)
  candidate_route_record_event(evidence, CandidateRoutePreparedEvent(prepared))
  { evidence, prepared }
}

///|
fn candidate_route_start(
  activation : CandidateRouteActivation,
  executor : CandidateRouteExecutor,
) -> Unit raise Error {
  let current = match
    activation.evidence.val.lifecycles.get(activation.prepared.activation_id) {
    Some(lifecycle) => lifecycle
    None =>
      raise @errors.InternalError(
        message="candidate route activation is not prepared",
      )
  }
  match current {
    CandidateRoutePending(prepared) => {
      let expected_executor = match prepared.decision {
        UseBytecode(_) => CandidateBytecodeExecutor
        UseTreeWalker(_) => CandidateTreeWalkerExecutor
      }
      guard executor == expected_executor else {
        raise @errors.InternalError(
          message="candidate route executor disagrees with prepared decision",
        )
      }
      let started = CandidateRouteStarted(
        prepared.activation_id,
        prepared.source_identity,
        executor,
      )
      activation.evidence.val.lifecycles[prepared.activation_id] = CandidateRouteRunning(
        started,
      )
      candidate_route_record_event(
        activation.evidence,
        CandidateRouteStartedEvent(started),
      )
    }
    CandidateRouteRunning(_) =>
      raise @errors.InternalError(
        message="candidate route activation started more than once",
      )
    CandidateRouteFinished(_) =>
      raise @errors.InternalError(
        message="candidate route activation was restarted after completion",
      )
  }
}

///|
fn candidate_route_complete(
  activation : CandidateRouteActivation,
  completion : CandidateRouteCompletion,
) -> Unit raise Error {
  let current = match
    activation.evidence.val.lifecycles.get(activation.prepared.activation_id) {
    Some(lifecycle) => lifecycle
    None =>
      raise @errors.InternalError(
        message="candidate route activation is not prepared",
      )
  }
  match current {
    CandidateRouteRunning(started) => {
      let completed = CandidateRouteCompleted(
        started.activation_id,
        started.source_identity,
        completion,
      )
      activation.evidence.val.lifecycles[activation.prepared.activation_id] = CandidateRouteFinished(
        completed,
      )
      candidate_route_record_event(
        activation.evidence,
        CandidateRouteCompletedEvent(completed),
      )
    }
    CandidateRoutePending(_) =>
      raise @errors.InternalError(
        message="candidate route completed before executor start",
      )
    CandidateRouteFinished(completed) => {
      ignore(completed.completion)
      raise @errors.InternalError(
        message="candidate route activation completed more than once",
      )
    }
  }
}
