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
} derive(Eq)

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
  {
    next_activation_id: 0,
    events: [],
    lifecycles: Map([]),
  }
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
  let prepared = CandidateRoutePrepared(activation_id, source_identity, decision)
  evidence.val.lifecycles[activation_id] = CandidateRoutePending(prepared)
  evidence.val.events.push(CandidateRoutePreparedEvent(prepared))
  { evidence, prepared }
}

///|
fn candidate_route_start(
  activation : CandidateRouteActivation,
  executor : CandidateRouteExecutor,
) -> Unit raise Error {
  let current = match activation.evidence.val.lifecycles.get(
    activation.prepared.activation_id,
  ) {
    Some(lifecycle) => lifecycle
    None =>
      raise @errors.InternalError(
        message="candidate route activation is not prepared",
      )
  }
  match current {
    CandidateRoutePending(prepared) => {
      let decision_matches = match (prepared.decision, executor) {
        (UseBytecode(_), CandidateBytecodeExecutor)
        | (UseTreeWalker(_), CandidateTreeWalkerExecutor) => true
        _ => false
      }
      guard decision_matches else {
        raise @errors.InternalError(
          message="candidate route executor disagrees with prepared decision",
        )
      }
      let started = CandidateRouteStarted(
        prepared.activation_id,
        prepared.source_identity,
        executor,
      )
      activation.evidence.val.lifecycles[prepared.activation_id] =
        CandidateRouteRunning(started)
      activation.evidence.val.events.push(CandidateRouteStartedEvent(started))
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
  let current = match activation.evidence.val.lifecycles.get(
    activation.prepared.activation_id,
  ) {
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
      activation.evidence.val.lifecycles[activation.prepared.activation_id] =
        CandidateRouteFinished(completed)
      activation.evidence.val.events.push(
        CandidateRouteCompletedEvent(completed),
      )
    }
    CandidateRoutePending(_) =>
      raise @errors.InternalError(
        message="candidate route completed before executor start",
      )
    CandidateRouteFinished(_) =>
      raise @errors.InternalError(
        message="candidate route activation completed more than once",
      )
  }
}
