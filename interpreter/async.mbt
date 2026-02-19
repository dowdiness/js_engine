///|
/// Create an async function value. When called, it:
/// 1. Creates a Promise
/// 2. Internally creates a generator from the body (await → yield)
/// 3. Auto-steps the generator, resolving/rejecting the Promise
/// 4. Returns the Promise
fn Interpreter::make_async_function(
  self : Interpreter,
  name : String?,
  params : Array[String],
  rest_param : String?,
  body : Array[@ast.Stmt],
  closure : Environment,
) -> Value {
  let display_name = match name {
    Some(n) => n
    None => "anonymous"
  }
  let async_proto = get_function_prototype(self)
  Object({
    properties: {},
    symbol_properties: {},
    prototype: async_proto,
    callable: Some(
      InterpreterCallable(
        display_name,
        fn(ip : Interpreter, this_val : Value, args : Array[Value]) -> Value raise Error {
          run_async_body(
            ip, this_val, args, name, params, None, rest_param, body, closure,
          )
        },
      ),
    ),
    class_name: "AsyncFunction",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
fn Interpreter::make_async_function_ext(
  self : Interpreter,
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  closure : Environment,
) -> Value {
  let display_name = match name {
    Some(n) => n
    None => "anonymous"
  }
  let async_proto = get_function_prototype(self)
  Object({
    properties: {},
    symbol_properties: {},
    prototype: async_proto,
    callable: Some(
      InterpreterCallable(
        display_name,
        fn(ip : Interpreter, this_val : Value, args : Array[Value]) -> Value raise Error {
          run_async_body(
            ip,
            this_val,
            args,
            name,
            [],
            Some(params),
            rest_param,
            body,
            closure,
          )
        },
      ),
    ),
    class_name: "AsyncFunction",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Execute an async function body by creating a generator internally
/// and auto-stepping it with Promise resolution.
fn run_async_body(
  ip : Interpreter,
  this_val : Value,
  args : Array[Value],
  name : String?,
  params : Array[String],
  params_ext : Array[@ast.Param]?,
  rest_param : String?,
  body : Array[@ast.Stmt],
  closure : Environment,
) -> Value {
  // Create a Promise for the result
  let promise_data : PromiseData = {
    state: Pending,
    result: Undefined,
    fulfill_reactions: [],
    reject_reactions: [],
    is_handled: false,
    properties: {},
    symbol_properties: {},
    descriptors: {},
    symbol_descriptors: {},
  }
  let promise_val = Promise(promise_data)
  let (resolve_fn, reject_fn) = create_resolving_functions(ip, promise_data)
  // Create a generator object from the async function body
  let gen_proto = get_generator_prototype(ip)
  let func_proto = Object({
    properties: {},
    symbol_properties: {},
    prototype: gen_proto,
    callable: None,
    class_name: "Object",
    descriptors: {},
    symbol_descriptors: {},
    extensible: true,
  })
  let gen_val = create_generator_instance(
    ip,
    this_val,
    args,
    name,
    params,
    params_ext,
    rest_param,
    body,
    closure,
    func_proto,
  )
  // Auto-step the generator
  async_step(ip, gen_val, Undefined, resolve_fn, reject_fn, false)
  promise_val
}

///|
/// Auto-step an async generator: call next/throw, handle result.
fn async_step(
  ip : Interpreter,
  gen_val : Value,
  value : Value,
  resolve_fn : Value,
  reject_fn : Value,
  is_throw : Bool,
) -> Unit {
  let loc = @token.Loc::default()
  // Call gen.next(value) or gen.throw(value)
  let result : Value = try {
    if is_throw {
      let throw_method = ip.get_property(gen_val, "throw", loc)
      ip.call_value(throw_method, gen_val, [value], loc)
    } else {
      let next_method = ip.get_property(gen_val, "next", loc)
      ip.call_value(next_method, gen_val, [value], loc)
    }
  } catch {
    JsException(e) => {
      // Generator threw — reject the promise
      let _ = ip.call_value(reject_fn, Undefined, [e], loc) catch {
        _ => Undefined
      }
      return
    }
    e => {
      let err_val = js_error_to_value_with_env(e, Some(ip.global))
      let _ = ip.call_value(reject_fn, Undefined, [err_val], loc) catch {
        _ => Undefined
      }
      return
    }
  }
  // Extract { value, done } from result
  let result_value = try {
    ip.get_property(result, "value", loc)
  } catch {
    _ => Undefined
  }
  let result_done = try {
    ip.get_property(result, "done", loc)
  } catch {
    _ => Bool(false)
  }
  let is_done = match result_done {
    Bool(b) => b
    _ => false
  }
  if is_done {
    // Generator completed — resolve the promise
    // Do NOT call run_microtasks() here; the outer event loop
    // (run_microtasks in js_engine.mbt) uses index-based draining
    // and will process any newly enqueued reaction microtasks.
    let _ = try {
      ip.call_value(resolve_fn, Undefined, [result_value], loc)
    } catch {
      _ => Undefined
    }
  } else {
    // Generator yielded (await) — schedule continuation via microtask.
    // Do NOT call run_microtasks() here to avoid recursive re-entry;
    // the outer event loop drains the queue with its while loop.
    let awaited = result_value
    let gen = gen_val
    let res_fn = resolve_fn
    let rej_fn = reject_fn
    let on_fulfill = make_interpreter_callable_with_length(
      "",
      1,
      fn(i : Interpreter, _this : Value, args : Array[Value]) -> Value raise Error {
        let v = if args.length() > 0 { args[0] } else { Undefined }
        async_step(i, gen, v, res_fn, rej_fn, false)
        Undefined
      },
    )
    let on_reject = make_interpreter_callable_with_length(
      "",
      1,
      fn(i : Interpreter, _this : Value, args : Array[Value]) -> Value raise Error {
        let v = if args.length() > 0 { args[0] } else { Undefined }
        async_step(i, gen, v, res_fn, rej_fn, true)
        Undefined
      },
    )
    // Wrap the awaited value in Promise.resolve() then schedule .then()
    // This ensures all await continuations go through the microtask queue,
    // matching spec behavior and preventing stack overflow.
    let resolved_promise = try {
      let promise_ctor = ip.get_property(
        ip.global.get("Promise"),
        "resolve",
        loc,
      )
      ip.call_value(
        promise_ctor,
        ip.global.get("Promise"),
        [awaited],
        loc,
      )
    } catch {
      _ => {
        // Fallback: directly schedule on microtask queue
        ip.enqueue_microtask(on_fulfill, [awaited])
        return
      }
    }
    let then_method = try {
      ip.get_property(resolved_promise, "then", loc)
    } catch {
      _ => Undefined
    }
    let _ = try {
      ip.call_value(
        then_method,
        resolved_promise,
        [on_fulfill, on_reject],
        loc,
      )
    } catch {
      _ => Undefined
    }
  }
}

///|
///|
/// Get the function prototype for async function objects.
/// Note: Uses the standard [[FunctionPrototype]] — there is no separate
/// async-specific prototype in this engine.
fn get_function_prototype(interp : Interpreter) -> Value {
  match interp.global.bindings.get("[[FunctionPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
}
