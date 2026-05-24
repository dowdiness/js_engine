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
    setup_builtins=fn(env, output, realm_state, ab) {
      @stdlib.setup_builtins_with_realm_state(
        env,
        output,
        realm_state,
        annex_b=ab,
      )
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
    get_string_method: fn(s, prop, realm_state, annex_b) {
      @stdlib.get_string_method(s, prop, realm_state, annex_b~)
    },
    get_number_method: fn(obj, prop) { @stdlib.get_number_method(obj, prop) },
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
    create_realm: fn() { new_interpreter() },
  }
}
