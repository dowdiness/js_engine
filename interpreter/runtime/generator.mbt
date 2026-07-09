///|
/// Generator state machine
pub(all) enum GenState {
  SuspendedStart // Created but body not yet started
  Executing // Currently running (re-entrancy guard)
  SuspendedYield // Suspended at a yield point
  Completed // Body finished or abruptly completed
}

///|
/// How the generator was resumed
pub(all) enum ResumeKind {
  Next(Value) // .next(v)
  Throw(Value) // .throw(e)
  Return(Value) // .return(v)
}

///|
/// Resume action for eval_yield to inspect when replaying
pub(all) enum ResumeAction {
  NextAction // deliver yield_value normally
  ThrowAction(Value) // inject throw at yield point
  ReturnAction(Value) // inject return at yield point
}

///|
/// Generator object stored as internal data on an ObjectData
pub(all) struct GeneratorObject {
  id : Int // generator object ID for cleanup
  mut state : GenState
  // The interpreter, body, params, closure, etc. needed to execute
  body : Array[@ast.Stmt]
  strict : Bool // strict mode flag captured from the defining function
  params : Array[String] // simple params
  params_ext : Array[@ast.Param]? // extended params (with defaults)
  rest_param : String?
  closure : Environment
  is_async : Bool
  name : String?
  interpreter : Interpreter
  args : Array[Value] // arguments passed when generator function was called
  this_val : Value // this value at call time
  // Step engine state
  mut env : Environment? // execution environment (created on first .next())
  mut pc : Int // program counter: index into body
  mut yield_value : Value // value to be returned by yield expression on resume
  // Resume replay state
  mut resuming : Bool // true when replaying a statement to deliver resume value
  mut resume_action : ResumeAction // what to do when eval_yield is hit during replay
  // Try/catch/finally resume tracking
  // -1 = no saved phase, 0 = try body, 1 = catch body, 2 = finally body
  mut try_resume_phase : Int
  mut try_resume_yield_base : Int // yield index at the start of the resumed try/catch/finally phase
  mut try_resume_error : Value // saved error value when resuming in catch
  mut try_resume_result : Signal // saved try/catch result when resuming in finally
  mut try_resume_pending_error : Error? // saved non-catchable error for finally
  // Loop resume tracking — stack of saved loop envs (innermost first, outermost last)
  loop_env_stack : Array[Environment]
  loop_yield_base_stack : Array[Int]
  // For-of resume state
  mut for_of_iterator : Value // last saved iterator object (compat/debug)
  mut for_of_next : Value // last saved next method (compat/debug)
  for_of_iterator_stack : Array[Value]
  for_of_next_stack : Array[Value]
  mut for_of_resume : Bool // true if resuming inside for-of
  // For-await-of: flag to distinguish next-await from body-yield on resume.
  // The for_of_iterator/next stacks above are shared with sync for-of.
  mut for_of_awaiting_next : Bool // true if resuming from an awaited next() call
  // Inner iterators saved when YieldSignal escapes array destructuring inside for-of.
  // On abrupt resume (ReturnAction/ThrowAction), these are closed directly without
  // re-running assign_pattern (which would call iterator.next() again).
  dstr_iterator_stack : Array[Value]
  // yield* delegation state
  mut delegate_iterator : Value // the delegate iterator (or Undefined if not delegating)
  mut delegate_next : Value // the delegate's next method
  mut delegating : Bool // true if currently in yield* delegation
  // Yield index tracking for nested yields (e.g. yield yield 1)
  mut yield_index : Int // counter incremented each time eval_yield is called
  mut resume_at_yield : Int // index of the yield that was suspended
  mut yield_resume_values : Map[Int, Value] // yield_index -> resume value for replay
}

///|
/// Mark generator as completed and remove from global map to free resources
fn complete_generator(gen : GeneratorObject) -> Unit {
  gen.state = Completed
  // Clear references to reduce memory pressure while keeping
  // the object in the map so subsequent .next/.throw/.return calls
  // correctly return {done: true} instead of "incompatible receiver".
  gen.env = None
  gen.delegate_iterator = Undefined
  gen.delegate_next = Undefined
  gen.delegating = false
  gen.for_of_iterator = Undefined
  gen.for_of_next = Undefined
  gen.for_of_iterator_stack.clear()
  gen.for_of_next_stack.clear()
  gen.for_of_resume = false
  gen.for_of_awaiting_next = false
  gen.dstr_iterator_stack.clear()
  gen.loop_env_stack.clear()
  gen.loop_yield_base_stack.clear()
  gen.yield_resume_values.clear()
  // Clear mutable fields to allow GC
  // Note: body/args/closure/this_val are immutable and may be shared
  // across generator instances from the same function, so leave them.
  gen.yield_value = Undefined
  gen.try_resume_yield_base = 0
  gen.try_resume_error = Undefined
  gen.try_resume_result = Normal(Undefined)
  gen.try_resume_pending_error = None
}

///|
/// §20.2.1.1.1 step 17a: Returns true if expr contains a YieldExpression at
/// any level, stopping at nested function boundaries (which have their own
/// generator context and may use yield freely).
fn expr_contains_yield(expr : @ast.Expr) -> Bool {
  match expr {
    YieldExpr(_, _, _) => true
    Binary(_, a, b, _) => expr_contains_yield(a) || expr_contains_yield(b)
    Unary(_, e, _)
    | UpdateExpr(_, e, _, _)
    | Grouping(e, _)
    | SpreadExpr(e, _) => expr_contains_yield(e)
    Assign(_, e, _) => expr_contains_yield(e)
    MemberAssign(obj, _, val, _) =>
      expr_contains_yield(obj) || expr_contains_yield(val)
    ComputedAssign(obj, key, val, _) =>
      expr_contains_yield(obj) ||
      expr_contains_yield(key) ||
      expr_contains_yield(val)
    CompoundAssign(_, a, b, _)
    | Comma(a, b, _)
    | WebCompatCallAssign(a, b, _) =>
      expr_contains_yield(a) || expr_contains_yield(b)
    Member(obj, _, _) | OptionalMember(obj, _, _) | ChainMember(obj, _, _) =>
      expr_contains_yield(obj)
    ComputedMember(obj, key, _)
    | OptionalComputedMember(obj, key, _)
    | ChainComputedMember(obj, key, _) =>
      expr_contains_yield(obj) || expr_contains_yield(key)
    SuperComputedMember(e, _) => expr_contains_yield(e)
    Ternary(cond, t, f, _) =>
      expr_contains_yield(cond) ||
      expr_contains_yield(t) ||
      expr_contains_yield(f)
    Call(f, args, _) | NewExpr(f, args, _) | OptionalCall(f, args, _) =>
      expr_contains_yield(f) ||
      args.iter().any(fn(a) { expr_contains_yield(a) })
    SuperCall(args, _) => args.iter().any(fn(a) { expr_contains_yield(a) })
    ArrayLit(elems, _) => elems.iter().any(fn(e) { expr_contains_yield(e) })
    ObjectLit(props, _) =>
      props
      .iter()
      .any(fn(p) { expr_contains_yield(p.key) || expr_contains_yield(p.value) })
    TemplateLit(_, exprs, _) =>
      exprs.iter().any(fn(e) { expr_contains_yield(e) })
    TaggedTemplate(tag, _, exprs, _) =>
      expr_contains_yield(tag) ||
      exprs.iter().any(fn(e) { expr_contains_yield(e) })
    // DestructureAssign LHS pattern can contain computed keys or defaults with
    // yield expressions ({[yield]: a} = {}, {a = yield} = {}) — scan both sides.
    DestructureAssign(pat, rhs, _) =>
      pattern_contains_yield(pat) || expr_contains_yield(rhs)
    // Arrow params (including defaults) are evaluated in the enclosing scope,
    // so ArrowFuncExt/AsyncArrowFuncExt are NOT full boundaries for yield.
    // Simple ArrowFunc/AsyncArrowFunc have no defaults, so false is safe.
    ArrowFuncExt(params, _, _, _, _) | AsyncArrowFuncExt(params, _, _, _, _) =>
      params_contain_yield(params)
    // Nested function boundaries — yield inside is not the outer generator's
    FuncExpr(_, _, _, _, _)
    | FuncExprExt(_, _, _, _, _, _)
    | GeneratorExpr(_, _, _, _, _)
    | GeneratorExprExt(_, _, _, _, _, _)
    | AsyncFuncExpr(_, _, _, _, _)
    | AsyncFuncExprExt(_, _, _, _, _, _)
    | AsyncArrowFunc(_, _, _, _)
    | AsyncGeneratorExpr(_, _, _, _, _)
    | AsyncGeneratorExprExt(_, _, _, _, _, _)
    | ArrowFunc(_, _, _, _) => false
    // Class is NOT a full boundary: heritage and computed member keys are
    // evaluated in the surrounding scope (ES §15.7.1 ClassElementName).
    ClassExpr(_, superclass, members, _, _) => {
      let heritage = match superclass {
        Some(e) => expr_contains_yield(e)
        None => false
      }
      let computed = members
        .iter()
        .any(fn(m) {
          match m {
            Method(cm) => cm.computed && expr_contains_yield(cm.key)
            Field(cf) => cf.computed && expr_contains_yield(cf.key)
          }
        })
      heritage || computed
    }
    _ => false
  }
}

///|
// Walk a binding pattern for yield expressions in default values and computed
// property keys. Property name strings (e.g. the "yield" in {yield: x}) are
// not expressions and are intentionally not flagged here.
fn pattern_contains_yield(pat : @ast.Pattern) -> Bool {
  match pat {
    IdentPat(_) => false
    DefaultPat(inner, default_expr) =>
      pattern_contains_yield(inner) || expr_contains_yield(default_expr)
    ArrayPat(elements, rest) => {
      let elems_yield = elements
        .iter()
        .any(fn(e) {
          match e {
            Some(p) => pattern_contains_yield(p)
            None => false
          }
        })
      let rest_yield = match rest {
        Some(r) => pattern_contains_yield(r)
        None => false
      }
      elems_yield || rest_yield
    }
    AssignTarget(e) => expr_contains_yield(e)
    ObjectPat(props, rest) => {
      let props_yield = props
        .iter()
        .any(fn(prop) {
          // Check computed key expression (e.g. {[yield]: x}), shorthand or
          // keyed default (e.g. {x = yield} or {a: b = yield}), and nested pat.
          let computed_yield = match prop.computed_key {
            Some(e) => expr_contains_yield(e)
            None => false
          }
          let default_yield = match prop.default_val {
            Some(e) => expr_contains_yield(e)
            None => false
          }
          computed_yield || default_yield || pattern_contains_yield(prop.value)
        })
      let rest_yield = match rest {
        Some(r) => pattern_contains_yield(r)
        None => false
      }
      props_yield || rest_yield
    }
  }
}

///|
fn params_contain_yield(params : Array[@ast.Param]) -> Bool {
  params
  .iter()
  .any(fn(p) {
    let default_has_yield = match p.default_val {
      Some(expr) => expr_contains_yield(expr)
      None => false
    }
    let pattern_has_yield = match p.pattern {
      Some(pat) => pattern_contains_yield(pat)
      None => false
    }
    default_has_yield || pattern_has_yield
  })
}

///|
/// Set up the GeneratorFunction constructor on the given interpreter.
/// GeneratorFunction("a", "yield a") creates a generator function,
/// analogous to Function("a", "return a") for regular functions.
pub fn setup_generator_function_constructor(
  env : Environment,
  global_this : Value,
  well_known_symbols~ : WellKnownSymbols,
) -> Unit {
  // %GeneratorFunction.prototype% inherits from Function.prototype
  let func_proto : Value = match env.bindings.get("[[FunctionPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let iter_proto = match env.realm_state {
    Some(rs) => rs.get_iterator_proto()
    None => Null
  }
  let tostringtag_sym = well_known_symbols.to_string_tag
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
  // %GeneratorFunction%.prototype — build shell first so it can serve as
  // the constructor value in %GeneratorPrototype%'s property map, ensuring
  // insertion order follows §27.3.3: constructor, prototype (string keys).
  let gf_sym_props : Map[Int, Value] = {}
  let gf_sym_descs : Map[Int, PropDescriptor] = {}
  gf_sym_props[tostringtag_sym.id] = String_("GeneratorFunction")
  gf_sym_descs[tostringtag_sym.id] = non_enum_non_writable
  let gen_func_proto : Value = Object({
    bag: {
      properties: {},
      symbol_properties: gf_sym_props,
      descriptors: {},
      symbol_descriptors: gf_sym_descs,
      internal_slots: {},
    },
    prototype: func_proto,
    callable: None,
    class_name: "GeneratorFunction",
    extensible: true,
    arraybuffer_state: None,
  })
  // %GeneratorPrototype% — shared singleton for all sync generator instances.
  // Own string keys follow §27.3.1: constructor, next, return, throw.
  let gp_props : Map[String, Value] = {}
  let gp_sym_props : Map[Int, Value] = {}
  let gp_descs : Map[String, PropDescriptor] = {}
  let gp_sym_descs : Map[Int, PropDescriptor] = {}
  gp_props["constructor"] = gen_func_proto
  gp_descs["constructor"] = non_enum_non_writable
  gp_props["next"] = make_interp_method_func(
    name="next",
    length=1,
    realm_state=env.realm_state,
    fn(ip, this_val, args) raise {
      let arg = match args {
        [first, ..] => first
        [] => Undefined
      }
      generator_resume(ip, this_val, Next(arg))
    },
  )
  gp_descs["next"] = non_enum
  gp_props["return"] = make_interp_method_func(
    name="return",
    length=1,
    realm_state=env.realm_state,
    fn(ip, this_val, args) raise {
      let arg = match args {
        [first, ..] => first
        [] => Undefined
      }
      generator_resume(ip, this_val, Return(arg))
    },
  )
  gp_descs["return"] = non_enum
  gp_props["throw"] = make_interp_method_func(
    name="throw",
    length=1,
    realm_state=env.realm_state,
    fn(ip, this_val, args) raise {
      let arg = match args {
        [first, ..] => first
        [] => Undefined
      }
      generator_resume(ip, this_val, Throw(arg))
    },
  )
  gp_descs["throw"] = non_enum
  gp_sym_props[tostringtag_sym.id] = String_("Generator")
  gp_sym_descs[tostringtag_sym.id] = non_enum_non_writable
  // [[Prototype]] = %IteratorPrototype% per §27.3.1 — Symbol.iterator is
  // inherited from there, not an own property of %GeneratorPrototype%.
  let gen_proto : Value = Object({
    bag: {
      properties: gp_props,
      symbol_properties: gp_sym_props,
      descriptors: gp_descs,
      symbol_descriptors: gp_sym_descs,
      internal_slots: {},
    },
    prototype: iter_proto,
    callable: None,
    class_name: "Generator",
    extensible: true,
    arraybuffer_state: None,
  })
  // GeneratorFunction constructor: GeneratorFunction(p1, p2, ..., body)
  let gen_func_ctor : Value = make_interp_method_func(
    name="GeneratorFunction",
    length=1,
    realm_state=env.realm_state,
    fn(interp, _this, args) raise {
      // §20.2.1.1.1: coerce params first (step 5a), body last (step 6).
      // Last arg is body, previous args are parameter names.
      let param_count = if args.length() == 0 { 0 } else { args.length() - 1 }
      let param_parts : Array[String] = []
      for i = 0; i < param_count; i = i + 1 {
        match args[i] {
          String_(s) => param_parts.push(s)
          _ => param_parts.push(interp.to_js_string(args[i]))
        }
      }
      let body_str = if args.length() == 0 {
        ""
      } else {
        match args[args.length() - 1] {
          String_(s) => s
          _ => interp.to_js_string(args[args.length() - 1])
        }
      }
      let params_str = param_parts.join(",")
      let source = "function* anonymous(" +
        params_str +
        "\n) {\n" +
        body_str +
        "\n}"
      let prog = @parser.parse(source)
      if prog.stmts.length() > 0 {
        match prog.stmts[0] {
          GeneratorDecl(_, params, body, _, source_text) => {
            let body_strict = @static_semantics.has_use_strict(body)
            validate_function_constructor_params(true, params, None, body)
            interp.validate_block_early_errors(body, body_strict)
            return interp.make_generator_function(
              Some("anonymous"),
              params,
              None,
              body,
              body_strict,
              interp.global,
              source_text~,
            )
          }
          GeneratorDeclExt(_, params, rest_param, body, _, source_text) => {
            // §20.2.1.1.1 step 17a: YieldExpression in generator params → SyntaxError.
            // The parser now enters generator context for params, so `yield` in
            // default values is parsed as YieldExpr and caught here via AST walk.
            if params_contain_yield(params) {
              raise @errors.SyntaxError(
                message="Generator function parameters may not contain yield expressions",
              )
            }
            let body_strict = @static_semantics.has_use_strict(body)
            validate_function_constructor_params_ext(params, rest_param, body)
            interp.validate_block_early_errors(body, body_strict)
            return interp.make_generator_function_ext(
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
      }
      raise @errors.SyntaxError(
        message="Invalid GeneratorFunction constructor source",
      )
    },
  )
  // §27.3.3: gen_func_proto string keys: constructor (§27.3.3.1) then prototype (§27.3.3.2).
  match gen_func_proto {
    Object(data) => {
      data.bag.properties["constructor"] = gen_func_ctor
      data.bag.descriptors["constructor"] = non_enum_non_writable
      data.bag.properties["prototype"] = gen_proto
      data.bag.descriptors["prototype"] = non_enum_non_writable
    }
    _ => ()
  }
  // Mirror onto globalThis
  match global_this {
    Object(data) => data.bag.properties["GeneratorFunction"] = gen_func_ctor
    _ => ()
  }
  // Add prototype property to GeneratorFunction constructor
  match gen_func_ctor {
    Object(data) => {
      data.bag.properties["prototype"] = gen_func_proto
      data.bag.descriptors["prototype"] = frozen
    }
    _ => ()
  }
  env.def_builtin("GeneratorFunction", gen_func_ctor)
  env.def_builtin("[[GeneratorFunctionPrototype]]", gen_func_proto)
  env.def_builtin("[[GeneratorPrototype]]", gen_proto)
}

///|
/// Yield signal — used to suspend generator execution
pub suberror YieldSignal {
  YieldSignal(Value) // the yielded value
}

///|
/// Generator return signal — used to inject return at yield point
/// This is NOT JS-catchable, but must trigger finally blocks.
pub suberror GeneratorReturnSignal {
  GeneratorReturnSignal(Value)
}

///|
/// Create a generator function value (simple params)
fn Interpreter::make_generator_function(
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
  let interp = self
  let gen_proto : Value = match
    interp.global.bindings.get("[[GeneratorPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  // Create the generator function's own .prototype (instances inherit from it)
  let func_prototype = Object({
    bag: PropertyBag(),
    prototype: gen_proto,
    callable: None,
    class_name: "Generator",
    extensible: true,
    arraybuffer_state: None,
  })
  // Generator functions inherit from %GeneratorFunction.prototype%
  let gen_func_proto : Value = match
    interp.global.bindings.get("[[GeneratorFunctionPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let func_name = match name {
    Some(n) => n
    None => ""
  }
  let fn_props : Map[String, Value] = {}
  fn_props["prototype"] = func_prototype
  fn_props["name"] = String_(func_name)
  fn_props["length"] = Number(params.length().to_double())
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
  let gen_func = stamp_function_realm(
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
            func_prototype,
          )
        }),
      ),
      class_name: "GeneratorFunction",
      extensible: true,
      arraybuffer_state: None,
    }),
    realm_state=Some(self.realm_state),
  )
  if has_name_binding {
    match name {
      Some(n) =>
        match effective_closure.bindings.get(n) {
          Some(b) => b.value = gen_func
          None => ()
        }
      None => ()
    }
  }
  gen_func
}

///|
/// Create a generator function value (extended params)
fn Interpreter::make_generator_function_ext(
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
  let interp = self
  let gen_proto : Value = match
    interp.global.bindings.get("[[GeneratorPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let func_prototype = Object({
    bag: PropertyBag(),
    prototype: gen_proto,
    callable: None,
    class_name: "Generator",
    extensible: true,
    arraybuffer_state: None,
  })
  // Generator functions inherit from %GeneratorFunction.prototype%
  let gen_func_proto : Value = match
    interp.global.bindings.get("[[GeneratorFunctionPrototype]]") {
    Some(binding) => binding.value
    None => Null
  }
  let func_name = match name {
    Some(n) => n
    None => ""
  }
  let expected_arg_count = expected_argument_count_ext(params)
  let fn_props : Map[String, Value] = {}
  fn_props["prototype"] = func_prototype
  fn_props["name"] = String_(func_name)
  fn_props["length"] = Number(expected_arg_count.to_double())
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
  let gen_func = stamp_function_realm(
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
            func_prototype,
          )
        }),
      ),
      class_name: "GeneratorFunction",
      extensible: true,
      arraybuffer_state: None,
    }),
    realm_state=Some(self.realm_state),
  )
  if has_name_binding {
    match name {
      Some(n) =>
        match effective_closure.bindings.get(n) {
          Some(b) => b.value = gen_func
          None => ()
        }
      None => ()
    }
  }
  gen_func
}

///|
/// Create a generator instance when a generator function is called
fn create_generator_instance(
  interp : Interpreter,
  this_val : Value,
  args : Array[Value],
  name : String?,
  params : Array[String],
  params_ext : Array[@ast.Param]?,
  rest_param : String?,
  body : Array[@ast.Stmt],
  strict : Bool,
  closure : Environment,
  func_prototype : Value,
  is_arrow? : Bool = false,
  callee? : Value = Undefined,
  is_async? : Bool = false,
) -> Value raise Error {
  // Per spec, FunctionDeclarationInstantiation runs eagerly when generator is called,
  // NOT when .next() is called. This means parameter binding errors throw immediately.
  // Use the stored strict flag instead of re-scanning the body.
  let gen_strict = strict
  let setup_ctx : ExecContext = { strict: gen_strict, current_generator: None }
  // §10.2.11 split: Ext-shape generator params (params_ext=Some) get a
  // separate body_env for body var/let/const. Simple params (params_ext=None)
  // stay single-env. `func_env` below is the param env in the Ext case and
  // the single env in the simple case; `body_exec_env` is the env the
  // generator body executes in (body_env when split, func_env otherwise).
  let func_env = Environment::new(parent=Some(closure))
  func_env.is_var_scope = true
  // Arrow functions don't rebind `this` (use closure's lexical this).
  if !is_arrow {
    let effective_this = if !strict {
      match this_val {
        Undefined | Null => interp.global_this
        _ => this_val
      }
    } else {
      this_val
    }
    func_env.def("this", effective_this, LetBinding)
  }
  func_env.def("<new.target>", Undefined, LetBinding)
  let has_arguments_param = match params_ext {
    Some(pext) => ext_params_include_arguments(pext, rest_param)
    None => params_include_arguments(params, rest_param)
  }
  // Arrow functions don't create own `arguments` (fall through to closure).
  if !is_arrow && !has_arguments_param {
    // Create arguments object before binding params so default value
    // evaluation can reference it (ES2026 §10.2.11 step 20).
    let args_obj = match (params_ext, strict) {
      (None, false) =>
        // Sloppy mode + simple params: mapped arguments with live param bindings.
        make_arguments_object(
          interp.realm_state,
          interp.realm_state.well_known_symbols,
          args,
          callee,
          false,
          mapped_names=params,
          mapped_env=Some(func_env),
        )
      _ => {
        // Strict mode or complex params: unmapped arguments object.
        let tte_val : Value? = if func_env.has("[[ThrowTypeError]]") {
          Some(func_env.get("[[ThrowTypeError]]"))
        } else {
          None
        }
        make_arguments_object(
          interp.realm_state,
          interp.realm_state.well_known_symbols,
          args,
          callee,
          strict,
          throw_type_error=tte_val,
        )
      }
    }
    func_env.def("arguments", args_obj, VarBinding)
  }
  // Bind parameters eagerly
  // §19.2.1.3 gate (#A.6): generator / async / async-gen functions are
  // all non-arrow, so default-expression evaluation activates the same
  // eval-declares-arguments gate as `bind_ext_params_and_exec_body`.
  // Save on entry / reset to false / restore on exit so nested invocations
  // in defaults don't inherit outer state.
  let saved_in_default = interp.in_nonarrow_param_default_eval
  let saved_param_default_conflicts = interp.param_default_eval_var_conflicts
  interp.in_nonarrow_param_default_eval = false
  interp.param_default_eval_var_conflicts = None
  let gen_result : Value = try {
    match params_ext {
      Some(pext) => {
        let param_default_conflicts = collect_param_default_eval_var_conflicts(
          pext,
          rest_param,
          implicit_arguments=true,
        )
        // §10.2.11 step 21: pre-declare all param BoundNames as TDZ so
        // that self- and forward-referencing defaults throw ReferenceError.
        let mut has_rest_pattern_param = false
        for p in pext {
          if p.is_rest_pattern {
            has_rest_pattern_param = true
            // Declare bound names from the rest destructuring pattern (...[a] → a),
            // but NOT the synthetic "$rest" name stored in rest_param.
            match p.pattern {
              Some(pat) =>
                walk_pattern_idents(pat, name => func_env.def_param_tdz(name))
              None => ()
            }
            continue
          }
          match p.pattern {
            Some(pat) =>
              // Destructuring param: pre-declare all bound names (e.g. {y} → y).
              walk_pattern_idents(pat, name => func_env.def_param_tdz(name))
            None => func_env.def_param_tdz(p.name)
          }
        }
        // Simple named rest (e.g. ...rest): pre-declare the user name.
        // Destructuring rest (...[a]): bound names declared above via walk_pattern_idents.
        if !has_rest_pattern_param {
          match rest_param {
            Some(rp) => func_env.def_param_tdz(rp)
            None => ()
          }
        }
        let mut effective_count = 0
        for i = 0; i < pext.length(); i = i + 1 {
          let param = pext[i]
          if param.is_rest_pattern {
            continue
          }
          let val : Value = if effective_count < args.length() &&
            !(args[effective_count] is Undefined) {
            args[effective_count]
          } else {
            match param.default_val {
              Some(d) => {
                interp.in_nonarrow_param_default_eval = true
                interp.param_default_eval_var_conflicts = Some(
                  param_default_conflicts,
                )
                let v = interp.eval_expr(setup_ctx, d, func_env)
                interp.in_nonarrow_param_default_eval = false
                interp.param_default_eval_var_conflicts = None
                v
              }
              None =>
                if effective_count < args.length() {
                  args[effective_count]
                } else {
                  Undefined
                }
            }
          }
          match param.pattern {
            Some(pat) =>
              interp.bind_pattern(pat, val, func_env, LetBinding, ctx=setup_ctx)
            None => func_env.initialize(param.name, val)
          }
          effective_count = effective_count + 1
        }
        match rest_param {
          Some(rp) => {
            let rest_elems : Array[Value] = []
            for i = effective_count; i < args.length(); i = i + 1 {
              rest_elems.push(args[i])
            }
            let rest_val = make_array(rest_elems)
            let mut bound_rest_pattern = false
            for p in pext {
              if p.is_rest_pattern {
                match p.pattern {
                  Some(pat) =>
                    interp.bind_pattern(
                      pat,
                      rest_val,
                      func_env,
                      LetBinding,
                      ctx=setup_ctx,
                    )
                  None => ()
                }
                bound_rest_pattern = true
                break
              }
            }
            if !bound_rest_pattern {
              func_env.initialize(rp, rest_val)
            }
          }
          None => ()
        }
      }
      None => {
        for i = 0; i < params.length(); i = i + 1 {
          let val = if i < args.length() { args[i] } else { Undefined }
          func_env.def_parameter(params[i], val)
        }
        match rest_param {
          Some(rp) => {
            let rest_elems : Array[Value] = []
            for i = params.length(); i < args.length(); i = i + 1 {
              rest_elems.push(args[i])
            }
            func_env.def_parameter(rp, make_array(rest_elems))
          }
          None => ()
        }
      }
    }
    // Split body env iff Ext shape AND HasParameterExpressions; simple
    // params + plain-rest Ext both stay single-env per §10.2.11 step 26.
    let split_scope = match params_ext {
      Some(pext) => has_parameter_expressions(pext)
      None => false
    }
    let body_exec_env = if split_scope {
      let be = Environment::new(parent=Some(func_env))
      be.is_var_scope = true
      be
    } else {
      func_env
    }
    let param_source : Environment? = if split_scope {
      Some(func_env)
    } else {
      None
    }
    // Hoist declarations eagerly too
    interp.hoist_declarations(
      body,
      body_exec_env,
      strict=gen_strict,
      param_source~,
    )
    hoist_block_tdz(body, body_exec_env)
    let gen_id = interp.gen_id_counter.val
    interp.gen_id_counter.val = gen_id + 1
    let gen_obj : GeneratorObject = {
      id: gen_id,
      state: SuspendedStart,
      body,
      strict: gen_strict,
      params,
      params_ext,
      rest_param,
      closure,
      is_async,
      name,
      interpreter: interp,
      args,
      this_val,
      env: Some(body_exec_env),
      pc: 0,
      yield_value: Undefined,
      yield_resume_values: {},
      resuming: false,
      resume_action: NextAction,
      try_resume_phase: -1,
      try_resume_yield_base: 0,
      try_resume_error: Undefined,
      try_resume_result: Normal(Undefined),
      try_resume_pending_error: None,
      loop_env_stack: [],
      loop_yield_base_stack: [],
      for_of_iterator: Undefined,
      for_of_next: Undefined,
      for_of_iterator_stack: [],
      for_of_next_stack: [],
      for_of_resume: false,
      for_of_awaiting_next: false,
      dstr_iterator_stack: [],
      delegate_iterator: Undefined,
      delegate_next: Undefined,
      delegating: false,
      yield_index: 0,
      resume_at_yield: 0,
    }
    interp.generator_objects[gen_id] = gen_obj
    // Create the generator instance object with gen_id stored in a property
    let props : Map[String, Value] = {}
    props["<gen_id>"] = Number(gen_id.to_double())
    Object({
      bag: {
        properties: props,
        symbol_properties: {},
        descriptors: {},
        symbol_descriptors: {},
        internal_slots: {},
      },
      prototype: func_prototype,
      callable: None,
      class_name: if is_async {
        "AsyncGenerator"
      } else {
        "Generator"
      },
      extensible: true,
      arraybuffer_state: None,
    })
  } catch {
    e => {
      interp.in_nonarrow_param_default_eval = saved_in_default
      interp.param_default_eval_var_conflicts = saved_param_default_conflicts
      raise e
    }
  }
  interp.in_nonarrow_param_default_eval = saved_in_default
  interp.param_default_eval_var_conflicts = saved_param_default_conflicts
  gen_result
}

///|
/// Get GeneratorObject from a generator instance Value
fn get_generator_object(
  interp : Interpreter,
  this_val : Value,
) -> GeneratorObject? {
  match this_val {
    Object(data) =>
      match data.bag.properties.get("<gen_id>") {
        Some(Number(id)) => interp.generator_objects.get(id.to_int())
        _ => None
      }
    _ => None
  }
}

///|
/// Resume generator execution
fn generator_resume(
  interp : Interpreter,
  this_val : Value,
  resume_kind : ResumeKind,
) -> Value raise Error {
  let gen = match get_generator_object(interp, this_val) {
    Some(g) => g
    None =>
      raise @errors.TypeError(
        message="Method next/throw/return called on incompatible receiver",
      )
  }
  match gen.state {
    Executing => raise @errors.TypeError(message="Generator is already running")
    Completed =>
      match resume_kind {
        Next(_) => create_iter_result(Undefined, true)
        Return(v) => create_iter_result(v, true)
        Throw(e) => raise JsException(e)
      }
    SuspendedStart =>
      match resume_kind {
        Next(_) => {
          // Start execution of generator body
          gen.state = Executing
          generator_start(interp, gen)
        }
        Throw(e) => {
          // .throw(e) on SuspendedStart: complete generator and throw
          complete_generator(gen)
          raise JsException(e)
        }
        Return(v) => {
          // .return(v) on SuspendedStart: complete generator and return done
          complete_generator(gen)
          create_iter_result(v, true)
        }
      }
    SuspendedYield =>
      if gen.delegating {
        // Forward to delegate iterator
        gen.state = Executing
        delegate_resume(interp, gen, resume_kind)
      } else {
        match resume_kind {
          Next(v) => {
            gen.state = Executing
            gen.yield_value = v
            gen.yield_resume_values[gen.resume_at_yield] = v
            gen.resume_action = NextAction
            generator_continue(interp, gen)
          }
          Throw(e) => {
            gen.state = Executing
            gen.yield_value = Undefined
            gen.resume_action = ThrowAction(e)
            generator_continue(interp, gen)
          }
          Return(v) => {
            gen.state = Executing
            gen.yield_value = v
            gen.resume_action = ReturnAction(v)
            generator_continue(interp, gen)
          }
        }
      }
  }
}

///|
/// Start generator body execution (first .next() call)
fn generator_start(
  interp : Interpreter,
  gen : GeneratorObject,
) -> Value raise Error {
  // Environment was already created and parameters bound in create_generator_instance
  let func_env = match gen.env {
    Some(e) => e
    None => abort("generator_start: no environment")
  }
  // Execute generator body, catching yields
  run_generator_body(interp, gen, func_env)
}

///|
/// Run generator body, handling yields.
/// On initial execution, statements run from gen.pc forward.
/// When a YieldSignal is caught, the generator suspends.
/// On resume, the SAME statement is re-executed with gen.resuming=true,
/// so that eval_yield returns the resume value instead of yielding again.
fn run_generator_body(
  interp : Interpreter,
  gen : GeneratorObject,
  env : Environment,
) -> Value raise Error {
  // Build per-execution context with this generator as the current generator.
  // Use the stored strict flag rather than re-scanning the body on every resume.
  let gen_ctx : ExecContext = {
    strict: gen.strict,
    current_generator: Some(gen),
  }
  let result = try {
    while gen.pc < gen.body.length() {
      let i = gen.pc
      let stmt = gen.body[i]
      if !gen.resuming {
        gen.yield_resume_values.clear()
        gen.yield_index = 0 // Reset yield counter for each non-resuming statement
      } else {
        // Resumes replay the suspended statement from its beginning, including
        // loop statements after their saved environments are restored. Keep
        // yield indexes stable so earlier yields in the same statement can be
        // replayed and abrupt resumes target the suspended yield.
        gen.yield_index = 0
      }
      let signal = interp.exec_stmt(gen_ctx, stmt, env) catch {
        YieldSignal(yielded_value) => {
          // Statement yielded. DON'T advance pc — on resume we'll replay this stmt.
          gen.state = SuspendedYield
          return create_iter_result(yielded_value, false)
        }
        GeneratorReturnSignal(v) => {
          // .return(v) was injected at yield point and propagated up
          // (possibly through finally blocks). Complete the generator.
          complete_generator(gen)
          return create_iter_result(v, true)
        }
        e => raise e
      }
      // Statement completed normally — advance to next
      gen.pc = i + 1
      match signal {
        Normal(_) => ()
        ReturnSignal(v) => {
          complete_generator(gen)
          return create_iter_result(v, true)
        }
        BreakSignal(_, _) | ContinueSignal(_, _) => ()
      }
    }
    // Body completed normally — per spec, generators return undefined if no explicit return
    complete_generator(gen)
    create_iter_result(Undefined, true)
  } catch {
    e => {
      complete_generator(gen)
      raise e
    }
  }
  result
}

///|
/// Continue generator after yield (resume with next value)
fn generator_continue(
  interp : Interpreter,
  gen : GeneratorObject,
) -> Value raise Error {
  match gen.env {
    Some(env) => {
      // Set resuming flag — the statement will be replayed, and eval_yield
      // will return the resume value instead of throwing YieldSignal
      gen.resuming = true
      run_generator_body(interp, gen, env)
    }
    None => {
      complete_generator(gen)
      create_iter_result(Undefined, true)
    }
  }
}

// generator_continue_throw and generator_continue_return are now handled
// by the unified generator_continue path via resume_action field.

///|
/// Evaluate a yield expression during generator body execution.
/// When resuming (gen.resuming == true), inspects resume_action:
/// - NextAction: returns the resume value
/// - ThrowAction(e): raises JsException(e) at the yield point
/// - ReturnAction(v): raises GeneratorReturnSignal(v) at the yield point
/// When delegate is true (yield*), iterates the delegate and yields each value.
fn Interpreter::eval_yield(
  self : Interpreter,
  ctx : ExecContext,
  argument : @ast.Expr?,
  delegate : Bool,
  env : Environment,
) -> Value raise Error {
  match ctx.current_generator {
    Some(gen) => {
      let current_yield_index = gen.yield_index
      gen.yield_index = gen.yield_index + 1
      if gen.resuming && current_yield_index == gen.resume_at_yield {
        // This is the exact yield that was suspended — apply resume action
        gen.resuming = false
        match gen.resume_action {
          NextAction => {
            gen.yield_resume_values[current_yield_index] = gen.yield_value
            return gen.yield_value
          }
          ThrowAction(e) => {
            gen.resume_action = NextAction
            raise JsException(e)
          }
          ReturnAction(v) => {
            gen.resume_action = NextAction
            raise GeneratorReturnSignal(v)
          }
        }
      }
      if gen.resuming && gen.loop_env_stack.length() == 0 {
        // If this yield already completed on a prior pass, replay its value.
        // Missing entries mean this is the active resume point or a yield nested
        // above it, so we must continue evaluating it normally.
        match gen.yield_resume_values.get(current_yield_index) {
          Some(v) => return v
          None => ()
        }
      }
      if delegate {
        // yield* expr — delegate to another iterable
        let iterable = match argument {
          Some(expr) => self.eval_expr(ctx, expr, env)
          None => Undefined
        }
        let loc = @token.Loc::default()
        if gen.is_async {
          // Async yield*: try @@asyncIterator first, fall back to wrapping sync @@iterator
          let async_iter_sym = self.realm_state.well_known_symbols.async_iterator
          let async_iter_method = self.get_computed_property(
            iterable,
            Symbol(async_iter_sym),
            loc,
          )
          let async_iterator = match async_iter_method {
            Object(data) =>
              match data.callable {
                Some(_) => self.call_value(async_iter_method, iterable, [], loc)
                None =>
                  raise @errors.TypeError(
                    message="Result of the Symbol.asyncIterator method is not callable",
                  )
              }
            Undefined | Null => {
              // Fall back to wrapping sync iterator via CreateAsyncFromSyncIterator
              let sync_iter_sym = self.realm_state.well_known_symbols.iterator
              let sync_iter_method = self.get_computed_property(
                iterable,
                Symbol(sync_iter_sym),
                loc,
              )
              let sync_iterator = match sync_iter_method {
                Object(data) =>
                  match data.callable {
                    Some(_) =>
                      self.call_value(sync_iter_method, iterable, [], loc)
                    None =>
                      raise @errors.TypeError(
                        message="Symbol.iterator is not a function",
                      )
                  }
                _ =>
                  raise @errors.TypeError(
                    message="yield* delegate is not async iterable",
                  )
              }
              let sync_next = get_iterator_next(self, sync_iterator)
              create_async_from_sync_iterator(
                self, sync_iterator, sync_next, loc,
              )
            }
            _ =>
              raise @errors.TypeError(
                message="Result of the Symbol.asyncIterator method is not an object",
              )
          }
          // Save async iterator delegation state on generator BEFORE calling first
          // .next() — the Promise from .next() is yielded and resolved asynchronously
          // by async_generator_step, which needs the delegate state to handle it.
          // (Sync yield* calls .next() first and only saves state if not immediately
          // done — async yield* always yields because .next() returns a Promise.)
          let async_next = get_iterator_next(self, async_iterator)
          gen.delegate_iterator = async_iterator
          gen.delegate_next = async_next
          gen.delegating = true
          gen.resume_at_yield = current_yield_index
          gen.yield_resume_values[current_yield_index] = Undefined
          // Start delegation by calling async .next() — returns a Promise
          let first_result = self.call_value(
            async_next,
            async_iterator,
            [],
            loc,
          )
          // Yield the Promise for async_generator_step to await and handle the result
          raise YieldSignal(first_result)
        } else {
          // Sync yield*: get iterator via Symbol.iterator
          let iterator_sym = self.realm_state.well_known_symbols.iterator
          let iterator_method = self.get_computed_property(
            iterable,
            Symbol(iterator_sym),
            loc,
          )
          let iterator = match iterator_method {
            Object(data) =>
              match data.callable {
                Some(_) => {
                  let result = self.call_value(
                    iterator_method,
                    iterable,
                    [],
                    loc,
                  )
                  match result {
                    Object(_) => result
                    _ =>
                      raise @errors.TypeError(
                        message="Result of the Symbol.iterator method is not an object",
                      )
                  }
                }
                None =>
                  raise @errors.TypeError(
                    message="Symbol.iterator is not a function",
                  )
              }
            _ =>
              raise @errors.TypeError(message="yield* delegate is not iterable")
          }
          // Get next method
          let next_method = get_iterator_next(self, iterator)
          // Start delegation: call next() and yield first value
          let first_result = self.call_value(
            next_method,
            iterator,
            [Undefined],
            loc,
          )
          guard is_object_value(first_result) else {
            raise @errors.TypeError(message="Iterator result is not an object")
          }
          // Extract done via proper Get (§7.4.2 IteratorComplete) so getter
          // side-effects fire correctly.
          let done = is_truthy(self.get_property(first_result, "done", loc))
          if done {
            // Delegate is immediately done — extract value via proper Get
            // (§7.4.3 IteratorValue) and yield* evaluates to the return value.
            self.get_property(first_result, "value", loc)
          } else {
            // Save delegation state on generator and yield the value.
            // Read value from bag.properties directly — must NOT trigger
            // value getter when done is false (test262 check).
            let value = match first_result {
              Object(data) =>
                match data.bag.properties.get("value") {
                  Some(v) => v
                  None => Undefined
                }
              _ => Undefined
            }
            gen.delegate_iterator = iterator
            gen.delegate_next = next_method
            gen.delegating = true
            gen.resume_at_yield = current_yield_index
            raise YieldSignal(value)
          }
        }
      } else {
        // Normal yield: evaluate argument and suspend
        let yielded_value = match argument {
          Some(expr) => self.eval_expr(ctx, expr, env)
          None => Undefined
        }
        // Track the value to use when re-running this yield during replay.
        gen.yield_resume_values[current_yield_index] = Undefined
        gen.resume_at_yield = current_yield_index
        raise YieldSignal(yielded_value)
      }
    }
    None =>
      // Parser prevents YieldExpr outside generator context, so this is unreachable
      raise @errors.TypeError(
        message="Internal error: yield outside generator context",
      )
  }
}

///|
/// Get iterator's next method (walk prototype chain)
fn get_iterator_next(
  interp : Interpreter,
  iterator : Value,
) -> Value raise Error {
  match get_optional_method(iterator, "next", interp) {
    Some(next_fn) => next_fn
    None => raise @errors.TypeError(message="iterator.next is not a function")
  }
}

///|
/// Inject an error into the generator body via ThrowAction.
/// Clears delegation state and resumes the generator with the error.
fn inject_error(
  interp : Interpreter,
  gen : GeneratorObject,
  error : Error,
) -> Value raise Error {
  gen.delegating = false
  gen.delegate_iterator = Undefined
  gen.delegate_next = Undefined
  let v = match error {
    JsException(js_val) => js_val
    _ => js_error_to_value_with_env(error, Some(interp.global))
  }
  gen.resume_action = ThrowAction(v)
  generator_continue(interp, gen)
}

///|

///|
/// Resume a delegated yield* — forward the resume to the delegate iterator

///|
/// Process a sync delegation result: check IsObject, extract done/value,
/// then either complete delegation (done:true, calling `make_resume_action`)
/// or yield the value (done:false).
fn process_delegate_result(
  interp : Interpreter,
  gen : GeneratorObject,
  result : Value,
  make_resume_action : (Value) -> ResumeAction,
) -> Value raise Error {
  let loc = @token.Loc::default()
  guard is_object_value(result) else {
    raise @errors.TypeError(message="Iterator result is not an object")
  }
  let done = is_truthy(interp.get_property(result, "done", loc))
  if done {
    let value = interp.get_property(result, "value", loc)
    gen.delegating = false
    gen.delegate_iterator = Undefined
    gen.delegate_next = Undefined
    gen.yield_value = value
    gen.resume_action = make_resume_action(value)
    generator_continue(interp, gen)
  } else {
    let value = match result {
      Object(data) =>
        match data.bag.properties.get("value") {
          Some(v) => v
          None => Undefined
        }
      _ => Undefined
    }
    gen.state = SuspendedYield
    create_iter_result(value, false)
  }
}

///|
fn delegate_resume(
  interp : Interpreter,
  gen : GeneratorObject,
  resume_kind : ResumeKind,
) -> Value raise Error {
  let loc = @token.Loc::default()
  let iterator = gen.delegate_iterator
  let next_method = gen.delegate_next
  // Forward the resume to the delegate
  match resume_kind {
    Next(v) =>
      try {
        let result = interp.call_value(next_method, iterator, [v], loc)
        if gen.is_async {
          gen.state = SuspendedYield
          create_iter_result(result, false)
        } else {
          process_delegate_result(interp, gen, result, fn(_) { NextAction })
        }
      } catch {
        e => inject_error(interp, gen, e)
      }
    Throw(e) =>
      try {
        let throw_method = get_optional_method(iterator, "throw", interp)
        match throw_method {
          Some(tm) => {
            let result = interp.call_value(tm, iterator, [e], loc)
            if gen.is_async {
              gen.state = SuspendedYield
              create_iter_result(result, false)
            } else {
              process_delegate_result(interp, gen, result, fn(_) { NextAction })
            }
          }
          None => {
            // No .throw: close delegate via .return() then throw TypeError
            let return_method = get_optional_method(iterator, "return", interp)
            match return_method {
              Some(rm) => {
                let close_result = interp.call_value(rm, iterator, [], loc)
                guard is_object_value(close_result) else {
                  raise @errors.TypeError(
                    message="Iterator close result is not an object",
                  )
                }
              }
              None => ()
            }
            gen.delegating = false
            gen.delegate_iterator = Undefined
            gen.delegate_next = Undefined
            raise @errors.TypeError(
              message="Iterator does not have a 'throw' method",
            )
          }
        }
      } catch {
        err => inject_error(interp, gen, err)
      }
    Return(v) =>
      try {
        let return_method = get_optional_method(iterator, "return", interp)
        match return_method {
          Some(rm) => {
            let result = interp.call_value(rm, iterator, [v], loc)
            if gen.is_async {
              gen.state = SuspendedYield
              create_iter_result(result, false)
            } else {
              process_delegate_result(interp, gen, result, fn(v) {
                ReturnAction(v)
              })
            }
          }
          None => {
            // No .return: propagate return through outer body for finally blocks
            gen.delegating = false
            gen.delegate_iterator = Undefined
            gen.delegate_next = Undefined
            gen.yield_value = v
            gen.resume_action = ReturnAction(v)
            generator_continue(interp, gen)
          }
        }
      } catch {
        err => inject_error(interp, gen, err)
      }
  }
}

///|
/// `None` if the property is absent, undefined, or null, or `Some(method)`
/// if it exists and is callable.  Raises `TypeError` if the property exists
/// but is not callable.  Delegates to `interp.get_property` for the full
/// `[[Get]]` chain (own data, own accessor getters, prototype walk, proxies).
fn get_optional_method(
  obj : Value,
  name : String,
  interp : Interpreter,
) -> Value? raise Error {
  let loc = @token.Loc::default()
  let func = interp.get_property(obj, name, loc)
  match func {
    Undefined | Null => None
    Object(fd) =>
      match fd.callable {
        Some(_) => Some(func)
        None => raise @errors.TypeError(message="\{name} is not a function")
      }
    _ => raise @errors.TypeError(message="\{name} is not a function")
  }
}

///|
/// On abrupt generator resume (ReturnAction/ThrowAction) while a destructuring
/// iterator is stacked, close iterators per §7.4.9 and propagate the
/// appropriate completion signal.  The for-of caller additionally closes its
/// own outer iterator *before* calling this helper.
///
/// Close order: innermost-first (index 0 = first pushed = innermost level),
/// matching the non-generator spec flow where each nested pattern closes its
/// own iterator before the containing pattern does.
fn Interpreter::close_dstr_stack_on_abrupt_resume(
  self : Interpreter,
  g : GeneratorObject,
  loc : @token.Loc,
) -> Unit raise Error {
  guard g.dstr_iterator_stack.length() > 0 else { return }
  // Only abrupt completions need to close iterators.
  let action = g.resume_action
  guard action is (ReturnAction(_) | ThrowAction(_)) else { return }
  g.resume_action = NextAction
  // Snapshot in push order (index 0 = innermost); drain the stack so stale
  // refs don't linger if a close raises.
  let n = g.dstr_iterator_stack.length()
  let iters : Array[Value] = []
  for i = 0; i < n; i = i + 1 {
    iters.push(g.dstr_iterator_stack[i])
  }
  while g.dstr_iterator_stack.length() > 0 {
    let _ = g.dstr_iterator_stack.pop()
  }
  match action {
    ReturnAction(v) => {
      // §7.4.9 step 8: a close error replaces the return completion.
      // Continue closing remaining iterators even after an error.
      // First error wins: once a completion is abrupt, later close errors are
      // discarded (§7.4.9 step 4 in subsequent levels).
      let mut close_err : Error? = None
      for iter in iters {
        self.iterator_close(iter, loc) catch {
          e => if close_err is None { close_err = Some(e) }
        }
      }
      match close_err {
        Some(e) => raise e
        None => raise GeneratorReturnSignal(v)
      }
    }
    ThrowAction(e) => {
      for iter in iters {
        // ThrowCompletion: §7.4.11 step 5 — close errors discarded.
        self.iterator_close(iter, loc, throw_completion=true)
      }
      raise JsException(e)
    }
    NextAction => () // unreachable: guard above excludes NextAction
  }
}
