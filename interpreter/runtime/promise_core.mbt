///|
/// Enqueue a microtask to be executed when the current execution context completes.
/// This implements HostEnqueuePromiseJob from the ECMAScript spec.
pub fn Interpreter::enqueue_microtask(
  self : Interpreter,
  callback : Value,
  args : Array[Value],
) -> Unit {
  self.host.microtask_queue.push({ callback, args })
}

///|
/// Run all pending microtasks until the queue is empty.
/// This is called after each task (script execution) completes.
/// Implements the microtask checkpoint from WHATWG Event Loop spec.
pub fn Interpreter::run_microtasks(self : Interpreter) -> Unit raise Error {
  // Process microtasks until queue is empty
  // Note: new microtasks can be enqueued during execution
  // Use index-based draining to avoid O(n²) from repeated remove(0)
  let mut head = 0
  while head < self.host.microtask_queue.length() {
    let task = self.host.microtask_queue[head]
    head = head + 1
    // Call the callback with queued arguments
    match task.callback {
      Object(obj_data) =>
        match obj_data.callable {
          Some(_) => {
            let loc = @token.Loc::default()
            let _ = self.call_value(task.callback, Undefined, task.args, loc)
          }
          None => ()
        }
      _ => ()
    }
  }
  // Clear processed microtasks
  self.host.microtask_queue.clear()
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
/// Create an InterpreterCallable function object with explicit `length`.
pub fn make_interpreter_callable_with_length(
  name : String,
  length : Int,
  body : (Interpreter, Value, Array[Value]) -> Value raise Error,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let props : Map[String, Value] = {}
  props["length"] = Number(length.to_double())
  props["name"] = String_(name)
  Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
    },
    prototype: get_func_proto(),
    callable: Some(InterpreterCallable(name, body)),
    class_name: "Function",
    extensible: true,
  })
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
  let job_callback = make_interp_method_func("PromiseReactionJob", 0, fn(
    i,
    _this,
    args,
  ) raise {
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
            let _ = i.call_value(reaction.reject, Undefined, [error_value], loc)
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
  })
  interp.enqueue_microtask(job_callback, [argument])
}

///|
/// Create resolve and reject capability functions for a promise.
/// Returns (resolve_func, reject_func).
pub fn create_resolving_functions(
  _interp : Interpreter,
  promise_data : PromiseData,
) -> (Value, Value) {
  // Track whether already resolved (prevents multiple resolution)
  let already_resolved : Ref[Bool] = { val: false }

  // Create resolve function
  let resolve_func = make_interpreter_callable_with_length("resolve", 1, fn(
    i,
    _this,
    args,
  ) {
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
                "PromiseResolveThenableJob",
                0,
                fn(i2, _t, _a) raise {
                  try {
                    let _ = i2.call_value(then_val, resolution, [res, rej], loc)
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
  })

  // Create reject function
  let reject_func = make_interpreter_callable_with_length("reject", 1, fn(
    i,
    _this,
    args,
  ) {
    if already_resolved.val {
      return Undefined
    }
    already_resolved.val = true
    let reason = if args.length() > 0 { args[0] } else { Undefined }
    reject_promise(i, promise_data, reason)
    Undefined
  })
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
  // Safety limit to prevent infinite loops from setInterval
  let max_iterations = 10000
  let mut iterations = 0
  while self.host.timer_queue.length() > 0 && iterations < max_iterations {
    iterations = iterations + 1
    // Sort timers by delay (ascending), then by insertion order (ascending)
    self.host.timer_queue.sort_by(fn(a, b) {
      if a.delay != b.delay {
        a.delay - b.delay
      } else {
        a.insertion_order - b.insertion_order
      }
    })
    // Take the first (soonest) timer
    let timer = self.host.timer_queue.remove(0)
    if timer.cancelled {
      continue
    }
    // Execute the timer callback
    let loc = @token.Loc::default()
    let _ = self.call_value(timer.callback, Undefined, timer.args, loc)
    // Microtask checkpoint after each task (per WHATWG event loop spec)
    self.run_microtasks()
    // If this is setInterval and not cancelled, re-enqueue.
    // Check both the timer's cancelled flag and cancelled_timer_ids,
    // because clearInterval called inside the callback can't mark the
    // already-removed timer struct — it records in cancelled_timer_ids instead.
    if timer.is_interval &&
      !timer.cancelled &&
      !self.host.cancelled_timer_ids.contains(timer.id) {
      let order = self.host.timer_insertion_counter.val
      self.host.timer_insertion_counter.val = order + 1
      self.host.timer_queue.push({
        id: timer.id,
        callback: timer.callback,
        args: timer.args,
        delay: timer.delay + timer.period,
        period: timer.period,
        cancelled: false,
        is_interval: true,
        insertion_order: order,
      })
    }
  }
  // Clear the cancelled set for this run
  self.host.cancelled_timer_ids.clear()
}
