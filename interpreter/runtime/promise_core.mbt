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
/// Run all pending microtasks until the queue is empty.
/// This is called after each task (script execution) completes.
/// Implements the microtask checkpoint from WHATWG Event Loop spec.
pub fn Interpreter::run_microtasks(self : Interpreter) -> Unit raise Error {
  with_cleared_active_callee_realm(self.realm_state, fn() raise {
    let policy = MicrotaskQueuePolicy(self.host.microtask_queue)
    while true {
      let task = match policy.select_next() {
        Some(task) => task
        None => break
      }
      // Call the callback with queued arguments
      match task.callback {
        Object(obj_data) =>
          match obj_data.callable {
            Some(_) => {
              let loc = @token.Loc::default()
              let _ = self.call_value(task.callback, Undefined, task.args, loc) catch {
                e => {
                  policy.fail_selected()
                  raise e
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
  }) catch {
    e => raise e
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
    fn(i, _this, args) {
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
  with_cleared_active_callee_realm(self.realm_state, fn() raise {
    // Safety limit to prevent infinite loops from setInterval
    let max_iterations = 10000
    let mut iterations = 0
    while self.host.timer_queue.length() > 0 && iterations < max_iterations {
      iterations = iterations + 1
      // pop() extracts the soonest-due timer via the Compare impl
      let timer = match self.host.timer_queue.pop() {
        Some(t) => t
        None => break // unreachable: guarded by length() > 0 above
      }
      // Lazy deletion: skip timers cancelled via clearTimeout/clearInterval
      if self.host.cancelled_timer_ids.contains(timer.id) {
        continue
      }
      // Execute the timer callback
      let loc = @token.Loc::default()
      let _ = self.call_value(timer.callback, Undefined, timer.args, loc)
      // Microtask checkpoint after each task (per WHATWG event loop spec)
      self.run_microtasks()
      // If this is setInterval and not cancelled inside the callback, re-enqueue.
      // cancelled_timer_ids covers both pre-pop and in-callback cancellation.
      if timer.is_interval && !self.host.cancelled_timer_ids.contains(timer.id) {
        let order = self.host.timer_insertion_counter.val
        self.host.timer_insertion_counter.val = order + 1
        self.host.timer_queue.push({
          id: timer.id,
          callback: timer.callback,
          args: timer.args,
          delay: timer.delay + timer.period,
          period: timer.period,
          is_interval: true,
          insertion_order: order,
        })
      }
    }
    // Clear cancelled IDs only when the queue is fully drained.
    // If the safety limit fires, surviving timers may fire on the next
    // run_timers call; keeping cancelled IDs ensures they are still skipped.
    if self.host.timer_queue.length() == 0 {
      self.host.cancelled_timer_ids.clear()
    }
  }) catch {
    e => raise e
  }
}
