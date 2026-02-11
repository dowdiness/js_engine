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
            let loc = @token.Loc::default()
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
/// ES object-like values that participate in thenable assimilation.
fn is_thenable_object_candidate(value : Value) -> Bool {
  match value {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) => true
    _ => false
  }
}

///|
/// Create an InterpreterCallable function object with explicit `length`.
fn make_interpreter_callable_with_length(
  name : String,
  length : Int,
  body : (Interpreter, Value, Array[Value]) -> Value raise Error,
) -> Value {
  let props : Map[String, Value] = {}
  props["length"] = Number(length.to_double())
  let descriptors : Map[String, PropDescriptor] = {}
  descriptors["length"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  Object({
    properties: props,
    symbol_properties: {},
    prototype: Null,
    callable: Some(InterpreterCallable(name, body)),
    class_name: "Function",
    descriptors,
    symbol_descriptors: {},
    extensible: true,
  })
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
              let job = Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: Some(
                  InterpreterCallable("PromiseResolveThenableJob", fn(
                    i2,
                    _t,
                    _a,
                  ) raise {
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
      InterpreterCallable("PromiseReactionJob", fn(i, _this, args) raise {
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
/// Get iterator and next method for Promise combinators
fn get_promise_iterator_record(
  interp : Interpreter,
  iterable : Value,
  loc : @token.Loc,
) -> (Value, Value) raise Error {
  let iterator_sym = get_iterator_symbol()
  let iterator_method = interp.get_computed_property(
    iterable,
    Symbol(iterator_sym),
    loc,
  )
  let iterator = match iterator_method {
    Object(data) =>
      match data.callable {
        Some(_) => interp.call_value(iterator_method, iterable, [], loc)
        None =>
          raise @errors.TypeError(
            message=type_of(iterable) +
              " is not iterable (Symbol.iterator is not a function)",
          )
      }
    Undefined =>
      raise @errors.TypeError(message=type_of(iterable) + " is not iterable")
    _ => raise @errors.TypeError(message=type_of(iterable) + " is not iterable")
  }
  let next_method = interp.get_property(iterator, "next", loc)
  match next_method {
    Object(next_data) =>
      match next_data.callable {
        Some(_) => (iterator, next_method)
        None =>
          raise @errors.TypeError(message="iterator.next is not a function")
      }
    _ => raise @errors.TypeError(message="iterator.next is not a function")
  }
}

///|
/// IteratorClose used by Promise combinators on abrupt completion during
/// iteration (e.g., next() throws, accessing .done or .value throws).
/// This is NOT invoked when a promise settles first - only for iteration errors.
fn promise_iterator_close(
  interp : Interpreter,
  iterator : Value,
  loc : @token.Loc,
) -> Unit raise Error {
  let return_method = interp.get_property(iterator, "return", loc)
  match return_method {
    Undefined | Null => ()
    Object(return_data) =>
      match return_data.callable {
        Some(_) => {
          let return_result = interp.call_value(
            return_method,
            iterator,
            [],
            loc,
          )
          match return_result {
            Object(_) => ()
            _ =>
              raise @errors.TypeError(
                message="Iterator result is not an object",
              )
          }
        }
        None =>
          raise @errors.TypeError(message="iterator.return is not a function")
      }
    _ => raise @errors.TypeError(message="iterator.return is not a function")
  }
}

///|
/// Handle abrupt completion in Promise combinators:
/// - If iteration is not done, attempt IteratorClose.
/// - For throw completions, preserve the original abrupt reason even if close throws.
/// - Reject the result capability and return its promise.
fn reject_combinator_abrupt(
  interp : Interpreter,
  result_promise : Value,
  reject : Value,
  iterator : Value,
  has_iterator : Bool,
  iterator_done : Bool,
  err : Error,
  loc : @token.Loc,
) -> Value raise Error {
  let reason = js_error_to_value_with_env(err, Some(interp.global))
  if has_iterator && not(iterator_done) {
    // For throw completions, IteratorClose errors do not replace the original
    // abrupt reason.
    promise_iterator_close(interp, iterator, loc) catch {
      _ => ()
    }
  }
  let _ = interp.call_value(reject, Undefined, [reason], loc)
  result_promise
}

///|
/// Resolve combinator result and convert abrupt resolve completion into reject.
fn resolve_combinator_result(
  interp : Interpreter,
  resolve : Value,
  reject : Value,
  resolution : Value,
  loc : @token.Loc,
) -> Unit raise Error {
  let _ = interp.call_value(resolve, Undefined, [resolution], loc) catch {
    e => {
      let reason = js_error_to_value_with_env(e, Some(interp.global))
      let _ = interp.call_value(reject, Undefined, [reason], loc)
      Undefined
    }
  }
}

///|
/// Get constructor.resolve for Promise combinators (single lookup per call)
fn get_promise_resolve_method(
  interp : Interpreter,
  ctor : Value,
  loc : @token.Loc,
) -> Value raise Error {
  let resolve_method = interp.get_property(ctor, "resolve", loc)
  match resolve_method {
    Object(resolve_data) =>
      match resolve_data.callable {
        Some(_) => resolve_method
        None => raise @errors.TypeError(message="resolve is not a function")
      }
    _ => raise @errors.TypeError(message="resolve is not a function")
  }
}

///|
/// Call cached constructor.resolve for Promise combinators
fn call_promise_resolve_method(
  interp : Interpreter,
  resolve_method : Value,
  ctor : Value,
  value : Value,
  loc : @token.Loc,
) -> Value raise Error {
  interp.call_value(resolve_method, ctor, [value], loc)
}

///|
/// SpeciesConstructor(promise, %Promise%) for Promise.prototype methods
fn get_promise_species_constructor(
  interp : Interpreter,
  promise : Value,
  loc : @token.Loc,
) -> Value raise Error {
  let default_ctor = interp.global.get("Promise") catch { _ => Undefined }
  let ctor = interp.get_property(promise, "constructor", loc)
  match ctor {
    Undefined => default_ctor
    Object(_) => {
      let symbol_ctor = interp.global.get("Symbol") catch { _ => Undefined }
      let species_key = match symbol_ctor {
        Object(_) =>
          interp.get_property(symbol_ctor, "species", loc) catch {
            _ => Undefined
          }
        _ => Undefined
      }
      match species_key {
        Symbol(_) => {
          let species = interp.get_computed_property(ctor, species_key, loc)
          match species {
            Undefined | Null => default_ctor
            Object(species_data) =>
              match species_data.callable {
                Some(_) => species
                None =>
                  raise @errors.TypeError(
                    message="Promise species is not a constructor",
                  )
              }
            _ =>
              raise @errors.TypeError(
                message="Promise species is not a constructor",
              )
          }
        }
        _ => default_ctor
      }
    }
    _ => raise @errors.TypeError(message="Promise constructor is not an object")
  }
}

///|
/// Construct a value with `new` from an already-evaluated constructor and args
fn construct_with_value(
  interp : Interpreter,
  ctor : Value,
  args : Array[Value],
  loc : @token.Loc,
) -> Value raise Error {
  interp.construct_value(ctor, args, loc)
}

///|
/// Minimal NewPromiseCapability(C) used by Promise.resolve
fn create_promise_capability_from_constructor(
  interp : Interpreter,
  ctor : Value,
  loc : @token.Loc,
) -> (Value, Value, Value) raise Error {
  let resolve_ref : Ref[Value] = { val: Undefined }
  let reject_ref : Ref[Value] = { val: Undefined }
  let executor = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("promiseCapabilityExecutor", fn(
        _i,
        _this,
        args,
      ) raise {
        let resolve_fn = if args.length() > 0 { args[0] } else { Undefined }
        let reject_fn = if args.length() > 1 { args[1] } else { Undefined }
        // Per GetCapabilitiesExecutor, only throw once either slot is set to
        // a non-undefined value. A prior call with (undefined, undefined) is
        // allowed and should not trigger this TypeError on a later call.
        if not(resolve_ref.val is Undefined) || not(reject_ref.val is Undefined) {
          raise @errors.TypeError(
            message="Promise capability executor called multiple times",
          )
        }
        resolve_ref.val = resolve_fn
        reject_ref.val = reject_fn
        Undefined
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let promise = construct_with_value(interp, ctor, [executor], loc)
  // Promise subclass instances are represented as Promise values in this engine.
  // Preserve the construction target so SpeciesConstructor-based lookups can
  // observe the right constructor on subsequent then/catch/finally calls.
  match promise {
    Promise(promise_data) => {
      promise_data.properties["constructor"] = ctor
      promise_data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
  let resolve = resolve_ref.val
  let reject = reject_ref.val
  match resolve {
    Object(data) =>
      if data.callable is None {
        raise @errors.TypeError(
          message="Promise resolve function is not callable",
        )
      }
    _ =>
      raise @errors.TypeError(
        message="Promise resolve function is not callable",
      )
  }
  match reject {
    Object(data) =>
      if data.callable is None {
        raise @errors.TypeError(
          message="Promise reject function is not callable",
        )
      }
    _ =>
      raise @errors.TypeError(message="Promise reject function is not callable")
  }
  (promise, resolve, reject)
}

///|
/// Invoke promiseLike.then(onFulfilled, onRejected)
fn invoke_then_method(
  interp : Interpreter,
  promise_like : Value,
  on_fulfilled : Value,
  on_rejected : Value,
  loc : @token.Loc,
) -> Unit raise Error {
  let then_method = interp.get_property(promise_like, "then", loc)
  match then_method {
    Object(then_data) =>
      match then_data.callable {
        Some(_) => {
          let _ = interp.call_value(
            then_method,
            promise_like,
            [on_fulfilled, on_rejected],
            loc,
          )
          ()
        }
        None => raise @errors.TypeError(message="then is not a function")
      }
    _ => raise @errors.TypeError(message="then is not a function")
  }
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
      InterpreterCallable("then", fn(interp, this_val, args) raise {
        match this_val {
          Promise(promise_data) => {
            let loc = @token.Loc::default()
            let ctor = get_promise_species_constructor(interp, this_val, loc)
            let (result_promise, resolve, reject) = create_promise_capability_from_constructor(
              interp, ctor, loc,
            )
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
      InterpreterCallable("catch", fn(interp, this_val, args) raise {
        // catch(onRejected) is just then(undefined, onRejected)
        let then_method = interp.get_property(
          this_val,
          "then",
          @token.Loc::default(),
        )
        let loc = @token.Loc::default()
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
      InterpreterCallable("finally", fn(interp, this_val, args) raise {
        let loc = @token.Loc::default()
        let ctor = get_promise_species_constructor(interp, this_val, loc)
        let on_finally = if args.length() > 0 { args[0] } else { Undefined }
        let is_callable = match on_finally {
          Object(od) => od.callable is Some(_)
          _ => false
        }
        if not(is_callable) {
          // If onFinally is not callable, pass through
          let then_method = interp.get_property(this_val, "then", loc)
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
            InterpreterCallable("finallyValueThunk", fn(
              i,
              _this,
              inner_args,
            ) raise {
              let value = if inner_args.length() > 0 {
                inner_args[0]
              } else {
                Undefined
              }
              // Call onFinally
              let finally_result = i.call_value(on_finally, Undefined, [], loc)
              let promise_resolve = get_promise_resolve_method(i, ctor, loc)
              let result_promise = call_promise_resolve_method(
                i, promise_resolve, ctor, finally_result, loc,
              )
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
              let then_method = i.get_property(result_promise, "then", loc)
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
            ) raise {
              let reason = if inner_args.length() > 0 {
                inner_args[0]
              } else {
                Undefined
              }
              // Call onFinally
              let finally_result = i.call_value(on_finally, Undefined, [], loc)
              let promise_resolve = get_promise_resolve_method(i, ctor, loc)
              let result_promise = call_promise_resolve_method(
                i, promise_resolve, ctor, finally_result, loc,
              )
              // Create a thunk that re-throws the original reason
              let throw_reason_thunk = Object({
                properties: {},
                symbol_properties: {},
                prototype: Null,
                callable: Some(
                  InterpreterCallable("throwReason", fn(_i2, _t, _a) raise {
                    raise JsException(reason)
                  }),
                ),
                class_name: "Function",
                descriptors: {},
                symbol_descriptors: {},
                extensible: true,
              })
              // Chain: Promise.resolve(finally_result).then(() => { throw reason })
              let then_method = i.get_property(result_promise, "then", loc)
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
        let then_method = interp.get_property(this_val, "then", loc)
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
      InterpreterCallable("resolve", fn(interp, this_val, args) raise {
        let value = if args.length() > 0 { args[0] } else { Undefined }
        let loc = @token.Loc::default()

        // Fast path: if x is a Promise already constructed by C, return x
        match value {
          Promise(_) => {
            let x_ctor = interp.get_property(value, "constructor", loc)
            if strict_equal(x_ctor, this_val) {
              return value
            }
          }
          _ => ()
        }

        let (promise, resolve, _reject) = create_promise_capability_from_constructor(
          interp, this_val, loc,
        )
        let _ = interp.call_value(resolve, Undefined, [value], loc)
        promise
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
      InterpreterCallable("reject", fn(interp, this_val, args) raise {
        let reason = if args.length() > 0 { args[0] } else { Undefined }
        let loc = @token.Loc::default()
        let (promise, _resolve, reject) = create_promise_capability_from_constructor(
          interp, this_val, loc,
        )
        let _ = interp.call_value(reject, Undefined, [reason], loc)
        promise
      }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })

  // Promise.all(iterable)
  // NOTE: PerformPromiseAll synchronously consumes the entire input iterator
  // before any promise settles. Iterator consumption is NOT lazy.
  promise_ctor_props["all"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("all", fn(interp, _this, args) raise {
        let iterable = if args.length() > 0 { args[0] } else { Undefined }
        let loc = @token.Loc::default()
        let (result_promise, resolve, reject) = create_promise_capability_from_constructor(
          interp, _this, loc,
        )
        let results : Array[Value] = []
        let remaining : Ref[Int] = { val: 1 }
        let mut iterator : Value = Undefined
        let mut has_iterator = false
        let mut iterator_done = false

        try {
          let promise_resolve = get_promise_resolve_method(interp, _this, loc)
          let (iter, next_method) = get_promise_iterator_record(
            interp, iterable, loc,
          )
          iterator = iter
          has_iterator = true
          while true {
            let next_result = interp.call_value(next_method, iterator, [], loc) catch {
              e => {
                iterator_done = true
                raise e
              }
            }
            let done = match next_result {
              Object(_) => {
                let done_value = interp.get_property(next_result, "done", loc) catch {
                  e => {
                    iterator_done = true
                    raise e
                  }
                }
                is_truthy(done_value)
              }
              _ => {
                iterator_done = true
                raise @errors.TypeError(
                  message="Iterator result is not an object",
                )
              }
            }
            if done {
              iterator_done = true
              break
            }
            let next_value = interp.get_property(next_result, "value", loc) catch {
              e => {
                iterator_done = true
                raise e
              }
            }
            let index = results.length()
            results.push(Undefined)
            remaining.val = remaining.val + 1

            let next_promise = call_promise_resolve_method(
              interp, promise_resolve, _this, next_value, loc,
            )
            let already_called : Ref[Bool] = { val: false }
            let resolve_element = make_interpreter_callable_with_length(
              "allResolveElement",
              1,
              fn(i2, _t2, args2) raise {
                if already_called.val {
                  return Undefined
                }
                already_called.val = true
                let value = if args2.length() > 0 {
                  args2[0]
                } else {
                  Undefined
                }
                results[index] = value
                remaining.val = remaining.val - 1
                if remaining.val == 0 {
                  resolve_combinator_result(
                    i2,
                    resolve,
                    reject,
                    Array({ elements: results }),
                    loc,
                  )
                }
                Undefined
              },
            )
            invoke_then_method(
              interp, next_promise, resolve_element, reject, loc,
            )
          }
        } catch {
          e =>
            return reject_combinator_abrupt(
              interp, result_promise, reject, iterator, has_iterator, iterator_done,
              e, loc,
            )
        }
        remaining.val = remaining.val - 1
        if remaining.val == 0 {
          resolve_combinator_result(
            interp,
            resolve,
            reject,
            Array({ elements: results }),
            loc,
          )
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
  // NOTE: PerformPromiseRace synchronously consumes the ENTIRE iterator before
  // any promise settles. IteratorClose is only invoked for abrupt completion
  // during iteration (e.g., next() throws), NOT when a promise settles first.
  promise_ctor_props["race"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("race", fn(interp, _this, args) raise {
        let iterable = if args.length() > 0 { args[0] } else { Undefined }
        let loc = @token.Loc::default()
        let (result_promise, resolve, reject) = create_promise_capability_from_constructor(
          interp, _this, loc,
        )
        let mut iterator : Value = Undefined
        let mut has_iterator = false
        let mut iterator_done = false

        try {
          let promise_resolve = get_promise_resolve_method(interp, _this, loc)
          let (iter, next_method) = get_promise_iterator_record(
            interp, iterable, loc,
          )
          iterator = iter
          has_iterator = true
          // Per PerformPromiseRace, iteration is synchronous and continues until
          // iterator completion or abrupt completion. We do not stop consuming
          // the iterator when one already-enqueued promise settles.
          while true {
            let next_result = interp.call_value(next_method, iterator, [], loc) catch {
              e => {
                iterator_done = true
                raise e
              }
            }
            let done = match next_result {
              Object(_) => {
                let done_value = interp.get_property(next_result, "done", loc) catch {
                  e => {
                    iterator_done = true
                    raise e
                  }
                }
                is_truthy(done_value)
              }
              _ => {
                iterator_done = true
                raise @errors.TypeError(
                  message="Iterator result is not an object",
                )
              }
            }
            if done {
              iterator_done = true
              break
            }
            let next_value = interp.get_property(next_result, "value", loc) catch {
              e => {
                iterator_done = true
                raise e
              }
            }
            let next_promise = call_promise_resolve_method(
              interp, promise_resolve, _this, next_value, loc,
            )
            invoke_then_method(interp, next_promise, resolve, reject, loc)
          }
        } catch {
          e =>
            return reject_combinator_abrupt(
              interp, result_promise, reject, iterator, has_iterator, iterator_done,
              e, loc,
            )
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
  // NOTE: PerformPromiseAllSettled synchronously consumes the entire input
  // iterator. Never rejects - waits for all promises to settle.
  promise_ctor_props["allSettled"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("allSettled", fn(interp, _this, args) raise {
        let iterable = if args.length() > 0 { args[0] } else { Undefined }
        let loc = @token.Loc::default()
        let (result_promise, resolve, reject) = create_promise_capability_from_constructor(
          interp, _this, loc,
        )
        let results : Array[Value] = []
        let remaining : Ref[Int] = { val: 1 }
        let mut iterator : Value = Undefined
        let mut has_iterator = false
        let mut iterator_done = false

        try {
          let promise_resolve = get_promise_resolve_method(interp, _this, loc)
          let (iter, next_method) = get_promise_iterator_record(
            interp, iterable, loc,
          )
          iterator = iter
          has_iterator = true
          while true {
            let next_result = interp.call_value(next_method, iterator, [], loc) catch {
              e => {
                iterator_done = true
                raise e
              }
            }
            let done = match next_result {
              Object(_) => {
                let done_value = interp.get_property(next_result, "done", loc) catch {
                  e => {
                    iterator_done = true
                    raise e
                  }
                }
                is_truthy(done_value)
              }
              _ => {
                iterator_done = true
                raise @errors.TypeError(
                  message="Iterator result is not an object",
                )
              }
            }
            if done {
              iterator_done = true
              break
            }
            let next_value = interp.get_property(next_result, "value", loc) catch {
              e => {
                iterator_done = true
                raise e
              }
            }
            let index = results.length()
            results.push(Undefined)
            remaining.val = remaining.val + 1

            let next_promise = call_promise_resolve_method(
              interp, promise_resolve, _this, next_value, loc,
            )
            let already_called : Ref[Bool] = { val: false }
            let on_fulfilled = make_interpreter_callable_with_length(
              "allSettledOnFulfilled",
              1,
              fn(i2, _t2, args2) raise {
                if already_called.val {
                  return Undefined
                }
                already_called.val = true
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
                  resolve_combinator_result(
                    i2,
                    resolve,
                    reject,
                    Array({ elements: results }),
                    loc,
                  )
                }
                Undefined
              },
            )
            let on_rejected = make_interpreter_callable_with_length(
              "allSettledOnRejected",
              1,
              fn(i2, _t2, args2) raise {
                if already_called.val {
                  return Undefined
                }
                already_called.val = true
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
                  resolve_combinator_result(
                    i2,
                    resolve,
                    reject,
                    Array({ elements: results }),
                    loc,
                  )
                }
                Undefined
              },
            )
            invoke_then_method(
              interp, next_promise, on_fulfilled, on_rejected, loc,
            )
          }
        } catch {
          e =>
            return reject_combinator_abrupt(
              interp, result_promise, reject, iterator, has_iterator, iterator_done,
              e, loc,
            )
        }
        remaining.val = remaining.val - 1
        if remaining.val == 0 {
          resolve_combinator_result(
            interp,
            resolve,
            reject,
            Array({ elements: results }),
            loc,
          )
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
  // NOTE: PerformPromiseAny synchronously consumes the entire input iterator.
  // Rejects with AggregateError only if ALL promises reject.
  promise_ctor_props["any"] = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      InterpreterCallable("any", fn(interp, _this, args) raise {
        let iterable = if args.length() > 0 { args[0] } else { Undefined }
        let loc = @token.Loc::default()
        let (result_promise, resolve, reject) = create_promise_capability_from_constructor(
          interp, _this, loc,
        )
        let errors : Array[Value] = []
        let remaining : Ref[Int] = { val: 1 }
        let mut iterator : Value = Undefined
        let mut has_iterator = false
        let mut iterator_done = false

        try {
          let promise_resolve = get_promise_resolve_method(interp, _this, loc)
          let (iter, next_method) = get_promise_iterator_record(
            interp, iterable, loc,
          )
          iterator = iter
          has_iterator = true
          // As in the spec algorithm, this loop consumes the iterator
          // synchronously; resolving early does not short-circuit iteration.
          while true {
            let next_result = interp.call_value(next_method, iterator, [], loc) catch {
              e => {
                iterator_done = true
                raise e
              }
            }
            let done = match next_result {
              Object(_) => {
                let done_value = interp.get_property(next_result, "done", loc) catch {
                  e => {
                    iterator_done = true
                    raise e
                  }
                }
                is_truthy(done_value)
              }
              _ => {
                iterator_done = true
                raise @errors.TypeError(
                  message="Iterator result is not an object",
                )
              }
            }
            if done {
              iterator_done = true
              break
            }
            let next_value = interp.get_property(next_result, "value", loc) catch {
              e => {
                iterator_done = true
                raise e
              }
            }
            let index = errors.length()
            errors.push(Undefined)
            remaining.val = remaining.val + 1

            let next_promise = call_promise_resolve_method(
              interp, promise_resolve, _this, next_value, loc,
            )
            let already_called : Ref[Bool] = { val: false }
            let on_fulfilled = make_interpreter_callable_with_length(
              "anyOnFulfilled",
              1,
              fn(i2, _t2, args2) raise {
                if already_called.val {
                  return Undefined
                }
                already_called.val = true
                let value = if args2.length() > 0 {
                  args2[0]
                } else {
                  Undefined
                }
                let _ = i2.call_value(resolve, Undefined, [value], loc)
                Undefined
              },
            )
            let on_rejected = make_interpreter_callable_with_length(
              "anyOnRejected",
              1,
              fn(i2, _t2, args2) raise {
                if already_called.val {
                  return Undefined
                }
                already_called.val = true
                let reason = if args2.length() > 0 {
                  args2[0]
                } else {
                  Undefined
                }
                errors[index] = reason
                remaining.val = remaining.val - 1
                if remaining.val == 0 {
                  let agg_error = make_aggregate_error(
                    interp, "All promises were rejected", errors,
                  )
                  let _ = i2.call_value(reject, Undefined, [agg_error], loc)
                }
                Undefined
              },
            )
            invoke_then_method(
              interp, next_promise, on_fulfilled, on_rejected, loc,
            )
          }
        } catch {
          e =>
            return reject_combinator_abrupt(
              interp, result_promise, reject, iterator, has_iterator, iterator_done,
              e, loc,
            )
        }
        remaining.val = remaining.val - 1
        if remaining.val == 0 {
          let agg_error = make_aggregate_error(
            interp, "All promises were rejected", errors,
          )
          let _ = interp.call_value(reject, Undefined, [agg_error], loc)
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
      ConstructorOnlyCallable("Promise", fn(interp, args) raise {
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
        let loc = @token.Loc::default()
        try {
          let _ = interp.call_value(executor, Undefined, [resolve, reject], loc)
        } catch {
          e => {
            // If executor throws, reject the promise
            let error_value = js_error_to_value_with_env(e, Some(interp.global))
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

  // Promise[Symbol.species] getter returns `this` (used by SpeciesConstructor).
  let species_getter = Object({
    properties: {},
    symbol_properties: {},
    prototype: Null,
    callable: Some(
      MethodCallable("get [Symbol.species]", fn(this_val, _args) { this_val }),
    ),
    class_name: "Function",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let species_symbol_val = env.get("Symbol") catch { _ => Undefined }
  match species_symbol_val {
    Object(symbol_data) =>
      match symbol_data.properties.get("species") {
        Some(Symbol(species_sym)) =>
          match promise_ctor {
            Object(ctor_data) => {
              ctor_data.symbol_properties[species_sym.id] = Undefined
              ctor_data.symbol_descriptors[species_sym.id] = {
                writable: false,
                enumerable: false,
                configurable: true,
                getter: Some(species_getter),
                setter: None,
              }
            }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }

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
      data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
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
        InterpreterCallable("queueMicrotask", fn(interp, _this, args) raise {
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
        InterpreterCallable("setTimeout", fn(interp, _this, args) raise {
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
        InterpreterCallable("setInterval", fn(interp, _this, args) raise {
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
    let loc = @token.Loc::default()
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
/// Helper to create an AggregateError value
fn make_aggregate_error(
  interp : Interpreter,
  message : String,
  errors : Array[Value],
) -> Value raise Error {
  let loc = @token.Loc::default()
  let errors_value = Array({ elements: errors })
  let aggregate_ctor = interp.global.get("AggregateError") catch {
    _ => Undefined
  }
  match aggregate_ctor {
    Object(data) =>
      match data.callable {
        Some(_) =>
          return interp.construct_value(
            aggregate_ctor,
            [errors_value, String_(message)],
            loc,
          )
        None => ()
      }
    _ => ()
  }
  let props : Map[String, Value] = {}
  props["name"] = String_("AggregateError")
  props["message"] = String_(message)
  props["errors"] = errors_value
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
