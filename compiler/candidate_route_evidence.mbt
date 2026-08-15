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
#warnings("-unused_field")
priv struct CandidateRouteSummary {
  mut verified_decisions : Int
  mut bytecode_starts : Int
  mut tree_starts : Int
  mut normal_completions : Int
  mut abrupt_completions : Int
  mut lowering_unsupported : Int
  mut activation_unsupported : Int
  mut active_activations : Int
  mut maximum_concurrent_activations : Int
  mut fallback_violations : Int
  mut replay_violations : Int
}

///|
fn CandidateRouteSummary::CandidateRouteSummary() -> CandidateRouteSummary {
  {
    verified_decisions: 0,
    bytecode_starts: 0,
    tree_starts: 0,
    normal_completions: 0,
    abrupt_completions: 0,
    lowering_unsupported: 0,
    activation_unsupported: 0,
    active_activations: 0,
    maximum_concurrent_activations: 0,
    fallback_violations: 0,
    replay_violations: 0,
  }
}

///|
priv struct CandidateRouteEvidence {
  mut next_activation_id : Int
  trace_enabled : Bool
  summary : CandidateRouteSummary
  // These collections are diagnostic trace storage only. Aggregate-only
  // production recorders never append or insert into them.
  events : Array[CandidateRouteEvent]
  lifecycles : Map[Int, CandidateRouteLifecycle]
}

///|
fn CandidateRouteEvidence::CandidateRouteEvidence(
  trace? : Bool = false,
) -> CandidateRouteEvidence {
  {
    next_activation_id: 0,
    trace_enabled: trace,
    summary: CandidateRouteSummary(),
    events: [],
    lifecycles: Map([]),
  }
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
  if evidence.val.trace_enabled {
    evidence.val.events.push(event)
  }
}

///|
fn candidate_route_record_lifecycle(
  evidence : Ref[CandidateRouteEvidence],
  activation_id : Int,
  lifecycle : CandidateRouteLifecycle,
) -> Unit {
  if evidence.val.trace_enabled {
    evidence.val.lifecycles[activation_id] = lifecycle
  }
}

///|
#warnings("-unused_value")
fn candidate_route_trace_length(evidence : Ref[CandidateRouteEvidence]) -> Int {
  evidence.val.events.length()
}

///|
priv struct CandidateRouteActivation {
  evidence : Ref[CandidateRouteEvidence]
  prepared : CandidateRoutePrepared
  lifecycle : Ref[CandidateRouteLifecycle]
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
  evidence.val.summary.verified_decisions += 1
  match decision {
    UseBytecode(_) => ()
    UseTreeWalker(CandidateLoweringUnsupported(_)) =>
      evidence.val.summary.lowering_unsupported += 1
    UseTreeWalker(CandidateActivationUnsupported(_)) =>
      evidence.val.summary.activation_unsupported += 1
  }
  let lifecycle : Ref[CandidateRouteLifecycle] = {
    val: CandidateRoutePending(prepared),
  }
  candidate_route_record_lifecycle(evidence, activation_id, lifecycle.val)
  candidate_route_record_event(evidence, CandidateRoutePreparedEvent(prepared))
  { evidence, prepared, lifecycle }
}

///|
fn candidate_route_start(
  activation : CandidateRouteActivation,
  executor : CandidateRouteExecutor,
) -> Unit raise Error {
  let current = activation.lifecycle.val
  match current {
    CandidateRoutePending(prepared) => {
      let expected_executor = match prepared.decision {
        UseBytecode(_) => CandidateBytecodeExecutor
        UseTreeWalker(_) => CandidateTreeWalkerExecutor
      }
      guard executor == expected_executor else {
        activation.evidence.val.summary.fallback_violations += 1
        raise @errors.InternalError(
          message="candidate route executor disagrees with prepared decision",
        )
      }
      let started = CandidateRouteStarted(
        prepared.activation_id,
        prepared.source_identity,
        executor,
      )
      activation.lifecycle.val = CandidateRouteRunning(started)
      candidate_route_record_lifecycle(
        activation.evidence,
        prepared.activation_id,
        activation.lifecycle.val,
      )
      match executor {
        CandidateBytecodeExecutor =>
          activation.evidence.val.summary.bytecode_starts += 1
        CandidateTreeWalkerExecutor =>
          activation.evidence.val.summary.tree_starts += 1
      }
      activation.evidence.val.summary.active_activations += 1
      activation.evidence.val.summary.maximum_concurrent_activations = activation.evidence.val.summary.maximum_concurrent_activations.max(
        activation.evidence.val.summary.active_activations,
      )
      candidate_route_record_event(
        activation.evidence,
        CandidateRouteStartedEvent(started),
      )
    }
    CandidateRouteRunning(_) => {
      activation.evidence.val.summary.replay_violations += 1
      raise @errors.InternalError(
        message="candidate route activation started more than once",
      )
    }
    CandidateRouteFinished(_) => {
      activation.evidence.val.summary.replay_violations += 1
      raise @errors.InternalError(
        message="candidate route activation was restarted after completion",
      )
    }
  }
}

///|
fn candidate_route_complete(
  activation : CandidateRouteActivation,
  completion : CandidateRouteCompletion,
) -> Unit raise Error {
  let current = activation.lifecycle.val
  match current {
    CandidateRouteRunning(started) => {
      let completed = CandidateRouteCompleted(
        started.activation_id,
        started.source_identity,
        completion,
      )
      activation.lifecycle.val = CandidateRouteFinished(completed)
      candidate_route_record_lifecycle(
        activation.evidence,
        activation.prepared.activation_id,
        activation.lifecycle.val,
      )
      activation.evidence.val.summary.active_activations -= 1
      match completion {
        CandidateRouteNormal =>
          activation.evidence.val.summary.normal_completions += 1
        CandidateRouteAbrupt =>
          activation.evidence.val.summary.abrupt_completions += 1
      }
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
      activation.evidence.val.summary.replay_violations += 1
      raise @errors.InternalError(
        message="candidate route activation completed more than once",
      )
    }
  }
}
