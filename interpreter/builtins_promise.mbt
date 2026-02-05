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
  argument : Value,
) -> Unit {
  self.microtask_queue.push({ callback, argument })
}

///|
/// Run all pending microtasks until the queue is empty
/// This is called after each task (script execution) completes
/// Implements the microtask checkpoint from WHATWG Event Loop spec
pub fn Interpreter::run_microtasks(self : Interpreter) -> Unit raise Error {
  // Process microtasks until queue is empty
  // Note: new microtasks can be enqueued during execution
  while self.microtask_queue.length() > 0 {
    let task = self.microtask_queue.remove(0)
    // Call the callback with the argument
    match task.callback {
      Object(obj_data) =>
        match obj_data.callable {
          Some(_) => {
            // Create a dummy location for the call
            let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
            let _ = self.call_value(task.callback, Undefined, [task.argument], loc)

          }
          None => ()
        }
      _ => ()
    }
  }
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
        fulfill_promise(i, promise_data, resolution)
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
            let result = try {
              i.call_value(handler, Undefined, [value], loc)
            } catch {
              e => {
                // Handler threw - reject the dependent promise
                let error_value = js_error_to_value(e)
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
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  interp.enqueue_microtask(job_callback, argument)
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
              interp,
              result_promise_data,
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
                promise_data.is_handled = true
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
            raise @errors.TypeError(message=
              "Promise.prototype.then requires a Promise",
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
            raise @errors.TypeError(message=
              "Promise.prototype.catch requires a Promise",
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
            raise @errors.TypeError(message=
              "Promise.prototype.finally requires a Promise",
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
              let _ = i.call_value(on_finally, Undefined, [], loc)
              // Return the original value
              value
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
            InterpreterCallable("finallyThrowerThunk", fn(i, _this, inner_args) {
              let reason = if inner_args.length() > 0 {
                inner_args[0]
              } else {
                Undefined
              }
              let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
              // Call onFinally
              let _ = i.call_value(on_finally, Undefined, [], loc)
              // Re-throw the reason
              raise JsException(reason)
            }),
          ),
          class_name: "Function",
          descriptors: {},
          symbol_descriptors: {},
          extensible: true,
        })

        let then_method = get_promise_method(promise_data, "then")
        let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
        interp.call_value(then_method, this_val, [value_thunk, thrower_thunk], loc)
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
      InterpreterCallable("resolve", fn(_interp, _this, args) {
        let value = if args.length() > 0 { args[0] } else { Undefined }

        // If value is already a promise, return it
        match value {
          Promise(_) => value
          _ => {
            // Create a fulfilled promise
            let promise_data : PromiseData = {
              state: Fulfilled,
              result: value,
              fulfill_reactions: [],
              reject_reactions: [],
              is_handled: false,
            }
            Promise(promise_data)
          }
        }
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
        let promises = get_promise_array(iterable)
        let count = promises.length()

        if count == 0 {
          // Empty array - return resolved promise with empty array
          let promise_data : PromiseData = {
            state: Fulfilled,
            result: Array({ elements: [] }),
            fulfill_reactions: [],
            reject_reactions: [],
            is_handled: false,
          }
          return Promise(promise_data)
        }

        // Create result promise
        let result_data = new_promise_data()
        let result_promise = Promise(result_data)
        let (resolve, reject) = create_resolving_functions(interp, result_data)

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
                let value = if args2.length() > 0 { args2[0] } else { Undefined }
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
                    {
                      handler: Some(on_fulfilled),
                      resolve,
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
        let promises = get_promise_array(iterable)

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
        let promises = get_promise_array(iterable)
        let count = promises.length()

        if count == 0 {
          let promise_data : PromiseData = {
            state: Fulfilled,
            result: Array({ elements: [] }),
            fulfill_reactions: [],
            reject_reactions: [],
            is_handled: false,
          }
          return Promise(promise_data)
        }

        let result_data = new_promise_data()
        let result_promise = Promise(result_data)
        let (resolve, _reject) = create_resolving_functions(interp, result_data)

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
                args2
              ) {
                let value = if args2.length() > 0 { args2[0] } else { Undefined }
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
                args2
              ) {
                let reason = if args2.length() > 0 { args2[0] } else { Undefined }
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
                    resolve,
                    reject: dummy_reject,
                    reaction_type: Fulfill,
                  })
                  pd.reject_reactions.push({
                    handler: Some(on_rejected),
                    resolve,
                    reject: dummy_reject,
                    reaction_type: Reject,
                  })
                }
                Fulfilled =>
                  enqueue_promise_reaction_job(
                    interp,
                    {
                      handler: Some(on_fulfilled),
                      resolve,
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
                      resolve,
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
        let promises = get_promise_array(iterable)
        let count = promises.length()

        if count == 0 {
          // Empty array - reject with AggregateError
          let promise_data : PromiseData = {
            state: Rejected,
            result: make_aggregate_error("All promises were rejected", []),
            fulfill_reactions: [],
            reject_reactions: [],
            is_handled: false,
          }
          return Promise(promise_data)
        }

        let result_data = new_promise_data()
        let result_promise = Promise(result_data)
        let (resolve, reject) = create_resolving_functions(interp, result_data)

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
                let reason = if args2.length() > 0 { args2[0] } else { Undefined }
                errors[index] = reason
                remaining.val = remaining.val - 1
                if remaining.val == 0 {
                  let loc : @token.Loc = { line: 0, col: 0, offset: 0 }
                  let agg_error = make_aggregate_error(
                    "All promises were rejected",
                    errors,
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
                    resolve,
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
                      resolve,
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

  // Promise constructor itself
  let promise_ctor = Object({
    properties: promise_ctor_props,
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("Promise", fn(interp, _this, args) {
        // Promise must be called with new
        let executor = if args.length() > 0 { args[0] } else { Undefined }

        // Validate executor is callable
        match executor {
          Object(od) =>
            match od.callable {
              Some(_) => ()
              None =>
                raise @errors.TypeError(message=
                  "Promise resolver undefined is not a function",
                )
            }
          _ =>
            raise @errors.TypeError(message=
              "Promise resolver undefined is not a function",
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
                Some(_) => interp.enqueue_microtask(callback, Undefined)
                None =>
                  raise @errors.TypeError(message=
                    "queueMicrotask requires a function argument",
                  )
              }
            _ =>
              raise @errors.TypeError(message=
                "queueMicrotask requires a function argument",
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
/// Helper to extract array of values from iterable (simplified version)
fn get_promise_array(iterable : Value) -> Array[Value] {
  match iterable {
    Array(data) => {
      let result : Array[Value] = []
      for elem in data.elements {
        result.push(elem)
      }
      result
    }
    _ => []
  }
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
