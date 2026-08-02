// Private decision core for timer and interval dispatch. Queue inspection,
// mutation, cancellation lookup, and callback execution stay in the shell.

///|
const TIMER_SAFETY_LIMIT = 10000

///|
priv enum TimerQueueReadiness {
  TimerQueueEmpty
  TimerQueueSafetyLimit
  TimerQueueObservationRequired
}

///|
fn[T] invalid_timer_queue_policy_transition(operation : String) -> T raise {
  fail("invalid timer queue policy transition: " + operation)
}

///|
priv enum TimerQueueCorePhase {
  TimerQueueCoreReady
  TimerQueueCoreCommitRequired
  TimerQueueCoreSelected(TimerTask)
  TimerQueueCoreCallbackSucceeded(TimerTask)
  TimerQueueCoreFailed
  TimerQueueCoreCompleted
}

///|
priv enum TimerQueueCommitDecision {
  TimerQueueDiscardCommitted
  TimerQueueRunCommitted(TimerTask)
}

///|
priv enum TimerQueueCheckpointDecision {
  TimerQueueDoNotRequeue
  TimerQueueRequeue(TimerTask)
}

///|
priv struct TimerQueuePolicyCore {
  safety_limit : Int
  iterations : Int
  phase : TimerQueueCorePhase
}

///|
fn TimerQueuePolicyCore::TimerQueuePolicyCore(
  safety_limit : Int,
) -> TimerQueuePolicyCore {
  { safety_limit, iterations: 0, phase: TimerQueueCoreReady }
}

///|
fn TimerQueuePolicyCore::readiness(
  self : TimerQueuePolicyCore,
  queue_is_empty : Bool,
) -> TimerQueueReadiness raise {
  guard self.phase is TimerQueueCoreReady else {
    invalid_timer_queue_policy_transition("readiness requires Ready")
  }
  if queue_is_empty {
    TimerQueueEmpty
  } else if self.iterations >= self.safety_limit {
    TimerQueueSafetyLimit
  } else {
    TimerQueueObservationRequired
  }
}

///|
fn TimerQueuePolicyCore::accept_dispatch_observation(
  self : TimerQueuePolicyCore,
  queue_is_empty : Bool,
) -> TimerQueuePolicyCore raise {
  match self.readiness(queue_is_empty) {
    TimerQueueObservationRequired =>
      { ..self, phase: TimerQueueCoreCommitRequired }
    TimerQueueEmpty | TimerQueueSafetyLimit =>
      invalid_timer_queue_policy_transition(
        "accept_dispatch_observation requires ObservationRequired",
      )
  }
}

///|
fn TimerQueuePolicyCore::reject_dispatch_observation(
  self : TimerQueuePolicyCore,
  queue_is_empty : Bool,
) -> TimerQueuePolicyCore raise {
  match self.readiness(queue_is_empty) {
    TimerQueueObservationRequired => self
    TimerQueueEmpty | TimerQueueSafetyLimit =>
      invalid_timer_queue_policy_transition(
        "reject_dispatch_observation requires ObservationRequired",
      )
  }
}

///|
fn TimerQueuePolicyCore::commit_popped(
  self : TimerQueuePolicyCore,
  timer : TimerTask,
  cancelled : Bool,
) -> (TimerQueuePolicyCore, TimerQueueCommitDecision) raise {
  guard self.phase is TimerQueueCoreCommitRequired else {
    invalid_timer_queue_policy_transition(
      "commit_popped requires CommitRequired",
    )
  }
  let iterations = self.iterations + 1
  if cancelled {
    (
      { ..self, iterations, phase: TimerQueueCoreReady },
      TimerQueueDiscardCommitted,
    )
  } else {
    (
      { ..self, iterations, phase: TimerQueueCoreSelected(timer) },
      TimerQueueRunCommitted(timer),
    )
  }
}

///|
fn TimerQueuePolicyCore::callback_succeeded(
  self : TimerQueuePolicyCore,
) -> TimerQueuePolicyCore raise {
  match self.phase {
    TimerQueueCoreSelected(timer) =>
      { ..self, phase: TimerQueueCoreCallbackSucceeded(timer) }
    TimerQueueCoreReady
    | TimerQueueCoreCommitRequired
    | TimerQueueCoreCallbackSucceeded(_)
    | TimerQueueCoreFailed
    | TimerQueueCoreCompleted =>
      invalid_timer_queue_policy_transition(
        "callback_succeeded requires Selected",
      )
  }
}

///|
fn TimerQueuePolicyCore::callback_failed(
  self : TimerQueuePolicyCore,
) -> TimerQueuePolicyCore raise {
  match self.phase {
    TimerQueueCoreSelected(_) => { ..self, phase: TimerQueueCoreFailed }
    TimerQueueCoreReady
    | TimerQueueCoreCommitRequired
    | TimerQueueCoreCallbackSucceeded(_)
    | TimerQueueCoreFailed
    | TimerQueueCoreCompleted =>
      invalid_timer_queue_policy_transition("callback_failed requires Selected")
  }
}

///|
fn TimerQueuePolicyCore::checkpoint_succeeded(
  self : TimerQueuePolicyCore,
  cancelled : Bool,
  insertion_order : Int,
) -> (TimerQueuePolicyCore, TimerQueueCheckpointDecision) raise {
  let timer = match self.phase {
    TimerQueueCoreCallbackSucceeded(timer) => timer
    TimerQueueCoreReady
    | TimerQueueCoreCommitRequired
    | TimerQueueCoreSelected(_)
    | TimerQueueCoreFailed
    | TimerQueueCoreCompleted =>
      invalid_timer_queue_policy_transition(
        "checkpoint_succeeded requires CallbackSucceeded",
      )
  }
  let decision = if timer.is_interval && !cancelled {
    TimerQueueRequeue({
      id: timer.id,
      callback: timer.callback,
      args: timer.args,
      delay: timer.delay + timer.period,
      period: timer.period,
      is_interval: true,
      insertion_order,
    })
  } else {
    TimerQueueDoNotRequeue
  }
  ({ ..self, phase: TimerQueueCoreReady }, decision)
}

///|
fn TimerQueuePolicyCore::checkpoint_failed(
  self : TimerQueuePolicyCore,
) -> TimerQueuePolicyCore raise {
  match self.phase {
    TimerQueueCoreCallbackSucceeded(_) =>
      { ..self, phase: TimerQueueCoreFailed }
    TimerQueueCoreReady
    | TimerQueueCoreCommitRequired
    | TimerQueueCoreSelected(_)
    | TimerQueueCoreFailed
    | TimerQueueCoreCompleted =>
      invalid_timer_queue_policy_transition(
        "checkpoint_failed requires CallbackSucceeded",
      )
  }
}

///|
fn TimerQueuePolicyCore::complete_run(
  self : TimerQueuePolicyCore,
  queue_is_empty : Bool,
) -> (TimerQueuePolicyCore, Bool) raise {
  guard self.phase is TimerQueueCoreReady else {
    invalid_timer_queue_policy_transition("complete_run requires Ready")
  }
  ({ ..self, phase: TimerQueueCoreCompleted }, queue_is_empty)
}
