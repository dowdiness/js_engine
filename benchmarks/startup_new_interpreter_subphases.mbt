// =============================================================================
// Focused new_interpreter startup subphase harness
//
// This is a measurement-only harness for deciding whether lazy/cached runtime
// initialization is justified. Each row measures one slice of
// @interpreter.new_interpreter() in fresh-realm context. Rows are independent
// microbenchmarks, not an additive profile.
// =============================================================================

///|
using @runtime {
  type Environment,
  type HostEnv,
  type Interpreter,
  type ModuleLoader,
  type PropDescriptor,
  type RealmState,
  type StdlibHooks,
}

///|
priv struct StartupInterpreterCore {
  interp : Interpreter
  global : Environment
  output : Array[String]
  global_this : Value
  realm_state : RealmState
}

///|
fn has_startup_new_interpreter_subphases_arg() -> Bool {
  let args = @env.args()
  for arg in args {
    if arg == "--startup-new-interpreter-subphases" ||
      arg == "--new-interpreter-subphases" {
      return true
    }
  }
  false
}

///|
fn has_csv_arg() -> Bool {
  let args = @env.args()
  for arg in args {
    if arg == "--csv" {
      return true
    }
  }
  false
}

///|
fn make_startup_stdlib_hooks() -> StdlibHooks {
  {
    get_string_method: fn(s, prop, realm_state, annex_b) {
      @stdlib.get_string_method(s, prop, realm_state, annex_b~)
    },
    get_number_method: fn(obj, prop, realm_state) {
      @stdlib.get_number_method(obj, prop, realm_state)
    },
    get_array_method_with_interp: fn(data, prop, realm_state) {
      @stdlib.get_array_method_with_interp(data, prop, realm_state)
    },
    get_map_method: fn(data, prop, realm_state) {
      @stdlib.get_map_method(data, prop, realm_state)
    },
    get_set_method: fn(data, prop, realm_state) {
      @stdlib.get_set_method(data, prop, realm_state)
    },
    get_promise_method: fn(data, prop, realm_state) {
      @stdlib.get_promise_method(data, prop, realm_state)
    },
    make_regexp_object: (realm_state, pattern, flags) => {
      @stdlib.make_regexp_object_with_realm_state(pattern, flags, realm_state)
    },
    typedarray_get_index: fn(data, idx, realm_state) {
      @stdlib.typedarray_get_index(data, idx, realm_state)
    },
    typedarray_set_index: fn(data, idx, val, realm_state) {
      @stdlib.typedarray_set_index(data, idx, val, realm_state)
    },
    typedarray_is_valid_index: fn(data, idx, realm_state) {
      @stdlib.typedarray_is_valid_index(data, idx, realm_state)
    },
    create_realm: fn() { @interpreter.new_interpreter() },
  }
}

///|
fn make_startup_global_object() -> Value {
  Value::Object({
    bag: @runtime.PropertyBag(),
    prototype: Value::Null,
    callable: None,
    class_name: "global",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn make_startup_host(output : Array[String]) -> HostEnv {
  let module_loader : ModuleLoader? = None
  {
    output,
    microtask_queue: [],
    timer_queue: @priority_queue.PriorityQueue([]),
    timer_id_counter: { val: 1 },
    timer_insertion_counter: { val: 0 },
    cancelled_timer_ids: {},
    module_loader,
  }
}

///|
fn make_startup_interpreter_core() -> StartupInterpreterCore {
  let global = Environment::new()
  global.is_var_scope = true
  let output : Array[String] = []
  let global_this = make_startup_global_object()
  let realm_state = RealmState()
  global.realm_state = Some(realm_state)
  let symbols = realm_state.symbols
  let host = make_startup_host(output)
  let interp : Interpreter = {
    host,
    global,
    global_this,
    annex_b: false,
    realm_state,
    module_registry: {},
    module_exports: {},
    module_export_bindings: [],
    generator_objects: {},
    gen_id_counter: { val: 0 },
    symbols,
    stdlib_hooks: make_startup_stdlib_hooks(),
    in_nonarrow_param_default_eval: false,
    param_default_eval_var_conflicts: None,
  }
  global.interpreter_context = Some(interp)
  { interp, global, output, global_this, realm_state }
}

///|
fn setup_startup_global_mirroring(core : StartupInterpreterCore) -> Unit {
  core.global.def_builtin("this", core.global_this)
  core.global.def_builtin("globalThis", core.global_this)
  let global_func_names = [
    "eval", "isFinite", "isNaN", "parseInt", "parseFloat", "encodeURIComponent",
    "decodeURIComponent", "encodeURI", "decodeURI", "escape", "unescape", "String",
    "Number", "Boolean", "Object", "Array", "Function", "RegExp", "Error", "TypeError",
    "RangeError", "ReferenceError", "SyntaxError", "URIError", "EvalError", "Date",
    "Math", "JSON", "Symbol", "Map", "Set", "WeakMap", "WeakSet", "Promise", "Proxy",
    "Reflect", "ArrayBuffer", "DataView", "Int8Array", "Uint8Array", "Uint8ClampedArray",
    "Int16Array", "Uint16Array", "Int32Array", "Uint32Array", "Float32Array", "Float64Array",
  ]
  let builtin_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  match core.global_this {
    Value::Object(data) =>
      for name in global_func_names {
        match core.global.bindings.get(name) {
          Some(binding) => {
            data.bag.properties[name] = binding.value
            data.bag.descriptors[name] = { ..builtin_desc }
          }
          None => ()
        }
      }
    _ => ()
  }
  match core.global_this {
    Value::Object(data) => {
      data.bag.properties["undefined"] = Value::Undefined
      data.bag.properties["NaN"] = Value::Number(0.0 / 0.0)
      data.bag.properties["Infinity"] = Value::Number(1.0 / 0.0)
      let frozen_desc : PropDescriptor = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
        is_accessor: false,
      }
      data.bag.descriptors["undefined"] = { ..frozen_desc }
      data.bag.descriptors["NaN"] = { ..frozen_desc }
      data.bag.descriptors["Infinity"] = { ..frozen_desc }
    }
    _ => ()
  }
}

///|
fn setup_startup_generator_async_constructors(
  core : StartupInterpreterCore,
) -> Unit {
  @runtime.setup_generator_function_constructor(
    core.global,
    core.global_this,
    well_known_symbols=core.realm_state.well_known_symbols,
  )
  @runtime.setup_async_function_constructor(
    core.global,
    well_known_symbols=core.realm_state.well_known_symbols,
  )
  @runtime.setup_async_generator_function_constructor(
    core.global,
    well_known_symbols=core.realm_state.well_known_symbols,
  )
}

///|
fn profiled_startup_new_interpreter() -> Interpreter {
  let core = make_startup_interpreter_core()
  @runtime.with_active_realm_state_unit(core.realm_state, fn() {
    @stdlib.setup_builtins_with_realm_state(
      core.global,
      core.output,
      core.realm_state,
    )
    setup_startup_global_mirroring(core)
    setup_startup_generator_async_constructors(core)
    @stdlib.setup_harness_builtins(core.global, core.output, core.global_this)
  })
  core.interp
}

///|
fn keep_global_binding(global : Environment, name : String) -> Unit {
  guard global.bindings.get(name) is Some(_) else {
    abort(
      "startup subphase precondition failed: missing global binding \{name}",
    )
  }
}

///|
fn keep_global_property(global_this : Value, name : String) -> Unit {
  match global_this {
    Value::Object(data) => {
      guard data.bag.properties.get(name) is Some(_) else {
        abort(
          "startup subphase precondition failed: missing global property \{name}",
        )
      }
    }
    _ =>
      abort("startup subphase precondition failed: global_this is not object")
  }
}

///|
// Mirrors interpreter/stdlib/builtins.mbt's final realm-stamp traversal marker.
// Keep this value and the startup_stamp_realm_* traversal below synchronized
// with production when changing hidden metadata traversal semantics.
const STARTUP_REALM_STAMP_VISITED_SYMBOL_ID = -111

///|
fn startup_clear_realm_stamp_markers(
  visited_objects : Array[@runtime.ObjectData],
) -> Unit {
  for data in visited_objects {
    let _ = data.bag.symbol_properties.remove(
      STARTUP_REALM_STAMP_VISITED_SYMBOL_ID,
    )
  }
}

///|
fn startup_stamp_realm_reachable_value(
  value : Value,
  realm_state : RealmState,
  depth : Int,
  visited_objects : Array[@runtime.ObjectData],
) -> Unit {
  match value {
    Value::Object(_)
    | Value::Array(_)
    | Value::Map(_)
    | Value::Set(_)
    | Value::Promise(_)
    | Value::Proxy(_) =>
      startup_stamp_realm_functions_in_value(
        value, realm_state, depth, visited_objects,
      )
    _ => ()
  }
}

///|
fn startup_stamp_realm_functions_in_bag(
  bag : @runtime.PropertyBag,
  realm_state : RealmState,
  depth : Int,
  visited_objects : Array[@runtime.ObjectData],
) -> Unit {
  bag.properties.each(fn(_key, value) {
    startup_stamp_realm_reachable_value(
      value, realm_state, depth, visited_objects,
    )
  })
  bag.symbol_properties.each(fn(key, value) {
    if key >= 0 {
      startup_stamp_realm_reachable_value(
        value, realm_state, depth, visited_objects,
      )
    }
  })
}

///|
fn startup_stamp_realm_object_seen_at_depth(
  data : @runtime.ObjectData,
  depth : Int,
  visited_objects : Array[@runtime.ObjectData],
) -> Bool {
  let current_depth = depth.to_double()
  match data.bag.symbol_properties.get(STARTUP_REALM_STAMP_VISITED_SYMBOL_ID) {
    Some(Value::Number(seen_depth)) => {
      if seen_depth >= current_depth {
        return true
      }
      data.bag.symbol_properties[STARTUP_REALM_STAMP_VISITED_SYMBOL_ID] = Value::Number(
        current_depth,
      )
      false
    }
    Some(_) => true
    None => {
      data.bag.symbol_properties[STARTUP_REALM_STAMP_VISITED_SYMBOL_ID] = Value::Number(
        current_depth,
      )
      visited_objects.push(data)
      false
    }
  }
}

///|
fn startup_stamp_realm_functions_in_value(
  value : Value,
  realm_state : RealmState,
  depth : Int,
  visited_objects : Array[@runtime.ObjectData],
) -> Unit {
  if depth == 0 {
    return
  }
  let next_depth = depth - 1
  match value {
    Value::Object(data) => {
      if startup_stamp_realm_object_seen_at_depth(data, depth, visited_objects) {
        return
      }
      match data.callable {
        Some(_) =>
          @runtime.stamp_function_realm(value, realm_state=Some(realm_state))
          |> ignore
        None => ()
      }
      startup_stamp_realm_functions_in_bag(
        data.bag,
        realm_state,
        next_depth,
        visited_objects,
      )
    }
    Value::Array(data) =>
      startup_stamp_realm_functions_in_bag(
        data.bag,
        realm_state,
        next_depth,
        visited_objects,
      )
    Value::Map(data) =>
      startup_stamp_realm_functions_in_bag(
        data.bag,
        realm_state,
        next_depth,
        visited_objects,
      )
    Value::Set(data) =>
      startup_stamp_realm_functions_in_bag(
        data.bag,
        realm_state,
        next_depth,
        visited_objects,
      )
    Value::Promise(data) =>
      startup_stamp_realm_functions_in_bag(
        data.bag,
        realm_state,
        next_depth,
        visited_objects,
      )
    Value::Proxy(proxy_data) =>
      match proxy_data.target {
        Some(target) =>
          startup_stamp_realm_functions_in_value(
            target, realm_state, next_depth, visited_objects,
          )
        None => ()
      }
    _ => ()
  }
}

///|
fn startup_stamp_realm_functions_from_env(
  env : Environment,
  realm_state : RealmState,
) -> Unit {
  let visited_objects : Array[@runtime.ObjectData] = []
  env.bindings.each(fn(_name, binding) {
    startup_stamp_realm_functions_in_value(
      binding.value,
      realm_state,
      4,
      visited_objects,
    )
  })
  startup_clear_realm_stamp_markers(visited_objects)
}

///|
fn prepare_startup_core_before_harness() -> StartupInterpreterCore {
  let core = make_startup_interpreter_core()
  @runtime.with_active_realm_state_unit(core.realm_state, fn() {
    @stdlib.setup_builtins_with_realm_state(
      core.global,
      core.output,
      core.realm_state,
    )
    setup_startup_global_mirroring(core)
    setup_startup_generator_async_constructors(core)
  })
  core
}

///|
fn prepare_startup_core_after_setup_builtins() -> StartupInterpreterCore {
  let core = make_startup_interpreter_core()
  @runtime.with_active_realm_state_unit(core.realm_state, fn() {
    @stdlib.setup_builtins_with_realm_state(
      core.global,
      core.output,
      core.realm_state,
    )
  })
  core
}

///|
fn make_startup_harness_print_func(core : StartupInterpreterCore) -> Value {
  let print_func = @runtime.make_native_func(
    name="print",
    realm_state=Some(core.realm_state),
    fn(args) {
      let parts : Array[String] = args.map(fn(a) { a.to_string() })
      core.output.push(parts.join(" "))
      Value::Undefined
    },
  )
  core.global.def_builtin("print", print_func)
  print_func
}

///|
fn make_startup_harness_agent_object(core : StartupInterpreterCore) -> Value {
  let realm_state = core.realm_state
  let agent_props : Map[String, Value] = {}
  agent_props["start"] = @runtime.make_native_func(
    name="start",
    realm_state=Some(realm_state),
    fn(_args) { Value::Undefined },
  )
  agent_props["broadcast"] = @runtime.make_native_func(
    name="broadcast",
    realm_state=Some(realm_state),
    fn(_args) { Value::Undefined },
  )
  agent_props["getReport"] = @runtime.make_native_func(
    name="getReport",
    realm_state=Some(realm_state),
    fn(_args) { Value::Undefined },
  )
  agent_props["sleep"] = @runtime.make_native_func(
    name="sleep",
    realm_state=Some(realm_state),
    fn(_args) { Value::Undefined },
  )
  agent_props["monotonicNow"] = @runtime.make_native_func(
    name="monotonicNow",
    realm_state=Some(realm_state),
    fn(_args) { Value::Undefined },
  )
  Value::Object({
    bag: {
      properties: agent_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
      internal_slots: {},
      host_slots: {},
    },
    prototype: Value::Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn fill_startup_harness_dollar262_props(
  core : StartupInterpreterCore,
  dollar262_props : Map[String, Value],
  agent : Value,
) -> Unit {
  dollar262_props["global"] = core.global_this
  dollar262_props["agent"] = agent
  dollar262_props["gc"] = @runtime.make_native_func(
    name="gc",
    realm_state=Some(core.realm_state),
    fn(_args) { Value::Undefined },
  )
  dollar262_props["createRealm"] = @runtime.make_interp_method_func(
    name="createRealm",
    length=0,
    realm_state=Some(core.realm_state),
    fn(_interp, _this_val, _args) { Value::Undefined },
  )
  dollar262_props["evalScript"] = @runtime.make_interp_method_func(
    name="evalScript",
    length=1,
    realm_state=Some(core.realm_state),
    fn(_interp, _this_val, _args) { Value::Undefined },
  )
  dollar262_props["detachArrayBuffer"] = @runtime.make_native_func(
    name="detachArrayBuffer",
    length=1,
    realm_state=Some(core.realm_state),
    fn(_args) { Value::Undefined },
  )
}

///|
fn bind_startup_harness_dollar262(
  core : StartupInterpreterCore,
  print_func : Value,
  dollar262_props : Map[String, Value],
) -> Value {
  let dollar262 : Value = Value::Object({
    bag: {
      properties: dollar262_props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
      internal_slots: {},
      host_slots: {},
    },
    prototype: Value::Null,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
  core.global.def_builtin("$262", dollar262)
  match core.global_this {
    Value::Object(data) => {
      data.bag.properties["$262"] = dollar262
      data.bag.properties["print"] = print_func
    }
    _ => ()
  }
  dollar262
}

///|
fn setup_startup_harness_without_stamp(core : StartupInterpreterCore) -> Unit {
  let print_func = make_startup_harness_print_func(core)
  let agent = make_startup_harness_agent_object(core)
  let dollar262_props : Map[String, Value] = {}
  fill_startup_harness_dollar262_props(core, dollar262_props, agent)
  bind_startup_harness_dollar262(core, print_func, dollar262_props) |> ignore
}

///|
fn measure_active_unit(realm_state : RealmState, f : () -> Unit) -> Double {
  let mut elapsed = 0.0
  @runtime.with_active_realm_state_unit(realm_state, fn() {
    let t0 = now_ms()
    f()
    let t1 = now_ms()
    elapsed = t1 - t0
  })
  elapsed
}

///|
fn time_full_new_interpreter() -> Double {
  let t0 = now_ms()
  let interp = @interpreter.new_interpreter()
  let t1 = now_ms()
  keep_global_binding(interp.global, "Array")
  t1 - t0
}

///|
fn time_realm_state() -> Double {
  let t0 = now_ms()
  let realm_state = RealmState()
  let t1 = now_ms()
  if realm_state.well_known_symbols.iterator.id < 0 {
    abort("startup subphase precondition failed: invalid iterator symbol")
  }
  t1 - t0
}

///|
fn time_global_environment_and_object() -> Double {
  let t0 = now_ms()
  let global = Environment::new()
  global.is_var_scope = true
  let output : Array[String] = []
  let global_this = make_startup_global_object()
  let t1 = now_ms()
  if !global.is_var_scope || output.length() != 0 {
    abort("startup subphase precondition failed: invalid global setup")
  }
  match global_this {
    Value::Object(data) =>
      if data.class_name != "global" {
        abort("startup subphase precondition failed: invalid global object")
      }
    _ => abort("startup subphase precondition failed: global object missing")
  }
  t1 - t0
}

///|
fn time_stdlib_hooks_module_loader_host() -> Double {
  let output : Array[String] = []
  let t0 = now_ms()
  let hooks = make_startup_stdlib_hooks()
  let host = make_startup_host(output)
  let t1 = now_ms()
  if host.timer_id_counter.val != 1 || host.output.length() != 0 {
    abort("startup subphase precondition failed: invalid host setup")
  }
  let _ = hooks
  t1 - t0
}

///|
fn time_setup_builtins_with_realm_state() -> Double {
  let core = make_startup_interpreter_core()
  let elapsed = measure_active_unit(core.realm_state, fn() {
    @stdlib.setup_builtins_with_realm_state(
      core.global,
      core.output,
      core.realm_state,
    )
  })
  keep_global_binding(core.global, "Array")
  elapsed
}

///|
fn time_global_global_this_mirroring() -> Double {
  let core = make_startup_interpreter_core()
  @runtime.with_active_realm_state_unit(core.realm_state, fn() {
    @stdlib.setup_builtins_with_realm_state(
      core.global,
      core.output,
      core.realm_state,
    )
  })
  let elapsed = measure_active_unit(core.realm_state, fn() {
    setup_startup_global_mirroring(core)
  })
  keep_global_property(core.global_this, "isFinite")
  keep_global_property(core.global_this, "Infinity")
  elapsed
}

///|
fn time_generator_async_constructors() -> Double {
  let core = make_startup_interpreter_core()
  @runtime.with_active_realm_state_unit(core.realm_state, fn() {
    @stdlib.setup_builtins_with_realm_state(
      core.global,
      core.output,
      core.realm_state,
    )
    setup_startup_global_mirroring(core)
  })
  let elapsed = measure_active_unit(core.realm_state, fn() {
    setup_startup_generator_async_constructors(core)
  })
  keep_global_binding(core.global, "GeneratorFunction")
  keep_global_binding(core.global, "[[AsyncFunctionPrototype]]")
  keep_global_binding(core.global, "[[AsyncGeneratorPrototype]]")
  elapsed
}

///|
fn time_test262_harness_setup() -> Double {
  let core = prepare_startup_core_before_harness()
  let elapsed = measure_active_unit(core.realm_state, fn() {
    @stdlib.setup_harness_builtins(core.global, core.output, core.global_this)
  })
  keep_global_binding(core.global, "$262")
  elapsed
}

///|
fn time_test262_harness_without_realm_stamp() -> Double {
  let core = prepare_startup_core_before_harness()
  let elapsed = measure_active_unit(core.realm_state, fn() {
    setup_startup_harness_without_stamp(core)
  })
  keep_global_binding(core.global, "$262")
  keep_global_property(core.global_this, "$262")
  elapsed
}

///|
fn time_test262_harness_print() -> Double {
  let core = prepare_startup_core_before_harness()
  let elapsed = measure_active_unit(core.realm_state, fn() {
    make_startup_harness_print_func(core) |> ignore
  })
  keep_global_binding(core.global, "print")
  elapsed
}

///|
fn time_test262_harness_agent_object() -> Double {
  let core = prepare_startup_core_before_harness()
  let mut agent = Value::Undefined
  let elapsed = measure_active_unit(core.realm_state, fn() {
    agent = make_startup_harness_agent_object(core)
  })
  match agent {
    Value::Object(_) => keep_global_property(agent, "start")
    _ => abort("startup subphase precondition failed: missing agent object")
  }
  elapsed
}

///|
fn time_test262_harness_dollar262_methods() -> Double {
  let core = prepare_startup_core_before_harness()
  let agent = make_startup_harness_agent_object(core)
  let dollar262_props : Map[String, Value] = {}
  let elapsed = measure_active_unit(core.realm_state, fn() {
    fill_startup_harness_dollar262_props(core, dollar262_props, agent)
  })
  guard dollar262_props.get("evalScript") is Some(_) else {
    abort("startup subphase precondition failed: missing evalScript")
  }
  elapsed
}

///|
fn time_test262_harness_dollar262_bind_mirror() -> Double {
  let core = prepare_startup_core_before_harness()
  let print_func = make_startup_harness_print_func(core)
  let agent = make_startup_harness_agent_object(core)
  let dollar262_props : Map[String, Value] = {}
  fill_startup_harness_dollar262_props(core, dollar262_props, agent)
  let elapsed = measure_active_unit(core.realm_state, fn() {
    bind_startup_harness_dollar262(core, print_func, dollar262_props) |> ignore
  })
  keep_global_binding(core.global, "$262")
  keep_global_property(core.global_this, "$262")
  elapsed
}

///|
fn time_test262_harness_realm_stamp() -> Double {
  let core = prepare_startup_core_before_harness()
  setup_startup_harness_without_stamp(core)
  let elapsed = measure_active_unit(core.realm_state, fn() {
    startup_stamp_realm_functions_from_env(core.global, core.realm_state)
  })
  keep_global_binding(core.global, "$262")
  elapsed
}

///|
fn time_realm_stamp_existing_builtins_env() -> Double {
  let core = prepare_startup_core_before_harness()
  let elapsed = measure_active_unit(core.realm_state, fn() {
    startup_stamp_realm_functions_from_env(core.global, core.realm_state)
  })
  keep_global_binding(core.global, "Array")
  elapsed
}

///|
// Diagnostic restamp probes for issue #190. These rows prepare a realm where
// setup_builtins has already run, then re-run the mirrored final realm-stamp
// traversal against selected env roots, including setup_builtins internal roots
// such as [[TypedArrayPrototype]]. They are useful for locating broad root
// families, but they are independent, non-additive microbenchmarks and not an
// exact production attribution of the original final_realm_stamp row.
fn time_realm_stamp_setup_builtins_env() -> Double {
  let core = prepare_startup_core_after_setup_builtins()
  let elapsed = measure_active_unit(core.realm_state, fn() {
    startup_stamp_realm_functions_from_env(core.global, core.realm_state)
  })
  keep_global_binding(core.global, "Array")
  elapsed
}

///|
fn time_realm_stamp_setup_bindings(names : Array[String]) -> Double {
  let core = prepare_startup_core_after_setup_builtins()
  let elapsed = measure_active_unit(core.realm_state, fn() {
    stamp_startup_bindings(core, names)
  })
  for name in names {
    keep_global_binding(core.global, name)
  }
  elapsed
}

///|
fn run_realm_stamp_setup_root(
  name : String,
  binding_names : Array[String],
) -> BenchResult {
  run_measured_subphase(
    "startup/phase/new_interpreter/realm_stamp/setup_root/\{name}",
    { warmup: 5, iterations: 50, group_size: 10 },
    () => time_realm_stamp_setup_bindings(binding_names),
  )
}

///|
fn stamp_startup_value(value : Value, realm_state : RealmState) -> Unit {
  let visited_objects : Array[@runtime.ObjectData] = []
  startup_stamp_realm_functions_in_value(value, realm_state, 4, visited_objects)
  startup_clear_realm_stamp_markers(visited_objects)
}

///|
fn stamp_startup_bindings(
  core : StartupInterpreterCore,
  names : Array[String],
) -> Unit {
  let visited_objects : Array[@runtime.ObjectData] = []
  for name in names {
    startup_stamp_realm_functions_in_value(
      get_startup_binding_value(core, name),
      core.realm_state,
      4,
      visited_objects,
    )
  }
  startup_clear_realm_stamp_markers(visited_objects)
}

///|
fn get_startup_binding_value(
  core : StartupInterpreterCore,
  name : String,
) -> Value {
  match core.global.bindings.get(name) {
    Some(binding) => binding.value
    None => abort("startup subphase precondition failed: missing \{name}")
  }
}

///|
fn clear_dollar262_global_link(dollar262 : Value) -> Unit {
  match dollar262 {
    Value::Object(data) => data.bag.properties["global"] = Value::Undefined
    _ => abort("startup subphase precondition failed: $262 is not object")
  }
}

///|
fn time_realm_stamp_new_harness_bindings_only() -> Double {
  let core = prepare_startup_core_before_harness()
  setup_startup_harness_without_stamp(core)
  let print_func = get_startup_binding_value(core, "print")
  let dollar262 = get_startup_binding_value(core, "$262")
  let elapsed = measure_active_unit(core.realm_state, fn() {
    let visited_objects : Array[@runtime.ObjectData] = []
    startup_stamp_realm_functions_in_value(
      print_func,
      core.realm_state,
      4,
      visited_objects,
    )
    startup_stamp_realm_functions_in_value(
      dollar262,
      core.realm_state,
      4,
      visited_objects,
    )
    startup_clear_realm_stamp_markers(visited_objects)
  })
  keep_global_binding(core.global, "$262")
  elapsed
}

///|
fn time_realm_stamp_global_this_only() -> Double {
  let core = prepare_startup_core_before_harness()
  let elapsed = measure_active_unit(core.realm_state, fn() {
    stamp_startup_value(core.global_this, core.realm_state)
  })
  keep_global_property(core.global_this, "Array")
  elapsed
}

///|
fn time_realm_stamp_print_binding_only() -> Double {
  let core = prepare_startup_core_before_harness()
  setup_startup_harness_without_stamp(core)
  let print_func = get_startup_binding_value(core, "print")
  let elapsed = measure_active_unit(core.realm_state, fn() {
    stamp_startup_value(print_func, core.realm_state)
  })
  keep_global_binding(core.global, "print")
  elapsed
}

///|
fn time_realm_stamp_dollar262_with_global_only() -> Double {
  let core = prepare_startup_core_before_harness()
  setup_startup_harness_without_stamp(core)
  let dollar262 = get_startup_binding_value(core, "$262")
  let elapsed = measure_active_unit(core.realm_state, fn() {
    stamp_startup_value(dollar262, core.realm_state)
  })
  keep_global_binding(core.global, "$262")
  elapsed
}

///|
fn time_realm_stamp_dollar262_without_global_link() -> Double {
  let core = prepare_startup_core_before_harness()
  setup_startup_harness_without_stamp(core)
  let dollar262 = get_startup_binding_value(core, "$262")
  clear_dollar262_global_link(dollar262)
  let elapsed = measure_active_unit(core.realm_state, fn() {
    stamp_startup_value(dollar262, core.realm_state)
  })
  keep_global_binding(core.global, "$262")
  elapsed
}

///|
fn time_realm_stamp_bare_callable_direct() -> Double {
  let core = prepare_startup_core_before_harness()
  let func = @runtime.make_native_func(name="stampProbe", fn(_args) {
    Value::Undefined
  })
  let elapsed = measure_active_unit(core.realm_state, fn() {
    @runtime.stamp_function_realm(func, realm_state=Some(core.realm_state))
    |> ignore
  })
  match func {
    Value::Object(_) => ()
    _ =>
      abort("startup subphase precondition failed: stamp probe is not object")
  }
  elapsed
}

///|
fn profile_startup_builtin_setup_once() -> Array[(String, Double)] {
  let core = make_startup_interpreter_core()
  let rows = @stdlib.profile_setup_builtins_with_realm_state(
    core.global,
    core.output,
    core.realm_state,
  )
  keep_global_binding(core.global, "Array")
  rows
}

///|
fn run_profiled_startup_builtin_setup_phases() -> Array[BenchResult] {
  let config : BenchConfig = { warmup: 5, iterations: 50, group_size: 10 }
  let initial_rows = profile_startup_builtin_setup_once()
  let names : Array[String] = []
  for row in initial_rows {
    names.push(row.0)
  }
  let times_by_name : Map[String, Array[Double]] = {}
  for name in names {
    times_by_name[name] = Array::make(config.iterations, 0.0)
  }
  for _ in 0..<config.warmup {
    for _ in 0..<config.group_size {
      profile_startup_builtin_setup_once() |> ignore
    }
  }
  for i in 0..<config.iterations {
    let totals : Map[String, Double] = {}
    for name in names {
      totals[name] = 0.0
    }
    for _ in 0..<config.group_size {
      for row in profile_startup_builtin_setup_once() {
        let name = row.0
        totals[name] = totals[name] + row.1
      }
    }
    for name in names {
      times_by_name[name][i] = totals[name] / config.group_size.to_double()
    }
  }
  let out : Array[BenchResult] = []
  for name in names {
    let (mean, lo, hi, stddev, cv) = compute_stats(times_by_name[name])
    out.push({
      name: "startup/phase/new_interpreter/setup_builtins/\{name}",
      category: Component,
      stage: Startup,
      warmup: config.warmup,
      iterations: config.iterations,
      group_size: config.group_size,
      mean_ms: mean,
      min_ms: lo,
      max_ms: hi,
      stddev_ms: stddev,
      cv_pct: cv,
      noisy: cv > 15.0,
    })
  }
  out
}

///|
fn run_measured_subphase(
  name : String,
  config : BenchConfig,
  measure : () -> Double,
) -> BenchResult {
  if config.iterations <= 0 {
    abort("run_measured_subphase: iterations must be > 0")
  }
  if config.group_size <= 0 {
    abort("run_measured_subphase: group_size must be > 0")
  }
  if config.warmup < 0 {
    abort("run_measured_subphase: warmup must be >= 0")
  }
  for _ in 0..<config.warmup {
    for _ in 0..<config.group_size {
      let _ = measure()
    }
  }
  let times : Array[Double] = Array::make(config.iterations, 0.0)
  for i in 0..<config.iterations {
    let mut total = 0.0
    for _ in 0..<config.group_size {
      total += measure()
    }
    times[i] = total / config.group_size.to_double()
  }
  let (mean, lo, hi, stddev, cv) = compute_stats(times)
  {
    name,
    category: Component,
    stage: Startup,
    warmup: config.warmup,
    iterations: config.iterations,
    group_size: config.group_size,
    mean_ms: mean,
    min_ms: lo,
    max_ms: hi,
    stddev_ms: stddev,
    cv_pct: cv,
    noisy: cv > 15.0,
  }
}

///|
fn verify_startup_new_interpreter_profiled() -> Unit raise {
  let interp = profiled_startup_new_interpreter()
  let prog = @parser.parse(
    "this.isFinite(1) && globalThis.Infinity === Infinity && typeof $262 === 'object'",
  )
  let got = interp.run(prog.stmts).to_string()
  if got != "true" {
    abort(
      "startup subphase harness produced invalid interpreter\n  expected: true\n  got:      \{got}",
    )
  }
}

///|
fn run_startup_new_interpreter_subphases() -> Array[BenchResult] raise {
  verify_startup_new_interpreter_profiled()
  let out : Array[BenchResult] = [
    run_measured_subphase(
      "startup/phase/new_interpreter/full",
      { warmup: 5, iterations: 50, group_size: 10 },
      time_full_new_interpreter,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/realm_state_symbols",
      { warmup: 5, iterations: 50, group_size: 1000 },
      time_realm_state,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/global_env_object",
      { warmup: 5, iterations: 50, group_size: 1000 },
      time_global_environment_and_object,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/stdlib_hooks_host",
      { warmup: 5, iterations: 50, group_size: 1000 },
      time_stdlib_hooks_module_loader_host,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/setup_builtins_with_realm_state",
      { warmup: 5, iterations: 50, group_size: 10 },
      time_setup_builtins_with_realm_state,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/global_globalthis_mirroring",
      { warmup: 5, iterations: 50, group_size: 10 },
      time_global_global_this_mirroring,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/generator_async_constructors",
      { warmup: 5, iterations: 50, group_size: 10 },
      time_generator_async_constructors,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/test262_harness",
      { warmup: 5, iterations: 50, group_size: 10 },
      time_test262_harness_setup,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/test262_harness/without_realm_stamp",
      { warmup: 5, iterations: 50, group_size: 100 },
      time_test262_harness_without_realm_stamp,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/test262_harness/print",
      { warmup: 5, iterations: 50, group_size: 100 },
      time_test262_harness_print,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/test262_harness/agent_object",
      { warmup: 5, iterations: 50, group_size: 100 },
      time_test262_harness_agent_object,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/test262_harness/dollar262_methods",
      { warmup: 5, iterations: 50, group_size: 100 },
      time_test262_harness_dollar262_methods,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/test262_harness/dollar262_bind_mirror",
      { warmup: 5, iterations: 50, group_size: 100 },
      time_test262_harness_dollar262_bind_mirror,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/test262_harness/realm_stamp",
      { warmup: 5, iterations: 50, group_size: 10 },
      time_test262_harness_realm_stamp,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/realm_stamp/existing_builtins_env",
      { warmup: 5, iterations: 50, group_size: 10 },
      time_realm_stamp_existing_builtins_env,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/realm_stamp/setup_builtins_env",
      { warmup: 5, iterations: 50, group_size: 10 },
      time_realm_stamp_setup_builtins_env,
    ),
    run_realm_stamp_setup_root("object", ["Object", "[[ObjectPrototype]]"]),
    run_realm_stamp_setup_root("function", [
      "Function", "[[FunctionPrototype]]", "[[ThrowTypeError]]",
    ]),
    run_realm_stamp_setup_root("array", ["Array"]),
    run_realm_stamp_setup_root("primitive_constructors", [
      "String", "[[StringPrototype]]", "Number", "[[NumberPrototype]]", "Boolean",
      "[[BooleanPrototype]]", "Symbol", "[[SymbolPrototype]]",
    ]),
    run_realm_stamp_setup_root("error_constructors", [
      "Error", "TypeError", "RangeError", "ReferenceError", "SyntaxError", "URIError",
      "EvalError", "InternalError", "AggregateError",
    ]),
    run_realm_stamp_setup_root("regexp", ["RegExp"]),
    run_realm_stamp_setup_root("map_set", ["Map", "Set"]),
    run_realm_stamp_setup_root("arraybuffer_typedarray_dataview", [
      "ArrayBuffer", "[[ArrayBufferPrototype]]", "DataView", "[[DataViewPrototype]]",
      "[[TypedArrayConstructor]]", "[[TypedArrayPrototype]]", "Int8Array", "[[Int8ArrayConstructor]]",
      "[[Int8ArrayPrototype]]", "Uint8Array", "[[Uint8ArrayConstructor]]", "[[Uint8ArrayPrototype]]",
      "Uint8ClampedArray", "[[Uint8ClampedArrayConstructor]]", "[[Uint8ClampedArrayPrototype]]",
      "Int16Array", "[[Int16ArrayConstructor]]", "[[Int16ArrayPrototype]]", "Uint16Array",
      "[[Uint16ArrayConstructor]]", "[[Uint16ArrayPrototype]]", "Int32Array", "[[Int32ArrayConstructor]]",
      "[[Int32ArrayPrototype]]", "Uint32Array", "[[Uint32ArrayConstructor]]", "[[Uint32ArrayPrototype]]",
      "Float32Array", "[[Float32ArrayConstructor]]", "[[Float32ArrayPrototype]]",
      "Float64Array", "[[Float64ArrayConstructor]]", "[[Float64ArrayPrototype]]",
    ]),
    run_realm_stamp_setup_root("global_functions", [
      "eval", "isNaN", "isFinite", "parseInt", "parseFloat", "encodeURIComponent",
      "decodeURIComponent", "encodeURI", "decodeURI", "escape", "unescape",
    ]),
    run_realm_stamp_setup_root("math_json_reflect", ["Math", "JSON", "Reflect"]),
    run_realm_stamp_setup_root("date_timers_proxy", [
      "Date", "setTimeout", "clearTimeout", "setInterval", "clearInterval", "Proxy",
    ]),
    run_realm_stamp_setup_root("weak_collections", ["WeakMap", "WeakSet"]),
    run_realm_stamp_setup_root("promise_and_microtask", [
      "Promise", "queueMicrotask",
    ]),
    run_measured_subphase(
      "startup/phase/new_interpreter/realm_stamp/new_harness_bindings_only",
      { warmup: 5, iterations: 50, group_size: 100 },
      time_realm_stamp_new_harness_bindings_only,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/realm_stamp/global_this_only",
      { warmup: 5, iterations: 50, group_size: 100 },
      time_realm_stamp_global_this_only,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/realm_stamp/print_binding_only",
      { warmup: 5, iterations: 50, group_size: 100 },
      time_realm_stamp_print_binding_only,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/realm_stamp/dollar262_with_global_only",
      { warmup: 5, iterations: 50, group_size: 100 },
      time_realm_stamp_dollar262_with_global_only,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/realm_stamp/dollar262_without_global_link",
      { warmup: 5, iterations: 50, group_size: 100 },
      time_realm_stamp_dollar262_without_global_link,
    ),
    run_measured_subphase(
      "startup/phase/new_interpreter/realm_stamp/bare_callable_direct",
      { warmup: 5, iterations: 50, group_size: 1000 },
      time_realm_stamp_bare_callable_direct,
    ),
  ]
  for r in run_profiled_startup_builtin_setup_phases() {
    out.push(r)
  }
  out
}
