///|
/// Wiring layer: connects the execution engine (runtime) with the
/// standard library implementations (stdlib). Creates a fully-configured
/// interpreter that has all built-in methods hooked up.

///|
pub using @runtime {type Value, type Interpreter, type Environment}

///|
/// Create a new interpreter wired with the full standard library.
/// This is the main entry point for creating a JavaScript interpreter.
pub fn new_interpreter(
  annex_b? : Bool = false,
  module_loader? : @runtime.ModuleLoader? = None,
) -> @runtime.Interpreter {
  @runtime.Interpreter::new(
    annex_b~,
    module_loader~,
    setup_builtins=fn(env, output, symbols, ab) {
      @stdlib.setup_builtins(env, output, symbols, annex_b=ab)
    },
    setup_harness=fn(env, output, global_this) {
      @stdlib.setup_harness_builtins(env, output, global_this)
    },
    stdlib_hooks=make_stdlib_hooks(),
  )
}

///|
/// Build the StdlibHooks struct that wires stdlib dispatch functions
/// into the runtime property lookup system.
fn make_stdlib_hooks() -> @runtime.StdlibHooks {
  {
    get_string_method: fn(s, prop, annex_b) {
      @stdlib.get_string_method(s, prop, annex_b~)
    },
    get_number_method: fn(obj, prop) { @stdlib.get_number_method(obj, prop) },
    get_array_method_with_interp: fn(data, prop) {
      @stdlib.get_array_method_with_interp(data, prop)
    },
    get_map_method: fn(data, prop) { @stdlib.get_map_method(data, prop) },
    get_set_method: fn(data, prop) { @stdlib.get_set_method(data, prop) },
    get_promise_method: fn(data, prop) {
      @stdlib.get_promise_method(data, prop)
    },
    make_regexp_object: fn(pattern, flags) {
      @stdlib.make_regexp_object(pattern, flags)
    },
    typedarray_get_index: fn(data, idx) {
      @stdlib.typedarray_get_index(data, idx)
    },
    typedarray_set_index: fn(data, idx, val) {
      @stdlib.typedarray_set_index(data, idx, val)
    },
    create_realm: fn() { new_interpreter() },
  }
}
