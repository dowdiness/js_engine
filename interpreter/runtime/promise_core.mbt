// Ordering for the priority queue (max-heap as min-delay-first min-heap).
// A timer with smaller (delay, insertion_order) compares as "greater" so that
// @priority_queue.pop() always extracts the soonest-due timer first.
// Eq uses timer ID as the unique identity.

///|
pub impl Eq for TimerTask with fn equal(self : TimerTask, other : TimerTask) -> Bool {
  self.id == other.id
}

///|
pub impl Compare for TimerTask with fn compare(
  self : TimerTask,
  other : TimerTask,
) -> Int {
  let d = self.delay.compare(other.delay)
  if d != 0 {
    -d
  } else {
    -self.insertion_order.compare(other.insertion_order)
  }
}

///|
/// Enqueue a microtask to be executed when the current execution context completes.
/// This implements HostEnqueuePromiseJob from the ECMAScript spec.
pub fn Interpreter::enqueue_microtask(
  self : Interpreter,
  callback : Value,
  args : Array[Value],
) -> Unit {
  microtask_policy_enqueue(self.host.microtask_queue, { callback, args })
}

///|
/// A microtask-run failure paired with trustworthy callback provenance.
pub struct MicrotaskRunFailure {
  cause_ : Error
  source_identity_ : String?
}

///|
fn MicrotaskRunFailure::MicrotaskRunFailure(
  cause : Error,
  source_identity : String?,
) -> MicrotaskRunFailure {
  { cause_: cause, source_identity_: source_identity }
}

///|
pub fn MicrotaskRunFailure::cause(self : MicrotaskRunFailure) -> Error {
  self.cause_
}

///|
pub fn MicrotaskRunFailure::source_identity(
  self : MicrotaskRunFailure,
) -> String? {
  self.source_identity_
}

///|
/// Run all pending microtasks while retaining callback provenance on failure.
pub fn Interpreter::run_microtasks_observed(
  self : Interpreter,
) -> Result[Unit, MicrotaskRunFailure] raise Error {
  with_cleared_active_callee_realm(self.realm_state, fn() raise {
    let policy = MicrotaskQueuePolicy(self.host.microtask_queue)
    while true {
      match policy.readiness() {
        MicrotaskQueueEmpty => break
        MicrotaskObservationRequired => ()
      }
      errdefer policy.reject_dispatch_observation()
      self.observe_execution_step()
      let task = match policy.select_next() {
        Some(task) => task
        None => fail("microtask queue readiness changed before selection")
      }
      // Call the callback with queued arguments. Applicable activation
      // observation belongs to call_value; queue dispatch must not charge it a
      // second time.
      match task.callback {
        Object(obj_data) =>
          match obj_data.callable {
            Some(_) => {
              let loc = @token.Loc::default()
              let call_result = observe_source_failure(self.realm_state, fn() raise {
                self.call_value(task.callback, Undefined, task.args, loc)
              })
              match call_result {
                Ok(_) => ()
                Err(failure) => {
                  policy.fail_selected()
                  return Err(
                    MicrotaskRunFailure(
                      failure.cause(),
                      failure.source_identity(),
                    ),
                  )
                }
              }
            }
            None => ()
          }
        _ => ()
      }
      policy.complete_selected()
    }
    policy.complete_drain()
    Ok(())
  })
}

///|
/// Run all pending microtasks until the queue is empty.
/// This is called after each task (script execution) completes.
/// Implements the microtask checkpoint from WHATWG Event Loop spec.
pub fn Interpreter::run_microtasks(self : Interpreter) -> Unit raise Error {
  match self.run_microtasks_observed() {
    Ok(_) => ()
    Err(failure) => raise failure.cause()
  }
}

///|
/// ES object-like values that participate in thenable assimilation.
pub fn is_thenable_object_candidate(value : Value) -> Bool {
  match value {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => true
    _ => false
  }
}

///|
/// Fulfill a promise with the given value.
/// Triggers all fulfill reactions as microtasks.
pub fn fulfill_promise(
  interp : Interpreter,
  promise_data : PromiseData,
  value : Value,
) -> Unit {
  // Can only transition from Pending
  guard promise_data.state is Pending else { return }
  promise_data.state = Fulfilled
  promise_data.result = value

  // Trigger all fulfill reactions
  for reaction in promise_data.fulfill_reactions {
    enqueue_promise_reaction_job(interp, reaction, value)
  }

  // Clear reaction queues
  promise_data.fulfill_reactions.clear()
  promise_data.reject_reactions.clear()
}

///|
/// Reject a promise with the given reason.
/// Triggers all reject reactions as microtasks.
pub fn reject_promise(
  interp : Interpreter,
  promise_data : PromiseData,
  reason : Value,
) -> Unit {
  // Can only transition from Pending
  guard promise_data.state is Pending else { return }
  promise_data.state = Rejected
  promise_data.result = reason

  // Trigger all reject reactions
  for reaction in promise_data.reject_reactions {
    enqueue_promise_reaction_job(interp, reaction, reason)
  }

  // Clear reaction queues
  promise_data.fulfill_reactions.clear()
  promise_data.reject_reactions.clear()
}

///|
/// Enqueue a promise reaction job (microtask).
/// This implements NewPromiseReactionJob from ECMAScript spec.
pub fn enqueue_promise_reaction_job(
  interp : Interpreter,
  reaction : PromiseReaction,
  argument : Value,
) -> Unit {
  // #745 still owns observation, selection, consumption, and FIFO. The
  // selected callback is a private one-shot executor callable; the queued
  // argument remains in the generic Microtask carrier.
  let job_callback = make_promise_reaction_job(interp, reaction)
  interp.enqueue_microtask(job_callback, [argument])
}

///|
/// Create resolve and reject capability functions for a promise.
/// Returns (resolve_func, reject_func).
pub fn create_resolving_functions(
  interp : Interpreter,
  promise_data : PromiseData,
) -> (Value, Value) {
  make_promise_resolving_functions(interp, promise_data)
}

///|
/// Run the event loop: process all pending timer tasks with
/// microtask checkpoints between each (per WHATWG event loop spec).
/// Timers are sorted by (delay, insertion_order) so they fire in the
/// correct relative order. After each timer callback, microtasks are
/// drained before the next timer fires.
///
/// For setInterval, the timer is re-enqueued after each invocation
/// until cancelled. A safety limit prevents infinite loops.
pub fn Interpreter::run_timers(self : Interpreter) -> Unit raise Error {
  match self.run_timers_observed() {
    Ok(_) => ()
    Err(failure) => raise failure.cause()
  }
}

///|
/// Failure phase retained for the stable root facade's diagnostic adapter.
pub enum TimerRunFailurePhase {
  TimerQueueDispatch
  TimerCallback
  IntervalCallback
  MicrotaskCheckpoint
}

///|
/// A timer-run failure paired atomically with the phase that observed it.
pub struct TimerRunFailure {
  cause_ : Error
  phase_ : TimerRunFailurePhase
  source_identity_ : String?
}

///|
fn TimerRunFailure::TimerRunFailure(
  cause : Error,
  phase : TimerRunFailurePhase,
  source_identity : String?,
) -> TimerRunFailure {
  { cause_: cause, phase_: phase, source_identity_: source_identity }
}

///|
pub fn TimerRunFailure::cause(self : TimerRunFailure) -> Error {
  self.cause_
}

///|
pub fn TimerRunFailure::phase(self : TimerRunFailure) -> TimerRunFailurePhase {
  self.phase_
}

///|
pub fn TimerRunFailure::source_identity(self : TimerRunFailure) -> String? {
  self.source_identity_
}

///|
/// Run timers while retaining callback-vs-checkpoint context for direct
/// package dependents. Queue-policy defects still raise as internal failures.
pub fn Interpreter::run_timers_observed(
  self : Interpreter,
) -> Result[Unit, TimerRunFailure] raise Error {
  with_cleared_active_callee_realm(self.realm_state, fn() raise {
    let mut policy = TimerQueuePolicyCore(TIMER_SAFETY_LIMIT)
    while true {
      match policy.readiness(self.host.timer_queue.is_empty()) {
        TimerQueueEmpty | TimerQueueSafetyLimit => break
        TimerQueueObservationRequired => ()
      }
      self.observe_execution_step() catch {
        error => {
          let _ = policy.reject_dispatch_observation(
            self.host.timer_queue.is_empty(),
          )
          return Err(
            TimerRunFailure(
              error,
              TimerRunFailurePhase::TimerQueueDispatch,
              None,
            ),
          )
        }
      }
      policy = policy.accept_dispatch_observation(
        self.host.timer_queue.is_empty(),
      )
      let popped = match self.host.timer_queue.pop() {
        Some(timer) => timer
        None =>
          invalid_timer_queue_policy_transition(
            "accepted observation requires a queued timer",
          )
      }
      let cancelled = self.host.cancelled_timer_ids.contains(popped.id)
      let (next_policy, commit_decision) = policy.commit_popped(
        popped, cancelled,
      )
      policy = next_policy
      let timer = match commit_decision {
        TimerQueueDiscardCommitted => continue
        TimerQueueRunCommitted(timer) => timer
      }
      // Execute the timer callback
      let loc = @token.Loc::default()
      let call_result = observe_source_failure(self.realm_state, fn() raise {
        self.call_value(timer.callback, Undefined, timer.args, loc)
      })
      match call_result {
        Ok(_) => ()
        Err(failure) => {
          let _ = policy.callback_failed()
          let phase = if timer.is_interval {
            TimerRunFailurePhase::IntervalCallback
          } else {
            TimerRunFailurePhase::TimerCallback
          }
          return Err(
            TimerRunFailure(failure.cause(), phase, failure.source_identity()),
          )
        }
      }
      policy = policy.callback_succeeded()
      // Microtask checkpoint after each task (per WHATWG event loop spec)
      let microtask_result = self.run_microtasks_observed() catch {
        e => {
          let _ = policy.checkpoint_failed()
          return Err(
            TimerRunFailure(e, TimerRunFailurePhase::MicrotaskCheckpoint, None),
          )
        }
      }
      match microtask_result {
        Ok(_) => ()
        Err(failure) => {
          let _ = policy.checkpoint_failed()
          return Err(
            TimerRunFailure(
              failure.cause(),
              TimerRunFailurePhase::MicrotaskCheckpoint,
              failure.source_identity(),
            ),
          )
        }
      }
      let cancelled = self.host.cancelled_timer_ids.contains(timer.id)
      let insertion_order = self.host.timer_insertion_counter.val
      let (next_policy, checkpoint_decision) = policy.checkpoint_succeeded(
        cancelled, insertion_order,
      )
      policy = next_policy
      match checkpoint_decision {
        TimerQueueDoNotRequeue => ()
        TimerQueueRequeue(timer) => {
          self.host.timer_insertion_counter.val = insertion_order + 1
          self.host.timer_queue.push(timer)
        }
      }
    }
    let (_, clear_cancellations) = policy.complete_run(
      self.host.timer_queue.is_empty(),
    )
    if clear_cancellations {
      self.host.cancelled_timer_ids.clear()
    }
    Ok(())
  })
}
