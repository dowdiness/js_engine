///|
fn callback_free_binding_test_label(
  snapshot : CallbackFreeBindingSnapshot,
) -> String {
  match snapshot {
    CallbackFreeBindingMissing => "missing"
    CallbackFreeBindingPresent(Number(value)) => "number:\{value}"
    CallbackFreeBindingPresent(_) => "present"
    CallbackFreeBindingUnsafe => "unsafe"
  }
}

///|
test "callback-free binding classifier distinguishes local outcomes" {
  let env = Environment::new()
  env.def("present", Number(7.0), LetBinding)
  env.def_tdz("tdz", LetBinding)
  let namespace_cache = make_object(
    Map([]),
    Null,
    None,
    MODULE_NAMESPACE_CACHE_CLASS,
    Map([]),
    false,
  )
  let module_tdz = make_object(Map([]), Null, None, "ModuleTDZ", Map([]), false)
  let export_cell = make_object(
    Map([]),
    Null,
    None,
    "ModuleExportCell",
    Map([]),
    false,
  )
  env.def("namespace_cache", namespace_cache, LetBinding)
  env.def("module_tdz", module_tdz, LetBinding)
  env.def("export_cell", export_cell, LetBinding)
  json_inspect(
    [
      callback_free_binding_test_label(
        callback_free_binding_snapshot(env, "missing"),
      ),
      callback_free_binding_test_label(
        callback_free_binding_snapshot(env, "present"),
      ),
      callback_free_binding_test_label(
        callback_free_binding_snapshot(env, "tdz"),
      ),
      callback_free_binding_test_label(
        callback_free_binding_snapshot(env, "namespace_cache"),
      ),
      callback_free_binding_test_label(
        callback_free_binding_snapshot(env, "module_tdz"),
      ),
      callback_free_binding_test_label(
        callback_free_binding_snapshot(env, "export_cell"),
      ),
    ],
    content=["missing", "number:7", "unsafe", "unsafe", "unsafe", "unsafe"],
  )
}

///|
test "callback-free binding classifier resolves only plain environment chains" {
  let root = Environment::new()
  root.def("callee", Number(11.0), LetBinding)
  let child = Environment::new(parent=Some(root))
  let with_scope = Environment::new(parent=Some(root))
  with_scope.with_object = Some(Undefined)
  json_inspect(
    [
      callback_free_binding_test_label(
        callback_free_binding_in_plain_chain(child, "callee"),
      ),
      callback_free_binding_test_label(
        callback_free_binding_in_plain_chain(child, "missing"),
      ),
      callback_free_binding_test_label(
        callback_free_binding_in_plain_chain(with_scope, "callee"),
      ),
    ],
    content=["number:11", "missing", "unsafe"],
  )
}
