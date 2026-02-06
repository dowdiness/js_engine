///|
/// Promise implementation for JavaScript engine
/// Follows ECMAScript spec with microtask/job queue integration
/// Uses host environment event loop for JS compilation target
///
/// Event Loop Architecture:
/// - For JS compilation (host environment): Uses host event loop via FFI
/// - For WASM compilation: Deferred - will use browser's event loop
/// - For native compilation: Deferred - will need custom event loop implementation
///
/// Reference: https://tc39.es/ecma262/multipage/executable-code-and-execution-contexts.html#sec-jobs

///|
/// Reference to Promise.prototype for method lookup
let promise_prototype_ref : Ref[Value?] = { val: None }

///|
/// Get Promise.prototype methods for a Promise instance
pub fn get_promise_method(_data : PromiseData, prop : String) -> Value {
  match promise_prototype_ref.val {
    Some(proto) =>
      match proto {
        Object(proto_data) =>
          match proto_data.properties.get(prop) {
            Some(m) => m
            None => Undefined
          }
        _ => Undefined
      }
    None => Undefined
  }
}

///|
/// Enqueue a microtask to be executed when the current execution context completes
/// This implements HostEnqueuePromiseJob from the ECMAScript spec
pub fn Interpreter::enqueue_microtask(
  self : Interpreter,
  callback : Value,
  args : Array[Value],
) -> Unit {
  self.microtask_queue.push({ callback, args })
}

///|
/// Run all pending microtasks until the queue is empty
/// This is called after each task (script execution) completes
/// Implements the microtask checkpoint from WHATWG Event Loop spec
pub fn Interpreter::run_microtasks(self : Interpreter) -> Unit raise Error {
  // Process microtasks until queue is empty
  // Note: new microtasks can be enqueued during execution
  // Use index-based draining to avoid O(n²) from repeated remove(0)
  let mut head = 0
  while head < self.microtask_queue.length() {
    let task = self.microtask_queue[head]
    head = head + 1
    // Call the callback with queued arguments
    match task.callback {
      Object(obj_data) =>
        match obj_data.callable {
          Some(_) => {
            let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
            let _ = self.call_value(task.callback, Undefined, task.args, loc)

          }
          None => ()
        }
      _ => ()
    }
  }
  // Clear processed microtasks
  self.microtask_queue.clear()
}

///|
/// Create resolve and reject capability functions for a promise
/// Returns (resolve_func, reject_func)
fn create_resolving_functions(
  _interp : Interpreter,
  promise_data : PromiseData,
) -> (Value, Value) {
  // Track whether already resolved (prevents multiple resolution)
  let already_resolved : Ref[Bool] = { val: false }

  // Create resolve function
  let resolve_func = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("resolve", fn(i, _this, args) {
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
              let error = make_type_error("Chaining cycle detected for promise")
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
        match resolution {
          Promise(_) | Object(_) => {
            // Get(resolution, "then") walks the prototype chain and
            // invokes accessors per ECMAScript spec
            let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
            let then_val = i.get_property(resolution, "then", loc) catch {
              e => {
                // If Get throws, reject the promise with the error
                let err = js_error_to_value(e)
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
                    let job = Object({
                      properties: {},
                      symbol_properties: {},
                      prototype: Null,
                      callable: Some(
                        InterpreterCallable("PromiseResolveThenableJob", fn(
                          i2,
                          _t,
                          _a,
                        ) {
                          try {
                            let _ = i2.call_value(
                              then_val,
                              resolution,
                              [res, rej],
                              loc,
                            )

                          } catch {
                            e => {
                              let err = js_error_to_value(e)
                              let _ = i2.call_value(rej, Undefined, [err], loc)

                            }
                          }
                          Undefined
                        }),
                      ),
                      class_name: "Function",
                      descriptors: {},
                      symbol_descriptors: {},
                      extensible: true,
                    })
                    i.enqueue_microtask(job, [])
                  }
                  None => fulfill_promise(i, promise_data, resolution)
                }
              _ => fulfill_promise(i, promise_data, resolution)
            }
          }
          _ => fulfill_promise(i, promise_data, resolution)
        }
        Undefined
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Create reject function
  let reject_func = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("reject", fn(i, _this, args) {
        if already_resolved.val {
          return Undefined
        }
        already_resolved.val = true
        let reason = if args.length() > 0 { args[0] } else { Undefined }
        reject_promise(i, promise_data, reason)
        Undefined
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  (resolve_func, reject_func)
}

///|
/// Fulfill a promise with the given value
/// Triggers all fulfill reactions as microtasks
fn fulfill_promise(
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
/// Reject a promise with the given reason
/// Triggers all reject reactions as microtasks
fn reject_promise(
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
/// Enqueue a promise reaction job (microtask)
/// This implements NewPromiseReactionJob from ECMAScript spec
fn enqueue_promise_reaction_job(
  interp : Interpreter,
  reaction : PromiseReaction,
  argument : Value,
) -> Unit {
  // Create a job that will execute the reaction handler
  let job_callback = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("PromiseReactionJob", fn(i, _this, args) {
        let value = if args.length() > 0 { args[0] } else { Undefined }
        let loc : @token.Loc = { line: 0, col: 0, offset: 0 }

        // If handler is None, use identity (fulfill) or thrower (reject)
        match reaction.handler {
          Some(handler) => {
            // Try to call the handler
            let result = i.call_value(handler, Undefined, [value], loc) catch {
              e => {
                // Handler threw - reject the dependent promise
                let error_value = js_error_to_value(e)
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  interp.enqueue_microtask(job_callback, [argument])
}

///|
/// Setup Promise constructor and prototype methods
pub fn setup_promise(env : Environment) -> Unit {
  // Promise prototype with then, catch, finally
  let promise_proto_props : Map[String, Value] = {}

  // Promise.prototype.then(onFulfilled, onRejected)
  promise_proto_props["then"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("then", fn(interp, this_val, args) {
        match this_val {
          Promise(promise_data) => {
            let on_fulfilled = if args.length() > 0 {
              match args[0] {
                Object(od) =>
                  match od.callable {
                    Some(_) => Some(args[0])
                    None => None
                  }
                _ => None
              }
            } else {
              None
            }
            let on_rejected = if args.length() > 1 {
              match args[1] {
                Object(od) =>
                  match od.callable {
                    Some(_) => Some(args[1])
                    None => None
                  }
                _ => None
              }
            } else {
              None
            }

            // Mark as handled if onRejected is provided
            if on_rejected is Some(_) {
              promise_data.is_handled = true
            }

            // Create new promise for the result
            let result_promise_data = new_promise_data()
            let result_promise : Value = Promise(result_promise_data)

            // Create resolving functions for the result promise
            let (resolve, reject) = create_resolving_functions(
              interp, result_promise_data,
            )

            // Create reactions
            let fulfill_reaction : PromiseReaction = {
              handler: on_fulfilled,
              resolve,
              reject,
              reaction_type: Fulfill,
            }
            let reject_reaction : PromiseReaction = {
              handler: on_rejected,
              resolve,
              reject,
              reaction_type: Reject,
            }

            // Depending on promise state, either queue reactions or enqueue jobs
            match promise_data.state {
              Pending => {
                promise_data.fulfill_reactions.push(fulfill_reaction)
                promise_data.reject_reactions.push(reject_reaction)
              }
              Fulfilled =>
                enqueue_promise_reaction_job(
                  interp,
                  fulfill_reaction,
                  promise_data.result,
                )
              Rejected => {
                if on_rejected is Some(_) {
                  promise_data.is_handled = true
                }
                enqueue_promise_reaction_job(
                  interp,
                  reject_reaction,
                  promise_data.result,
                )
              }
            }
            result_promise
          }
          _ =>
            raise @errors.TypeError(
              message="Promise.prototype.then requires a Promise",
            )
        }
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Promise.prototype.catch(onRejected)
  promise_proto_props["catch"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("catch", fn(interp, this_val, args) {
        // catch(onRejected) is just then(undefined, onRejected)
        let then_method = match this_val {
          Promise(pd) => get_promise_method(pd, "then")
          _ =>
            raise @errors.TypeError(
              message="Promise.prototype.catch requires a Promise",
            )
        }
        let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
        let on_rejected = if args.length() > 0 { args[0] } else { Undefined }
        interp.call_value(then_method, this_val, [Undefined, on_rejected], loc)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Promise.prototype.finally(onFinally)
  promise_proto_props["finally"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("finally", fn(interp, this_val, args) {
        // Ensure this_val is a Promise
        let promise_data = match this_val {
          Promise(pd) => pd
          _ =>
            raise @errors.TypeError(
              message="Promise.prototype.finally requires a Promise",
            )
        }
        let on_finally = if args.length() > 0 { args[0] } else { Undefined }
        let is_callable = match on_finally {
          Object(od) => od.callable is Some(_)
          _ => false
        }
        if not(is_callable) {
          // If onFinally is not callable, pass through
          let then_method = get_promise_method(promise_data, "then")
          let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
          return interp.call_value(
            then_method,
            this_val,
            [on_finally, on_finally],
            loc,
          )
        }

        // Create wrapper functions that call onFinally then pass through value
        // Per ECMAScript §27.2.5.3, we must await the result of onFinally
        // by chaining through Promise.resolve(onFinally_result).then(...)
        let value_thunk = Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            InterpreterCallable("finallyValueThunk", fn(i, _this, inner_args) {
              let value = if inner_args.length() > 0 {
                inner_args[0]
              } else {
                Undefined
              }
              let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
              // Call onFinally
              let finally_result = i.call_value(on_finally, Undefined, [], loc)
              // Wrap result via PromiseResolve algorithm
              let result_promise = promise_resolve_value(i, finally_result)
              // Create a thunk that returns the original value
              let return_value_thunk = Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: Some(
                  InterpreterCallable("returnValue", fn(_i2, _t, _a) { value }),
                ),
                class_name: "Function",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
              // Chain: Promise.resolve(finally_result).then(() => value)
              let then_method = match result_promise {
                Promise(pd) => get_promise_method(pd, "then")
                _ => Undefined
              }
              i.call_value(
                then_method,
                result_promise,
                [return_value_thunk],
                loc,
              )
            }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
        let thrower_thunk = Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            InterpreterCallable("finallyThrowerThunk", fn(
              i,
              _this,
              inner_args,
            ) {
              let reason = if inner_args.length() > 0 {
                inner_args[0]
              } else {
                Undefined
              }
              let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
              // Call onFinally
              let finally_result = i.call_value(on_finally, Undefined, [], loc)
              // Wrap result via PromiseResolve algorithm
              let result_promise = promise_resolve_value(i, finally_result)
              // Create a thunk that re-throws the original reason
              let throw_reason_thunk = Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: Some(
                  InterpreterCallable("throwReason", fn(_i2, _t, _a) {
                    raise JsException(reason)
                  }),
                ),
                class_name: "Function",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
              // Chain: Promise.resolve(finally_result).then(() => { throw reason })
              let then_method = match result_promise {
                Promise(pd) => get_promise_method(pd, "then")
                _ => Undefined
              }
              i.call_value(
                then_method,
                result_promise,
                [throw_reason_thunk],
                loc,
              )
            }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
        let then_method = get_promise_method(promise_data, "then")
        let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
        interp.call_value(
          then_method,
          this_val,
          [value_thunk, thrower_thunk],
          loc,
        )
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let promise_proto = Object({
    properties: promise_proto_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Promise",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Store prototype reference for method lookup
  promise_prototype_ref.val = Some(promise_proto)

  // Promise constructor
  let promise_ctor_props : Map[String, Value] = {}

  // Promise.resolve(value)
  promise_ctor_props["resolve"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("resolve", fn(interp, _this, args) {
        let value = if args.length() > 0 { args[0] } else { Undefined }
        promise_resolve_value(interp, value)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Promise.reject(reason)
  promise_ctor_props["reject"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("reject", fn(_interp, _this, args) {
        let reason = if args.length() > 0 { args[0] } else { Undefined }
        let promise_data : PromiseData = {
          state: Rejected,
          result: reason,
          fulfill_reactions: [],
          reject_reactions: [],
          is_handled: false,
          properties: {},
          symbol_properties: {},
        }
        Promise(promise_data)
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Promise.all(iterable)
  promise_ctor_props["all"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("all", fn(interp, _this, args) {
        let iterable = if args.length() > 0 { args[0] } else { Undefined }

        // Get array of promises
        let promises = get_promise_array(interp, iterable)
        let count = promises.length()
        if count == 0 {
          // Empty array - return resolved promise with empty array
          let promise_data : PromiseData = {
            state: Fulfilled,
            result: Array({ elements: [] }),
            fulfill_reactions: [],
            reject_reactions: [],
            is_handled: false,
            properties: {},
            symbol_properties: {},
          }
          return Promise(promise_data)
        }

        // Create result promise
        let result_data = new_promise_data()
        let result_promise = Promise(result_data)
        let (resolve, reject) = create_resolving_functions(interp, result_data)
        let bookkeeping_resolve = Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            NativeCallable("allBookkeepingResolve", fn(_args) { Undefined }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })

        // Track results
        let results : Array[Value] = Array::make(count, Undefined)
        let remaining : Ref[Int] = { val: count }
        for i = 0; i < count; i = i + 1 {
          let promise = promises[i]
          let index = i

          // Ensure it's a promise (wrap if not)
          let p = match promise {
            Promise(_) => promise
            _ => {
              let pd : PromiseData = {
                state: Fulfilled,
                result: promise,
                fulfill_reactions: [],
                reject_reactions: [],
                is_handled: false,
                properties: {},
                symbol_properties: {},
              }
              Promise(pd)
            }
          }

          // Create handlers for this promise
          let on_fulfilled = Object({
            properties: {},
            symbol_properties: {},
            prototype: Null,
            callable: Some(
              InterpreterCallable("allOnFulfilled", fn(i2, _this2, args2) {
                let value = if args2.length() > 0 {
                  args2[0]
                } else {
                  Undefined
                }
                results[index] = value
                remaining.val = remaining.val - 1
                if remaining.val == 0 {
                  let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
                  let _ = i2.call_value(
                    resolve,
                    Undefined,
                    [Array({ elements: results })],
                    loc,
                  )

                }
                Undefined
              }),
            ),
            class_name: "Function",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })

          // Attach handlers
          match p {
            Promise(pd) => {
              pd.is_handled = true
              match pd.state {
                Pending => {
                  let fulfill_reaction : PromiseReaction = {
                    handler: Some(on_fulfilled),
                    resolve: bookkeeping_resolve,
                    reject,
                    reaction_type: Fulfill,
                  }
                  let reject_reaction : PromiseReaction = {
                    handler: None,
                    resolve: bookkeeping_resolve,
                    reject,
                    reaction_type: Reject,
                  }
                  pd.fulfill_reactions.push(fulfill_reaction)
                  pd.reject_reactions.push(reject_reaction)
                }
                Fulfilled =>
                  enqueue_promise_reaction_job(
                    interp,
                    {
                      handler: Some(on_fulfilled),
                      resolve: bookkeeping_resolve,
                      reject,
                      reaction_type: Fulfill,
                    },
                    pd.result,
                  )
                Rejected =>
                  enqueue_promise_reaction_job(
                    interp,
                    { handler: None, resolve, reject, reaction_type: Reject },
                    pd.result,
                  )
              }
            }
            _ => ()
          }
        }
        result_promise
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Promise.race(iterable)
  promise_ctor_props["race"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("race", fn(interp, _this, args) {
        let iterable = if args.length() > 0 { args[0] } else { Undefined }
        let promises = get_promise_array(interp, iterable)

        // Create result promise
        let result_data = new_promise_data()
        let result_promise = Promise(result_data)
        let (resolve, reject) = create_resolving_functions(interp, result_data)
        for promise in promises {
          // Ensure it's a promise
          let p = match promise {
            Promise(_) => promise
            _ => {
              let pd : PromiseData = {
                state: Fulfilled,
                result: promise,
                fulfill_reactions: [],
                reject_reactions: [],
                is_handled: false,
                properties: {},
                symbol_properties: {},
              }
              Promise(pd)
            }
          }
          match p {
            Promise(pd) => {
              pd.is_handled = true
              match pd.state {
                Pending => {
                  let fulfill_reaction : PromiseReaction = {
                    handler: None,
                    resolve,
                    reject,
                    reaction_type: Fulfill,
                  }
                  let reject_reaction : PromiseReaction = {
                    handler: None,
                    resolve,
                    reject,
                    reaction_type: Reject,
                  }
                  pd.fulfill_reactions.push(fulfill_reaction)
                  pd.reject_reactions.push(reject_reaction)
                }
                Fulfilled =>
                  enqueue_promise_reaction_job(
                    interp,
                    { handler: None, resolve, reject, reaction_type: Fulfill },
                    pd.result,
                  )
                Rejected =>
                  enqueue_promise_reaction_job(
                    interp,
                    { handler: None, resolve, reject, reaction_type: Reject },
                    pd.result,
                  )
              }
            }
            _ => ()
          }
        }
        result_promise
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Promise.allSettled(iterable)
  promise_ctor_props["allSettled"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("allSettled", fn(interp, _this, args) {
        let iterable = if args.length() > 0 { args[0] } else { Undefined }
        let promises = get_promise_array(interp, iterable)
        let count = promises.length()
        if count == 0 {
          let promise_data : PromiseData = {
            state: Fulfilled,
            result: Array({ elements: [] }),
            fulfill_reactions: [],
            reject_reactions: [],
            is_handled: false,
            properties: {},
            symbol_properties: {},
          }
          return Promise(promise_data)
        }
        let result_data = new_promise_data()
        let result_promise = Promise(result_data)
        let (resolve, _reject) = create_resolving_functions(interp, result_data)
        let bookkeeping_resolve = Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            NativeCallable("allSettledBookkeepingResolve", fn(_args) {
              Undefined
            }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
        let results : Array[Value] = Array::make(count, Undefined)
        let remaining : Ref[Int] = { val: count }
        for i = 0; i < count; i = i + 1 {
          let promise = promises[i]
          let index = i
          let p = match promise {
            Promise(_) => promise
            _ => {
              let pd : PromiseData = {
                state: Fulfilled,
                result: promise,
                fulfill_reactions: [],
                reject_reactions: [],
                is_handled: false,
                properties: {},
                symbol_properties: {},
              }
              Promise(pd)
            }
          }
          let on_fulfilled = Object({
            properties: {},
            symbol_properties: {},
            prototype: Null,
            callable: Some(
              InterpreterCallable("allSettledOnFulfilled", fn(
                i2,
                _this2,
                args2,
              ) {
                let value = if args2.length() > 0 {
                  args2[0]
                } else {
                  Undefined
                }
                let result_props : Map[String, Value] = {}
                result_props["status"] = String_("fulfilled")
                result_props["value"] = value
                results[index] = Object({
                  properties: result_props,
                  symbol_properties: {},
                  prototype: Null,
                  callable: None,
                  class_name: "Object",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
                remaining.val = remaining.val - 1
                if remaining.val == 0 {
                  let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
                  let _ = i2.call_value(
                    resolve,
                    Undefined,
                    [Array({ elements: results })],
                    loc,
                  )

                }
                Undefined
              }),
            ),
            class_name: "Function",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
          let on_rejected = Object({
            properties: {},
            symbol_properties: {},
            prototype: Null,
            callable: Some(
              InterpreterCallable("allSettledOnRejected", fn(
                i2,
                _this2,
                args2,
              ) {
                let reason = if args2.length() > 0 {
                  args2[0]
                } else {
                  Undefined
                }
                let result_props : Map[String, Value] = {}
                result_props["status"] = String_("rejected")
                result_props["reason"] = reason
                results[index] = Object({
                  properties: result_props,
                  symbol_properties: {},
                  prototype: Null,
                  callable: None,
                  class_name: "Object",
                  descriptors: {},
                  symbol_descriptors: {},
                  extensible: true,
                })
                remaining.val = remaining.val - 1
                if remaining.val == 0 {
                  let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
                  let _ = i2.call_value(
                    resolve,
                    Undefined,
                    [Array({ elements: results })],
                    loc,
                  )

                }
                Undefined
              }),
            ),
            class_name: "Function",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })

          // Create a dummy resolve that won't be used (allSettled never rejects)
          let dummy_reject = Object({
            properties: {},
            symbol_properties: {},
            prototype: Null,
            callable: Some(
              NativeCallable("dummyReject", fn(_args) { Undefined }),
            ),
            class_name: "Function",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
          match p {
            Promise(pd) => {
              pd.is_handled = true
              match pd.state {
                Pending => {
                  pd.fulfill_reactions.push({
                    handler: Some(on_fulfilled),
                    resolve: bookkeeping_resolve,
                    reject: dummy_reject,
                    reaction_type: Fulfill,
                  })
                  pd.reject_reactions.push({
                    handler: Some(on_rejected),
                    resolve: bookkeeping_resolve,
                    reject: dummy_reject,
                    reaction_type: Reject,
                  })
                }
                Fulfilled =>
                  enqueue_promise_reaction_job(
                    interp,
                    {
                      handler: Some(on_fulfilled),
                      resolve: bookkeeping_resolve,
                      reject: dummy_reject,
                      reaction_type: Fulfill,
                    },
                    pd.result,
                  )
                Rejected =>
                  enqueue_promise_reaction_job(
                    interp,
                    {
                      handler: Some(on_rejected),
                      resolve: bookkeeping_resolve,
                      reject: dummy_reject,
                      reaction_type: Reject,
                    },
                    pd.result,
                  )
              }
            }
            _ => ()
          }
        }
        result_promise
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Promise.any(iterable)
  promise_ctor_props["any"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("any", fn(interp, _this, args) {
        let iterable = if args.length() > 0 { args[0] } else { Undefined }
        let promises = get_promise_array(interp, iterable)
        let count = promises.length()
        if count == 0 {
          // Empty array - reject with AggregateError
          let promise_data : PromiseData = {
            state: Rejected,
            result: make_aggregate_error("All promises were rejected", []),
            fulfill_reactions: [],
            reject_reactions: [],
            is_handled: false,
            properties: {},
            symbol_properties: {},
          }
          return Promise(promise_data)
        }
        let result_data = new_promise_data()
        let result_promise = Promise(result_data)
        let (resolve, reject) = create_resolving_functions(interp, result_data)
        let bookkeeping_resolve = Object({
          properties: {},
          symbol_properties: {},
          prototype: Null,
          callable: Some(
            NativeCallable("anyBookkeepingResolve", fn(_args) { Undefined }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })
        let errors : Array[Value] = Array::make(count, Undefined)
        let remaining : Ref[Int] = { val: count }
        for i = 0; i < count; i = i + 1 {
          let promise = promises[i]
          let index = i
          let p = match promise {
            Promise(_) => promise
            _ => {
              let pd : PromiseData = {
                state: Fulfilled,
                result: promise,
                fulfill_reactions: [],
                reject_reactions: [],
                is_handled: false,
                properties: {},
                symbol_properties: {},
              }
              Promise(pd)
            }
          }
          let on_rejected = Object({
            properties: {},
            symbol_properties: {},
            prototype: Null,
            callable: Some(
              InterpreterCallable("anyOnRejected", fn(i2, _this2, args2) {
                let reason = if args2.length() > 0 {
                  args2[0]
                } else {
                  Undefined
                }
                errors[index] = reason
                remaining.val = remaining.val - 1
                if remaining.val == 0 {
                  let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
                  let agg_error = make_aggregate_error(
                    "All promises were rejected", errors,
                  )
                  let _ = i2.call_value(reject, Undefined, [agg_error], loc)

                }
                Undefined
              }),
            ),
            class_name: "Function",
            descriptors: {},
            symbol_descriptors: {},
            extensible: true,
          })
          match p {
            Promise(pd) => {
              pd.is_handled = true
              match pd.state {
                Pending => {
                  pd.fulfill_reactions.push({
                    handler: None,
                    resolve,
                    reject,
                    reaction_type: Fulfill,
                  })
                  pd.reject_reactions.push({
                    handler: Some(on_rejected),
                    resolve: bookkeeping_resolve,
                    reject,
                    reaction_type: Reject,
                  })
                }
                Fulfilled =>
                  enqueue_promise_reaction_job(
                    interp,
                    { handler: None, resolve, reject, reaction_type: Fulfill },
                    pd.result,
                  )
                Rejected =>
                  enqueue_promise_reaction_job(
                    interp,
                    {
                      handler: Some(on_rejected),
                      resolve: bookkeeping_resolve,
                      reject,
                      reaction_type: Reject,
                    },
                    pd.result,
                  )
              }
            }
            _ => ()
          }
        }
        result_promise
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Promise constructor itself - requires 'new' keyword
  let promise_ctor = Object({
    properties: promise_ctor_props,
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      ConstructorOnlyCallable("Promise", fn(interp, args) {
        let executor = if args.length() > 0 { args[0] } else { Undefined }

        // Validate executor is callable
        match executor {
          Object(od) =>
            match od.callable {
              Some(_) => ()
              None =>
                raise @errors.TypeError(
                  message="Promise resolver undefined is not a function",
                )
            }
          _ =>
            raise @errors.TypeError(
              message="Promise resolver undefined is not a function",
            )
        }

        // Create new promise
        let promise_data = new_promise_data()
        let promise = Promise(promise_data)

        // Create resolving functions
        let (resolve, reject) = create_resolving_functions(interp, promise_data)

        // Call executor synchronously
        let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
        try {
          let _ = interp.call_value(executor, Undefined, [resolve, reject], loc)

        } catch {
          e => {
            // If executor throws, reject the promise
            let error_value = js_error_to_value(e)
            let _ = interp.call_value(reject, Undefined, [error_value], loc)

          }
        }
        promise
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Set prototype property on constructor
  match promise_ctor {
    Object(od) => od.properties["prototype"] = promise_proto
    _ => ()
  }
  env.def_builtin("Promise", promise_ctor)
  // Set Promise.prototype.constructor = Promise
  match promise_proto {
    Object(data) => {
      data.properties["constructor"] = promise_ctor
      data.descriptors["constructor"] = { writable: true, enumerable: false, configurable: true, getter: None, setter: None }
    }
    _ => ()
  }

  // queueMicrotask(callback) - schedules a microtask
  // Part of the Web Platform APIs, used for scheduling microtasks directly
  env.def_builtin(
    "queueMicrotask",
    Object({
      properties: {},
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        InterpreterCallable("queueMicrotask", fn(interp, _this, args) {
          let callback = if args.length() > 0 { args[0] } else { Undefined }

          // Validate callback is callable
          match callback {
            Object(od) =>
              match od.callable {
                Some(_) => interp.enqueue_microtask(callback, [])
                None =>
                  raise @errors.TypeError(
                    message="queueMicrotask requires a function argument",
                  )
              }
            _ =>
              raise @errors.TypeError(
                message="queueMicrotask requires a function argument",
              )
          }
          Undefined
        }),
      ),
      class_name: "Function",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    }),
  )
}

///|
/// Setup timer builtins: setTimeout, clearTimeout, setInterval, clearInterval
/// These implement the WHATWG Timer APIs
/// Reference: https://html.spec.whatwg.org/multipage/timers-and-user-prompts.html#timers
pub fn setup_timers(env : Environment) -> Unit {
  // setTimeout(callback, delay, ...args) -> timerId
  env.def_builtin(
    "setTimeout",
    Object({
      properties: {},
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        InterpreterCallable("setTimeout", fn(interp, _this, args) {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          // Validate callback is callable
          match callback {
            Object(od) =>
              match od.callable {
                Some(_) => ()
                None =>
                  raise @errors.TypeError(
                    message="setTimeout requires a function as first argument",
                  )
              }
            _ =>
              raise @errors.TypeError(
                message="setTimeout requires a function as first argument",
              )
          }
          let delay = if args.length() > 1 {
            match args[1] {
              Number(n) => {
                let d = n.to_int()
                if d < 0 {
                  0
                } else {
                  d
                }
              }
              _ => 0
            }
          } else {
            0
          }
          // Collect extra arguments to pass to callback
          let extra_args : Array[Value] = []
          for i = 2; i < args.length(); i = i + 1 {
            extra_args.push(args[i])
          }
          let id = interp.timer_id_counter.val
          interp.timer_id_counter.val = id + 1
          let order = interp.timer_insertion_counter.val
          interp.timer_insertion_counter.val = order + 1
          interp.timer_queue.push({
            id,
            callback,
            args: extra_args,
            delay,
            period: 0,
            cancelled: false,
            is_interval: false,
            insertion_order: order,
          })
          Number(id.to_double())
        }),
      ),
      class_name: "Function",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    }),
  )

  // clearTimeout(id)
  env.def_builtin(
    "clearTimeout",
    Object({
      properties: {},
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        InterpreterCallable("clearTimeout", fn(interp, _this, args) {
          let id = if args.length() > 0 {
            match args[0] {
              Number(n) => n.to_int()
              _ => return Undefined
            }
          } else {
            return Undefined
          }
          // Mark timer as cancelled in queue
          for timer in interp.timer_queue {
            if timer.id == id {
              timer.cancelled = true
              break
            }
          }
          // Also record in cancelled set so run_timers won't re-enqueue
          // an interval whose callback called clearInterval on itself
          interp.cancelled_timer_ids[id] = true
          Undefined
        }),
      ),
      class_name: "Function",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    }),
  )

  // setInterval(callback, delay, ...args) -> timerId
  env.def_builtin(
    "setInterval",
    Object({
      properties: {},
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        InterpreterCallable("setInterval", fn(interp, _this, args) {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          match callback {
            Object(od) =>
              match od.callable {
                Some(_) => ()
                None =>
                  raise @errors.TypeError(
                    message="setInterval requires a function as first argument",
                  )
              }
            _ =>
              raise @errors.TypeError(
                message="setInterval requires a function as first argument",
              )
          }
          let delay = if args.length() > 1 {
            match args[1] {
              Number(n) => {
                let d = n.to_int()
                if d < 0 {
                  0
                } else {
                  d
                }
              }
              _ => 0
            }
          } else {
            0
          }
          let extra_args : Array[Value] = []
          for i = 2; i < args.length(); i = i + 1 {
            extra_args.push(args[i])
          }
          let id = interp.timer_id_counter.val
          interp.timer_id_counter.val = id + 1
          let order = interp.timer_insertion_counter.val
          interp.timer_insertion_counter.val = order + 1
          interp.timer_queue.push({
            id,
            callback,
            args: extra_args,
            delay,
            period: delay,
            cancelled: false,
            is_interval: true,
            insertion_order: order,
          })
          Number(id.to_double())
        }),
      ),
      class_name: "Function",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    }),
  )

  // clearInterval(id) - same semantics as clearTimeout
  env.def_builtin(
    "clearInterval",
    Object({
      properties: {},
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        InterpreterCallable("clearInterval", fn(interp, _this, args) {
          let id = if args.length() > 0 {
            match args[0] {
              Number(n) => n.to_int()
              _ => return Undefined
            }
          } else {
            return Undefined
          }
          for timer in interp.timer_queue {
            if timer.id == id {
              timer.cancelled = true
              break
            }
          }
          // Also record in cancelled set so run_timers won't re-enqueue
          // an interval whose callback called clearInterval on itself
          interp.cancelled_timer_ids[id] = true
          Undefined
        }),
      ),
      class_name: "Function",
      descriptors: {},
      symbol_descriptors: {},
      extensible: true,
    }),
  )
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
  while self.timer_queue.length() > 0 && iterations < max_iterations {
    iterations = iterations + 1
    // Sort timers by delay (ascending), then by insertion order (ascending)
    self.timer_queue.sort_by(fn(a, b) {
      if a.delay != b.delay {
        a.delay - b.delay
      } else {
        a.insertion_order - b.insertion_order
      }
    })
    // Take the first (soonest) timer
    let timer = self.timer_queue.remove(0)
    if timer.cancelled {
      continue
    }
    // Execute the timer callback
    let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
    let _ = self.call_value(timer.callback, Undefined, timer.args, loc)
    // Microtask checkpoint after each task (per WHATWG event loop spec)
    self.run_microtasks()
    // If this is setInterval and not cancelled, re-enqueue.
    // Check both the timer's cancelled flag and cancelled_timer_ids,
    // because clearInterval called inside the callback can't mark the
    // already-removed timer struct — it records in cancelled_timer_ids instead.
    if timer.is_interval &&
      not(timer.cancelled) &&
      not(self.cancelled_timer_ids.contains(timer.id)) {
      let order = self.timer_insertion_counter.val
      self.timer_insertion_counter.val = order + 1
      self.timer_queue.push({
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
  self.cancelled_timer_ids.clear()
}

///|
/// Helper to extract array of values from iterable using iterator protocol
fn get_promise_array(
  interp : Interpreter,
  iterable : Value,
) -> Array[Value] raise Error {
  match iterable {
    Undefined | Null =>
      raise @errors.TypeError(
        message="Cannot read properties of " +
          type_of(iterable) +
          " (reading 'Symbol(Symbol.iterator)')",
      )
    _ => {
      let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
      interp.spread_iterable(iterable, loc)
    }
  }
}

///|
/// PromiseResolve algorithm (ECMAScript §27.2.4.7)
/// If value is already a Promise, return it; otherwise resolve a new Promise with it
fn promise_resolve_value(
  interp : Interpreter,
  value : Value,
) -> Value raise Error {
  match value {
    Promise(_) => value
    _ => {
      let pd : PromiseData = {
        state: Pending,
        result: Undefined,
        fulfill_reactions: [],
        reject_reactions: [],
        is_handled: false,
        properties: {},
        symbol_properties: {},
      }
      let promise = Promise(pd)
      let (resolve, _reject) = create_resolving_functions(interp, pd)
      let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
      let _ = interp.call_value(resolve, Undefined, [value], loc)
      promise
    }
  }
}

///|
/// Helper to create a TypeError value (for promise rejection)
fn make_type_error(message : String) -> Value {
  let props : Map[String, Value] = {}
  props["name"] = String_("TypeError")
  props["message"] = String_(message)
  Object({
    properties: props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "TypeError",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Helper to create an AggregateError value
fn make_aggregate_error(message : String, errors : Array[Value]) -> Value {
  let props : Map[String, Value] = {}
  props["name"] = String_("AggregateError")
  props["message"] = String_(message)
  props["errors"] = Array({ elements: errors })
  Object({
    properties: props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "AggregateError",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}
