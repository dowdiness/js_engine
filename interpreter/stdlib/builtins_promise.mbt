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
/// Get Promise.prototype methods for a Promise instance
pub fn get_promise_method(
  _data : PromiseData,
  prop : String,
  realm_state : @runtime.RealmState,
) -> Value {
  match realm_state.get_promise_proto() {
    Object(proto_data) =>
      match proto_data.bag.properties.get(prop) {
        Some(m) => m
        None => Undefined
      }
    _ => Undefined
  }
}

///|
/// Get iterator and next method for Promise combinators
fn get_promise_iterator_record(
  interp : Interpreter,
  iterable : Value,
  loc : @token.Loc,
) -> (Value, Value) raise Error {
  let iterator_sym = interp.realm_state.well_known_symbols.iterator
  let iterator_method = interp.get_computed_property(
    iterable,
    Symbol(iterator_sym),
    loc,
  )
  let iterator = match iterator_method {
    _ if @runtime.is_function_value(iterator_method) =>
      interp.call_value(iterator_method, iterable, [], loc)
    Object(_) =>
      raise @errors.TypeError(
        message=@runtime.type_of(iterable) +
          " is not iterable (Symbol.iterator is not a function)",
      )
    _ =>
      raise @errors.TypeError(
        message=@runtime.type_of(iterable) + " is not iterable",
      )
  }
  let next_method = interp.get_property(iterator, "next", loc)
  guard @runtime.is_function_value(next_method) else {
    raise @errors.TypeError(message="iterator.next is not a function")
  }
  (iterator, next_method)
}

///|
/// Handle abrupt completion in Promise combinators:
/// - If iteration is not done, attempt IteratorClose (ThrowCompletion path).
/// - Preserve the original abrupt reason.
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
  let reason = @runtime.js_error_to_value_with_env(err, Some(interp.global))
  if has_iterator && !iterator_done {
    interp.iterator_close_throw(iterator, loc)
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
      let reason = @runtime.js_error_to_value_with_env(e, Some(interp.global))
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
  guard @runtime.is_function_value(resolve_method) else {
    raise @errors.TypeError(message="resolve is not a function")
  }
  resolve_method
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
            _ if @runtime.is_function_value(species) => species
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
  let executor = @runtime.make_interp_method_func(
    name="",
    length=2,
    realm_state=Some(interp.realm_state),
    fn(_i, _this, args) raise {
      let resolve_fn = if args.length() > 0 { args[0] } else { Undefined }
      let reject_fn = if args.length() > 1 { args[1] } else { Undefined }
      // Per GetCapabilitiesExecutor, only throw once either slot is set to
      // a non-undefined value. A prior call with (undefined, undefined) is
      // allowed and should not trigger this TypeError on a later call.
      if !(resolve_ref.val is Undefined) || !(reject_ref.val is Undefined) {
        raise @errors.TypeError(
          message="Promise capability executor called multiple times",
        )
      }
      resolve_ref.val = resolve_fn
      reject_ref.val = reject_fn
      Undefined
    },
  )
  let promise = construct_with_value(interp, ctor, [executor], loc)
  let resolve = resolve_ref.val
  let reject = reject_ref.val
  guard @runtime.is_function_value(resolve) else {
    raise @errors.TypeError(message="Promise resolve function is not callable")
  }
  guard @runtime.is_function_value(reject) else {
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
  guard @runtime.is_function_value(then_method) else {
    raise @errors.TypeError(message="then is not a function")
  }
  let _ = interp.call_value(
    then_method,
    promise_like,
    [on_fulfilled, on_rejected],
    loc,
  )
}

///|
/// Setup Promise constructor and prototype methods
pub fn setup_promise(
  env : Environment,
  realm_state : @runtime.RealmState,
) -> Unit {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  // Promise prototype with then, catch, finally
  let promise_proto_props : Map[String, Value] = {}

  // Promise.prototype.then(onFulfilled, onRejected)
  promise_proto_props["then"] = @runtime.make_interp_method_func(
    name="then",
    length=2,
    fn(interp, this_val, args) raise {
      match this_val {
        Value::Promise(promise_data) => {
          let loc = @token.Loc::default()
          let ctor = get_promise_species_constructor(interp, this_val, loc)
          let (result_promise, resolve, reject) = create_promise_capability_from_constructor(
            interp, ctor, loc,
          )
          let on_fulfilled = match args {
            [f, ..] if @runtime.is_function_value(f) => Some(f)
            _ => None
          }
          let on_rejected = match args {
            [_, r, ..] if @runtime.is_function_value(r) => Some(r)
            _ => None
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
              @runtime.enqueue_promise_reaction_job(
                interp,
                fulfill_reaction,
                promise_data.result,
              )
            Rejected => {
              if on_rejected is Some(_) {
                promise_data.is_handled = true
              }
              @runtime.enqueue_promise_reaction_job(
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
    },
  )

  // Promise.prototype.catch(onRejected)
  promise_proto_props["catch"] = @runtime.make_interp_method_func(
    name="catch",
    length=1,
    fn(interp, this_val, args) raise {
      // catch(onRejected) is just then(undefined, onRejected)
      let then_method = interp.get_property(
        this_val,
        "then",
        @token.Loc::default(),
      )
      let loc = @token.Loc::default()
      let on_rejected = if args.length() > 0 { args[0] } else { Undefined }
      interp.call_value(then_method, this_val, [Undefined, on_rejected], loc)
    },
  )

  // Promise.prototype.finally(onFinally)
  promise_proto_props["finally"] = @runtime.make_interp_method_func(
    name="finally",
    length=1,
    fn(interp, this_val, args) raise {
      let loc = @token.Loc::default()
      let ctor = get_promise_species_constructor(interp, this_val, loc)
      let on_finally = if args.length() > 0 { args[0] } else { Undefined }
      if !@runtime.is_function_value(on_finally) {
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
      let value_thunk = @runtime.make_interp_method_func(name="", length=1, fn(
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
        let return_value_thunk = @runtime.make_interp_method_func(
          name="",
          length=0,
          fn(_i2, _t, _a) { value },
        )
        // Chain: Promise.resolve(finally_result).then(() => value)
        let then_method = i.get_property(result_promise, "then", loc)
        i.call_value(then_method, result_promise, [return_value_thunk], loc)
      })
      let thrower_thunk = @runtime.make_interp_method_func(name="", length=1, fn(
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
        let throw_reason_thunk = @runtime.make_interp_method_func(
          name="",
          length=0,
          fn(_i2, _t, _a) raise {
            @runtime.raise_js_exception(reason)
            Undefined
          },
        )
        // Chain: Promise.resolve(finally_result).then(() => { throw reason })
        let then_method = i.get_property(result_promise, "then", loc)
        i.call_value(then_method, result_promise, [throw_reason_thunk], loc)
      })
      let then_method = interp.get_property(this_val, "then", loc)
      interp.call_value(
        then_method,
        this_val,
        [value_thunk, thrower_thunk],
        loc,
      )
    },
  )
  let promise_proto_descs : Map[String, PropDescriptor] = {}
  let pd_method_desc = @runtime.builtin_method_desc()
  promise_proto_descs["then"] = pd_method_desc
  promise_proto_descs["catch"] = pd_method_desc
  promise_proto_descs["finally"] = pd_method_desc
  // Symbol.toStringTag = "Promise" per §27.2.3.6: {w:false, e:false, c:true}
  let to_string_tag_sym = realm_state.well_known_symbols.to_string_tag
  let promise_proto_sym_props : Map[Int, Value] = {}
  let promise_proto_sym_descs : Map[Int, PropDescriptor] = {}
  promise_proto_sym_props[to_string_tag_sym.id] = Value::String_("Promise")
  promise_proto_sym_descs[to_string_tag_sym.id] = nf_desc
  let promise_proto = Value::Object({
    bag: {
      properties: promise_proto_props,
      symbol_properties: promise_proto_sym_props,
      descriptors: promise_proto_descs,
      symbol_descriptors: promise_proto_sym_descs,
      internal_slots: {},
    },
    prototype: @runtime.get_obj_proto(realm_state=Some(realm_state)),
    callable: None,
    class_name: "Promise",
    extensible: true,
    arraybuffer_state: None,
  })

  // Promise constructor
  let promise_ctor_props : Map[String, Value] = {}
  promise_ctor_props["length"] = Value::Number(1.0)
  promise_ctor_props["name"] = Value::String_("Promise")

  // Promise.resolve(value)
  promise_ctor_props["resolve"] = @runtime.make_interp_method_func(
    name="resolve",
    length=1,
    fn(interp, this_val, args) raise {
      // §27.2.4.5 step 2: If Type(C) is not Object, throw a TypeError exception.
      if !@runtime.is_object_value(this_val) {
        raise @errors.TypeError(message="Promise.resolve called on non-object")
      }
      let value = if args.length() > 0 { args[0] } else { Undefined }
      let loc = @token.Loc::default()

      // Fast path: if x is a Promise already constructed by C, return x
      match value {
        Promise(_) => {
          let x_ctor = interp.get_property(value, "constructor", loc)
          if @runtime.strict_equal(x_ctor, this_val) {
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
    },
  )

  // Promise.reject(reason)
  promise_ctor_props["reject"] = @runtime.make_interp_method_func(
    name="reject",
    length=1,
    fn(interp, this_val, args) raise {
      // §27.2.4.4 step 2: If Type(C) is not Object, throw a TypeError exception.
      if !@runtime.is_object_value(this_val) {
        raise @errors.TypeError(message="Promise.reject called on non-object")
      }
      let reason = if args.length() > 0 { args[0] } else { Undefined }
      let loc = @token.Loc::default()
      let (promise, _resolve, reject) = create_promise_capability_from_constructor(
        interp, this_val, loc,
      )
      let _ = interp.call_value(reject, Undefined, [reason], loc)
      promise
    },
  )

  // Promise.withResolvers()
  // https://tc39.es/ecma262/#sec-promise.withresolvers
  promise_ctor_props["withResolvers"] = @runtime.make_interp_method_func(
    name="withResolvers",
    length=0,
    fn(interp, this_val, _args) raise {
      let loc = @token.Loc::default()
      let (promise, resolve, reject) = create_promise_capability_from_constructor(
        interp, this_val, loc,
      )
      let props : Map[String, Value] = {}
      props["promise"] = promise
      props["resolve"] = resolve
      props["reject"] = reject
      Value::Object({
        bag: {
          properties: props,
          symbol_properties: {},
          descriptors: {},
          symbol_descriptors: {},
          internal_slots: {},
        },
        prototype: @runtime.get_obj_proto(realm_state=Some(realm_state)),
        callable: None,
        class_name: "Object",
        extensible: true,
        arraybuffer_state: None,
      })
    },
  )

  // Promise.try(callbackFn, ...args)
  // https://tc39.es/ecma262/#sec-promise.try
  promise_ctor_props["try"] = @runtime.make_interp_method_func(
    name="try",
    length=1,
    fn(interp, this_val, args) raise {
      let loc = @token.Loc::default()
      // Step 1-3: NewPromiseCapability(C) — validates C is a constructor
      let (promise, resolve, reject) = create_promise_capability_from_constructor(
        interp, this_val, loc,
      )
      // Extract callbackFn and rest args
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      let call_args : Array[Value] = if args.length() > 1 {
        let a : Array[Value] = []
        for i in 1..<args.length() {
          a.push(args[i])
        }
        a
      } else {
        []
      }
      // Step 4: Call callback, capture completion
      let status : Result[Value, _] = Ok(
        interp.call_value(callback, Undefined, call_args, loc),
      ) catch {
        err => Err(err)
      }
      // Step 5-6: Resolve or reject based on completion.
      // resolve/reject throws propagate outward per spec (? Call).
      match status {
        Ok(result) => {
          let _ = interp.call_value(resolve, Undefined, [result], loc)
        }
        Err(err) => {
          // Env-aware conversion so the rejection value gets a proper
          // prototype chain — without this, the error has prototype: Null
          // and `err instanceof TypeError` fails.
          let error_val = @runtime.js_error_to_value_with_env(
            err,
            Some(interp.global),
          )
          let _ = interp.call_value(reject, Undefined, [error_val], loc)
        }
      }
      // Step 7
      promise
    },
  )

  // Promise.all(iterable)
  // NOTE: PerformPromiseAll synchronously consumes the entire input iterator
  // before any promise settles. Iterator consumption is NOT lazy.
  promise_ctor_props["all"] = @runtime.make_interp_method_func(
    name="all",
    length=1,
    fn(interp, _this, args) raise {
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
              @runtime.is_truthy(done_value)
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
          let resolve_element = @runtime.make_interp_method_func(
            name="",
            length=1,
            realm_state=Some(realm_state),
            fn(i2, _t2, args2) raise {
              if already_called.val {
                return Undefined
              }
              already_called.val = true
              let value = if args2.length() > 0 { args2[0] } else { Undefined }
              results[index] = value
              remaining.val = remaining.val - 1
              if remaining.val == 0 {
                resolve_combinator_result(
                  i2,
                  resolve,
                  reject,
                  @runtime.make_array(results),
                  loc,
                )
              }
              Undefined
            },
          )
          invoke_then_method(interp, next_promise, resolve_element, reject, loc)
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
          @runtime.make_array(results),
          loc,
        )
      }
      result_promise
    },
  )

  // Promise.race(iterable)
  // NOTE: PerformPromiseRace synchronously consumes the ENTIRE iterator before
  // any promise settles. IteratorClose is only invoked for abrupt completion
  // during iteration (e.g., next() throws), NOT when a promise settles first.
  promise_ctor_props["race"] = @runtime.make_interp_method_func(
    name="race",
    length=1,
    fn(interp, _this, args) raise {
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
              @runtime.is_truthy(done_value)
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
    },
  )

  // Promise.allSettled(iterable)
  // NOTE: PerformPromiseAllSettled synchronously consumes the entire input
  // iterator. Never rejects - waits for all promises to settle.
  promise_ctor_props["allSettled"] = @runtime.make_interp_method_func(
    name="allSettled",
    length=1,
    fn(interp, _this, args) raise {
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
              @runtime.is_truthy(done_value)
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
          let on_fulfilled = @runtime.make_interp_method_func(
            name="",
            length=1,
            realm_state=Some(realm_state),
            fn(i2, _t2, args2) raise {
              if already_called.val {
                return Undefined
              }
              already_called.val = true
              let value = if args2.length() > 0 { args2[0] } else { Undefined }
              let result_props : Map[String, Value] = {}
              result_props["status"] = Value::String_("fulfilled")
              result_props["value"] = value
              results[index] = Value::Object({
                bag: {
                  properties: result_props,
                  symbol_properties: {},
                  descriptors: {},
                  symbol_descriptors: {},
                  internal_slots: {},
                },
                prototype: Null,
                callable: None,
                class_name: "Object",
                extensible: true,
                arraybuffer_state: None,
              })
              remaining.val = remaining.val - 1
              if remaining.val == 0 {
                resolve_combinator_result(
                  i2,
                  resolve,
                  reject,
                  @runtime.make_array(results),
                  loc,
                )
              }
              Undefined
            },
          )
          let on_rejected = @runtime.make_interp_method_func(
            name="",
            length=1,
            realm_state=Some(realm_state),
            fn(i2, _t2, args2) raise {
              if already_called.val {
                return Undefined
              }
              already_called.val = true
              let reason = if args2.length() > 0 { args2[0] } else { Undefined }
              let result_props : Map[String, Value] = {}
              result_props["status"] = Value::String_("rejected")
              result_props["reason"] = reason
              results[index] = Value::Object({
                bag: {
                  properties: result_props,
                  symbol_properties: {},
                  descriptors: {},
                  symbol_descriptors: {},
                  internal_slots: {},
                },
                prototype: Null,
                callable: None,
                class_name: "Object",
                extensible: true,
                arraybuffer_state: None,
              })
              remaining.val = remaining.val - 1
              if remaining.val == 0 {
                resolve_combinator_result(
                  i2,
                  resolve,
                  reject,
                  @runtime.make_array(results),
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
          @runtime.make_array(results),
          loc,
        )
      }
      result_promise
    },
  )

  // Promise.any(iterable)
  // NOTE: PerformPromiseAny synchronously consumes the entire input iterator.
  // Rejects with AggregateError only if ALL promises reject.
  promise_ctor_props["any"] = @runtime.make_interp_method_func(
    name="any",
    length=1,
    fn(interp, _this, args) raise {
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
              @runtime.is_truthy(done_value)
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
          // §27.2.4.3.1: Promise.any resolve element has no alreadyCalled guard —
          // multiple calls are intentionally allowed per spec.
          let on_fulfilled = @runtime.make_interp_method_func(
            name="",
            length=1,
            realm_state=Some(realm_state),
            fn(i2, _t2, args2) raise {
              let value = if args2.length() > 0 { args2[0] } else { Undefined }
              let _ = i2.call_value(resolve, Undefined, [value], loc)
              Undefined
            },
          )
          // §27.2.4.3.2: Promise.any reject element has its own alreadyCalled guard.
          let already_called_reject : Ref[Bool] = { val: false }
          let on_rejected = @runtime.make_interp_method_func(
            name="",
            length=1,
            realm_state=Some(realm_state),
            fn(i2, _t2, args2) raise {
              if already_called_reject.val {
                return Undefined
              }
              already_called_reject.val = true
              let reason = if args2.length() > 0 { args2[0] } else { Undefined }
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
    },
  )

  // Promise constructor itself - requires 'new' keyword
  let promise_ctor = Value::Object({
    bag: {
      properties: promise_ctor_props,
      symbol_properties: {},
      descriptors: {
        "length": nf_desc,
        "name": nf_desc,
        "prototype": {
          writable: false,
          enumerable: false,
          configurable: false,
          getter: None,
          setter: None,
          is_accessor: false,
        },
        "resolve": @runtime.builtin_method_desc(),
        "reject": @runtime.builtin_method_desc(),
        "all": @runtime.builtin_method_desc(),
        "race": @runtime.builtin_method_desc(),
        "allSettled": @runtime.builtin_method_desc(),
        "any": @runtime.builtin_method_desc(),
        "withResolvers": @runtime.builtin_method_desc(),
        "try": @runtime.builtin_method_desc(),
      },
      symbol_descriptors: {},
      internal_slots: {},
    },
    prototype: Null,
    callable: Some(
      InterpreterCallableWithContext("Promise", fn(
        interp,
        context,
        _this_val,
        args,
      ) raise {
        // §27.2.1.1: Promise constructor requires 'new'.
        if !context.is_constructing() {
          raise @errors.TypeError(
            message="Promise constructor cannot be invoked without 'new'",
          )
        }
        let executor = if args.length() > 0 { args[0] } else { Undefined }
        let loc = @token.Loc::default()

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

        // §9.1.13/§9.1.14 OrdinaryCreateFromConstructor (§27.2.1.1 step 3):
        // read newTarget.prototype — propagates abrupt completion; if the result
        // is an Object it becomes the promise's [[Prototype]], otherwise
        // %Promise.prototype% is used (Null sentinel → realm fallback at lookup).
        let new_target_proto : Value = if context.new_target()
          is Some(new_target) {
          interp.get_property(new_target, "prototype", loc)
        } else {
          Null
        }

        // Create new promise
        let promise_data = @runtime.new_promise_data()
        if @runtime.is_object_value(new_target_proto) {
          promise_data.prototype = Some(new_target_proto)
        }
        let promise = Value::Promise(promise_data)

        // Create resolving functions
        let (resolve, reject) = @runtime.create_resolving_functions(
          interp, promise_data,
        )

        // Call executor synchronously
        try {
          let _ = interp.call_value(executor, Undefined, [resolve, reject], loc)
        } catch {
          e => {
            // If executor throws, reject the promise
            let error_value = @runtime.js_error_to_value_with_env(
              e,
              Some(interp.global),
            )
            let _ = interp.call_value(reject, Undefined, [error_value], loc)
          }
        }
        promise
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })

  // Promise[Symbol.species] getter returns `this` (used by SpeciesConstructor).
  let species_getter = @runtime.make_method_func(
    name="get [Symbol.species]",
    length=0,
    fn(this_val, _args) { this_val },
  )
  let species_symbol_val = env.get("Symbol") catch { _ => Undefined }
  match species_symbol_val {
    Object(symbol_data) =>
      match symbol_data.bag.properties.get("species") {
        Some(Symbol(species_sym)) =>
          match promise_ctor {
            Object(ctor_data) => {
              ctor_data.bag.symbol_properties[species_sym.id] = Undefined
              ctor_data.bag.symbol_descriptors[species_sym.id] = {
                writable: false,
                enumerable: false,
                configurable: true,
                getter: Some(species_getter),
                setter: None,
                is_accessor: true,
              }
            }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }

  // Set prototype property on constructor
  @runtime.install_realm_pinned_builtin_constructor_assign_prototype_with_proto_constructor(
    env,
    realm_state.promise_prototype,
    "Promise",
    promise_ctor,
    promise_proto,
  )

  // queueMicrotask(callback) - schedules a microtask
  // Part of the Web Platform APIs, used for scheduling microtasks directly
  env.def_builtin(
    "queueMicrotask",
    @runtime.make_interp_method_func(name="queueMicrotask", length=1, fn(
      interp,
      _this,
      args,
    ) raise {
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
  )
}

///|
/// Schedule a timer and return its ID.
/// `period` is 0 for one-shot timers (setTimeout) and the repeat interval
/// in virtual ms for repeating timers (setInterval).
/// `is_interval` must be true for setInterval even when delay=0.
fn Interpreter::schedule_timer(
  self : Interpreter,
  callback : Value,
  extra_args : Array[Value],
  delay : Int,
  period : Int,
  is_interval : Bool,
) -> Int {
  let id = self.host.timer_id_counter.val
  self.host.timer_id_counter.val = id + 1
  // Purge any stale cancellation for this ID before enqueuing.
  // clearTimeout/clearInterval called with IDs not yet in the queue
  // would otherwise cancel the first timer to inherit this ID.
  self.host.cancelled_timer_ids.remove(id)
  let order = self.host.timer_insertion_counter.val
  self.host.timer_insertion_counter.val = order + 1
  self.host.timer_queue.push({
    id,
    callback,
    args: extra_args,
    delay,
    period,
    is_interval,
    insertion_order: order,
  })
  id
}

///|
/// Cancel a pending setTimeout or setInterval by ID.
/// Uses lazy deletion: the ID is recorded here; run_timers skips it on pop.
fn Interpreter::cancel_timer(self : Interpreter, id : Int) -> Unit {
  self.host.cancelled_timer_ids[id] = true
}

///|
/// Setup timer builtins: setTimeout, clearTimeout, setInterval, clearInterval
/// These implement the WHATWG Timer APIs
/// Reference: https://html.spec.whatwg.org/multipage/timers-and-user-prompts.html#timers
pub fn setup_timers(env : Environment) -> Unit {
  // setTimeout(callback, delay, ...args) -> timerId
  env.def_builtin(
    "setTimeout",
    @runtime.make_interp_method_func(name="setTimeout", length=1, fn(
      interp,
      _this,
      args,
    ) raise {
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
          Value::Number(n) => {
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
      let id = interp.schedule_timer(callback, extra_args, delay, 0, false)
      Value::Number(id.to_double())
    }),
  )

  // clearTimeout(id)
  env.def_builtin(
    "clearTimeout",
    @runtime.make_interp_method_func(name="clearTimeout", length=1, fn(
      interp,
      _this,
      args,
    ) {
      let id = if args.length() > 0 {
        match args[0] {
          Value::Number(n) => n.to_int()
          _ => return Undefined
        }
      } else {
        return Undefined
      }
      interp.cancel_timer(id)
      Undefined
    }),
  )

  // setInterval(callback, delay, ...args) -> timerId
  env.def_builtin(
    "setInterval",
    @runtime.make_interp_method_func(name="setInterval", length=1, fn(
      interp,
      _this,
      args,
    ) raise {
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
          Value::Number(n) => {
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
      let id = interp.schedule_timer(callback, extra_args, delay, delay, true)
      Value::Number(id.to_double())
    }),
  )

  // clearInterval(id) - same semantics as clearTimeout
  env.def_builtin(
    "clearInterval",
    @runtime.make_interp_method_func(name="clearInterval", length=1, fn(
      interp,
      _this,
      args,
    ) {
      let id = if args.length() > 0 {
        match args[0] {
          Value::Number(n) => n.to_int()
          _ => return Undefined
        }
      } else {
        return Undefined
      }
      interp.cancel_timer(id)
      Undefined
    }),
  )
}

///|
/// Helper to create an AggregateError value
fn make_aggregate_error(
  interp : Interpreter,
  message : String,
  errors : Array[Value],
) -> Value raise Error {
  let loc = @token.Loc::default()
  let errors_value = @runtime.make_array(errors)
  let aggregate_ctor = interp.global.get("AggregateError") catch {
    _ => Undefined
  }
  match aggregate_ctor {
    Object(data) =>
      match data.callable {
        Some(_) =>
          return interp.construct_value(
            aggregate_ctor,
            [errors_value, Value::String_(message)],
            loc,
          )
        None => ()
      }
    _ => ()
  }
  let props : Map[String, Value] = {}
  props["name"] = Value::String_("AggregateError")
  props["message"] = Value::String_(message)
  props["errors"] = errors_value
  Value::Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
      internal_slots: {},
    },
    prototype: Null,
    callable: None,
    class_name: "AggregateError",
    extensible: true,
    arraybuffer_state: None,
  })
}
