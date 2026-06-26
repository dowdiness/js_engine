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
  strict : Bool,
  closure : Environment,
  has_name_binding? : Bool = false,
  source_text? : String? = None,
) -> Value {
  let func_name = match name {
    Some(n) => n
    None => ""
  }
  let internal_slots : Map[InternalSlotKey, Value] = {}
  match source_text {
    Some(text) => internal_slots[SourceText] = String_(text)
    None => ()
  }
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let async_proto = get_function_prototype(self)
  let effective_closure : Environment = if has_name_binding {
    match name {
      Some(n) => {
        let ne = Environment::new(parent=Some(closure))
        ne.bindings[n] = {
          value: Undefined,
          kind: FunctionNameBinding,
          initialized: true,
          annex_b_hoisted: false,
          is_parameter: false,
        }
        ne
      }
      None => closure
    }
  } else {
    closure
  }
  let async_func = stamp_function_realm(
    Object({
      bag: {
        properties: {
          "name": String_(func_name),
          "length": Number(params.length().to_double()),
        },
        symbol_properties: {},
        descriptors: { "name": nf_desc, "length": nf_desc },
        symbol_descriptors: {},
        internal_slots,
      },
      prototype: async_proto,
      callable: Some(
        InterpreterCallable(func_name, fn(
          ip : Interpreter,
          this_val : Value,
          args : Array[Value],
        ) -> Value {
          run_async_body(
            ip,
            this_val,
            args,
            name,
            params,
            None,
            rest_param,
            body,
            strict,
            effective_closure,
          )
        }),
      ),
      class_name: "AsyncFunction",
      extensible: true,
      arraybuffer_state: None,
    }),
    realm_state=Some(self.realm_state),
  )
  if has_name_binding {
    match name {
      Some(n) =>
        match effective_closure.bindings.get(n) {
          Some(b) => b.value = async_func
          None => ()
        }
      None => ()
    }
  }
  async_func
}

///|
fn Interpreter::make_async_function_ext(
  self : Interpreter,
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  strict : Bool,
  closure : Environment,
  has_name_binding? : Bool = false,
  source_text? : String? = None,
) -> Value {
  let func_name = match name {
    Some(n) => n
    None => ""
  }
  let internal_slots : Map[InternalSlotKey, Value] = {}
  match source_text {
    Some(text) => internal_slots[SourceText] = String_(text)
    None => ()
  }
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let async_proto = get_function_prototype(self)
  let func_length = expected_argument_count_ext(params)
  let effective_closure : Environment = if has_name_binding {
    match name {
      Some(n) => {
        let ne = Environment::new(parent=Some(closure))
        ne.bindings[n] = {
          value: Undefined,
          kind: FunctionNameBinding,
          initialized: true,
          annex_b_hoisted: false,
          is_parameter: false,
        }
        ne
      }
      None => closure
    }
  } else {
    closure
  }
  let async_func = stamp_function_realm(
    Object({
      bag: {
        properties: {
          "name": String_(func_name),
          "length": Number(func_length.to_double()),
        },
        symbol_properties: {},
        descriptors: { "name": nf_desc, "length": nf_desc },
        symbol_descriptors: {},
        internal_slots,
      },
      prototype: async_proto,
      callable: Some(
        InterpreterCallable(func_name, fn(
          ip : Interpreter,
          this_val : Value,
          args : Array[Value],
        ) -> Value {
          run_async_body(
            ip,
            this_val,
            args,
            name,
            [],
            Some(params),
            rest_param,
            body,
            strict,
            effective_closure,
          )
        }),
      ),
      class_name: "AsyncFunction",
      extensible: true,
      arraybuffer_state: None,
    }),
    realm_state=Some(self.realm_state),
  )
  if has_name_binding {
    match name {
      Some(n) =>
        match effective_closure.bindings.get(n) {
          Some(b) => b.value = async_func
          None => ()
        }
      None => ()
    }
  }
  async_func
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
  strict : Bool,
  closure : Environment,
) -> Value {
  let promise_data = new_promise_data()
  let promise_val = Promise(promise_data)
  let (resolve_fn, reject_fn) = create_resolving_functions(ip, promise_data)
  // Create a generator object from the async function body.
  // The prototype here is unused for step driving — async_step calls
  // generator_resume() directly, bypassing any prototype dispatch.
  let gen_proto : Value = match
    ip.global.bindings.get("[[GeneratorPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let func_proto = Object({
    bag: PropertyBag(),
    prototype: gen_proto,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  let gen_val = create_generator_instance(
    ip, this_val, args, name, params, params_ext, rest_param, body, strict, closure,
    func_proto,
  ) catch {
    JsException(e) => {
      // Parameter binding error rejects the promise
      let _ = ip.call_value(reject_fn, Undefined, [e], @token.Loc::default()) catch {
        _ => Undefined
      }
      return promise_val
    }
    e => {
      let err_val = String_(e.to_string())
      let _ = ip.call_value(
        reject_fn,
        Undefined,
        [err_val],
        @token.Loc::default(),
      ) catch {
        _ => Undefined
      }
      return promise_val
    }
  }
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
  // Drive the internal generator directly — NOT through prototype dispatch.
  // The gen_val here is an implementation artifact (not user-accessible),
  // so using ip.get_property would allow user monkey-patching of
  // %GeneratorPrototype%.next to hijack async function resolution.
  let result : Value = try {
    if is_throw {
      generator_resume(ip, gen_val, Throw(value))
    } else {
      generator_resume(ip, gen_val, Next(value))
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
  let result_value = ip.get_property(result, "value", loc) catch {
    _ => Undefined
  }
  let result_done = ip.get_property(result, "done", loc) catch {
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
    let _ = ip.call_value(resolve_fn, Undefined, [result_value], loc) catch {
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
    let on_fulfill = make_interp_method_func(
      name="",
      length=1,
      realm_state=Some(ip.realm_state),
      fn(i : Interpreter, _this : Value, args : Array[Value]) -> Value {
        let v = if args.length() > 0 { args[0] } else { Undefined }
        async_step(i, gen, v, res_fn, rej_fn, false)
        Undefined
      },
    )
    let on_reject = make_interp_method_func(
      name="",
      length=1,
      realm_state=Some(ip.realm_state),
      fn(i : Interpreter, _this : Value, args : Array[Value]) -> Value {
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
      ip.call_value(promise_ctor, ip.global.get("Promise"), [awaited], loc)
    } catch {
      _ => {
        // Fallback: Promise.resolve() unavailable; inspect awaited directly
        match awaited {
          Promise(pd) =>
            match pd.state {
              Fulfilled => ip.enqueue_microtask(on_fulfill, [pd.result])
              Rejected => ip.enqueue_microtask(on_reject, [pd.result])
              Pending => {
                let noop = make_interp_method_func(
                  name="",
                  length=0,
                  realm_state=Some(ip.realm_state),
                  fn(_i : Interpreter, _t : Value, _a : Array[Value]) -> Value {
                    Undefined
                  },
                )
                pd.fulfill_reactions.push({
                  handler: Some(on_fulfill),
                  resolve: noop,
                  reject: noop,
                  reaction_type: Fulfill,
                })
                pd.reject_reactions.push({
                  handler: Some(on_reject),
                  resolve: noop,
                  reject: noop,
                  reaction_type: Reject,
                })
              }
            }
          _ => ip.enqueue_microtask(on_fulfill, [awaited])
        }
        return
      }
    }
    // Fast path: if resolved_promise is a native Promise, bypass the JS-level
    // .then property and attach reactions directly via the internal record.
    // This avoids issues with overridden .then and matches spec PerformPromiseThen.
    match resolved_promise {
      Promise(pd) =>
        match pd.state {
          Fulfilled => ip.enqueue_microtask(on_fulfill, [pd.result])
          Rejected => ip.enqueue_microtask(on_reject, [pd.result])
          Pending => {
            let noop = make_interp_method_func(
              name="",
              length=0,
              realm_state=Some(ip.realm_state),
              fn(_i : Interpreter, _t : Value, _a : Array[Value]) -> Value {
                Undefined
              },
            )
            pd.fulfill_reactions.push({
              handler: Some(on_fulfill),
              resolve: noop,
              reject: noop,
              reaction_type: Fulfill,
            })
            pd.reject_reactions.push({
              handler: Some(on_reject),
              resolve: noop,
              reject: noop,
              reaction_type: Reject,
            })
          }
        }
      _ => {
        // Non-native promise: use JS-level .then() property
        let then_method = ip.get_property(resolved_promise, "then", loc) catch {
          e => {
            // get_property threw — propagate to on_reject
            let err_val = js_error_to_value_with_env(e, Some(ip.global))
            ip.enqueue_microtask(on_reject, [err_val])
            return
          }
        }
        // Check if then_method is callable before invoking
        let is_callable = match then_method {
          Object(od) => od.callable is Some(_)
          _ => false
        }
        if is_callable {
          try {
            let _ = ip.call_value(
              then_method,
              resolved_promise,
              [on_fulfill, on_reject],
              loc,
            )
          } catch {
            e => {
              // .then() threw — propagate to on_reject
              let err_val = js_error_to_value_with_env(e, Some(ip.global))
              ip.enqueue_microtask(on_reject, [err_val])
            }
          }
        } else {
          // Non-callable .then — treat as non-thenable, fulfill directly
          ip.enqueue_microtask(on_fulfill, [resolved_promise])
        }
      }
    }
  }
}

///|
/// Create an async generator function value (simple params).
fn Interpreter::make_async_generator_function(
  self : Interpreter,
  name : String?,
  params : Array[String],
  rest_param : String?,
  body : Array[@ast.Stmt],
  strict : Bool,
  closure : Environment,
  source_text? : String? = None,
) -> Value {
  make_async_gen_function_inner(
    self,
    name,
    params,
    None,
    rest_param,
    body,
    strict,
    closure,
    source_text,
  )
}

///|
/// Create an async generator function value (extended params).
fn Interpreter::make_async_generator_function_ext(
  self : Interpreter,
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
  strict : Bool,
  closure : Environment,
  source_text? : String? = None,
) -> Value {
  make_async_gen_function_inner(
    self,
    name,
    [],
    Some(params),
    rest_param,
    body,
    strict,
    closure,
    source_text,
  )
}

///|
/// Shared factory for async generator functions.
/// Builds the function object with async generator prototype and class name.
fn make_async_gen_function_inner(
  interp : Interpreter,
  name : String?,
  params : Array[String],
  params_ext : Array[@ast.Param]?,
  rest_param : String?,
  body : Array[@ast.Stmt],
  strict : Bool,
  closure : Environment,
  source_text : String?,
) -> Value {
  // Use the shared %AsyncGeneratorPrototype% singleton (set up during interpreter init).
  let async_gen_proto : Value = match
    interp.global.bindings.get("[[AsyncGeneratorPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let func_prototype = Object({
    bag: PropertyBag(),
    prototype: async_gen_proto,
    callable: None,
    class_name: "AsyncGenerator",
    extensible: true,
    arraybuffer_state: None,
  })
  // Use the shared %AsyncGeneratorFunction%.prototype (not the sync generator's prototype).
  let gen_func_proto : Value = match
    interp.global.bindings.get("[[AsyncGeneratorFunctionPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let func_name = match name {
    Some(n) => n
    None => ""
  }
  let func_length = match params_ext {
    Some(pext) => expected_argument_count_ext(pext)
    None => params.length()
  }
  let fn_props : Map[String, Value] = {}
  fn_props["prototype"] = func_prototype
  fn_props["name"] = String_(func_name)
  fn_props["length"] = Number(func_length.to_double())
  let internal_slots : Map[InternalSlotKey, Value] = {}
  match source_text {
    Some(text) => internal_slots[SourceText] = String_(text)
    None => ()
  }
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  stamp_function_realm(
    Object({
      bag: {
        properties: fn_props,
        symbol_properties: {},
        descriptors: {
          "name": nf_desc,
          "length": nf_desc,
          "prototype": {
            writable: true,
            enumerable: false,
            configurable: false,
            getter: None,
            setter: None,
            is_accessor: false,
          },
        },
        symbol_descriptors: {},
        internal_slots,
      },
      prototype: gen_func_proto,
      callable: Some(
        InterpreterCallable(func_name, fn(ip, this_val, args) raise {
          create_generator_instance(
            ip, this_val, args, name, params, params_ext, rest_param, body, strict,
            closure, func_prototype,
          )
        }),
      ),
      class_name: "AsyncGeneratorFunction",
      extensible: true,
      arraybuffer_state: None,
    }),
    realm_state=Some(interp.realm_state),
  )
}

///|
/// Wrap generator_resume in a Promise for async generator protocol.
/// Returns a resolved Promise with {value, done} on success,
/// or a rejected Promise with the error on failure.
fn async_generator_resume(
  ip : Interpreter,
  this_val : Value,
  resume_kind : ResumeKind,
) -> Value {
  let result = generator_resume(ip, this_val, resume_kind) catch {
    JsException(e) => {
      let pd = new_promise_data()
      pd.state = Rejected
      pd.result = e
      return Promise(pd)
    }
    e => {
      let pd = new_promise_data()
      pd.state = Rejected
      pd.result = js_error_to_value_with_env(e, Some(ip.global))
      return Promise(pd)
    }
  }
  let pd = new_promise_data()
  pd.state = Fulfilled
  pd.result = result
  Promise(pd)
}

///|
/// Get the function prototype for async function objects.
fn get_function_prototype(interp : Interpreter) -> Value {
  match interp.global.bindings.get("[[AsyncFunctionPrototype]]") {
    Some(binding) => binding.value
    None =>
      match interp.global.bindings.get("[[FunctionPrototype]]") {
        Some(binding) => binding.value
        None => Null
      }
  }
}

///|
/// Set up the AsyncFunction constructor and prototype chain.
/// Mirrors setup_generator_function_constructor in generator.mbt.
///
/// Prototype chain (per ES spec):
///   AsyncFunction.__proto__ === Function
///   AsyncFunction.prototype.__proto__ === Function.prototype
///   AsyncFunction.prototype[@@toStringTag] === "AsyncFunction"
///   AsyncFunction.prototype.constructor === AsyncFunction
pub fn setup_async_function_constructor(
  env : Environment,
  well_known_symbols~ : WellKnownSymbols,
) -> Unit {
  // %AsyncFunction.prototype% inherits from Function.prototype
  let func_proto : Value = match env.bindings.get("[[FunctionPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let af_sym_props : Map[Int, Value] = {}
  let af_sym_descs : Map[Int, PropDescriptor] = {}
  let tostringtag_sym = well_known_symbols.to_string_tag
  af_sym_props[tostringtag_sym.id] = String_("AsyncFunction")
  af_sym_descs[tostringtag_sym.id] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let async_func_proto : Value = Object({
    bag: {
      properties: {},
      symbol_properties: af_sym_props,
      descriptors: {},
      symbol_descriptors: af_sym_descs,
      internal_slots: {},
    },
    prototype: func_proto,
    callable: None,
    class_name: "AsyncFunction",
    extensible: true,
    arraybuffer_state: None,
  })
  // AsyncFunction constructor: AsyncFunction(p1, p2, ..., body)
  let async_func_ctor : Value = make_interp_method_func(
    name="AsyncFunction",
    length=1,
    realm_state=env.realm_state,
    fn(interp, _this, args) raise {
      // §20.2.1.1: coerce all parameter args before the body arg
      let param_parts : Array[String] = []
      for i in 0..<(args.length() - 1) {
        match args[i] {
          String_(s) => param_parts.push(s)
          _ => param_parts.push(to_js_string(args[i], interp=Some(interp)))
        }
      }
      let body_str = match args {
        [] => ""
        [.., last] =>
          match last {
            String_(s) => s
            _ => to_js_string(last, interp=Some(interp))
          }
      }
      let params_str = param_parts.join(",")
      let source = "async function anonymous(" +
        params_str +
        "\n) {\n" +
        body_str +
        "\n}"
      let prog = @parser.parse(source)
      match prog.stmts {
        [AsyncFuncDecl(_, params, body, _, source_text), ..] => {
          let body_strict = @static_semantics.has_use_strict(body)
          validate_function_constructor_params(true, params, None, body)
          interp.validate_block_early_errors(body, body_strict)
          return interp.make_async_function(
            Some("anonymous"),
            params,
            None,
            body,
            body_strict,
            interp.global,
            source_text~,
          )
        }
        [AsyncFuncDeclExt(_, params, rest_param, body, _, source_text), ..] => {
          let body_strict = @static_semantics.has_use_strict(body)
          validate_function_constructor_params_ext(params, rest_param, body)
          interp.validate_block_early_errors(body, body_strict)
          return interp.make_async_function_ext(
            Some("anonymous"),
            params,
            rest_param,
            body,
            body_strict,
            interp.global,
            source_text~,
          )
        }
        _ => ()
      }
      raise @errors.SyntaxError(
        message="Invalid AsyncFunction constructor source",
      )
    },
  )
  // AsyncFunction.prototype.constructor = AsyncFunction
  match async_func_proto {
    Object(data) => {
      data.bag.properties["constructor"] = async_func_ctor
      data.bag.descriptors["constructor"] = {
        writable: false,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
        is_accessor: false,
      }
    }
    _ => ()
  }
  // AsyncFunction.prototype property on the constructor
  match async_func_ctor {
    Object(data) => {
      data.bag.properties["prototype"] = async_func_proto
      data.bag.descriptors["prototype"] = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
        is_accessor: false,
      }
    }
    _ => ()
  }
  // Note: AsyncFunction is NOT a global property per spec (section 19).
  // It is only reachable via (async function(){}).constructor.
  // We store it as an internal binding so async functions get the right prototype.
  env.def_builtin("[[AsyncFunctionPrototype]]", async_func_proto)
}

///|
/// Set up the AsyncGeneratorFunction constructor and prototype chain.
/// Mirrors setup_generator_function_constructor in generator.mbt.
///
/// Prototype chain (per ES spec §27.4):
///   %AsyncGeneratorFunction%.__proto__ === Function
///   %AsyncGeneratorFunction%.prototype.__proto__ === Function.prototype
///   %AsyncGeneratorFunction%.prototype[@@toStringTag] === "AsyncGeneratorFunction"
///   %AsyncGeneratorFunction%.prototype.constructor === %AsyncGeneratorFunction%
///   %AsyncGeneratorFunction%.prototype.prototype === %AsyncGeneratorPrototype%
///   %AsyncIteratorPrototype%.__proto__ === Object.prototype
///   %AsyncIteratorPrototype%[@@asyncIterator] returns this
///   %AsyncGeneratorPrototype%.__proto__ === %AsyncIteratorPrototype%
///   %AsyncGeneratorPrototype%.constructor === %AsyncGeneratorFunction%.prototype
///   %AsyncGeneratorPrototype%[@@toStringTag] === "AsyncGenerator"
pub fn setup_async_generator_function_constructor(
  env : Environment,
  well_known_symbols~ : WellKnownSymbols,
) -> Unit {
  let async_iter_sym = well_known_symbols.async_iterator
  let to_string_tag_sym = well_known_symbols.to_string_tag
  let object_prototype = env.get("[[ObjectPrototype]]") catch { _ => Null }
  let func_proto : Value = match env.bindings.get("[[FunctionPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let non_enum : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let non_enum_non_writable : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let frozen : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }

  // Build %AsyncGeneratorFunction%.prototype first so it can be used as the
  // constructor value in %AsyncGeneratorPrototype%'s property map, ensuring
  // insertion order follows spec §27.4.3: constructor, prototype (string keys).
  let agf_sym_props : Map[Int, Value] = {}
  let agf_sym_descs : Map[Int, PropDescriptor] = {}
  agf_sym_props[to_string_tag_sym.id] = String_("AsyncGeneratorFunction")
  agf_sym_descs[to_string_tag_sym.id] = non_enum_non_writable
  let agf_proto : Value = Object({
    bag: {
      properties: {},
      symbol_properties: agf_sym_props,
      descriptors: {},
      symbol_descriptors: agf_sym_descs,
      internal_slots: {},
    },
    prototype: func_proto,
    callable: None,
    class_name: "AsyncGeneratorFunction",
    extensible: true,
    arraybuffer_state: None,
  })

  // Build %AsyncIteratorPrototype% (§27.1.2) — owns Symbol.asyncIterator only.
  // %AsyncGeneratorPrototype% inherits from it; own-key checks on the latter
  // must not see Symbol.asyncIterator.
  let aip_sym_props : Map[Int, Value] = {}
  let aip_sym_descs : Map[Int, PropDescriptor] = {}
  aip_sym_props[async_iter_sym.id] = make_method_func(
    name="[Symbol.asyncIterator]",
    length=0,
    realm_state=env.realm_state,
    fn(this_val, _args) { this_val },
  )
  aip_sym_descs[async_iter_sym.id] = non_enum
  let async_iter_proto : Value = Object({
    bag: {
      properties: {},
      symbol_properties: aip_sym_props,
      descriptors: {},
      symbol_descriptors: aip_sym_descs,
      internal_slots: {},
    },
    prototype: object_prototype,
    callable: None,
    class_name: "AsyncIterator",
    extensible: true,
    arraybuffer_state: None,
  })

  // Build %AsyncGeneratorPrototype% — shared singleton for all async gen instances.
  // [[Prototype]] = %AsyncIteratorPrototype% (not Object.prototype).
  // Own string keys follow spec §27.6: constructor, next, return, throw.
  // Own symbol keys: Symbol.toStringTag only — Symbol.asyncIterator is inherited.
  let agp_props : Map[String, Value] = {}
  let agp_sym_props : Map[Int, Value] = {}
  let agp_descs : Map[String, PropDescriptor] = {}
  let agp_sym_descs : Map[Int, PropDescriptor] = {}

  agp_props["constructor"] = agf_proto
  agp_descs["constructor"] = non_enum_non_writable
  agp_props["next"] = make_interp_method_func(
    name="next",
    length=1,
    realm_state=env.realm_state,
    fn(ip, this_val, args) {
      let arg = match args {
        [first, ..] => first
        [] => Undefined
      }
      async_generator_resume(ip, this_val, Next(arg))
    },
  )
  agp_descs["next"] = non_enum
  agp_props["return"] = make_interp_method_func(
    name="return",
    length=1,
    realm_state=env.realm_state,
    fn(ip, this_val, args) {
      let arg = match args {
        [first, ..] => first
        [] => Undefined
      }
      async_generator_resume(ip, this_val, Return(arg))
    },
  )
  agp_descs["return"] = non_enum
  agp_props["throw"] = make_interp_method_func(
    name="throw",
    length=1,
    realm_state=env.realm_state,
    fn(ip, this_val, args) {
      let arg = match args {
        [first, ..] => first
        [] => Undefined
      }
      async_generator_resume(ip, this_val, Throw(arg))
    },
  )
  agp_descs["throw"] = non_enum
  agp_sym_props[to_string_tag_sym.id] = String_("AsyncGenerator")
  agp_sym_descs[to_string_tag_sym.id] = non_enum_non_writable
  let async_gen_proto : Value = Object({
    bag: {
      properties: agp_props,
      symbol_properties: agp_sym_props,
      descriptors: agp_descs,
      symbol_descriptors: agp_sym_descs,
      internal_slots: {},
    },
    prototype: async_iter_proto,
    callable: None,
    class_name: "AsyncGenerator",
    extensible: true,
    arraybuffer_state: None,
  })

  // Build AsyncGeneratorFunction constructor
  let async_gen_func_ctor : Value = make_interp_method_func(
    name="AsyncGeneratorFunction",
    length=1,
    realm_state=env.realm_state,
    fn(interp, _this, args) raise {
      // §20.2.1.1: coerce all parameter args before the body arg
      let param_parts : Array[String] = []
      for i in 0..<(args.length() - 1) {
        match args[i] {
          String_(s) => param_parts.push(s)
          _ => param_parts.push(to_js_string(args[i], interp=Some(interp)))
        }
      }
      let body_str = match args {
        [] => ""
        [.., last] =>
          match last {
            String_(s) => s
            _ => to_js_string(last, interp=Some(interp))
          }
      }
      let params_str = param_parts.join(",")
      let source = "async function* anonymous(" +
        params_str +
        "\n) {\n" +
        body_str +
        "\n}"
      let prog = @parser.parse(source)
      match prog.stmts {
        [AsyncGeneratorDecl(_, params, body, _, source_text), ..] => {
          let body_strict = @static_semantics.has_use_strict(body)
          validate_function_constructor_params(true, params, None, body)
          interp.validate_block_early_errors(body, body_strict)
          return interp.make_async_generator_function(
            Some("anonymous"),
            params,
            None,
            body,
            body_strict,
            interp.global,
            source_text~,
          )
        }
        [AsyncGeneratorDeclExt(_, params, rest_param, body, _, source_text), ..] => {
          let body_strict = @static_semantics.has_use_strict(body)
          validate_function_constructor_params_ext(params, rest_param, body)
          interp.validate_block_early_errors(body, body_strict)
          return interp.make_async_generator_function_ext(
            Some("anonymous"),
            params,
            rest_param,
            body,
            body_strict,
            interp.global,
            source_text~,
          )
        }
        _ => ()
      }
      raise @errors.SyntaxError(
        message="Invalid AsyncGeneratorFunction constructor source",
      )
    },
  )

  // Wire up cross-references between the three objects.
  // %AsyncGeneratorPrototype%.constructor was set at construction time (agf_proto).
  // §27.4.3: agf_proto string keys must be constructor (§27.4.3.1) then prototype (§27.4.3.2).
  match agf_proto {
    Object(data) => {
      data.bag.properties["constructor"] = async_gen_func_ctor
      data.bag.descriptors["constructor"] = non_enum_non_writable
      // §27.4.3.2: prototype property on %AsyncGeneratorFunction%.prototype is configurable
      data.bag.properties["prototype"] = async_gen_proto
      data.bag.descriptors["prototype"] = non_enum_non_writable
    }
    _ => ()
  }
  // §27.4.1: %AsyncGeneratorFunction%.[[Prototype]] = Function (not Function.prototype)
  let function_ctor = env.get("Function") catch { _ => Null }
  match async_gen_func_ctor {
    Object(data) => {
      data.bag.properties["prototype"] = agf_proto
      data.bag.descriptors["prototype"] = frozen
      data.prototype = function_ctor
    }
    _ => ()
  }

  env.def_builtin("[[AsyncIteratorPrototype]]", async_iter_proto)
  env.def_builtin("[[AsyncGeneratorPrototype]]", async_gen_proto)
  env.def_builtin("[[AsyncGeneratorFunctionPrototype]]", agf_proto)
}
