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
      self.observe_execution_step() catch {
        error => {
          policy.reject_dispatch_observation()
          raise error
        }
      }
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
  }) catch {
    e => raise e
  }
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
  // Create a job that will execute the reaction handler
  let job_callback = make_interp_method_func(
    name="PromiseReactionJob",
    length=0,
    realm_state=Some(interp.realm_state),
    fn(i, _this, args) raise {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      let loc = @token.Loc::default()

      // If handler is None, use identity (fulfill) or thrower (reject)
      match reaction.handler {
        Some(handler) => {
          // Try to call the handler
          let result = i.call_value(handler, Undefined, [value], loc) catch {
            e => {
              guard is_js_catchable_error(e) else { raise e }
              // Handler threw - reject the dependent promise
              let error_value = js_error_to_value_with_env(e, Some(i.global))
              let _ = i.call_value(
                reaction.reject,
                Undefined,
                [error_value],
                loc,
              )
              return Undefined
            }
          }
          // Resolve the dependent promise with handler result
          let _ = i.call_value(reaction.resolve, Undefined, [result], loc)
          Undefined
        }
        None =>
          // No handler - pass through value/reason
          match reaction.reaction_type {
            Fulfill => {
              let _ = i.call_value(reaction.resolve, Undefined, [value], loc)
              Undefined
            }
            Reject => {
              let _ = i.call_value(reaction.reject, Undefined, [value], loc)
              Undefined
            }
          }
      }
    },
  )
  interp.enqueue_microtask(job_callback, [argument])
}

///|
/// Create resolve and reject capability functions for a promise.
/// Returns (resolve_func, reject_func).
pub fn create_resolving_functions(
  interp : Interpreter,
  promise_data : PromiseData,
) -> (Value, Value) {
  // Track whether already resolved (prevents multiple resolution)
  let already_resolved : Ref[Bool] = { val: false }

  // Create resolve function
  let resolve_func = make_interp_method_func(
    name="",
    length=1,
    realm_state=Some(interp.realm_state),
    fn(i, _this, args) raise {
      if already_resolved.val {
        return Undefined
      }
      already_resolved.val = true
      let resolution = if args.length() > 0 { args[0] } else { Undefined }

      // Check for self-resolution (ECMAScript spec requirement)
      match resolution {
        Promise(pd) =>
          if physical_equal(pd, promise_data) {
            // Self-resolution: reject with TypeError
            let error = js_error_to_value_with_env(
              @errors.TypeError(message="Chaining cycle detected for promise"),
              Some(i.global),
            )
            reject_promise(i, promise_data, error)
            return Undefined
          }
        _ => ()
      }

      // Thenable assimilation (ECMAScript §25.6.1.3.2 steps 8-13)
      // If resolution is not an object, fulfill directly.
      // Otherwise, perform Get(resolution, "then") and check if callable.
      // This applies uniformly to both native Promises and plain objects
      // — the spec has no fast-path for native promises.
      if is_thenable_object_candidate(resolution) {
        // Get(resolution, "then") walks the prototype chain and
        // invokes accessors per ECMAScript spec
        let loc = @token.Loc::default()
        let then_val = i.get_property(resolution, "then", loc) catch {
          e => {
            guard is_js_catchable_error(e) else { raise e }
            // If Get throws, reject the promise with the error
            let err = js_error_to_value_with_env(e, Some(i.global))
            reject_promise(i, promise_data, err)
            return Undefined
          }
        }
        match then_val {
          Object(then_od) =>
            match then_od.callable {
              Some(_) => {
                // Thenable: enqueue PromiseResolveThenableJob
                let (res, rej) = create_resolving_functions(i, promise_data)
                let job = make_interp_method_func(
                  name="PromiseResolveThenableJob",
                  length=0,
                  realm_state=Some(i.realm_state),
                  fn(i2, _t, _a) raise {
                    try {
                      let _ = i2.call_value(
                        then_val,
                        resolution,
                        [res, rej],
                        loc,
                      )
                    } catch {
                      e => {
                        guard is_js_catchable_error(e) else { raise e }
                        let err = js_error_to_value_with_env(e, Some(i2.global))
                        let _ = i2.call_value(rej, Undefined, [err], loc)
                      }
                    }
                    Undefined
                  },
                )
                i.enqueue_microtask(job, [])
              }
              None => fulfill_promise(i, promise_data, resolution)
            }
          _ => fulfill_promise(i, promise_data, resolution)
        }
      } else {
        fulfill_promise(i, promise_data, resolution)
      }
      Undefined
    },
  )

  // Create reject function
  let reject_func = make_interp_method_func(
    name="",
    length=1,
    realm_state=Some(interp.realm_state),
    fn(i, _this, args) {
      if already_resolved.val {
        return Undefined
      }
      already_resolved.val = true
      let reason = if args.length() > 0 { args[0] } else { Undefined }
      reject_promise(i, promise_data, reason)
      Undefined
    },
  )
  (resolve_func, reject_func)
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
    let policy = TimerQueuePolicy(
      self.host.timer_queue,
      self.host.cancelled_timer_ids,
      self.host.timer_insertion_counter,
      TIMER_SAFETY_LIMIT,
    )
    while true {
      match policy.readiness() {
        TimerQueueEmpty | TimerQueueSafetyLimit => break
        TimerQueueObservationRequired => ()
      }
      self.observe_execution_step() catch {
        error => {
          policy.reject_dispatch_observation()
          return Err(
            TimerRunFailure(
              error,
              TimerRunFailurePhase::TimerQueueDispatch,
              None,
            ),
          )
        }
      }
      let timer = match policy.commit_next() {
        Some(timer) => timer
        None => continue
      }
      // Execute the timer callback
      let loc = @token.Loc::default()
      let call_result = observe_source_failure(self.realm_state, fn() raise {
        self.call_value(timer.callback, Undefined, timer.args, loc)
      })
      match call_result {
        Ok(_) => ()
        Err(failure) => {
          policy.callback_failed()
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
      policy.callback_succeeded()
      // Microtask checkpoint after each task (per WHATWG event loop spec)
      let microtask_result = self.run_microtasks_observed() catch {
        e => {
          policy.checkpoint_failed()
          return Err(
            TimerRunFailure(e, TimerRunFailurePhase::MicrotaskCheckpoint, None),
          )
        }
      }
      match microtask_result {
        Ok(_) => ()
        Err(failure) => {
          policy.checkpoint_failed()
          return Err(
            TimerRunFailure(
              failure.cause(),
              TimerRunFailurePhase::MicrotaskCheckpoint,
              failure.source_identity(),
            ),
          )
        }
      }
      policy.checkpoint_succeeded()
    }
    policy.complete_run()
    Ok(())
  }) catch {
    e => raise e
  }
}
